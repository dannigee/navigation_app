"""Inspector UI: live visualisation of what the app just did to the rig.

The app itself gives an operator almost no feedback -- every response string is
routed into an empty closure (multi_device_control_page.dart:325 and friends),
so a failed preset recall looks identical to a successful one. This page is the
missing half of that loop: it renders switcher and camera state as it changes,
logs every command on the wire, and provides fault injection so the failure
paths can actually be exercised at a desk.
"""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import state as st

PAGE = r"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>V-160HD + PTZ Mock Rig</title>
<style>
  :root {
    --bg: #0c0e12; --panel: #14181f; --line: #232936;
    --text: #dfe4ec; --dim: #7c879b; --live: #ff4d4d; --pvw: #3ddc84;
    --accent: #4da3ff;
  }
  * { box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--text); margin: 0; padding: 18px;
    font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
  }
  h1 { font-size: 15px; letter-spacing: .12em; margin: 0 0 14px; color: var(--dim);
       text-transform: uppercase; font-weight: 600; }
  .grid { display: grid; grid-template-columns: minmax(0,2fr) minmax(280px,1fr);
          gap: 16px; align-items: start; }
  .panel { background: var(--panel); border: 1px solid var(--line);
           border-radius: 8px; padding: 12px; }
  .panel h2 { font-size: 11px; letter-spacing: .1em; text-transform: uppercase;
              color: var(--dim); margin: 0 0 10px; font-weight: 600; }
  canvas { width: 100%; display: block; border-radius: 5px; background: #05070a; }
  .cams { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px,1fr));
          gap: 12px; margin-top: 16px; }
  .cam h3 { font-size: 12px; margin: 0 0 6px; display: flex;
            justify-content: space-between; align-items: baseline; }
  .cam .meta { color: var(--dim); font-size: 11px; }
  .pills { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
  .pill { background: #1c222c; border: 1px solid var(--line); border-radius: 4px;
          padding: 3px 8px; font-size: 11px; color: var(--dim); }
  .pill b { color: var(--text); font-weight: 600; }
  .pill.live { border-color: var(--live); color: #ffb3b3; }
  button { background: #1c222c; color: var(--text); border: 1px solid var(--line);
           padding: 7px 10px; border-radius: 5px; cursor: pointer; font: inherit;
           font-size: 11px; width: 100%; text-align: left; }
  button:hover { border-color: var(--accent); }
  button.danger { border-color: #6b2b2b; color: #ffb3b3; }
  button.danger:hover { border-color: var(--live); }
  button.on { background: #3a1d1d; border-color: var(--live); color: #ffd7d7; }
  .stack { display: flex; flex-direction: column; gap: 7px; }
  label.row { display: flex; justify-content: space-between; align-items: center;
              gap: 8px; font-size: 11px; color: var(--dim); }
  input[type=number] { background: #0b0e13; color: var(--text);
                       border: 1px solid var(--line); border-radius: 4px;
                       padding: 5px; width: 78px; font: inherit; font-size: 11px; }
  #log { height: 260px; overflow-y: auto; background: #05070a;
         border: 1px solid var(--line); border-radius: 5px; padding: 8px;
         font-size: 11px; margin-top: 16px; }
  #log div { white-space: pre-wrap; word-break: break-word; }
  .ch { display: inline-block; width: 52px; color: var(--dim); }
  .ch-RECV { color: var(--accent); } .ch-SENT { color: #8fd694; }
  .ch-NACK, .ch-FAULT, .ch-CHAOS { color: var(--live); }
  .ch-PTZ  { color: #d9b45f; } .ch-CAM { color: #b48ee0; }
  .ch-AUTH, .ch-CONN, .ch-DISC { color: #66c6d6; }
</style>
</head>
<body>
<h1>Roland V-160HD + Panasonic PTZ &mdash; Mock Rig</h1>

<div class="grid">
  <div>
    <div class="panel">
      <h2>Program output</h2>
      <canvas id="pgm" width="960" height="540"></canvas>
      <div class="pills" id="pgmPills"></div>
    </div>
    <div class="cams" id="cams"></div>
  </div>

  <div>
    <div class="panel">
      <h2>Fault injection</h2>
      <div class="stack">
        <button class="danger" onclick="post('/control',{action:'drop'})">
          Drop all TCP sockets &mdash; simulate switcher reboot
        </button>
        <button id="fNack" class="danger"
                onclick="toggle('nackEverything')">NACK every command</button>
        <button id="fSwallow" class="danger"
                onclick="toggle('swallowAcks')">Swallow all responses (ACK timeout)</button>
        <label class="row">Added latency (ms)
          <input type="number" id="lat" value="0" min="0" max="10000" step="100"
                 onchange="post('/control',{action:'fault',latencyMs:+this.value})">
        </label>
      </div>
      <div class="stack" id="camFaults" style="margin-top:10px"></div>
    </div>
    <div class="panel" style="margin-top:16px">
      <h2>Wire log</h2>
      <div id="log"></div>
    </div>
  </div>
</div>

<script>
const SOURCE_COLORS = ['#2f5d8f','#8f3030','#2f8f57','#8f7a2f','#6a2f8f',
                       '#2f8f8f','#8f5a2f','#4a4a52'];

// Landmarks match the seeded preset poses in state.py, so a recall visibly
// frames the thing the preset is named after.
const LANDMARKS = [
  {pan:-0.45, tilt:-0.10, label:'AMBO'},
  {pan: 0.00, tilt:-0.05, label:'ALTAR'},
  {pan: 0.42, tilt:-0.08, label:'CHAIR'},
  {pan:-0.62, tilt: 0.02, label:'CANTOR'},
  {pan: 0.10, tilt: 0.30, label:'TABERNACLE'},
  {pan: 0.70, tilt: 0.15, label:'CHOIR'},
  {pan: 0.00, tilt: 0.22, label:'NAVE'},
  {pan:-0.75, tilt: 0.18, label:'FONT'},
  {pan: 0.05, tilt: 0.45, label:'CRUCIFIX'},
];

function srcColor(src) {
  let h = 0;
  for (const c of src) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return SOURCE_COLORS[h % SOURCE_COLORS.length];
}

async function post(path, body) {
  await fetch(path, {method:'POST', headers:{'Content-Type':'application/json'},
                     body: JSON.stringify(body)});
}
let faults = {};
function toggle(key) { post('/control', {action:'fault', [key]: !faults[key]}); }

const camCanvases = new Map();

function ensureCamPanels(cams) {
  const host = document.getElementById('cams');
  if (host.childElementCount === cams.length) return;
  host.innerHTML = '';
  camCanvases.clear();
  for (const cam of cams) {
    const el = document.createElement('div');
    el.className = 'panel cam';
    el.innerHTML =
      `<h3><span>${cam.name}</span><span class="meta">${cam.ip}</span></h3>` +
      `<canvas width="480" height="270"></canvas>` +
      `<div class="pills" id="cp${cam.index}"></div>`;
    host.appendChild(el);
    camCanvases.set(cam.index, el.querySelector('canvas'));
  }

  const fh = document.getElementById('camFaults');
  fh.innerHTML = '';
  for (const cam of cams) {
    for (const [act, lbl] of [['offline','unreachable'], ['busy','answer ER2 busy']]) {
      const b = document.createElement('button');
      b.className = 'danger';
      b.textContent = `${cam.name}: ${lbl}`;
      b.onclick = () => post('/control', {action:'camera', ip:cam.ip, fault:act});
      fh.appendChild(b);
    }
  }
}

function drawScene(ctx, w, h) {
  ctx.fillStyle = '#0a0d13';
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = '#1b2230';
  ctx.lineWidth = 1;
  for (let i = 1; i < 6; i++) {
    ctx.beginPath();
    ctx.moveTo(w * i / 6, 0); ctx.lineTo(w * i / 6, h);
    ctx.moveTo(0, h * i / 6); ctx.lineTo(w, h * i / 6);
    ctx.stroke();
  }
  for (const lm of LANDMARKS) {
    const x = w / 2 + lm.pan * (w / 2) * 0.92;
    const y = h / 2 + lm.tilt * (h / 2) * 0.92;
    ctx.fillStyle = '#252d3d';
    ctx.fillRect(x - 26, y - 9, 52, 18);
    ctx.fillStyle = '#6c7a92';
    ctx.font = '9px ui-monospace, monospace';
    ctx.textAlign = 'center';
    ctx.fillText(lm.label, x, y + 3);
  }
  ctx.textAlign = 'left';
}

function drawCamera(cam) {
  const canvas = camCanvases.get(cam.index);
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const w = canvas.width, h = canvas.height;

  drawScene(ctx, w, h);

  // Framing rectangle: centre follows pan/tilt, size shrinks as zoom rises.
  const fw = (w * 0.62) / cam.zoom;
  const fh = (h * 0.62) / cam.zoom;
  const cx = w / 2 + cam.pan * (w / 2) * 0.92;
  const cy = h / 2 + cam.tilt * (h / 2) * 0.92;

  ctx.save();
  ctx.strokeStyle = cam.moving ? '#00e5c0' : 'rgba(255,255,255,.75)';
  ctx.lineWidth = cam.moving ? 3 : 2;
  ctx.setLineDash(cam.moving ? [7, 5] : []);
  ctx.strokeRect(cx - fw / 2, cy - fh / 2, fw, fh);
  ctx.setLineDash([]);
  ctx.strokeStyle = 'rgba(255,255,255,.5)';
  ctx.beginPath();
  ctx.moveTo(cx - 9, cy); ctx.lineTo(cx + 9, cy);
  ctx.moveTo(cx, cy - 9); ctx.lineTo(cx, cy + 9);
  ctx.stroke();
  ctx.fillStyle = cam.moving ? '#00e5c0' : 'rgba(255,255,255,.8)';
  ctx.font = 'bold 10px ui-monospace, monospace';
  ctx.fillText(`${cam.zoom.toFixed(1)}x${cam.moving ? '  MOVING' : ''}`,
               cx - fw / 2 + 4, cy - fh / 2 - 5);
  ctx.restore();

  const pills = document.getElementById('cp' + cam.index);
  if (pills) {
    pills.innerHTML =
      `<span class="pill">pan <b>${cam.pan.toFixed(2)}</b></span>` +
      `<span class="pill">tilt <b>${cam.tilt.toFixed(2)}</b></span>` +
      `<span class="pill">presets <b>${cam.presetCount}</b></span>` +
      (cam.power ? '' : '<span class="pill live">POWER OFF</span>');
  }
}

function drawProgram(s) {
  const canvas = document.getElementById('pgm');
  const ctx = canvas.getContext('2d');
  const w = canvas.width, h = canvas.height;

  ctx.fillStyle = srcColor(s.pgm);
  ctx.fillRect(0, 0, w, h);

  if (s.transitionProgress > 0) {
    ctx.save();
    ctx.globalAlpha = s.transitionProgress;
    ctx.fillStyle = srcColor(s.pst);
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }

  ctx.fillStyle = 'rgba(255,255,255,.92)';
  ctx.font = 'bold 30px ui-monospace, monospace';
  ctx.fillText(`PGM  ${s.pgm}`, 28, 50);

  for (const key of Object.keys(s.pinp)) {
    const p = s.pinp[key];
    if (!p.onPgm) continue;
    const pw = w * (p.size / 100), ph = h * (p.size / 100);
    const x = w / 2 - pw / 2 + (p.h / 1000) * (w / 2) * 0.85;
    const y = h / 2 - ph / 2 + (p.v / 1000) * (h / 2) * 0.85;
    ctx.fillStyle = srcColor(p.source);
    ctx.fillRect(x, y, pw, ph);
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 3;
    ctx.strokeRect(x, y, pw, ph);
    ctx.fillStyle = '#fff';
    ctx.font = 'bold 15px ui-monospace, monospace';
    ctx.fillText(`PinP${p.index}  ${p.source}`, x + 9, y + 22);
  }

  if (s.freeze) {
    ctx.fillStyle = 'rgba(200,25,55,.9)';
    ctx.fillRect(w - 168, 22, 146, 38);
    ctx.fillStyle = '#fff';
    ctx.font = 'bold 18px ui-monospace, monospace';
    ctx.fillText('FREEZE', w - 140, 48);
  }

  document.getElementById('pgmPills').innerHTML =
    `<span class="pill live">PGM <b>${s.pgm}</b></span>` +
    `<span class="pill">PST <b>${s.pst}</b></span>` +
    `<span class="pill">macro <b>${s.lastMacro ?? '--'}</b></span>` +
    `<span class="pill">clients <b>${s.clients}</b></span>` +
    `<span class="pill">cmds <b>${s.commandCount}</b></span>` +
    `<span class="pill${s.nackCount ? ' live' : ''}">nacks <b>${s.nackCount}</b></span>`;
}

async function tick() {
  try {
    const s = await (await fetch('/state')).json();
    faults = s.faults;
    ensureCamPanels(s.cameras);
    drawProgram(s);
    s.cameras.forEach(drawCamera);

    document.getElementById('fNack').className =
      'danger' + (faults.nackEverything ? ' on' : '');
    document.getElementById('fSwallow').className =
      'danger' + (faults.swallowAcks ? ' on' : '');

    const log = document.getElementById('log');
    const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 40;
    log.innerHTML = s.logs.map(l =>
      `<div><span class="ch ch-${l.channel}">${l.channel}</span>` +
      `<span style="color:#4a5468">${l.t}</span>  ` +
      `${l.message.replace(/</g,'&lt;')}</div>`).join('');
    if (atBottom) log.scrollTop = log.scrollHeight;
  } catch (e) { /* server restarting; keep polling */ }
  setTimeout(tick, 100);
}
tick();
</script>
</body>
</html>
"""


class Inspector:
    def __init__(self, rig, roland, farm, host="127.0.0.1", port=8080):
        self.rig = rig
        self.roland = roland
        self.farm = farm
        self.host = host
        self.port = port
        self._httpd = None

    def start(self):
        inspector = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):  # noqa: N802
                if self.path.startswith("/state"):
                    inspector._send_json(self, inspector.rig.snapshot())
                else:
                    inspector._send(self, PAGE, "text/html; charset=utf-8")

            def do_POST(self):  # noqa: N802
                length = int(self.headers.get("Content-Length") or 0)
                try:
                    body = json.loads(self.rfile.read(length) or b"{}")
                except json.JSONDecodeError:
                    body = {}
                inspector._control(body)
                inspector._send_json(self, {"ok": True})

            def log_message(self, fmt, *args):
                pass

        self._httpd = ThreadingHTTPServer((self.host, self.port), Handler)
        self._httpd.daemon_threads = True
        threading.Thread(target=self._httpd.serve_forever, daemon=True).start()
        self.rig.log("INIT", f"Inspector at http://{self.host}:{self.port}")

    def stop(self):
        if self._httpd:
            self._httpd.shutdown()
            self._httpd.server_close()

    # -- control plane ---------------------------------------------------

    def _control(self, body):
        action = body.get("action")

        if action == "drop":
            self.roland.drop_all_clients("inspector chaos button")

        elif action == "fault":
            with st.lock:
                if "nackEverything" in body:
                    self.rig.fault_nack_everything = bool(body["nackEverything"])
                if "swallowAcks" in body:
                    self.rig.fault_swallow_acks = bool(body["swallowAcks"])
                if "latencyMs" in body:
                    self.rig.fault_latency_ms = max(0, int(body["latencyMs"]))
                flags = (
                    self.rig.fault_nack_everything,
                    self.rig.fault_swallow_acks,
                    self.rig.fault_latency_ms,
                )
            self.rig.log(
                "FAULT",
                f"nack={flags[0]} swallow={flags[1]} latency={flags[2]}ms",
            )

        elif action == "camera":
            mock = self.farm.by_ip(body.get("ip", ""))
            if mock:
                which = body.get("fault")
                if which == "offline":
                    mock.offline = not mock.offline
                    stateword = "unreachable" if mock.offline else "reachable"
                elif which == "busy":
                    mock.force_busy = not mock.force_busy
                    stateword = "busy (ER2)" if mock.force_busy else "normal"
                else:
                    return
                self.rig.log("FAULT", f"{mock.camera.name} is now {stateword}")

    # -- transport helpers -----------------------------------------------

    def _send(self, handler, text, content_type):
        payload = text.encode("utf-8")
        handler.send_response(200)
        handler.send_header("Content-Type", content_type)
        handler.send_header("Content-Length", str(len(payload)))
        handler.end_headers()
        handler.wfile.write(payload)

    def _send_json(self, handler, obj):
        self._send(handler, json.dumps(obj), "application/json")

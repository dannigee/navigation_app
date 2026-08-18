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
  canvas { width: 100%; display: block; border-radius: 5px; background: #05070a;
           aspect-ratio: 16 / 9; }
  .cams { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px,1fr));
          gap: 12px; margin-top: 16px; }
  .cam h3 { font-size: 12px; margin: 0 0 6px; display: flex;
            justify-content: space-between; align-items: baseline; }
  .cam .meta { color: var(--dim); font-size: 11px; }
  .now { font-size: 13px; margin: 9px 0 0; display: flex; gap: 7px;
         align-items: baseline; }
  .now b { color: #ffd98a; font-weight: 600; }
  .now .idle { color: var(--dim); font-weight: 400; }
  .now .mv { color: #00e5c0; font-size: 11px; }
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
      <canvas id="pgm"></canvas>
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

// Landmarks come from each camera's own stored presets (see CameraState.snapshot),
// so the scene always matches where that camera actually points.

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
      `<canvas></canvas>` +
      `<div class="now" id="cn${cam.index}"></div>` +
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

// Match the backing store to the element's real size so text renders at true
// resolution instead of being downscaled into mush, and draw in CSS pixels.
function fitCanvas(canvas) {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const w = Math.max(1, Math.round(rect.width));
  const h = Math.max(1, Math.round(rect.height));
  if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
    canvas.width = w * dpr;
    canvas.height = h * dpr;
  }
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return {ctx, w, h};
}

// Pan/tilt of +-1.0 maps to this fraction of the half-canvas. Kept below 1 so a
// wide frame at the edge of travel still fits inside the drawing area.
const SCENE_SCALE = 0.66;

const scenePos = (lm, w, h) => ({
  x: w / 2 + lm.pan * (w / 2) * SCENE_SCALE,
  y: h / 2 + lm.tilt * (h / 2) * SCENE_SCALE,
});

function drawScene(ctx, w, h, landmarks, framedNum) {
  ctx.fillStyle = '#0a0d13';
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = '#161c27';
  ctx.lineWidth = 1;
  for (let i = 1; i < 6; i++) {
    ctx.beginPath();
    ctx.moveTo(Math.round(w * i / 6) + .5, 0);
    ctx.lineTo(Math.round(w * i / 6) + .5, h);
    ctx.moveTo(0, Math.round(h * i / 6) + .5);
    ctx.lineTo(w, Math.round(h * i / 6) + .5);
    ctx.stroke();
  }

  const font = Math.max(8, Math.round(w / 40));
  ctx.font = `${font}px ui-monospace, monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  // Dots for every stored preset.
  for (const lm of landmarks) {
    const {x, y} = scenePos(lm, w, h);
    const framed = lm.num === framedNum;
    ctx.fillStyle = framed ? '#ffd98a' : '#4d5a70';
    ctx.beginPath();
    ctx.arc(x, y, framed ? 3.5 : 2, 0, Math.PI * 2);
    ctx.fill();
  }

  // Labels, framed one first so it always wins a collision. Anything that would
  // overlap an already-drawn label is dropped -- these panels are small and a
  // pile of overstruck text reads as noise.
  const drawn = [];
  const ordered = [...landmarks].sort(
    (a, b) => (b.num === framedNum) - (a.num === framedNum));
  for (const lm of ordered) {
    if (!lm.label) continue;  // unnamed preset: dot only
    const text = lm.label.toUpperCase();
    const {x, y} = scenePos(lm, w, h);
    const tw = ctx.measureText(text).width;
    const box = {l: x - tw / 2, r: x + tw / 2,
                 t: y + 2, b: y + font * 2 + 2};
    const clash = drawn.some(d =>
      box.l < d.r && box.r > d.l && box.t < d.b && box.b > d.t);
    if (clash) continue;
    drawn.push(box);
    ctx.fillStyle = lm.num === framedNum ? '#ffd98a' : '#5b6982';
    ctx.fillText(text, x, y + font + 2);
  }
  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';
}

// Which of this camera's presets is closest to the centre of frame, if any is
// inside it. Returns a preset number, or null.
function framedLandmark(cam, w, h) {
  const fw = (w * 0.58) / cam.zoom, fh = (h * 0.58) / cam.zoom;
  const cx = w / 2 + cam.pan * (w / 2) * SCENE_SCALE;
  const cy = h / 2 + cam.tilt * (h / 2) * SCENE_SCALE;
  let best = null, bestD = Infinity;
  for (const lm of cam.landmarks) {
    const {x, y} = scenePos(lm, w, h);
    if (Math.abs(x - cx) > fw / 2 || Math.abs(y - cy) > fh / 2) continue;
    const d = (x - cx) ** 2 + (y - cy) ** 2;
    if (d < bestD) { bestD = d; best = lm.num; }
  }
  return best;
}

function drawCamera(cam) {
  const canvas = camCanvases.get(cam.index);
  if (!canvas) return;
  const {ctx, w, h} = fitCanvas(canvas);

  const framed = framedLandmark(cam, w, h);
  drawScene(ctx, w, h, cam.landmarks, framed);

  // Framing rectangle: centre follows pan/tilt, size shrinks as zoom rises.
  const fw = (w * 0.58) / cam.zoom;
  const fh = (h * 0.58) / cam.zoom;
  const cx = w / 2 + cam.pan * (w / 2) * SCENE_SCALE;
  const cy = h / 2 + cam.tilt * (h / 2) * SCENE_SCALE;

  ctx.save();
  ctx.strokeStyle = cam.moving ? '#00e5c0' : 'rgba(255,255,255,.8)';
  ctx.lineWidth = 2;
  ctx.setLineDash(cam.moving ? [6, 4] : []);
  ctx.strokeRect(cx - fw / 2, cy - fh / 2, fw, fh);
  ctx.setLineDash([]);
  ctx.strokeStyle = 'rgba(255,255,255,.45)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(cx - 7, cy); ctx.lineTo(cx + 7, cy);
  ctx.moveTo(cx, cy - 7); ctx.lineTo(cx, cy + 7);
  ctx.stroke();
  ctx.fillStyle = cam.moving ? '#00e5c0' : 'rgba(255,255,255,.85)';
  ctx.font = `bold ${Math.max(9, Math.round(w / 34))}px ui-monospace, monospace`;
  ctx.fillText(`${cam.zoom.toFixed(1)}x`, cx - fw / 2 + 3, cy - fh / 2 - 4);
  ctx.restore();

  const now = document.getElementById('cn' + cam.index);
  if (now) {
    now.innerHTML = cam.lastPreset === null
      ? '<span class="idle">no preset recalled yet</span>'
      : `<b>${cam.lastPresetName || 'Preset ' + (cam.lastPreset + 1)}</b>` +
        `<span class="idle">preset ${cam.lastPreset + 1}</span>` +
        (cam.moving ? '<span class="mv">MOVING</span>' : '');
  }

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
  const {ctx, w, h} = fitCanvas(document.getElementById('pgm'));

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
                try:
                    body = json.loads(inspector._read_body(self) or b"{}")
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
                # "value" sets the flag explicitly; omitting it toggles, which is
                # what the inspector buttons want. Scripts should pass a value so
                # an aborted run cannot leave a camera stuck offline.
                explicit = body.get("value")
                if which == "offline":
                    mock.offline = (
                        not mock.offline if explicit is None else bool(explicit)
                    )
                    stateword = "unreachable" if mock.offline else "reachable"
                elif which == "busy":
                    mock.force_busy = (
                        not mock.force_busy if explicit is None else bool(explicit)
                    )
                    stateword = "busy (ER2)" if mock.force_busy else "normal"
                else:
                    return
                self.rig.log("FAULT", f"{mock.camera.name} is now {stateword}")

    # -- transport helpers -----------------------------------------------

    @staticmethod
    def _read_body(handler):
        """Read a request body under either framing.

        Dart's HttpClient uses chunked transfer encoding whenever contentLength
        is not set explicitly, so reading Content-Length alone silently yields
        an empty body and every control request becomes a no-op.
        """
        encoding = (handler.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" not in encoding:
            length = int(handler.headers.get("Content-Length") or 0)
            return handler.rfile.read(length) if length else b""

        chunks = bytearray()
        while True:
            size_line = handler.rfile.readline().split(b";", 1)[0].strip()
            if not size_line:
                break
            try:
                size = int(size_line, 16)
            except ValueError:
                break
            if size == 0:
                handler.rfile.readline()  # trailing CRLF after the last chunk
                break
            chunks += handler.rfile.read(size)
            handler.rfile.readline()  # CRLF terminating this chunk
        return bytes(chunks)

    def _send(self, handler, text, content_type):
        payload = text.encode("utf-8")
        handler.send_response(200)
        handler.send_header("Content-Type", content_type)
        handler.send_header("Content-Length", str(len(payload)))
        handler.end_headers()
        handler.wfile.write(payload)

    def _send_json(self, handler, obj):
        self._send(handler, json.dumps(obj), "application/json")

"""Panasonic AW-series PTZ camera emulator (HTTP).

PanasonicService talks plain HTTP GET to the AW CGI endpoints:

    http://{ip}/cgi-bin/aw_ptz?cmd={cmd}&res=1     PTZ + preset commands
    http://{ip}/cgi-bin/aw_cam?cmd={cmd}&res=1     camera settings, preset names
    http://{ip}/live/camdata.html                  bulk state dump

The client percent-encodes only '#' (panasonic_service.dart:379), so anything
else that needs escaping arrives raw. That is a real client bug and this mock
does not paper over it -- a preset name containing a space will produce a
malformed request here exactly as it would against a real camera.

One camera == one HTTP server bound to its own address on port 80, because the
client's ipRegex (panasonic_service.dart:346) accepts a bare dotted quad only
and gives no way to specify a port.
"""

import re
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import state as st

_RECALL = re.compile(r"^#R(\d{2})$")
_SAVE = re.compile(r"^#M(\d{2})$")
_DELETE = re.compile(r"^#C(\d{2})$")
_ENTRIES = re.compile(r"^#PE(\d{2})$")
_SPEED = re.compile(r"^#UPVS(\d{3})$")
_SAVE_NAME = re.compile(r"^OSJ:35:(\d{2}):(.*)$")
_GET_NAME = re.compile(r"^QSJ:35:(\d{2})$")


class CameraMock:
    def __init__(self, rig, camera):
        self.rig = rig
        self.camera = camera
        self.offline = False
        self.force_busy = False
        self._httpd = None

    # -- lifecycle -------------------------------------------------------

    def start(self):
        mock = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):  # noqa: N802 - required by BaseHTTPRequestHandler
                mock._handle_get(self)

            def log_message(self, fmt, *args):
                pass  # silence; we do our own logging

        self._httpd = ThreadingHTTPServer(
            (self.camera.ip, self.camera.port), Handler
        )
        self._httpd.daemon_threads = True
        threading.Thread(target=self._httpd.serve_forever, daemon=True).start()
        self.rig.log(
            "INIT",
            f"Camera '{self.camera.name}' listening on "
            f"{self.camera.ip}:{self.camera.port}",
        )

    def stop(self):
        if self._httpd:
            self._httpd.shutdown()
            self._httpd.server_close()

    # -- request handling ------------------------------------------------

    def _handle_get(self, handler):
        parsed = urllib.parse.urlparse(handler.path)
        name = self.camera.name

        if self.offline:
            self.rig.log("FAULT", f"{name}: refusing request (offline)")
            try:
                handler.connection.close()
            except OSError:
                pass
            return

        if parsed.path == "/live/camdata.html":
            self._respond(handler, self._camdata())
            return

        if parsed.path not in ("/cgi-bin/aw_ptz", "/cgi-bin/aw_cam"):
            self._respond(handler, "ER3:Not Found", status=404)
            return

        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        command = query.get("cmd", [""])[0]
        self.rig.log("CAM", f"{name} <- {command}")

        if self.force_busy:
            self.rig.log("FAULT", f"{name}: answering ER2 (busy)")
            self._respond(handler, "ER2")
            return

        reply = self._execute(command)
        self.rig.log("CAM", f"{name} -> {reply}")
        self._respond(handler, reply)

    def _respond(self, handler, body, status=200):
        payload = body.encode("ascii", "replace")
        handler.send_response(status)
        handler.send_header("Content-Type", "text/plain")
        handler.send_header("Content-Length", str(len(payload)))
        # Real cameras send no CORS headers, so the web build of the app cannot
        # reach them from a browser at all. The mock allows it so the web target
        # is at least testable -- see README, "Deliberate deviations".
        handler.send_header("Access-Control-Allow-Origin", "*")
        handler.end_headers()
        handler.wfile.write(payload)

    def _camdata(self):
        cam = self.camera
        with st.lock:
            return (
                f"OID:AW-UE100\r\n"
                f"OSA:87:{'1' if cam.power else '0'}\r\n"
                f"pan:{cam.pan:.3f}\r\n"
                f"tilt:{cam.tilt:.3f}\r\n"
                f"zoom:{cam.zoom:.3f}\r\n"
            )

    # -- command execution -----------------------------------------------

    def _execute(self, cmd):
        cam = self.camera

        m = _RECALL.match(cmd)
        if m:
            num = int(m.group(1))
            with st.lock:
                target = cam.presets.get(num)
            if target is None:
                return "ER3"  # no such preset stored
            with st.lock:
                cam.last_preset = num
                cam.last_preset_name = cam.preset_names.get(num)
            threading.Thread(
                target=st.animate_camera,
                args=(self.rig, cam, dict(target)),
                kwargs={"duration": max(0.3, 3.0 - cam.preset_speed / 400.0)},
                daemon=True,
            ).start()
            label = cam.preset_names.get(num, f"Preset {num + 1}")
            self.rig.log("PTZ", f"{cam.name} -> preset {num} ({label})")
            return f"s{num:02d}"

        m = _SAVE.match(cmd)
        if m:
            num = int(m.group(1))
            with st.lock:
                cam.presets[num] = {
                    "pan": cam.pan, "tilt": cam.tilt, "zoom": cam.zoom,
                }
            self.rig.log("PTZ", f"{cam.name} stored preset {num}")
            return f"s{num:02d}"

        m = _DELETE.match(cmd)
        if m:
            num = int(m.group(1))
            with st.lock:
                cam.presets.pop(num, None)
                cam.preset_names.pop(num, None)
                if cam.last_preset == num:
                    cam.last_preset = None
                    cam.last_preset_name = None
            self.rig.log("PTZ", f"{cam.name} deleted preset {num}")
            return f"s{num:02d}"

        m = _ENTRIES.match(cmd)
        if m:
            rng = int(m.group(1))
            if rng > 2:
                return "ER1"
            with st.lock:
                bitmap = cam.preset_entries_hex(rng)
            # 'pE' + 2-char data1 + 10-char data2 == the 14 chars the client
            # asserts on (panasonic_service.dart:946).
            return f"pE{rng:02d}{bitmap}"

        m = _SPEED.match(cmd)
        if m:
            with st.lock:
                cam.preset_speed = int(m.group(1))
            return f"uPVS{m.group(1)}"

        m = _SAVE_NAME.match(cmd)
        if m:
            num, label = int(m.group(1)), m.group(2)
            with st.lock:
                cam.preset_names[num] = label[:15]
            return f"OSJ:35:{num:02d}:{label[:15]}"

        m = _GET_NAME.match(cmd)
        if m:
            num = int(m.group(1))
            with st.lock:
                label = cam.preset_names.get(num, "")
            # Client splits on ':' and joins from index 3
            # (panasonic_service.dart:916).
            return f"qsj:35:{num:02d}:{label}"

        if cmd == "#O1":
            with st.lock:
                cam.power = True
            return "p1"
        if cmd == "#O0":
            with st.lock:
                cam.power = False
            return "p0"

        if cmd == "#PTV":
            with st.lock:
                pan = int((cam.pan + 1) / 2 * 0xFFF)
                tilt = int((cam.tilt + 1) / 2 * 0xFFF)
            return f"pTV{pan:04X}{tilt:04X}"

        if cmd == "#GZ":
            with st.lock:
                z = int(0x555 + (cam.zoom - 1.0) / 3.0 * (0xFFF - 0x555))
            return f"gz{z:03X}"

        if cmd == "QID":
            return "OID:AW-UE100"
        if cmd == "QSV":
            return "OSV:V01.14"

        return "ER1"  # unsupported / bad parameter


class CameraFarm:
    """Owns every CameraMock so the runner and web UI can address them by IP."""

    def __init__(self, rig):
        self.rig = rig
        self.mocks = [CameraMock(rig, cam) for cam in rig.cameras]

    def start(self):
        for mock in self.mocks:
            mock.start()

    def stop(self):
        for mock in self.mocks:
            mock.stop()

    def by_ip(self, ip):
        for mock in self.mocks:
            if mock.camera.ip == ip:
                return mock
        return None

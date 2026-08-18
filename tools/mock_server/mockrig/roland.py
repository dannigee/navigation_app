"""Roland V-160HD TCP emulator.

Speaks the wire protocol RolandService actually expects, which is *not* the
same as the ASCII grammar in the vendor docs alone. The extra framing was
reverse-engineered by the app's author and recorded in HANDOFF.md:

  * Telnet on port 8023, with option negotiation on connect.
  * Password authentication (default '0000'), answered with a banner
    containing the word "Welcome".
  * Commands arrive as `CMD:p1,p2;` followed by CR+LF.
  * Responses are prefixed with STX (0x02) and terminated with LF.
  * Acknowledged commands answer `ACK;`; queries answer `CMD:p1,p2;ACK;`.
  * Failures answer `NACK;`.

Reference points in the client:
  roland_service.dart:1644  _buildCommand   -> `CMD:p1,p2;`
  roland_service.dart:1674  telnet handling -> replies IAC WILL to our IAC DO
  roland_service.dart:1722  blind 500ms wait, then writes the password
  roland_service.dart:1752  auth succeeds on the substring 'Welcome'
  roland_service.dart:1875  strips \\r and \\x02 before parsing
  roland_service.dart:1914  ACK detection heuristic
"""

import socket
import threading
import time

from . import state as st

IAC = 0xFF
DO = 0xFD
WILL = 0xFB
DONT = 0xFE
WONT = 0xFC
SB = 0xFA
SE = 0xF0
OPT_ECHO = 0x01

STX = b"\x02"

# Commands that take effect but carry no query payload back.
_SIMPLE_ACK = {
    "CUT", "ATO", "MCREX", "FRZ", "FTB", "DSK", "SPS", "SEQSW", "ACS",
}


def _strip_telnet(raw):
    """Remove IAC sequences from an inbound byte string."""
    out = bytearray()
    i = 0
    while i < len(raw):
        b = raw[i]
        if b != IAC:
            out.append(b)
            i += 1
            continue
        if i + 1 >= len(raw):
            break
        nxt = raw[i + 1]
        if nxt in (DO, DONT, WILL, WONT):
            i += 3  # IAC + verb + option
        elif nxt == SB:
            end = raw.find(bytes([IAC, SE]), i)
            i = len(raw) if end == -1 else end + 2
        elif nxt == IAC:
            out.append(IAC)
            i += 2
        else:
            i += 2
    return bytes(out)


class RolandMock:
    def __init__(self, rig, host="0.0.0.0", port=8023, password="0000"):
        self.rig = rig
        self.host = host
        self.port = port
        self.password = password
        self._server = None
        self._clients = []
        self._clients_lock = threading.Lock()
        self._stop = threading.Event()

    # -- lifecycle -------------------------------------------------------

    def start(self):
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind((self.host, self.port))
        self._server.listen(8)
        threading.Thread(target=self._accept_loop, daemon=True).start()
        self.rig.log("INIT", f"Roland V-160HD listening on {self.host}:{self.port}")

    def stop(self):
        self._stop.set()
        self.drop_all_clients("shutdown")
        if self._server:
            try:
                self._server.close()
            except OSError:
                pass

    def drop_all_clients(self, reason="chaos test"):
        """Yank every open socket without a clean close -- the whole point of
        the chaos button. This is what a switch reboot or a pulled Ethernet
        cable looks like to the app."""
        with self._clients_lock:
            victims = list(self._clients)
            self._clients.clear()
        for conn in victims:
            try:
                # RST rather than FIN, so the client sees an error not a clean
                # stream close.
                conn.setsockopt(
                    socket.SOL_SOCKET, socket.SO_LINGER,
                    b"\x01\x00\x00\x00\x00\x00\x00\x00",
                )
                conn.close()
            except OSError:
                pass
        if victims:
            self.rig.log("CHAOS", f"Dropped {len(victims)} TCP client(s): {reason}")
        return len(victims)

    def _accept_loop(self):
        while not self._stop.is_set():
            try:
                conn, addr = self._server.accept()
            except OSError:
                return
            threading.Thread(
                target=self._client_thread, args=(conn, addr), daemon=True
            ).start()

    # -- per-connection --------------------------------------------------

    def _client_thread(self, conn, addr):
        peer = f"{addr[0]}:{addr[1]}"
        with self._clients_lock:
            self._clients.append(conn)
        with st.lock:
            self.rig.clients += 1
        self.rig.log("CONN", f"Client connected from {peer}")

        authed = False
        buffer = b""
        try:
            # Kick off telnet negotiation. The client watches for IAC DO at
            # byte 0 and answers IAC WILL (roland_service.dart:1674).
            conn.sendall(bytes([IAC, DO, OPT_ECHO]))
            time.sleep(0.05)
            # No colon in this prompt on purpose -- see README, "Deliberate
            # deviations".
            conn.sendall(STX + b"Enter password\n")

            while not self._stop.is_set():
                data = conn.recv(4096)
                if not data:
                    break
                buffer += _strip_telnet(data)

                if not authed:
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        candidate = line.decode("ascii", "ignore").strip()
                        if not candidate:
                            continue
                        if candidate == self.password:
                            authed = True
                            conn.sendall(STX + b"Welcome to V-160HD Mock\n")
                            self.rig.log("AUTH", f"{peer} authenticated")
                        else:
                            conn.sendall(STX + b"Authentication error\n")
                            self.rig.log("AUTH", f"{peer} bad password: {candidate!r}")
                    continue

                # Authenticated: commands are semicolon-terminated.
                while b";" in buffer:
                    raw, buffer = buffer.split(b";", 1)
                    command = raw.decode("ascii", "ignore").strip()
                    if not command:
                        continue
                    self._dispatch(conn, peer, command)
        except OSError as exc:
            self.rig.log("DISC", f"{peer} dropped: {exc}")
        finally:
            with self._clients_lock:
                if conn in self._clients:
                    self._clients.remove(conn)
            with st.lock:
                self.rig.clients = max(0, self.rig.clients - 1)
            try:
                conn.close()
            except OSError:
                pass
            self.rig.log("DISC", f"Client disconnected from {peer}")

    # -- command dispatch ------------------------------------------------

    def _reply(self, conn, payload):
        conn.sendall(STX + payload.encode("ascii") + b"\n")
        self.rig.log("SENT", payload)

    def _dispatch(self, conn, peer, command):
        self.rig.log("RECV", f"{command};")
        with st.lock:
            self.rig.command_count += 1
            latency = self.rig.fault_latency_ms
            nack_all = self.rig.fault_nack_everything
            swallow = self.rig.fault_swallow_acks

        if latency:
            time.sleep(latency / 1000.0)

        if swallow:
            self.rig.log("FAULT", f"Swallowed response for {command};")
            return

        if nack_all:
            with st.lock:
                self.rig.nack_count += 1
            self._reply(conn, "NACK;")
            return

        head, _, tail = command.partition(":")
        params = [p.strip() for p in tail.split(",")] if tail else []

        try:
            reply = self._handle(head.upper(), params)
        except _Nack as exc:
            with st.lock:
                self.rig.nack_count += 1
            self.rig.log("NACK", f"{command}; -> {exc}")
            self._reply(conn, "NACK;")
            return

        if reply is not None:
            self._reply(conn, reply)

    def _handle(self, cmd, params):
        rig = self.rig

        # ---- transitions ----
        if cmd == "CUT":
            with st.lock:
                if params:
                    _require_source(params[0])
                    rig.pst = params[0]
                rig.pgm, rig.pst = rig.pst, rig.pgm
            return "ACK;"

        if cmd == "ATO":
            with st.lock:
                if params and params[0] in st.VIDEO_SOURCES:
                    rig.pst = params[0]
                if len(params) > 1:
                    rig.transition_time = int(params[1])
            threading.Thread(
                target=st.animate_transition, args=(rig,), daemon=True
            ).start()
            return "ACK;"

        # ---- bus assignment ----
        if cmd == "PGM":
            _require(params, 1)
            _require_source(params[0])
            with st.lock:
                rig.pgm = params[0]
            return "ACK;"

        if cmd == "QPGM":
            with st.lock:
                return f"PGM:{rig.pgm};ACK;"

        if cmd == "PST":
            _require(params, 1)
            _require_source(params[0])
            with st.lock:
                rig.pst = params[0]
            return "ACK;"

        if cmd == "QPST":
            with st.lock:
                return f"PST:{rig.pst};ACK;"

        # ---- macros ----
        if cmd == "MCREX":
            _require(params, 1)
            num = _macro_number(params[0])
            with st.lock:
                rig.last_macro = num
                rig.macro_running = num
            self.rig.log("MACRO", f"Executed MACRO{num}")
            threading.Thread(
                target=self._clear_macro, args=(num,), daemon=True
            ).start()
            return "ACK;"

        if cmd == "QMCRST":
            _require(params, 1)
            num = _macro_number(params[0])
            with st.lock:
                running = rig.macro_running == num
            return f"MCRST:MACRO{num},{'RUN' if running else 'STOP'};ACK;"

        # ---- PinP ----
        if cmd in ("PIS", "QPIS", "PIP", "QPIP", "PPS", "QPPS", "PPW", "QPPW"):
            return self._handle_pinp(cmd, params)

        # ---- freeze ----
        if cmd == "FRZ":
            with st.lock:
                if params and params[0] in ("ON", "OFF"):
                    rig.freeze = params[0] == "ON"
                else:
                    rig.freeze = not rig.freeze
            return "ACK;"

        if cmd == "QFRZ":
            with st.lock:
                return f"FRZ:{'ON' if rig.freeze else 'OFF'};ACK;"

        # ---- system ----
        if cmd == "VER":
            return "VER:V-160HD,3.41.312;ACK;"

        if cmd == "ACS":
            return "ACK;"

        if cmd in _SIMPLE_ACK:
            return "ACK;"

        raise _Nack(f"unsupported command {cmd}")

    def _clear_macro(self, num):
        time.sleep(1.0)
        with st.lock:
            if self.rig.macro_running == num:
                self.rig.macro_running = None

    def _handle_pinp(self, cmd, params):
        rig = self.rig
        _require(params, 1)
        idx = _pinp_index(params[0])
        label = f"PinP{idx}"

        with st.lock:
            pinp = rig.pinp[idx]

            if cmd == "PIS":
                _require(params, 2)
                _require_source(params[1])
                pinp.source = params[1]
                return "ACK;"
            if cmd == "QPIS":
                return f"PIS:{label},{pinp.source};ACK;"

            if cmd == "PIP":
                _require(params, 3)
                h, v = int(params[1]), int(params[2])
                if not (-1000 <= h <= 1000 and -1000 <= v <= 1000):
                    raise _Nack("PinP position out of range")
                pinp.h, pinp.v = h, v
                return "ACK;"
            if cmd == "QPIP":
                return f"PIP:{label},{pinp.h},{pinp.v};ACK;"

            if cmd == "PPS":
                pinp.on_pgm = (
                    (params[1] == "ON") if len(params) > 1 else not pinp.on_pgm
                )
                return "ACK;"
            if cmd == "QPPS":
                return f"PPS:{label},{'ON' if pinp.on_pgm else 'OFF'};ACK;"

            if cmd == "PPW":
                pinp.on_pvw = (
                    (params[1] == "ON") if len(params) > 1 else not pinp.on_pvw
                )
                return "ACK;"
            if cmd == "QPPW":
                return f"PPW:{label},{'ON' if pinp.on_pvw else 'OFF'};ACK;"

        raise _Nack(f"unhandled PinP command {cmd}")


class _Nack(Exception):
    """Raised by a handler to answer NACK; instead of ACK;."""


def _require(params, count):
    if len(params) < count:
        raise _Nack(f"expected {count} parameter(s), got {len(params)}")


def _require_source(value):
    if value not in st.VIDEO_SOURCES:
        raise _Nack(f"invalid video source {value}")


def _pinp_index(value):
    if not value.startswith("PinP") or not value[4:].isdigit():
        raise _Nack(f"invalid PinP selector {value}")
    idx = int(value[4:])
    if idx < 1 or idx > 4:
        raise _Nack(f"PinP index out of range: {idx}")
    return idx


def _macro_number(value):
    if not value.startswith("MACRO") or not value[5:].isdigit():
        raise _Nack(f"invalid macro selector {value}")
    num = int(value[5:])
    if num < 1 or num > 100:
        raise _Nack(f"macro out of range: {num}")
    return num

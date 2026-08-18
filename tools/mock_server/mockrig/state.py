"""Device state for the mock rig.

Models one Roland V-160HD switcher and N Panasonic PTZ cameras. Every mutation
goes through the module-level lock, because the TCP server, each camera's HTTP
server, the web inspector and the PTZ animation threads all touch this
concurrently.

Camera pan/tilt/zoom are held in a normalised space (pan/tilt -1.0..1.0, zoom
1.0..4.0) rather than the AW protocol's hex ranges. The app never drives
absolute position -- it only recalls presets -- so the normalised space exists
purely so the inspector can draw a meaningful reticle.
"""

import copy
import threading
import time

# Sources the client will accept, mirroring RolandService.validVideoSources.
VIDEO_SOURCES = (
    [f"HDMI{i}" for i in range(1, 9)]
    + [f"SDI{i}" for i in range(1, 9)]
    + [f"STILL{i}" for i in range(1, 17)]
    + [f"INPUT{i}" for i in range(1, 21)]
)

MAX_LOG_LINES = 200

lock = threading.RLock()


def _preset(pan, tilt, zoom):
    return {"pan": pan, "tilt": tilt, "zoom": zoom}


# Seeded presets, named for where they'd actually point in a sanctuary. Index is
# the 0-based preset number the app uses; the UI displays these 1-based.
SEED_PRESETS = {
    0: ("Wide", _preset(0.0, 0.0, 1.0)),
    1: ("Ambo", _preset(-0.45, -0.10, 2.4)),
    2: ("Altar", _preset(0.0, -0.05, 1.8)),
    3: ("Presider Chair", _preset(0.42, -0.08, 2.2)),
    4: ("Cantor", _preset(-0.62, 0.02, 2.8)),
    5: ("Tabernacle", _preset(0.10, 0.30, 3.0)),
    6: ("Choir", _preset(0.70, 0.15, 1.6)),
    7: ("Congregation", _preset(0.0, 0.22, 1.2)),
    8: ("Font", _preset(-0.75, 0.18, 2.6)),
    9: ("Crucifix", _preset(0.05, 0.45, 3.4)),
}


class CameraState:
    """One Panasonic PTZ camera."""

    def __init__(self, index, name, ip, port):
        self.index = index
        self.name = name
        self.ip = ip
        self.port = port

        self.pan = 0.0
        self.tilt = 0.0
        self.zoom = 1.0
        self.moving = False
        self.power = True

        # preset number (0-99) -> {"pan","tilt","zoom"}
        self.presets = {}
        # preset number (0-99) -> str (max 15 ASCII chars)
        self.preset_names = {}
        self.preset_speed = 250

        for num, (label, pose) in SEED_PRESETS.items():
            self.presets[num] = dict(pose)
            self.preset_names[num] = label

        # Each camera is offset slightly so three cameras recalling the same
        # preset don't render as one reticle stacked on itself.
        skew = (index - 1) * 0.06
        for pose in self.presets.values():
            pose["pan"] = max(-1.0, min(1.0, pose["pan"] + skew))

        self._move_generation = 0

    def snapshot(self):
        return {
            "index": self.index,
            "name": self.name,
            "ip": self.ip,
            "port": self.port,
            "pan": round(self.pan, 4),
            "tilt": round(self.tilt, 4),
            "zoom": round(self.zoom, 4),
            "moving": self.moving,
            "power": self.power,
            "presetCount": len(self.presets),
            "presetNames": dict(self.preset_names),
        }

    def preset_entries_hex(self, rng):
        """40-bit availability bitmap for a range, as 10 hex chars.

        Encoding is derived from the client's `_hexStringToBits`
        (panasonic_service.dart:986): bits are read starting at the *rightmost*
        nibble, least-significant bit first. bits[i] therefore corresponds to
        preset number `rng * 40 + i`.
        """
        nibbles = [0] * 10
        for bit_index in range(40):
            preset_num = rng * 40 + bit_index
            if preset_num not in self.presets:
                continue
            char_index = 9 - (bit_index // 4)
            nibbles[char_index] |= 1 << (bit_index % 4)
        return "".join(f"{n:X}" for n in nibbles)


class PinPState:
    def __init__(self, index):
        self.index = index
        self.source = VIDEO_SOURCES[index + 1]
        self.on_pgm = False
        self.on_pvw = False
        self.h = 0
        self.v = 0
        self.size = 30

    def snapshot(self):
        return {
            "index": self.index,
            "source": self.source,
            "onPgm": self.on_pgm,
            "onPvw": self.on_pvw,
            "h": self.h,
            "v": self.v,
            "size": self.size,
        }


class RigState:
    def __init__(self, cameras):
        self.pgm = "HDMI1"
        self.pst = "HDMI2"
        self.transition_progress = 0.0
        self.transition_time = 10  # tenths of a second
        self.freeze = False
        self.last_macro = None
        self.macro_running = None

        self.pinp = {i: PinPState(i) for i in range(1, 5)}
        self.cameras = cameras

        self.logs = []
        self.clients = 0
        self.command_count = 0
        self.nack_count = 0

        # Set by the operator in the inspector to make the rig misbehave.
        self.fault_nack_everything = False
        self.fault_swallow_acks = False
        self.fault_latency_ms = 0

    # -- logging ---------------------------------------------------------

    def log(self, channel, message):
        line = {
            "t": time.strftime("%H:%M:%S"),
            "channel": channel,
            "message": message,
        }
        with lock:
            self.logs.append(line)
            if len(self.logs) > MAX_LOG_LINES:
                del self.logs[: len(self.logs) - MAX_LOG_LINES]
        print(f"[{line['t']}] [{channel:<5}] {message}", flush=True)

    # -- snapshot for the inspector --------------------------------------

    def snapshot(self):
        with lock:
            return {
                "pgm": self.pgm,
                "pst": self.pst,
                "transitionProgress": round(self.transition_progress, 3),
                "freeze": self.freeze,
                "lastMacro": self.last_macro,
                "macroRunning": self.macro_running,
                "pinp": {str(i): p.snapshot() for i, p in self.pinp.items()},
                "cameras": [c.snapshot() for c in self.cameras],
                "clients": self.clients,
                "commandCount": self.command_count,
                "nackCount": self.nack_count,
                "faults": {
                    "nackEverything": self.fault_nack_everything,
                    "swallowAcks": self.fault_swallow_acks,
                    "latencyMs": self.fault_latency_ms,
                },
                "logs": copy.deepcopy(self.logs[-60:]),
            }


def ease_in_out_quad(t):
    return 2 * t * t if t < 0.5 else 1 - pow(-2 * t + 2, 2) / 2


def animate_camera(rig, camera, target, duration=1.2):
    """Ease a camera to a target pose on a background thread.

    A newer move supersedes an older one via `_move_generation`, so rapid preset
    recalls don't fight each other mid-flight.
    """
    with lock:
        camera._move_generation += 1
        generation = camera._move_generation
        start = (camera.pan, camera.tilt, camera.zoom)
        camera.moving = True

    steps = 36
    for i in range(1, steps + 1):
        time.sleep(duration / steps)
        eased = ease_in_out_quad(i / float(steps))
        with lock:
            if camera._move_generation != generation:
                return  # superseded by a newer recall
            camera.pan = start[0] + (target["pan"] - start[0]) * eased
            camera.tilt = start[1] + (target["tilt"] - start[1]) * eased
            camera.zoom = start[2] + (target["zoom"] - start[2]) * eased

    with lock:
        if camera._move_generation == generation:
            camera.moving = False


def animate_transition(rig, duration=0.5):
    """Run an AUTO transition, then swap PGM and PST."""
    steps = 20
    for i in range(steps + 1):
        with lock:
            rig.transition_progress = i / float(steps)
        time.sleep(duration / steps)
    with lock:
        rig.pgm, rig.pst = rig.pst, rig.pgm
        rig.transition_progress = 0.0

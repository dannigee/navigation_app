#!/usr/bin/env python3
"""Run the mock rig.

    sudo python3 tools/mock_server/run.py            # switcher + 3 cameras
    python3 tools/mock_server/run.py --no-cameras    # switcher only, no root

Root is needed only for the cameras: the app's camera field accepts a bare
dotted quad with no port (panasonic_service.dart:346), so each camera has to
answer on its own loopback alias at port 80, and both aliasing lo0 and binding
a port below 1024 are privileged operations. Aliases created here are removed
again on exit.

Then point the app at the rig via Settings -> Connections:

    Roland   127.0.0.1
    Camera 1 127.0.0.2
    Camera 2 127.0.0.3
    Camera 3 127.0.0.4

Leave the app in Live mode. Demo mode bypasses the network entirely and will
not touch this server.
"""

import argparse
import os
import signal
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mockrig import netsetup, panasonic, roland, state as st, web  # noqa: E402

DEFAULT_CAMERA_IPS = ["127.0.0.2", "127.0.0.3", "127.0.0.4"]
DEFAULT_CAMERA_NAMES = ["Cam 1 House", "Cam 2 Sanctuary", "Cam 3 Choir"]


def build_parser():
    p = argparse.ArgumentParser(
        description="Roland V-160HD + Panasonic PTZ mock rig",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--roland-host", default="0.0.0.0")
    p.add_argument("--roland-port", type=int, default=8023)
    p.add_argument("--password", default="0000",
                   help="telnet password the app must send (default: 0000)")
    p.add_argument("--camera-ips", default=",".join(DEFAULT_CAMERA_IPS),
                   help="comma-separated addresses for the mock cameras")
    p.add_argument("--camera-port", type=int, default=80,
                   help="port each camera listens on (the app always uses 80)")
    p.add_argument("--no-cameras", action="store_true",
                   help="switcher and inspector only; runs without root")
    p.add_argument("--inspector-host", default="127.0.0.1")
    p.add_argument("--inspector-port", type=int, default=8080)
    return p


def main():
    args = build_parser().parse_args()
    camera_ips = [ip.strip() for ip in args.camera_ips.split(",") if ip.strip()]

    if args.no_cameras:
        camera_ips = []
    elif args.camera_port < 1024 and os.geteuid() != 0:
        sys.exit(
            "Cameras need root: binding port "
            f"{args.camera_port} and adding loopback aliases are privileged.\n"
            "  Run:  sudo python3 " + " ".join(sys.argv) + "\n"
            "  Or:   python3 " + sys.argv[0] + " --no-cameras   "
            "(switcher only, no root)"
        )

    cameras = [
        st.CameraState(
            index=i + 1,
            name=DEFAULT_CAMERA_NAMES[i] if i < len(DEFAULT_CAMERA_NAMES)
            else f"Cam {i + 1}",
            ip=ip,
            port=args.camera_port,
        )
        for i, ip in enumerate(camera_ips)
    ]

    rig = st.RigState(cameras)
    aliases = netsetup.AliasManager(rig.log)

    try:
        if camera_ips:
            aliases.ensure(camera_ips)
    except PermissionError as exc:
        sys.exit(f"{exc}\nRe-run with sudo, or use --no-cameras.")

    roland_mock = roland.RolandMock(
        rig, host=args.roland_host, port=args.roland_port,
        password=args.password,
    )
    farm = panasonic.CameraFarm(rig)
    inspector = web.Inspector(
        rig, roland_mock, farm,
        host=args.inspector_host, port=args.inspector_port,
    )

    roland_mock.start()
    farm.start()
    inspector.start()

    print()
    print("  Point the app at:")
    print(f"    Roland      127.0.0.1        (port {args.roland_port}, "
          f"password {args.password})")
    for cam in cameras:
        print(f"    {cam.name:<16}{cam.ip}")
    if not cameras:
        print("    (cameras disabled -- run with sudo to enable them)")
    print()
    print(f"  Inspector:  http://{args.inspector_host}:{args.inspector_port}")
    print("  Keep the app in LIVE mode; Demo mode never touches the network.")
    print("  Ctrl-C to stop and remove any loopback aliases.")
    print()

    stopping = threading.Event()

    def shutdown(signum, frame):
        if stopping.is_set():
            return
        stopping.set()
        print()
        rig.log("EXIT", "Shutting down")
        inspector.stop()
        farm.stop()
        roland_mock.stop()
        aliases.teardown()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    try:
        while not stopping.is_set():
            stopping.wait(0.5)
    finally:
        if not stopping.is_set():
            shutdown(None, None)


if __name__ == "__main__":
    main()

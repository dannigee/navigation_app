#!/bin/bash
# Start the mock rig and the app together, wired to point at each other.
#
#   ./tools/mock_server/dev.sh                   switcher only, flutter run -d macos
#   ./tools/mock_server/dev.sh --cameras         switcher + 3 cameras (needs sudo)
#   ./tools/mock_server/dev.sh --device chrome   any other flutter device
#
# Ctrl-C, or quitting the app, stops both: the rig has its own SIGINT handler
# that tears down any loopback aliases it created, so cleanup here only has to
# make sure that signal actually reaches it.
#
# Web is a dead end for the switcher: RolandService uses dart:io sockets,
# which don't exist in a browser (see tools/mock_server/README.md). Web is
# fine for camera-only testing, or just eyeballing the UI.

set -euo pipefail
set -m  # background jobs get their own process group, so cleanup can signal
        # the whole group instead of just the direct child (sudo, when used).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

DEVICE="macos"
CAMERAS=0
ROLAND_PORT=8023

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cameras) CAMERAS=1; shift ;;
    --no-cameras) CAMERAS=0; shift ;;
    --device) DEVICE="${2:?usage: --device <flutter-device>}"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

rig_cmd=(python3 tools/mock_server/run.py)
if [[ "$CAMERAS" == 1 ]]; then
  # Authenticate synchronously, in the foreground, before anything is
  # backgrounded -- a sudo prompt on a backgrounded job can go unseen and
  # hang the script. -n on the actual run makes a since-expired ticket fail
  # fast instead of prompting a second time from the background.
  echo "Cameras need root; authenticating now..."
  sudo -v || { echo "sudo authentication failed" >&2; exit 1; }
  rig_cmd=(sudo -n "${rig_cmd[@]}")
else
  rig_cmd+=(--no-cameras)
fi

echo "Starting mock rig: ${rig_cmd[*]}"
"${rig_cmd[@]}" &
RIG_PID=$!

cleanup() {
  if kill -0 "$RIG_PID" 2>/dev/null; then
    echo
    echo "Stopping mock rig (pid $RIG_PID)..."
    # Signal the whole process group, not just $RIG_PID: with --cameras that
    # pid is sudo, and sudo does not reliably forward signals to the python
    # child it launched, which would leave loopback aliases behind.
    kill -INT -- "-$RIG_PID" 2>/dev/null || true
    wait "$RIG_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Waiting for the switcher on 127.0.0.1:$ROLAND_PORT..."
until (exec 3<>"/dev/tcp/127.0.0.1/$ROLAND_PORT") 2>/dev/null; do
  if ! kill -0 "$RIG_PID" 2>/dev/null; then
    echo "Mock rig exited before it came up -- see output above." >&2
    exit 1
  fi
  sleep 0.1
done
exec 3>&- 3<&- 2>/dev/null || true

echo "Rig is up. Launching the app (flutter run -d $DEVICE)..."
echo "  Settings -> Connections -> Roland: 127.0.0.1  (Live mode, not Demo)"
echo

flutter run -d "$DEVICE"

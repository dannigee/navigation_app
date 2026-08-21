#!/bin/bash
# Drive the built macOS app deterministically, for testing against the mock rig.
#
#   ./drive_macos_app.sh shot <name>       activate, pin the window, screenshot
#   ./drive_macos_app.sh click <wx> <wy>   activate, click at a window-relative point
#   ./drive_macos_app.sh type <text>       activate, type text
#   ./drive_macos_app.sh key <key>         activate, press a key (see cliclick kp)
#   ./drive_macos_app.sh bounds            print the current window frame
#
# The window is pinned to a fixed frame before every action, because otherwise
# coordinates go stale the moment anything moves the window -- and because the
# terminal takes focus back after each command, so the app has to be re-activated
# every time or the click lands on whatever is in front.
#
# Requires:
#   cliclick        brew install cliclick
#   Accessibility + Screen Recording permission for the controlling terminal
#     (System Settings -> Privacy & Security)
#
# Screenshots are written at the display's backing scale, so on a Retina Mac a
# 1200x820 window produces a 2400x1640 image: halve image coordinates to get the
# window coordinates this script expects.

set -euo pipefail

APP_NAME="${APP_NAME:-Production Control}"
WIN_X="${WIN_X:-60}"
WIN_Y="${WIN_Y:-80}"
WIN_W="${WIN_W:-1200}"
WIN_H="${WIN_H:-820}"
SHOT_DIR="${SHOT_DIR:-$PWD}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

pin() {
  osascript >/dev/null 2>&1 <<OSA
tell application "$APP_NAME" to activate
delay 0.6
tell application "System Events" to tell process "$APP_NAME"
  set position of window 1 to {$WIN_X, $WIN_Y}
  set size of window 1 to {$WIN_W, $WIN_H}
end tell
OSA
  sleep 0.4
}

case "${1:-}" in
  shot)
    need cliclick; pin
    screencapture -x -o -R "$WIN_X,$WIN_Y,$WIN_W,$WIN_H" "$SHOT_DIR/${2:?usage: shot <name>}.png"
    echo "wrote $SHOT_DIR/$2.png"
    ;;
  click)
    need cliclick; pin
    cliclick "c:$((WIN_X + ${2:?usage: click <x> <y>})),$((WIN_Y + ${3:?usage: click <x> <y>}))"
    echo "clicked window($2,$3)"
    ;;
  type)
    need cliclick; pin
    cliclick "t:${2:?usage: type <text>}"
    ;;
  key)
    need cliclick; pin
    cliclick "kp:${2:?usage: key <keyname>}"
    ;;
  bounds)
    osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to get {position, size} of window 1"
    ;;
  *)
    sed -n '2,26p' "$0"
    exit 1
    ;;
esac

# Mock rig — Roland V-160HD + Panasonic AW PTZ

A hardware-free stand-in for the AV booth. Runs a fake V-160HD switcher and
three fake AW-series PTZ cameras that the **unmodified app** can connect to and
drive, plus a browser inspector that shows what each command actually did.

The app has no feedback loop of its own — every device response is routed into
an empty closure (`multi_device_control_page.dart:325`, `:540`, `:548`, `:555`),
so a failed preset recall is visually identical to a successful one. This tool
is the missing half: it shows the state the app is blind to, and it can inject
the failures the app currently cannot survive.

## Running it

```bash
sudo python3 tools/mock_server/run.py          # switcher + 3 cameras
python3 tools/mock_server/run.py --no-cameras  # switcher only, no root
```

Then in the app, **Settings → Connections**:

| Device   | Address     |
|----------|-------------|
| Roland   | `127.0.0.1` |
| Camera 1 | `127.0.0.2` |
| Camera 2 | `127.0.0.3` |
| Camera 3 | `127.0.0.4` |

Inspector: <http://127.0.0.1:8080>

Leave the app in **Live** mode. Demo mode swaps in `MockRolandService` /
`MockPanasonicService` and never touches the network, so it will bypass this
server entirely.

No dependencies beyond the Python 3 standard library.

### Why it needs root

Only for the cameras. `PanasonicService`'s `ipRegex`
(`panasonic_service.dart:346`) accepts a bare dotted quad and offers no way to
specify a port, so each mock camera has to answer on its own address at port
80. Both aliasing `lo0` and binding a port below 1024 are privileged.

`127.0.0.2-4` are used rather than the real `10.0.1.10-12` on purpose: aliasing
the church's actual camera addresses onto this Mac would shadow the real
cameras if the alias were ever left in place before a service.

Aliases created at startup are removed on Ctrl-C, and also if startup fails
part-way (a port clash, say). An alias that already existed when the rig started
is adopted for the run but deliberately left in place on exit, since we did not
create it — the rig says so at startup when this happens.

If the process is killed with SIGKILL no handler runs, so remove them by hand:

```bash
sudo ifconfig lo0 -alias 127.0.0.2
sudo ifconfig lo0 -alias 127.0.0.3
sudo ifconfig lo0 -alias 127.0.0.4
```

## Verifying it

`verify.dart` drives the rig using the app's **real** `RolandService` and
`PanasonicService` classes, so a pass means the app will work against it — it
is not the mock confirming its own assumptions.

```bash
sudo python3 tools/mock_server/run.py        # terminal 1
dart run tools/mock_server/verify.dart       # terminal 2
```

Last run: **34 passed, 0 failed** (Flutter 3.47.0 / Dart 3.13.0, macOS).

## Proving the bugs

`chaos_demo.dart` injects each fault into the rig and lets the real client cope,
so the failure modes below are observed rather than argued:

```bash
dart run tools/mock_server/chaos_demo.dart
```

Results as of this commit:

**1. The ACK desync is permanent.** With responses swallowed, `CUT` fails after
20.6 s (4 attempts × 5 s). With the fault switched back **off** and the rig fully
healthy, the next `CUT` *still* times out after 20.6 s. The queue never recovers
— every subsequent command is answering someone else's orphaned completer.

**2. A dropped socket is unobservable.** After the drop, commands throw
`ConnectionException: Not connected` instantly and nothing reconnects. There is
no public connection state on `RolandService` at all, so
`multi_device_control_page` keeps `_rolandConnected` true and the UI still reads
**Live**.

**3. The camera deadlock is worse than a hang.** One unreachable-camera timeout
wedges `_isProcessing` permanently. Afterwards, with the camera reachable and
answering, `recallPreset` never completes — no timeout, no error. The rethrow
also escapes as an *uncatchable* async error, because `_processQueue()` is
called fire-and-forget at `panasonic_service.dart:91`; no caller can catch it,
and in the app it reaches the Flutter zone handler and is logged, never shown.

## Fault control API

The inspector buttons toggle; scripts should set explicitly so an aborted run
cannot leave a camera stuck offline.

```bash
curl -X POST -H 'Content-Type: application/json' \
  -d '{"action":"fault","swallowAcks":true,"latencyMs":500}' \
  http://127.0.0.1:8080/control

curl -X POST -H 'Content-Type: application/json' \
  -d '{"action":"camera","ip":"127.0.0.2","fault":"offline","value":true}' \
  http://127.0.0.1:8080/control

curl -X POST -H 'Content-Type: application/json' \
  -d '{"action":"drop"}' http://127.0.0.1:8080/control
```

Omitting `value` toggles. `action: "drop"` logs even when nothing was connected,
so the button is never silently a no-op.

## What it emulates

**Roland**, on TCP 8023 — telnet option negotiation, password auth, `CMD:p1,p2;`
grammar, `\x02`-prefixed responses, `ACK;` / `NACK;`:

`CUT` `ATO` `PGM` `QPGM` `PST` `QPST` `MCREX` `QMCRST` `PIS` `QPIS` `PIP` `QPIP`
`PPS` `QPPS` `PPW` `QPPW` `FRZ` `QFRZ` `VER` `ACS`

That covers everything reachable from the app's UI. Anything else answers
`NACK;`, which is itself useful — it tells you the app sent something the mock
doesn't model yet.

**Cameras**, HTTP on port 80 — `cgi-bin/aw_ptz`, `cgi-bin/aw_cam`,
`live/camdata.html`:

`#R` recall · `#M` save · `#C` delete · `#PE` preset bitmap · `#UPVS` speed ·
`OSJ:35:` / `QSJ:35:` preset names · `#O1`/`#O0` power · `#PTV` · `#GZ` · `QID` ·
`QSV`

Each camera boots with ten seeded presets named for where they'd point in a
sanctuary — Wide, Ambo, Altar, Presider Chair, Cantor, Tabernacle, Choir,
Congregation, Font, Crucifix — so preset recalls are legible in the inspector
instead of being anonymous numbers. Each camera is skewed slightly so three
cameras recalling the same preset don't render as one reticle on top of itself.

## The inspector

- **Program output** — PGM as a colour field, PST cross-fading during an AUTO
  transition, PinP boxes at their real position and size, FREEZE overlay.
- **Per-camera viewfinders** — a stylised sanctuary with the camera's framing
  rectangle over it. Position follows pan/tilt, size shrinks as zoom rises, and
  the border goes dashed cyan while a move is in flight. Recall "Ambo" and you
  watch the frame settle onto the ambo.
- **Wire log** — every command in and every response out, colour-coded.
- **Fault injection** — see below.

## Fault injection

These exist because of four defects confirmed in the current code. Each button
reproduces one on demand:

| Control | Reproduces |
|---|---|
| **Drop all TCP sockets** | `RolandService` flips its private `_isConnected` on socket error (`roland_service.dart:1707`) but never notifies the UI, and auto-reconnect is off by default and would fail anyway because `disconnect()` permanently closes `_responseController` (`:1783`). Expect the app to keep showing **Live** while every command fails silently. |
| **Swallow all responses** | ACK-wait uses `.timeout()` without completing or removing the pending completer (`roland_service.dart:1839`). Orphans accumulate at the head of `_ackCompleters`, and because ACK matching is head-of-queue with no command correlation (`:1923`), the queue desyncs permanently after one timeout. |
| **NACK every command** | Error path through `_processCompleteResponse`'s NACK branch (`:1937`). |
| **Camera: unreachable** | `CommandQueue._processQueue` sets `_isProcessing = true`, and the queued wrapper rethrows (`panasonic_service.dart:88`), so the flag is never cleared (`:113`). Every later command on that camera enqueues a completer that is never completed — no timeout, no error, just a permanent hang. |
| **Camera: ER2 busy** | Busy-retry path at `panasonic_service.dart:461`. |
| **Added latency** | Slow-network behaviour against the 5 s ACK timeout and 5 s HTTP timeout. |

The camera-unreachable case is not theoretical — it fired during the very first
`verify.dart` run against a rig with cameras disabled, and killed the harness
with an unhandled `CommandQueue._processQueue` exception.

## Deliberate deviations from real hardware

Documented because they matter if anyone diffs this against a real V-160HD:

1. **The password prompt contains no colon.** Real firmware likely sends
   `Enter password:`. The client's ACK heuristic (`roland_service.dart:1914`)
   treats *any* line containing `:` as an ACK, so a colon in the banner would
   consume a pending ACK. It is harmless at auth time only because
   `_ackCompleters` happens to be empty. Worth fixing in the client rather than
   relying on that.
2. **Camera pan/tilt/zoom are normalised** (`-1.0..1.0`, zoom `1.0..4.0`)
   instead of the AW hex ranges. The app only recalls presets, never drives
   absolute position, so the normalised space exists purely for the inspector.
3. **The mock is built from the client's beliefs about the protocol.** Where
   the app's reverse-engineering is wrong, this will faithfully reproduce the
   same wrong assumption and report success. It de-risks the disconnect,
   deadlock and desync classes of bug; it does not replace verification against
   real hardware.
4. **Preset names containing spaces will fail** — `_encodeCommand`
   (`panasonic_service.dart:379`) percent-encodes only `#`, so a name with a
   space produces a malformed request line. That is a real client bug and is
   deliberately not papered over here.
5. **The cameras send `Access-Control-Allow-Origin: *`.** Real AW cameras send
   no CORS headers at all, so a browser build of the app could not reach them.
   The mock allows it so the web target is testable. Do not read a working web
   build against this rig as evidence that the web build would work against
   real cameras — it would not.

## Running the app against the rig

**macOS** (`flutter run -d macos`) is the real deployment and exercises
everything.

**Web** (`flutter build web` + any static server) is useful for a quick look at
the UI, with one hard limit: **Roland control cannot work in a browser at all.**
`RolandService` uses `dart:io` sockets for raw TCP, which browsers do not
provide. It compiles, and it fails silently — verified: pressing a macro button
puts nothing on the wire, logs nothing to the console, and shows nothing in the
UI.

Worse, the app still reads **Live** and enters the full tab shell, because
`isConnected` (`multi_device_control_page.dart:389`) is true if the Roland *or
any camera* is connected. One camera connecting is enough to mask a completely
absent switcher. The Panel tab then renders 25 enabled macro buttons that do
nothing.

Point the app at `127.0.0.1` and `127.0.0.2-4` under Settings → Connections.
Cameras work correctly on web: preset availability, recall, names and the
`#PE` bitmap all round-trip.

## Layout

```
tools/mock_server/
├── run.py              CLI entry point, lifecycle, signal handling
├── verify.dart         checks the rig using the app's real service classes
├── chaos_demo.dart     reproduces the three failure modes against that client
└── mockrig/
    ├── state.py        rig + camera state, PTZ easing, preset bitmaps
    ├── roland.py       TCP: telnet, auth, command grammar, STX/ACK framing
    ├── panasonic.py    HTTP: aw_ptz / aw_cam / camdata
    ├── web.py          inspector UI and control plane
    └── netsetup.py     lo0 alias create/teardown
```

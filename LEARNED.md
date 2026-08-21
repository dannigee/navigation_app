# Learned

Verified facts about this repo: stack, run commands, architecture, and the
behaviours that have already burned someone. Read this first.

**Admission bar:** something had to be *verified* — a command that ran, a file
read, a failure observed. Not a plan, not a preference, not a rule invented
after one incident. **Cap: 300 lines.** Over it, the least load-bearing entry
comes out the same sitting.

## Where the facts live

| Doc | Holds |
|---|---|
| `HANDOFF.md` | The network setup and the Roland telnet protocol as verified in Aug 2026. Still the record for wiring, IPs, and the ACK/STX findings. Not maintained here — this file does not duplicate it. |
| `docs/learned/verification.md` | The test policy. Which surfaces get tests, which get screenshots, which get neither. |
| `docs/superpowers/runbooks/lane-process.md` | How work gets done: tiers, worktrees, the merge gate. |
| `docs/superpowers/specs/` | Dated design docs. Receipts, not owner docs — they never override live code. |
| `.github/copilot-instructions.md` | Maintained for the collaborator's tooling. Shared file; leave it alone unless Daniel says otherwise. |

## Stack

- **Flutter 3.47.0 stable**, Dart SDK `>=3.0.0 <4.0.0`. Verified 2026-08-21.
- Runtime deps are deliberately thin: `http`, `shared_preferences`, `logging`,
  `cupertino_icons`. Dev: `flutter_test`, `integration_test`, `mocktail`,
  `flutter_lints`, `flutter_launcher_icons`.
- **macOS and iOS build with Swift Package Manager. CocoaPods was dropped**
  (`5608d36`) after the Flutter 3.47 migration. Don't re-add a Podfile.
- macOS needs the `network.client` entitlement in both `DebugProfile` and
  `Release.entitlements` or every outgoing socket fails with
  "Operation not permitted".
- `analysis_options.yaml` excludes `build/` and the platform dirs (`4cb37d9`).

## Commands

```bash
flutter run -d macos                  # the real app
flutter analyze                       # must be clean
flutter test                          # full suite, fast
flutter test test/<name>_test.dart    # the one file you're iterating on
flutter test integration_test/        # layout + device-control flow
```

## The mock rig — test without hardware

`tools/mock_server/` runs a fake V-160HD and three fake AW-series PTZ cameras
that the **unmodified app** connects to and drives, plus a browser inspector
showing what each command actually did.

```bash
sudo python3 tools/mock_server/run.py          # switcher + 3 cameras
python3 tools/mock_server/run.py --no-cameras  # switcher only, no root
```

Then **Settings → Connections**: Roland `127.0.0.1`, cameras `127.0.0.2`,
`.3`, `.4`. Inspector at <http://127.0.0.1:8080>. Standard library only.

- **Leave the app in Live mode.** Demo mode swaps in `MockRolandService` /
  `MockPanasonicService` and never touches the network, so it bypasses the rig
  entirely and every test against it is vacuous.
- **Root is only for the cameras.** `PanasonicService.ipRegex`
  (`panasonic_service.dart:346`) takes a bare dotted quad with no port, so each
  mock camera must answer on its own address at port 80 — which needs an `lo0`
  alias and a privileged port.
- `127.0.0.2-4` are used instead of the real `10.0.1.10-12` on purpose: aliasing
  the church's actual camera addresses onto this Mac would shadow the real
  cameras if an alias were ever left in place before a service.

## Screenshots of the real app

`tools/mock_server/drive_macos_app.sh` drives the built macOS app
deterministically — `shot`, `click`, `type`, `key`, `bounds`. It pins the window
to a fixed frame before every action, because the terminal steals focus back
after each command and stale coordinates put the click on whatever is in front.

Needs `cliclick` (`brew install cliclick`) plus Accessibility and Screen
Recording permission for the controlling terminal. **Screenshots come out at
the display's backing scale** — a 1200×820 window gives a 2400×1640 image, so
halve image coordinates before feeding them back to the script.

## Architecture

- **Eight `SharedPreferences`-backed stores** — device config, people, positions,
  services, height ranges, operator profiles, preset names, visibility. Each
  owns its own keys and its own `toJson`/`fromJson`.
- **`ConfigBundle`** (`lib/services/config_bundle.dart`) gathers all of them
  into one JSON document and can read it back. Wired to manual export/import in
  `settings_dialog.dart:176` onward. This is the whole backup story today.
- **`RolandService`** speaks telnet over TCP; **`PanasonicService`** speaks
  HTTP. Both have an `abstract/` interface and a `mock/` implementation used by
  demo mode.
- **`preset_resolver.resolvePreset`** decides which camera preset points at a
  person: explicit per-person override first, then a `HeightRange` match on
  height, then null. Getting this silently wrong aims a camera at nobody.

## Known silent failures

These are the reason the test policy draws Class 1 where it does. All three are
live as of 2026-08-21.

1. **A dropped switcher socket still reads Live.** Every device response is
   routed into an empty closure —
   `lib/widgets/multi_device_control_page.dart:325`, `:540`, `:548`, `:555`.
   A failed preset recall is visually identical to a successful one.
2. **Permanent ACK desync.** After a malformed response the command queue never
   recovers.
3. **A wedged camera reports nothing at all.**

A design for the status surface that would absorb these exists at
`docs/superpowers/specs/2026-08-21-drive-backup-and-status-surface-design.md`
(open question 4). It is a design, not shipped behaviour.

## Agent setup

The superpowers skills live in `.claude/skills/`, vendored into the repo so they
travel with a clone. The upstream plugin is **disabled for this project**
(`.claude/settings.json`) — it injects a "you have superpowers" preamble into
every single turn, which is noise, and its copies here have Daniel's test policy
folded in. Provenance is stamped at the top of each `SKILL.md`; diff against
`superpowers@6.3.0` (`e4a2375`) before pulling upstream changes.

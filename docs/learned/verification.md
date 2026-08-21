# Verification field notes

What gets a test in this repo, what gets a screenshot, and what gets neither.

Binding project copy of the test-value policy. The general policy is the `tdd`
skill (`.claude/skills/tdd/`); **this file wins where they differ**, because it
names the actual surfaces.

## Test policy

A test exists where a silent wrong answer could point a camera at the wrong
person, tell the operator a dead switcher is Live, or lose a configuration that
took an hour to enter — and almost nowhere else. Coverage is not the goal.

| Class | Covers | Policy |
|---|---|---|
| **1 — Trust contract** | `ConfigBundle` export/import and the import contract; the eight `*_store.dart` `SharedPreferences` round-trips; every model `toJson`/`fromJson` (`person`, `position`, `service`, `height_range`, `operator_profile`); `preset_resolver.resolvePreset` and `height_utils`; Roland command encoding and response parsing (terminator, STX strip, ACK/NACK); Panasonic request building and response parsing | Behavioral tests required before the work is done. Bug fix ⇒ failing repro test first. Serialized output ⇒ golden test on the bytes/JSON, not a field-by-field walk. |
| **2 — Behavior wiring** | Dialog → store plumbing, tab wiring, connection lifecycle, response routing, settings propagation | Test-AFTER, thin: ONE test per behavior asserting the user-visible outcome. Edge-case matrices belong at Class 1, never re-run through `pumpWidget`. |
| **3 — Presentation** | Layout, iPad sizing, chrome, styling, button placement | NO unit tests. Screenshots of the real app against the mock rig are the verification. |
| **4 — Spikes & ops** | `tools/`, `chaos_demo.dart`, `verify.dart`, throwaway exploration | No tests. A diagnostic that becomes load-bearing graduates to Class 1/2 explicitly. |

When unsure between 1 and 2, ask: *if this silently returned the wrong answer,
would anyone notice before Sunday morning?* No ⇒ Class 1.

## The bug-fix rule

Fix a bug by first writing a failing test that reproduces it, watching it fail
for the expected reason, then fixing. This survived the retirement of strict
TDD because it earns its cost every time: the repro proves the fix and pins the
regression. Never fix a Class 1 or Class 2 bug without it.

## Anti-patterns — never write these

- A test per function because the function exists
- Mocking a store or service this app owns to assert what got passed to it —
  mock at the socket, the HTTP client, the clock; nowhere else
- Asserting on mock call counts when a real result is assertable. An
  `verifyNever`-style guard with no same-file positive control proving the seam
  fires is presumed vacuous
- Pixel pins, widget-tree structural chains, `find.byType` ladders standing in
  for "does it look right"
- Re-running a logic matrix through `pumpWidget` or `integration_test`
- Reading source text and asserting on it

## Loop discipline

- **While iterating:** the one owning file — `flutter test test/<name>_test.dart`
- **At task end:** `flutter analyze` and the full `flutter test`. The suite is
  small and fast; a per-lane allowlist would be ceremony here.
- **Layout or device-control changes also run:** `flutter test integration_test/`
- **Presentation work is not done until the screenshots have been looked at.**
  Green tests never verify what the operator sees. Anything removed or moved
  gets a screenshot showing it ABSENT.

## The existing suite predates this policy

As of 2026-08-21: 305 tests green in 4s, 4,925 test lines against 10,073 lib lines.
`test/manager_dialogs_test.dart` (971 lines) and `test/service_tab_test.dart`
(502) are dialog widget tests that this policy would mostly classify Class 3.
**They have not been audited and nothing here asks you to delete them.** This
policy binds new work. A prune pass is Daniel's call, made with the list in
front of him — not something to slip into an unrelated change.

## Known silent failures — the reason Class 1 is drawn where it is

1. **A dropped switcher socket still reads Live.** Every device response is
   routed into `onResponse: (_) {}` — `lib/widgets/multi_device_control_page.dart:325`
   and again at `:540`, `:548`, `:555`.
2. **Permanent ACK desync** after a malformed response — the queue never
   recovers.
3. **A wedged camera reports nothing at all.**

These are worse than any backup or config fault, because they happen during a
service. The status-surface design
(`docs/superpowers/specs/2026-08-21-drive-backup-and-status-surface-design.md`,
open question 4) is where they get absorbed, if they do.

---
name: tdd
description: Use when deciding whether and how to test a change. Classify the change (trust contract / wiring / presentation / spike), then write behavioral tests through public interfaces for contracts, one thin wiring test for glue, none for presentation. Bug fix ⇒ failing repro test first. Triggers on "write a test", "add tests", "implement", "fix bug", or any request that produces new code paths.
---

<!-- Vendored from ~/.claude/skills/tdd, 2026-08-21. Project copy so the policy travels with the repo. -->

# Test Value Policy

**Policy shift, Daniel's ruling 2026-08-19: strict test-first TDD is retired.**
A test is written where a silent wrong answer could corrupt data, lie to a
user, or break a persisted/exported/contracted shape — and almost nowhere
else. Coverage is not the goal; catching the failures that matter is.
**This repo's binding class table — which navigation_app surfaces are Class 1,
and what a screenshot means here — is `docs/learned/verification.md`. Read it
with this skill; where they differ, the project file wins.**

## Step 1 — Classify the change

| Class | What's in it | Test policy |
|---|---|---|
| **1 — Trust contract** | Persisted shapes, serialized exports, money/data-integrity logic, validation gates, user-facing copy that is itself a contract, cross-language payloads, determinism guarantees | Behavioral tests REQUIRED before the work is done. Bug fix ⇒ failing repro test first. Serialized output ⇒ golden/byte test. |
| **2 — Behavior wiring** | Glue between contracts and the user: route handlers, component wiring, plumbing, event handling | Test-AFTER, thin: ONE test per behavior asserting the user-visible outcome. Edge-case matrices belong at Class-1 pure-logic level, never re-run through expensive integration mounts. |
| **3 — Presentation** | Layout, styling, chrome, cosmetics | NO unit tests. Screenshots / visual verification. |
| **4 — Spikes & ops tooling** | Throwaway exploration, scripts, diagnostics | No tests. A diagnostic that becomes load-bearing graduates to Class 1/2 explicitly. |

When unsure between 1 and 2, ask: "if this silently returned the wrong
answer, would anyone notice before it did damage?" No ⇒ Class 1.

## Step 2 — The bug-fix rule (the one place red-first survives)

Fix a bug by first writing a failing test that reproduces it, watching it
fail for the expected reason, then fixing. This is kept from TDD because it
earns its cost every time: the repro proves the fix and pins the regression.
Never fix a Class-1/2 bug without its repro test.

## What makes a test high-value

| Quality | Good | Bad |
|---------|------|-----|
| **Minimal** | One behavior. "and" in the name? Split it. | `test('validates email and domain and whitespace')` |
| **Clear** | Name describes behavior | `test('test1')` |
| **Through interface** | Uses public API, asserts through public API | Reaches into internal state, private helpers, or a database |
| **Refactor-proof** | Survives internal restructure with behavior unchanged | Breaks on a private-method rename, a CSS reshuffle, a call-count change |
| **Real code** | Mocks only at true system boundaries | Mocks its own collaborators, asserts on mock call counts |

Worked examples: `tests.md`. Interface trouble: `interface-design.md`,
`deep-modules.md`.

## Mocking — boundaries only

Mock external APIs, network, hardware, time, randomness — never your own
classes, internal collaborators, or pure logic you control. If a test can't
be written without mocking an internal collaborator, the interface is coupled
wrong: fix the interface, not the test. Full patterns and gate functions:
`mocking.md`.

**Never assert on a mock call count when a real result is assertable.** An
`assert_not_called`/call-count guard without a same-file positive control
(proof the seam fires when it should) is presumed vacuous — it passes when
aimed at nothing.

## Anti-patterns — never write these

- Regex/`readFileSync` assertions over source code or CSS text
- Pixel/coordinate pins, structural class-selector chains
- Mocking a sibling component to assert the props passed to it
- Re-running a logic matrix through full-app mounts or live-server clients
- A test for every function because it exists ("simple code breaks" is not a
  reason; simple code failing loudly needs no test)
- Meta-tests that grep source for decorators/private names (architectural
  fences with a documented incident behind them are the exception)

## Test-first remains available, not required

When an interface is genuinely unclear, writing the wished-for API as a
failing test first is still the best design tool — use it. If you do write
tests first, write ONE, watch it fail, make it pass, repeat; a pile of
up-front tests written against imagined behavior tests the shape, not the
behavior.

## Execution discipline

While iterating, run the ONE test file that owns what you're editing:
`flutter test test/<owning>_test.dart`. At task completion run `flutter
analyze` and the full `flutter test` — 305 tests in 4s, so a per-lane
allowlist would be pure ceremony. `flutter test integration_test/` runs when
the change touched layout or the device-control flow.

## Refactoring

After tests pass, clean up per `refactor-candidates.md`: run the owning tests
after each step, never refactor while red, don't add behavior mid-refactor.
If a refactor breaks many tests while behavior is unchanged, the tests were
implementation-coupled — delete or rewrite them against the public interface;
that is a test bug, not a reason to keep the old structure.

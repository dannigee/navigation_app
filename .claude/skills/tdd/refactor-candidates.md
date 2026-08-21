# Refactor Candidates

**Load this when:** tests are passing and you're looking for cleanup opportunities.

After landing a change, look for:

- **Duplication** — extract a function or class. If the same shape appears three times, it's probably worth extracting. Two times, probably not yet.
- **Long methods** — break into private helpers. Keep the tests on the public interface; the helpers don't need their own tests.
- **Shallow modules** — combine or deepen. A module whose interface is nearly as complex as its implementation is carrying no weight. See `deep-modules.md`.
- **Feature envy** — a method that reaches repeatedly into another object's data probably belongs on that other object.
- **Primitive obsession** — a string that's really an email, an int that's really a cents amount. Introduce a value object when the primitive starts carrying rules.
- **Existing code the new code reveals as problematic** — new work often exposes weaknesses in code you didn't touch. Note them, fix them deliberately (with tests per the test-value policy), don't sweep them in silently.

## Rules during refactor

- Run tests after every step. Not at the end — after every step. A refactor that breaks a test you find out about three changes later is a debugging problem, not a refactor.
- Never refactor while red. Get to green first.
- Don't add behavior during refactor. If you notice missing behavior, note it, finish the refactor, then start a new RED cycle for the new behavior.
- If a refactor requires changing many tests, the tests were probably coupled to implementation. That's a signal — revisit `interface-design.md`.

## What refactor is not

Refactor is not:
- Adding the thing you forgot
- Expanding scope because "while we're here"
- Rewriting something unrelated that's been bugging you
- Cleaning up without a passing test suite first

All of those are new work. Start a new RED.

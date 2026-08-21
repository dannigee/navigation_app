# Deep Modules

**Load this when:** designing a new module, class, or public API — especially if you're tempted to expose a lot of small methods for "flexibility."

From John Ousterhout's *A Philosophy of Software Design*:

**Deep module** = small interface + lots of implementation

```
┌─────────────────────┐
│   Small Interface   │  ← Few methods, simple params
├─────────────────────┤
│                     │
│                     │
│  Deep Implementation│  ← Complex logic hidden
│                     │
│                     │
└─────────────────────┘
```

**Shallow module** = large interface + little implementation (avoid)

```
┌─────────────────────────────────┐
│       Large Interface           │  ← Many methods, complex params
├─────────────────────────────────┤
│  Thin Implementation            │  ← Just passes through
└─────────────────────────────────┘
```

Shallow modules are traps: they force the caller to learn a lot of surface area while providing very little actual abstraction. The interface becomes the cost center.

Deep modules hide complexity behind a simple contract. Users of the module learn a few methods and get a lot of behavior. Tests of the module exercise a few methods and cover a lot of implementation.

## Design questions

When shaping a module, ask:

- **Can I reduce the number of methods?** Every public method is a test surface and a commitment.
- **Can I simplify the parameters?** Long parameter lists mean combinatoric test cases.
- **Can I hide more complexity inside?** If the caller has to know *how* the module works to use it, the module is too shallow.
- **Does this method exist because I need it, or because I imagined someone might?** YAGNI — cut it.

## Why this matters for TDD

Deep modules produce tests that survive refactors.

- Fewer public methods → fewer tests that could break.
- Tests go through a small, stable interface → internal restructuring doesn't move the test surface.
- Implementation complexity stays hidden → refactoring the internals doesn't require rewriting the tests.

A shallow module with 12 public methods has 12 test surfaces that all move when you restructure. A deep module with 3 public methods has 3 test surfaces, and the internal reorganization is invisible to the tests. That's the whole point.

## Related

- `interface-design.md` — how to shape individual methods for testability
- `refactor-candidates.md` — "shallow modules → combine or deepen" is a refactor trigger

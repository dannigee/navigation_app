---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

<!-- Vendored from superpowers@claude-plugins-official v6.3.0 (sha e4a2375), 2026-08-21.
     Local edits fold in Daniel's test-value policy; diff against upstream before pulling changes. -->

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. Frequent commits. Tests per the project's test policy — the `tdd` skill and the class table in `docs/learned/verification.md` — never a test per function because the function exists.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `using-git-worktrees` skill at execution time.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Task Right-Sizing

A task is the smallest unit that carries its own test cycle and is worth a
fresh reviewer's gate. When drawing task boundaries: fold setup,
configuration, scaffolding, and documentation steps into the task whose
deliverable needs them; split only where a reviewer could meaningfully
reject one task while approving its neighbor. Each task ends with an
independently testable deliverable.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes).** Which steps a task gets depends on
its test-policy class, not on a fixed ceremony:

| Class | Steps |
|---|---|
| **1 — trust contract** | Implement → write the behavioral test → run it → commit. A **bug fix inverts this**: failing repro test first, watch it fail for the right reason, then fix. |
| **2 — wiring** | Implement → ONE thin test asserting the user-visible outcome → run it → commit. |
| **3 — presentation** | Implement → screenshot the real app → commit. No unit test. |
| **4 — spike / ops** | Implement → commit. No test. |

Writing the test first is still available where the interface is genuinely
unclear — it is the best design tool there is. It is not required.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** [path to the spec/design doc this plan implements — the plan
argues from the spec, so the spec travels with it; executors read both]

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits,
naming and copy rules, platform requirements — one line each, with exact
values copied verbatim from the spec. Every task's requirements implicitly
include this section.]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Test-policy class:** 1 trust contract | 2 wiring | 3 presentation | 4 spike
— per `docs/learned/verification.md`. If this task puts a test at an expensive
layer (`integration_test/`, a full `pumpWidget` mount) for logic a pure Dart
test could hold, say why here.

**Files:**
- Create: `exact/path/to/file.dart`
- Modify: `exact/path/to/existing.dart:123-145`
- Test: `test/exact/path/to/thing_test.dart` — or `none (Class 3, screenshot)`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]

- [ ] **Step 1: Implement**

```dart
String encodeCommand(String verb) => '$verb;';
```

- [ ] **Step 2: Write the test the class calls for**

Class 1 gets a behavioral test through the public API. Class 2 gets one thin
test for the user-visible outcome. Class 3 gets a screenshot instead. Class 4
gets nothing.

```dart
test('encodes a bare verb with the terminator', () {
  expect(encodeCommand('CUT'), 'CUT;');
});
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/path/thing_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add test/path/thing_test.dart lib/path/file.dart
git commit -m "feat: add specific feature"
```
````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, offer execution choice:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use subagent-driven-development
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use executing-plans
- Batch execution with checkpoints for review

# Lane Process

How work gets done in this repo. Binding for every agent Daniel points at this
code — don't substitute your own flow, and don't add to this one. **Hard cap:
100 lines.** Over it, something comes out the same sitting.

## When you need a lane

Product behavior, persisted shapes, device protocols, and anything an operator
sees during a service. **No lane:** docs, mechanical fixes, lint, additive
tests, `tools/` and other off-product-path ops work.

**Zero-user gate.** Two people run this app; old local state is disposable. No
migration or legacy-fallback work unless today's workflow reproduces the
problem or Daniel names state worth preserving — data-loss bugs in the current
workflow still get a lane.

## Tiers — declare yours in one line, then go

**Tier 1 — screenshot fix. This is the normal tier.** A visual or layout defect
with an obvious right answer. Fix it, test only where the policy calls for one,
screenshot the real app before and after. The screenshot is the review.

**Tier 2 — light lane. The other normal tier.** A narrow surface: a short spec
pass, tests per `docs/learned/verification.md`, a screenshot. One cold reviewer
only if you're unsure of the contract.

**Tier 3 — full lane. Rare, and fenced.** Reserved for a new or changed
**persisted shape**, an **import/export contract**, a **device protocol**
change, or **anything where being wrong is invisible until Sunday**. The Drive
backup work qualifies; most work here does not. Tier down when the fix is
visible and self-evidently right, up when a mistake would be silent.

**Every tier isolates.** Code at any tier rides its own worktree and branch —
`git worktree add .worktrees/<lane> -b <lane>`. **Merge and push are Daniel's,
always, at every tier.** No agent merges, pushes, or deletes a lane branch.

## Tier 3 flow

1. **Open.** Worktree + branch off current `main`. Packet lives at
   `docs/superpowers/lanes/<lane>/`: `spec.md`, `plan.md`, `progress.md`.

2. **Spike first — before a line of spec.** Throwaway code running the
   load-bearing path end to end against real hardware or the mock rig
   (`tools/mock_server`); receipts in `<packet>/spike/`. A killed premise ends
   the lane. Reverted before the build, never grown into it. **No spike ⇒ no
   spec.**

3. **Spec.** Purpose, decision, rejected alternatives, exact persisted shapes
   and copy strings, scope fences, acceptance criteria, §Evidence citing the
   spike. One contract surface; >~3 shippable behaviors means split it.

4. **Two cold reviewers, cross-family**, via `scripts/handoff-to-agent.sh`
   (`codex` with `gpt-5.6-sol`, `grok`, `kimi`, `claude` with `opus 5`) — never
   your own family. Each gets the whole artifact and an open mandate: find
   anything wrong anywhere, ranked by severity. Demand `BLOCKERS: <n>` first;
   silence is not a verdict. A **BLOCKER** is one concrete reachable breakage —
   no counterfactual, no BLOCKER.

5. **Fold it yourself.** No adjudicator, no disposition artifact. One
   revision-log line per finding in `spec.md`: severity as filed, what you did,
   and a receipt — `file:line`, a command with its exit status, or a named
   reproducer. **Reviewers are wrong sometimes; verify both directions.** No
   receipt ⇒ UNVERIFIED, change nothing.

6. **Plan.** Exact files, real Dart, exact commands with expected output,
   per-task commits with guarded staging — never `git add -A`. Every task names
   its test-policy class and which tests will exist when it's done.

7. **Plan review.** Two cold cross-family reviewers on the committed plan, step
   4's mechanics. Every plan brief carries three standing questions verbatim:
   *Is there a simpler approach with identical results? A different approach
   with a better result? Does the plan cover everything the spec promised, end
   to end?* **A beaten-up plan gets re-thought, not patched.**

8. **Execute.** Per-task commits, tests per the policy, iterate on the owning
   test file. Blocked or failing twice ⇒ peer help via
   `scripts/handoff-to-agent.sh` before escalating to Daniel.

9. **Sweep.** `flutter analyze`, full `flutter test`, `flutter test
   integration_test/`, and a screenshot of every affected view against the mock
   rig — **looked at**, not just captured. Must carry a `## Limitations`
   section naming every acceptance criterion not fully met, or stating there
   are none; silence reads as unqualified success. Then hand it to Daniel —
   **the merge is his call, always.**

## Rules that stop spirals

**Freeze the proof standard at round 1.** Acceptance criteria and evidence
standard fix when the spec commits. A better standard found mid-lane goes to
`LEARNED.md` and binds the *next* lane, unless it would let a real defect ship.

**One artifact, one file, one revision log.** No `-v2.md` siblings; a revision
never resets a round counter. **Closed questions bind** — reopening needs new
cited evidence, not a re-reading of the same text.

**Do not add process.** A tier, a review round, an artifact directory, or an
extra session needs **Daniel's word** — not your judgment that it would be
safer. Sight-reader's flow got cut 425 → 149 lines for this exact reason; this
repo is a tenth its size and starts where that one landed.

# Google Drive backup and the status surface

Design, 21 Aug 2026. Revised after adversarial review by `gpt-5.6-sol` (high)
and Antigravity; see [Review history](#review-history).

## Problem

Every piece of configuration this app holds — positions, people, service
orders, height ranges, preset names, item visibilities, device addresses,
operator profiles — lives in `SharedPreferences` on one machine. A dead Mac
mini takes all of it with no way back.

`ConfigBundle` (`lib/services/config_bundle.dart`) already gathers the whole
lot into a single JSON document and can write and read it, wired to manual
export/import buttons in `settings_dialog.dart:179-248`. What is missing is
somewhere off-machine to put it, and something that says out loud when putting
it there fails.

Two people share one dedicated Google account for the project, so Drive is the
store. The second half of this design matters more than the first: this app's
established failure mode is going quiet. A dropped switcher socket still reads
**Live** (`multi_device_control_page.dart:294-325` routes every device response
into `onResponse: (_) {}`); a wedged camera reports nothing at all. A backup
that failed silently would be the same bug in a new place.

## Scope

In:

- An immutable, append-only revision store on Google Drive.
- A `BackupTarget` interface with Drive and mock implementations, so the engine
  is testable without a network or a Google account.
- A defined sync protocol: what pull does, what push does, and how the local
  provenance pointer moves.
- An explicit import contract, because the current one is neither a full
  replace nor atomic.
- An always-visible status pill in the AppBar and a clickable error-log popover.

Out:

- Real-time collaborative editing. Concurrent edits are detected and surfaced,
  never merged.
- **Per-*user* attribution.** One shared Google account means Drive's own actor
  identity is useless. `deviceLabel` names the *machine*, which is what the
  conflict UI needs, but it is self-declared and trivially wrong if someone
  mislabels a machine. It is a usability aid, not an audit trail. Real
  person-level auditability would require separate Google identities.
- Encrypting the bundle at rest. It holds names and LAN addresses.
- **Drive on Linux or Windows.** `google_sign_in` has no Linux support, the
  production machine is the Mac mini, and John develops against
  `MockBackupTarget`. A second OAuth path for desktop Linux was avoidable scope
  and has been cut.
- **Any automatic local file target.** See [One target only](#one-target-only).
  The existing manual export/import is untouched and remains the offline
  escape hatch.

## Assumptions

1. **The Mac mini has internet while driving the Roland.** Confirmed by Daniel,
   21 Aug 2026: WiFi is up alongside the Ethernet that runs to the Roland's
   isolated switch. Sync can therefore run live during a service, and no
   store-and-forward queue is needed.
2. **The pill is the single surface for every failure and warning in the app**,
   not just backup. Decided by Daniel, 21 Aug 2026. Backup is the first tenant;
   device faults follow in phase 5. This is why the fault type and the log are
   general from day one — see [One surface for every
   fault](#one-surface-for-every-fault).
3. **Drive is the only backup target.** Decided by Daniel, 21 Aug 2026. There
   is no local file target. See [One target only](#one-target-only) for what
   that removes and what it costs.

## What the existing code actually does

The first version of this spec asserted that `ConfigBundle.saveToStores()` is a
full replace and built everything on top of that. **It is not**, and the
correction changes the design rather than just the prose.

`saveToStores()` (`config_bundle.dart:155-179`) does three different things:

| Data | Behaviour on import |
|---|---|
| positions, people, services, heightRanges | **Full replace.** Each `saveAll` writes one complete JSON list. |
| `preset_names_*`, `item_visibility_*` | **Merge.** The loops only `setString` keys present in the bundle. A device key absent from the bundle is never deleted. |
| rolandIp, cameras, operators | **Skipped entirely** when the bundle's nullable field is absent. |

Two consequences the design must handle:

- **The restore is not transactional.** It is a series of independent
  `SharedPreferences` writes. A failure partway leaves a hybrid of old and new
  configuration, and the next backup can upload that hybrid as a valid revision.
- **The existing test does not catch this.** `'saveToStores overwrites previous
  store contents'` (`test/config_bundle_test.dart:240-253`) asserts only on
  positions, people and services. It blesses the incomplete replace.

Separately, `ConfigBundle.fromJson({})` produces an empty-everything bundle and
a test asserts that it should (`test/config_bundle_test.dart:110-118`). So a
truncated or incompatible JSON object is currently a *valid destructive
restore* of the four list stores.

The motivation for this project survives all of that: a stale machine pushing a
snapshot still silently reverts the other machine's positions, people, services
and height ranges. Only the stated contract was wrong.

### The import contract, decided

Bundle-owned keys are **fully replaced**. On import, any `preset_names_*` or
`item_visibility_*` key not present in the incoming bundle is **deleted**.

`ConfigBundle` must distinguish "field absent because this is a legacy file"
from "field present and deliberately empty", so it carries a `schemaVersion`
field of its own — `ConfigBundle.fromJson` cannot decide, and `saveToStores`
cannot act, without it. The full matrix is in
[Schema and validation](#schema-and-validation), and it is load-bearing: get it
wrong and importing an old manual export deletes every preset name on the
machine.

### Import is transactional via a rollback journal

An earlier revision of this spec proposed "stage a canonical snapshot, then
materialize the stores". That is not a transaction. A failure after two store
writes still leaves the live stores hybrid, and retaining old bytes in a third
place neither rolls them back nor stops `fromStores()` assembling the hybrid and
uploading it as a valid revision. It also created a second authority — a
canonical snapshot alongside eight independently authoritative stores — which is
duplicated state that buys no atomicity.

Use a write-ahead journal instead. The stores remain the single authority and
the app's read path is untouched.

1. Read every bundle-owned key's **current** value into one journal object and
   write it to `backup_restore_journal` as a single `setString`.
2. Materialize the individual stores.
3. Delete the journal, then advance the provenance pointer.

If any step fails, restore every key from the journal and delete it. **On app
start, a journal that exists at all means a previous materialization was
interrupted — roll it back before doing anything else.**

The observable guarantee is what the test must assert: after an injected failure
at any point, the live stores are **wholly old or wholly new**, never a mix.
Asserting only that some retained snapshot survived is not the same claim and
would pass over the bug.

Only after a fully successful materialization does the pointer move. Every use
of "apply transactionally" elsewhere in this document means precisely this
procedure.

## Architecture

```
lib/services/backup/
├── abstract/backup_target_abstract.dart   the interface
├── drive_backup_target.dart               googleapis drive/v3
├── mock/mock_backup_target.dart           in-memory, for tests
├── backup_revision.dart                   revision metadata, incl. ancestry
├── backup_failure.dart                    the failure taxonomy
├── backup_log.dart                        the bounded log
├── config_mutation_notifier.dart          the change source (see below)
└── backup_service.dart                    the engine: single-flight, protocol, status
```

`BackupService` is the only thing the UI talks to, and **every operation runs
through one single-flight queue inside it**. Pulls, debounced pushes, periodic
sweeps, manual retries and the backoff timer are otherwise five independent
callers of the same mutable state; without serialization an older operation can
complete after a newer one and overwrite status or provenance.

### The interface

```dart
abstract class BackupTargetAbstract {
  /// Uploads a new immutable revision. Never overwrites an existing one.
  /// Must fail rather than replace if the generated id already exists.
  Future<BackupRevision> put(
    String json, {
    required String contentHash,
    required String? parentRevisionId,
  });

  /// Newest revision's metadata, or null when the store is empty.
  /// Must not download the body. Ordering rules are defined per target.
  Future<BackupRevision?> latest();

  /// Revisions, newest first.
  Future<List<BackupRevision>> list({int limit = 50});

  /// Downloads a revision and verifies the body against a trusted checksum.
  Future<String> fetch(BackupRevision revision);

  /// Deletes revisions outside the retention policy.
  Future<void> prune({required int keepCount, required Duration keepFor});
}
```

There is no `siblings()`. An earlier draft had one for fork detection, but it
forced all three implementations to grow a specialised parent-query when
`list(limit: 10)` and a filter in `BackupService` answers the same question.

`put` takes serialized JSON so that hashing, serialization and transport each
have one owner. Everything throws an `AppFault` in the `backup` domain and
nothing else; implementations translate their own exceptions at the boundary.

There is no `ping()`. The previous draft had one and then argued three sections
later that no liveness probe was needed, because the pull already is one.

### Revision metadata

```dart
class BackupRevision {
  final String id;                 // Drive file id; locally, a UUID
  final String filename;
  final DateTime createdAt;        // SERVER time on Drive; see below
  final String contentHash;        // sha256 of the canonical JSON body
  final String? parentRevisionId;  // the revision this was edited from
  final int sizeBytes;
  final String deviceLabel;        // "Mac mini", "Daniel's iPad"
}
```

The app enforces **singleton launch**: a second instance must be refused at
startup. Two copies sharing `SharedPreferences` through its cached legacy API
would otherwise read stale values and race the journal.

`parentRevisionId` is the piece the first draft missed. Keeping provenance out
of the hashed *body* is correct — it would change the hash on every upload and
defeat the guard — but that was wrongly taken as a reason to omit ancestry from
the *metadata* too. Ancestry in metadata costs nothing and is what makes fork
detection possible.

## Canonical serialization

**The bundle must be serialized with recursively sorted keys before hashing or
uploading.**

`presetNames` and `visibilities` are `Map<String, Map<String, String>>` built by
iterating `prefs.getKeys()` (`config_bundle.dart:114-140`), which returns a
`Set` with no guaranteed order, and `jsonEncode` preserves insertion order. Two
machines holding *identical configuration* can therefore produce different JSON
bytes, different hashes, and consequently redundant uploads on every sweep plus
spurious conflicts against each other.

The hash guard is load-bearing for the entire design. Without canonical
serialization it does not work at all. Use `SplayTreeMap` recursively, or an
RFC 8785 implementation.

## Schema and validation

`schemaVersion` lives in the **JSON envelope**, not only in Drive
`appProperties`. A downloaded file, an emailed manual export, or a local file
without its sidecar must be self-describing. It changes only when the schema
changes, so it does not defeat content hashing.

`ConfigBundle` gains a `schemaVersion` field. Current exports have no such key
(`config_bundle.dart:52-64`), so **a missing `schemaVersion` means legacy v0** —
accepted, not rejected, and never defaulted to 1. Defaulting an unversioned
legacy export to v1 is precisely the data-loss bug this section exists to
prevent.

The complete matrix, which an implementer must be able to follow literally:

| | **v0 (no `schemaVersion` key)** | **v1+** |
|---|---|---|
| `positions`, `people`, `services` | Required. Absent → `malformedRemote`. | Required. Absent → `malformedRemote`. |
| `heightRanges` | Absent → preserve existing. | Required. Absent → `malformedRemote`. |
| `presetNames`, `visibilities` | Absent → **preserve** existing keys. Present → apply, and delete keys not listed. | Absent → treat as `{}` and **delete** all existing keys. |
| `rolandIp`, `cameras`, `operators` | Absent → preserve. | Absent → **delete/reset** to defaults. |
| `schemaVersion` > this build | n/a | `unsupportedSchema`. Never pull, never push over it. |

`{}` is therefore `malformedRemote` under both versions, because the three core
lists are required in both. The existing tests at
`test/config_bundle_test.dart:110-118` and `:131-136` encode the old permissive
behaviour and must change with the code.

The `unsupportedSchema` rule protects against the reverse hazard: an older
machine pulling a newer revision, silently dropping fields it does not
understand, and pushing back a downgraded snapshot that destroys them
permanently.

**The load-bearing regression test:** seed preset names and visibilities, import
an unversioned legacy export containing neither field, and assert they *survive*.
Without that test the v1 delete rule will eventually be applied to a v0 file by
someone who read the code and not this table.

## The sync protocol

### Pull

The previous draft said "Pull" in four places and never defined it, which is
exactly where local work gets destroyed. It is now explicit:

Branches are evaluated **in order**, and the first match wins.

1. Fetch `latest()` metadata only. If the target identity does not match the one
   recorded with the pointer, the pointer is meaningless → treat as
   **unprovenanced** (branch 3).
2. **Remote is empty.**
   - Pointer is null → genuinely new target. Nothing to apply; local is pending.
   - Pointer is **not** null → the revision we were provenanced against is
     *gone*. **Invalidate the durable head**, null the pointer, and raise a
     `targetMissing` condition. This is not "nothing to do": a successful round
     trip has just proved the backup no longer exists, and leaving the pill
     green would be a lie of exactly the kind this design exists to prevent.
3. **Unprovenanced** (pointer is null, remote is non-empty). Never auto-apply.
   - Local stores are pristine/empty → adopt: fetch, validate, apply
     transactionally, set the pointer.
   - Local has data → **ask which snapshot to adopt.** This covers first run,
     a changed account or folder, and a machine that has just done a manual
     import. Manual import deliberately leaves the pointer null, and without
     this branch the freshly imported configuration would be classified as
     "clean" against its recorded hash and silently replaced by the remote head.
4. **`latest().id == pointer`** → remote has not moved. Nothing to apply.
5. **Content is equivalent under a different id.** Compare the local canonical
   hash against a **trusted** body checksum — Drive's own output-only checksum
   field, or the hash recomputed from a `fetch()`. **Never** against
   `contentHash` from `appProperties` alone: that value is client-supplied and
   stays stale if the file is edited by hand in the Drive web UI, which would
   certify green for bytes that no longer exist at the target. On a genuine
   match, rebase the pointer to the remote id and stop. Without this rebase a
   machine whose content matches a differently-identified revision conflicts
   forever.
6. **`latest().parentRevisionId == pointer` and local is clean** (local hash
   equals the hash recorded for the pointer) → a linear descendant. Fetch,
   validate, apply transactionally, advance the pointer.
7. **Anything else** — remote moved and local is dirty, *or* remote is not a
   descendant of our pointer. Record an unresolved-conflict condition, surface
   it on the pill, and let the operator choose when to resolve. **Do not apply,
   and do not show a modal.** A blocking dialog during a live service is
   unacceptable.

The ancestry test in branch 6 is not decoration. Checking only "local is clean"
asks whether local matches *its own* pointer, which says nothing about whether
remote descends from it. Two machines both starting at Rev 1, both pushing, is
enough:

> Mac pushes Rev 2A. iPad pushes Rev 2B; its pointer advances to 2B and it is
> now perfectly clean. Rev 2A sorts as `latest()` on server time. The iPad
> pulls, finds `latest().id != pointer` and local clean — and overwrites its own
> just-pushed work with the Mac's, silently.

Push already detects forks after the fact; without branch 6's ancestry check
pull walks straight into one and destroys the loser's local state.

### Push

1. If the canonical hash equals the hash of the current head → no-op. No file,
   no request, no log entry. **If that head's id differs from the pointer,
   rebase the pointer to it.** Pull has this rebase and push must too: without
   it a push that finds equivalent bytes under another id leaves a stale
   pointer, and the next genuine edit trips a phantom conflict at step 2.
2. If `latest().id != pointer` → conflict; surface it; do not upload.
3. Otherwise `put(json, parentRevisionId: pointer)`.
4. **After the upload, re-read `list()` and check for a revision other than
   ours sharing our `parentRevisionId`.** If one exists, a fork happened
   between check and write.

Step 4 exists because `latest()`-then-`put()` is a time-of-check/time-of-use
race and Drive's `files.create` offers no compare-and-swap. Two machines
starting from the same revision can both pass step 2 and both upload. Append-only
means neither body is destroyed, but without a fork check neither machine is
ever told. **This design does not promise pre-upload conflict detection**; it
promises detection, honestly, immediately after the fact.

### Pointer transitions

`backup_source_revision` — and the hash recorded alongside it — move on exactly
these events, and no others:

| Event | Pointer becomes |
|---|---|
| Push succeeds | the id returned by `put` |
| Push no-ops on equal hash under a different id | that head's id (rebase) |
| Pull applies a revision (transactionally, fully) | that revision's id |
| Pull verifies remote body equals local content | remote's id (rebase) |
| Manual import from a file | null; local is unprovenanced pending work |
| First adoption of a non-empty remote | the adopted revision's id |
| Account, folder or target identity changes | null; unprovenanced |
| Pull finds remote empty while pointer was set | null, **and the durable head is invalidated** |
| Push fails, pull fails, or restore fails partway | **unchanged** |

The pointer is stored with the target identity. A pointer from a different Drive
folder or account is meaningless and must not be compared.

**First run with a non-empty remote and non-empty local state is a question, not
a default.** Ask which snapshot to adopt. Silently pushing local up can destroy
the other machine's work; silently pulling down can destroy this one's.

### Triggers

| Trigger | Action |
|---|---|
| App start | Pull |
| Unbackground | Pull, then resume any durable pending push |
| Periodic sweep, every 10 min while foregrounded | Pull, then hash-guarded push |
| Bundle-owned data mutated | Push, debounced 30 s |
| Background or quit | Best-effort flush; correctness does not depend on it |
| User taps Retry in the popover | Immediate |

The pull is an unconditional round trip, so an expired credential surfaces on
the next app open or sweep. No separate liveness probe is needed.

### The change source

The trigger table says "data mutated", and **nothing in the codebase can
currently tell us that.** All eight stores are static classes over
`SharedPreferences` with no `Stream`, `ChangeNotifier` or event bus, and writes
are scattered across many widgets — including `ControllableDevice`
(`lib/models/controllable_device.dart:48-60`) and `MasterControlWidget`
(`lib/widgets/master_control_widget.dart:140-159`), which has no data-changed
callback at all.

The first draft claimed the hash guard made a missed mutation path safe. That
is backwards: **a hash guard suppresses a redundant write after a trigger; it
cannot manufacture a trigger that never fired.** A mutation nobody reports is
simply never backed up until something else happens to fire.

So phase 1 introduces `ConfigMutationNotifier`, and every bundle-owned write
goes through it. This is a real refactor of eight stores and their call sites,
and it is a prerequisite, not a detail.

### Durability of pending work

An in-memory debounce timer, retry count and next-attempt time vanish when iOS
suspends or kills the app. **Pending intent must be persisted at the moment of
mutation**, not held only in RAM: record the dirty hash durably when the change
happens, and resume from it on next start or foreground.

Lifecycle flush on background is then an optimization rather than the thing
correctness rests on. This is the only workable answer on iPad, where
backgrounding suspends Dart within seconds and an in-flight HTTPS upload is
killed mid-request.

## Conflict handling

Surfaced on the pill, resolved when the operator chooses, never automatically
and never modally mid-service.

The realistic case is not two people clicking at once — it is a stale local
copy, and the window is days wide.

The resolution UI must show **which device, when, and a compact summary of what
differs**. Three unlabelled buttons are not a decision anyone can make. The
device name comes from `BackupRevision.deviceLabel`, set once per machine in
settings and defaulting to the OS hostname so it is never blank.

- **Use the remote copy** — snapshot local first, then apply transactionally.
- **Keep my copy as a new revision** — uploads with the remote head as parent.
  Named for what it does: append-only means this adds, it does not destroy.
- **Decide later** — **suppresses prompting for that specific remote revision
  id** until the operator reopens it from the popover. Without the suppression,
  the next sweep ten minutes later re-raises the same prompt during the service.

"Recoverable" is only true if recovery is operable. Either ship a minimal
revision-history picker that can preview and restore an older revision, or drop
the recoverability claim and document the manual Drive procedure. This design
takes the first option, in phase 3.

## Drive specifics

- **Folder identity.** A named folder is not an identity: Drive names are not
  unique and two first runs can create two. Create once, persist the folder id
  alongside the pointer, and handle "folder deleted or not found" as a distinct
  condition that invalidates the pointer.
- **`latest()` ordering.** Query explicitly with `trashed = false`, `orderBy`
  server `createdTime desc`, defined pagination, and a deterministic tie-break
  on file id. List order is otherwise arbitrary. **Never order by the
  client-generated filename** — one machine with a wrong clock would then pick
  the wrong head and corrupt retention.
- **Trust the body, not the metadata.** `contentHash` in `appProperties` is
  client-supplied; a file edited by hand in the Drive web UI keeps stale
  metadata. `fetch` verifies the downloaded bytes against Drive's own checksum
  field and against the recomputed hash, and reports `malformedRemote` on
  disagreement.
- **Scope** is `drive.file` against a visible folder, not `drive.appdata`, so
  the backups can be seen and recovered by hand.

## One target only

Earlier drafts specified a `LocalFileBackupTarget` writing timestamped
revisions to a directory. It has been cut. **Drive is the backup; there is no
second automatic target.**

What that removes, which is most of why it was cut:

- **The whole sandbox problem.** The Mac app is sandboxed
  (`macos/Runner/*.entitlements`) with no user-selected-file entitlement, so
  `Platform.environment['HOME']` resolves *inside the app container*. An
  operator-visible local target would have needed a directory picker, the
  read-write entitlement, and a persistent security-scoped bookmark to survive
  a restart, plus an iOS equivalent. That was the open decision blocking
  phase 2, and it is now moot.
- Atomic-write machinery for a second target: collision-proof ids, temp-file
  and rename, post-write re-read verification, and corruption quarantine in
  `latest()`. All of it existed only to make a local directory behave like an
  append-only store.

What it costs:

- **No fallback if Drive is unavailable.** The only offline path is the
  existing manual export/import.
- **John cannot exercise a real target on Linux.** He can still build and test
  the engine, protocol and status surface against `MockBackupTarget`, which is
  where all the difficult logic lives. He was never going to run Drive on Linux
  regardless, since `google_sign_in` has no Linux support.

`BackupTargetAbstract` stays. It costs nothing, `MockBackupTarget` needs it, and
it is what keeps the engine testable without a network.

### The existing manual export stays as it is

`ConfigBundle.writeToPath` / `readFromPath` and their settings-dialog wiring
(`config_bundle.dart:181-205`, `settings_dialog.dart:215-248`) are **not**
refactored onto the new interface and **not** removed. They remain the manual
escape hatch.

They carry a pre-existing bug worth writing down even though fixing it is out of
scope here: under the sandbox, the `$HOME/Documents` path that export suggests
and the path import asks the operator to type do not resolve where either party
expects. That is true today, with or without this project.

## One surface for every fault

Every failure and warning in this app belongs in the pill. Backup is simply the
first thing wired into it.

That decision costs almost nothing today and would cost a migration later. The
log is persisted to `SharedPreferences` on the production machine; once it holds
a year of real entries, changing the shape of an entry means migrating saved
data. So the type is general from the start:

```dart
class AppFault {
  final FaultDomain domain;   // backup, roland, camera
  final String kind;          // domain-specific, stable, never free text
  final String message;
  final Object? cause;
  bool get isRetryable;
  bool get needsUserAction;
}
```

Only `FaultDomain.backup` is implemented in phases 1-4. The other two domains
exist as enum values and nothing more until phase 5.

## Failure taxonomy

Backup-domain kinds:

```dart
enum BackupFailureKind {
  offline,
  authExpired,
  permissionDenied,
  rateLimited,        // temporary; honour Retry-After
  transientServer,    // Drive 5xx; Google prescribes exponential backoff
  storageFull,        // Drive quota; waiting does NOT fix this
  conflict,
  unsupportedSchema,
  malformedRemote,
  targetMissing,      // folder deleted, account changed
  unknown,
}
```

`rateLimited` and `storageFull` were one `quotaExceeded` in the first draft.
Only one of them is repaired by waiting.

`transientServer` is a correction to the second draft, which split
`quotaExceeded` and dropped the original `serverError` in the process — leaving
Drive 5xx with nowhere to go but `unknown`'s slow sweep or a misclassification
as `offline`. Google prescribes exponential backoff for those, so they get their
own retryable kind.

| Kind | Automatic retry |
|---|---|
| `offline`, `rateLimited`, `transientServer` | Backoff 30 s → 1 m → 2 m → 5 m → 10 m, hold at 10 m, never give up. |
| `unknown` | Retry on the 10-minute sweep only. A tight loop around a permanent programmer error burns battery forever. |
| `authExpired`, `permissionDenied`, `storageFull`, `unsupportedSchema`, `targetMissing`, `malformedRemote` | None. Waiting cannot fix these. Retry on foreground or user action, and offer the action that can. |
| `conflict` | None. It is a question, not a failure. |

One persisted scheduler owns the backoff and the sweep. Backoff resets only on
success of the operation that failed.

## The status surface

### Three facts, not one

Colour cannot come from "the most recent attempt", because pull and push are
both attempts. That rule produces this: a push of new edits fails, the pill goes
red, the app is foregrounded, its pull succeeds — and the pill goes green while
the edits are still not backed up anywhere.

The engine therefore tracks three independent things:

1. **Durable head** — the last revision whose content is known to exist at the
   target, and its hash.
2. **Dirty** — whether the local canonical hash differs from the durable head.
3. **Active condition** — the unresolved operation-specific state, if any.

Status is derived by evaluating these **in order**, first match wins. The order
is part of the specification, not an implementation detail:

| # | Condition | Colour | Pill reads |
|---|---|---|---|
| 1 | Active non-conflict failure (`authExpired`, `offline`, `targetMissing`, `storageFull`, `unsupportedSchema`, …) | red | operation-specific, e.g. "Upload failing", "Sign-in expired" |
| 2 | Unresolved conflict or diverged branch | amber | "Needs review" |
| 3 | No durable head, or signed out | grey | "Not backed up" |
| 4 | Dirty — local hash differs from durable head | amber | "3 changes pending" |
| 5 | Local hash equals durable head | green | "Backed up 2h ago" |

Without an explicit order the table is ambiguous in a way that reintroduces the
original bug. Nothing has been edited locally, so "durable head equals local
hash" is true — *and* the background sweep's pull just died on `authExpired`, so
an active failure is also true. An implementer who checks the hash first shows
**green while the credentials are dead.** Failure outranks agreement, always.

**Green means the current local state is known to exist durably at the target** —
not merely that something recently succeeded. A pull success never clears a
failed push, a conflict, or dirty state; a condition clears only when that same
condition resolves.

Amber is the normal resting state between an edit and the debounced upload that
follows it, so it will be seen often and must not read as an error.

### The pill

`AppBar.title` on `multi_device_control_page.dart:463` — the slot is empty since
`9ec4c33` removed the title.

Set `centerTitle: false` explicitly. It happens to left-align today because
`_getEffectiveCenterTitle` (`app_bar.dart:805-816`) returns
`actions.length < 2` on macOS/iOS and this AppBar has four entries — but that
is an accident of the current action count, and dropping to one would silently
centre it.

Visually a sibling of the Live/Demo chip (`:479-497`): `BorderRadius.circular(12)`,
`shade100` fill, `shade800` bold 12 px label, in an `InkWell`.

**Always clickable, in every state**, including green. The popover is the log,
and the log is useful when things are working.

### The popover

Fixed header, outside the scroll area: last successful backup as a relative age,
pending-change count, and the action for the active condition if there is one.

Then a scrollable list, newest first:

- The **active condition is pinned, has no dismiss control, and is stored
  outside the historical ring** so eviction can never remove it.
- **History entries each have an `x`.** Dismissing means "I have read this".
- A cleared condition **becomes an ordinary dismissable row** rather than
  disappearing, so the recovery does not erase the evidence.

Rows show relative timestamp, message, and classification. Timestamps ladder:
under 1 h → "20 minutes ago"; under 24 h → "3 hours ago"; under 7 d →
"Sunday 9:42 AM"; older → "11 Aug, 9:42 AM".

Width capped at 400 px with wrapping. Dismissed by tapping outside.

### Log fingerprinting and bounds

Entries collapse on a **structured fingerprint** — `(kind, operation, stable
error code, target identity)` — never on the message text.

`(kind, message)` was the first draft's key and it does not collapse anything:
`SocketException: ... timed out after 5002ms` differs on every attempt, so a
retry storm fills the cap with unique rows and evicts the auth failure that
actually mattered. Changing detail goes in a `lastDetail` field on the collapsed
row.

Bounded by 14 days, 200 rows, **and** a serialized byte cap with per-message
truncation, since `cause` strings are otherwise unbounded. Persisted in
`SharedPreferences` under `backup_log`, matching every other store here.

## Authentication

macOS and iOS only. `google_sign_in` 7.2.0 with
`extension_google_sign_in_as_googleapis_auth`.

**The first draft claimed the existing macOS entitlements were already
sufficient. That is false.** Required and currently absent:

- `CFBundleURLTypes` with the reversed OAuth client id in both
  `macos/Runner/Info.plist` and `ios/Runner/Info.plist`. Without it the browser
  never returns to the app.
- A `keychain-access-groups` entitlement containing
  `$(AppIdentifierPrefix)com.google.GIDSignIn` on macOS. The GoogleSignIn SDK
  throws a keychain `PlatformException` without it.
- The same keychain sharing if `flutter_secure_storage` is adopted — and whether
  a refresh token is ever handed to the app, and therefore whether a second
  credential store is needed at all, must be **determined from the API rather
  than assumed**.

Any new Apple dependency must ship as a Swift Package. CocoaPods was removed
from both platforms in `5608d36`.

### Day-zero spike, before phase 1

The first draft claimed phase 1 would answer whether `google_sign_in` breaks
`flutter run -d linux`. It cannot: phase 1 adds no such dependency. That
question needs its own throwaway spike, run first, covering macOS, iOS and
Linux builds, OAuth client registration, callback URL configuration, signing and
bundle identity, and the keychain entitlements.

## Testing

- **`MockBackupTarget`** — in-memory, scriptable to throw any failure kind on
  any call, and to simulate a concurrent writer between `latest()` and `put()`.
- **Engine tests** — canonical serialization is order-independent; hash guard
  suppresses identical uploads; every row of the pointer transition table;
  **every pull branch in order**, including the two that destroy data if wrong:
  a clean machine whose remote head is a *sibling* rather than a descendant must
  raise a conflict and must not apply; and a machine that has just manually
  imported must not have that import auto-replaced. Also: push rebases on
  equal-hash-different-id; remote-empty with a set pointer invalidates the
  durable head; fork detection after upload; the single-flight queue serializes
  out-of-order completions; a pull success does not clear a failed push.
- **Status precedence tests** — one per row, and specifically: clean local plus
  an active `authExpired` renders **red, not green**.
- **Import contract tests** — the gap the current suite has. Under v1, absent
  preset and visibility keys are deleted. **Under v0 they are preserved** —
  seed values, import an unversioned legacy export lacking both fields, assert
  they survive. `{}` is malformed under both versions; a newer `schemaVersion`
  is refused.
- **Transaction tests** — inject a failure at each materialization step and
  assert the live stores are **wholly old or wholly new**, never a mix.
  Asserting merely that a retained snapshot survived would pass over the bug.
  A journal present at startup triggers rollback before anything else runs.
- **Log tests** — fingerprint collapsing; all three bounds; the active condition
  survives eviction.
- **Widget tests** — all five pill states; tappable in each; header pins;
  timestamp ladder boundaries; width cap with a pathological message.
- **Integration** — edit config, observe a revision appear in
  `MockBackupTarget`, restart the app, confirm the pull restores it. The one
  test that needs a real Drive account is deferred to phase 4 and run by hand.

## Phasing

0. **Spike** — the day-zero auth and platform build questions above. Throwaway.
1. **Foundations** — `ConfigMutationNotifier` and the eight-store refactor;
   canonical serialization; `schemaVersion` and validation; the import contract
   with its tests; the interface and `MockBackupTarget`. No new dependencies.
2. **The engine** — `BackupService` with the full protocol, single-flight and
   durable pending state, tested entirely against `MockBackupTarget`. Every
   pull branch, the pointer transitions, fork detection and the transaction
   journal are provable here with no network and no Google account.
3. **Status surface** — pill, popover, log, conflict UI, revision-history
   picker. Driven by phase 2, with faults injected by the mock.
4. **Drive** — `DriveBackupTarget`, auth, folder identity, ordering, checksum
   verification. Carries every new dependency and the only platform risk.
5. **Device faults into the pill** — surface Roland and camera connection state
   through the same `AppFault` surface, so a dropped switcher stops reading
   **Live**. Scope and its limits are below.

Phases 1-3 need no Google account, no network and no Apple-only dependency,
so John can build and verify all of them on Linux. Only phase 4 is
macOS/iOS-bound.

Phase 1 does not claim to ship user-visible value on its own; it is groundwork,
and pretending otherwise in an earlier draft was how the mutation-source problem
stayed hidden.

### Phase 5 in detail, and what it is not

Phase 5 is **not** a UI task. The pill can only report what the app knows, and
today the app knows almost nothing about its own devices.

What has to be built:

- **`RolandService` has no public connection state at all.** It flips a private
  `_isConnected` on socket error (`roland_service.dart:1707`) and never tells
  anyone. It needs a connection-state stream.
- **Device responses are discarded.** Every one is routed into an empty closure
  (`multi_device_control_page.dart:294-325`), so success and failure are
  literally indistinguishable to the UI.
- **`PanasonicService` needs the same**, plus a way to report a camera that has
  stopped answering.
- A `roland` and `camera` `FaultDomain` mapping, and warning-level states —
  device faults include conditions that are degradations rather than failures,
  which is why `AppFault` covers "warning" and not only "error".

What phase 5 explicitly does **not** do, and must not be sold as doing: it does
not fix the three underlying bugs. The permanent ACK desync
(`roland_service.dart:1839`, `:1923`), the absent reconnect
(`:1783`), and the camera command-queue deadlock
(`panasonic_service.dart:88`, `:113`) are their own project. Phase 5 makes the
app *report* that it has become useless; it does not make it recover.

That distinction matters at the point of use. After phase 5 the operator learns
the switcher is gone instead of pressing dead buttons — a real improvement — but
the fix is still to restart. Anyone reading this spec should not expect
otherwise, and `chaos_demo.dart` already reproduces all three on demand for
whoever takes that project on.

## Open questions

None blocking. Everything raised in two review rounds is either decided above or
explicitly out of scope.

## Review history

Reviewed adversarially on 21 Aug 2026 by `gpt-5.6-sol` (high effort) and
Antigravity, independently, against the repository, in two rounds.

### Round 1 — against the first draft

Accepted: the `saveToStores()` contract correction and the import-contract
decision; canonical serialization; the structured log fingerprint; a defined
pull algorithm; the three-fact status model; `parentRevisionId` with
post-upload fork checking; the pointer transition table; `schemaVersion` in the
envelope and `{}` as malformed; local-target atomicity; the macOS keychain and
URL-scheme entitlements; the mutation-source refactor; durable pending work;
Drive folder identity and ordering; conflict-UI recoverability; splitting
`rateLimited` from `storageFull`; and the day-zero spike replacing phase 1's
impossible claim.

Cut as YAGNI: `ping()`, which contradicted this document's own argument that
the pull is the liveness check; and Linux/Windows OAuth, which assumption 3 says
nobody needs.

**Rejected:** the claim that `AppBar.centerTitle` defaults to true on macOS and
iOS and would centre the pill. `_getEffectiveCenterTitle`
(`app_bar.dart:805-816`) returns `actions == null || actions!.length < 2`, and
this AppBar has four action entries, so it already left-aligns. Both reviewers
independently confirmed this rejection in round 2. The suggested fix is adopted
anyway as cheap insurance; the stated reason was wrong.

### Round 2 — against the second draft

The second draft fixed round 1 but introduced new defects of its own, all in
material written to address round 1. Accepted:

- **The "staging" fix was not a transaction.** Retaining old bytes elsewhere
  does not roll back partially written stores, and it added a second authority
  alongside eight already-authoritative stores. Replaced with a write-ahead
  rollback journal, and the test now asserts the observable stores are wholly
  old or wholly new rather than merely that a snapshot survived.
- **Pull branch 6 destroyed the machine's own work.** Checking only "local is
  clean" compares local against *its own* pointer and proves nothing about
  whether remote descends from it, so a machine that had just pushed would
  silently adopt a sibling fork over its own state. Now requires linear
  ancestry.
- **Pull certified green from client-supplied metadata**, contradicting this
  document's own "trust the body, not the metadata" rule two sections later.
- **Remote-empty with a set pointer was treated as "nothing to do"**, leaving
  the pill green after a round trip had proved the backup gone.
- **A just-imported configuration could be auto-replaced**, because manual
  import records a hash while nulling the pointer, which read as "clean".
- **Push lacked pull's equal-hash rebase**, stranding a stale pointer that would
  trip a phantom conflict on the next real edit.
- **The status table had no evaluation order**, so clean-local plus a dead
  credential could render green — the precise bug the surface exists to prevent.
- **The legacy schema gate never said a missing `schemaVersion` means v0**,
  leaving the door open to the exact import-deletes-preset-names bug it was
  written to close. Now a literal matrix with a named regression test.
- **`serverError` was dropped** while splitting `quotaExceeded`, leaving Drive
  5xx unclassified. Restored as `transientServer`.
- `siblings()` cut; `list(limit:)` answers the same question without forcing
  three implementations to grow a specialised query.

Antigravity's verdict was a conditional pass; `gpt-5.6-sol`'s was not-ready,
citing the transactionality gap. The stricter verdict was taken.

### Decisions taken after round 2

Daniel, 21 Aug 2026:

- The Mac mini **does** have internet at church alongside the Roland Ethernet,
  confirming assumption 1 and removing the store-and-forward contingency.
- **Drive is the only backup target.** The local file target is cut, which also
  retires the sandbox question that was blocking phase 2. See
  [One target only](#one-target-only).
- **One machine runs production, but several write configs.** So the conflict
  machinery is guarding something real, and `deviceLabel` is **kept** — a
  conflict prompt that cannot say whose change it is asks the operator to choose
  blind. (Briefly cut earlier on an incomplete reading of "one production
  machine"; reinstated once Daniel clarified that several machines edit.)
- **The app is a singleton.** A second instance must be prevented from starting
  rather than tolerated, which removes the cached-`SharedPreferences` staleness
  hazard rather than requiring reload semantics for it.

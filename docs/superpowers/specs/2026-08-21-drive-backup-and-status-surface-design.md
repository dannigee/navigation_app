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
- A `BackupTarget` interface with Drive, local-directory and mock implementations.
- A defined sync protocol: what pull does, what push does, and how the local
  provenance pointer moves.
- An explicit import contract, because the current one is neither a full
  replace nor atomic.
- An always-visible status pill in the AppBar and a clickable error-log popover.

Out:

- Real-time collaborative editing. Concurrent edits are detected and surfaced,
  never merged.
- Per-user attribution. One shared account means Drive's actor identity is
  useless, and a free-form device label is not an audit trail. If person-level
  auditability is ever needed, that requires separate Google identities.
- Encrypting the bundle at rest. It holds names and LAN addresses.
- **Drive on Linux or Windows.** Assumption 3 says nobody needs it; specifying
  a second OAuth path for it was avoidable scope and has been cut.

## Assumptions

1. **The Mac mini has internet while driving the Roland.** `HANDOFF.md`
   describes its Ethernet going to the Roland's isolated switch at
   `10.0.1.100`. This design assumes a second live path. If that is wrong, see
   [If there is no internet at church](#if-there-is-no-internet-at-church).
2. **The status surface is backup-only for now**, shaped so device faults can
   move into it later.
3. **John does not need Drive on Linux.** He runs the app on the Mac mini;
   Linux is his development machine and gets the local target.

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

`ConfigBundle` must distinguish "field absent because this is a legacy file" from
"field present and deliberately empty". A `schemaVersion` in the envelope (see
[Schema](#schema-and-validation)) makes that decidable: at version 1 and above,
absent means empty and is applied; below it, absent means unknown and is
preserved.

Import becomes transactional by staging: validate the whole bundle, write it to
a single canonical snapshot key, then materialize the individual stores, and
only then advance the provenance pointer. A failure mid-materialization is
recoverable because the previous canonical snapshot is still there.

## Architecture

```
lib/services/backup/
├── abstract/backup_target_abstract.dart   the interface
├── drive_backup_target.dart               googleapis drive/v3
├── local_file_backup_target.dart          a directory; Linux dev, and manual export
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

  /// Revisions sharing a parent with [revision] — a fork check.
  Future<List<BackupRevision>> siblings(BackupRevision revision);

  /// Deletes revisions outside the retention policy.
  Future<void> prune({required int keepCount, required Duration keepFor});
}
```

`put` takes serialized JSON so that hashing, serialization and transport each
have one owner. Everything throws `BackupFailure` and nothing else.

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
  final String deviceLabel;
}
```

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

Before any store write:

- **Reject** a bundle whose `schemaVersion` is greater than this build
  supports, as `BackupFailureKind.unsupportedSchema` — "App update required to
  sync". Never pull it, and never push over it. Without this, an older machine
  pulls a newer revision, silently drops the fields it does not understand, and
  pushes back a downgraded snapshot that permanently destroys them.
- **Validate** required fields and semantic invariants. `{}` must become
  `malformedRemote`, not an empty bundle that wipes four stores. The existing
  test at `test/config_bundle_test.dart:110-118` encodes the old behaviour and
  must be changed along with the code.

## The sync protocol

### Pull

The previous draft said "Pull" in four places and never defined it, which is
exactly where local work gets destroyed. It is now explicit:

1. Fetch `latest()` metadata only. Verify the target identity matches.
2. If remote is empty → nothing to do.
3. Compute the local canonical hash.
4. If `remoteHash == localHash` → the two agree. **Rebase the pointer to the
   remote revision id** and stop. This transition is required: without it, a
   machine whose content matches a differently-identified remote revision
   raises a meaningless conflict forever.
5. If `latest().id == pointer` → remote has not moved; local is ahead or equal.
   Nothing to apply.
6. If `latest().id != pointer` **and local is clean** (local hash equals the
   hash recorded for the pointer) → fetch, validate, snapshot the current local
   bundle, apply transactionally, advance the pointer.
7. If `latest().id != pointer` **and local is dirty** → **do not apply, do not
   show a modal.** Record an unresolved-conflict condition, surface it on the
   pill, and let the operator choose when to resolve. A blocking dialog during a
   live service is unacceptable.

Step 7 is the correction to the biggest hazard in the first draft: either
reading of an undefined "Pull" was bad — one silently erased a Saturday's
planning, the other interrupted a Sunday service.

### Push

1. If the canonical hash equals the hash of the current head → no-op. No file,
   no request, no log entry.
2. If `latest().id != pointer` → conflict; prompt (see below); do not upload.
3. Otherwise `put(json, parentRevisionId: pointer)`.
4. **After the upload, re-read `latest()` and call `siblings()`.** If another
   revision shares our parent, a fork happened between check and write.

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
| Pull applies a revision (transactionally, fully) | that revision's id |
| Pull finds remote hash equals local hash | remote's id (rebase) |
| Manual import from a file | null, with the imported hash recorded |
| First adoption of a non-empty remote | the adopted revision's id |
| Account, folder or target identity changes | null; local becomes unprovenanced |
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
differs**. Three unlabelled buttons are not a decision anyone can make.

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

## The local target

Second-resolution filenames are **not** sufficient for append-only. Two
instances, two clicks in one second, or a retry all collide.

- Revision ids are collision-proof: timestamp plus a UUID suffix.
- Writes are atomic: create exclusively into a temp file in the same directory,
  flush, rename into place, then verify by re-reading and re-hashing.
- Metadata lives in the JSON envelope. The first draft's separate sidecar file
  added a second partial-write boundary for no benefit.
- `latest()` **quarantines** an unparseable or partial file, logs it loudly, and
  falls back to the next valid revision rather than treating corruption as head.

### The sandbox problem

The Mac app is sandboxed (`macos/Runner/*.entitlements`) with **no
user-selected-file entitlement**. `Platform.environment['HOME']` resolves inside
the app container, so today's `$HOME/Documents` export
(`config_bundle.dart:181-205`) and the type-a-path import
(`settings_dialog.dart:215-248`) do not mean what they appear to mean.

A decision is required before phase 1 is called shippable:

- **App-private** — write into the application-support container, and state
  plainly that it is not an operator-visible backup; or
- **User-selected** — add a directory picker, the read-write entitlement, and a
  persistent security-scoped bookmark so access survives a restart, with an
  iOS equivalent defined.

## Failure taxonomy

```dart
enum BackupFailureKind {
  offline,
  authExpired,
  permissionDenied,
  rateLimited,        // temporary; honour Retry-After
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

| Kind | Automatic retry |
|---|---|
| `offline`, `rateLimited` | Backoff 30 s → 1 m → 2 m → 5 m → 10 m, hold at 10 m, never give up. |
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

| State | Colour | Pill reads |
|---|---|---|
| No successful backup ever, or signed out | grey | "Not backed up" |
| Durable head equals local hash | green | "Backed up 2h ago" |
| Dirty, no failure | amber | "3 changes pending" |
| Unresolved conflict | amber | "Needs review" |
| Active failure | red | operation-specific, e.g. "Upload failing" |

**Green means the current local state is known to exist durably at the target** —
not merely that something recently succeeded. A pull success never clears a
failed push, a conflict, or dirty state; a condition clears only when that same
condition resolves.

Amber also covers the offline-queue case if assumption 1 turns out wrong, which
is why the state model already has room for it.

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
  each pull branch, especially dirty-with-moved-remote; fork detection; the
  single-flight queue serializes out-of-order completions; a pull success does
  not clear a failed push.
- **Import contract tests** — the gap the current suite has. Absent preset and
  visibility keys are deleted; `{}` is rejected as malformed; a newer
  `schemaVersion` is refused; a failure mid-materialization leaves the previous
  snapshot intact.
- **Local target tests** — concurrent writes do not collide; a partial file is
  quarantined rather than treated as head; atomic rename holds.
- **Log tests** — fingerprint collapsing; all three bounds; the active condition
  survives eviction.
- **Widget tests** — all five pill states; tappable in each; header pins;
  timestamp ladder boundaries; width cap with a pathological message.
- **Integration** — edit, observe a revision in a `LocalFileBackupTarget`
  directory, restart, confirm the pull restores it.

## Phasing

0. **Spike** — the day-zero auth and platform build questions above. Throwaway.
1. **Foundations** — `ConfigMutationNotifier` and the eight-store refactor;
   canonical serialization; `schemaVersion` and validation; the import contract
   with its tests; the interface and `MockBackupTarget`. No new dependencies.
2. **Local target and engine** — `LocalFileBackupTarget` with atomic writes and
   the sandbox decision; `BackupService` with the full protocol, single-flight
   and durable pending state, tested against the mock.
3. **Status surface** — pill, popover, log, conflict UI, revision-history
   picker. Driven by phase 2 with faults injected by the mock.
4. **Drive** — `DriveBackupTarget`, auth, folder identity, ordering, checksum
   verification. Last, because it carries every new dependency.

Phase 1 no longer claims to ship user-visible value on its own; it is
groundwork, and pretending otherwise was how the sandbox and mutation-source
problems stayed hidden.

## If there is no internet at church

Uploads become store-and-forward: revisions queue locally and flush when the
machine next reaches the internet. The amber "N changes pending" state already
covers the display. `BackupTarget` is unaffected; `BackupService` grows a
durable queue, which the durable-pending-work requirement already half builds.

## Open questions

1. **Internet at church** — assumption 1.
2. **Device label** — a settings field the operator fills in once. Not an audit
   trail; see Scope.
3. **Local target: app-private or user-selected?** Blocks phase 2.
4. **Does the status surface absorb device faults later?** The three known
   silent failures — socket drop still reading Live, permanent ACK desync,
   wedged camera — are worse than any backup fault because they happen during a
   service. If they are ever moving here, `BackupFailure` should become a
   subtype of a broader `AppFault` **before** the log format is fixed.
5. **Multiple macOS instances.** Two copies of the app share
   `SharedPreferences` through a cached legacy API. Either prevent a second
   instance or define reload semantics.

## Review history

Reviewed adversarially on 21 Aug 2026 by `gpt-5.6-sol` (high effort) and
Antigravity, independently, against the repository.

Accepted and folded in: the `saveToStores()` contract correction and the
import-contract decision; canonical serialization; the structured log
fingerprint; the pull algorithm; the three-fact status model; `parentRevisionId`
with post-upload fork checking; the pointer transition table; `schemaVersion` in
the envelope and `{}` as malformed; local-target atomicity; the macOS keychain
and URL-scheme entitlements; the mutation-source refactor; durable pending work;
Drive folder identity and ordering; conflict-UI recoverability; splitting
`rateLimited` from `storageFull`; and the day-zero spike replacing phase 1's
impossible claim.

Cut as YAGNI: `ping()`, which contradicted this document's own argument that the
pull is the liveness check; and Linux/Windows OAuth, which assumption 3 says
nobody needs.

**Rejected:** the claim that `AppBar.centerTitle` defaults to true on macOS and
iOS and would centre the pill. `_getEffectiveCenterTitle`
(`app_bar.dart:805-816`) returns `actions == null || actions!.length < 2`, and
this AppBar has four action entries, so it already left-aligns. The suggested
fix is adopted anyway as cheap insurance, but the stated reason was wrong.

# Google Drive backup and the status surface

Design, 21 Aug 2026.

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
**Live**; a wedged camera reports nothing at all. A backup that fails silently
would be the same bug in a new place.

## Scope

In:

- An immutable, append-only revision store on Google Drive.
- A `BackupTarget` interface with Drive, local-directory and mock implementations.
- Pull on open, debounced push on change, periodic sweep, retry with backoff.
- Conflict detection between two machines editing the same config.
- An always-visible status pill in the AppBar and a clickable error-log popover.

Out:

- Real-time collaborative editing. Two people editing simultaneously is
  detected and surfaced, not merged.
- Per-user attribution. One shared account means Drive revision history cannot
  distinguish Daniel from John; a device label in file metadata is as close as
  this gets.
- Encrypting the bundle at rest. It holds names and LAN addresses, nothing
  secret.
- Migrating existing manual export/import away. That path stays exactly as it
  is, and becomes the local implementation of the new interface.

## Assumptions

Three questions were open when this was written. Each is called out again at
the point it affects the design.

1. **The Mac mini has internet while driving the Roland.** `HANDOFF.md`
   describes its Ethernet going to the Roland's isolated switch at
   `10.0.1.100`. This design assumes a second live path — building WiFi — so
   sync can run during a service. If that is wrong, see
   [If there is no internet at church](#if-there-is-no-internet-at-church).
2. **The status surface is Drive-only for now.** It is designed so device
   connection faults can move into it later without rework, but this spec ships
   backup states only.
3. **John does not need Drive working on Linux.** He runs the app on the Mac
   mini at church; Linux is his development machine and gets the local
   implementation. See [Authentication](#authentication).

## Architecture

Three layers, following the `abstract/` + `mock/` + concrete split the repo
already uses for `RolandService` and `PanasonicService`.

```
lib/services/backup/
├── abstract/backup_target_abstract.dart   the interface
├── drive_backup_target.dart               googleapis drive/v3
├── local_file_backup_target.dart          a directory; Linux, and manual export
├── mock/mock_backup_target.dart           in-memory, for tests
├── backup_revision.dart                   revision metadata
├── backup_failure.dart                    the failure taxonomy
├── backup_log.dart                        the 14-day log, persisted
└── backup_service.dart                    the engine: triggers, hash, retry
```

`BackupService` is the only thing the UI talks to. It owns scheduling, hashing,
retry and conflict detection, and it is the sole writer of status. Swapping
Drive for something else means writing one `BackupTarget`; nothing above it
changes.

### The interface

```dart
abstract class BackupTargetAbstract {
  /// Uploads a new immutable revision. Never overwrites an existing one.
  Future<BackupRevision> put(String json, {required String contentHash});

  /// Newest revision's metadata, or null when the store is empty.
  /// Must not download the body.
  Future<BackupRevision?> latest();

  /// Revisions, newest first.
  Future<List<BackupRevision>> list({int limit = 50});

  /// Downloads and returns the raw JSON for a revision.
  Future<String> fetch(BackupRevision revision);

  /// Deletes revisions outside the retention policy.
  Future<void> prune({required int keepCount, required Duration keepFor});

  /// Cheap credential and reachability probe. No body transfer.
  Future<void> ping();
}
```

`put` takes serialized JSON rather than a `ConfigBundle` so that hashing,
serialization and transport each have one owner. Everything throws
`BackupFailure` (below) and nothing else; implementations translate their own
exceptions at the boundary.

`latest()` returning metadata without a download is what makes the periodic
sweep cheap enough to run every ten minutes.

### Revision metadata

```dart
class BackupRevision {
  final String id;           // Drive file id, or absolute path locally
  final String filename;     // nav_config_20260821-143205.json
  final DateTime createdAt;  // UTC
  final String contentHash;  // sha256 of the JSON body
  final int sizeBytes;
  final String deviceLabel;  // "Mac mini (church)", "Daniel's iPad"
}
```

On Drive, `contentHash`, `deviceLabel` and a `schemaVersion` live in the file's
`appProperties`, so `latest()` is one metadata query. Locally they are parsed
from the filename plus a sidecar, or recomputed on read.

## Data model

### File naming

`nav_config_<YYYYMMDD>-<HHMMSS>.json`, UTC.

`suggestedExportPath()` (`config_bundle.dart:182-186`) currently stamps to the
day only, so a second save on any given day collides with the first. Append-only
cannot tolerate that — widen it to seconds before anything is built on top.
The existing manual-export UI picks up the improvement for free.

### The revision pointer is not in the bundle

Local state records which revision it was loaded from, in `SharedPreferences`
under `backup_source_revision`. It is deliberately **not** a field on
`ConfigBundle`.

If the pointer lived in the uploaded JSON, every upload would change the
document, which would change its hash, which would defeat the hash guard that
stops redundant uploads. Hash the data; track provenance beside it.

`ConfigBundle.toJson()` therefore needs no new fields, and existing exported
files stay readable.

## The sync engine

### Triggers

| Trigger | Action |
|---|---|
| App start | Pull |
| Unbackground | Pull |
| Periodic sweep, every 10 min while foregrounded | Pull, then hash-guarded push |
| Local data changed | Push, debounced 30 s after edits stop |
| Background or quit | Flush any pending debounce |
| User taps "Retry" in the popover | Immediate push |

The pull is what keeps credentials honest. It is an unconditional round trip
that does not care whether local data changed, so an expired token surfaces the
next time anyone opens the app or the next sweep — whichever comes first. No
separate liveness probe is needed.

Ten minutes for the sweep matches the ceiling of the retry backoff below, so
there is one cadence to reason about rather than two that drift apart.

### The hash guard

Before any upload, serialize the bundle and hash it. If the hash equals
`latest()?.contentHash`, do nothing — no file, no request body, no log entry.

This is what makes the trigger list safe to be generous with. Fire the check as
often as convenient; it costs one comparison when nothing has changed. Without
it, every trigger would have to be reasoned about individually, and a missed
mutation path would fail silently.

### Debounce

Reordering a service with eight drag-drops must produce one revision, not
eight. Thirty seconds of quiet after the last mutation, flushed early on
background or quit. A pending debounce lost to app termination is the edit the
user most recently made and most cares about.

### Retention

A revision is deleted only when it is **both** outside the newest 50 **and**
older than 90 days. Either condition alone is not enough. The conjunction errs
toward keeping too much, which is the right direction for a backup: a busy
fortnight cannot age out a revision that is still one of the newest, and a quiet
year cannot leave a single stale file as the only thing standing between you and
an empty Drive folder.

Pruning rides on successful upload, so there is no separate schedule to
maintain and it can never run when the store is unreachable.

## Conflict handling

Detected at upload, prompted, never resolved automatically.

Before pushing, compare `latest().id` against `backup_source_revision`. If they
differ, another machine has written since this one last synced, and pushing
would replace their work wholesale — `ConfigBundle.saveToStores()` is a full
replace, not a merge, so the loser's changes vanish without a trace.

The realistic case is not two people clicking at once. It is a stale local copy,
and the window is days wide: config is planned on one machine on a Saturday and
the other machine still holds last week's state on Sunday morning.

On conflict, stop and ask:

- **Reload theirs** — discard local changes, pull the newer revision.
- **Overwrite** — push anyway. Safe by construction: the other revision is
  still in Drive, because nothing is ever overwritten.
- **Cancel** — leave both alone, keep the pill red, keep the entry pinned.

Append-only is what makes "Overwrite" a recoverable choice rather than a
destructive one.

## Failure taxonomy

Classification is not cosmetic. It decides whether the app can fix itself.

```dart
enum BackupFailureKind {
  offline,           // no route to host, DNS failure
  authExpired,       // token invalid or revoked
  permissionDenied,  // account lacks access to the folder
  quotaExceeded,     // Drive storage or API rate limit
  conflict,          // remote is newer than our source revision
  serverError,       // 5xx
  malformedRemote,   // downloaded JSON will not parse
  unknown,
}
```

```dart
class BackupFailure implements Exception {
  final BackupFailureKind kind;
  final String message;        // human-readable, shown in the popover
  final Object? cause;         // original exception, for logs
  bool get isRetryable;
  bool get needsUserAction;
}
```

| Kind | Retryable | Needs a human | Behaviour |
|---|---|---|---|
| `offline` | yes | no | Back off and keep trying. |
| `serverError` | yes | no | Back off and keep trying. |
| `quotaExceeded` | yes | no | Back off; honour `Retry-After` when present. |
| `authExpired` | no | yes | Stop automatic retries. Popover offers "Sign in again". Retry on foreground or user tap only. |
| `permissionDenied` | no | yes | Same, with a different message. |
| `conflict` | no | yes | Not an error so much as a question. Prompt as above. |
| `malformedRemote` | no | yes | Do not overwrite. Surface which revision failed to parse. |
| `unknown` | yes | no | Treated as retryable, logged with the original exception. |

### Retry policy

Retryable failures back off 30 s → 1 m → 2 m → 5 m → 10 m, then hold at 10 m
indefinitely. **The loop never gives up.** A retry schedule that exhausts itself
and stops is a silent failure with extra steps.

Non-retryable failures schedule nothing. Waiting cannot fix a revoked token, and
hammering only fills the log. They retry when the app is foregrounded or when
the user asks.

## The status surface

### States

Colour is derived from the most recent attempt only. Nothing in the popover can
change it.

| State | Colour | Pill reads | Meaning |
|---|---|---|---|
| `never` | grey | "Not backed up" | No successful backup, or not signed in. |
| `ok` | green | "Backed up 2h ago" | Most recent attempt succeeded. |
| `failing` | red | "Backup failed" | Most recent attempt failed. |

Green carries the age rather than a bare tick. An age is self-evident and cannot
be dismissed into silence; a green dot only ever means "nothing broke recently".

`never` is a real third state. Nothing has failed, so red is a lie; nothing is
protected, so green is a worse one.

### The pill

Lives in `AppBar.title` on `multi_device_control_page.dart:463`. That slot is
empty — `9ec4c33` removed the title — and `title:` left-aligns by default when
unset. `leading:` is the wrong slot: it is 56 px wide and would need
`leadingWidth` fighting to fit text.

No collision above or beside it. The macOS traffic lights are in the window
chrome, not the Flutter AppBar, and the debug banner is upper-right.

Visually a sibling of the existing Live/Demo chip (`:479-497`): a `Container`
with `BorderRadius.circular(12)`, `shade100` fill, `shade800` bold 12 px label,
wrapped in an `InkWell`. Reusing the idiom keeps it reading as part of the app
rather than bolted on.

**Always clickable, in every state**, including green. The popover is the log,
and the log is useful when things are working.

### The popover

Fixed header, outside the scroll area so it cannot scroll away:

- "Last backup: 2 hours ago", or "Never backed up".
- An action button when the current condition needs one — "Sign in again",
  "Retry now", "Resolve conflict".

Then a scrollable list, newest first:

- The **active condition is pinned at the top and has no dismiss control.**
  It persists until an attempt succeeds. This is the whole point: dismissal
  must never be able to turn a broken state green.
- **Historical entries each have an `x`.** Dismissing means "I have read this",
  never "this is fixed".
- When a condition clears, its pinned entry **becomes an ordinary dismissable
  row**. It is not deleted — the recovery must not erase the evidence that
  something broke.

Each row shows: relative timestamp, the human-readable message, and the
classification.

Timestamps degrade across the retention window, so they ladder:

- under 1 h → "20 minutes ago"
- under 24 h → "3 hours ago"
- under 7 d → "Sunday 9:42 AM"
- older → "11 Aug, 9:42 AM"

Relative-only is useless at day eleven.

Width is capped at 400 px with wrapping. Sizing to content means one long
exception string produces a popover wider than the window.

Dismissed by tapping outside, via a barrier.

### Repeat collapsing

A dismissable list assumes a human-sized number of rows. Losing the church WiFi
on a Friday at a 30-second retry produces roughly 2,880 identical rows before
Saturday, and around 40,000 across a fourteen-day window. The popover becomes
unusable and `SharedPreferences` gets megabytes of noise.

Entries collapse on `(kind, message)` into one row carrying a count and a
last-seen time:

> **Network unreachable** — 340 times, most recent 2 minutes ago

One row, one `x`, and strictly more information than 340 rows.

### Log persistence

`SharedPreferences` key `backup_log`, a JSON array, matching how every other
store in this app persists.

Bounded by **both** 14 days and 200 entries, whichever bites first. Age alone is
not a bound — collapsing makes a storm cheap, but a bound that depends on
collapsing working is a bound that fails when collapsing has a bug.

The log survives restarts. A failure that vanishes because the app was quit and
reopened is a silent failure.

## Authentication

Two paths, because no single package covers every platform.

| Platform | Mechanism |
|---|---|
| macOS, iOS | `google_sign_in` 7.2.0 (macOS 10.15+) with `extension_google_sign_in_as_googleapis_auth` |
| Linux, Windows | `googleapis_auth` loopback consent flow — development only |

`google_sign_in` does not support Linux. This is why `LocalFileBackupTarget`
exists: John develops on Linux against a directory, and the Drive path ships to
the machines that run it. Assumption 3 above.

**Verify on day one, before anything is built on this:** that adding
`google_sign_in` to `pubspec.yaml` does not break `flutter run -d linux`.
Federated plugins without a Linux implementation usually build and throw
`MissingPluginException` when called, but that must be confirmed rather than
assumed — if the build breaks, the dependency has to be made conditional and
that changes the shape of this work.

macOS entitlements are already sufficient. `network.client` and
`network.server` are present in both `DebugProfile.entitlements` and
`Release.entitlements`; the loopback OAuth listener needs the latter.

Refresh tokens go in secure storage, not `SharedPreferences`. This adds a
dependency the project does not currently have — `flutter_secure_storage` or
equivalent — and it must ship as a Swift Package, because CocoaPods was removed
from both Apple platforms in `5608d36` and reinstating it is a real cost.

Scope is `drive.file` against a visible folder, not `drive.appdata`. A shared
account makes `appdata` technically workable, but it is invisible in the Drive
web UI. For a backup, being able to open drive.google.com and see the JSON is
worth more than tidiness.

## Testing

The existing suite is the model: `test/config_bundle_test.dart` and
`test/stores_test.dart` cover this area already.

- **`MockBackupTarget`** — in-memory, scriptable to throw any `BackupFailureKind`
  on any call. Every engine test runs against it. No fake Drive server is
  needed; the mock rig covers device protocols and has nothing to say here.
- **Engine unit tests** — hash guard suppresses identical uploads; debounce
  coalesces bursts; flush-on-background fires; backoff schedule is correct;
  non-retryable kinds schedule nothing; conflict is detected when
  `latest().id` moves.
- **Log unit tests** — collapsing by `(kind, message)`; both bounds enforced;
  active condition is not dismissable; a cleared condition becomes dismissable
  rather than disappearing; round-trips through `SharedPreferences`.
- **Widget tests** — pill renders all three states; is tappable in each;
  popover header pins; timestamp ladder at each boundary; width cap holds with
  a pathological message.
- **Integration** — `integration_test/` already drives the real app. One test:
  edit config, observe a revision appear in a `LocalFileBackupTarget`
  directory, restart, confirm it pulls back.

## If there is no internet at church

If assumption 1 is wrong, the shape changes and this section is the amendment.

Uploads become store-and-forward: revisions queue locally and flush when the
machine next reaches the internet. The pill needs a fourth state — amber,
"Offline, 3 changes queued" — which is neither a failure nor a success. The
`BackupTarget` interface is unaffected; `BackupService` grows a local queue, and
the periodic sweep becomes a connectivity check.

Worth confirming before implementation starts, because it is roughly a day of
extra work and is far cheaper to design in now than to retrofit.

## Suggested phasing

This is more than one sitting, and the pieces have a natural order. Each phase
is independently useful and independently testable, which matters because the
riskiest dependency — Google auth — is not in the first one.

1. **The interface and the local target.** `BackupTargetAbstract`,
   `BackupRevision`, `BackupFailure`, `LocalFileBackupTarget`,
   `MockBackupTarget`, and the second-granularity filename fix. No new
   dependencies, works on Linux, and the existing manual export is refactored
   onto it. Ships value on its own: timestamped local revisions instead of one
   overwritten file.
2. **The engine.** `BackupService` — triggers, hash guard, debounce, retry,
   conflict detection — tested entirely against `MockBackupTarget`. Still no
   new dependencies. This is where the logic that is easy to get wrong lives,
   and it can be got right before any network is involved.
3. **The status surface.** Pill, popover, `BackupLog`. Driven by phase 2, so it
   can be built and demonstrated against the local target with faults injected
   by the mock.
4. **Drive.** `DriveBackupTarget`, auth, secure token storage. Last, because it
   carries every new dependency and the only platform risk. By this point
   everything above it is already proven.

Phase 1 also answers the Linux build question in
[Authentication](#authentication) at the cheapest possible moment — before
`google_sign_in` is added at all.

## Open questions

1. **Internet at church** — assumption 1. Blocking for the offline-queue
   decision, nothing else.
2. **Device label** — how does a machine know it is "Mac mini (church)"? A
   settings field the operator fills in once is the cheap answer.
3. **First-run adoption** — an existing install has local config and Drive has
   nothing. Push local up on first sign-in, or ask? Pushing silently is
   probably right, given nothing can be lost.
4. **Does the status surface absorb device faults later?** Assumption 2 says
   not yet. The three known silent failures — socket drop still reading Live,
   permanent ACK desync, wedged camera — are worse than any backup fault
   because they happen during a service. If they are ever going to move here,
   `BackupFailure` should become a subtype of a broader `AppFault` before the
   log format is fixed, rather than after.

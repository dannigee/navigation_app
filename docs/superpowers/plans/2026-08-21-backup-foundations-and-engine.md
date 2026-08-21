# Backup Foundations and Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete, fully-tested configuration backup engine — canonical serialization, a transactional import contract, and the whole sync protocol — running against an in-memory mock, with no new dependencies and nothing user-visible yet.

**Architecture:** Eight static `SharedPreferences` stores gain a single mutation notifier so changes can be observed. `ConfigBundle` gains a schema version, canonical (key-sorted) serialization, and validation. Imports become transactional via a write-ahead rollback journal. `BackupService` sits above a `BackupTargetAbstract` and owns the entire protocol — single-flight queueing, pull branches, push with ancestry, pointer transitions, retry backoff — verified end to end against `MockBackupTarget`.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `shared_preferences` ^2.3.0, `flutter_test`, `mocktail` ^1.0.0. No new dependencies in this plan.

**Spec:** `docs/superpowers/specs/2026-08-21-drive-backup-and-status-surface-design.md`

## Global Constraints

- **No new pubspec dependencies in this plan.** Phase 4 (Drive) adds them; nothing here may.
- **Everything must build and test on Linux**, so John can work on all of it. No `dart:io` beyond what already exists, no Apple-only APIs.
- Dart SDK floor `>=3.11.0`, Flutter `>=3.38.0` — unchanged from `pubspec.lock`.
- All persistence goes through `SharedPreferences`, matching every existing store.
- Every test file uses `SharedPreferences.setMockInitialValues({})` in `setUp`, matching `test/stores_test.dart:15-17`.
- `flutter analyze` must be clean after every task.
- Faults thrown across the backup boundary are always `AppFault`, never raw exceptions.
- Existing behaviour that is *not* bundle-owned must not change. The manual export/import UI (`settings_dialog.dart:179-248`) stays wired to the existing `ConfigBundle.writeToPath`/`readFromPath`.

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `lib/services/backup/canonical_json.dart` | Recursive key-sorted JSON encoding. Pure function, no I/O. |
| `lib/services/backup/app_fault.dart` | `AppFault`, `FaultDomain`, `BackupFailureKind`, retry classification. |
| `lib/services/backup/backup_revision.dart` | Immutable revision metadata including ancestry. |
| `lib/services/backup/abstract/backup_target_abstract.dart` | The storage interface. |
| `lib/services/backup/mock/mock_backup_target.dart` | In-memory target, scriptable to fail and to simulate a concurrent writer. |
| `lib/services/backup/config_mutation_notifier.dart` | The change source: a durable generation counter plus a broadcast stream. |
| `lib/services/backup/restore_journal.dart` | Write-ahead journal making multi-key import transactional. |
| `lib/services/backup/backup_pointer.dart` | Provenance pointer + target identity + recorded hash, and its transitions. |
| `lib/services/backup/backup_service.dart` | The engine: single-flight, pull, push, retry. |

**Modified:**

| File | Change |
|---|---|
| `lib/services/config_bundle.dart` | Add `schemaVersion`; canonical serialization; validation; full-replace import; delegate apply to the journal. |
| `lib/services/position_store.dart`, `people_store.dart`, `service_store.dart`, `height_range_store.dart`, `operator_store.dart`, `preset_name_store.dart`, `visibility_store.dart`, `device_config_store.dart` | One line each: notify the mutation notifier after a successful write. |
| `test/config_bundle_test.dart` | Update the two tests that encode the old permissive behaviour. |

---

## Phase 0 — Spike

### Task 1: Platform build spike

**Test-policy class: spike.** No tests. The deliverable is an answer written down, and any code produced is throwaway.

**Files:**
- Create: `docs/superpowers/spikes/2026-08-21-google-signin-platform-spike.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a go/no-go answer that phase 4 depends on. Nothing in phases 1–3 imports anything from this task.

The spec asserts that phases 1–3 need no Apple-only dependency and that John can build them on Linux. That is true *of this plan*. What is not yet known is whether adding `google_sign_in` in phase 4 breaks `flutter run -d linux`, and finding out after building three phases on that assumption is the expensive order.

- [ ] **Step 1: Record the baseline**

```bash
cd /Users/danielgreig/Desktop/navigation_app
git status --short          # expect clean
flutter analyze 2>&1 | tail -3
flutter test 2>&1 | tail -3
```

Expected: analyze clean, all tests pass. Write both numbers into the spike doc.

- [ ] **Step 2: Add the dependency temporarily**

```bash
git checkout -b spike/google-signin-platform
```

Add to `pubspec.yaml` under `dependencies:` (after `shared_preferences`):

```yaml
  google_sign_in: ^7.2.0
```

Then:

```bash
flutter pub get 2>&1 | tail -5
```

- [ ] **Step 3: Answer the three questions**

```bash
flutter build linux --debug 2>&1 | tail -20
flutter build macos --debug 2>&1 | tail -20
flutter analyze 2>&1 | tail -5
```

Record verbatim in the spike doc, for each: pass or fail, and the exact error if it fails. The Linux one is the question this spike exists for — a federated plugin with no Linux implementation usually builds and throws `MissingPluginException` at call time, but that must be observed rather than assumed.

- [ ] **Step 4: Record the Apple setup requirements**

Confirm by inspection and note in the doc, with the current state of each:

```bash
grep -c "CFBundleURLTypes" macos/Runner/Info.plist ios/Runner/Info.plist    # expect 0 0
grep -c "keychain-access-groups" macos/Runner/*.entitlements                # expect 0
```

The spec requires all three before phase 4 can work. This step only proves they are absent and records what must be added.

- [ ] **Step 5: Revert completely**

```bash
git checkout -- pubspec.yaml pubspec.lock
flutter pub get
git status --short          # expect clean apart from the spike doc
```

- [ ] **Step 6: Commit the answer, not the code**

```bash
git checkout main
git branch -D spike/google-signin-platform
git add docs/superpowers/spikes/2026-08-21-google-signin-platform-spike.md
git commit -m "docs: spike result for google_sign_in platform support"
```

---

## Phase 1 — Foundations

### Task 2: Canonical JSON

**Test-policy class: trust contract.** Behavioral tests through the public function. This is the piece the entire hash guard rests on: if two machines with identical config produce different bytes, every sweep uploads and every comparison conflicts.

**Files:**
- Create: `lib/services/backup/canonical_json.dart`
- Test: `test/backup/canonical_json_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `String canonicalJsonEncode(Object? value)` and `String canonicalHash(Object? value)` returning a lowercase hex SHA-256 of the canonical encoding.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/canonical_json_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';

void main() {
  group('canonicalJsonEncode', () {
    test('sorts top-level keys regardless of insertion order', () {
      final a = <String, dynamic>{'b': 1, 'a': 2};
      final b = <String, dynamic>{'a': 2, 'b': 1};
      expect(canonicalJsonEncode(a), canonicalJsonEncode(b));
      expect(canonicalJsonEncode(a), '{"a":2,"b":1}');
    });

    test('sorts nested map keys too', () {
      final a = <String, dynamic>{
        'outer': {'z': 1, 'y': 2}
      };
      final b = <String, dynamic>{
        'outer': {'y': 2, 'z': 1}
      };
      expect(canonicalJsonEncode(a), canonicalJsonEncode(b));
    });

    test('sorts maps nested inside lists', () {
      final a = <String, dynamic>{
        'items': [
          {'q': 1, 'p': 2}
        ]
      };
      final b = <String, dynamic>{
        'items': [
          {'p': 2, 'q': 1}
        ]
      };
      expect(canonicalJsonEncode(a), canonicalJsonEncode(b));
    });

    test('preserves list order, which is meaningful', () {
      expect(canonicalJsonEncode({'l': [1, 2]}),
          isNot(canonicalJsonEncode({'l': [2, 1]})));
    });

    test('round-trips through jsonDecode unchanged in value', () {
      final original = <String, dynamic>{
        'b': [1, 2],
        'a': {'z': 'x'}
      };
      expect(jsonDecode(canonicalJsonEncode(original)), original);
    });
  });

  group('canonicalHash', () {
    test('is equal for equal content in different key order', () {
      expect(canonicalHash({'b': 1, 'a': 2}), canonicalHash({'a': 2, 'b': 1}));
    });

    test('differs when content differs', () {
      expect(canonicalHash({'a': 1}), isNot(canonicalHash({'a': 2})));
    });

    test('is 64 lowercase hex characters', () {
      expect(canonicalHash({'a': 1}), matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/canonical_json_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'navigation_app/services/backup/canonical_json.dart'`

- [ ] **Step 3: Implement**

Create `lib/services/backup/canonical_json.dart`:

```dart
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Encodes [value] to JSON with every map's keys sorted, recursively.
///
/// Two structurally equal values always produce byte-identical output, which
/// is what makes a content hash comparable across machines. `jsonEncode`
/// alone preserves insertion order, and `SharedPreferences.getKeys()` returns
/// an unordered `Set`, so bundles built on two machines from identical data
/// would otherwise hash differently.
String canonicalJsonEncode(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    value.forEach((k, v) => sorted['$k'] = _canonicalize(v));
    return sorted;
  }
  if (value is List) {
    // List order is meaningful — service order, position order — so it is
    // preserved. Only maps are reordered.
    return value.map(_canonicalize).toList();
  }
  return value;
}

/// Lowercase hex SHA-256 of [value]'s canonical encoding.
String canonicalHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJsonEncode(value))).toString();
```

- [ ] **Step 4: Confirm `crypto` is already available**

`crypto` is a transitive dependency of `flutter_test`, but transitive availability is not a contract. Make it explicit:

```bash
grep -n "^  crypto:" pubspec.yaml || echo "NOT DECLARED"
grep -n "^  crypto:" pubspec.lock
```

If not declared, add to `pubspec.yaml` under `dependencies:`:

```yaml
  crypto: ^3.0.3
```

Then `flutter pub get`. This is the one dependency addition this plan permits, because hashing is load-bearing and relying on a transitive package is how builds break later. It is pure Dart and adds no platform risk.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/backup/canonical_json_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/canonical_json.dart test/backup/canonical_json_test.dart pubspec.yaml pubspec.lock
git commit -m "feat(backup): canonical key-sorted JSON encoding and hashing"
```

---

### Task 3: The fault type

**Test-policy class: trust contract.** The retry classification is behaviour other code branches on, so it gets behavioral tests. The enum itself does not.

**Files:**
- Create: `lib/services/backup/app_fault.dart`
- Test: `test/backup/app_fault_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppFault` with `domain`, `kind`, `message`, `cause`, `isRetryable`, `needsUserAction`, `fingerprint`; enums `FaultDomain { backup, roland, camera }` and `BackupFailureKind`.

The type is general from day one because the log is persisted; changing an entry's shape once it holds a year of real entries means migrating saved data. Only `FaultDomain.backup` is used in this plan.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/app_fault_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';

void main() {
  group('AppFault retry classification', () {
    test('offline, rateLimited and transientServer retry automatically', () {
      for (final k in [
        BackupFailureKind.offline,
        BackupFailureKind.rateLimited,
        BackupFailureKind.transientServer,
      ]) {
        final f = AppFault.backup(k, 'x');
        expect(f.isRetryable, isTrue, reason: '$k should be retryable');
        expect(f.needsUserAction, isFalse, reason: '$k needs no human');
      }
    });

    test('authExpired, permissionDenied, storageFull, unsupportedSchema, '
        'targetMissing and malformedRemote need a human and do not retry', () {
      for (final k in [
        BackupFailureKind.authExpired,
        BackupFailureKind.permissionDenied,
        BackupFailureKind.storageFull,
        BackupFailureKind.unsupportedSchema,
        BackupFailureKind.targetMissing,
        BackupFailureKind.malformedRemote,
      ]) {
        final f = AppFault.backup(k, 'x');
        expect(f.isRetryable, isFalse, reason: '$k must not spin');
        expect(f.needsUserAction, isTrue, reason: '$k needs a human');
      }
    });

    test('conflict is a question, not a failure: no retry, needs a human', () {
      final f = AppFault.backup(BackupFailureKind.conflict, 'x');
      expect(f.isRetryable, isFalse);
      expect(f.needsUserAction, isTrue);
    });

    test('unknown retries but only on the slow sweep', () {
      final f = AppFault.backup(BackupFailureKind.unknown, 'x');
      expect(f.isRetryable, isTrue);
      expect(f.sweepOnly, isTrue,
          reason: 'a tight loop around a permanent bug burns battery forever');
    });
  });

  group('fingerprint', () {
    test('ignores the message, so varying detail still collapses', () {
      final a = AppFault.backup(BackupFailureKind.offline,
          'SocketException: timed out after 5002ms', operation: 'push');
      final b = AppFault.backup(BackupFailureKind.offline,
          'SocketException: timed out after 7113ms', operation: 'push');
      expect(a.fingerprint, b.fingerprint);
    });

    test('distinguishes operation', () {
      final push = AppFault.backup(BackupFailureKind.offline, 'x',
          operation: 'push');
      final pull = AppFault.backup(BackupFailureKind.offline, 'x',
          operation: 'pull');
      expect(push.fingerprint, isNot(pull.fingerprint));
    });

    test('distinguishes domain', () {
      final backup =
          AppFault.backup(BackupFailureKind.offline, 'x', operation: 'push');
      final roland = AppFault(
          domain: FaultDomain.roland,
          kind: 'disconnected',
          message: 'x',
          operation: 'push');
      expect(backup.fingerprint, isNot(roland.fingerprint));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/app_fault_test.dart`
Expected: FAIL — package not resolvable.

- [ ] **Step 3: Implement**

Create `lib/services/backup/app_fault.dart`:

```dart
/// Which subsystem a fault came from.
///
/// Only [backup] is produced today. [roland] and [camera] exist because the
/// fault log is persisted, and widening a stored entry's shape later means
/// migrating saved data. Phase 5 fills them in.
enum FaultDomain { backup, roland, camera }

enum BackupFailureKind {
  offline,
  authExpired,
  permissionDenied,
  rateLimited,
  transientServer,
  storageFull,
  conflict,
  unsupportedSchema,
  malformedRemote,
  targetMissing,
  unknown,
}

/// Any failure or warning the app wants to surface.
class AppFault implements Exception {
  final FaultDomain domain;

  /// Stable, domain-specific identifier. Never free text — the log collapses
  /// on it, so it must not vary between two occurrences of the same problem.
  final String kind;

  /// Human-readable, shown in the popover. May contain varying detail.
  final String message;

  /// Which operation was in flight: 'push', 'pull', 'prune'.
  final String? operation;

  final Object? cause;

  const AppFault({
    required this.domain,
    required this.kind,
    required this.message,
    this.operation,
    this.cause,
  });

  factory AppFault.backup(
    BackupFailureKind kind,
    String message, {
    String? operation,
    Object? cause,
  }) =>
      AppFault(
        domain: FaultDomain.backup,
        kind: kind.name,
        message: message,
        operation: operation,
        cause: cause,
      );

  static const _retryable = {'offline', 'rateLimited', 'transientServer'};
  static const _sweepOnly = {'unknown'};
  static const _needsHuman = {
    'authExpired',
    'permissionDenied',
    'storageFull',
    'unsupportedSchema',
    'targetMissing',
    'malformedRemote',
    'conflict',
  };

  /// Whether waiting and trying again can fix this without a human.
  bool get isRetryable => _retryable.contains(kind) || sweepOnly;

  /// Retryable, but only on the slow periodic sweep. A tight backoff loop
  /// around a permanent programmer error would spin forever.
  bool get sweepOnly => _sweepOnly.contains(kind);

  bool get needsUserAction => _needsHuman.contains(kind);

  /// Log collapsing key. Deliberately excludes [message]: real exception text
  /// carries timeouts and request ids that differ on every occurrence, so
  /// collapsing on it collapses nothing and a retry storm evicts the entry
  /// that mattered.
  String get fingerprint => '${domain.name}/$kind/${operation ?? "-"}';

  @override
  String toString() => 'AppFault(${domain.name}/$kind): $message';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/app_fault_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/app_fault.dart test/backup/app_fault_test.dart
git commit -m "feat(backup): AppFault with retry classification and stable fingerprint"
```

---

### Task 4: Revision metadata and the target interface

**Test-policy class: trust contract** for `MockBackupTarget` (it is a real implementation whose behaviour later tasks depend on); the abstract class itself has no behaviour to test.

**Files:**
- Create: `lib/services/backup/backup_revision.dart`
- Create: `lib/services/backup/abstract/backup_target_abstract.dart`
- Create: `lib/services/backup/mock/mock_backup_target.dart`
- Test: `test/backup/mock_backup_target_test.dart`

**Interfaces:**
- Consumes: `AppFault`, `BackupFailureKind` (Task 3).
- Produces: `BackupRevision`; `BackupTargetAbstract` with `put`, `latest`, `list`, `fetch`, `prune`; `MockBackupTarget` with `failNextWith`, `concurrentWriterBeforePut`, and `revisions`.

Follows the `abstract/` + `mock/` split already used by `RolandServiceAbstract` and `MockRolandService`.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/mock_backup_target_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';

void main() {
  late MockBackupTarget target;

  setUp(() => target = MockBackupTarget());

  test('latest returns null when empty', () async {
    expect(await target.latest(), isNull);
  });

  test('put stores a revision and latest returns it', () async {
    final rev = await target.put('{"a":1}',
        contentHash: 'h1', parentRevisionId: null, deviceLabel: 'Mac mini');
    final latest = await target.latest();
    expect(latest!.id, rev.id);
    expect(latest.contentHash, 'h1');
    expect(latest.deviceLabel, 'Mac mini');
    expect(latest.parentRevisionId, isNull);
  });

  test('put never overwrites: two puts make two revisions', () async {
    final a = await target.put('{"a":1}',
        contentHash: 'h1', parentRevisionId: null, deviceLabel: 'm');
    final b = await target.put('{"a":2}',
        contentHash: 'h2', parentRevisionId: a.id, deviceLabel: 'm');
    expect(a.id, isNot(b.id));
    expect((await target.list()).length, 2);
  });

  test('list is newest first', () async {
    final a = await target.put('{"a":1}',
        contentHash: 'h1', parentRevisionId: null, deviceLabel: 'm');
    final b = await target.put('{"a":2}',
        contentHash: 'h2', parentRevisionId: a.id, deviceLabel: 'm');
    expect((await target.list()).map((r) => r.id).toList(), [b.id, a.id]);
  });

  test('fetch returns the exact body that was put', () async {
    final rev = await target.put('{"a":1}',
        contentHash: 'h1', parentRevisionId: null, deviceLabel: 'm');
    expect(await target.fetch(rev), '{"a":1}');
  });

  test('failNextWith makes exactly the next call throw', () async {
    target.failNextWith(
        AppFault.backup(BackupFailureKind.offline, 'no network'));
    await expectLater(target.latest(), throwsA(isA<AppFault>()));
    expect(await target.latest(), isNull, reason: 'only the next call fails');
  });

  test('concurrentWriterBeforePut simulates another machine winning the race',
      () async {
    final base = await target.put('{"a":1}',
        contentHash: 'h1', parentRevisionId: null, deviceLabel: 'mac');
    target.concurrentWriterBeforePut(
        body: '{"a":9}', contentHash: 'h9', parentRevisionId: base.id,
        deviceLabel: 'ipad');

    final mine = await target.put('{"a":2}',
        contentHash: 'h2', parentRevisionId: base.id, deviceLabel: 'mac');

    final all = await target.list();
    final siblings =
        all.where((r) => r.parentRevisionId == base.id).toList();
    expect(siblings.length, 2, reason: 'a fork now exists');
    expect(siblings.map((r) => r.id), contains(mine.id));
  });

  test('prune keeps a revision that is recent even when beyond keepCount',
      () async {
    for (var i = 0; i < 5; i++) {
      await target.put('{"a":$i}',
          contentHash: 'h$i', parentRevisionId: null, deviceLabel: 'm');
    }
    await target.prune(keepCount: 2, keepFor: const Duration(days: 90));
    expect((await target.list()).length, 5,
        reason: 'deletion requires BOTH beyond count AND older than keepFor');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/mock_backup_target_test.dart`
Expected: FAIL — package not resolvable.

- [ ] **Step 3: Implement the revision type**

Create `lib/services/backup/backup_revision.dart`:

```dart
/// Immutable metadata for one stored revision.
class BackupRevision {
  /// Storage-assigned id. On Drive, the file id.
  final String id;
  final String filename;

  /// Server time where the target has one. Never the client's clock: a
  /// machine with a wrong clock would otherwise choose the wrong head.
  final DateTime createdAt;

  /// SHA-256 of the canonical body. On Drive this is client-supplied
  /// metadata and must not be trusted on its own — see the spec's
  /// "Trust the body, not the metadata".
  final String contentHash;

  /// The revision this one was edited from. Null for the first revision.
  /// This is what makes fork detection and the pull ancestry test possible.
  final String? parentRevisionId;

  final int sizeBytes;

  /// Self-declared machine name. A usability aid for the conflict UI, not an
  /// audit trail.
  final String deviceLabel;

  const BackupRevision({
    required this.id,
    required this.filename,
    required this.createdAt,
    required this.contentHash,
    required this.parentRevisionId,
    required this.sizeBytes,
    required this.deviceLabel,
  });
}
```

- [ ] **Step 4: Implement the interface**

Create `lib/services/backup/abstract/backup_target_abstract.dart`:

```dart
import '../backup_revision.dart';

/// Append-only revision storage.
///
/// Every method throws `AppFault` and nothing else; implementations translate
/// their own exceptions at this boundary.
abstract class BackupTargetAbstract {
  /// Uploads a new immutable revision. Never overwrites an existing one.
  Future<BackupRevision> put(
    String json, {
    required String contentHash,
    required String? parentRevisionId,
    required String deviceLabel,
  });

  /// Newest revision's metadata, or null when the store is empty.
  /// Must not download the body.
  Future<BackupRevision?> latest();

  /// Revisions, newest first.
  Future<List<BackupRevision>> list({int limit = 50});

  /// Downloads a revision's body, verified against a trusted checksum.
  Future<String> fetch(BackupRevision revision);

  /// Deletes revisions that are BOTH outside the newest [keepCount] AND
  /// older than [keepFor]. Either condition alone is not enough.
  Future<void> prune({required int keepCount, required Duration keepFor});
}
```

- [ ] **Step 5: Implement the mock**

Create `lib/services/backup/mock/mock_backup_target.dart`:

```dart
import '../abstract/backup_target_abstract.dart';
import '../app_fault.dart';
import '../backup_revision.dart';

/// In-memory target for tests. Scriptable to fail, and to simulate another
/// machine writing between a caller's `latest()` and its `put()`.
class MockBackupTarget implements BackupTargetAbstract {
  final List<BackupRevision> revisions = [];
  final Map<String, String> _bodies = {};

  AppFault? _nextFailure;
  Map<String, String?>? _pendingConcurrentWrite;
  int _seq = 0;
  DateTime _clock = DateTime.utc(2026, 1, 1);

  /// The next call to any method throws [fault], once.
  void failNextWith(AppFault fault) => _nextFailure = fault;

  /// Insert a revision by another writer immediately before the next [put],
  /// reproducing the time-of-check/time-of-use race that no compare-and-swap
  /// can prevent on Drive.
  void concurrentWriterBeforePut({
    required String body,
    required String contentHash,
    required String? parentRevisionId,
    required String deviceLabel,
  }) {
    _pendingConcurrentWrite = {
      'body': body,
      'contentHash': contentHash,
      'parentRevisionId': parentRevisionId,
      'deviceLabel': deviceLabel,
    };
  }

  void _maybeFail() {
    final f = _nextFailure;
    if (f != null) {
      _nextFailure = null;
      throw f;
    }
  }

  DateTime _tick() {
    _clock = _clock.add(const Duration(seconds: 1));
    return _clock;
  }

  BackupRevision _insert(
    String json,
    String contentHash,
    String? parentRevisionId,
    String deviceLabel,
  ) {
    final id = 'rev-${++_seq}';
    final created = _tick();
    final rev = BackupRevision(
      id: id,
      filename: 'nav_config_${created.toIso8601String()}.json',
      createdAt: created,
      contentHash: contentHash,
      parentRevisionId: parentRevisionId,
      sizeBytes: json.length,
      deviceLabel: deviceLabel,
    );
    revisions.add(rev);
    _bodies[id] = json;
    return rev;
  }

  @override
  Future<BackupRevision> put(
    String json, {
    required String contentHash,
    required String? parentRevisionId,
    required String deviceLabel,
  }) async {
    _maybeFail();
    final pending = _pendingConcurrentWrite;
    if (pending != null) {
      _pendingConcurrentWrite = null;
      _insert(pending['body']!, pending['contentHash']!,
          pending['parentRevisionId'], pending['deviceLabel']!);
    }
    return _insert(json, contentHash, parentRevisionId, deviceLabel);
  }

  @override
  Future<BackupRevision?> latest() async {
    _maybeFail();
    if (revisions.isEmpty) return null;
    return (await list()).first;
  }

  @override
  Future<List<BackupRevision>> list({int limit = 50}) async {
    _maybeFail();
    final sorted = [...revisions]
      ..sort((a, b) {
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return sorted.take(limit).toList();
  }

  @override
  Future<String> fetch(BackupRevision revision) async {
    _maybeFail();
    final body = _bodies[revision.id];
    if (body == null) {
      throw AppFault.backup(
          BackupFailureKind.targetMissing, 'revision ${revision.id} is gone');
    }
    return body;
  }

  @override
  Future<void> prune({
    required int keepCount,
    required Duration keepFor,
  }) async {
    _maybeFail();
    final ordered = await list(limit: 1 << 30);
    final cutoff = _clock.subtract(keepFor);
    for (var i = keepCount; i < ordered.length; i++) {
      final r = ordered[i];
      if (r.createdAt.isBefore(cutoff)) {
        revisions.remove(r);
        _bodies.remove(r.id);
      }
    }
  }
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/backup/mock_backup_target_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 7: Commit**

```bash
git add lib/services/backup/backup_revision.dart \
        lib/services/backup/abstract/backup_target_abstract.dart \
        lib/services/backup/mock/mock_backup_target.dart \
        test/backup/mock_backup_target_test.dart
git commit -m "feat(backup): revision metadata, target interface, and scriptable mock"
```

---

### Task 5: The mutation notifier

**Test-policy class: trust contract** for the notifier itself. The eight store call sites are **wiring** and get one thin test proving the wiring exists, not eight.

**Files:**
- Create: `lib/services/backup/config_mutation_notifier.dart`
- Modify: `lib/services/position_store.dart:18-22`, `people_store.dart:18-22`, `service_store.dart:18-22`, `height_range_store.dart:18-22`, `operator_store.dart:25-31`, `preset_name_store.dart:18-29`, `visibility_store.dart:25-32`, `device_config_store.dart:39-46`
- Test: `test/backup/config_mutation_notifier_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `ConfigMutationNotifier.instance` with `Future<void> notify()`, `Stream<int> get onMutated`, `Future<int> generation()`, `Future<void> markSynced(int generation)`, `Future<bool> isDirty()`.

Nothing in this codebase can currently report that config changed. All eight stores are static classes over `SharedPreferences` with no stream or notifier, and the spec is explicit that a hash guard cannot substitute: **a guard suppresses a redundant write after a trigger; it cannot manufacture a trigger that never fired.**

**Deliberate substitution from the spec:** the spec says to persist "the dirty hash" at mutation time. This uses a monotonic generation counter instead. It answers the same question — is local ahead of what was last pushed — and is O(1) at mutation time where hashing the whole bundle is O(bundle) on every keystroke-driven save. Dirtiness is `generation != lastSyncedGeneration`.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/config_mutation_notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/position_store.dart';

void main() {
  setUp(() async {
    await ConfigMutationNotifier.instance.resetForTest();
  });

  test('starts clean at generation zero', () async {
    expect(await ConfigMutationNotifier.instance.generation(), 0);
    expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);
  });

  test('notify increments the generation and makes it dirty', () async {
    await ConfigMutationNotifier.instance.notify();
    expect(await ConfigMutationNotifier.instance.generation(), 1);
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue);
  });

  test('markSynced clears dirty for that generation only', () async {
    await ConfigMutationNotifier.instance.notify();
    await ConfigMutationNotifier.instance.markSynced(1);
    expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);

    await ConfigMutationNotifier.instance.notify();
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'a later edit re-dirties');
  });

  test('markSynced for a stale generation does not clear a newer edit',
      () async {
    await ConfigMutationNotifier.instance.notify(); // gen 1
    await ConfigMutationNotifier.instance.notify(); // gen 2
    await ConfigMutationNotifier.instance.markSynced(1);
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'an in-flight push must not clear an edit made during it');
  });

  test('dirty state survives a restart, because it is persisted', () async {
    await ConfigMutationNotifier.instance.notify();
    await ConfigMutationNotifier.instance.reloadForTest();
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'an in-memory debounce dies with the app; intent must not');
  });

  test('emits the new generation on the stream', () async {
    final seen = <int>[];
    final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);
    await ConfigMutationNotifier.instance.notify();
    await ConfigMutationNotifier.instance.notify();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [1, 2]);
  });

  group('store wiring', () {
    test('a store write notifies', () async {
      final before = await ConfigMutationNotifier.instance.generation();
      await PositionStore.saveAll([const Position(id: 'p1', name: 'Ambo')]);
      expect(await ConfigMutationNotifier.instance.generation(), before + 1,
          reason: 'stores must report their own mutations');
    });
  });
}
```

> The `Position` constructor arguments above must match `lib/models/position.dart`. Open it and adjust the literal if the field names differ; the assertion is what matters, not the fixture.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/config_mutation_notifier_test.dart`
Expected: FAIL — package not resolvable.

- [ ] **Step 3: Implement the notifier**

Create `lib/services/backup/config_mutation_notifier.dart`:

```dart
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// The single place that learns config changed.
///
/// Every bundle-owned write calls [notify]. The generation counter is
/// persisted at the moment of mutation, so pending intent survives an iOS
/// suspension or a kill — a lifecycle flush is then an optimisation rather
/// than the thing correctness rests on.
class ConfigMutationNotifier {
  static final ConfigMutationNotifier instance = ConfigMutationNotifier._();
  ConfigMutationNotifier._();

  static const _generationKey = 'backup_mutation_generation';
  static const _syncedKey = 'backup_synced_generation';

  final _controller = StreamController<int>.broadcast();

  /// Emits the new generation each time config changes.
  Stream<int> get onMutated => _controller.stream;

  Future<int> generation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_generationKey) ?? 0;
  }

  Future<int> syncedGeneration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_syncedKey) ?? 0;
  }

  Future<bool> isDirty() async =>
      await generation() != await syncedGeneration();

  Future<void> notify() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_generationKey) ?? 0) + 1;
    await prefs.setInt(_generationKey, next);
    _controller.add(next);
  }

  /// Records that [generation] has been durably stored at the target.
  ///
  /// Never clears a generation newer than the one that was pushed: an edit
  /// made while a push was in flight must stay dirty.
  Future<void> markSynced(int generation) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_syncedKey) ?? 0;
    if (generation > current) {
      await prefs.setInt(_syncedKey, generation);
    }
  }

  /// Test seam: clears both counters.
  Future<void> resetForTest() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
  }

  /// Test seam: proves state is read from storage, not memory.
  Future<void> reloadForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
  }
}
```

- [ ] **Step 4: Wire the eight stores**

In each of the following, add the import and one `await` immediately after the existing `prefs.setString(...)` / `prefs.setInt(...)` write, before the method returns:

```dart
import 'backup/config_mutation_notifier.dart';
```

```dart
    await ConfigMutationNotifier.instance.notify();
```

Apply to exactly these methods:

| File | Method |
|---|---|
| `position_store.dart` | `saveAll` |
| `people_store.dart` | `saveAll` |
| `service_store.dart` | `saveAll` |
| `height_range_store.dart` | `saveAll` |
| `operator_store.dart` | `saveAll` **and** `saveActiveId` |
| `preset_name_store.dart` | `save` |
| `visibility_store.dart` | `save` |
| `device_config_store.dart` | `save` |

Do **not** wire it into `ConfigBundle.saveToStores` — an import is not a user mutation, and notifying there would make every restore immediately dirty and trigger a push of what was just pulled.

- [ ] **Step 5: Verify every store is wired**

```bash
grep -L "ConfigMutationNotifier" \
  lib/services/position_store.dart lib/services/people_store.dart \
  lib/services/service_store.dart lib/services/height_range_store.dart \
  lib/services/operator_store.dart lib/services/preset_name_store.dart \
  lib/services/visibility_store.dart lib/services/device_config_store.dart
```

Expected: no output. Any filename printed is a store that would silently never be backed up.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/backup/config_mutation_notifier_test.dart`
Expected: PASS, 7 tests.

Run: `flutter test && flutter analyze`
Expected: full suite still green, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/services/backup/config_mutation_notifier.dart \
        lib/services/*_store.dart \
        test/backup/config_mutation_notifier_test.dart
git commit -m "feat(backup): mutation notifier with durable generation counter"
```

---

### Task 6: Schema version and validation

**Test-policy class: trust contract.** The v0/v1 matrix decides whether importing an old export destroys preset names, so it is tested exhaustively.

**Files:**
- Modify: `lib/services/config_bundle.dart:19-50` (add `schemaVersion`), `:52-64` (`toJson`), `:66-101` (`fromJson`)
- Test: `test/backup/config_bundle_schema_test.dart`
- Modify: `test/config_bundle_test.dart:110-118` and `:131-136`

**Interfaces:**
- Consumes: `AppFault` (Task 3).
- Produces: `ConfigBundle.schemaVersion` (`int`), `ConfigBundle.currentSchemaVersion` (`= 1`), and `ConfigBundle.fromJsonValidated(Map<String, dynamic>)` which throws `AppFault`.

The matrix, copied from the spec so the implementer does not have to hold two documents open:

| | **v0 (no `schemaVersion` key)** | **v1+** |
|---|---|---|
| `positions`, `people`, `services` | Required. Absent → `malformedRemote`. | Required. Absent → `malformedRemote`. |
| `heightRanges` | Absent → preserve existing. | Required. Absent → `malformedRemote`. |
| `presetNames`, `visibilities` | Absent → **preserve** existing keys. | Absent → treat as `{}` and **delete** all existing keys. |
| `rolandIp`, `cameras`, `operators` | Absent → preserve. | Absent → **delete/reset** to defaults. |
| `schemaVersion` > current | n/a | `unsupportedSchema`. |

- [ ] **Step 1: Write the failing tests**

Create `test/backup/config_bundle_schema_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/app_fault_import_shim.dart'
    if (dart.library.io) 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/config_bundle.dart';

Map<String, dynamic> _core() => {
      'positions': <dynamic>[],
      'people': <dynamic>[],
      'services': <dynamic>[],
    };

void main() {
  group('version detection', () {
    test('a bundle with no schemaVersion is legacy v0, not malformed', () {
      final b = ConfigBundle.fromJsonValidated(_core());
      expect(b.schemaVersion, 0);
    });

    test('an explicit version is honoured', () {
      final b = ConfigBundle.fromJsonValidated(
          {..._core(), 'schemaVersion': 1, 'heightRanges': <dynamic>[]});
      expect(b.schemaVersion, 1);
    });

    test('a newer version than this build is refused', () {
      expect(
        () => ConfigBundle.fromJsonValidated({..._core(), 'schemaVersion': 99}),
        throwsA(predicate((e) =>
            e is AppFault &&
            e.kind == BackupFailureKind.unsupportedSchema.name)),
      );
    });
  });

  group('required fields', () {
    test('{} is malformed, not an empty bundle that wipes four stores', () {
      expect(
        () => ConfigBundle.fromJsonValidated(<String, dynamic>{}),
        throwsA(predicate((e) =>
            e is AppFault &&
            e.kind == BackupFailureKind.malformedRemote.name)),
      );
    });

    for (final missing in ['positions', 'people', 'services']) {
      test('v0 missing $missing is malformed', () {
        final json = _core()..remove(missing);
        expect(
          () => ConfigBundle.fromJsonValidated(json),
          throwsA(predicate((e) =>
              e is AppFault &&
              e.kind == BackupFailureKind.malformedRemote.name)),
        );
      });
    }

    test('v1 missing heightRanges is malformed', () {
      expect(
        () => ConfigBundle.fromJsonValidated({..._core(), 'schemaVersion': 1}),
        throwsA(predicate((e) =>
            e is AppFault &&
            e.kind == BackupFailureKind.malformedRemote.name)),
      );
    });

    test('v0 missing heightRanges is fine', () {
      expect(ConfigBundle.fromJsonValidated(_core()).heightRanges, isEmpty);
    });

    test('empty lists are valid — clearing everything is a legitimate edit',
        () {
      final b = ConfigBundle.fromJsonValidated(
          {..._core(), 'schemaVersion': 1, 'heightRanges': <dynamic>[]});
      expect(b.positions, isEmpty);
    });
  });

  group('absent optional fields carry version-dependent meaning', () {
    test('v0 leaves presetNames unknown so import preserves them', () {
      final b = ConfigBundle.fromJsonValidated(_core());
      expect(b.presetNames, isNull,
          reason: 'null means unknown; {} would mean delete everything');
      expect(b.visibilities, isNull);
    });

    test('v1 treats absent presetNames as an explicit empty set', () {
      final b = ConfigBundle.fromJsonValidated(
          {..._core(), 'schemaVersion': 1, 'heightRanges': <dynamic>[]});
      expect(b.presetNames, isNotNull);
      expect(b.presetNames, isEmpty);
    });
  });

  test('toJson always stamps the current version', () {
    final json = ConfigBundle.fromJsonValidated(
            {..._core(), 'schemaVersion': 1, 'heightRanges': <dynamic>[]})
        .toJson();
    expect(json['schemaVersion'], ConfigBundle.currentSchemaVersion);
  });
}
```

> Replace the conditional-import line at the top with a plain
> `import 'package:navigation_app/services/backup/app_fault.dart';` — the
> conditional form above is wrong and is here only to be deleted. Written this
> way deliberately so a copy-paste without reading fails loudly at compile
> time rather than silently.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/config_bundle_schema_test.dart`
Expected: FAIL to compile on the import line, then on `fromJsonValidated`.

- [ ] **Step 3: Change the presetNames and visibilities fields to nullable**

In `lib/services/config_bundle.dart`, change these two fields and their constructor parameters so absence is distinguishable from emptiness:

```dart
  /// Preset/macro names keyed by device storage key, then item index string.
  /// **Null means "not present in this bundle"** — a v0 legacy file — and
  /// import must then preserve whatever is on the machine. An empty map means
  /// "explicitly none", and import deletes every existing key.
  final Map<String, Map<String, String>>? presetNames;

  /// Item visibility, with the same null-versus-empty distinction.
  final Map<String, Map<String, String>>? visibilities;
```

Update the constructor to `this.presetNames` and `this.visibilities` with no defaults, and add:

```dart
  /// Schema version of the source document. 0 means a legacy file written
  /// before versioning existed.
  final int schemaVersion;

  static const int currentSchemaVersion = 1;
```

adding `required this.schemaVersion` to the constructor. Then fix the two `toJson` lines to always emit both keys and the version:

```dart
  Map<String, dynamic> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'positions': positions.map((p) => p.toJson()).toList(),
        'people': people.map((p) => p.toJson()).toList(),
        'services': services.map((s) => s.toJson()).toList(),
        'heightRanges': heightRanges.map((r) => r.toJson()).toList(),
        'presetNames': presetNames ?? const <String, Map<String, String>>{},
        'visibilities': visibilities ?? const <String, Map<String, String>>{},
        if (rolandIp != null) 'rolandIp': rolandIp,
        if (cameras != null)
          'cameras': cameras!.map((c) => c.toJson()).toList(),
        if (operators != null)
          'operators': operators!.map((o) => o.toJson()).toList(),
      };
```

- [ ] **Step 4: Add the validating factory**

Add to `ConfigBundle`, alongside the existing `fromJson`:

```dart
  /// Parses and validates, throwing [AppFault] rather than silently
  /// producing an empty bundle.
  ///
  /// `ConfigBundle.fromJson({})` returns an all-empty bundle, and applying
  /// that replaces four stores with nothing. A truncated download must be a
  /// fault, not a destructive restore.
  factory ConfigBundle.fromJsonValidated(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version != null && version is! int) {
      throw AppFault.backup(
          BackupFailureKind.malformedRemote, 'schemaVersion is not an integer');
    }
    final v = (version as int?) ?? 0;
    if (v > currentSchemaVersion) {
      throw AppFault.backup(BackupFailureKind.unsupportedSchema,
          'This backup was written by a newer version of the app '
          '(schema $v, this build understands $currentSchemaVersion). '
          'Update the app to sync.');
    }

    void requireList(String field) {
      if (json[field] is! List) {
        throw AppFault.backup(BackupFailureKind.malformedRemote,
            'required field "$field" is missing or not a list');
      }
    }

    requireList('positions');
    requireList('people');
    requireList('services');
    if (v >= 1) requireList('heightRanges');

    final parsed = ConfigBundle.fromJson(json);
    return ConfigBundle(
      schemaVersion: v,
      positions: parsed.positions,
      people: parsed.people,
      services: parsed.services,
      heightRanges: parsed.heightRanges,
      presetNames: json.containsKey('presetNames')
          ? parsed.presetNames
          : (v >= 1 ? const <String, Map<String, String>>{} : null),
      visibilities: json.containsKey('visibilities')
          ? parsed.visibilities
          : (v >= 1 ? const <String, Map<String, String>>{} : null),
      rolandIp: parsed.rolandIp,
      cameras: parsed.cameras,
      operators: parsed.operators,
    );
  }
```

Add `import 'backup/app_fault.dart';` at the top of the file.

- [ ] **Step 5: Update the two tests that encode the old behaviour**

In `test/config_bundle_test.dart`, the test at `:110-118` asserts `fromJson({})` yields empty collections. That remains true of the *unvalidated* `fromJson`, so keep it but rename it so its scope is unambiguous:

```dart
    test('fromJson (unvalidated) treats missing keys as empty collections',
        () {
```

and add immediately after it:

```dart
    test('fromJsonValidated rejects {} rather than producing an empty bundle',
        () {
      expect(() => ConfigBundle.fromJsonValidated(<String, dynamic>{}),
          throwsA(isA<AppFault>()));
    });
```

The test at `:131-136` asserting `toJson` omits empty maps must be inverted, since `toJson` now always emits them:

```dart
    test('toJson always emits presetNames and visibilities, even when empty',
        () {
      final json = _full().toJson();
      expect(json.containsKey('presetNames'), isTrue);
      expect(json.containsKey('visibilities'), isTrue);
    });
```

- [ ] **Step 6: Fix every remaining construction site**

Adding a required field breaks every `ConfigBundle(...)` literal:

```bash
flutter analyze 2>&1 | grep -c "error"
grep -rn "ConfigBundle(" lib/ test/ | grep -v "fromJson\|fromStores"
```

Add `schemaVersion: ConfigBundle.currentSchemaVersion,` to each, and in `fromStores` add the same. Re-run until analyze is clean.

- [ ] **Step 7: Run to verify it passes**

Run: `flutter test test/backup/config_bundle_schema_test.dart test/config_bundle_test.dart`
Expected: PASS.

Run: `flutter test && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 8: Commit**

```bash
git add lib/services/config_bundle.dart \
        test/backup/config_bundle_schema_test.dart test/config_bundle_test.dart
git commit -m "feat(backup): schema version, validation, and the v0/v1 field matrix"
```

---

### Task 7: The rollback journal and the import contract

**Test-policy class: trust contract.** This is the highest-stakes task in the plan: it decides whether a failed import leaves the operator's configuration in one piece, and whether importing a legacy export destroys every preset name.

**Files:**
- Create: `lib/services/backup/restore_journal.dart`
- Modify: `lib/services/config_bundle.dart:155-179` (`saveToStores`)
- Test: `test/backup/restore_journal_test.dart`

**Interfaces:**
- Consumes: `ConfigBundle` with `schemaVersion` and nullable maps (Task 6).
- Produces: `RestoreJournal.capture()`, `RestoreJournal.rollbackIfPresent()`, `RestoreJournal.clear()`; and `ConfigBundle.applyTransactionally()`.

Two corrections to current behaviour, both from the spec:

1. `saveToStores` is **not** a full replace today. The preset/visibility loops only `setString` keys present in the bundle, so a device key absent from the bundle is never deleted. Under v1 it now is.
2. The apply is a series of independent writes. A failure partway leaves a hybrid, and `fromStores()` will happily upload that hybrid as a valid revision.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/restore_journal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/restore_journal.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/services/visibility_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _v1(Map<String, dynamic> extra) => {
      'schemaVersion': 1,
      'positions': <dynamic>[],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
      ...extra,
    };

Map<String, dynamic> _v0(Map<String, dynamic> extra) => {
      'positions': <dynamic>[],
      'people': <dynamic>[],
      'services': <dynamic>[],
      ...extra,
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('v1 full replacement', () {
    test('deletes preset keys absent from the incoming bundle', () async {
      await PresetNameStore.save('10.0.1.10', 3, 'Close Up');
      expect(await PresetNameStore.loadAll('10.0.1.10'), isNotEmpty);

      await ConfigBundle.fromJsonValidated(_v1({}))
          .applyTransactionally();

      expect(await PresetNameStore.loadAll('10.0.1.10'), isEmpty,
          reason: 'v1 absent means explicitly none');
    });

    test('deletes visibility keys absent from the incoming bundle', () async {
      await VisibilityStore.save('roland_10.0.1.20', 5, ItemVisibility.hide);
      await ConfigBundle.fromJsonValidated(_v1({}))
          .applyTransactionally();
      expect(await VisibilityStore.loadAll('roland_10.0.1.20'), isEmpty);
    });
  });

  group('v0 legacy preservation — the load-bearing regression', () {
    test('importing an unversioned export PRESERVES preset names', () async {
      await PresetNameStore.save('10.0.1.10', 3, 'Close Up');

      await ConfigBundle.fromJsonValidated(_v0({}))
          .applyTransactionally();

      expect(await PresetNameStore.loadAll('10.0.1.10'), {3: 'Close Up'},
          reason: 'a legacy file omits presetNames because versioning did not '
              'exist yet, not because the operator cleared them');
    });

    test('importing an unversioned export PRESERVES visibilities', () async {
      await VisibilityStore.save('roland_10.0.1.20', 5, ItemVisibility.hide);
      await ConfigBundle.fromJsonValidated(_v0({}))
          .applyTransactionally();
      expect(await VisibilityStore.loadAll('roland_10.0.1.20'),
          {5: ItemVisibility.hide});
    });
  });

  group('transactionality', () {
    test('a failure mid-apply leaves the stores WHOLLY OLD', () async {
      await PositionStore.saveAll([const Position(id: 'p1', name: 'Ambo')]);
      await PresetNameStore.save('10.0.1.10', 3, 'Close Up');

      final bundle = ConfigBundle.fromJsonValidated(_v1({}));
      await expectLater(
        bundle.applyTransactionally(failAfterStoresForTest: 2),
        throwsA(anything),
      );

      expect((await PositionStore.loadAll()).length, 1,
          reason: 'wholly old, never a mix');
      expect(await PresetNameStore.loadAll('10.0.1.10'), {3: 'Close Up'});
    });

    test('a journal left behind by a crash is rolled back at startup',
        () async {
      await PositionStore.saveAll([const Position(id: 'p1', name: 'Ambo')]);
      await RestoreJournal.capture();
      await PositionStore.saveAll([]); // simulate a half-done apply

      await RestoreJournal.rollbackIfPresent();

      expect((await PositionStore.loadAll()).length, 1);
    });

    test('rollbackIfPresent is a no-op when no journal exists', () async {
      await PositionStore.saveAll([const Position(id: 'p1', name: 'Ambo')]);
      await RestoreJournal.rollbackIfPresent();
      expect((await PositionStore.loadAll()).length, 1);
    });

    test('a successful apply leaves no journal behind', () async {
      await ConfigBundle.fromJsonValidated(_v1({})).applyTransactionally();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('backup_restore_journal'), isNull);
    });
  });
}
```

> `Position(id:, name:)` must match `lib/models/position.dart`. Adjust the
> fixture to the real constructor; the assertions are the point.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/restore_journal_test.dart`
Expected: FAIL — `restore_journal.dart` not found.

- [ ] **Step 3: Implement the journal**

Create `lib/services/backup/restore_journal.dart`:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Write-ahead journal that makes a multi-key import atomic.
///
/// `SharedPreferences` has no transaction. Applying a bundle touches a dozen
/// keys across eight stores, and a failure partway leaves a hybrid of old and
/// new that `ConfigBundle.fromStores()` will happily upload as a valid
/// revision. Capturing the previous values first turns "wholly old or wholly
/// new" into something that can actually be guaranteed.
class RestoreJournal {
  static const String key = 'backup_restore_journal';

  static const _fixedKeys = <String>[
    'positions',
    'people',
    'services',
    'height_ranges',
    'operators',
    'active_operator_id',
    'roland_ip',
    'panasonic_cameras',
  ];

  static const _prefixes = <String>['preset_names_', 'item_visibility_'];

  static bool isBundleOwned(String k) =>
      _fixedKeys.contains(k) || _prefixes.any(k.startsWith);

  /// Snapshots every bundle-owned key's current value.
  static Future<void> capture() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = <String, dynamic>{};
    for (final k in prefs.getKeys().where(isBundleOwned)) {
      snapshot[k] = prefs.get(k);
    }
    await prefs.setString(key, jsonEncode(snapshot));
  }

  /// Restores every captured key and drops the journal.
  ///
  /// Keys that did not exist when the journal was captured are removed, so a
  /// partial apply cannot leave a key the operator never had.
  static Future<void> rollbackIfPresent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return;

    final snapshot = jsonDecode(raw) as Map<String, dynamic>;
    for (final k in prefs.getKeys().where(isBundleOwned).toList()) {
      if (!snapshot.containsKey(k)) await prefs.remove(k);
    }
    for (final entry in snapshot.entries) {
      final v = entry.value;
      if (v is String) {
        await prefs.setString(entry.key, v);
      } else if (v is int) {
        await prefs.setInt(entry.key, v);
      } else if (v is bool) {
        await prefs.setBool(entry.key, v);
      } else if (v is double) {
        await prefs.setDouble(entry.key, v);
      } else if (v is List) {
        await prefs.setStringList(entry.key, v.cast<String>());
      }
    }
    await prefs.remove(key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
```

- [ ] **Step 4: Implement the transactional apply**

Add to `ConfigBundle` in `lib/services/config_bundle.dart`, leaving the existing `saveToStores()` in place for the untouched manual-import path:

```dart
  /// Applies this bundle to the live stores, atomically.
  ///
  /// Either every bundle-owned key ends up matching this bundle, or none of
  /// them change. [failAfterStoresForTest] is a test seam that throws after
  /// N store writes to prove the rollback works.
  Future<void> applyTransactionally({int? failAfterStoresForTest}) async {
    await RestoreJournal.capture();
    var written = 0;
    void tick() {
      written++;
      if (failAfterStoresForTest != null &&
          written >= failAfterStoresForTest!) {
        throw StateError('injected failure after $written store writes');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      await PositionStore.saveAll(positions);
      tick();
      await PeopleStore.saveAll(people);
      tick();
      await ServiceStore.saveAll(services);
      tick();
      await HeightRangeStore.saveAll(heightRanges);
      tick();

      if (rolandIp != null || cameras != null) {
        await DeviceConfigStore.save(
          rolandIp ?? DeviceConfigStore.defaultRolandIp,
          cameras ?? DeviceConfigStore.defaultCameras,
        );
      }
      if (operators != null) await OperatorStore.saveAll(operators!);

      // Null means "not present in this bundle" — a v0 legacy file — and the
      // existing keys are left alone. A non-null map is authoritative: keys
      // it does not mention are deleted.
      if (presetNames != null) {
        await _replacePrefixed(prefs, _presetPrefix, presetNames!);
      }
      if (visibilities != null) {
        await _replacePrefixed(prefs, _visibilityPrefix, visibilities!);
      }

      await RestoreJournal.clear();
    } catch (_) {
      await RestoreJournal.rollbackIfPresent();
      rethrow;
    }
  }

  static Future<void> _replacePrefixed(
    SharedPreferences prefs,
    String prefix,
    Map<String, Map<String, String>> incoming,
  ) async {
    for (final k in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      final deviceKey = k.substring(prefix.length);
      if (!incoming.containsKey(deviceKey)) await prefs.remove(k);
    }
    for (final entry in incoming.entries) {
      await prefs.setString('$prefix${entry.key}', jsonEncode(entry.value));
    }
  }
```

Add `import 'backup/restore_journal.dart';` at the top.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/backup/restore_journal_test.dart`
Expected: PASS, 8 tests.

Run: `flutter test && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/restore_journal.dart lib/services/config_bundle.dart \
        test/backup/restore_journal_test.dart
git commit -m "feat(backup): transactional import via a write-ahead rollback journal"
```

---

## Phase 2 — The Engine

### Task 8: The provenance pointer

**Test-policy class: trust contract.** Every row of the spec's transition table is a behaviour the protocol depends on.

**Files:**
- Create: `lib/services/backup/backup_pointer.dart`
- Test: `test/backup/backup_pointer_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `BackupPointer` with `load()`, `save({revisionId, recordedHash, targetIdentity})`, `clear()`, and `matchesTarget(String)`.

The pointer records which revision local state came from. It is deliberately **not** a field on `ConfigBundle`: putting provenance in the hashed body would change the hash on every upload and defeat the guard that suppresses redundant uploads. It is stored with the target identity, because a pointer from a different Drive folder or account is meaningless and must never be compared.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/backup_pointer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads as unprovenanced when nothing is stored', () async {
    final p = await BackupPointer.load();
    expect(p.revisionId, isNull);
    expect(p.recordedHash, isNull);
    expect(p.isProvenanced, isFalse);
  });

  test('round-trips through storage', () async {
    await BackupPointer.save(
        revisionId: 'rev-1', recordedHash: 'h1', targetIdentity: 'folder-A');
    final p = await BackupPointer.load();
    expect(p.revisionId, 'rev-1');
    expect(p.recordedHash, 'h1');
    expect(p.isProvenanced, isTrue);
    expect(p.matchesTarget('folder-A'), isTrue);
  });

  test('a pointer from another target does not match', () async {
    await BackupPointer.save(
        revisionId: 'rev-1', recordedHash: 'h1', targetIdentity: 'folder-A');
    final p = await BackupPointer.load();
    expect(p.matchesTarget('folder-B'), isFalse,
        reason: 'comparing a pointer across accounts or folders is meaningless');
  });

  test('clear makes it unprovenanced again', () async {
    await BackupPointer.save(
        revisionId: 'rev-1', recordedHash: 'h1', targetIdentity: 'folder-A');
    await BackupPointer.clear();
    expect((await BackupPointer.load()).isProvenanced, isFalse);
  });

  test('local is clean only when its hash matches the recorded one', () async {
    await BackupPointer.save(
        revisionId: 'rev-1', recordedHash: 'h1', targetIdentity: 'folder-A');
    final p = await BackupPointer.load();
    expect(p.isCleanAgainst('h1'), isTrue);
    expect(p.isCleanAgainst('h2'), isFalse);
  });

  test('an unprovenanced pointer is never clean, whatever the hash', () async {
    final p = await BackupPointer.load();
    expect(p.isCleanAgainst('anything'), isFalse,
        reason: 'null == null must not read as clean on a fresh install');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_pointer_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement**

Create `lib/services/backup/backup_pointer.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Which revision the local configuration came from.
///
/// Stored beside the target identity: a pointer captured against one Drive
/// folder or Google account says nothing about another, and comparing across
/// them would produce confident nonsense.
class BackupPointer {
  static const _revisionKey = 'backup_source_revision';
  static const _hashKey = 'backup_source_hash';
  static const _targetKey = 'backup_target_identity';

  final String? revisionId;
  final String? recordedHash;
  final String? targetIdentity;

  const BackupPointer({this.revisionId, this.recordedHash, this.targetIdentity});

  bool get isProvenanced => revisionId != null;

  bool matchesTarget(String identity) => targetIdentity == identity;

  /// Whether local content is unchanged since this pointer was recorded.
  ///
  /// An unprovenanced pointer is never clean. Without that guard a fresh
  /// install compares null to null, reads as clean, and a pull would
  /// auto-apply over local state it knows nothing about.
  bool isCleanAgainst(String localHash) =>
      isProvenanced && recordedHash == localHash;

  static Future<BackupPointer> load() async {
    final prefs = await SharedPreferences.getInstance();
    return BackupPointer(
      revisionId: prefs.getString(_revisionKey),
      recordedHash: prefs.getString(_hashKey),
      targetIdentity: prefs.getString(_targetKey),
    );
  }

  static Future<void> save({
    required String revisionId,
    required String recordedHash,
    required String targetIdentity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_revisionKey, revisionId);
    await prefs.setString(_hashKey, recordedHash);
    await prefs.setString(_targetKey, targetIdentity);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_revisionKey);
    await prefs.remove(_hashKey);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/backup_pointer_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_pointer.dart test/backup/backup_pointer_test.dart
git commit -m "feat(backup): provenance pointer bound to a target identity"
```

---

### Task 9: The engine — push

**Test-policy class: trust contract.** Push decides whether the other machine's work survives.

**Files:**
- Create: `lib/services/backup/backup_service.dart`
- Test: `test/backup/backup_service_push_test.dart`

**Interfaces:**
- Consumes: `BackupTargetAbstract`, `MockBackupTarget`, `BackupPointer`, `ConfigMutationNotifier`, `canonicalHash`, `AppFault`.
- Produces: `BackupService({required BackupTargetAbstract target, required String targetIdentity, required Future<String> Function() deviceLabel})`, with `Future<PushResult> push()` and `enum PushOutcome { noOp, uploaded, conflict, forked }`.

Push steps, from the spec:

1. Hash equals the current head's hash → no-op. **If that head's id differs from the pointer, rebase the pointer to it.** Pull has this rebase; without the matching one here, a push that finds equivalent bytes under another id strands a stale pointer and the next genuine edit trips a phantom conflict.
2. `latest().id != pointer` → conflict. Do not upload.
3. `put(json, parentRevisionId: pointer)`.
4. Re-read `list()` and check for another revision sharing our parent. **This design does not promise pre-upload conflict detection** — Drive has no compare-and-swap — it promises honest detection immediately after.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/backup_service_push_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _identity = 'folder-A';

BackupService _service(MockBackupTarget t, Map<String, dynamic> bundle) =>
    BackupService(
      target: t,
      targetIdentity: _identity,
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => bundle,
    );

void main() {
  late MockBackupTarget target;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    target = MockBackupTarget();
  });

  test('first push uploads and records the pointer', () async {
    final bundle = {'positions': <dynamic>[]};
    final result = await _service(target, bundle).push();

    expect(result.outcome, PushOutcome.uploaded);
    expect(target.revisions.length, 1);

    final p = await BackupPointer.load();
    expect(p.revisionId, target.revisions.single.id);
    expect(p.recordedHash, canonicalHash(bundle));
  });

  test('pushing identical content is a no-op', () async {
    final bundle = {'positions': <dynamic>[]};
    await _service(target, bundle).push();
    final result = await _service(target, bundle).push();

    expect(result.outcome, PushOutcome.noOp);
    expect(target.revisions.length, 1, reason: 'no second file');
  });

  test('a no-op against an equal head under a different id rebases the pointer',
      () async {
    final bundle = {'positions': <dynamic>[]};
    // Another machine uploaded byte-identical content first.
    await target.put(canonicalJsonEncode(bundle),
        contentHash: canonicalHash(bundle),
        parentRevisionId: null,
        deviceLabel: 'iPad');

    final result = await _service(target, bundle).push();

    expect(result.outcome, PushOutcome.noOp);
    final p = await BackupPointer.load();
    expect(p.revisionId, target.revisions.single.id,
        reason: 'a stale pointer here trips a phantom conflict on the next edit');
  });

  test('a moved remote is a conflict and uploads nothing', () async {
    final bundle = {'positions': <dynamic>[]};
    await _service(target, bundle).push();

    await target.put('{"other":1}',
        contentHash: 'other',
        parentRevisionId: target.revisions.first.id,
        deviceLabel: 'iPad');

    final changed = {'positions': <dynamic>['edited']};
    final result = await _service(target, changed).push();

    expect(result.outcome, PushOutcome.conflict);
    expect(result.remoteRevision!.deviceLabel, 'iPad');
    expect(target.revisions.length, 2, reason: 'nothing new was uploaded');
  });

  test('a concurrent writer between check and write is reported as a fork',
      () async {
    final bundle = {'positions': <dynamic>[]};
    await _service(target, bundle).push();
    final base = target.revisions.single;

    target.concurrentWriterBeforePut(
        body: '{"theirs":1}',
        contentHash: 'theirs',
        parentRevisionId: base.id,
        deviceLabel: 'iPad');

    final changed = {'positions': <dynamic>['edited']};
    final result = await _service(target, changed).push();

    expect(result.outcome, PushOutcome.forked,
        reason: 'Drive has no compare-and-swap; detection is after the fact');
    expect(result.siblings!.map((r) => r.deviceLabel), contains('iPad'));
  });

  test('a successful push marks the mutation generation synced', () async {
    await ConfigMutationNotifierTestHelper.bumpTo(3);
    await _service(target, {'positions': <dynamic>[]}).push();
    expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);
  });
}
```

> The last test needs a helper. Add to `config_mutation_notifier.dart`:
> a top-level `class ConfigMutationNotifierTestHelper { static Future<void>
> bumpTo(int n) async { for (var i = 0; i < n; i++) { await
> ConfigMutationNotifier.instance.notify(); } } }` and import
> `config_mutation_notifier.dart` in this test.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_service_push_test.dart`
Expected: FAIL — `backup_service.dart` not found.

- [ ] **Step 3: Implement push**

Create `lib/services/backup/backup_service.dart`:

```dart
import 'dart:async';

import 'abstract/backup_target_abstract.dart';
import 'app_fault.dart';
import 'backup_pointer.dart';
import 'backup_revision.dart';
import 'canonical_json.dart';
import 'config_mutation_notifier.dart';

enum PushOutcome { noOp, uploaded, conflict, forked }

class PushResult {
  final PushOutcome outcome;
  final BackupRevision? revision;
  final BackupRevision? remoteRevision;
  final List<BackupRevision>? siblings;

  const PushResult(this.outcome,
      {this.revision, this.remoteRevision, this.siblings});
}

/// Owns the whole backup protocol.
///
/// Every operation runs through one single-flight queue. Pulls, debounced
/// pushes, periodic sweeps, manual retries and the backoff timer are
/// otherwise five independent callers of the same mutable state, and an older
/// operation completing after a newer one would overwrite status or
/// provenance.
class BackupService {
  final BackupTargetAbstract target;
  final String targetIdentity;
  final Future<String> Function() deviceLabel;
  final Future<Map<String, dynamic>> Function() readBundleJson;

  Future<void> _queue = Future<void>.value();

  BackupService({
    required this.target,
    required this.targetIdentity,
    required this.deviceLabel,
    required this.readBundleJson,
  });

  /// Serializes [action] behind every operation already queued.
  Future<T> _single<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<PushResult> push() => _single(_push);

  Future<PushResult> _push() async {
    final generation = await ConfigMutationNotifier.instance.generation();
    final bundle = await readBundleJson();
    final json = canonicalJsonEncode(bundle);
    final hash = canonicalHash(bundle);

    final head = await target.latest();
    var pointer = await BackupPointer.load();
    if (!pointer.matchesTarget(targetIdentity)) {
      pointer = const BackupPointer();
    }

    // 1. Identical content. Rebase if the head carries a different id, or the
    //    stale pointer trips a phantom conflict on the next real edit.
    if (head != null && head.contentHash == hash) {
      if (pointer.revisionId != head.id) {
        await BackupPointer.save(
          revisionId: head.id,
          recordedHash: hash,
          targetIdentity: targetIdentity,
        );
      }
      await ConfigMutationNotifier.instance.markSynced(generation);
      return const PushResult(PushOutcome.noOp);
    }

    // 2. Remote moved since we last synced.
    if (head != null && head.id != pointer.revisionId) {
      return PushResult(PushOutcome.conflict, remoteRevision: head);
    }

    // 3. Upload, recording where we branched from.
    final revision = await target.put(
      json,
      contentHash: hash,
      parentRevisionId: pointer.revisionId,
      deviceLabel: await deviceLabel(),
    );

    await BackupPointer.save(
      revisionId: revision.id,
      recordedHash: hash,
      targetIdentity: targetIdentity,
    );
    await ConfigMutationNotifier.instance.markSynced(generation);

    // 4. Fork check. Drive offers no compare-and-swap, so a second writer can
    //    pass step 2 concurrently. Both bodies survive; say so rather than
    //    pretend the race did not happen.
    final recent = await target.list(limit: 10);
    final siblings = recent
        .where((r) =>
            r.id != revision.id &&
            r.parentRevisionId == revision.parentRevisionId)
        .toList();
    if (siblings.isNotEmpty) {
      return PushResult(PushOutcome.forked,
          revision: revision, siblings: siblings);
    }

    return PushResult(PushOutcome.uploaded, revision: revision);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/backup_service_push_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_service.dart \
        lib/services/backup/config_mutation_notifier.dart \
        test/backup/backup_service_push_test.dart
git commit -m "feat(backup): push with ancestry, no-op rebase, and post-upload fork check"
```

---

### Task 10: The engine — pull

**Test-policy class: trust contract.** Two of these branches destroy data if they are wrong, and both were live defects in an earlier draft of the spec.

**Files:**
- Modify: `lib/services/backup/backup_service.dart` (add `pull`)
- Test: `test/backup/backup_service_pull_test.dart`

**Interfaces:**
- Consumes: everything from Task 9.
- Produces: `Future<PullResult> pull()` and `enum PullOutcome { nothingToDo, adopted, applied, rebased, conflict, targetEmptied, needsAdoptionChoice }`.

Branches are evaluated **in order**, first match wins:

1. `latest()` metadata only. Target identity mismatch → treat as unprovenanced.
2. **Remote empty.** Pointer null → new target, nothing to apply. Pointer set → the revision we were provenanced against is *gone*: invalidate the durable head, clear the pointer, raise `targetMissing`. Not "nothing to do" — a successful round trip has just proved the backup no longer exists.
3. **Unprovenanced, remote non-empty.** Never auto-apply. Local pristine → adopt. Local has data → ask. This covers first run, a changed account, and a machine that has just manually imported.
4. `latest().id == pointer` → nothing to apply.
5. **Equivalent content under a different id** → rebase. Compare against a *trusted* body hash, never client metadata alone.
6. **`latest().parentRevisionId == pointer` and local clean** → linear descendant. Fetch, validate, apply transactionally, advance.
7. **Anything else** → conflict. Do not apply, do not show a modal.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/backup_service_pull_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _identity = 'folder-A';

Map<String, dynamic> _bundle(String marker) => {
      'schemaVersion': 1,
      'positions': <dynamic>[],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
      'marker': marker,
    };

void main() {
  late MockBackupTarget target;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    target = MockBackupTarget();
  });

  BackupService service(Map<String, dynamic> local, {bool pristine = false}) =>
      BackupService(
        target: target,
        targetIdentity: _identity,
        deviceLabel: () async => 'Mac mini',
        readBundleJson: () async => local,
        localIsPristine: () async => pristine,
      );

  test('empty remote with no pointer is simply nothing to do', () async {
    final r = await service(_bundle('local'), pristine: true).pull();
    expect(r.outcome, PullOutcome.nothingToDo);
  });

  test('empty remote with a pointer set means the backup is GONE', () async {
    await BackupPointer.save(
        revisionId: 'rev-1', recordedHash: 'h', targetIdentity: _identity);

    final r = await service(_bundle('local')).pull();

    expect(r.outcome, PullOutcome.targetEmptied,
        reason: 'a round trip just proved the backup does not exist; '
            'staying green would be a lie');
    expect((await BackupPointer.load()).isProvenanced, isFalse);
  });

  test('unprovenanced with pristine local adopts the remote', () async {
    final remote = _bundle('remote');
    await target.put(canonicalJsonEncode(remote),
        contentHash: canonicalHash(remote),
        parentRevisionId: null,
        deviceLabel: 'iPad');

    final r = await service(_bundle('local'), pristine: true).pull();

    expect(r.outcome, PullOutcome.adopted);
    expect((await BackupPointer.load()).revisionId, isNotNull);
  });

  test('unprovenanced with local data ASKS rather than auto-applying',
      () async {
    final remote = _bundle('remote');
    await target.put(canonicalJsonEncode(remote),
        contentHash: canonicalHash(remote),
        parentRevisionId: null,
        deviceLabel: 'iPad');

    final r = await service(_bundle('local'), pristine: false).pull();

    expect(r.outcome, PullOutcome.needsAdoptionChoice,
        reason: 'a just-imported config must not be silently replaced');
  });

  test('pointer equal to head is nothing to do', () async {
    final b = _bundle('same');
    final rev = await target.put(canonicalJsonEncode(b),
        contentHash: canonicalHash(b),
        parentRevisionId: null,
        deviceLabel: 'iPad');
    await BackupPointer.save(
        revisionId: rev.id,
        recordedHash: canonicalHash(b),
        targetIdentity: _identity);

    expect((await service(b).pull()).outcome, PullOutcome.nothingToDo);
  });

  test('equal content under a different id rebases without applying',
      () async {
    final b = _bundle('same');
    await target.put(canonicalJsonEncode(b),
        contentHash: canonicalHash(b),
        parentRevisionId: null,
        deviceLabel: 'iPad');
    await BackupPointer.save(
        revisionId: 'some-old-id',
        recordedHash: canonicalHash(b),
        targetIdentity: _identity);

    final r = await service(b).pull();

    expect(r.outcome, PullOutcome.rebased);
    expect((await BackupPointer.load()).revisionId, target.revisions.single.id);
  });

  test('a linear descendant with clean local is applied', () async {
    final base = _bundle('base');
    final baseRev = await target.put(canonicalJsonEncode(base),
        contentHash: canonicalHash(base),
        parentRevisionId: null,
        deviceLabel: 'iPad');
    await BackupPointer.save(
        revisionId: baseRev.id,
        recordedHash: canonicalHash(base),
        targetIdentity: _identity);

    final next = _bundle('next');
    final nextRev = await target.put(canonicalJsonEncode(next),
        contentHash: canonicalHash(next),
        parentRevisionId: baseRev.id,
        deviceLabel: 'iPad');

    final r = await service(base).pull();

    expect(r.outcome, PullOutcome.applied);
    expect((await BackupPointer.load()).revisionId, nextRev.id);
  });

  test('A SIBLING FORK IS NOT APPLIED even though local is clean', () async {
    // The regression this test exists for: checking only "local is clean"
    // compares local against its OWN pointer and proves nothing about whether
    // remote descends from it. A machine that had just pushed would otherwise
    // silently adopt the other machine's fork over its own work.
    final base = _bundle('base');
    final baseRev = await target.put(canonicalJsonEncode(base),
        contentHash: canonicalHash(base),
        parentRevisionId: null,
        deviceLabel: 'shared');

    final mine = _bundle('mine');
    final myRev = await target.put(canonicalJsonEncode(mine),
        contentHash: canonicalHash(mine),
        parentRevisionId: baseRev.id,
        deviceLabel: 'Mac mini');

    // Their sibling lands later, so it sorts as latest().
    final theirs = _bundle('theirs');
    await target.put(canonicalJsonEncode(theirs),
        contentHash: canonicalHash(theirs),
        parentRevisionId: baseRev.id,
        deviceLabel: 'iPad');

    await BackupPointer.save(
        revisionId: myRev.id,
        recordedHash: canonicalHash(mine),
        targetIdentity: _identity);

    final r = await service(mine).pull();

    expect(r.outcome, PullOutcome.conflict,
        reason: 'clean-against-own-pointer is not ancestry');
    expect((await BackupPointer.load()).revisionId, myRev.id,
        reason: 'my own work must still be the pointer');
  });

  test('a moved remote with dirty local is a conflict, never a modal',
      () async {
    final base = _bundle('base');
    final baseRev = await target.put(canonicalJsonEncode(base),
        contentHash: canonicalHash(base),
        parentRevisionId: null,
        deviceLabel: 'iPad');
    await BackupPointer.save(
        revisionId: baseRev.id,
        recordedHash: canonicalHash(base),
        targetIdentity: _identity);

    final next = _bundle('next');
    await target.put(canonicalJsonEncode(next),
        contentHash: canonicalHash(next),
        parentRevisionId: baseRev.id,
        deviceLabel: 'iPad');

    final r = await service(_bundle('dirty-local')).pull();
    expect(r.outcome, PullOutcome.conflict);
  });

  test('a pointer from another target is ignored, not compared', () async {
    final b = _bundle('remote');
    await target.put(canonicalJsonEncode(b),
        contentHash: canonicalHash(b),
        parentRevisionId: null,
        deviceLabel: 'iPad');
    await BackupPointer.save(
        revisionId: 'rev-from-elsewhere',
        recordedHash: 'h',
        targetIdentity: 'a-different-folder');

    final r = await service(_bundle('local'), pristine: true).pull();
    expect(r.outcome, PullOutcome.adopted,
        reason: 'treated as unprovenanced, not compared across targets');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_service_pull_test.dart`
Expected: FAIL — `pull` and `localIsPristine` do not exist.

- [ ] **Step 3: Implement pull**

Add to `BackupService`. First extend the constructor with:

```dart
  /// Whether local configuration is untouched — a fresh install with nothing
  /// worth protecting. Only consulted when the pointer is null.
  final Future<bool> Function() localIsPristine;
```

adding `required this.localIsPristine,` to the constructor parameter list, and defaulting it in production wiring to "all four core stores are empty".

Then add:

```dart
enum PullOutcome {
  nothingToDo,
  adopted,
  applied,
  rebased,
  conflict,
  targetEmptied,
  needsAdoptionChoice,
}

class PullResult {
  final PullOutcome outcome;
  final BackupRevision? revision;
  const PullResult(this.outcome, {this.revision});
}
```

and the method:

```dart
  Future<PullResult> pull() => _single(_pull);

  Future<PullResult> _pull() async {
    // 1. Metadata only. A pointer from another target is meaningless.
    final head = await target.latest();
    var pointer = await BackupPointer.load();
    if (!pointer.matchesTarget(targetIdentity)) {
      pointer = const BackupPointer();
    }

    // 2. Remote empty.
    if (head == null) {
      if (!pointer.isProvenanced) {
        return const PullResult(PullOutcome.nothingToDo);
      }
      await BackupPointer.clear();
      return const PullResult(PullOutcome.targetEmptied);
    }

    final localHash = canonicalHash(await readBundleJson());

    // 3. Unprovenanced. Never auto-apply over local data.
    if (!pointer.isProvenanced) {
      if (!await localIsPristine()) {
        return PullResult(PullOutcome.needsAdoptionChoice, revision: head);
      }
      await _applyRevision(head);
      return PullResult(PullOutcome.adopted, revision: head);
    }

    // 4. Remote has not moved.
    if (head.id == pointer.revisionId) {
      return const PullResult(PullOutcome.nothingToDo);
    }

    // 5. Equivalent content under another id. Verified against the body, not
    //    client-supplied metadata, which goes stale if a file is edited by
    //    hand in the Drive web UI.
    final remoteBody = await target.fetch(head);
    if (canonicalHash(jsonDecode(remoteBody)) == localHash) {
      await BackupPointer.save(
        revisionId: head.id,
        recordedHash: localHash,
        targetIdentity: targetIdentity,
      );
      return PullResult(PullOutcome.rebased, revision: head);
    }

    // 6. Linear descendant of our pointer, and local is unchanged.
    //    The ancestry test is load-bearing: "clean" compares local against its
    //    OWN pointer and says nothing about whether remote descends from it.
    if (head.parentRevisionId == pointer.revisionId &&
        pointer.isCleanAgainst(localHash)) {
      await _applyRevision(head, body: remoteBody);
      return PullResult(PullOutcome.applied, revision: head);
    }

    // 7. Diverged, or local is dirty. Surface it; never a modal.
    return PullResult(PullOutcome.conflict, revision: head);
  }

  Future<void> _applyRevision(BackupRevision revision, {String? body}) async {
    final raw = body ?? await target.fetch(revision);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw AppFault.backup(BackupFailureKind.malformedRemote,
          'revision ${revision.id} is not a JSON object');
    }
    final bundle = ConfigBundle.fromJsonValidated(decoded);
    await bundle.applyTransactionally();
    await BackupPointer.save(
      revisionId: revision.id,
      recordedHash: canonicalHash(decoded),
      targetIdentity: targetIdentity,
    );
    await ConfigMutationNotifier.instance
        .markSynced(await ConfigMutationNotifier.instance.generation());
  }
```

Add `import 'dart:convert';` and `import '../config_bundle.dart';` at the top of `backup_service.dart`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/backup_service_pull_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Run everything**

Run: `flutter test && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/backup_service.dart test/backup/backup_service_pull_test.dart
git commit -m "feat(backup): pull with ordered branches and the ancestry test"
```

---

### Task 11: Single-flight and retry

**Test-policy class: trust contract** for the backoff schedule and ordering guarantee.

**Files:**
- Modify: `lib/services/backup/backup_service.dart`
- Test: `test/backup/backup_service_scheduling_test.dart`

**Interfaces:**
- Consumes: Task 10.
- Produces: `Duration? nextRetryDelay(AppFault fault, int attempt)`, `void resetBackoff()`, and the ordering guarantee already provided by `_single`.

Backoff is 30 s → 1 m → 2 m → 5 m → 10 m, then held at 10 m. **The loop never gives up** — a retry schedule that exhausts itself and stops is a silent failure with extra steps. Non-retryable kinds schedule nothing; `unknown` waits for the ten-minute sweep rather than spinning.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/backup_service_scheduling_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('backoff schedule', () {
    final offline = AppFault.backup(BackupFailureKind.offline, 'x');

    test('follows 30s, 1m, 2m, 5m, 10m', () {
      expect(BackupService.nextRetryDelay(offline, 0),
          const Duration(seconds: 30));
      expect(BackupService.nextRetryDelay(offline, 1),
          const Duration(minutes: 1));
      expect(BackupService.nextRetryDelay(offline, 2),
          const Duration(minutes: 2));
      expect(BackupService.nextRetryDelay(offline, 3),
          const Duration(minutes: 5));
      expect(BackupService.nextRetryDelay(offline, 4),
          const Duration(minutes: 10));
    });

    test('holds at ten minutes and never gives up', () {
      for (final attempt in [5, 20, 5000]) {
        expect(BackupService.nextRetryDelay(offline, attempt),
            const Duration(minutes: 10),
            reason: 'a schedule that exhausts itself is a silent failure');
      }
    });

    test('non-retryable kinds schedule nothing', () {
      for (final k in [
        BackupFailureKind.authExpired,
        BackupFailureKind.storageFull,
        BackupFailureKind.permissionDenied,
        BackupFailureKind.conflict,
      ]) {
        expect(BackupService.nextRetryDelay(AppFault.backup(k, 'x'), 0), isNull,
            reason: 'waiting cannot fix $k');
      }
    });

    test('unknown waits for the sweep rather than spinning', () {
      expect(
          BackupService.nextRetryDelay(
              AppFault.backup(BackupFailureKind.unknown, 'x'), 0),
          const Duration(minutes: 10));
    });
  });

  group('single-flight', () {
    test('operations complete in the order they were queued', () async {
      final target = MockBackupTarget();
      final service = BackupService(
        target: target,
        targetIdentity: 'folder-A',
        deviceLabel: () async => 'Mac mini',
        readBundleJson: () async => {'positions': <dynamic>[]},
        localIsPristine: () async => true,
      );

      final order = <String>[];
      final a = service.pull().then((_) => order.add('a'));
      final b = service.pull().then((_) => order.add('b'));
      final c = service.pull().then((_) => order.add('c'));
      await Future.wait([a, b, c]);

      expect(order, ['a', 'b', 'c'],
          reason: 'an older operation completing after a newer one would '
              'overwrite status or provenance');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_service_scheduling_test.dart`
Expected: FAIL — `nextRetryDelay` not defined.

- [ ] **Step 3: Implement**

Add to `BackupService`:

```dart
  static const _backoff = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  /// How long to wait before retrying after [fault], or null when retrying
  /// cannot help.
  ///
  /// The schedule never terminates. A loop that exhausts its attempts and
  /// stops is a silent failure with extra steps: the pill would sit red
  /// forever with nothing trying to clear it.
  static Duration? nextRetryDelay(AppFault fault, int attempt) {
    if (!fault.isRetryable) return null;
    if (fault.sweepOnly) return const Duration(minutes: 10);
    return _backoff[attempt.clamp(0, _backoff.length - 1)];
  }
```

The single-flight guarantee is already provided by `_single` from Task 9; this task only proves it.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/backup_service_scheduling_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_service.dart \
        test/backup/backup_service_scheduling_test.dart
git commit -m "feat(backup): retry backoff that never gives up, plus single-flight proof"
```

---

### Task 12: Startup rollback wiring

**Test-policy class: wiring.** One thin test that the hook is called; the rollback behaviour itself is already covered by Task 7.

**Files:**
- Modify: `lib/main.dart:1-21`
- Test: `test/backup/startup_rollback_test.dart`

**Interfaces:**
- Consumes: `RestoreJournal.rollbackIfPresent()` (Task 7).
- Produces: nothing other tasks consume.

A journal present at startup means a previous materialization was interrupted. It must be rolled back **before anything else runs**, or the app reads a hybrid configuration and the next push uploads it.

- [ ] **Step 1: Read the current entry point**

```bash
cat lib/main.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/backup/startup_rollback_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/restore_journal.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an interrupted apply is rolled back before the app reads config',
      () async {
    await PositionStore.saveAll([const Position(id: 'p1', name: 'Ambo')]);
    await RestoreJournal.capture();
    await PositionStore.saveAll([]); // crash mid-apply

    await RestoreJournal.rollbackIfPresent();

    expect((await PositionStore.loadAll()).length, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(RestoreJournal.key), isNull);
  });
}
```

- [ ] **Step 3: Run to verify it fails or passes**

Run: `flutter test test/backup/startup_rollback_test.dart`
Expected: PASS — Task 7 already implemented the behaviour. This test pins it against regression at the startup boundary.

- [ ] **Step 4: Wire it into main**

In `lib/main.dart`, make `main` async and call the rollback before `runApp`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A journal here means a previous restore was interrupted. Roll it back
  // before anything reads configuration, or the app runs on a hybrid of old
  // and new and the next backup uploads that hybrid as a valid revision.
  await RestoreJournal.rollbackIfPresent();
  runApp(const MyApp());
}
```

Add `import 'services/backup/restore_journal.dart';`. Keep the existing widget class name — read the file first and match it rather than assuming `MyApp`.

- [ ] **Step 5: Verify the app still starts**

Run: `flutter test && flutter analyze`
Expected: full suite green, analyze clean.

Run: `flutter run -d macos` (or `-d linux`), confirm the app reaches its normal first screen, then quit.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart test/backup/startup_rollback_test.dart
git commit -m "feat(backup): roll back an interrupted restore at startup"
```

---

## Self-Review

**Spec coverage for phases 0–2:**

| Spec section | Task |
|---|---|
| Canonical serialization | 2 |
| `AppFault`, `FaultDomain`, general-from-day-one | 3 |
| Failure taxonomy incl. `rateLimited`/`transientServer` split | 3 |
| Log fingerprint excluding message | 3 (fingerprint) — the log store itself is phase 3 |
| `BackupRevision` with `parentRevisionId`, `deviceLabel` | 4 |
| `BackupTargetAbstract`, no `siblings()` | 4 |
| `MockBackupTarget` with concurrent-writer simulation | 4 |
| Retention conjunction (count AND age) | 4 |
| Mutation source, eight-store refactor | 5 |
| Durable pending intent | 5 |
| `schemaVersion` in envelope, v0/v1 matrix, `{}` malformed | 6 |
| `unsupportedSchema` fail-closed | 6 |
| Import contract: full replace under v1 | 7 |
| Legacy preservation regression test | 7 |
| Rollback journal, wholly-old-or-wholly-new | 7, 12 |
| Pointer transitions, target identity | 8, 9, 10 |
| Push: no-op rebase, conflict, fork check | 9 |
| Pull: seven ordered branches, ancestry test | 10 |
| Trust the body not the metadata | 10 (branch 5 fetches) |
| Single-flight | 9 (`_single`), 11 (proof) |
| Retry backoff, never gives up | 11 |

**Deferred to later plans, deliberately:** the status pill and popover, the persisted fault log, the conflict resolution UI, the revision-history picker, the debounce and periodic sweep timers, `DriveBackupTarget`, auth, device-label naming UI, and phase 5. Each is named in the spec and none is silently dropped.

**Known gaps this plan leaves open, to fix in the phase-3 plan:**

- `BackupService` has no timer wiring. `push()` and `pull()` exist and are correct; nothing calls them on a schedule yet. That is deliberate — timers are hard to test and belong with the UI that displays their results.
- Device-label naming (reject `localhost`, `iPad`, empty, duplicates) is specified but has no task here, because it needs a settings UI. `deviceLabel` is a callback on `BackupService` so phase 3 can supply it without touching the engine.
- `prune` is implemented on the mock and declared on the interface but never called by the engine. It belongs with push in phase 4, where a real target makes retention meaningful.

**Type consistency check:** `canonicalHash`/`canonicalJsonEncode` (Task 2) are used verbatim in 9 and 10. `AppFault.backup(kind, message, operation:)` (Task 3) is used in 6 and 10. `BackupRevision.parentRevisionId` (Task 4) is used in 9 and 10. `BackupPointer.isCleanAgainst` (Task 8) is used in 10. `ConfigMutationNotifier.instance.markSynced` (Task 5) is used in 9 and 10. `ConfigBundle.fromJsonValidated` (Task 6) is used in 7 and 10. `applyTransactionally` (Task 7) is used in 10.

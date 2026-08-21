# Backup Foundations and Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete configuration backup engine — canonical serialization, a transactional import contract, the full sync protocol, and the scheduler that drives it — running against an in-memory mock.

**Architecture:** Eight static `SharedPreferences` stores gain a mutation notifier so changes can be observed. `ConfigBundle` gains a required schema version, canonical serialization, and validation, with exactly one parser. Imports become transactional via a write-ahead rollback journal. `BackupService` sits above `BackupTargetAbstract` and owns the protocol — single-flight queueing, ordered pull branches, push with ancestry, pointer transitions, retry backoff — and `BackupScheduler` drives it with debounced pushes, a periodic sweep, and lifecycle pulls. Everything is verified against `MockBackupTarget`.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `shared_preferences` ^2.3.0, `crypto` ^3.0.3, `flutter_test`, `mocktail` ^1.0.0.

**Spec:** `docs/superpowers/specs/2026-08-21-drive-backup-and-status-surface-design.md`

## Global Constraints

- **One new pubspec dependency, declared:** `crypto` ^3.0.3, added in Task 2. It is already present transitively via `flutter_test` (`pubspec.lock:116`), but hashing is production code and a transitive package is not a contract. Nothing else may be added; Drive's dependencies belong to phase 4.
- **Everything must build and test on Linux and macOS.** No Apple-only APIs.
- Dart SDK floor `>=3.11.0`, Flutter `>=3.38.0` — unchanged.
- All persistence goes through `SharedPreferences`.
- Every test file uses `SharedPreferences.setMockInitialValues({})` in `setUp`, matching `test/stores_test.dart:15-17`.
- Faults crossing the backup boundary are always `AppFault`. A `TypeError`, `FormatException` or `CastError` escaping from parsing or transport is a defect.
- **No backward compatibility.** Pre-release, no users, no deployed data. One schema, one parser, one apply path. **Tests asserting superseded behaviour are deleted, never renamed or inverted.** If a task leaves two ways to do the same thing, that is a defect.
- `Position` has a **non-const** constructor (`lib/models/position.dart:5`). Never write `const Position(...)`.
- `flutter analyze` clean and `flutter test --concurrency=1` green at the end of every task. A task whose commit leaves `main` broken is a failed task.

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `lib/services/backup/canonical_json.dart` | Key-sorted encoding; sha256 content hash; md5 body checksum. |
| `lib/services/backup/app_fault.dart` | `AppFault`, `FaultDomain`, `BackupFailureKind`, retry classification, fingerprint. |
| `lib/services/backup/backup_revision.dart` | Revision metadata: ancestry, client hash, server checksum. |
| `lib/services/backup/abstract/backup_target_abstract.dart` | Storage interface. |
| `lib/services/backup/mock/mock_backup_target.dart` | In-memory target; scriptable failures, concurrent writer, delays, lying metadata. |
| `lib/services/backup/config_mutation_notifier.dart` | Durable generation counter, broadcast stream, suspension during restore. |
| `lib/services/backup/backup_pointer.dart` | Provenance pointer bound to target identity. |
| `lib/services/backup/restore_journal.dart` | Write-ahead journal for atomic import. |
| `lib/services/backup/backup_service.dart` | Protocol: single-flight, push, pull, retry policy. |
| `lib/services/backup/backup_scheduler.dart` | Triggers: debounce, sweep, lifecycle, retry loop. |
| `lib/services/backup/single_instance.dart` | Refuses a second app instance. |

**Modified:**

| File | Change |
|---|---|
| `lib/services/config_bundle.dart` | Required `schemaVersion`; **`fromJson` deleted** and replaced by a validating parser; **`saveToStores` deleted** and replaced by `applyTransactionally`. |
| The eight `lib/services/*_store.dart` | One line each: notify after a successful write. |
| `lib/widgets/settings_dialog.dart:294-304` | Use the transactional apply; drop preserve-if-absent UI branches. |
| `lib/main.dart` | Singleton guard and journal rollback before `runApp`. |
| `test/config_bundle_test.dart` | Superseded tests **deleted**; remaining call sites moved to the new API. |

---

## Phase 0 — Spike

### Task 1: Platform and auth spike

**Test-policy class: spike.** No tests. The deliverable is a written answer; any code is throwaway.

**Files:**
- Create: `docs/superpowers/spikes/2026-08-21-google-signin-platform-spike.md`

**Interfaces:**
- Consumes: nothing. Produces: a go/no-go answer phase 4 depends on. Nothing in phases 1–2 imports from this task.

**Flutter cannot cross-compile Linux from macOS.** `flutter build linux` on this Mac fails with a host-OS error whether or not `google_sign_in` is present, so it cannot answer the Linux question. Determine Linux impact from the plugin's declared platform support, and have John confirm on his own machine.

- [ ] **Step 1: Record the baseline**

```bash
cd /Users/danielgreig/Desktop/navigation_app
git status --short
flutter analyze 2>&1 | tail -3
flutter test --concurrency=1 2>&1 | tail -3
```

Expected: analyze clean, 305 tests pass. Record both numbers in the spike doc.

- [ ] **Step 2: Add the dependency on a scratch branch**

```bash
git checkout -b spike/google-signin-platform
```

Add under `dependencies:` in `pubspec.yaml`:

```yaml
  google_sign_in: ^7.2.0
```

```bash
flutter pub get 2>&1 | tail -5
```

- [ ] **Step 3: Determine Linux impact without building Linux**

```bash
find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name "google_sign_in-*" -type d
sed -n '/^flutter:/,/^[a-z]/p' ~/.pub-cache/hosted/pub.dev/google_sign_in-*/pubspec.yaml
grep -A3 "google_sign_in" pubspec.lock
```

Record which platforms the plugin federates to and whether any Linux implementation package resolves at all. A federated plugin with no Linux implementation normally still *builds* on Linux and throws `MissingPluginException` at call time — record that as **the expectation for John to confirm**, not as a finding.

- [ ] **Step 4: Build the platforms this machine can build**

```bash
flutter build macos --debug 2>&1 | tail -20
flutter build ios --debug --no-codesign 2>&1 | tail -20
flutter analyze 2>&1 | tail -5
```

Record pass/fail and the exact error for each.

- [ ] **Step 5: Inventory the missing Apple setup**

```bash
grep -c "CFBundleURLTypes" macos/Runner/Info.plist ios/Runner/Info.plist
grep -c "keychain-access-groups" macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements
```

Expected: all zero. The spec requires the reversed client ID URL scheme in both `Info.plist` files and `$(AppIdentifierPrefix)com.google.GIDSignIn` in the macOS entitlements. This step proves they are absent and records what phase 4 must add; it does not add them.

Also record, from the `google_sign_in` API surface, **whether the app ever receives a refresh token it must store itself.** The spec says to determine this rather than assume, because it decides whether a secure-storage dependency is needed at all.

- [ ] **Step 6: Revert completely**

```bash
git checkout -- pubspec.yaml pubspec.lock
flutter pub get
git checkout main
git branch -D spike/google-signin-platform
git status --short
```

- [ ] **Step 7: Commit the answer, not the code**

```bash
git add docs/superpowers/spikes/2026-08-21-google-signin-platform-spike.md
git commit -m "docs: spike result for google_sign_in platform support"
```

---

## Phase 1 — Foundations

### Task 2: Canonical JSON

**Test-policy class: trust contract.** The entire hash guard rests on this: if two machines with identical config produce different bytes, every sweep uploads and every comparison conflicts.

**Files:**
- Create: `lib/services/backup/canonical_json.dart`
- Test: `test/backup/canonical_json_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: nothing.
- Produces: `String canonicalJsonEncode(Object? value)`, `String canonicalHash(Object? value)` (lowercase hex sha256), `String bodyChecksumOf(String json)` (lowercase hex md5 of exact bytes).

`bodyChecksumOf` exists because Drive returns a **server-computed** checksum for stored content, while the `contentHash` this app writes into the target's metadata is client-supplied and goes stale if the file is edited by hand in a web UI. Comparing local bytes against the server's own checksum is how the engine trusts the body without downloading it.

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
      expect(
        canonicalJsonEncode({'outer': {'z': 1, 'y': 2}}),
        canonicalJsonEncode({'outer': {'y': 2, 'z': 1}}),
      );
    });

    test('sorts maps nested inside lists', () {
      expect(
        canonicalJsonEncode({'items': [{'q': 1, 'p': 2}]}),
        canonicalJsonEncode({'items': [{'p': 2, 'q': 1}]}),
      );
    });

    test('preserves list order, which is meaningful', () {
      expect(canonicalJsonEncode({'l': [1, 2]}),
          isNot(canonicalJsonEncode({'l': [2, 1]})));
    });

    test('round-trips through jsonDecode unchanged in value', () {
      final original = <String, dynamic>{'b': [1, 2], 'a': {'z': 'x'}};
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

  group('bodyChecksumOf', () {
    test('is 32 lowercase hex characters', () {
      expect(bodyChecksumOf('{"a":1}'), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('is a function of the exact bytes, not the parsed value', () {
      expect(bodyChecksumOf('{"a":1}'), isNot(bodyChecksumOf('{"a": 1}')),
          reason: 'it mirrors a server checksum over stored bytes');
    });

    test('agrees for the canonical encoding of equal content', () {
      expect(bodyChecksumOf(canonicalJsonEncode({'b': 1, 'a': 2})),
          bodyChecksumOf(canonicalJsonEncode({'a': 2, 'b': 1})));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/canonical_json_test.dart`
Expected: FAIL — `Couldn't resolve the package 'navigation_app/services/backup/canonical_json.dart'`

- [ ] **Step 3: Declare the dependency**

Add under `dependencies:` in `pubspec.yaml`, after `shared_preferences`:

```yaml
  crypto: ^3.0.3
```

```bash
flutter pub get
grep -n "^  crypto:" pubspec.yaml
```

- [ ] **Step 4: Implement**

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
/// would otherwise hash differently and conflict forever.
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

/// Lowercase hex MD5 of the exact bytes of [json].
///
/// Mirrors the server-computed checksum a storage backend returns for stored
/// content. Unlike the `contentHash` this app writes into the target's own
/// metadata, a server checksum cannot go stale: it is recomputed from
/// whatever bytes are actually there, including after a hand edit in a web UI.
String bodyChecksumOf(String json) =>
    md5.convert(utf8.encode(json)).toString();
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/backup/canonical_json_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/canonical_json.dart test/backup/canonical_json_test.dart pubspec.yaml pubspec.lock
git commit -m "feat(backup): canonical JSON, content hash, and body checksum"
```

---

### Task 3: The fault type

**Test-policy class: trust contract.** Retry classification and the fingerprint are behaviour other code branches on.

**Files:**
- Create: `lib/services/backup/app_fault.dart`
- Test: `test/backup/app_fault_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppFault` with `domain`, `kind`, `message`, `operation`, `targetIdentity`, `cause`, `isRetryable`, `sweepOnly`, `needsUserAction`, `fingerprint`; `enum FaultDomain { backup, roland, camera }`; `enum BackupFailureKind`.

The type is general from day one because the log is persisted, and widening a stored entry's shape once it holds real entries means migrating saved data. Only `FaultDomain.backup` is produced in this plan.

The fingerprint is `(domain, kind, operation, targetIdentity)` per the spec. It excludes `message`: real exception text carries timeouts and request ids that differ every occurrence, so collapsing on it collapses nothing and a retry storm evicts the entry that mattered.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/app_fault_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';

void main() {
  group('retry classification', () {
    test('offline, rateLimited and transientServer retry automatically', () {
      for (final k in [
        BackupFailureKind.offline,
        BackupFailureKind.rateLimited,
        BackupFailureKind.transientServer,
      ]) {
        final f = AppFault.backup(k, 'x');
        expect(f.isRetryable, isTrue, reason: '$k should be retryable');
        expect(f.sweepOnly, isFalse, reason: '$k backs off promptly');
        expect(f.needsUserAction, isFalse);
      }
    });

    test('kinds a human must fix do not retry', () {
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
        expect(f.needsUserAction, isTrue);
      }
    });

    test('conflict is a question, not a failure', () {
      final f = AppFault.backup(BackupFailureKind.conflict, 'x');
      expect(f.isRetryable, isFalse);
      expect(f.needsUserAction, isTrue);
    });

    test('unknown retries only on the slow sweep', () {
      final f = AppFault.backup(BackupFailureKind.unknown, 'x');
      expect(f.isRetryable, isTrue);
      expect(f.sweepOnly, isTrue,
          reason: 'a tight loop around a permanent bug burns battery forever');
    });
  });

  group('fingerprint', () {
    AppFault f(BackupFailureKind k, String m, {String? op, String? target}) =>
        AppFault.backup(k, m, operation: op, targetIdentity: target);

    test('ignores the message so varying detail still collapses', () {
      expect(
        f(BackupFailureKind.offline, 'timed out after 5002ms', op: 'push')
            .fingerprint,
        f(BackupFailureKind.offline, 'timed out after 7113ms', op: 'push')
            .fingerprint,
      );
    });

    test('distinguishes operation', () {
      expect(f(BackupFailureKind.offline, 'x', op: 'push').fingerprint,
          isNot(f(BackupFailureKind.offline, 'x', op: 'pull').fingerprint));
    });

    test('distinguishes target identity', () {
      expect(
        f(BackupFailureKind.offline, 'x', op: 'push', target: 'folder-A')
            .fingerprint,
        isNot(f(BackupFailureKind.offline, 'x', op: 'push', target: 'folder-B')
            .fingerprint),
        reason: 'faults against different targets are different incidents',
      );
    });

    test('distinguishes domain', () {
      expect(
        f(BackupFailureKind.offline, 'x', op: 'push').fingerprint,
        isNot(const AppFault(
                domain: FaultDomain.roland,
                kind: 'disconnected',
                message: 'x',
                operation: 'push')
            .fingerprint),
      );
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

  /// Which storage target this happened against.
  final String? targetIdentity;

  final Object? cause;

  const AppFault({
    required this.domain,
    required this.kind,
    required this.message,
    this.operation,
    this.targetIdentity,
    this.cause,
  });

  factory AppFault.backup(
    BackupFailureKind kind,
    String message, {
    String? operation,
    String? targetIdentity,
    Object? cause,
  }) =>
      AppFault(
        domain: FaultDomain.backup,
        kind: kind.name,
        message: message,
        operation: operation,
        targetIdentity: targetIdentity,
        cause: cause,
      );

  static const _promptRetry = {'offline', 'rateLimited', 'transientServer'};
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

  /// Retryable, but only on the slow periodic sweep. A tight backoff loop
  /// around a permanent programmer error would spin forever.
  bool get sweepOnly => _sweepOnly.contains(kind);

  /// Whether waiting and trying again can fix this without a human.
  bool get isRetryable => _promptRetry.contains(kind) || sweepOnly;

  bool get needsUserAction => _needsHuman.contains(kind);

  /// Log collapsing key, per the spec: domain, kind, operation, target.
  String get fingerprint =>
      '${domain.name}/$kind/${operation ?? "-"}/${targetIdentity ?? "-"}';

  @override
  String toString() => 'AppFault(${domain.name}/$kind): $message';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/app_fault_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/app_fault.dart test/backup/app_fault_test.dart
git commit -m "feat(backup): AppFault with retry classification and target-aware fingerprint"
```

---

### Task 4: Revision metadata, target interface, and mock

**Test-policy class: trust contract** for `MockBackupTarget` — it is a real implementation every later test depends on, and a weak mock produces tests that pass against no-ops.

**Files:**
- Create: `lib/services/backup/backup_revision.dart`
- Create: `lib/services/backup/abstract/backup_target_abstract.dart`
- Create: `lib/services/backup/mock/mock_backup_target.dart`
- Test: `test/backup/mock_backup_target_test.dart`

**Interfaces:**
- Consumes: `AppFault`, `BackupFailureKind` (Task 3); `bodyChecksumOf` (Task 2).
- Produces: `BackupRevision` (`id`, `filename`, `createdAt`, `contentHash`, `bodyChecksum`, `parentRevisionId`, `sizeBytes`, `deviceLabel`, `copyWith`); `BackupTargetAbstract` (`put`, `latest`, `list`, `fetch`, `prune`); `MockBackupTarget` (`failNextWith`, `delayNextBy`, `advanceClock`, `corruptMetadataOf`, `concurrentWriterBeforePut`, `revisions`).

Follows the `abstract/` + `mock/` split already used by `RolandServiceAbstract` and `MockRolandService`. There is no `siblings()` — `list(limit:)` plus a filter answers the same question without forcing every implementation to grow a specialised query.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/mock_backup_target_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_revision.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';

void main() {
  late MockBackupTarget target;

  setUp(() => target = MockBackupTarget());

  Future<BackupRevision> put(String body,
          {String? parent, String label = 'Mac mini'}) =>
      target.put(body,
          contentHash: 'h-$body',
          parentRevisionId: parent,
          deviceLabel: label);

  test('latest returns null when empty', () async {
    expect(await target.latest(), isNull);
  });

  test('put stores a revision and latest returns it', () async {
    final rev = await put('{"a":1}');
    final latest = await target.latest();
    expect(latest!.id, rev.id);
    expect(latest.deviceLabel, 'Mac mini');
    expect(latest.parentRevisionId, isNull);
  });

  test('bodyChecksum is computed from the stored bytes, not supplied', () async {
    final rev = await put('{"a":1}');
    expect(rev.bodyChecksum, bodyChecksumOf('{"a":1}'));
  });

  test('put never overwrites: two puts make two revisions', () async {
    final a = await put('{"a":1}');
    final b = await put('{"a":2}', parent: a.id);
    expect(a.id, isNot(b.id));
    expect((await target.list()).length, 2);
  });

  test('list is newest first', () async {
    final a = await put('{"a":1}');
    final b = await put('{"a":2}', parent: a.id);
    expect((await target.list()).map((r) => r.id).toList(), [b.id, a.id]);
  });

  test('fetch returns the exact body that was put', () async {
    final rev = await put('{"a":1}');
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
    final base = await put('{"a":1}');
    target.concurrentWriterBeforePut(
        body: '{"a":9}', parentRevisionId: base.id, deviceLabel: 'iPad');

    final mine = await put('{"a":2}', parent: base.id);

    final siblings = (await target.list())
        .where((r) => r.parentRevisionId == base.id)
        .toList();
    expect(siblings.length, 2, reason: 'a fork now exists');
    expect(siblings.map((r) => r.id), contains(mine.id));
  });

  test('corruptMetadataOf makes contentHash lie while bodyChecksum stays true',
      () async {
    final rev = await put('{"a":1}');
    target.corruptMetadataOf(rev.id, contentHash: 'a-stale-lie');

    final latest = await target.latest();
    expect(latest!.contentHash, 'a-stale-lie');
    expect(latest.bodyChecksum, bodyChecksumOf('{"a":1}'),
        reason: 'a server checksum cannot go stale; client metadata can');
  });

  test('delayNextBy makes the next call slow, so ordering can be observed',
      () async {
    target.delayNextBy(const Duration(milliseconds: 60));
    final started = DateTime.now();
    await target.latest();
    expect(DateTime.now().difference(started).inMilliseconds,
        greaterThanOrEqualTo(50));
  });

  group('prune', () {
    test('keeps a revision beyond keepCount when it is not yet old', () async {
      for (var i = 0; i < 5; i++) {
        await put('{"a":$i}');
      }
      await target.prune(keepCount: 2, keepFor: const Duration(days: 90));
      expect((await target.list()).length, 5,
          reason: 'deletion needs BOTH beyond count AND older than keepFor');
    });

    test('keeps an old revision that is still within keepCount', () async {
      for (var i = 0; i < 3; i++) {
        await put('{"a":$i}');
      }
      target.advanceClock(const Duration(days: 365));
      await target.prune(keepCount: 10, keepFor: const Duration(days: 90));
      expect((await target.list()).length, 3);
    });

    test('deletes only revisions that are BOTH beyond count AND old', () async {
      for (var i = 0; i < 5; i++) {
        await put('{"a":$i}');
      }
      target.advanceClock(const Duration(days: 365));
      await target.prune(keepCount: 2, keepFor: const Duration(days: 90));
      expect((await target.list()).length, 2,
          reason: 'the three oldest are beyond count and old, so they go');
    });
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

  /// SHA-256 of the canonical body, written by the client into the target's
  /// own metadata. **Not trustworthy on its own** — it is not recomputed when
  /// the body changes, so a hand edit in a storage web UI leaves it stale.
  final String contentHash;

  /// Checksum computed by the *server* over the stored bytes. Cannot go
  /// stale. This is what the engine compares against to decide whether local
  /// content already exists at the target.
  final String bodyChecksum;

  /// The revision this one was edited from. Null for the first revision.
  /// Makes fork detection and the pull ancestry test possible.
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
    required this.bodyChecksum,
    required this.parentRevisionId,
    required this.sizeBytes,
    required this.deviceLabel,
  });

  BackupRevision copyWith({String? contentHash}) => BackupRevision(
        id: id,
        filename: filename,
        createdAt: createdAt,
        contentHash: contentHash ?? this.contentHash,
        bodyChecksum: bodyChecksum,
        parentRevisionId: parentRevisionId,
        sizeBytes: sizeBytes,
        deviceLabel: deviceLabel,
      );
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

  /// Downloads a revision's body.
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
import '../canonical_json.dart';

/// In-memory target for tests.
///
/// Scriptable to fail, to be slow, to have another machine write between a
/// caller's `latest()` and its `put()`, and to carry stale client metadata
/// over an honest body — each a real failure mode the engine must survive
/// and that a test could otherwise pass without exercising.
class MockBackupTarget implements BackupTargetAbstract {
  final List<BackupRevision> revisions = [];
  final Map<String, String> _bodies = {};

  AppFault? _nextFailure;
  Duration? _nextDelay;
  Map<String, String?>? _pendingConcurrentWrite;
  int _seq = 0;
  DateTime _clock = DateTime.utc(2026, 1, 1);

  /// The next call to any method throws [fault], once.
  void failNextWith(AppFault fault) => _nextFailure = fault;

  /// The next call to any method takes [d] before returning, once.
  void delayNextBy(Duration d) => _nextDelay = d;

  /// Moves the mock's clock forward, so retention can actually age things out.
  void advanceClock(Duration d) => _clock = _clock.add(d);

  /// Replace a revision's client-supplied [contentHash] with a lie, leaving
  /// its server [bodyChecksum] honest — what a hand edit in a web UI does.
  void corruptMetadataOf(String id, {required String contentHash}) {
    final i = revisions.indexWhere((r) => r.id == id);
    if (i >= 0) revisions[i] = revisions[i].copyWith(contentHash: contentHash);
  }

  /// Insert a revision by another writer immediately before the next [put],
  /// reproducing the time-of-check/time-of-use race no compare-and-swap can
  /// prevent on Drive.
  void concurrentWriterBeforePut({
    required String body,
    required String? parentRevisionId,
    required String deviceLabel,
  }) {
    _pendingConcurrentWrite = {
      'body': body,
      'parentRevisionId': parentRevisionId,
      'deviceLabel': deviceLabel,
    };
  }

  Future<void> _gate() async {
    final d = _nextDelay;
    if (d != null) {
      _nextDelay = null;
      await Future<void>.delayed(d);
    }
    final f = _nextFailure;
    if (f != null) {
      _nextFailure = null;
      throw f;
    }
  }

  BackupRevision _insert(
    String json,
    String contentHash,
    String? parentRevisionId,
    String deviceLabel,
  ) {
    final id = 'rev-${++_seq}';
    _clock = _clock.add(const Duration(seconds: 1));
    final rev = BackupRevision(
      id: id,
      filename: 'nav_config_${_clock.toIso8601String()}.json',
      createdAt: _clock,
      contentHash: contentHash,
      bodyChecksum: bodyChecksumOf(json),
      parentRevisionId: parentRevisionId,
      sizeBytes: json.length,
      deviceLabel: deviceLabel,
    );
    revisions.add(rev);
    _bodies[id] = json;
    return rev;
  }

  List<BackupRevision> _ordered() {
    return [...revisions]..sort((a, b) {
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
  }

  @override
  Future<BackupRevision> put(
    String json, {
    required String contentHash,
    required String? parentRevisionId,
    required String deviceLabel,
  }) async {
    await _gate();
    final pending = _pendingConcurrentWrite;
    if (pending != null) {
      _pendingConcurrentWrite = null;
      _insert(pending['body']!, 'h-theirs', pending['parentRevisionId'],
          pending['deviceLabel']!);
    }
    return _insert(json, contentHash, parentRevisionId, deviceLabel);
  }

  @override
  Future<BackupRevision?> latest() async {
    await _gate();
    if (revisions.isEmpty) return null;
    return _ordered().first;
  }

  @override
  Future<List<BackupRevision>> list({int limit = 50}) async {
    await _gate();
    return _ordered().take(limit).toList();
  }

  @override
  Future<String> fetch(BackupRevision revision) async {
    await _gate();
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
    await _gate();
    final ordered = _ordered();
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
Expected: PASS, 13 tests.

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

**Test-policy class: trust contract** for the notifier. The eight store call sites are **wiring** and get one thin test proving a store reports its own writes.

**Files:**
- Create: `lib/services/backup/config_mutation_notifier.dart`
- Modify: the eight `lib/services/*_store.dart` files
- Test: `test/backup/config_mutation_notifier_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `ConfigMutationNotifier.instance` with `notify()`, `onMutated` (`Stream<int>`), `generation()`, `syncedGeneration()`, `markSynced(int)`, `isDirty()`, `suspendWhile<T>(...)`, and the public key names `generationKey` / `syncedKey`.

Nothing in this codebase can currently report that config changed. All eight stores are static classes over `SharedPreferences` with no stream or notifier. The spec is explicit that a hash guard is no substitute: **a guard suppresses a redundant write after a trigger; it cannot manufacture a trigger that never fired.**

**Deliberate substitution from the spec:** the spec says to persist "the dirty hash" at mutation time. This uses a monotonic generation counter — same question answered, O(1) at mutation time where hashing the whole bundle is O(bundle) on every save.

`suspendWhile` exists because a restore writes through these same stores. Without it, applying a pulled revision emits mutation events that the scheduler debounces into a push of what was just pulled.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/config_mutation_notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue);
  });

  test('markSynced for a stale generation does not clear a newer edit',
      () async {
    await ConfigMutationNotifier.instance.notify(); // 1
    await ConfigMutationNotifier.instance.notify(); // 2
    await ConfigMutationNotifier.instance.markSynced(1);
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'an edit made during an in-flight push must stay pending');
  });

  test('dirty state is persisted, so it survives a restart', () async {
    await ConfigMutationNotifier.instance.notify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
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

  group('suspendWhile', () {
    test('neither bumps the generation nor emits, so a restore is not an edit',
        () async {
      final seen = <int>[];
      final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);

      await ConfigMutationNotifier.instance.suspendWhile(() async {
        await ConfigMutationNotifier.instance.notify();
        await ConfigMutationNotifier.instance.notify();
      });

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(await ConfigMutationNotifier.instance.generation(), 0);
      expect(seen, isEmpty);
    });

    test('resumes notifying afterwards, even if the body threw', () async {
      await expectLater(
        ConfigMutationNotifier.instance
            .suspendWhile(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      await ConfigMutationNotifier.instance.notify();
      expect(await ConfigMutationNotifier.instance.generation(), 1,
          reason: 'a failed restore must not leave notifications muted');
    });
  });

  group('store wiring', () {
    test('a store write notifies', () async {
      final before = await ConfigMutationNotifier.instance.generation();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      expect(await ConfigMutationNotifier.instance.generation(), before + 1,
          reason: 'a store that does not report is never backed up');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/config_mutation_notifier_test.dart`
Expected: FAIL — package not resolvable.

- [ ] **Step 3: Implement**

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

  static const String generationKey = 'backup_mutation_generation';
  static const String syncedKey = 'backup_synced_generation';

  final _controller = StreamController<int>.broadcast();
  bool _suspended = false;

  /// Emits the new generation each time config changes.
  Stream<int> get onMutated => _controller.stream;

  Future<int> generation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(generationKey) ?? 0;
  }

  Future<int> syncedGeneration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(syncedKey) ?? 0;
  }

  Future<bool> isDirty() async =>
      await generation() != await syncedGeneration();

  Future<void> notify() async {
    if (_suspended) return;
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(generationKey) ?? 0) + 1;
    await prefs.setInt(generationKey, next);
    _controller.add(next);
  }

  /// Records that [generation] has been durably stored at the target.
  ///
  /// Never clears a generation newer than the one that was pushed: an edit
  /// made while a push was in flight must stay dirty.
  Future<void> markSynced(int generation) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(syncedKey) ?? 0;
    if (generation > current) await prefs.setInt(syncedKey, generation);
  }

  /// Runs [body] with notifications muted.
  ///
  /// A restore writes through the same stores a user edit does. Without this,
  /// applying a pulled revision emits mutation events and the scheduler
  /// debounces them into a push of what was just pulled.
  Future<T> suspendWhile<T>(Future<T> Function() body) async {
    _suspended = true;
    try {
      return await body();
    } finally {
      _suspended = false;
    }
  }
}
```

- [ ] **Step 4: Wire the eight stores**

In each file below, add the import and one line immediately after the existing `prefs.set...` write, before the method returns:

```dart
import 'backup/config_mutation_notifier.dart';
```

```dart
    await ConfigMutationNotifier.instance.notify();
```

| File | Method(s) |
|---|---|
| `position_store.dart` | `saveAll` |
| `people_store.dart` | `saveAll` |
| `service_store.dart` | `saveAll` |
| `height_range_store.dart` | `saveAll` |
| `operator_store.dart` | `saveAll` **and** `saveActiveId` |
| `preset_name_store.dart` | `save` |
| `visibility_store.dart` | `save` |
| `device_config_store.dart` | `save` |

- [ ] **Step 5: Verify every store is wired**

```bash
grep -L "ConfigMutationNotifier" \
  lib/services/position_store.dart lib/services/people_store.dart \
  lib/services/service_store.dart lib/services/height_range_store.dart \
  lib/services/operator_store.dart lib/services/preset_name_store.dart \
  lib/services/visibility_store.dart lib/services/device_config_store.dart
```

Expected: no output. Any filename printed is a store whose changes would silently never be backed up.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/backup/config_mutation_notifier_test.dart`
Expected: PASS, 9 tests.

Run: `flutter test --concurrency=1 && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/services/backup/config_mutation_notifier.dart \
        lib/services/*_store.dart \
        test/backup/config_mutation_notifier_test.dart
git commit -m "feat(backup): mutation notifier with durable generation and restore suspension"
```

---

### Task 6: Required schema version and one parser

**Test-policy class: trust contract.** Validation decides whether a truncated document silently wipes four stores.

**Files:**
- Modify: `lib/services/config_bundle.dart`
- Modify: `test/config_bundle_test.dart`
- Test: `test/backup/config_bundle_schema_test.dart`

**Interfaces:**
- Consumes: `AppFault`, `BackupFailureKind` (Task 3).
- Produces: `ConfigBundle.schemaVersion` (`int`), `ConfigBundle.currentSchemaVersion` (`= 1`), `ConfigBundle.fromJsonValidated(Map<String, dynamic>)` — the **only** parser.

The rules, from the spec. There is **one** schema — no legacy branch, because no document predating it exists:

| Field | Rule |
|---|---|
| `schemaVersion` | **Required**, and must equal `currentSchemaVersion`. Absent, non-integer, or any other value → `malformedRemote`. Greater than current → `unsupportedSchema`. |
| `positions`, `people`, `services`, `heightRanges` | **Required** lists of objects. Absent or wrong type → `malformedRemote`. Empty list is valid. |
| `presetNames`, `visibilities` | Absent → `{}`. Present but not a map of maps of strings → `malformedRemote`. |
| `rolandIp`, `cameras`, `operators` | Absent → **reset to defaults** on apply (Task 8). |

`presetNames` and `visibilities` stay **non-nullable**. **`fromJson` is deleted, not kept alongside** — two parsers with different strictness is the same baggage as two apply paths, and the permissive one is what the manual-import UI actually calls.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/config_bundle_schema_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/config_bundle.dart';

Map<String, dynamic> valid([Map<String, dynamic> extra = const {}]) => {
      'schemaVersion': 1,
      'positions': <dynamic>[],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
      ...extra,
    };

Matcher throwsKind(BackupFailureKind k) => throwsA(
    predicate((e) => e is AppFault && e.kind == k.name, 'AppFault ${k.name}'));

void main() {
  group('version', () {
    test('a valid document parses and reports its version', () {
      expect(ConfigBundle.fromJsonValidated(valid()).schemaVersion, 1);
    });

    test('a missing schemaVersion is malformed', () {
      expect(
          () => ConfigBundle.fromJsonValidated(valid()..remove('schemaVersion')),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a non-integer schemaVersion is malformed', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'schemaVersion': 'one'})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('schemaVersion 0 is malformed, not an implicit old schema', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'schemaVersion': 0})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a negative schemaVersion is malformed', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'schemaVersion': -1})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a newer version than this build is refused, not downgraded', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'schemaVersion': 99})),
          throwsKind(BackupFailureKind.unsupportedSchema));
    });
  });

  group('required fields', () {
    test('{} is malformed, not an empty bundle that wipes four stores', () {
      expect(() => ConfigBundle.fromJsonValidated(<String, dynamic>{}),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    for (final f in ['positions', 'people', 'services', 'heightRanges']) {
      test('missing $f is malformed', () {
        expect(() => ConfigBundle.fromJsonValidated(valid()..remove(f)),
            throwsKind(BackupFailureKind.malformedRemote));
      });

      test('$f of the wrong type is malformed', () {
        expect(() => ConfigBundle.fromJsonValidated(valid({f: 'nope'})),
            throwsKind(BackupFailureKind.malformedRemote));
      });
    }

    test('empty lists are valid — clearing everything is a legitimate edit',
        () {
      expect(ConfigBundle.fromJsonValidated(valid()).positions, isEmpty);
    });
  });

  group('optional fields', () {
    test('absent presetNames means explicitly none', () {
      expect(ConfigBundle.fromJsonValidated(valid()).presetNames, isEmpty);
    });

    test('absent visibilities means explicitly none', () {
      expect(ConfigBundle.fromJsonValidated(valid()).visibilities, isEmpty);
    });

    test('presetNames of the wrong shape is malformed, not silently empty', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'presetNames': 'nope'})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a malformed list entry is an AppFault, not a raw TypeError', () {
      expect(
          () => ConfigBundle.fromJsonValidated(valid({'positions': ['nope']})),
          throwsKind(BackupFailureKind.malformedRemote));
    });
  });

  test('toJson stamps the current version and always emits both maps', () {
    final json = ConfigBundle.fromJsonValidated(valid()).toJson();
    expect(json['schemaVersion'], ConfigBundle.currentSchemaVersion);
    expect(json.containsKey('presetNames'), isTrue);
    expect(json.containsKey('visibilities'), isTrue);
  });

  test('a bundle round-trips through toJson and back', () {
    final original = ConfigBundle.fromJsonValidated(valid());
    final again = ConfigBundle.fromJsonValidated(original.toJson());
    expect(again.schemaVersion, original.schemaVersion);
    expect(again.positions.length, original.positions.length);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/config_bundle_schema_test.dart`
Expected: FAIL — `fromJsonValidated` is not defined.

- [ ] **Step 3: Add the field and replace the parser**

In `lib/services/config_bundle.dart`, add `import 'backup/app_fault.dart';`.

Add to the class:

```dart
  /// Schema version of the source document.
  final int schemaVersion;

  static const int currentSchemaVersion = 1;
```

and `required this.schemaVersion,` to the constructor.

**Delete the entire `factory ConfigBundle.fromJson(...)`** (`config_bundle.dart:66-88`) and the now-unused `_parseStringStringMaps` helper. Replace with:

```dart
  /// The only parser. Throws [AppFault] rather than silently producing an
  /// empty bundle: applying an all-empty bundle replaces four stores with
  /// nothing, so a truncated document must be a fault, not a destructive
  /// restore.
  factory ConfigBundle.fromJsonValidated(Map<String, dynamic> json) {
    Never bad(String why) =>
        throw AppFault.backup(BackupFailureKind.malformedRemote, why);

    final version = json['schemaVersion'];
    if (version is! int) bad('schemaVersion is missing or not an integer');
    if (version > currentSchemaVersion) {
      throw AppFault.backup(
          BackupFailureKind.unsupportedSchema,
          'This backup was written by a newer version of the app '
          '(schema $version, this build understands $currentSchemaVersion). '
          'Update the app to sync.');
    }
    if (version != currentSchemaVersion) {
      bad('schemaVersion $version is not a schema this app has ever written');
    }

    List<Map<String, dynamic>> requireObjectList(String field) {
      final raw = json[field];
      if (raw is! List) bad('required field "$field" is missing or not a list');
      return raw.map((e) {
        if (e is! Map<String, dynamic>) bad('"$field" contains a non-object');
        return e;
      }).toList();
    }

    Map<String, Map<String, String>> optionalStringMaps(String field) {
      final raw = json[field];
      if (raw == null) return const {};
      if (raw is! Map) bad('"$field" is present but not a map');
      final out = <String, Map<String, String>>{};
      raw.forEach((k, v) {
        if (v is! Map) bad('"$field.$k" is not a map');
        final inner = <String, String>{};
        v.forEach((ik, iv) {
          if (iv is! String) bad('"$field.$k.$ik" is not a string');
          inner['$ik'] = iv;
        });
        out['$k'] = inner;
      });
      return out;
    }

    T guard<T>(String field, T Function() parse) {
      try {
        return parse();
      } on AppFault {
        rethrow;
      } catch (e) {
        throw AppFault.backup(BackupFailureKind.malformedRemote,
            'could not parse "$field": $e',
            cause: e);
      }
    }

    return ConfigBundle(
      schemaVersion: version,
      positions: guard('positions',
          () => requireObjectList('positions').map(Position.fromJson).toList()),
      people: guard('people',
          () => requireObjectList('people').map(Person.fromJson).toList()),
      services: guard('services',
          () => requireObjectList('services').map(Service.fromJson).toList()),
      heightRanges: guard(
          'heightRanges',
          () => requireObjectList('heightRanges')
              .map(HeightRange.fromJson)
              .toList()),
      presetNames: optionalStringMaps('presetNames'),
      visibilities: optionalStringMaps('visibilities'),
      rolandIp: guard('rolandIp', () => json['rolandIp'] as String?),
      cameras: guard(
          'cameras',
          () => (json['cameras'] as List<dynamic>?)
              ?.map((c) => CameraEntry.fromJson(c as Map<String, dynamic>))
              .toList()),
      operators: guard(
          'operators',
          () => (json['operators'] as List<dynamic>?)
              ?.map((o) => OperatorProfile.fromJson(o as Map<String, dynamic>))
              .toList()),
    );
  }
```

Update `toJson`:

```dart
  Map<String, dynamic> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'positions': positions.map((p) => p.toJson()).toList(),
        'people': people.map((p) => p.toJson()).toList(),
        'services': services.map((s) => s.toJson()).toList(),
        'heightRanges': heightRanges.map((r) => r.toJson()).toList(),
        'presetNames': presetNames,
        'visibilities': visibilities,
        if (rolandIp != null) 'rolandIp': rolandIp,
        if (cameras != null)
          'cameras': cameras!.map((c) => c.toJson()).toList(),
        if (operators != null)
          'operators': operators!.map((o) => o.toJson()).toList(),
      };
```

- [ ] **Step 4: Fix EVERY construction site**

**Do not filter the grep.** The site that breaks hardest sits on the same line as the word `fromJson`, so `grep -v fromJson` hides exactly it:

```bash
grep -rn "ConfigBundle(" lib/ test/
```

Expected 8 hits:

| Site | Fix |
|---|---|
| `lib/services/config_bundle.dart:40` | the constructor — add `required this.schemaVersion` |
| `lib/services/config_bundle.dart` `fromJsonValidated` | already passes `schemaVersion: version` |
| `lib/services/config_bundle.dart:142` (`fromStores`) | add `schemaVersion: currentSchemaVersion,` |
| `test/config_bundle_test.dart:13` (`_full()`) | add `schemaVersion: ConfigBundle.currentSchemaVersion,` |
| `test/config_bundle_test.dart:121`, `:146`, `:243` | drop `const`, add `schemaVersion: ConfigBundle.currentSchemaVersion,` |
| `test/config_bundle_test.dart:132` | inside a test deleted in Step 5 — delete, do not fix |

- [ ] **Step 5: Delete superseded tests and move the rest off `fromJson`**

**Delete** outright from `test/config_bundle_test.dart`:

- `:110-118` — `'missing keys in JSON produce empty collections and empty maps'`. It blesses `{}` as a valid empty bundle, precisely the destructive restore the parser now refuses.
- `:131-136` — the test asserting `toJson` omits empty maps. `toJson` now always emits them.

Do not rename or invert either. Then replace every remaining `ConfigBundle.fromJson(` with `ConfigBundle.fromJsonValidated(`, making each fixture a complete valid document.

```bash
grep -rn "\.fromJson(" lib/ test/ | grep -vE "(Position|Person|Service|HeightRange|CameraEntry|OperatorProfile)\.fromJson"
```

Expected: no output.

- [ ] **Step 6: Route manual import through the one parser**

`readFromPath` (`config_bundle.dart:208-217`) returns `ConfigBundle.fromJson(json)`, so a manual `{}` file still becomes an empty bundle. Change it to:

```dart
    return ConfigBundle.fromJsonValidated(json);
```

- [ ] **Step 7: Run to verify it passes**

Run: `flutter test test/backup/config_bundle_schema_test.dart test/config_bundle_test.dart`
Expected: PASS.

Run: `flutter test --concurrency=1 && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 8: Commit**

```bash
git add lib/services/config_bundle.dart test/config_bundle_test.dart \
        test/backup/config_bundle_schema_test.dart
git commit -m "feat(backup): required schema version and a single validating parser"
```

---

### Task 7: The provenance pointer

**Test-policy class: trust contract.** Every row of the spec's transition table is behaviour the protocol depends on.

This comes **before** the journal so Task 8's apply can clear it, per the spec's "manual import → null" transition.

**Files:**
- Create: `lib/services/backup/backup_pointer.dart`
- Test: `test/backup/backup_pointer_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `BackupPointer` with `revisionId`, `recordedHash`, `targetIdentity`, `isProvenanced`, `matchesTarget`, `isCleanAgainst`; statics `load()`, `save(...)`, `clear()`, and the public key names `revisionKey`, `hashKey`, `targetKey`.

The pointer is deliberately **not** a field on `ConfigBundle`: putting provenance in the hashed body would change the hash on every upload and defeat the guard. It is stored with the target identity, because a pointer captured against one folder or account says nothing about another.

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
    expect((await BackupPointer.load()).matchesTarget('folder-B'), isFalse,
        reason: 'comparing across accounts or folders is meaningless');
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
    expect((await BackupPointer.load()).isCleanAgainst('anything'), isFalse,
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
/// Stored beside the target identity: a pointer captured against one storage
/// folder or account says nothing about another, and comparing across them
/// would produce confident nonsense.
class BackupPointer {
  static const String revisionKey = 'backup_source_revision';
  static const String hashKey = 'backup_source_hash';
  static const String targetKey = 'backup_target_identity';

  final String? revisionId;
  final String? recordedHash;
  final String? targetIdentity;

  const BackupPointer(
      {this.revisionId, this.recordedHash, this.targetIdentity});

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
      revisionId: prefs.getString(revisionKey),
      recordedHash: prefs.getString(hashKey),
      targetIdentity: prefs.getString(targetKey),
    );
  }

  static Future<void> save({
    required String revisionId,
    required String recordedHash,
    required String targetIdentity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(revisionKey, revisionId);
    await prefs.setString(hashKey, recordedHash);
    await prefs.setString(targetKey, targetIdentity);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(revisionKey);
    await prefs.remove(hashKey);
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

### Task 8: Rollback journal and the transactional import contract

**Test-policy class: trust contract.** The highest-stakes task in the plan: it decides whether a failed import leaves configuration in one piece.

**Files:**
- Create: `lib/services/backup/restore_journal.dart`
- Modify: `lib/services/config_bundle.dart` — **delete** `saveToStores`, add `applyTransactionally`
- Modify: `lib/widgets/settings_dialog.dart:294-304`
- Modify: `test/config_bundle_test.dart`
- Test: `test/backup/restore_journal_test.dart`

**Interfaces:**
- Consumes: `ConfigBundle` (Task 6), `BackupPointer` (Task 7), `ConfigMutationNotifier` (Task 5).
- Produces: `RestoreJournal.{key, capture, rollbackIfPresent, clear, isJournalled}`; `ConfigBundle.applyTransactionally({int? failAfterWritesForTest})`.

Three corrections to current behaviour, all from the spec:

1. `saveToStores` is **not** a full replace today: the preset/visibility loops only `setString` keys present in the bundle, so a device key absent from the bundle is never deleted. Now it is.
2. Absent `rolandIp` / `cameras` / `operators` are currently **skipped**, leaving machine values in place. Absent now means reset to defaults.
3. The apply is a series of independent writes; a failure partway leaves a hybrid that `fromStores()` will upload as a valid revision.

The journal must also capture the **notifier and pointer keys**. Rolling back the stores while leaving the generation advanced would make `isDirty` lie.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/restore_journal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/backup/restore_journal.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/device_config_store.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/services/visibility_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> bundleJson([Map<String, dynamic> extra = const {}]) => {
      'schemaVersion': 1,
      'positions': <dynamic>[],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
      ...extra,
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('full replacement', () {
    test('deletes preset keys absent from the incoming bundle', () async {
      await PresetNameStore.save('10.0.1.10', 3, 'Close Up');
      expect(await PresetNameStore.loadAll('10.0.1.10'), isNotEmpty);

      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally();

      expect(await PresetNameStore.loadAll('10.0.1.10'), isEmpty,
          reason: 'absent means explicitly none');
    });

    test('deletes visibility keys absent from the incoming bundle', () async {
      await VisibilityStore.save('roland_10.0.1.20', 5, ItemVisibility.hide);
      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally();
      expect(await VisibilityStore.loadAll('roland_10.0.1.20'), isEmpty);
    });

    test('keeps preset keys the bundle DOES list', () async {
      await ConfigBundle.fromJsonValidated(bundleJson({
        'presetNames': {
          '10.0.1.10': {'3': 'Ambo'}
        }
      })).applyTransactionally();
      expect(await PresetNameStore.loadAll('10.0.1.10'), {3: 'Ambo'});
    });

    test('absent rolandIp and cameras RESET to defaults', () async {
      await DeviceConfigStore.save(
          '192.168.9.9', const [CameraEntry(name: 'Odd', ip: '192.168.9.10')]);

      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally();

      expect(await DeviceConfigStore.loadRolandIp(),
          DeviceConfigStore.defaultRolandIp,
          reason: 'absent means default, not "leave the machine alone"');
      expect((await DeviceConfigStore.loadCameras()).first.ip,
          DeviceConfigStore.defaultCameras.first.ip);
    });

    test('absent operators RESET to defaults', () async {
      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally();
      expect(await OperatorStore.loadAll(), isNotEmpty);
    });
  });

  group('transactionality', () {
    test('a failure after the FIRST write leaves the stores wholly old',
        () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      await PresetNameStore.save('10.0.1.10', 3, 'Close Up');

      await expectLater(
        ConfigBundle.fromJsonValidated(bundleJson())
            .applyTransactionally(failAfterWritesForTest: 1),
        throwsA(isA<StateError>()),
      );

      expect((await PositionStore.loadAll()).length, 1);
      expect(await PresetNameStore.loadAll('10.0.1.10'), {3: 'Close Up'});
    });

    test('a failure DURING the preset replace still leaves stores wholly old',
        () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      await PresetNameStore.save('10.0.1.10', 3, 'Close Up');

      // Writes: 4 lists, device, operators, then the prefix replacement.
      // Failing at 7 lands inside the preset delete — the correction this
      // task exists for, and a step the old seam could not reach.
      await expectLater(
        ConfigBundle.fromJsonValidated(bundleJson())
            .applyTransactionally(failAfterWritesForTest: 7),
        throwsA(isA<StateError>()),
      );

      expect((await PositionStore.loadAll()).length, 1,
          reason: 'positions were overwritten then rolled back');
      expect(await PresetNameStore.loadAll('10.0.1.10'), {3: 'Close Up'},
          reason: 'the preset delete was rolled back too');
    });

    test('a successful apply leaves the stores wholly new', () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      await ConfigBundle.fromJsonValidated(bundleJson({
        'positions': [
          {'id': 'p2', 'name': 'Altar'}
        ]
      })).applyTransactionally();

      final loaded = await PositionStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded.single.id, 'p2');
    });

    test('rollback restores the mutation generation too', () async {
      await ConfigMutationNotifier.instance.notify();
      final before = await ConfigMutationNotifier.instance.generation();

      await expectLater(
        ConfigBundle.fromJsonValidated(bundleJson())
            .applyTransactionally(failAfterWritesForTest: 1),
        throwsA(isA<StateError>()),
      );

      expect(await ConfigMutationNotifier.instance.generation(), before,
          reason: 'stores old but generation ahead would make isDirty lie');
    });

    test('a journal left behind by a crash is rolled back', () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      await RestoreJournal.capture();
      await PositionStore.saveAll([]);

      await RestoreJournal.rollbackIfPresent();

      expect((await PositionStore.loadAll()).length, 1);
    });

    test('rollbackIfPresent is a no-op when no journal exists', () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      await RestoreJournal.rollbackIfPresent();
      expect((await PositionStore.loadAll()).length, 1);
    });

    test('a successful apply leaves no journal behind', () async {
      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RestoreJournal.key), isNull);
    });
  });

  group('side effects', () {
    test('applying does NOT count as a user edit', () async {
      final seen = <int>[];
      final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);

      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally();

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, isEmpty,
          reason: 'a restore that looks like an edit gets pushed straight back');
    });

    test('applying clears the provenance pointer', () async {
      await BackupPointer.save(
          revisionId: 'rev-1', recordedHash: 'h', targetIdentity: 'folder-A');

      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally();

      expect((await BackupPointer.load()).isProvenanced, isFalse,
          reason: 'imported state is unprovenanced pending work; the engine '
              're-establishes provenance itself when it applies a revision');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/restore_journal_test.dart`
Expected: FAIL — `restore_journal.dart` not found.

- [ ] **Step 3: Implement the journal**

Create `lib/services/backup/restore_journal.dart`:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backup_pointer.dart';
import 'config_mutation_notifier.dart';

/// Write-ahead journal that makes a multi-key import atomic.
///
/// `SharedPreferences` has no transaction. Applying a bundle touches a dozen
/// keys across eight stores, and a failure partway leaves a hybrid of old and
/// new that `ConfigBundle.fromStores()` will happily upload as a valid
/// revision. Capturing previous values first makes "wholly old or wholly new"
/// something that can actually be guaranteed.
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
    // Restoring stores without these would leave the generation ahead of the
    // data, so isDirty would lie and the next push would surface a phantom
    // conflict.
    ConfigMutationNotifier.generationKey,
    ConfigMutationNotifier.syncedKey,
    BackupPointer.revisionKey,
    BackupPointer.hashKey,
  ];

  static const _prefixes = <String>['preset_names_', 'item_visibility_'];

  static bool isJournalled(String k) =>
      _fixedKeys.contains(k) || _prefixes.any(k.startsWith);

  /// Snapshots every journalled key's current value.
  static Future<void> capture() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = <String, dynamic>{};
    for (final k in prefs.getKeys().where(isJournalled)) {
      snapshot[k] = prefs.get(k);
    }
    await prefs.setString(key, jsonEncode(snapshot));
  }

  /// Restores every captured key and drops the journal.
  ///
  /// Keys absent from the snapshot are removed, so a partial apply cannot
  /// leave behind a key the operator never had.
  static Future<void> rollbackIfPresent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return;

    final snapshot = jsonDecode(raw) as Map<String, dynamic>;
    for (final k in prefs.getKeys().where(isJournalled).toList()) {
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

- [ ] **Step 4: Replace `saveToStores` with `applyTransactionally`**

**Delete** `saveToStores()` from `lib/services/config_bundle.dart` and add:

```dart
  /// Applies this bundle to the live stores, atomically.
  ///
  /// Either every journalled key ends up matching this bundle, or none of
  /// them change. [failAfterWritesForTest] throws after N writes to prove the
  /// rollback works; every write increments the counter, so a failure can be
  /// injected at any materialization step.
  Future<void> applyTransactionally({int? failAfterWritesForTest}) async {
    await RestoreJournal.capture();
    var written = 0;
    void tick() {
      written++;
      if (failAfterWritesForTest != null && written >= failAfterWritesForTest) {
        throw StateError('injected failure after $written writes');
      }
    }

    try {
      await ConfigMutationNotifier.instance.suspendWhile(() async {
        final prefs = await SharedPreferences.getInstance();

        await PositionStore.saveAll(positions);
        tick();
        await PeopleStore.saveAll(people);
        tick();
        await ServiceStore.saveAll(services);
        tick();
        await HeightRangeStore.saveAll(heightRanges);
        tick();

        // Absent means reset to defaults, not "leave the machine alone".
        await DeviceConfigStore.save(
          rolandIp ?? DeviceConfigStore.defaultRolandIp,
          cameras ?? DeviceConfigStore.defaultCameras,
        );
        tick();
        await OperatorStore.saveAll(
            operators ?? const [OperatorProfile.defaultProfile]);
        tick();

        // Authoritative: any device key the bundle does not mention is
        // deleted. This is the correction to today's behaviour, where the
        // loops only setString keys that are present and never remove others.
        await _replacePrefixed(prefs, _presetPrefix, presetNames, tick);
        await _replacePrefixed(prefs, _visibilityPrefix, visibilities, tick);
      });

      // Imported state is unprovenanced pending work. The engine
      // re-establishes provenance itself after applying a fetched revision.
      await BackupPointer.clear();
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
    void Function() tick,
  ) async {
    for (final k
        in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      if (!incoming.containsKey(k.substring(prefix.length))) {
        await prefs.remove(k);
        tick();
      }
    }
    for (final entry in incoming.entries) {
      await prefs.setString('$prefix${entry.key}', jsonEncode(entry.value));
      tick();
    }
  }
```

Add to `config_bundle.dart` (check each is not already present):

```dart
import 'backup/backup_pointer.dart';
import 'backup/config_mutation_notifier.dart';
import 'backup/restore_journal.dart';
import '../models/operator_profile.dart';
```

- [ ] **Step 5: Update EVERY caller**

```bash
grep -rn "saveToStores" lib/ test/
```

Expected 7 hits outside `config_bundle.dart`. Fix all:

**`lib/widgets/settings_dialog.dart:294-304`** — the `if (bundle.rolandIp != null || bundle.cameras != null)` and `if (bundle.operators != null)` guards are the old preserve-if-absent contract. Apply now always writes those, so the UI must always refresh:

```dart
    await bundle.applyTransactionally();
    onDeviceConfigSaved(
      bundle.rolandIp ?? DeviceConfigStore.defaultRolandIp,
      bundle.cameras ?? DeviceConfigStore.defaultCameras,
    );
    await OperatorStore.saveActiveId(OperatorProfile.defaultId);
    onOperatorsChanged();
    onAllDataChanged();
```

**`test/config_bundle_test.dart`** — `:171`, `:196`, `:225`, `:241`, `:247`, `:259` become `applyTransactionally()`. Then **delete** `'saveToStores overwrites previous store contents'` (`:240-253`): it asserts only positions/people/services, which the spec names as blessing the incomplete replace, and Task 8's own suite covers full replacement properly including presets and device fields.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/backup/restore_journal_test.dart`
Expected: PASS, 13 tests.

Run: `flutter test --concurrency=1 && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/services/backup/restore_journal.dart lib/services/config_bundle.dart \
        lib/widgets/settings_dialog.dart test/config_bundle_test.dart \
        test/backup/restore_journal_test.dart
git commit -m "feat(backup): transactional import via a write-ahead rollback journal"
```

---

## Phase 2 — The Engine

### Task 9: Push

**Test-policy class: trust contract.** Push decides whether the other machine's work survives.

**Files:**
- Create: `lib/services/backup/backup_service.dart`
- Test: `test/backup/backup_service_push_test.dart`

**Interfaces:**
- Consumes: Tasks 2–8.
- Produces: `BackupService({required target, required targetIdentity, required deviceLabel, required readBundleJson, required localIsPristine})`; `Future<PushResult> push()`; `enum PushOutcome { noOp, uploaded, conflict, forked }`; `class PushResult`.

`localIsPristine` is required **from the start**, so Task 10 does not break these tests by adding it later.

Push steps, from the spec:

1. Local content already at the target → no-op. **If that head's id differs from the pointer, rebase.** Without the matching rebase a push that finds equivalent bytes under another id strands a stale pointer and the next genuine edit trips a phantom conflict.
2. `latest().id != pointer` → conflict; do not upload.
3. `put(json, parentRevisionId: pointer)`.
4. Re-read `list()` and check for another revision sharing our parent. **This does not promise pre-upload conflict detection** — there is no compare-and-swap — it promises honest detection immediately after.

Equality in step 1 is decided by the **server** `bodyChecksum`, never the client-written `contentHash`.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/backup_service_push_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

const identity = 'folder-A';

Map<String, dynamic> doc([String marker = 'base']) => {
      'schemaVersion': 1,
      'positions': [
        {'id': marker, 'name': marker}
      ],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
    };

void main() {
  late MockBackupTarget target;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    target = MockBackupTarget();
  });

  BackupService service(Map<String, dynamic> local) => BackupService(
        target: target,
        targetIdentity: identity,
        deviceLabel: () async => 'Mac mini',
        readBundleJson: () async => local,
        localIsPristine: () async => false,
      );

  test('first push uploads and records the pointer', () async {
    final r = await service(doc()).push();

    expect(r.outcome, PushOutcome.uploaded);
    expect(target.revisions.length, 1);
    final p = await BackupPointer.load();
    expect(p.revisionId, target.revisions.single.id);
    expect(p.recordedHash, canonicalHash(doc()));
  });

  test('pushing identical content is a no-op', () async {
    await service(doc()).push();
    final r = await service(doc()).push();
    expect(r.outcome, PushOutcome.noOp);
    expect(target.revisions.length, 1, reason: 'no second file');
  });

  test('a no-op against equal content under a different id rebases', () async {
    await target.put(canonicalJsonEncode(doc()),
        contentHash: canonicalHash(doc()),
        parentRevisionId: null,
        deviceLabel: 'iPad');

    final r = await service(doc()).push();

    expect(r.outcome, PushOutcome.noOp);
    expect((await BackupPointer.load()).revisionId, target.revisions.single.id,
        reason: 'a stale pointer trips a phantom conflict on the next edit');
  });

  test('equality is judged by the server checksum, not client metadata',
      () async {
    await service(doc()).push();
    // Somebody edits metadata at the target; the contentHash we wrote is now
    // a lie, but the server checksum still tracks the real bytes.
    target.corruptMetadataOf(target.revisions.single.id,
        contentHash: canonicalHash(doc('tampered')));

    final r = await service(doc()).push();

    expect(r.outcome, PushOutcome.noOp,
        reason: 'the BODY still matches, so there is nothing to upload; '
            'trusting contentHash would have said "different"');
    expect(target.revisions.length, 1);
  });

  test('a moved remote is a conflict and uploads nothing', () async {
    await service(doc()).push();
    await target.put('{"other":1}',
        contentHash: 'other',
        parentRevisionId: target.revisions.first.id,
        deviceLabel: 'iPad');

    final r = await service(doc('edited')).push();

    expect(r.outcome, PushOutcome.conflict);
    expect(r.remoteRevision!.deviceLabel, 'iPad');
    expect(target.revisions.length, 2, reason: 'nothing new was uploaded');
  });

  test('a concurrent writer between check and write is reported as a fork',
      () async {
    await service(doc()).push();
    final base = target.revisions.single;

    target.concurrentWriterBeforePut(
        body: '{"theirs":1}', parentRevisionId: base.id, deviceLabel: 'iPad');

    final r = await service(doc('edited')).push();

    expect(r.outcome, PushOutcome.forked,
        reason: 'no compare-and-swap exists; detection is after the fact');
    expect(r.siblings!.map((s) => s.deviceLabel), contains('iPad'));
  });

  test('a successful push clears dirty', () async {
    await ConfigMutationNotifier.instance.notify();
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue);
    await service(doc()).push();
    expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);
  });

  test('an edit made during a push stays dirty afterwards', () async {
    await ConfigMutationNotifier.instance.notify();
    final svc = BackupService(
      target: target,
      targetIdentity: identity,
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async {
        await ConfigMutationNotifier.instance.notify(); // lands mid-push
        return doc();
      },
      localIsPristine: () async => false,
    );

    await svc.push();

    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'the push only covered the generation it read');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_service_push_test.dart`
Expected: FAIL — `backup_service.dart` not found.

- [ ] **Step 3: Implement**

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

/// Owns the backup protocol.
///
/// Every operation runs through one single-flight queue. Pulls, debounced
/// pushes, periodic sweeps, manual retries and the backoff timer are
/// otherwise independent callers of the same mutable state, and an older
/// operation completing after a newer one would overwrite status or
/// provenance.
class BackupService {
  final BackupTargetAbstract target;
  final String targetIdentity;
  final Future<String> Function() deviceLabel;
  final Future<Map<String, dynamic>> Function() readBundleJson;

  /// Whether local configuration is untouched — nothing worth protecting.
  /// Only consulted when the pointer is null.
  final Future<bool> Function() localIsPristine;

  Future<void> _queue = Future<void>.value();

  BackupService({
    required this.target,
    required this.targetIdentity,
    required this.deviceLabel,
    required this.readBundleJson,
    required this.localIsPristine,
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

  Future<BackupPointer> _pointer() async {
    final p = await BackupPointer.load();
    return p.matchesTarget(targetIdentity) ? p : const BackupPointer();
  }

  Future<PushResult> push() => _single(_push);

  Future<PushResult> _push() async {
    final generation = await ConfigMutationNotifier.instance.generation();
    final bundle = await readBundleJson();
    final json = canonicalJsonEncode(bundle);
    final hash = canonicalHash(bundle);
    final localChecksum = bodyChecksumOf(json);

    final head = await target.latest();
    final pointer = await _pointer();

    // 1. The bytes are already there. Judged by the SERVER checksum: the
    //    contentHash we wrote is client metadata and goes stale if the file
    //    is edited by hand at the target.
    if (head != null && head.bodyChecksum == localChecksum) {
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

    // 4. Fork check. No compare-and-swap exists, so a second writer can pass
    //    step 2 concurrently. Both bodies survive; say so rather than pretend
    //    the race did not happen.
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
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_service.dart test/backup/backup_service_push_test.dart
git commit -m "feat(backup): push with server-checksum equality, rebase, and fork check"
```

---

### Task 10: Pull

**Test-policy class: trust contract.** Two of these branches destroy data if they are wrong.

**Files:**
- Modify: `lib/services/backup/backup_service.dart`
- Test: `test/backup/backup_service_pull_test.dart`

**Interfaces:**
- Consumes: Task 9.
- Produces: `Future<PullResult> pull()`; `enum PullOutcome { nothingToDo, adopted, applied, rebased, conflict, targetEmptied, needsAdoptionChoice }`; `class PullResult`.

Branches, **in order**, first match wins:

1. `latest()` metadata only. Target identity mismatch → treat as unprovenanced.
2. **Remote empty.** Pointer null → nothing to apply. Pointer set → the revision we were provenanced against is *gone*: clear the pointer, `targetEmptied`. A round trip has just proved the backup no longer exists; "nothing to do" would leave the pill green over an absent backup.
3. **Unprovenanced, remote non-empty.** Never auto-apply. Local pristine → adopt. Local has data → ask.
4. `latest().id == pointer` → nothing to apply.
5. **Equivalent content under a different id** → rebase, judged by the **server checksum**.
6. **`latest().parentRevisionId == pointer` and local clean** → linear descendant. Fetch, validate, apply, advance.
7. **Anything else** → conflict. Do not apply, do not show a modal.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/backup_service_pull_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_revision.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const identity = 'folder-A';

/// A document whose difference is a REAL ConfigBundle field, so a test can
/// tell whether it was actually applied.
Map<String, dynamic> doc(String marker) => {
      'schemaVersion': 1,
      'positions': [
        {'id': marker, 'name': marker}
      ],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
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
        targetIdentity: identity,
        deviceLabel: () async => 'Mac mini',
        readBundleJson: () async => local,
        localIsPristine: () async => pristine,
      );

  Future<BackupRevision> remotePut(Map<String, dynamic> d,
          {String? parent, String label = 'iPad'}) =>
      target.put(canonicalJsonEncode(d),
          contentHash: canonicalHash(d),
          parentRevisionId: parent,
          deviceLabel: label);

  test('empty remote with no pointer is nothing to do', () async {
    final r = await service(doc('local'), pristine: true).pull();
    expect(r.outcome, PullOutcome.nothingToDo);
  });

  test('empty remote with a pointer set means the backup is GONE', () async {
    await BackupPointer.save(
        revisionId: 'rev-1', recordedHash: 'h', targetIdentity: identity);

    final r = await service(doc('local')).pull();

    expect(r.outcome, PullOutcome.targetEmptied,
        reason: 'a round trip proved the backup is absent; green would lie');
    expect((await BackupPointer.load()).isProvenanced, isFalse);
  });

  test('unprovenanced with pristine local ADOPTS and actually applies',
      () async {
    await remotePut(doc('remote'));

    final r = await service(doc('local'), pristine: true).pull();

    expect(r.outcome, PullOutcome.adopted);
    expect((await PositionStore.loadAll()).single.id, 'remote',
        reason: 'outcome alone would pass without applying anything');
    expect((await BackupPointer.load()).revisionId, isNotNull);
  });

  test('unprovenanced with local data ASKS rather than auto-applying',
      () async {
    await remotePut(doc('remote'));
    await PositionStore.saveAll([]);

    final r = await service(doc('local'), pristine: false).pull();

    expect(r.outcome, PullOutcome.needsAdoptionChoice,
        reason: 'a just-imported config must not be silently replaced');
    expect(await PositionStore.loadAll(), isEmpty);
  });

  test('pointer equal to head is nothing to do', () async {
    final rev = await remotePut(doc('same'));
    await BackupPointer.save(
        revisionId: rev.id,
        recordedHash: canonicalHash(doc('same')),
        targetIdentity: identity);

    expect((await service(doc('same')).pull()).outcome,
        PullOutcome.nothingToDo);
  });

  test('equal content under a different id rebases without applying',
      () async {
    await remotePut(doc('same'));
    await BackupPointer.save(
        revisionId: 'some-old-id',
        recordedHash: canonicalHash(doc('same')),
        targetIdentity: identity);

    final r = await service(doc('same')).pull();

    expect(r.outcome, PullOutcome.rebased);
    expect((await BackupPointer.load()).revisionId, target.revisions.single.id);
  });

  test('rebase trusts the BODY, not the stale contentHash', () async {
    final rev = await remotePut(doc('same'));
    target.corruptMetadataOf(rev.id, contentHash: 'a-stale-lie');
    await BackupPointer.save(
        revisionId: 'some-old-id',
        recordedHash: canonicalHash(doc('same')),
        targetIdentity: identity);

    final r = await service(doc('same')).pull();

    expect(r.outcome, PullOutcome.rebased,
        reason: 'comparing contentHash would have called this a conflict');
  });

  test('a linear descendant with clean local is APPLIED to the stores',
      () async {
    final base = await remotePut(doc('base'));
    await BackupPointer.save(
        revisionId: base.id,
        recordedHash: canonicalHash(doc('base')),
        targetIdentity: identity);
    final next = await remotePut(doc('next'), parent: base.id);

    final r = await service(doc('base')).pull();

    expect(r.outcome, PullOutcome.applied);
    expect((await PositionStore.loadAll()).single.id, 'next',
        reason: 'the stores must actually change');
    expect((await BackupPointer.load()).revisionId, next.id);
  });

  test('A SIBLING FORK IS NOT APPLIED even though local is clean', () async {
    // "Local is clean" compares local against its OWN pointer and proves
    // nothing about whether remote descends from it. A machine that had just
    // pushed would otherwise silently adopt the other machine's fork.
    final base = await remotePut(doc('base'), label: 'shared');
    final mine =
        await remotePut(doc('mine'), parent: base.id, label: 'Mac mini');
    await remotePut(doc('theirs'), parent: base.id, label: 'iPad');

    await BackupPointer.save(
        revisionId: mine.id,
        recordedHash: canonicalHash(doc('mine')),
        targetIdentity: identity);
    await PositionStore.saveAll([]);

    final r = await service(doc('mine')).pull();

    expect(r.outcome, PullOutcome.conflict,
        reason: 'clean-against-own-pointer is not ancestry');
    expect((await BackupPointer.load()).revisionId, mine.id);
    expect(await PositionStore.loadAll(), isEmpty,
        reason: 'nothing may be applied on a fork');
  });

  test('a moved remote with dirty local is a conflict, never a modal',
      () async {
    final base = await remotePut(doc('base'));
    await BackupPointer.save(
        revisionId: base.id,
        recordedHash: canonicalHash(doc('base')),
        targetIdentity: identity);
    await remotePut(doc('next'), parent: base.id);

    final r = await service(doc('dirty-local')).pull();
    expect(r.outcome, PullOutcome.conflict);
  });

  test('a pointer from another target is ignored, not compared', () async {
    await remotePut(doc('remote'));
    await BackupPointer.save(
        revisionId: 'rev-from-elsewhere',
        recordedHash: 'h',
        targetIdentity: 'a-different-folder');

    final r = await service(doc('local'), pristine: true).pull();
    expect(r.outcome, PullOutcome.adopted,
        reason: 'treated as unprovenanced, not compared across targets');
  });

  test('invalid remote JSON surfaces as AppFault, not FormatException',
      () async {
    await target.put('not json at all',
        contentHash: 'x', parentRevisionId: null, deviceLabel: 'iPad');

    await expectLater(
        service(doc('local'), pristine: true).pull(), throwsA(isA<AppFault>()));
  });

  test('a remote bundle failing validation is an AppFault and applies nothing',
      () async {
    await PositionStore.saveAll([]);
    await target.put('{"nope":true}',
        contentHash: 'x', parentRevisionId: null, deviceLabel: 'iPad');

    await expectLater(
        service(doc('local'), pristine: true).pull(), throwsA(isA<AppFault>()));
    expect(await PositionStore.loadAll(), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_service_pull_test.dart`
Expected: FAIL — `pull` is not defined.

- [ ] **Step 3: Implement**

Add to the top of `lib/services/backup/backup_service.dart`:

```dart
import 'dart:convert';

import '../config_bundle.dart';
```

Add above the class:

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

and inside `BackupService`:

```dart
  Future<PullResult> pull() => _single(_pull);

  Future<PullResult> _pull() async {
    // 1. Metadata only. A pointer from another target is meaningless.
    final head = await target.latest();
    final pointer = await _pointer();

    // 2. Remote empty.
    if (head == null) {
      if (!pointer.isProvenanced) {
        return const PullResult(PullOutcome.nothingToDo);
      }
      await BackupPointer.clear();
      return const PullResult(PullOutcome.targetEmptied);
    }

    final localBundle = await readBundleJson();
    final localJson = canonicalJsonEncode(localBundle);
    final localHash = canonicalHash(localBundle);
    final localChecksum = bodyChecksumOf(localJson);

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

    // 5. Equivalent content under another id. Judged by the SERVER checksum:
    //    the contentHash at the target is client-written and goes stale if
    //    someone edits the file by hand.
    if (head.bodyChecksum == localChecksum) {
      await BackupPointer.save(
        revisionId: head.id,
        recordedHash: localHash,
        targetIdentity: targetIdentity,
      );
      return PullResult(PullOutcome.rebased, revision: head);
    }

    // 6. Linear descendant, and local unchanged. The ancestry test is
    //    load-bearing: "clean" compares local against its OWN pointer and
    //    says nothing about whether remote descends from it.
    if (head.parentRevisionId == pointer.revisionId &&
        pointer.isCleanAgainst(localHash)) {
      await _applyRevision(head);
      return PullResult(PullOutcome.applied, revision: head);
    }

    // 7. Diverged, or local is dirty. Surface it; never a modal.
    return PullResult(PullOutcome.conflict, revision: head);
  }

  Future<void> _applyRevision(BackupRevision revision) async {
    final raw = await target.fetch(revision);

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw AppFault.backup(
        BackupFailureKind.malformedRemote,
        'revision ${revision.id} is not valid JSON',
        operation: 'pull',
        targetIdentity: targetIdentity,
        cause: e,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AppFault.backup(
        BackupFailureKind.malformedRemote,
        'revision ${revision.id} is not a JSON object',
        operation: 'pull',
        targetIdentity: targetIdentity,
      );
    }

    // Throws AppFault on anything malformed, before a single store is touched.
    final bundle = ConfigBundle.fromJsonValidated(decoded);
    await bundle.applyTransactionally();

    // applyTransactionally deliberately clears the pointer, because an import
    // is unprovenanced. Applying a fetched revision is the one case where we
    // know exactly what it came from, so re-establish it here.
    await BackupPointer.save(
      revisionId: revision.id,
      recordedHash: canonicalHash(decoded),
      targetIdentity: targetIdentity,
    );
    await ConfigMutationNotifier.instance
        .markSynced(await ConfigMutationNotifier.instance.generation());
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/backup_service_pull_test.dart`
Expected: PASS, 13 tests.

Run: `flutter test --concurrency=1 && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_service.dart test/backup/backup_service_pull_test.dart
git commit -m "feat(backup): pull with ordered branches and the ancestry test"
```

---

### Task 11: Retry policy and single-flight

**Test-policy class: trust contract** for the backoff schedule and the ordering guarantee.

**Files:**
- Modify: `lib/services/backup/backup_service.dart`
- Test: `test/backup/backup_service_scheduling_test.dart`

**Interfaces:**
- Consumes: Task 10.
- Produces: `static Duration? BackupService.nextRetryDelay(AppFault fault, int attempt)`.

Backoff is 30 s → 1 m → 2 m → 5 m → 10 m, then held. **The loop never gives up** — a schedule that exhausts itself is a silent failure with extra steps.

`num.clamp` returns `num`, so a list index needs `.toInt()`.

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
    test('a slow first operation blocks a fast second until it finishes',
        () async {
      final target = MockBackupTarget();
      final service = BackupService(
        target: target,
        targetIdentity: 'folder-A',
        deviceLabel: () async => 'Mac mini',
        readBundleJson: () async => {
          'schemaVersion': 1,
          'positions': <dynamic>[],
          'people': <dynamic>[],
          'services': <dynamic>[],
          'heightRanges': <dynamic>[],
        },
        localIsPristine: () async => true,
      );

      final order = <String>[];

      // Only the FIRST call is slowed. Without serialization the second
      // finishes first, because nothing is waiting on the first.
      target.delayNextBy(const Duration(milliseconds: 120));
      final slow = service.pull().then((_) => order.add('slow'));
      final fast = service.pull().then((_) => order.add('fast'));

      await Future.wait([slow, fast]);

      expect(order, ['slow', 'fast'],
          reason: 'an older operation completing after a newer one would '
              'overwrite status or provenance');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_service_scheduling_test.dart`
Expected: FAIL — `nextRetryDelay` is not defined.

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
    final i = attempt.clamp(0, _backoff.length - 1).toInt();
    return _backoff[i];
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/backup_service_scheduling_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_service.dart \
        test/backup/backup_service_scheduling_test.dart
git commit -m "feat(backup): retry backoff that never gives up, and single-flight proof"
```

---

### Task 12: The scheduler

**Test-policy class: trust contract.** Without this nothing ever calls `push()` or `pull()`, and the engine is a library rather than a backup.

**Files:**
- Create: `lib/services/backup/backup_scheduler.dart`
- Test: `test/backup/backup_scheduler_test.dart`

**Interfaces:**
- Consumes: `BackupService` (Tasks 9–11), `ConfigMutationNotifier` (Task 5), `AppFault` (Task 3).
- Produces: `BackupScheduler({required service, Duration debounce, Duration sweepInterval, Future<void> Function(Duration)? sleep})` with `start()`, `stop()`, `onAppStart()`, `onForeground()`, `flushPending()`, `events`, `pullCount`, `pushCount`.

Triggers, from the spec:

| Trigger | Action |
|---|---|
| App start | Pull |
| Unbackground | Pull, then resume any durable pending push |
| Periodic sweep | Pull, then hash-guarded push |
| Data mutated | Push, debounced |
| Background or quit | Best-effort flush |
| Retryable fault | Backoff per `nextRetryDelay`, never giving up |

`sleep` is injectable so tests do not wait real minutes; it defaults to `Future.delayed`. That avoids adding a fake-time dependency for one class.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/backup_scheduler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> doc(String marker) => {
      'schemaVersion': 1,
      'positions': [
        {'id': marker, 'name': marker}
      ],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
    };

void main() {
  late MockBackupTarget target;
  late BackupService service;
  late List<Duration> slept;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    target = MockBackupTarget();
    slept = [];
    service = BackupService(
      target: target,
      targetIdentity: 'folder-A',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => doc('local'),
      localIsPristine: () async => false,
    );
  });

  BackupScheduler scheduler({Duration? debounce}) => BackupScheduler(
        service: service,
        debounce: debounce ?? const Duration(milliseconds: 20),
        sweepInterval: const Duration(milliseconds: 40),
        sleep: (d) async {
          slept.add(d);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        },
      );

  test('app start pulls', () async {
    final s = scheduler();
    await s.onAppStart();
    expect(s.pullCount, 1);
    await s.stop();
  });

  test('a mutation triggers exactly one push after the debounce', () async {
    final s = scheduler();
    s.start();

    await ConfigMutationNotifier.instance.notify();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(s.pushCount, 1);
    expect(target.revisions.length, 1);
    await s.stop();
  });

  test('a burst of mutations coalesces into ONE push', () async {
    final s = scheduler(debounce: const Duration(milliseconds: 40));
    s.start();

    for (var i = 0; i < 8; i++) {
      await ConfigMutationNotifier.instance.notify();
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(s.pushCount, 1,
        reason: 'eight drag-drops must not make eight revisions');
    await s.stop();
  });

  test('flushPending pushes immediately without waiting for the debounce',
      () async {
    final s = scheduler(debounce: const Duration(seconds: 30));
    s.start();

    await ConfigMutationNotifier.instance.notify();
    await s.flushPending();

    expect(s.pushCount, 1,
        reason: 'a pending debounce lost to termination is the edit the user '
            'most recently made');
    await s.stop();
  });

  test('the sweep pulls repeatedly on its interval', () async {
    final s = scheduler();
    s.start();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(s.pullCount, greaterThanOrEqualTo(2));
    await s.stop();
  });

  test('stop cancels everything; no work happens afterwards', () async {
    final s = scheduler();
    s.start();
    await s.stop();

    final pullsAtStop = s.pullCount;
    await ConfigMutationNotifier.instance.notify();
    await Future<void>.delayed(const Duration(milliseconds: 140));

    expect(s.pullCount, pullsAtStop);
    expect(s.pushCount, 0);
  });

  group('retry', () {
    test('a retryable fault is retried after the backoff delay', () async {
      final s = scheduler();
      target.failNextWith(
          AppFault.backup(BackupFailureKind.offline, 'no network'));

      await s.onAppStart();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(slept, contains(const Duration(seconds: 30)),
          reason: 'the first backoff step');
      expect(s.pullCount, greaterThanOrEqualTo(2),
          reason: 'it actually tried again');
      await s.stop();
    });

    test('a fault needing a human is NOT retried on a timer', () async {
      final s = scheduler();
      target.failNextWith(
          AppFault.backup(BackupFailureKind.authExpired, 'sign in again'));

      await s.onAppStart();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(slept, isEmpty, reason: 'waiting cannot fix an expired credential');
      await s.stop();
    });

    test('the fault is emitted so a UI can show it', () async {
      final s = scheduler();
      final seen = <Object>[];
      final sub = s.events.listen(seen.add);
      target.failNextWith(
          AppFault.backup(BackupFailureKind.authExpired, 'sign in again'));

      await s.onAppStart();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(seen.whereType<AppFault>().map((f) => f.kind),
          contains(BackupFailureKind.authExpired.name),
          reason: 'a fault nothing can see is a silent failure');
      await s.stop();
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/backup_scheduler_test.dart`
Expected: FAIL — `backup_scheduler.dart` not found.

- [ ] **Step 3: Implement**

Create `lib/services/backup/backup_scheduler.dart`:

```dart
import 'dart:async';

import 'app_fault.dart';
import 'backup_service.dart';
import 'config_mutation_notifier.dart';

enum _Op { pull, push }

/// Drives [BackupService]. Nothing else calls push or pull.
///
/// Timings are injectable so tests do not wait real minutes; [sleep] defaults
/// to `Future.delayed`.
class BackupScheduler {
  final BackupService service;
  final Duration debounce;
  final Duration sweepInterval;
  final Future<void> Function(Duration) sleep;

  final _events = StreamController<Object>.broadcast();

  StreamSubscription<int>? _mutations;
  Timer? _debounceTimer;
  Timer? _sweepTimer;
  bool _running = false;
  int _retryAttempt = 0;

  int pullCount = 0;
  int pushCount = 0;

  BackupScheduler({
    required this.service,
    this.debounce = const Duration(seconds: 30),
    this.sweepInterval = const Duration(minutes: 10),
    Future<void> Function(Duration)? sleep,
  }) : sleep = sleep ?? Future<void>.delayed;

  /// Results and faults, for a UI to display. A fault nothing can see is a
  /// silent failure.
  Stream<Object> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    _mutations = ConfigMutationNotifier.instance.onMutated.listen((_) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () {
        unawaited(_run(_Op.push));
      });
    });
    _sweepTimer = Timer.periodic(sweepInterval, (_) async {
      await _run(_Op.pull);
      await _run(_Op.push);
    });
  }

  Future<void> stop() async {
    _running = false;
    await _mutations?.cancel();
    _mutations = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
  }

  /// Pull on launch. The round trip also proves the credential still works.
  Future<void> onAppStart() => _run(_Op.pull);

  /// Pull on unbackground, then resume anything left pending.
  Future<void> onForeground() async {
    await _run(_Op.pull);
    if (await ConfigMutationNotifier.instance.isDirty()) {
      await _run(_Op.push);
    }
  }

  /// Push now rather than waiting out the debounce. Best-effort: correctness
  /// rests on the persisted generation, not on this completing.
  Future<void> flushPending() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (await ConfigMutationNotifier.instance.isDirty()) {
      await _run(_Op.push);
    }
  }

  Future<void> _run(_Op op) async {
    try {
      if (op == _Op.pull) {
        pullCount++;
        _events.add(await service.pull());
      } else {
        pushCount++;
        _events.add(await service.push());
      }
      _retryAttempt = 0;
    } on AppFault catch (f) {
      _events.add(f);
      await _scheduleRetry(f, op);
    } catch (e) {
      final f = AppFault.backup(BackupFailureKind.unknown, '$e', cause: e);
      _events.add(f);
      await _scheduleRetry(f, op);
    }
  }

  Future<void> _scheduleRetry(AppFault fault, _Op op) async {
    final delay = BackupService.nextRetryDelay(fault, _retryAttempt);
    if (delay == null) {
      // Waiting cannot fix this. It retries on foreground or user action.
      _retryAttempt = 0;
      return;
    }
    _retryAttempt++;
    await sleep(delay);
    await _run(op);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/backup/backup_scheduler_test.dart`
Expected: PASS, 9 tests.

Run: `flutter test --concurrency=1 && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_scheduler.dart test/backup/backup_scheduler_test.dart
git commit -m "feat(backup): scheduler for debounce, sweep, lifecycle, and retry"
```

---

### Task 13: Startup — journal rollback and singleton launch

**Test-policy class:** `SingleInstance` is a **trust contract**; the `main.dart` wiring is **wiring** and gets one test asserting the call sites exist and are ordered.

**Files:**
- Create: `lib/services/backup/single_instance.dart`
- Modify: `lib/main.dart`
- Test: `test/backup/startup_test.dart`

**Interfaces:**
- Consumes: `RestoreJournal` (Task 8).
- Produces: `SingleInstance.claim()` → `bool`, `release()`, `releaseForTest()`.

Two things must happen before `runApp`:

1. **Singleton guard.** Two copies sharing `SharedPreferences` through its cached API would read stale values and race the journal, which is the premise the journal's atomicity rests on.
2. **Journal rollback.** A journal present means a previous materialization was interrupted; the app must not read a hybrid configuration.

- [ ] **Step 1: Write the failing tests**

Create `test/backup/startup_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/restore_journal.dart';
import 'package:navigation_app/services/backup/single_instance.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SingleInstance.releaseForTest();
  });

  group('SingleInstance', () {
    test('the first claim succeeds', () {
      expect(SingleInstance.claim(), isTrue);
    });

    test('a second claim in the same process is refused', () {
      expect(SingleInstance.claim(), isTrue);
      expect(SingleInstance.claim(), isFalse,
          reason: 'two copies racing the journal is what this prevents');
    });

    test('after release, a claim succeeds again', () {
      SingleInstance.claim();
      SingleInstance.release();
      expect(SingleInstance.claim(), isTrue);
    });
  });

  group('journal rollback', () {
    test('an interrupted apply is rolled back', () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      await RestoreJournal.capture();
      await PositionStore.saveAll([]);

      await RestoreJournal.rollbackIfPresent();

      expect((await PositionStore.loadAll()).length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RestoreJournal.key), isNull);
    });
  });

  group('main wiring', () {
    late String source;

    setUpAll(() => source = File('lib/main.dart').readAsStringSync());

    test('main rolls back the journal before runApp', () {
      expect(source.contains('RestoreJournal.rollbackIfPresent'), isTrue,
          reason: 'without this the app can start on a hybrid configuration');
      expect(source.indexOf('RestoreJournal.rollbackIfPresent'),
          lessThan(source.indexOf('runApp')),
          reason: 'it must happen before anything reads configuration');
    });

    test('main claims the single instance before runApp', () {
      expect(source.contains('SingleInstance.claim'), isTrue);
      expect(source.indexOf('SingleInstance.claim'),
          lessThan(source.indexOf('runApp')));
    });
  });
}
```

> The `main wiring` group reads `lib/main.dart` as text on purpose. Calling `main()` in a test would run the whole app; asserting on the source proves the call sites exist and are ordered, which is what a wiring test should check and nothing more.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/backup/startup_test.dart`
Expected: FAIL — `single_instance.dart` not found.

- [ ] **Step 3: Implement the guard**

Create `lib/services/backup/single_instance.dart`:

```dart
import 'dart:io';

/// Refuses a second copy of the app.
///
/// Two instances share `SharedPreferences` through its cached API: one would
/// read stale values and both could race the restore journal, which is the
/// premise the journal's atomicity rests on. Refusing is far cheaper than
/// defining reload semantics for that.
class SingleInstance {
  static RandomAccessFile? _held;
  static bool _claimedInProcess = false;

  /// Attempts to become the only running instance. Returns false if another
  /// instance already holds the lock.
  static bool claim() {
    if (_claimedInProcess) return false;
    try {
      final file = File('${Directory.systemTemp.path}/navigation_app.lock');
      final raf = file.openSync(mode: FileMode.write);
      raf.lockSync(FileLock.exclusive);
      _held = raf;
      _claimedInProcess = true;
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static void release() {
    try {
      _held?.unlockSync();
      _held?.closeSync();
    } on FileSystemException {
      // Already gone; nothing to do.
    }
    _held = null;
    _claimedInProcess = false;
  }

  /// Test seam: drops in-process state without touching the filesystem lock.
  static void releaseForTest() {
    _held = null;
    _claimedInProcess = false;
  }
}
```

- [ ] **Step 4: Wire `main`**

Replace `main()` in `lib/main.dart`. The existing widget class is `MyApp` — keep it:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'services/backup/restore_journal.dart';
import 'services/backup/single_instance.dart';
import 'widgets/multi_device_control_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Two instances share SharedPreferences through its cached API and can race
  // the restore journal. Refuse rather than tolerate.
  if (!SingleInstance.claim()) {
    stderr.writeln('Production Control is already running.');
    exit(0);
  }

  // A journal here means a previous restore was interrupted. Roll it back
  // before anything reads configuration, or the app runs on a hybrid of old
  // and new and the next backup uploads that hybrid as a valid revision.
  await RestoreJournal.rollbackIfPresent();

  runApp(const MyApp());
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/backup/startup_test.dart`
Expected: PASS, 6 tests.

Run: `flutter test --concurrency=1 && flutter analyze`
Expected: full suite green, analyze clean.

- [ ] **Step 6: Confirm the app still starts**

Run `flutter run -d macos` (or `-d linux`), confirm it reaches the normal first screen, then quit.

- [ ] **Step 7: Commit**

```bash
git add lib/services/backup/single_instance.dart lib/main.dart \
        test/backup/startup_test.dart
git commit -m "feat(backup): roll back interrupted restores and refuse a second instance"
```

---

## Self-Review

**Spec coverage for phases 0–2:**

| Spec requirement | Task |
|---|---|
| Canonical serialization | 2 |
| Server-checksum body trust | 2, 9, 10 |
| `AppFault` general from day one; full taxonomy | 3 |
| Fingerprint `(domain, kind, operation, target)` | 3 |
| `BackupRevision` with ancestry and device label | 4 |
| Interface, no `siblings()` | 4 |
| Mock with concurrent writer, delay, lying metadata | 4 |
| Retention conjunction, proven in all three directions | 4 |
| Mutation source; eight-store refactor | 5 |
| Restore is not an edit | 5, 8 |
| Durable pending intent | 5, 12 |
| `schemaVersion` required; `{}` malformed; one parser | 6 |
| `unsupportedSchema` fail-closed | 6 |
| Malformed input → `AppFault`, never a raw `TypeError`/`FormatException` | 6, 10 |
| Import: full replace; device fields reset | 8 |
| Rollback journal; wholly old or wholly new; injectable at every write | 8, 13 |
| Manual import → pointer null | 8 |
| Pointer transitions and target identity | 7, 9, 10 |
| Push: no-op rebase, conflict, post-upload fork check | 9 |
| Pull: seven ordered branches; ancestry test | 10 |
| Single-flight, proven slow-then-fast | 9, 11 |
| Retry backoff, never gives up | 11, 12 |
| Triggers: start, foreground, sweep, debounce, flush | 12 |
| Singleton launch | 13 |
| Startup journal rollback | 13 |

**Deferred to later plans, deliberately:** the status pill and popover, the persisted fault log, conflict resolution UI, revision-history picker, device-label naming UI, `DriveBackupTarget`, auth, and phase 5. Each is named in the spec; none is silently dropped.

**Known gaps this plan leaves open:**

- **The three-fact status model** (durable head / dirty / active condition) is not built. `BackupScheduler.events` emits every result and fault so phase 3 can derive it; the derivation and its "a pull success does not clear a failed push" test belong with the pill.
- **`prune` is never called by the engine.** Implemented and tested on the mock; wiring it to push belongs in phase 4, where a real target makes retention meaningful.
- **Device-label naming rules** (reject `localhost`, `iPad`, empty, duplicates) need a settings UI. `deviceLabel` is a callback so phase 3 supplies it without touching the engine.
- **`BackupScheduler` is not constructed anywhere in production.** There is no UI yet to own its lifetime or attach a `WidgetsBindingObserver` for `onForeground`/`flushPending`; that wiring lands with the pill in phase 3.
- **`localIsPristine` has no production implementation.** Phase 3 must define it as "every bundle-owned store is empty" — not just the four list stores, since a machine can have customised device addresses, operators, preset names or visibilities while its lists are empty.

**Type consistency:** `canonicalJsonEncode`/`canonicalHash`/`bodyChecksumOf` (T2) used in 4, 9, 10. `AppFault.backup(kind, message, operation:, targetIdentity:, cause:)` (T3) used in 4, 6, 10, 12. `BackupRevision.{bodyChecksum, parentRevisionId, copyWith}` (T4) used in 9, 10. `ConfigMutationNotifier.instance.{notify, markSynced, isDirty, suspendWhile, generationKey, syncedKey}` (T5) used in 8, 9, 10, 12. `ConfigBundle.{fromJsonValidated, currentSchemaVersion}` (T6) used in 8, 10. `BackupPointer.{load, save, clear, isCleanAgainst, revisionKey, hashKey}` (T7) used in 8, 9, 10. `applyTransactionally` (T8) used in 10. `BackupService.{push, pull, nextRetryDelay}` (T9–11) used in 12. `RestoreJournal.{key, capture, rollbackIfPresent, clear}` (T8) used in 13.

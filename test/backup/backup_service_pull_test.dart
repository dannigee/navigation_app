import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_revision.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const identity = 'folder-A';

class _FailingSharedPreferencesStore extends InMemorySharedPreferencesStore {
  _FailingSharedPreferencesStore(Map<String, Object> values)
      : super.withData(values);

  var _didRefuseSetOnce = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.positions' && !_didRefuseSetOnce) {
      _didRefuseSetOnce = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

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

    expect(
        (await service(doc('same')).pull()).outcome, PullOutcome.nothingToDo);
  });

  test('equal content under a different id rebases without applying', () async {
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

  test('a failed store write during pull rolls back state and provenance',
      () async {
    final base = await remotePut(doc('base'));
    final next = await remotePut(doc('next'), parent: base.id);
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _FailingSharedPreferencesStore({
      'flutter.positions': jsonEncode(doc('base')['positions']),
      'flutter.${BackupPointer.revisionKey}': base.id,
      'flutter.${BackupPointer.hashKey}': canonicalHash(doc('base')),
      'flutter.${BackupPointer.targetKey}': identity,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    Object? thrown;
    try {
      await service(doc('base')).pull();
    } catch (error) {
      thrown = error;
    }

    expect(
      thrown,
      isA<AppFault>()
          .having((fault) => fault.kind, 'kind',
              BackupFailureKind.storageWriteFailed.name)
          .having((fault) => fault.cause, 'cause', isA<StateError>()),
    );
    expect(thrown, isNot(isA<StateError>()),
        reason: 'pull must not leak a raw persistence StateError');
    expect((await PositionStore.loadAll()).single.id, 'base',
        reason: 'the local stores must be wholly rolled back');
    final pointer = await BackupPointer.load();
    expect(pointer.revisionId, base.id,
        reason: 'a failed apply must not advance provenance to ${next.id}');
    expect(pointer.recordedHash, canonicalHash(doc('base')));
    expect(pointer.targetIdentity, identity);
  });
}

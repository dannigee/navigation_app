import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const identity = 'folder-A';

class _RefusePointerWriteStore extends InMemorySharedPreferencesStore {
  _RefusePointerWriteStore(Map<String, Object> values, this.refuseKey)
      : super.withData(values);

  final String refuseKey;
  var refused = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == refuseKey && !refused) {
      refused = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

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

  test('a deleted remote under an existing pointer is not recreated', () async {
    await ConfigMutationNotifier.instance.notify();
    await BackupPointer.save(
        revisionId: 'deleted-rev',
        recordedHash: canonicalHash(doc()),
        targetIdentity: identity);

    await expectLater(
      service(doc('edited')).push(),
      throwsA(
        isA<AppFault>()
            .having((fault) => fault.kind, 'kind',
                BackupFailureKind.targetMissing.name)
            .having((fault) => fault.operation, 'operation', 'push'),
      ),
    );

    expect(target.revisions, isEmpty,
        reason: 'push must not recreate deletion');
    expect((await BackupPointer.load()).isProvenanced, isFalse,
        reason: 'the deleted durable head is no longer valid provenance');
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'local work remains pending after the remote loss');
  });

  test('a refused pointer write fails push and leaves the edit pending',
      () async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _RefusePointerWriteStore(
      {'flutter.${ConfigMutationNotifier.generationKey}': 1},
      'flutter.${BackupPointer.revisionKey}',
    );
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await expectLater(
      service(doc()).push(),
      throwsA(
        isA<AppFault>()
            .having((fault) => fault.kind, 'kind',
                BackupFailureKind.storageWriteFailed.name)
            .having((fault) => fault.cause, 'cause', isA<StateError>()),
      ),
    );

    expect(target.revisions, hasLength(1),
        reason: 'the remote upload happened before local persistence failed');
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'a failed provenance write must not mark the upload synced');
  });

  test('a later pointer-field refusal cannot make retry certify a stale hash',
      () async {
    final base = await target.put(
      canonicalJsonEncode(doc()),
      contentHash: canonicalHash(doc()),
      parentRevisionId: null,
      deviceLabel: 'Mac mini',
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _RefusePointerWriteStore(
      {
        'flutter.${ConfigMutationNotifier.generationKey}': 1,
        'flutter.${BackupPointer.revisionKey}': base.id,
        'flutter.${BackupPointer.hashKey}': canonicalHash(doc()),
        'flutter.${BackupPointer.targetKey}': identity,
      },
      'flutter.${BackupPointer.hashKey}',
    );
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await expectLater(
      service(doc('edited')).push(),
      throwsA(isA<AppFault>().having((fault) => fault.kind, 'kind',
          BackupFailureKind.storageWriteFailed.name)),
    );
    expect((await BackupPointer.load()).revisionId, base.id,
        reason: 'revision is the commit field and must move last');
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue);

    final retry = await service(doc('edited')).push();

    expect(retry.outcome, PushOutcome.noOp);
    final repaired = await BackupPointer.load();
    expect(repaired.revisionId, target.revisions.last.id);
    expect(repaired.recordedHash, canonicalHash(doc('edited')));
    expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);
  });
}

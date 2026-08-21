import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _RefuseHashWriteStore extends InMemorySharedPreferencesStore {
  _RefuseHashWriteStore() : super.withData({});

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${BackupPointer.hashKey}') return false;
    return super.setValue(valueType, key, value);
  }
}

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
    final p = await BackupPointer.load();
    expect(p.isProvenanced, isFalse);
    expect(p.matchesTarget('folder-A'), isFalse);
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

  test('save reports when SharedPreferences refuses a pointer field', () async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _RefuseHashWriteStore();
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await expectLater(
      BackupPointer.save(
          revisionId: 'rev-1', recordedHash: 'h1', targetIdentity: 'folder-A'),
      throwsA(isA<StateError>()),
    );
  });
}

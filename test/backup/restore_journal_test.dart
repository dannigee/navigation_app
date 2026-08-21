import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
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
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingSharedPreferencesStore extends InMemorySharedPreferencesStore {
  _FailingSharedPreferencesStore(
    Map<String, Object> values, {
    this.refuseSetOnce = 'flutter.positions',
    this.refuseRemoveOnce,
    this.refuseSetAfterFirstSuccess,
  }) : super.withData(values);

  final String? refuseSetOnce;
  final String? refuseRemoveOnce;
  final String? refuseSetAfterFirstSuccess;
  final _setAttempts = <String, int>{};
  var _didRefuseSetOnce = false;
  var _didRefuseRemoveOnce = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final attempt = (_setAttempts[key] ?? 0) + 1;
    _setAttempts[key] = attempt;
    if (key == refuseSetOnce && !_didRefuseSetOnce) {
      _didRefuseSetOnce = true;
      return false;
    }
    if (key == refuseSetAfterFirstSuccess && attempt > 1) return false;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == refuseRemoveOnce && !_didRefuseRemoveOnce) {
      _didRefuseRemoveOnce = true;
      return false;
    }
    return super.remove(key);
  }
}

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

      await ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally();

      expect(await PresetNameStore.loadAll('10.0.1.10'), isEmpty,
          reason: 'absent means explicitly none');
    });

    test('deletes visibility keys absent from the incoming bundle', () async {
      await VisibilityStore.save('roland_10.0.1.20', 5, ItemVisibility.hide);
      await ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally();
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

      await ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally();

      expect(await DeviceConfigStore.loadRolandIp(),
          DeviceConfigStore.defaultRolandIp,
          reason: 'absent means default, not "leave the machine alone"');
      expect((await DeviceConfigStore.loadCameras()).first.ip,
          DeviceConfigStore.defaultCameras.first.ip);
    });

    test('absent operators RESET to defaults', () async {
      await OperatorStore.saveActiveId('operator-who-will-not-exist');

      await ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally();

      expect(await OperatorStore.loadAll(), isNotEmpty);
      expect(await OperatorStore.loadActiveId(), OperatorProfile.defaultId,
          reason: 'the active operator is part of the replacement');
    });
  });

  group('transactionality', () {
    test('a refused store write rolls back before reporting a backup fault',
        () async {
      final oldPosition = Position(id: 'p1', name: 'Ambo');
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _FailingSharedPreferencesStore({
        'flutter.positions': jsonEncode([oldPosition.toJson()]),
      });

      Object? thrown;
      try {
        await ConfigBundle.fromJsonValidated(bundleJson())
            .applyTransactionally();
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
      expect(thrown, isNot(isA<StateError>()));
      expect((await PositionStore.loadAll()).single.id, oldPosition.id,
          reason: 'the old store must be restored before the fault escapes');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RestoreJournal.key), isNull,
          reason: 'a completed rollback must clear its journal first');
    });

    test('a refused pointer removal reloads and rolls the whole apply back',
        () async {
      final oldPosition = Position(id: 'p1', name: 'Ambo');
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _FailingSharedPreferencesStore(
        {
          'flutter.positions': jsonEncode([oldPosition.toJson()]),
          'flutter.${BackupPointer.revisionKey}': 'rev-1',
          'flutter.${BackupPointer.hashKey}': 'hash-1',
          'flutter.${BackupPointer.targetKey}': 'folder-A',
        },
        refuseSetOnce: null,
        refuseRemoveOnce: 'flutter.${BackupPointer.revisionKey}',
      );

      await expectLater(
        ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally(),
        throwsA(
          isA<AppFault>()
              .having((fault) => fault.kind, 'kind',
                  BackupFailureKind.storageWriteFailed.name)
              .having((fault) => fault.cause, 'cause', isA<StateError>()),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pointer = await BackupPointer.load();
      expect(pointer.revisionId, 'rev-1');
      expect(pointer.recordedHash, 'hash-1');
      expect(pointer.targetIdentity, 'folder-A');
      expect((await PositionStore.loadAll()).single.id, oldPosition.id);
      expect(prefs.getString(RestoreJournal.key), isNull);
    });

    test('a refused rollback is wrapped and leaves its journal for recovery',
        () async {
      final oldPosition = Position(id: 'p1', name: 'Ambo');
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _FailingSharedPreferencesStore(
        {
          'flutter.positions': jsonEncode([oldPosition.toJson()]),
        },
        refuseSetOnce: null,
        refuseSetAfterFirstSuccess: 'flutter.positions',
      );

      await expectLater(
        ConfigBundle.fromJsonValidated(bundleJson())
            .applyTransactionally(failAfterWritesForTest: 1),
        throwsA(
          isA<AppFault>()
              .having((fault) => fault.kind, 'kind',
                  BackupFailureKind.storageWriteFailed.name)
              .having((fault) => fault.cause, 'cause', isA<StateError>()),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString(RestoreJournal.key), isNotNull,
          reason: 'a failed rollback must remain recoverable on next launch');
    });

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

      // Writes: 4 lists, device, operators, active operator, then the prefix
      // replacement. Failing at 8 lands inside the preset delete — the
      // correction this task exists for, and a step the old seam could not
      // reach.
      await expectLater(
        ConfigBundle.fromJsonValidated(bundleJson())
            .applyTransactionally(failAfterWritesForTest: 8),
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
      await ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RestoreJournal.key), isNull);
    });
  });

  group('side effects', () {
    test('manual import becomes one durable pending edit', () async {
      await OperatorStore.saveActiveId('operator-who-will-not-exist');
      final seen = <int>[];
      final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);

      await ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally();

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [2],
          reason: 'generation 1 was the setup edit before listening');
      expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
          reason: 'a manual import must survive termination before its push');
      expect(await OperatorStore.loadActiveId(), OperatorProfile.defaultId,
          reason: 'the operator reset belongs inside the suspended apply');
    });

    test('applying a fetched revision does not count as a local edit',
        () async {
      final seen = <int>[];
      final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);

      await ConfigBundle.fromJsonValidated(bundleJson())
          .applyTransactionally(markAsPending: false);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, isEmpty,
          reason: 'a fetched restore must not schedule itself for upload');
      expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);
    });

    test('applying clears the provenance pointer', () async {
      await BackupPointer.save(
          revisionId: 'rev-1', recordedHash: 'h', targetIdentity: 'folder-A');

      await ConfigBundle.fromJsonValidated(bundleJson()).applyTransactionally();

      expect((await BackupPointer.load()).isProvenanced, isFalse,
          reason: 'imported state is unprovenanced pending work; the engine '
              're-establishes provenance itself when it applies a revision');
    });
  });
}

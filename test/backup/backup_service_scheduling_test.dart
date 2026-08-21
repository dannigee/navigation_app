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
      expect(
          BackupService.nextRetryDelay(offline, 1), const Duration(minutes: 1));
      expect(
          BackupService.nextRetryDelay(offline, 2), const Duration(minutes: 2));
      expect(
          BackupService.nextRetryDelay(offline, 3), const Duration(minutes: 5));
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

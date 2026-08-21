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

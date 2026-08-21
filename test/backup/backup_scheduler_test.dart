import 'dart:async';

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

    test('a successful push does not reset a pull retry backoff', () async {
      final firstRetry = Completer<void>();
      final secondRetry = Completer<void>();
      final s = BackupScheduler(
        service: service,
        sleep: (delay) {
          slept.add(delay);
          return slept.length == 1 ? firstRetry.future : secondRetry.future;
        },
      );
      target.failNextWith(
          AppFault.backup(BackupFailureKind.offline, 'pull offline'));

      unawaited(s.onAppStart());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(slept, [const Duration(seconds: 30)]);

      await ConfigMutationNotifier.instance.notify();
      await s.flushPending();
      target.failNextWith(
          AppFault.backup(BackupFailureKind.offline, 'still offline'));
      firstRetry.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(slept, [
        const Duration(seconds: 30),
        const Duration(minutes: 1),
      ]);
      await s.stop();
      secondRetry.complete();
    });

    test('app-start returns after scheduling retry rather than retaining it',
        () async {
      final retryMayFinish = Completer<void>();
      final s = BackupScheduler(service: service, sleep: (_) => retryMayFinish.future);
      var returned = false;
      target.failNextWith(
          AppFault.backup(BackupFailureKind.offline, 'no network'));

      unawaited(s.onAppStart().then((_) => returned = true));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(returned, isTrue,
          reason: 'the retry must not recursively retain its original call');
      await s.stop();
      retryMayFinish.complete();
    });

    test('stopping during retry sleep prevents the retry', () async {
      final retryMayFinish = Completer<void>();
      final s = BackupScheduler(
        service: service,
        sleep: (_) => retryMayFinish.future,
      );
      target.failNextWith(
          AppFault.backup(BackupFailureKind.offline, 'no network'));

      unawaited(s.onAppStart());
      await Future<void>.delayed(Duration.zero);
      await s.stop();
      retryMayFinish.complete();
      await Future<void>.delayed(Duration.zero);

      expect(s.pullCount, 1);
    });

    test('stop gates work still waiting behind an earlier service operation',
        () async {
      final s = scheduler();
      target.delayNextBy(const Duration(milliseconds: 60));

      final first = s.onAppStart();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final queued = s.onAppStart();
      await s.stop();
      await Future.wait([first, queued]);

      expect(s.pullCount, 1,
          reason: 'the second pull was queued before stop but never started');
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

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
  var _running = false;
  var _stopped = false;
  var _retryAttempt = 0;

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
    if (_running || _stopped) return;
    _running = true;
    _mutations = ConfigMutationNotifier.instance.onMutated.listen((_) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () {
        _debounceTimer = null;
        unawaited(_run(_Op.push));
      });
    });
    _sweepTimer = Timer.periodic(sweepInterval, (_) async {
      await _run(_Op.pull);
      if (!_stopped &&
          _debounceTimer == null &&
          await ConfigMutationNotifier.instance.isDirty()) {
        await _run(_Op.push);
      }
    });
  }

  Future<void> stop() async {
    _stopped = true;
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
    if (!_stopped && await ConfigMutationNotifier.instance.isDirty()) {
      await _run(_Op.push);
    }
  }

  /// Push now rather than waiting out the debounce. Best-effort: correctness
  /// rests on the persisted generation, not on this completing.
  Future<void> flushPending() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_stopped && await ConfigMutationNotifier.instance.isDirty()) {
      await _run(_Op.push);
    }
  }

  Future<void> _run(_Op op) async {
    if (_stopped) return;
    try {
      if (op == _Op.pull) {
        pullCount++;
        final result = await service.pull();
        if (!_stopped) _events.add(result);
      } else {
        pushCount++;
        final result = await service.push();
        if (!_stopped) _events.add(result);
      }
      _retryAttempt = 0;
    } on AppFault catch (fault) {
      if (_stopped) return;
      _events.add(fault);
      await _scheduleRetry(fault, op);
    } catch (error) {
      if (_stopped) return;
      final fault = AppFault.backup(BackupFailureKind.unknown, '$error',
          cause: error);
      _events.add(fault);
      await _scheduleRetry(fault, op);
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
    if (!_stopped) await _run(op);
  }
}

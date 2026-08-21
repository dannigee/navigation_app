import 'dart:async';

import 'app_fault.dart';
import 'backup_service.dart';
import 'config_mutation_notifier.dart';

enum _Op { pull, push }

class _Attempt {
  final AppFault? fault;
  final bool stopped;

  const _Attempt.success()
      : fault = null,
        stopped = false;
  const _Attempt.fault(this.fault) : stopped = false;
  const _Attempt.stopped()
      : fault = null,
        stopped = true;
}

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
  final _retryAttempts = <_Op, int>{_Op.pull: 0, _Op.push: 0};
  final _retryTokens = <_Op, int>{_Op.pull: 0, _Op.push: 0};

  Future<void> _operationQueue = Future<void>.value();
  StreamSubscription<int>? _mutations;
  Timer? _debounceTimer;
  Timer? _sweepTimer;
  var _running = false;
  var _stopped = false;

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
    for (final op in _Op.values) {
      _retryTokens[op] = _retryTokens[op]! + 1;
    }
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
    final attempt = await _attempt(op);
    final fault = attempt.fault;
    if (!attempt.stopped && fault != null) _startRetryLoop(op, fault);
  }

  /// Queues scheduler operations so the stop guard runs immediately before
  /// the service call, even when an earlier service operation is slow.
  Future<_Attempt> _attempt(_Op op) {
    final queued = _operationQueue.then((_) => _perform(op));
    _operationQueue = queued.then<void>((_) {}, onError: (_, __) {});
    return queued;
  }

  Future<_Attempt> _perform(_Op op) async {
    if (_stopped) return const _Attempt.stopped();
    try {
      if (op == _Op.pull) {
        pullCount++;
        final result = await service.pull();
        if (_stopped) return const _Attempt.stopped();
        _events.add(result);
      } else {
        pushCount++;
        final result = await service.push();
        if (_stopped) return const _Attempt.stopped();
        _events.add(result);
      }
      _retryAttempts[op] = 0;
      _retryTokens[op] = _retryTokens[op]! + 1;
      return const _Attempt.success();
    } on AppFault catch (fault) {
      if (_stopped) return const _Attempt.stopped();
      _events.add(fault);
      return _Attempt.fault(fault);
    } catch (error) {
      if (_stopped) return const _Attempt.stopped();
      final fault = AppFault.backup(BackupFailureKind.unknown, '$error',
          cause: error);
      _events.add(fault);
      return _Attempt.fault(fault);
    }
  }

  void _startRetryLoop(_Op op, AppFault fault) {
    final token = _retryTokens[op]! + 1;
    _retryTokens[op] = token;
    unawaited(_retryLoop(op, fault, token));
  }

  Future<void> _retryLoop(_Op op, AppFault fault, int token) async {
    var currentFault = fault;
    while (!_stopped && _retryTokens[op] == token) {
      final delay =
          BackupService.nextRetryDelay(currentFault, _retryAttempts[op]!);
      if (delay == null) {
        _retryAttempts[op] = 0;
        return;
      }
      _retryAttempts[op] = _retryAttempts[op]! + 1;
      await sleep(delay);
      if (_stopped || _retryTokens[op] != token) return;

      final attempt = await _attempt(op);
      if (attempt.stopped || attempt.fault == null) return;
      currentFault = attempt.fault!;
    }
  }
}

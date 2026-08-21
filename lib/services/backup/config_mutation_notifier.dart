import 'dart:async';
import 'dart:collection';

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
  final _exclusiveZoneKey = Object();
  final _suspendedZoneKey = Object();
  final Queue<Completer<void>> _exclusiveWaiters = Queue<Completer<void>>();
  var _exclusiveHeld = false;

  bool get _insideExclusive => Zone.current[_exclusiveZoneKey] == this;
  bool get _suspended => Zone.current[_suspendedZoneKey] == this;

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

  /// Serializes a complete config mutation with transactional restores.
  ///
  /// Store writes use this around both persistence and notification. A pull
  /// holds the same lock from its final freshness check through apply and
  /// provenance commit, so an operator edit either lands before that check or
  /// waits until after the restore. It can never be muted in the middle.
  Future<T> runExclusive<T>(Future<T> Function() body) async {
    if (_insideExclusive) return body();

    if (_exclusiveHeld) {
      final turn = Completer<void>();
      _exclusiveWaiters.addLast(turn);
      await turn.future;
    } else {
      _exclusiveHeld = true;
    }

    try {
      return await runZoned(
        body,
        zoneValues: {_exclusiveZoneKey: this},
      );
    } finally {
      if (_exclusiveWaiters.isEmpty) {
        _exclusiveHeld = false;
      } else {
        _exclusiveWaiters.removeFirst().complete();
      }
    }
  }

  Future<void> notify() => runExclusive(_notify);

  Future<void> _notify() async {
    if (_suspended) return;
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(generationKey) ?? 0) + 1;
    final persisted = await prefs.setInt(generationKey, next);
    if (!persisted) {
      await prefs.reload();
      throw StateError('Could not persist config mutation generation');
    }
    _controller.add(next);
  }

  /// Records that [generation] has been durably stored at the target.
  ///
  /// Never clears a generation newer than the one that was pushed: an edit
  /// made while a push was in flight must stay dirty.
  Future<void> markSynced(int generation) =>
      runExclusive(() => _markSynced(generation));

  Future<void> _markSynced(int generation) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(syncedKey) ?? 0;
    if (generation > current) {
      final persisted = await prefs.setInt(syncedKey, generation);
      if (!persisted) {
        await prefs.reload();
        throw StateError('Could not persist synced config generation');
      }
    }
  }

  /// Runs [body] with notifications muted.
  ///
  /// A restore writes through the same stores a user edit does. Without this,
  /// applying a pulled revision emits mutation events and the scheduler
  /// debounces them into a push of what was just pulled.
  Future<T> suspendWhile<T>(Future<T> Function() body) async {
    return runZoned(
      body,
      zoneValues: {_suspendedZoneKey: this},
    );
  }
}

import 'dart:async';

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
  bool _suspended = false;

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

  Future<void> notify() async {
    if (_suspended) return;
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(generationKey) ?? 0) + 1;
    await prefs.setInt(generationKey, next);
    _controller.add(next);
  }

  /// Records that [generation] has been durably stored at the target.
  ///
  /// Never clears a generation newer than the one that was pushed: an edit
  /// made while a push was in flight must stay dirty.
  Future<void> markSynced(int generation) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(syncedKey) ?? 0;
    if (generation > current) await prefs.setInt(syncedKey, generation);
  }

  /// Runs [body] with notifications muted.
  ///
  /// A restore writes through the same stores a user edit does. Without this,
  /// applying a pulled revision emits mutation events and the scheduler
  /// debounces them into a push of what was just pulled.
  Future<T> suspendWhile<T>(Future<T> Function() body) async {
    _suspended = true;
    try {
      return await body();
    } finally {
      _suspended = false;
    }
  }
}

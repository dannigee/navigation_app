import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backup_pointer.dart';
import 'config_mutation_notifier.dart';

/// Write-ahead journal that makes a multi-key import atomic.
///
/// `SharedPreferences` has no transaction. Applying a bundle touches a dozen
/// keys across eight stores, and a failure partway leaves a hybrid of old and
/// new that `ConfigBundle.fromStores()` will happily upload as a valid
/// revision. Capturing previous values first makes "wholly old or wholly new"
/// something that can actually be guaranteed.
class RestoreJournal {
  static const String key = 'backup_restore_journal';

  static const _fixedKeys = <String>[
    'positions',
    'people',
    'services',
    'height_ranges',
    'operators',
    'active_operator_id',
    'roland_ip',
    'panasonic_cameras',
    // Restoring stores without these would leave the generation ahead of the
    // data, so isDirty would lie and the next push would surface a phantom
    // conflict.
    ConfigMutationNotifier.generationKey,
    ConfigMutationNotifier.syncedKey,
    BackupPointer.revisionKey,
    BackupPointer.hashKey,
    BackupPointer.targetKey,
  ];

  static const _prefixes = <String>['preset_names_', 'item_visibility_'];

  static bool isJournalled(String k) =>
      _fixedKeys.contains(k) || _prefixes.any(k.startsWith);

  /// Snapshots every journalled key's current value.
  static Future<void> capture() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = <String, dynamic>{};
    for (final k in prefs.getKeys().where(isJournalled)) {
      snapshot[k] = prefs.get(k);
    }
    await _requirePersisted(
      prefs.setString(key, jsonEncode(snapshot)),
      prefs,
      'restore journal',
    );
  }

  /// Restores every captured key and drops the journal.
  ///
  /// Keys absent from the snapshot are removed, so a partial apply cannot
  /// leave behind a key the operator never had.
  static Future<void> rollbackIfPresent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return;

    final snapshot = jsonDecode(raw) as Map<String, dynamic>;
    for (final k in prefs.getKeys().where(isJournalled).toList()) {
      if (!snapshot.containsKey(k)) {
        await _requirePersisted(
          prefs.remove(k),
          prefs,
          'rollback removal for $k',
        );
      }
    }
    for (final entry in snapshot.entries) {
      final v = entry.value;
      if (v is String) {
        await _requirePersisted(
            prefs.setString(entry.key, v), prefs, entry.key);
      } else if (v is int) {
        await _requirePersisted(prefs.setInt(entry.key, v), prefs, entry.key);
      } else if (v is bool) {
        await _requirePersisted(prefs.setBool(entry.key, v), prefs, entry.key);
      } else if (v is double) {
        await _requirePersisted(
            prefs.setDouble(entry.key, v), prefs, entry.key);
      } else if (v is List) {
        await _requirePersisted(
          prefs.setStringList(entry.key, v.cast<String>()),
          prefs,
          entry.key,
        );
      }
    }
    await clear();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _requirePersisted(prefs.remove(key), prefs, 'restore journal');
  }

  static Future<void> _requirePersisted(
    Future<bool> write,
    SharedPreferences prefs,
    String description,
  ) async {
    if (!await write) {
      await prefs.reload();
      throw StateError('Could not persist $description');
    }
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';

/// Where a macro/preset button should appear. Not yet consumed anywhere —
/// the pages that filter on this live elsewhere.
enum ItemVisibility { hide, expanded, basic }

/// Stores per-item visibility locally, keyed by device IP (or `roland_<ip>`)
/// and 1-based macro number / 0-based preset index — same keying convention
/// as [PresetNameStore].
class VisibilityStore {
  static String _key(String deviceKey) => 'item_visibility_$deviceKey';

  /// Returns all saved visibilities for [deviceKey] as a map of itemIndex -> visibility.
  static Future<Map<int, ItemVisibility>> loadAll(String deviceKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(deviceKey));
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
        (k, v) => MapEntry(int.parse(k), ItemVisibility.values.byName(v as String)));
  }

  /// Saves [visibility] for [itemIndex] on [deviceKey].
  static Future<void> save(
      String deviceKey, int itemIndex, ItemVisibility visibility) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadAll(deviceKey);
    existing[itemIndex] = visibility;
    await prefs.setString(_key(deviceKey),
        jsonEncode(existing.map((k, v) => MapEntry('$k', v.name))));
    await ConfigMutationNotifier.instance.notify();
  }
}

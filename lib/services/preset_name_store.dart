import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';

/// Stores preset names locally, keyed by camera IP and 0-based preset index.
class PresetNameStore {
  static String _key(String cameraIp) => 'preset_names_$cameraIp';

  /// Returns all saved names for [cameraIp] as a map of presetIndex -> name.
  static Future<Map<int, String>> loadAll(String cameraIp) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(cameraIp));
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  /// Saves [name] for [presetIndex] on [cameraIp]. Pass an empty string to clear.
  static Future<void> save(
      String cameraIp, int presetIndex, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadAll(cameraIp);
    if (name.isEmpty) {
      existing.remove(presetIndex);
    } else {
      existing[presetIndex] = name;
    }
    await prefs.setString(
        _key(cameraIp), jsonEncode(existing.map((k, v) => MapEntry('$k', v))));
    await ConfigMutationNotifier.instance.notify();
  }
}

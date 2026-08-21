import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';
import '../models/operator_profile.dart';

class OperatorStore {
  static const _operatorsKey = 'operators';
  static const _activeIdKey = 'active_operator_id';

  static Future<List<OperatorProfile>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_operatorsKey);
    if (raw == null) return [OperatorProfile.defaultProfile];

    final list = jsonDecode(raw) as List<dynamic>;
    final profiles = list
        .map((e) => OperatorProfile.fromJson(e as Map<String, dynamic>))
        .toList();

    if (!profiles.any((p) => p.isDefault)) {
      profiles.insert(0, OperatorProfile.defaultProfile);
    }
    return profiles;
  }

  static Future<void> saveAll(List<OperatorProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = await prefs.setString(
      _operatorsKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
    if (!persisted) {
      await prefs.reload();
      throw StateError('Could not persist operator profiles');
    }
    await ConfigMutationNotifier.instance.notify();
  }

  static Future<String> loadActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeIdKey) ?? OperatorProfile.defaultId;
  }

  static Future<void> saveActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = await prefs.setString(_activeIdKey, id);
    if (!persisted) {
      await prefs.reload();
      throw StateError('Could not persist active operator');
    }
    await ConfigMutationNotifier.instance.notify();
  }
}

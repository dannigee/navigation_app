import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';
import '../models/position.dart';

class PositionStore {
  static const String _key = 'positions';

  static Future<List<Position>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Position.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAll(List<Position> positions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(positions.map((p) => p.toJson()).toList()));
    await ConfigMutationNotifier.instance.notify();
  }
}

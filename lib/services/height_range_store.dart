import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';
import '../models/height_range.dart';

class HeightRangeStore {
  static const String _key = 'height_ranges';

  static Future<List<HeightRange>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => HeightRange.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAll(List<HeightRange> ranges) async {
    await ConfigMutationNotifier.instance.runExclusive(() async {
      final prefs = await SharedPreferences.getInstance();
      final persisted = await prefs.setString(
          _key, jsonEncode(ranges.map((r) => r.toJson()).toList()));
      if (!persisted) {
        await prefs.reload();
        throw StateError('Could not persist height ranges');
      }
      await ConfigMutationNotifier.instance.notify();
    });
  }
}

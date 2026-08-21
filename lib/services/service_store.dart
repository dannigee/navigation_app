import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';
import '../models/service.dart';

class ServiceStore {
  static const String _key = 'services';

  static Future<List<Service>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Service.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAll(List<Service> services) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(services.map((s) => s.toJson()).toList()));
    await ConfigMutationNotifier.instance.notify();
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';
import '../models/person.dart';

class PeopleStore {
  static const String _key = 'people';

  static Future<List<Person>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Person.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAll(List<Person> people) async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = await prefs.setString(
        _key, jsonEncode(people.map((p) => p.toJson()).toList()));
    if (!persisted) {
      await prefs.reload();
      throw StateError('Could not persist people');
    }
    await ConfigMutationNotifier.instance.notify();
  }
}

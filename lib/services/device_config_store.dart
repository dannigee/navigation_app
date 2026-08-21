import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup/config_mutation_notifier.dart';

class CameraEntry {
  final String name;
  final String ip;
  const CameraEntry({required this.name, required this.ip});
  Map<String, dynamic> toJson() => {'name': name, 'ip': ip};
  factory CameraEntry.fromJson(Map<String, dynamic> j) =>
      CameraEntry(name: j['name'] as String, ip: j['ip'] as String);
}

class DeviceConfigStore {
  static const _rolandIpKey = 'roland_ip';
  static const _camerasKey = 'panasonic_cameras';

  static const String defaultRolandIp = '10.0.1.20';
  static const List<CameraEntry> defaultCameras = [
    CameraEntry(name: 'Camera 1', ip: '10.0.1.10'),
    CameraEntry(name: 'Camera 2', ip: '10.0.1.11'),
    CameraEntry(name: 'Camera 3', ip: '10.0.1.12'),
  ];

  static Future<String> loadRolandIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rolandIpKey) ?? defaultRolandIp;
  }

  static Future<List<CameraEntry>> loadCameras() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_camerasKey);
    if (raw == null) return defaultCameras;
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CameraEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(String rolandIp, List<CameraEntry> cameras) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_rolandIpKey, rolandIp),
      prefs.setString(
          _camerasKey, jsonEncode(cameras.map((c) => c.toJson()).toList())),
    ]);
    await ConfigMutationNotifier.instance.notify();
  }
}

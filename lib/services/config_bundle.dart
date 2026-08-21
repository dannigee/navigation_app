import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/height_range.dart';
import '../models/operator_profile.dart';
import '../models/person.dart';
import '../models/position.dart';
import '../models/service.dart';
import 'device_config_store.dart';
import 'height_range_store.dart';
import 'operator_store.dart';
import 'people_store.dart';
import 'position_store.dart';
import 'service_store.dart';
import 'visibility_store.dart';

class ConfigBundle {
  final List<Position> positions;
  final List<Person> people;
  final List<Service> services;
  final List<HeightRange> heightRanges;

  /// Preset/macro names keyed by device storage key, then item index string → custom name.
  final Map<String, Map<String, String>> presetNames;

  /// Item visibility keyed by device storage key, then item index string → visibility name.
  final Map<String, Map<String, String>> visibilities;

  /// Roland V-160HD IP address. Null means "not included in this bundle".
  final String? rolandIp;

  /// Panasonic camera list. Null means "not included in this bundle".
  final List<CameraEntry>? cameras;

  /// Operator profiles. Null means "not included in this bundle".
  final List<OperatorProfile>? operators;

  const ConfigBundle({
    required this.positions,
    required this.people,
    required this.services,
    this.heightRanges = const [],
    this.presetNames = const {},
    this.visibilities = const {},
    this.rolandIp,
    this.cameras,
    this.operators,
  });

  Map<String, dynamic> toJson() => {
        'positions': positions.map((p) => p.toJson()).toList(),
        'people': people.map((p) => p.toJson()).toList(),
        'services': services.map((s) => s.toJson()).toList(),
        'heightRanges': heightRanges.map((r) => r.toJson()).toList(),
        if (presetNames.isNotEmpty) 'presetNames': presetNames,
        if (visibilities.isNotEmpty) 'visibilities': visibilities,
        if (rolandIp != null) 'rolandIp': rolandIp,
        if (cameras != null)
          'cameras': cameras!.map((c) => c.toJson()).toList(),
        if (operators != null)
          'operators': operators!.map((o) => o.toJson()).toList(),
      };

  factory ConfigBundle.fromJson(Map<String, dynamic> json) => ConfigBundle(
        positions: (json['positions'] as List<dynamic>? ?? [])
            .map((p) => Position.fromJson(p as Map<String, dynamic>))
            .toList(),
        people: (json['people'] as List<dynamic>? ?? [])
            .map((p) => Person.fromJson(p as Map<String, dynamic>))
            .toList(),
        services: (json['services'] as List<dynamic>? ?? [])
            .map((s) => Service.fromJson(s as Map<String, dynamic>))
            .toList(),
        heightRanges: (json['heightRanges'] as List<dynamic>? ?? [])
            .map((r) => HeightRange.fromJson(r as Map<String, dynamic>))
            .toList(),
        presetNames: _parseStringStringMaps(json['presetNames']),
        visibilities: _parseStringStringMaps(json['visibilities']),
        rolandIp: json['rolandIp'] as String?,
        cameras: (json['cameras'] as List<dynamic>?)
            ?.map((c) => CameraEntry.fromJson(c as Map<String, dynamic>))
            .toList(),
        operators: (json['operators'] as List<dynamic>?)
            ?.map((o) => OperatorProfile.fromJson(o as Map<String, dynamic>))
            .toList(),
      );

  static Map<String, Map<String, String>> _parseStringStringMaps(dynamic raw) {
    if (raw is! Map<String, dynamic>) return {};
    return raw.map((deviceKey, inner) {
      if (inner is! Map<String, dynamic>) {
        return MapEntry(deviceKey, <String, String>{});
      }
      return MapEntry(
        deviceKey,
        inner.map((k, v) => MapEntry(k, v as String)),
      );
    });
  }

  static const _presetPrefix = 'preset_names_';
  static const _visibilityPrefix = 'item_visibility_';

  static Future<ConfigBundle> fromStores() async {
    final results = await Future.wait([
      PositionStore.loadAll(),
      PeopleStore.loadAll(),
      ServiceStore.loadAll(),
      HeightRangeStore.loadAll(),
    ]);

    final prefs = await SharedPreferences.getInstance();
    final presetNames = <String, Map<String, String>>{};
    final visibilities = <String, Map<String, String>>{};

    for (final key in prefs.getKeys()) {
      if (key.startsWith(_presetPrefix)) {
        final deviceKey = key.substring(_presetPrefix.length);
        final raw = prefs.getString(key);
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          presetNames[deviceKey] =
              decoded.map((k, v) => MapEntry(k, v as String));
        }
      } else if (key.startsWith(_visibilityPrefix)) {
        final deviceKey = key.substring(_visibilityPrefix.length);
        final raw = prefs.getString(key);
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          visibilities[deviceKey] =
              decoded.map((k, v) => MapEntry(k, v as String));
        }
      }
    }

    final rolandIp = await DeviceConfigStore.loadRolandIp();
    final cameras = await DeviceConfigStore.loadCameras();
    final operators = await OperatorStore.loadAll();

    return ConfigBundle(
      positions: results[0] as List<Position>,
      people: results[1] as List<Person>,
      services: results[2] as List<Service>,
      heightRanges: results[3] as List<HeightRange>,
      presetNames: presetNames,
      visibilities: visibilities,
      rolandIp: rolandIp,
      cameras: cameras,
      operators: operators,
    );
  }

  Future<void> saveToStores() async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      PositionStore.saveAll(positions),
      PeopleStore.saveAll(people),
      ServiceStore.saveAll(services),
      HeightRangeStore.saveAll(heightRanges),
      if (rolandIp != null || cameras != null)
        DeviceConfigStore.save(
          rolandIp ?? DeviceConfigStore.defaultRolandIp,
          cameras ?? DeviceConfigStore.defaultCameras,
        ),
      if (operators != null) OperatorStore.saveAll(operators!),
    ]);

    for (final entry in presetNames.entries) {
      await prefs.setString(
          '$_presetPrefix${entry.key}', jsonEncode(entry.value));
    }
    for (final entry in visibilities.entries) {
      await prefs.setString(
          '$_visibilityPrefix${entry.key}', jsonEncode(entry.value));
    }
    // Bypasses VisibilityStore.save above, so bump its notifier directly --
    // otherwise an already-mounted OperatorPanel never learns that imported
    // hide/show values landed underneath it.
    if (visibilities.isNotEmpty) {
      VisibilityStore.changes.value++;
    }
  }

  /// Suggested default export path using the platform Documents folder.
  static String suggestedExportPath() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final filename = 'nav_config_$stamp.json';
    if (kIsWeb) return filename;
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null) return '$home\\Documents\\$filename';
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) return '$home/Documents/$filename';
    }
    return filename;
  }

  static Future<void> writeToPath(String path, ConfigBundle bundle) {
    if (kIsWeb) {
      return Future.error(
          UnsupportedError('File export is not supported on web'));
    }
    return File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(bundle.toJson()),
    );
  }

  static Future<ConfigBundle> readFromPath(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('File import is not supported on web');
    }
    final content = await File(path).readAsString();
    final json = jsonDecode(content);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Not a valid configuration file');
    }
    return ConfigBundle.fromJson(json);
  }
}

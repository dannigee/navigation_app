import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether a macro/preset button should appear in OperatorPanel at all,
/// for every operator (including Default). This is a global suppression
/// layer underneath OperatorProfile.items' per-operator allow-list: a
/// hidden item stays hidden even for an operator whose list explicitly
/// includes it.
enum ItemVisibility { visible, hidden }

/// Stores per-item visibility locally, keyed by device IP (or `roland_<ip>`)
/// and 1-based macro number / 0-based preset index — same keying convention
/// as [PresetNameStore].
class VisibilityStore {
  static String _key(String deviceKey) => 'item_visibility_$deviceKey';

  /// Maps names from the old three-tier enum (`hide`/`expanded`/`basic`) to
  /// their binary equivalent, so data saved before that enum collapsed to
  /// visible/hidden — and configuration bundles exported back then — still
  /// decode instead of throwing in [ItemVisibility.values.byName].
  static const _legacyNames = {
    'hide': 'hidden',
    'expanded': 'visible',
    'basic': 'visible',
  };

  static ItemVisibility _parse(String raw) =>
      ItemVisibility.values.byName(_legacyNames[raw] ?? raw);

  /// Bumped every time [save] persists a change, so widgets that cache
  /// visibility from an earlier [loadAll] (e.g. an already-mounted
  /// OperatorPanel) know to reload without a callback threaded through the
  /// widget tree.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// Returns all saved visibilities for [deviceKey] as a map of itemIndex -> visibility.
  static Future<Map<int, ItemVisibility>> loadAll(String deviceKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(deviceKey));
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded
        .map((k, v) => MapEntry(int.parse(k), _parse(v as String)));
  }

  /// Saves [visibility] for [itemIndex] on [deviceKey].
  static Future<void> save(
      String deviceKey, int itemIndex, ItemVisibility visibility) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadAll(deviceKey);
    existing[itemIndex] = visibility;
    await prefs.setString(_key(deviceKey),
        jsonEncode(existing.map((k, v) => MapEntry('$k', v.name))));
    changes.value++;
  }
}

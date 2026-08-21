import 'package:flutter/foundation.dart';
import '../services/preset_name_store.dart';
import '../services/visibility_store.dart';
import '../utils/label_utils.dart';
import 'service.dart';

/// Base class for a controllable device (Roland V-160HD macros, Panasonic presets, etc.).
///
/// Subclasses provide device-specific [execute] and [refreshItems] logic.
/// Name and visibility persistence is implemented here using [storageKey], so
/// subclasses get rename and visibility for free without duplicating storage code.
abstract class ControllableDevice {
  /// Label shown in the device selector (e.g. 'Roland', 'Camera 1').
  String get name;

  /// Key used to namespace SharedPreferences entries for this device.
  String get storageKey;

  /// Whether the device is currently reachable/connected.
  bool get isConnected;

  /// Notifier that fires when [isConnected] changes.
  ValueListenable<bool> get connectionListenable;

  /// Native indices currently available to show (e.g. 1–100 for Roland macros,
  /// filtered 0–99 subset for Panasonic after querying the camera).
  List<int> get itemIndices;

  /// True while [refreshItems] is fetching data from the device.
  bool get isLoadingItems;

  /// Default button label for [index] when no custom name has been saved.
  String defaultLabel(int index);

  /// Human-readable description of [index] used in response/confirmation text.
  /// Defaults to [defaultLabel]; override for richer descriptions (e.g. 'Preset 5').
  String describe(int index) => defaultLabel(index);

  /// Bare number shown in parentheses alongside a custom name -- e.g. "13"
  /// for Roland macro 13, "4" for Panasonic preset index 3 (1-based).
  String numberSuffix(int index);

  /// Display label for [index]: "name (N)" when [name] is a non-empty custom
  /// name, otherwise just [defaultLabel]. The bare number stays visible next
  /// to a custom name so a renamed item can still be identified by number.
  String labelFor(int index, String? name) =>
      formatItemLabel(name, numberSuffix(index), fallback: defaultLabel(index));

  /// Message shown when [itemIndices] is empty and [isLoadingItems] is false.
  String get emptyMessage => 'No items available';

  /// Refreshes [itemIndices] from the device. No-op for devices whose items
  /// are always the same (e.g. Roland macros).
  Future<void> refreshItems();

  /// Executes the action for [index]. Returns a human-readable success message
  /// or throws [DeviceException] on failure.
  Future<String> execute(int index);

  /// Describes the action that firing [index] performs, as a [ServiceStep].
  /// Used to record a live sequence of actions into a reusable [Service].
  ServiceStep toServiceStep(int index);

  // ── Shared name/visibility persistence ────────────────────────────────────

  Future<Map<int, String>> loadNames() =>
      PresetNameStore.loadAll(storageKey);

  Future<void> saveName(int index, String name) =>
      PresetNameStore.save(storageKey, index, name);

  Future<Map<int, ItemVisibility>> loadVisibility() =>
      VisibilityStore.loadAll(storageKey);

  Future<void> saveVisibility(int index, ItemVisibility visibility) =>
      VisibilityStore.save(storageKey, index, visibility);
}

/// Thrown by [ControllableDevice.execute] to carry a clean user-facing message.
class DeviceException implements Exception {
  const DeviceException(this.message);
  final String message;
  @override
  String toString() => message;
}

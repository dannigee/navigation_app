import 'dart:async';
import 'package:flutter/foundation.dart';
import 'controllable_device.dart';
import 'panasonic_camera_config.dart';
import 'service.dart';

/// [ControllableDevice] implementation for a Panasonic PTZ camera (presets 0–99).
class PanasonicDevice extends ControllableDevice {
  PanasonicDevice(this.camera);

  final PanasonicCameraConfig camera;

  List<int> _availableIndices = [];
  bool _isLoadingItems = false;

  @override
  String get name => camera.name;

  @override
  String get storageKey => camera.ipController.text;

  @override
  bool get isConnected =>
      camera.isConnected.value && camera.service != null;

  @override
  ValueListenable<bool> get connectionListenable => camera.isConnected;

  @override
  List<int> get itemIndices => _availableIndices;

  @override
  bool get isLoadingItems => _isLoadingItems;

  @override
  String defaultLabel(int index) => '${index + 1}';

  @override
  String describe(int index) => 'Preset ${index + 1}';

  @override
  String numberSuffix(int index) => '${index + 1}';

  @override
  String get emptyMessage => 'No saved presets available';

  @override
  Future<void> refreshItems() async {
    if (camera.service == null) {
      _availableIndices = [];
      _isLoadingItems = false;
      return;
    }
    _isLoadingItems = true;
    _availableIndices = List.generate(100, (i) => i); // show all while loading
    try {
      final statuses = await camera.service!
          .getAllPresetStatuses()
          .timeout(const Duration(seconds: 15));
      _availableIndices =
          statuses.entries.where((e) => e.value).map((e) => e.key).toList();
    } on TimeoutException {
      // keep all 100 shown
    } finally {
      _isLoadingItems = false;
    }
  }

  @override
  Future<String> execute(int index) async {
    final service = camera.service;
    if (service == null) {
      throw DeviceException('Camera ${camera.name} not connected');
    }
    try {
      final response = await service.recallPreset(index);
      return 'Camera ${camera.name}: $response';
    } catch (e) {
      throw DeviceException('Error recalling preset: $e');
    }
  }

  @override
  ServiceStep toServiceStep(int index) => ServiceStep(
        id: generateServiceId(),
        type: StepType.shot,
        cameraIp: camera.ipController.text,
        cameraPresetIndex: index,
      );
}

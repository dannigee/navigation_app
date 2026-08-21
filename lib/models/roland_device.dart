import 'package:flutter/foundation.dart';
import '../services/abstract/roland_service_abstract.dart';
import 'controllable_device.dart';
import 'service.dart';

/// [ControllableDevice] implementation for Roland V-160HD macros (1–100).
class RolandDevice extends ControllableDevice {
  RolandDevice({
    required RolandServiceAbstract? Function() service,
    required ValueNotifier<bool> connected,
    required String Function() ip,
  })  : _service = service,
        _connected = connected,
        _ip = ip;

  final RolandServiceAbstract? Function() _service;
  final ValueNotifier<bool> _connected;
  final String Function() _ip;

  static final List<int> _allMacros =
      List.unmodifiable(List.generate(100, (i) => i + 1));

  @override
  String get name => 'Roland';

  @override
  String get storageKey => 'roland_${_ip()}';

  @override
  bool get isConnected => _connected.value;

  @override
  ValueListenable<bool> get connectionListenable => _connected;

  @override
  List<int> get itemIndices => _allMacros;

  @override
  bool get isLoadingItems => false;

  @override
  String defaultLabel(int index) => 'Macro $index';

  @override
  Future<void> refreshItems() async {}

  @override
  Future<String> execute(int index) async {
    final service = _service();
    if (service == null || !isConnected) {
      throw const DeviceException('Roland not connected');
    }
    try {
      await service.executeMacro(index);
      return 'Executed Roland macro $index';
    } catch (e) {
      throw DeviceException('Error executing macro: $e');
    }
  }

  @override
  ServiceStep toServiceStep(int index) => ServiceStep(
        id: generateServiceId(),
        type: StepType.macro,
        macroNumber: index,
      );
}

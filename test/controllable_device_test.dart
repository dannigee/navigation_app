import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/panasonic_device.dart';
import 'package:navigation_app/models/roland_device.dart';
import 'package:navigation_app/models/service.dart';

void main() {
  group('RolandDevice.toServiceStep', () {
    test('produces a macro step for the fired index', () {
      final device = RolandDevice(
        service: () => null,
        connected: ValueNotifier(false),
        ip: () => '10.0.1.20',
      );

      final step = device.toServiceStep(7);

      expect(step.type, StepType.macro);
      expect(step.macroNumber, 7);
      expect(step.cameraIp, isNull);
      expect(step.cameraPresetIndex, isNull);
      expect(step.id, isNotEmpty);
    });
  });

  group('PanasonicDevice.toServiceStep', () {
    test('produces a shot step for the fired preset index', () {
      final camera =
          PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.11');
      addTearDown(camera.dispose);
      final device = PanasonicDevice(camera);

      final step = device.toServiceStep(4);

      expect(step.type, StepType.shot);
      expect(step.cameraIp, '10.0.1.11');
      expect(step.cameraPresetIndex, 4);
      expect(step.macroNumber, isNull);
      expect(step.id, isNotEmpty);
    });
  });

  group('RolandDevice.labelFor', () {
    final device = RolandDevice(
      service: () => null,
      connected: ValueNotifier(false),
      ip: () => '10.0.1.20',
    );

    test('combines a custom name with the macro number', () {
      expect(device.labelFor(13, 'Opening Wide'), 'Opening Wide (13)');
    });

    test('falls back to the default label when no name is set', () {
      expect(device.labelFor(13, null), 'Macro 13');
    });

    test('falls back to the default label when the name is blank', () {
      expect(device.labelFor(13, ''), 'Macro 13');
    });
  });

  group('PanasonicDevice.labelFor', () {
    late PanasonicCameraConfig camera;
    late PanasonicDevice device;

    setUp(() {
      camera = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.11');
      device = PanasonicDevice(camera);
    });
    tearDown(() => camera.dispose());

    test('combines a custom name with the 1-based preset number', () {
      // index 3 is preset 4 (0-based storage, 1-based display).
      expect(device.labelFor(3, 'Cantor'), 'Cantor (4)');
    });

    test('falls back to the default label when no name is set', () {
      expect(device.labelFor(3, null), device.defaultLabel(3));
    });
  });
}

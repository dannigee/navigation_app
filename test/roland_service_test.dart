import 'package:test/test.dart';
import 'package:navigation_app/services/roland_service.dart';

void main() {
  group('RolandService', () {
    late RolandService service;

    setUp(() {
      service = RolandService(host: '127.0.0.1', port: 12345); // Mock server needed
    });

    test('constants are correct', () {
      expect(RolandService.defaultPort, 8023);
      expect(RolandService.maxFaderLevel, 2047);
      expect(RolandService.minFaderLevel, 0);
      expect(RolandService.maxAudioLevel, 100);
      expect(RolandService.minAudioLevel, -800);
    });

    test('host validation', () {
      expect(() => RolandService(host: ''), throwsA(isA<ValidationException>()));
      expect(() => RolandService(host: 'invalid@host'), throwsA(isA<ValidationException>()));
      expect(() => RolandService(host: '192.168.1.1'), isNotNull);
    });

    // Note: Actual connection tests require a mock server
    // For now, test validation
    test('setProgram validates input', () {
      expect(() => service.setProgram('INPUT0'), throwsArgumentError);
      expect(() => service.setProgram('INPUT21'), throwsArgumentError);
      expect(() => service.setProgram('INVALID'), throwsArgumentError);
      expect(() => service.setProgram('HDMI9'), throwsArgumentError);
      // Valid ones should throw ConnectionException since not connected
      expect(() => service.setProgram('HDMI1'), throwsA(isA<ConnectionException>()));
      expect(() => service.setProgram('INPUT1'), throwsA(isA<ConnectionException>()));
    });

    test('setFaderLevel validates level', () {
      expect(() => service.setFaderLevel(-1), throwsArgumentError);
      expect(() => service.setFaderLevel(2048), throwsArgumentError);
    });

    test('setAudioInputLevel validates level', () {
      expect(() => service.setAudioInputLevel('XLR1', -801), throwsArgumentError);
      expect(() => service.setAudioInputLevel('XLR1', 101), throwsArgumentError);
    });

    test('setSplitPositions validates ranges', () {
      expect(() => service.setSplitPositions('SPLIT1', -501, 0), throwsArgumentError);
      expect(() => service.setSplitPositions('SPLIT1', 0, 501), throwsArgumentError);
      expect(() => service.setSplitPositions('SPLIT1', 0, 0, center: 501), throwsArgumentError);
    });

    test('setPanTilt validates directions', () {
      expect(() => service.setPanTilt('CAMERA1', 'INVALID', 'STOP'), throwsArgumentError);
      expect(() => service.setPanTilt('CAMERA1', 'LEFT', 'INVALID'), throwsArgumentError);
      // Valid call would require connection, but validation passes
      expect(() => service.setPanTilt('CAMERA1', 'LEFT', 'STOP'), throwsA(isA<ConnectionException>()));
    });

    test('disconnect handles gracefully', () {
      // Test that disconnect doesn't crash
      service.disconnect();
    });

    test('parseResponse parses VFL correctly', () {
      final result = service.parseResponseForTest('VFL:1024;ACK;');
      expect(result, isA<FaderLevelResponse>());
      expect((result as FaderLevelResponse).level, 1024);
    });

    test('parseResponse parses CAFC correctly', () {
      final result = service.parseResponseForTest('CAFC:CAMERA1,ON;ACK;');
      expect(result, isA<AutoFocusResponse>());
      expect((result as AutoFocusResponse).camera, 'CAMERA1');
      expect((result).status, 'ON');
    });

    test('parseResponse parses CPTS correctly', () {
      final result = service.parseResponseForTest('CPTS:CAMERA1,12;ACK;');
      expect(result, isA<PanTiltSpeedResponse>());
      expect((result as PanTiltSpeedResponse).speed, 12);
    });

    test('parseResponse parses CPR correctly', () {
      final result = service.parseResponseForTest('CPR:CAMERA1,PRESET1;ACK;');
      expect(result, isA<PresetResponse>());
      expect((result as PresetResponse).preset, 'PRESET1');
    });

    test('parseResponse parses HCP correctly', () {
      final result = service.parseResponseForTest('HCP:ON;ACK;');
      expect(result, isA<HdcpResponse>());
      expect((result as HdcpResponse).status, 'ON');
    });

    test('parseResponse handles auto-transmit MTRLV', () {
      final result = service.parseResponseForTest('MTRLV:-INF,-80,0');
      expect(result, isA<MeterResponse>());
      expect((result as MeterResponse).levels, ['-INF', '-80', '0']);
    });
  });
}

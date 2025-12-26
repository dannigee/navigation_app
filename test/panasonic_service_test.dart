import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_app/services/panasonic_service.dart';

void main() {
  group('PanasonicService', () {
    late PanasonicService service;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient((request) async {
        // Mock responses based on request
        if (request.url.toString().contains('aw_ptz') && request.url.toString().contains('%23O1')) {
          return http.Response('"p1"', 200);
        } else if (request.url.toString().contains('aw_cam') && request.url.toString().contains('QID')) {
          return http.Response('"OID:AW-UE100"', 200);
        } else if (request.url.toString().contains('aw_ptz') && request.url.toString().contains('%23P50')) {
          return http.Response('"pS50"', 200);
        } else if (request.url.toString().contains('aw_ptz') && request.url.toString().contains('%23PTV')) {
          return http.Response('"pTV80008000800800800"', 200);
        } else if (request.url.toString().contains('aw_cam') && request.url.toString().contains('OAW:0')) {
          return http.Response('"OAW0"', 200);
        } else if (request.url.toString().contains('aw_cam') && request.url.toString().contains('OGU:10')) {
          return http.Response('"OGU10"', 200);
        }
        return http.Response('ER1', 200);
      });
      service = PanasonicService(ipAddress: '192.168.1.100', client: mockClient);
    });

    tearDown(() {
      service.dispose();
    });

    test('powerOn sends correct command and returns response', () async {
      final result = await service.powerOn();
      expect(result, 'p1');
    });

    test('getCameraInfo sends correct command and returns response', () async {
      final result = await service.getCameraInfo();
      expect(result, 'OID:AW-UE100');
    });

    test('setPanSpeed sends correct command', () async {
      final result = await service.setPanSpeed(50);
      expect(result, 'pS50');
    });

    test('setPanSpeed throws on invalid speed', () async {
      expect(() async => await service.setPanSpeed(0), throwsArgumentError);
      expect(() async => await service.setPanSpeed(100), throwsArgumentError);
    });

    test('getPanTiltZoomFocusIris parses response correctly', () async {
      final result = await service.getPanTiltZoomFocusIris();
      expect(result.pan, '8000');
      expect(result.tilt, '8000');
      expect(result.zoom, '800');
      expect(result.focus, '800');
      expect(result.iris, '800');
    });

    test('setWhiteBalanceMode sends correct command for ATW', () async {
      final result = await service.setWhiteBalanceMode(WhiteBalanceMode.atw);
      expect(result, 'OAW0');
    });

    test('setGain sends correct command', () async {
      final result = await service.setGain(10);
      expect(result, 'OGU10');
    });

    test('setGain throws on invalid gain', () async {
      expect(() async => await service.setGain(7), throwsArgumentError);
      expect(() async => await service.setGain(33), throwsArgumentError);
      expect(() async => await service.setGain(81), throwsArgumentError);
    });

    test('invalid IP throws ArgumentError', () {
      expect(() => PanasonicService(ipAddress: 'invalid'), throwsArgumentError);
    });

    test('setZoomPosition throws on invalid position range', () async {
      expect(() async => await service.setZoomPosition('554'), throwsArgumentError); // Below min
      expect(() async => await service.setZoomPosition('1000'), throwsArgumentError); // Above max
    });

    test('getAllLensPositions returns correct map', () async {
      final mockClientWithLens = MockClient((request) async {
        if (request.url.toString().contains('%23GZ')) {
          return http.Response('"gz800"', 200);
        } else if (request.url.toString().contains('%23GF')) {
          return http.Response('"gf800"', 200);
        } else if (request.url.toString().contains('%23GI')) {
          return http.Response('"gi8000"', 200);
        }
        return http.Response('ER1', 200);
      });
      final serviceWithLens = PanasonicService(ipAddress: '192.168.1.100', client: mockClientWithLens);
      final result = await serviceWithLens.getAllLensPositions();
      expect(result, {'zoom': '800', 'focus': '800', 'iris': '800'});
      serviceWithLens.dispose();
    });

    test('getZoomPosition throws ProtocolException on invalid response', () async {
      final mockClientInvalid = MockClient((request) async {
        if (request.url.toString().contains('%23GZ')) {
          return http.Response('"invalid"', 200);
        }
        return http.Response('ER1', 200);
      });
      final serviceInvalid = PanasonicService(ipAddress: '192.168.1.100', client: mockClientInvalid);
      expect(() async => await serviceInvalid.getZoomPosition(), throwsA(isA<ProtocolException>()));
      serviceInvalid.dispose();
    });

    test('getPanTiltZoomFocusIris throws ProtocolException on invalid PTV response', () async {
      final mockClientInvalidPtv = MockClient((request) async {
        if (request.url.toString().contains('%23PTV')) {
          return http.Response('"pTVinvalid"', 200);
        }
        return http.Response('ER1', 200);
      });
      final serviceInvalidPtv = PanasonicService(ipAddress: '192.168.1.100', client: mockClientInvalidPtv);
      expect(() async => await serviceInvalidPtv.getPanTiltZoomFocusIris(), throwsA(isA<ProtocolException>()));
      serviceInvalidPtv.dispose();
    });

    test('getCurrentGain returns correct value from camera data', () async {
      final mockClientData = MockClient((request) async {
        if (request.url.toString().contains('camdata.html')) {
          return http.Response('"gain=10\nshutter_mode=1"', 200);
        }
        return http.Response('ER1', 200);
      });
      final serviceData = PanasonicService(ipAddress: '192.168.1.100', client: mockClientData);
      final result = await serviceData.getCurrentGain();
      expect(result, 10);
      serviceData.dispose();
    });

    test('getCurrentGain throws CameraException when gain data not available', () async {
      final mockClientNoData = MockClient((request) async {
        if (request.url.toString().contains('camdata.html')) {
          return http.Response('"other=1"', 200);
        }
        return http.Response('ER1', 200);
      });
      final serviceNoData = PanasonicService(ipAddress: '192.168.1.100', client: mockClientNoData);
      expect(() async => await serviceNoData.getCurrentGain(), throwsA(isA<CameraException>()));
      serviceNoData.dispose();
    });

    test('getCurrentShutterMode returns correct value from camera data', () async {
      final mockClientData = MockClient((request) async {
        if (request.url.toString().contains('camdata.html')) {
          return http.Response('"gain=10\nshutter_mode=2"', 200);
        }
        return http.Response('ER1', 200);
      });
      final serviceData = PanasonicService(ipAddress: '192.168.1.100', client: mockClientData);
      final result = await serviceData.getCurrentShutterMode();
      expect(result, 2);
      serviceData.dispose();
    });

    test('getCurrentShutterMode throws CameraException when shutter mode data not available', () async {
      final mockClientNoData = MockClient((request) async {
        if (request.url.toString().contains('camdata.html')) {
          return http.Response('"other=1"', 200);
        }
        return http.Response('ER1', 200);
      });
      final serviceNoData = PanasonicService(ipAddress: '192.168.1.100', client: mockClientNoData);
      expect(() async => await serviceNoData.getCurrentShutterMode(), throwsA(isA<CameraException>()));
      serviceNoData.dispose();
    });
  });
}
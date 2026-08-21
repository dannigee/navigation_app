// Verifies the mock rig against the app's real service classes.
//
// This imports RolandService and PanasonicService exactly as the app does, so a
// pass here means the app itself will work against the mock -- it is not a
// restatement of what the mock believes about the protocol.
//
//   1. sudo python3 tools/mock_server/run.py
//   2. dart run tools/mock_server/verify.dart
//
// Exits non-zero if any check fails.

import 'dart:async';
import 'dart:io';

import 'package:navigation_app/services/panasonic_service.dart';
import 'package:navigation_app/services/roland_service.dart';

const rolandHost = '127.0.0.1';
const cameraIps = ['127.0.0.2', '127.0.0.3', '127.0.0.4'];

int _passed = 0;
int _failed = 0;

void _ok(String what, [String? detail]) {
  _passed++;
  stdout.writeln('  PASS  $what${detail == null ? '' : '  ($detail)'}');
}

void _fail(String what, Object error) {
  _failed++;
  stdout.writeln('  FAIL  $what');
  stdout.writeln('        $error');
}

Future<void> check(String what, Future<void> Function() body) async {
  try {
    await body().timeout(const Duration(seconds: 15));
    _ok(what);
  } catch (e) {
    _fail(what, e);
  }
}

Future<void> expectEquals(String what, Future<Object?> Function() body,
    Object? expected) async {
  try {
    final actual = await body().timeout(const Duration(seconds: 15));
    if (actual == expected) {
      _ok(what, '$actual');
    } else {
      _fail(what, 'expected $expected, got $actual');
    }
  } catch (e) {
    _fail(what, e);
  }
}

Future<void> main() async {
  stdout.writeln('\n=== Roland V-160HD ===');
  await _verifyRoland();

  stdout.writeln('\n=== Panasonic PTZ cameras ===');
  await _verifyCameras();

  stdout.writeln('\n$_passed passed, $_failed failed\n');
  exit(_failed == 0 ? 0 : 1);
}

Future<void> _verifyRoland() async {
  final service = RolandService(host: rolandHost);

  // Collect everything the client manages to parse off the wire.
  final received = <dynamic>[];
  StreamSubscription<dynamic>? sub;

  await check('connect (telnet negotiation + password auth)',
      () => service.connect());

  sub = service.responseStream.listen(received.add, onError: (_) {});

  Future<T?> awaitResponse<T>(Future<void> Function() trigger) async {
    received.clear();
    await trigger();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final hit = received.whereType<T>().cast<T?>().firstWhere(
            (e) => e != null,
            orElse: () => null,
          );
      if (hit != null) return hit;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  await check('CUT;  -> ACK', () => service.cut());
  await check('ATO;  -> ACK', () => service.auto());
  await check('PGM:HDMI3;  -> ACK', () => service.setProgram('HDMI3'));
  await check('PST:SDI1;  -> ACK', () => service.setPreview('SDI1'));
  await check('MCREX:MACRO7;  -> ACK', () => service.executeMacro(7));

  await check('PIS:PinP1,HDMI4;  -> ACK',
      () => service.setPinPSource('PinP1', 'HDMI4'));

  await expectEquals(
    'QPIS:PinP1;  -> parsed PinPSourceResponse',
    () async {
      final r = await awaitResponse<PinPSourceResponse>(
          () => service.getPinPSource('PinP1'));
      return r == null ? null : '${r.pinp}/${r.source}';
    },
    'PinP1/HDMI4',
  );

  await check('PPS:PinP1,ON;  -> ACK',
      () => service.setPinPPgm('PinP1', true));

  await expectEquals(
    'QPPS:PinP1;  -> parsed PinPProgramResponse',
    () async {
      final r = await awaitResponse<PinPProgramResponse>(
          () => service.getPinPPgm('PinP1'));
      return r == null ? null : '${r.pinp}/${r.status}';
    },
    'PinP1/ON',
  );

  await check('PIP:PinP1,250,-125;  -> ACK',
      () => service.setPinPPosition('PinP1', 250, -125));

  await expectEquals(
    'QPIP:PinP1;  -> parsed PinPPositionResponse',
    () async {
      final r = await awaitResponse<PinPPositionResponse>(
          () => service.getPinPPosition('PinP1'));
      return r == null ? null : '${r.h},${r.v}';
    },
    '250,-125',
  );

  await sub.cancel();
  await service.disconnect();
  _ok('disconnect');
}

Future<void> _verifyCameras() async {
  for (final ip in cameraIps) {
    stdout.writeln('-- $ip');
    final cam = PanasonicService(ipAddress: ip);

    await expectEquals('recallPreset(1)  -> #R01',
        () => cam.recallPreset(1), 's01');

    await expectEquals('getPresetName(1)  -> seeded name',
        () => cam.getPresetName(1), 'Ambo');

    await expectEquals(
      'getAllPresetStatuses()  -> seeded presets present',
      () async {
        final all = await cam.getAllPresetStatuses();
        final seeded = List.generate(10, (i) => all[i] == true)
            .every((e) => e);
        final unseeded = all[50] == false && all[77] == false;
        return seeded && unseeded;
      },
      true,
    );

    await expectEquals('savePreset(42)  -> #M42',
        () => cam.savePreset(42), 's42');

    await expectEquals(
      'preset 42 now reports as stored',
      () async {
        final all = await cam.getAllPresetStatuses();
        return all[42];
      },
      true,
    );

    await expectEquals('deletePreset(42)  -> #C42',
        () => cam.deletePreset(42), 's42');

    await expectEquals('setPresetSpeed(250)',
        () => cam.setPresetSpeed('250'), 'uPVS250');

    cam.dispose();
  }
}

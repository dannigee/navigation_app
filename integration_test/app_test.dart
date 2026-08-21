// Integration tests that drive the real app on a real device.
//
//   flutter test integration_test -d macos
//
// Two groups:
//
//   * "app shell" needs no hardware and no mock rig. It runs the app in Demo
//     mode and exercises navigation.
//
//   * "against the mock rig" drives the app in Live mode at the mock server and
//     then asserts against the *rig's* own state over its inspector API — so a
//     pass means the switcher actually received the command, not merely that the
//     app thought it sent one. Skipped automatically when the rig is not running.
//
// Start the rig first for the second group:
//
//   sudo python3 tools/mock_server/run.py

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:navigation_app/main.dart' as app;
import 'package:navigation_app/services/backup/single_instance.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rolandHost = '127.0.0.1';
const rolandPort = 8023;
const inspector = '127.0.0.1:8080';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final rigUp = await _rigReachable();
  if (!rigUp) {
    // ignore: avoid_print
    print('Mock rig not reachable on $rolandHost:$rolandPort — '
        'skipping the live group. Start it with:\n'
        '  sudo python3 tools/mock_server/run.py');
  }

  group('app shell', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(SingleInstance.releaseForTest);

    testWidgets('starts disconnected and in Live mode', (tester) async {
      _useLargeWindow(tester);
      app.main();
      await _pumpUntil(tester, () => _has('No devices connected'));

      expect(_has('No devices connected'), isTrue);
      expect(_has('Live Mode'), isTrue,
          reason: 'the app has defaulted to production mode since 9ec4c33');
      expect(find.widgetWithText(FilledButton, 'Connect All'), findsOneWidget);
    });

    testWidgets('Demo mode connects and reveals the three tabs',
        (tester) async {
      _useLargeWindow(tester);
      app.main();
      await _pumpUntil(tester, () => _has('No devices connected'));

      await _enableDemoMode(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect All'));
      await _pumpUntil(tester, () => _has('Service'),
          timeout: const Duration(seconds: 20));

      expect(_has('Service'), isTrue);
      expect(_has('Panel'), isTrue);
      expect(_has('Positions'), isTrue);
    });

    testWidgets('Panel lists the Roland and every configured camera',
        (tester) async {
      _useLargeWindow(tester);
      SharedPreferences.setMockInitialValues({
        'panasonic_cameras': jsonEncode([
          {'name': 'Cam A', 'ip': '10.9.9.1'},
          {'name': 'Cam B', 'ip': '10.9.9.2'},
        ]),
      });

      app.main();
      await _pumpUntil(tester, () => _has('No devices connected'));
      await _enableDemoMode(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect All'));
      await _pumpUntil(tester, () => _has('Panel'),
          timeout: const Duration(seconds: 20));

      await _switchTab(tester, 'Panel', 'Roland');

      expect(_has('Roland'), isTrue);
      expect(_has('Cam A'), isTrue);
      expect(_has('Cam B'), isTrue);
    });
  });

  group('against the mock rig', () {
    setUp(() async {
      await _rigReset();
      SharedPreferences.setMockInitialValues({
        'roland_ip': rolandHost,
        'panasonic_cameras': jsonEncode([
          {'name': 'Cam 1 House', 'ip': '127.0.0.2'},
          {'name': 'Cam 2 Sanctuary', 'ip': '127.0.0.3'},
          {'name': 'Cam 3 Choir', 'ip': '127.0.0.4'},
        ]),
      });
    });

    testWidgets('firing a macro reaches the switcher', (tester) async {
      _useLargeWindow(tester);
      final before = await _rigState();

      app.main();
      await _pumpUntil(tester, () => _has('No devices connected'));

      await tester.tap(find.widgetWithText(FilledButton, 'Connect All'));
      await _pumpUntil(tester, () => _has('Panel'),
          timeout: const Duration(seconds: 40));

      await _switchTab(tester, 'Panel', 'Macro 7');

      await tester.tap(find.text('Macro 7'));
      await tester.pump(const Duration(seconds: 2));

      // The assertion that matters: ask the rig what it received. If the app
      // silently swallowed the command this fails, however healthy the UI looks.
      final after = await _rigUntil(
        (s) => s['lastMacro'] == 7,
        describe: 'switcher to report MACRO7',
      );

      expect(after['lastMacro'], 7);
      expect(after['commandCount'], greaterThan(before['commandCount'] as int));
      expect(after['nackCount'], before['nackCount'],
          reason: 'the switcher should not have rejected anything');
    });

    testWidgets('a camera preset recall reaches that camera', (tester) async {
      _useLargeWindow(tester);
      app.main();
      await _pumpUntil(tester, () => _has('No devices connected'));

      await tester.tap(find.widgetWithText(FilledButton, 'Connect All'));
      await _pumpUntil(tester, () => _has('Panel'),
          timeout: const Duration(seconds: 40));

      await _switchTab(tester, 'Panel', 'Cam 1 House');

      await tester.tap(find.text('Cam 1 House'));
      // Preset buttons are labelled 1-based; the rig seeds presets 0-9.
      await _pumpUntil(tester, () => _has('5'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      await tester.tap(find.text('5').first);
      await tester.pump(const Duration(seconds: 2));

      final after = await _rigUntil(
        (s) => (s['cameras'] as List).first['lastPreset'] == 4,
        describe: 'Cam 1 to report preset index 4',
      );

      final cam = (after['cameras'] as List).first;
      expect(cam['lastPreset'], 4, reason: 'button "5" is preset index 4');
      expect(cam['lastPresetName'], 'Cantor');
    });
  }, skip: rigUp ? false : 'mock rig not running on $rolandHost:$rolandPort');
}

// ---------------------------------------------------------------------------
// helpers

bool _has(String text) => find.text(text).evaluate().isNotEmpty;

/// Desktop integration tests inherit whatever window size the app opens at,
/// which is too small for the Panel grid — buttons lay out beyond the visible
/// view and taps miss the hit test. Pin a generous logical size instead.
void _useLargeWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Switch tabs and wait for the transition to finish.
///
/// TabBarView wraps its pages in an IgnorePointer while they animate, so a tap
/// issued as soon as the target text appears silently misses the hit test. Wait
/// for the page to exist *and then* let the slide complete.
Future<void> _switchTab(WidgetTester tester, String tab, String expect) async {
  await tester.tap(find.text(tab));
  await _pumpUntil(tester, () => _has(expect));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Pump until [condition] holds. `pumpAndSettle` is unusable here: the connect
/// spinner and the PinP poll timer mean the tree rarely goes quiet.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (condition()) return;
  }
  fail('timed out after $timeout waiting for the UI condition');
}

Future<void> _enableDemoMode(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Settings'));
  await _pumpUntil(tester, () => find.byType(Switch).evaluate().isNotEmpty);

  await tester.tap(find.byType(Switch).first);
  await _pumpUntil(tester, () => _has('Demo Mode'));

  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await _pumpUntil(tester, () => _has('No devices connected'));
}

Future<bool> _rigReachable() async {
  try {
    final socket = await Socket.connect(rolandHost, rolandPort,
        timeout: const Duration(seconds: 2));
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

/// Clear rig state and faults so a test cannot pass on residue from an earlier
/// run — the `lastMacro == 7` assertion did exactly that before this existed.
Future<void> _rigReset() async {
  await http
      .post(Uri.parse('http://$inspector/control'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'reset'}))
      .timeout(const Duration(seconds: 5));
}

Future<Map<String, dynamic>> _rigState() async {
  final res = await http
      .get(Uri.parse('http://$inspector/state'))
      .timeout(const Duration(seconds: 5));
  return jsonDecode(res.body) as Map<String, dynamic>;
}

/// Poll the rig until [condition] holds, so the test does not depend on how
/// long a real socket round trip happens to take.
Future<Map<String, dynamic>> _rigUntil(
  bool Function(Map<String, dynamic>) condition, {
  required String describe,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  Map<String, dynamic> state = const {};
  while (DateTime.now().isBefore(deadline)) {
    state = await _rigState();
    if (condition(state)) return state;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('timed out after $timeout waiting for $describe; last state: $state');
}

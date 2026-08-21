// Layout checks at real iPad dimensions.
//
//   flutter test integration_test/ipad_layout_test.dart -d macos
//
// Every dialog in this app is a hardcoded pixel width (400-700) and there are no
// width breakpoints anywhere in lib/. This opens each one at the logical size of
// each iPad the app might land on and fails if Flutter reports an overflow,
// which it does as a caught exception rather than a silent visual glitch.
//
// Runs on any device — the view size is overridden, so layout is what is under
// test, not the host platform.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:navigation_app/main.dart' as app;
import 'package:navigation_app/services/backup/single_instance.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Logical point sizes, portrait. Landscape is derived by flipping.
const iPads = <String, Size>{
  'iPad mini': Size(744, 1133),
  'iPad (A16)': Size(820, 1180),
  'iPad Pro 11': Size(834, 1194),
  'iPad Pro 13': Size(1024, 1366),
};

/// Settings tiles and the title of the dialog each one opens.
const dialogs = <String, String>{
  'Manage Operators': 'Manage Operators',
  'Preset Labels & Visibility': 'Preset Labels',
  'Manage Positions': 'Manage Positions',
  'Manage Services': 'Manage Services',
  'Manage Height Ranges': 'Height Ranges',
  'Connections': 'Manage Connections',
  'PinP': 'PinP',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in iPads.entries) {
    for (final portrait in [true, false]) {
      final size = portrait
          ? entry.value
          : Size(entry.value.height, entry.value.width);
      final label = '${entry.key} ${portrait ? 'portrait' : 'landscape'} '
          '(${size.width.toInt()}x${size.height.toInt()})';

      group(label, () {
        setUp(() {
          SharedPreferences.setMockInitialValues({
            'panasonic_cameras': jsonEncode([
              {'name': 'Cam 1 House', 'ip': '127.0.0.2'},
              {'name': 'Cam 2 Sanctuary', 'ip': '127.0.0.3'},
              {'name': 'Cam 3 Choir', 'ip': '127.0.0.4'},
            ]),
          });
        });
        tearDown(SingleInstance.releaseForTest);

        for (final tile in dialogs.keys) {
          testWidgets('$tile lays out without overflow', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            app.main();
            await _pumpUntil(tester, () => _has('No devices connected'));

            await tester.tap(find.widgetWithText(OutlinedButton, 'Settings'));
            await _pumpUntil(tester, () => _has('Manage Operators'));
            await _settle(tester);

            final target = find.text(tile);
            expect(target, findsWidgets, reason: 'settings tile "$tile"');
            await tester.ensureVisible(target.first);
            await _settle(tester);

            await tester.tap(target.first);
            await _settle(tester, frames: 20);

            // An overflow surfaces here rather than as a visual glitch.
            expect(tester.takeException(), isNull,
                reason: '$tile overflowed at ${size.width.toInt()}pt wide');
          });
        }
      });
    }
  }
}

bool _has(String text) => find.text(text).evaluate().isNotEmpty;

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

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

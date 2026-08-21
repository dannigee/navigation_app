import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/widgets/multi_device_control_page.dart';

// Connects using Demo Mode so tests never attempt a real network connection.
// The app now defaults to production (live) mode, so tests must switch it
// on explicitly before hitting "Connect All".
Future<void> _connect(WidgetTester tester) async {
  await tester
      .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
  await tester.pumpAndSettle();

  await tester.tap(find.descendant(
      of: find.byType(AppBar), matching: find.byIcon(Icons.settings)));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Switch));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Connect All'));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MultiDeviceControlPage — tabs', () {
    testWidgets('shows Service, Panel, and Positions tabs once connected',
        (tester) async {
      await _connect(tester);

      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Panel'), findsOneWidget);
      expect(find.text('Positions'), findsOneWidget);
    });

    testWidgets('does not show a Switching tab', (tester) async {
      await _connect(tester);

      expect(find.text('Switching'), findsNothing);
    });
  });

  group('MultiDeviceControlPage — AppBar identity', () {
    testWidgets('shows the active operator name once connected',
        (tester) async {
      await _connect(tester);

      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('shows a Demo mode badge once connected in Demo Mode',
        (tester) async {
      await _connect(tester);

      expect(find.text('Demo'), findsOneWidget);
    });
  });

  group('MultiDeviceControlPage — production mode default', () {
    testWidgets('defaults to Live Mode (not Demo Mode) before connecting',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
      await tester.pumpAndSettle();

      expect(find.text('Live Mode'), findsOneWidget);
      expect(find.text('Demo Mode'), findsNothing);
    });

    testWidgets('does not show a "Roland V-160HD Control" title',
        (tester) async {
      await _connect(tester);

      expect(find.text('Roland V-160HD Control'), findsNothing);
    });
  });

  group('MultiDeviceControlPage — People shortcut', () {
    testWidgets('AppBar has a People shortcut icon when connected',
        (tester) async {
      await _connect(tester);

      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('tapping the People shortcut opens the People manager',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.byIcon(Icons.person_add));
      await tester.pumpAndSettle();

      expect(find.text('Add Person'), findsOneWidget);
    });

    testWidgets('AppBar has a People shortcut icon before connecting',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets(
        'Settings dialog also has a Manage People tile, for setup discovery',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // The AppBar icon remains the fast path for the frequent case (a new
      // person filling a role); this tile exists so Settings' Positions /
      // Services / Height Ranges group doesn't leave People undiscoverable
      // during initial setup.
      expect(find.text('Manage People'), findsOneWidget);
    });
  });

  group('MultiDeviceControlPage — operator switching', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OperatorStore.saveAll([
        OperatorProfile.defaultProfile,
        const OperatorProfile(id: 'op2', name: 'Engineer'),
      ]);
    });

    testWidgets(
        'tapping the operator name in the AppBar opens a switch-operator dialog',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();

      expect(find.text('Switch Operator'), findsOneWidget);
      expect(find.text('Engineer'), findsOneWidget);
    });

    testWidgets('selecting a different operator updates the AppBar name',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Engineer'));
      await tester.pumpAndSettle();

      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('Default'), findsNothing);
    });

    testWidgets('Settings dialog no longer has an Active operator tile',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.textContaining('Active:'), findsNothing);
      expect(find.text('Tap to switch operator'), findsNothing);
    });
  });
}

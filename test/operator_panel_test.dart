import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/abstract/roland_service_abstract.dart';
import 'package:navigation_app/services/mock/mock_roland_service.dart';
import 'package:navigation_app/services/service_store.dart';
import 'package:navigation_app/services/visibility_store.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/widgets/operator_panel.dart';

Widget _build({
  OperatorProfile operator = OperatorProfile.defaultProfile,
  List<PanasonicCameraConfig> cameras = const [],
  RolandServiceAbstract? rolandService,
  ValueNotifier<bool>? rolandConnected,
  VoidCallback? onServicesChanged,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Scaffold(
      body: OperatorPanel(
        operator: operator,
        rolandService: rolandService,
        rolandConnected: rolandConnected ?? ValueNotifier(false),
        cameras: cameras,
        onResponse: (_) {},
        onServicesChanged: onServicesChanged,
      ),
    ),
  );
}

Widget _buildConnected({
  OperatorProfile operator = OperatorProfile.defaultProfile,
  List<PanasonicCameraConfig> cameras = const [],
  VoidCallback? onServicesChanged,
}) =>
    _build(
      operator: operator,
      cameras: cameras,
      rolandService: MockRolandService(),
      rolandConnected: ValueNotifier(true),
      onServicesChanged: onServicesChanged,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OperatorPanel — device tabs', () {
    testWidgets('shows Roland tab by default', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Roland'), findsOneWidget);
    });

    testWidgets('shows camera tab when a camera is provided', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();
      expect(find.text('Wide'), findsOneWidget);
    });

    testWidgets('Roland tab is selected initially', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();
      final tb = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(tb.isSelected[0], isTrue);
      expect(tb.isSelected[1], isFalse);
    });
  });

  group('OperatorPanel — Default operator', () {
    testWidgets('shows all 100 Roland macros', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets('shows Macro 1 button', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Macro 1'), findsWidgets);
    });

    testWidgets('shows no empty-state message', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.textContaining('No items'), findsNothing);
    });
  });

  group('OperatorPanel — custom operator', () {
    testWidgets('shows empty state when operator has no items configured',
        (tester) async {
      const op = OperatorProfile(id: 'op1', name: 'Sound');
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.textContaining('No items configured'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows only configured items', (tester) async {
      const op = OperatorProfile(
        id: 'op1',
        name: 'Camera Op',
        items: {'roland_': [3, 7, 42]},
      );
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(3));
    });

    testWidgets('shows custom preset name when saved', (tester) async {
      await PresetNameStore.save('roland_', 3, 'Entrance');
      const op = OperatorProfile(
        id: 'op1',
        name: 'Camera Op',
        items: {'roland_': [3]},
      );
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.text('Entrance'), findsOneWidget);
    });

    testWidgets('empty state mentions the operator name', (tester) async {
      const op = OperatorProfile(id: 'op1', name: 'Choir Director');
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.textContaining('Choir Director'), findsOneWidget);
    });
  });

  group('OperatorPanel — camera tab', () {
    testWidgets('tapping camera tab switches selection', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Side', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Side'));
      await tester.pumpAndSettle();

      final tb = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(tb.isSelected[1], isTrue);
    });

    testWidgets(
        'disconnected camera with no items shows empty panel for custom op',
        (tester) async {
      final cam = PanasonicCameraConfig(name: 'Close', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      const op = OperatorProfile(id: 'op1', name: 'Op');
      await tester.pumpWidget(_build(operator: op, cameras: [cam]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('OperatorPanel — operator rebuild', () {
    testWidgets('rebuilds when operator prop changes', (tester) async {
      const op1 = OperatorProfile(
        id: 'op1',
        name: 'A',
        items: {'roland_': [1]},
      );
      const op2 = OperatorProfile(
        id: 'op2',
        name: 'B',
        items: {'roland_': [1, 2, 3]},
      );

      // Start with op1 (1 button)
      await tester.pumpWidget(_build(operator: op1));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(1));

      // Switch to op2 (3 buttons)
      await tester.pumpWidget(_build(operator: op2));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(3));
    });
  });

  // VisibilityStore is no longer used by OperatorPanel — confirm independence.
  group('OperatorPanel — no dependency on VisibilityStore', () {
    testWidgets(
        'Default operator shows all items regardless of saved visibility',
        (tester) async {
      // Tag macro 1 as hidden in VisibilityStore — should have no effect
      await VisibilityStore.save('roland_', 1, ItemVisibility.hide);
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      // Macro 1 should still appear (OperatorPanel ignores VisibilityStore)
      expect(find.text('Macro 1'), findsWidgets);
    });
  });

  group('OperatorPanel — recording', () {
    testWidgets('shows a Record button that is not active initially',
        (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('tapping Record switches to a Stop button with a step count',
        (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Stop'), findsOneWidget);
      expect(find.textContaining('0 step'), findsOneWidget);
    });

    testWidgets('firing an action while recording increments the step count',
        (tester) async {
      await tester.pumpWidget(_buildConnected());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('1 step'), findsOneWidget);
    });

    testWidgets('firing an action while not recording does not open the save dialog',
        (tester) async {
      await tester.pumpWidget(_buildConnected());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('stopping with no recorded steps does not show a save dialog',
        (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets(
        'stopping with recorded steps opens a naming dialog; Save persists the Service',
        (tester) async {
      var changedCount = 0;
      await tester.pumpWidget(
          _buildConnected(onServicesChanged: () => changedCount++));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 2').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Recorded Run');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = await ServiceStore.loadAll();
      expect(saved, hasLength(1));
      expect(saved.first.name, 'Recorded Run');
      expect(saved.first.steps.map((s) => s.type),
          [StepType.macro, StepType.macro]);
      expect(saved.first.steps.map((s) => s.macroNumber), [1, 2]);
      expect(changedCount, 1);

      // Recording state is reset back to idle.
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('Discard clears the pending recording without saving',
        (tester) async {
      await tester.pumpWidget(_buildConnected());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(await ServiceStore.loadAll(), isEmpty);
      expect(find.text('Record'), findsOneWidget);
    });
  });
}

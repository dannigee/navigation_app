import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/height_range_store.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/utils/height_utils.dart';
import 'package:navigation_app/widgets/height_range_manager_dialog.dart';

Future<void> _open(
    WidgetTester tester, Widget Function(BuildContext) builder) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Builder(
        builder: (ctx) => TextButton(
              onPressed: () =>
                  showDialog<void>(context: ctx, builder: builder),
              child: const Text('Open'),
            )),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HeightRangeManagerDialog — list view', () {
    testWidgets('shows empty state when no ranges exist', (tester) async {
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.textContaining('No height ranges yet'), findsOneWidget);
    });

    testWidgets('shows ranges from the store labeled by their bounds',
        (tester) async {
      await HeightRangeStore.saveAll([
        HeightRange(id: 'r1', maxHeightCm: feetInchesToCm(5, 4)),
        HeightRange(id: 'r2'),
      ]);
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));

      expect(find.textContaining('Up to 5\'4"'), findsOneWidget);
      expect(find.textContaining('Taller than 5\'4"'), findsOneWidget);
    });

    testWidgets('a lone catch-all range displays as "Any height"',
        (tester) async {
      await HeightRangeStore.saveAll([HeightRange(id: 'r1')]);
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));

      expect(find.textContaining('Any height'), findsOneWidget);
    });

    testWidgets('shows Add Height Range button', (tester) async {
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.text('Add Height Range'), findsOneWidget);
    });
  });

  group('HeightRangeManagerDialog — add / edit', () {
    testWidgets('Add Height Range opens an editor with only max-height fields',
        (tester) async {
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Height Range'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Name'), findsNothing);
      expect(find.widgetWithText(TextField, 'Max Height — ft'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Max Height — in'), findsOneWidget);
    });

    testWidgets('saving with a bound adds a range labeled by that bound',
        (tester) async {
      bool saved = false;
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));
      await tester.tap(find.text('Add Height Range'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Max Height — ft'), '5');
      await tester.enterText(
          find.widgetWithText(TextField, 'Max Height — in'), '4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Up to 5\'4"'), findsOneWidget);
      expect(saved, isTrue);

      final stored = await HeightRangeStore.loadAll();
      expect(stored.single.maxHeightCm, feetInchesToCm(5, 4));
    });

    testWidgets(
        'leaving max height blank creates a catch-all range shown as "Any height"',
        (tester) async {
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Height Range'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Any height'), findsOneWidget);

      final stored = await HeightRangeStore.loadAll();
      expect(stored.single.maxHeightCm, isNull);
    });

    testWidgets('Cancel from editor returns to list without saving',
        (tester) async {
      bool saved = false;
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));
      await tester.tap(find.text('Add Height Range'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Max Height — ft'), '9');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No height ranges yet'), findsOneWidget);
      expect(saved, isFalse);
    });

    testWidgets('editing an existing range prefills its max-height fields',
        (tester) async {
      await HeightRangeStore.saveAll([
        HeightRange(id: 'r1', maxHeightCm: feetInchesToCm(5, 4)),
      ]);
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      final ftField = tester
          .widget<TextField>(find.widgetWithText(TextField, 'Max Height — ft'));
      expect(ftField.controller?.text, '5');
      final inField = tester
          .widget<TextField>(find.widgetWithText(TextField, 'Max Height — in'));
      expect(inField.controller?.text, '4');
    });

    testWidgets(
        'preset grid shows positions and cameras with a dropdown, and saves entries',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
                positions: [Position(id: 'pos1', name: 'Lectern')],
                cameras: [cam],
                onSaved: () {},
              ));
      await tester.tap(find.text('Add Height Range'));
      await tester.pumpAndSettle();

      expect(find.text('Lectern'), findsOneWidget);
      expect(find.text('Cam 1'), findsOneWidget);
      expect(find.byType(DropdownButton<int?>), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Preset #'), findsNothing);

      await tester.tap(find.byType(DropdownButton<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await HeightRangeStore.loadAll();
      expect(stored.single.positionPresets['pos1']?['10.0.1.10'], 2);
    });

    testWidgets(
        'editing an existing range prefills its preset dropdown selection',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await HeightRangeStore.saveAll([
        HeightRange(
          id: 'r1',
          positionPresets: {
            'pos1': {'10.0.1.10': 6},
          },
        ),
      ]);

      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
                positions: [Position(id: 'pos1', name: 'Lectern')],
                cameras: [cam],
                onSaved: () {},
              ));
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      final dropdown =
          tester.widget<DropdownButton<int?>>(find.byType(DropdownButton<int?>));
      expect(dropdown.value, 7);
    });
  });

  group('HeightRangeManagerDialog — preset names', () {
    testWidgets('preset dropdown shows a saved preset name instead of its number',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await PresetNameStore.save('10.0.1.10', 4, 'Wide Shot');

      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
                positions: [Position(id: 'pos1', name: 'Lectern')],
                cameras: [cam],
                onSaved: () {},
              ));
      await tester.tap(find.text('Add Height Range'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<int?>));
      await tester.pumpAndSettle();

      expect(find.text('Wide Shot (5)'), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('selecting a named preset persists its underlying index',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await PresetNameStore.save('10.0.1.10', 4, 'Wide Shot');

      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
                positions: [Position(id: 'pos1', name: 'Lectern')],
                cameras: [cam],
                onSaved: () {},
              ));
      await tester.tap(find.text('Add Height Range'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wide Shot (5)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await HeightRangeStore.loadAll();
      expect(stored.single.positionPresets['pos1']?['10.0.1.10'], 4);
    });
  });

  group('HeightRangeManagerDialog — delete', () {
    testWidgets('delete shows confirmation dialog', (tester) async {
      await HeightRangeStore.saveAll([HeightRange(id: 'r1')]);
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.text('Delete Height Range'), findsOneWidget);
    });

    testWidgets('confirming delete removes the range', (tester) async {
      bool saved = false;
      await HeightRangeStore.saveAll(
          [HeightRange(id: 'r1', maxHeightCm: feetInchesToCm(5, 4))]);
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Up to 5\'4"'), findsNothing);
      expect(find.textContaining('No height ranges yet'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('cancelling delete keeps the range', (tester) async {
      await HeightRangeStore.saveAll(
          [HeightRange(id: 'r1', maxHeightCm: feetInchesToCm(5, 4))]);
      await _open(
          tester,
          (_) => HeightRangeManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Up to 5\'4"'), findsOneWidget);
    });
  });
}

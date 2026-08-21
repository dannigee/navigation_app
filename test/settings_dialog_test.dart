import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/services/height_range_store.dart';
import 'package:navigation_app/utils/height_utils.dart';
import 'package:navigation_app/widgets/settings_dialog.dart';

Widget _settingsDialog({
  List<HeightRange> heightRanges = const [],
  VoidCallback? onHeightRangesChanged,
  VoidCallback? onPeopleChanged,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => showDialog<void>(
          context: ctx,
          builder: (_) => SettingsDialog(
            mockMode: true,
            onMockModeChanged: (_) {},
            rolandService: null,
            rolandIpController: TextEditingController(),
            rolandConnected: ValueNotifier(false),
            rolandConnecting: ValueNotifier(false),
            rolandConnectionError: ValueNotifier(''),
            onConnectRoland: () async {},
            panasonicCameras: const [],
            onConnectPanasonic: (_) async {},
            onResponse: (_) {},
            positions: const [],
            heightRanges: heightRanges,
            onPositionsChanged: () {},
            onServicesChanged: () {},
            onHeightRangesChanged: onHeightRangesChanged ?? () {},
            onPeopleChanged: onPeopleChanged ?? () {},
            onAllDataChanged: () {},
            onDeviceConfigSaved: (_, __) {},
            onOperatorsChanged: () {},
          ),
        ),
        child: const Text('Open'),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a Manage Height Ranges tile', (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Manage Height Ranges'), findsOneWidget);
  });

  testWidgets('tapping the tile opens the HeightRangeManagerDialog',
      (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();

    expect(find.text('Add Height Range'), findsOneWidget);
  });

  testWidgets('saving a new height range calls onHeightRangesChanged',
      (tester) async {
    bool changed = false;
    await tester.pumpWidget(
        _settingsDialog(onHeightRangesChanged: () => changed = true));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Height Range'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Max Height — ft'), '5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(changed, isTrue);
    final stored = await HeightRangeStore.loadAll();
    expect(stored.single.maxHeightCm, feetInchesToCm(5, 0));
  });

  testWidgets('shows a Manage People tile', (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Manage People'), findsOneWidget);
  });

  testWidgets('tapping the tile opens the PeopleManagerDialog',
      (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Manage People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage People'));
    await tester.pumpAndSettle();

    expect(find.text('Add Person'), findsOneWidget);
  });
}

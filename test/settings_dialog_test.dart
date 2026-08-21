import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/height_range_store.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/utils/height_utils.dart';
import 'package:navigation_app/widgets/settings_dialog.dart';

Widget _settingsDialog({
  List<HeightRange> heightRanges = const [],
  VoidCallback? onHeightRangesChanged,
  ValueChanged<String>? onResponse,
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
            onResponse: onResponse ?? (_) {},
            positions: const [],
            heightRanges: heightRanges,
            onPositionsChanged: () {},
            onServicesChanged: () {},
            onHeightRangesChanged: onHeightRangesChanged ?? () {},
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

  testWidgets('import commits the active-operator reset as pending work',
      (tester) async {
    late final Directory tempDir;
    late final File configFile;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('nav-import-test-');
      configFile = File('${tempDir.path}/config.json');
      await configFile.writeAsString(jsonEncode({
        'schemaVersion': 1,
        'positions': <dynamic>[],
        'people': <dynamic>[],
        'services': <dynamic>[],
        'heightRanges': <dynamic>[],
      }));
    });
    addTearDown(() => tempDir.delete(recursive: true));
    await OperatorStore.saveActiveId('operator-who-will-not-exist');
    final seen = <int>[];
    final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);
    addTearDown(sub.cancel);
    String? response;

    await tester.pumpWidget(
      _settingsDialog(onResponse: (value) => response = value),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Import Configuration'));
    await tester.tap(find.text('Import Configuration'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), configFile.path);
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    for (var attempt = 0;
        attempt < 20 && find.text('Replace all').evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('Replace all'), findsOneWidget);
    await tester.tap(find.text('Replace all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(response, 'Configuration imported successfully');
    expect(await OperatorStore.loadActiveId(), OperatorProfile.defaultId);
    expect(seen, [2],
        reason: 'the prior operator edit was generation 1; import is one edit');
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'manual import must remain pending across app termination');
  });
}

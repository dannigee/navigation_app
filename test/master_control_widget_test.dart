import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/controllable_device.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/widgets/master_control_widget.dart';

/// A minimal [ControllableDevice] whose [saveName] can be held open on
/// [saveNameGate] and whose calls are recorded in [saveNameCalls] --
/// used to deterministically reproduce races between an in-flight save
/// and a device/item switch that would otherwise depend on real timing.
class _GatedDevice extends ControllableDevice {
  _GatedDevice(this.name, this.storageKey);

  @override
  final String name;
  @override
  final String storageKey;

  Completer<void>? saveNameGate;
  final List<String> saveNameCalls = [];

  @override
  bool get isConnected => true;

  @override
  ValueListenable<bool> get connectionListenable => ValueNotifier(true);

  @override
  List<int> get itemIndices => const [1, 2, 3];

  @override
  bool get isLoadingItems => false;

  @override
  String defaultLabel(int index) => '$name Item $index';

  @override
  Future<void> refreshItems() async {}

  @override
  Future<String> execute(int index) async => 'executed';

  @override
  ServiceStep toServiceStep(int index) =>
      ServiceStep(id: 'step', type: StepType.macro, macroNumber: index);

  @override
  Future<void> saveName(int index, String name) async {
    saveNameCalls.add('start:$index:$name');
    if (saveNameGate != null) await saveNameGate!.future;
    saveNameCalls.add('resolve:$index:$name');
    await super.saveName(index, name);
  }
}

Widget _build() {
  return MaterialApp(
    home: Scaffold(
      body: MasterControlWidget(
        rolandService: null,
        rolandConnected: ValueNotifier(false),
        cameras: const [],
        onResponse: (_) {},
      ),
    ),
  );
}

Future<void> _selectMacro(WidgetTester tester, String macro) async {
  await tester.tap(find.text('Edit Mode'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(macro));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Rename and Visibility are hidden until Edit Mode is on',
      (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsNothing);
    expect(find.text('Visibility'), findsNothing);

    await tester.tap(find.text('Edit Mode'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Visibility'), findsOneWidget);
  });

  testWidgets('there is no separate Save Name button', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    expect(find.text('Save Name'), findsNothing);
  });

  testWidgets('grid buttons have no hover tooltip', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets(
      'selecting an item with no saved name pre-fills the field with its '
      'current (default) label', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _selectMacro(tester, 'Macro 1');

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Macro 1');
  });

  testWidgets('typing a new name autosaves without pressing anything else',
      (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _selectMacro(tester, 'Macro 1');

    await tester.enterText(find.byType(TextField).first, 'Opening Wide');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect((await PresetNameStore.loadAll('roland_'))[1], 'Opening Wide');
  });

  testWidgets('submitting the field saves immediately', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _selectMacro(tester, 'Macro 1');

    await tester.enterText(find.byType(TextField).first, 'Opening Wide');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect((await PresetNameStore.loadAll('roland_'))[1], 'Opening Wide');
  });

  testWidgets('switching to another item flushes a pending rename first',
      (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _selectMacro(tester, 'Macro 1');

    await tester.enterText(find.byType(TextField).first, 'Opening Wide');
    // Switch before the debounce would have fired on its own.
    await tester.tap(find.text('Macro 2'));
    await tester.pumpAndSettle();

    expect((await PresetNameStore.loadAll('roland_'))[1], 'Opening Wide');
  });

  testWidgets('a named grid button shows "name (number)"', (tester) async {
    await PresetNameStore.save('roland_', 1, 'Opening Wide');
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    expect(find.text('Opening Wide (1)'), findsOneWidget);
    expect(find.text('Opening Wide'), findsNothing);
  });

  testWidgets(
      'the Rename caption shows "name (number)" once a name is saved',
      (tester) async {
    await PresetNameStore.save('roland_', 1, 'Opening Wide');
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _selectMacro(tester, 'Opening Wide (1)');

    expect(find.text('— Opening Wide (1)'), findsOneWidget);
  });

  group('race conditions between an in-flight save and a switch', () {
    testWidgets(
        'a rename still saving when the device is switched updates the '
        'device it was started on, not whichever device ends up selected',
        (tester) async {
      final deviceA = _GatedDevice('A', 'device_a');
      final deviceB = _GatedDevice('B', 'device_b');
      final gate = Completer<void>();
      deviceA.saveNameGate = gate;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MasterControlWidget(
            rolandService: null,
            rolandConnected: ValueNotifier(false),
            cameras: const [],
            onResponse: (_) {},
            devicesOverride: [deviceA, deviceB],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A Item 1'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Stolen');
      // Fires the debounce, which starts _saveRename() for device A. It
      // blocks inside deviceA.saveName on `gate`, so it's still in flight.
      await tester.pump(const Duration(milliseconds: 600));

      // Switch to device B while device A's save is still pending.
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      // Now let the blocked save through.
      gate.complete();
      await tester.pumpAndSettle();

      // Device B (currently shown) must not be corrupted by device A's
      // rename landing after the switch.
      expect(find.text('Stolen'), findsNothing);
      expect(find.text('B Item 1'), findsOneWidget);

      // The rename really did persist -- for device A, not device B.
      expect((await PresetNameStore.loadAll('device_a'))[1], 'Stolen');
      expect((await PresetNameStore.loadAll('device_b'))[1], isNull);
    });

    testWidgets(
        'a save that is still in flight is never overtaken by the next '
        'one for the same item -- they always run start-to-finish in order',
        (tester) async {
      final device = _GatedDevice('A', 'device_a');
      final gate = Completer<void>();
      device.saveNameGate = gate;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MasterControlWidget(
            rolandService: null,
            rolandConnected: ValueNotifier(false),
            cameras: const [],
            onResponse: (_) {},
            devicesOverride: [device],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A Item 1'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'First');
      // Fires the debounce; _saveRename() calls saveName('First'), which
      // blocks on `gate` -- still in flight.
      await tester.pump(const Duration(milliseconds: 600));
      expect(device.saveNameCalls, ['start:1:First']);

      // Submitting immediately queues a second save for the same item.
      // It must not start until the first one has fully resolved.
      await tester.enterText(find.byType(TextField).first, 'Second');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(device.saveNameCalls, ['start:1:First']);

      gate.complete();
      await tester.pumpAndSettle();

      expect(device.saveNameCalls,
          ['start:1:First', 'resolve:1:First', 'start:1:Second', 'resolve:1:Second']);
      expect((await PresetNameStore.loadAll('device_a'))[1], 'Second');
    });
  });
}

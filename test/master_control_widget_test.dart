import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/widgets/master_control_widget.dart';

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
}

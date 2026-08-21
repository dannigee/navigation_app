import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/widgets/operator_manager_dialog.dart';

Future<void> _openEditor(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => OperatorManagerDialog(
                rolandStorageKey: 'roland_',
                cameras: const [],
                onSaved: () {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add Operator'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a named macro chip shows "name (number)"', (tester) async {
    await PresetNameStore.save('roland_', 2, 'Opening Wide');
    await _openEditor(tester);

    await tester.ensureVisible(find.text('Opening Wide (M2)'));
    expect(find.text('Opening Wide (M2)'), findsOneWidget);
    expect(find.text('Opening Wide'), findsNothing);
  });

  testWidgets('an unnamed macro chip still shows its abbreviated number',
      (tester) async {
    await _openEditor(tester);

    await tester.ensureVisible(find.text('M2'));
    expect(find.text('M2'), findsOneWidget);
  });
}

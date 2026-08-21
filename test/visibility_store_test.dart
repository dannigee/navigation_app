import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/services/visibility_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('VisibilityStore — legacy value migration', () {
    testWidgets(
        'loadAll maps the old three-tier enum names to the new binary ones',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'item_visibility_roland_':
            jsonEncode({'1': 'hide', '2': 'expanded', '3': 'basic'}),
      });

      final result = await VisibilityStore.loadAll('roland_');

      expect(result[1], ItemVisibility.hidden);
      expect(result[2], ItemVisibility.visible);
      expect(result[3], ItemVisibility.visible);
    });

    testWidgets('loadAll still reads values already saved in the new format',
        (tester) async {
      await VisibilityStore.save('roland_', 5, ItemVisibility.hidden);

      final result = await VisibilityStore.loadAll('roland_');

      expect(result[5], ItemVisibility.hidden);
    });
  });

  group('VisibilityStore — change notification', () {
    testWidgets('save bumps the shared changes notifier', (tester) async {
      final before = VisibilityStore.changes.value;
      await VisibilityStore.save('roland_', 1, ItemVisibility.hidden);
      expect(VisibilityStore.changes.value, greaterThan(before));
    });
  });
}

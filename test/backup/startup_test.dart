import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/restore_journal.dart';
import 'package:navigation_app/services/backup/single_instance.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SingleInstance.releaseForTest();
  });

  group('SingleInstance', () {
    test('the first claim succeeds', () {
      expect(SingleInstance.claim(), isTrue);
    });

    test('a second claim in the same process is refused', () {
      expect(SingleInstance.claim(), isTrue);
      expect(SingleInstance.claim(), isFalse,
          reason: 'two copies racing the journal is what this prevents');
    });

    test('after release, a claim succeeds again', () {
      SingleInstance.claim();
      SingleInstance.release();
      expect(SingleInstance.claim(), isTrue);
    });
  });

  group('journal rollback', () {
    test('an interrupted apply is rolled back', () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      await RestoreJournal.capture();
      await PositionStore.saveAll([]);

      await RestoreJournal.rollbackIfPresent();

      expect((await PositionStore.loadAll()).length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RestoreJournal.key), isNull);
    });
  });

  group('main wiring', () {
    late String source;

    setUpAll(() => source = File('lib/main.dart').readAsStringSync());

    test('main rolls back the journal before runApp', () {
      expect(source.contains('RestoreJournal.rollbackIfPresent'), isTrue,
          reason: 'without this the app can start on a hybrid configuration');
      expect(source.indexOf('RestoreJournal.rollbackIfPresent'),
          lessThan(source.indexOf('runApp')),
          reason: 'it must happen before anything reads configuration');
    });

    test('main claims the single instance before runApp', () {
      expect(source.contains('SingleInstance.claim'), isTrue);
      expect(source.indexOf('SingleInstance.claim'),
          lessThan(source.indexOf('runApp')));
    });
  });
}

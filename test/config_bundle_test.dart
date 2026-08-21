import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/height_range_store.dart';
import 'package:navigation_app/services/people_store.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/services/service_store.dart';

ConfigBundle _full() => ConfigBundle(
      schemaVersion: ConfigBundle.currentSchemaVersion,
      positions: [
        Position(id: 'pos1', name: 'Lectern'),
        Position(id: 'pos2', name: 'Pulpit'),
      ],
      people: [
        Person(
          id: 'p1',
          name: 'Alice',
          heightCm: 170,
          positionPresets: {
            'pos1': {'10.0.0.1': 2},
          },
        ),
      ],
      services: [
        Service(
          id: 's1',
          name: 'Standard Mass',
          participants: [
            Participant(id: 'pt1', name: 'Reader 1'),
          ],
          steps: [
            const ServiceStep(id: 'st1', type: StepType.macro, macroNumber: 3),
            const ServiceStep(
                id: 'st2',
                type: StepType.ministry,
                participantId: 'pt1',
                positionId: 'pos1'),
          ],
        ),
      ],
      heightRanges: [
        HeightRange(
          id: 'hr1',
          maxHeightCm: 163,
          positionPresets: {
            'pos1': {'10.0.0.1': 1},
          },
        ),
        HeightRange(
          id: 'hr2',
          positionPresets: {
            'pos1': {'10.0.0.1': 5},
          },
        ),
      ],
      presetNames: {
        'roland_10.0.1.20': {'1': 'Opening Prayer', '2': 'Entrance Hymn'},
        '10.0.1.10': {'0': 'Wide Shot', '3': 'Close Up'},
      },
      visibilities: {
        'roland_10.0.1.20': {'1': 'basic', '5': 'hide'},
      },
    );

void main() {
  group('ConfigBundle — serialisation', () {
    test(
        'toJson/fromJson round-trips all collections including names and visibilities',
        () {
      final bundle = _full();
      final copy = ConfigBundle.fromJsonValidated(bundle.toJson());

      expect(copy.positions.length, 2);
      expect(copy.positions[0].name, 'Lectern');
      expect(copy.positions[1].name, 'Pulpit');

      expect(copy.people.length, 1);
      expect(copy.people[0].name, 'Alice');
      expect(copy.people[0].heightCm, 170);
      expect(copy.people[0].positionPresets['pos1']?['10.0.0.1'], 2);

      expect(copy.heightRanges.length, 2);
      expect(copy.heightRanges[0].id, 'hr1');
      expect(copy.heightRanges[0].maxHeightCm, 163);
      expect(copy.heightRanges[0].positionPresets['pos1']?['10.0.0.1'], 1);
      expect(copy.heightRanges[1].id, 'hr2');
      expect(copy.heightRanges[1].maxHeightCm, isNull);
      expect(copy.heightRanges[1].positionPresets['pos1']?['10.0.0.1'], 5);

      expect(copy.services.length, 1);
      expect(copy.services[0].name, 'Standard Mass');
      expect(copy.services[0].participants.length, 1);
      expect(copy.services[0].participants[0].name, 'Reader 1');
      expect(copy.services[0].steps.length, 2);
      expect(copy.services[0].steps[0].macroNumber, 3);
      expect(copy.services[0].steps[1].participantId, 'pt1');

      expect(copy.presetNames['roland_10.0.1.20']?['1'], 'Opening Prayer');
      expect(copy.presetNames['roland_10.0.1.20']?['2'], 'Entrance Hymn');
      expect(copy.presetNames['10.0.1.10']?['0'], 'Wide Shot');
      expect(copy.presetNames['10.0.1.10']?['3'], 'Close Up');

      expect(copy.visibilities['roland_10.0.1.20']?['1'], 'basic');
      expect(copy.visibilities['roland_10.0.1.20']?['5'], 'hide');
    });

    test('toJson uses positions, services, and heightRanges keys', () {
      const bundle = ConfigBundle(
        schemaVersion: ConfigBundle.currentSchemaVersion,
        positions: [],
        people: [],
        services: [],
      );
      final json = bundle.toJson();
      expect(json.containsKey('positions'), isTrue);
      expect(json.containsKey('services'), isTrue);
      expect(json.containsKey('heightRanges'), isTrue);
      expect(json.containsKey('roles'), isFalse);
      expect(json.containsKey('scenes'), isFalse);
      expect(json.containsKey('serviceOrders'), isFalse);
    });

    test('toJson includes presetNames and visibilities when non-empty', () {
      final bundle = _full();
      final json = bundle.toJson();
      expect(json.containsKey('presetNames'), isTrue);
      expect(json.containsKey('visibilities'), isTrue);
    });

    test('empty bundle round-trips', () {
      const bundle = ConfigBundle(
        schemaVersion: ConfigBundle.currentSchemaVersion,
        positions: [],
        people: [],
        services: [],
      );
      final copy = ConfigBundle.fromJsonValidated(bundle.toJson());
      expect(copy.positions, isEmpty);
      expect(copy.people, isEmpty);
      expect(copy.services, isEmpty);
      expect(copy.heightRanges, isEmpty);
    });
  });

  group('ConfigBundle — store integration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fromStores returns empty bundle when stores are empty', () async {
      final bundle = await ConfigBundle.fromStores();
      expect(bundle.positions, isEmpty);
      expect(bundle.people, isEmpty);
      expect(bundle.services, isEmpty);
      expect(bundle.heightRanges, isEmpty);
      expect(bundle.presetNames, isEmpty);
      expect(bundle.visibilities, isEmpty);
    });

    test(
        'applyTransactionally persists positions, people, services, and heightRanges',
        () async {
      await _full().applyTransactionally();

      final positions = await PositionStore.loadAll();
      expect(positions.length, 2);
      expect(positions[0].name, 'Lectern');

      final people = await PeopleStore.loadAll();
      expect(people.length, 1);
      expect(people[0].heightCm, 170);
      expect(people[0].positionPresets['pos1']?['10.0.0.1'], 2);

      final services = await ServiceStore.loadAll();
      expect(services.length, 1);
      expect(services[0].steps.length, 2);

      final heightRanges = await HeightRangeStore.loadAll();
      expect(heightRanges.length, 2);
      expect(heightRanges[0].id, 'hr1');
      expect(heightRanges[0].maxHeightCm, 163);
      expect(heightRanges[0].positionPresets['pos1']?['10.0.0.1'], 1);
      expect(heightRanges[1].id, 'hr2');
      expect(heightRanges[1].maxHeightCm, isNull);
    });

    test('applyTransactionally persists preset names and visibilities',
        () async {
      await _full().applyTransactionally();
      final prefs = await SharedPreferences.getInstance();

      final rolandRaw = prefs.getString('preset_names_roland_10.0.1.20');
      expect(rolandRaw, isNotNull);
      expect(rolandRaw, contains('Opening Prayer'));

      final camRaw = prefs.getString('preset_names_10.0.1.10');
      expect(camRaw, isNotNull);
      expect(camRaw, contains('Wide Shot'));

      final visRaw = prefs.getString('item_visibility_roland_10.0.1.20');
      expect(visRaw, isNotNull);
      expect(visRaw, contains('basic'));
    });

    test(
        'fromStores reads preset names and visibilities from SharedPreferences',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preset_names_10.0.1.10', '{"0":"Wide Shot"}');
      await prefs.setString('item_visibility_roland_10.0.1.20', '{"3":"hide"}');

      final bundle = await ConfigBundle.fromStores();
      expect(bundle.presetNames['10.0.1.10']?['0'], 'Wide Shot');
      expect(bundle.visibilities['roland_10.0.1.20']?['3'], 'hide');
    });

    test('fromStores reflects what applyTransactionally wrote', () async {
      await _full().applyTransactionally();
      final loaded = await ConfigBundle.fromStores();

      expect(loaded.positions.map((p) => p.id), containsAll(['pos1', 'pos2']));
      expect(loaded.people[0].name, 'Alice');
      expect(loaded.people[0].heightCm, 170);
      expect(loaded.services[0].name, 'Standard Mass');
      expect(loaded.heightRanges.length, 2);
      expect(loaded.heightRanges[0].id, 'hr1');
      expect(loaded.heightRanges[1].maxHeightCm, isNull);
      expect(loaded.presetNames['roland_10.0.1.20']?['1'], 'Opening Prayer');
      expect(loaded.presetNames['10.0.1.10']?['3'], 'Close Up');
      expect(loaded.visibilities['roland_10.0.1.20']?['5'], 'hide');
    });

    test('toJson/fromJson/applyTransactionally/fromStores full round-trip',
        () async {
      final original = _full();
      final json = original.toJson();
      final decoded = ConfigBundle.fromJsonValidated(json);
      await decoded.applyTransactionally();
      final reloaded = await ConfigBundle.fromStores();

      expect(reloaded.positions.length, original.positions.length);
      expect(reloaded.people[0].heightCm, 170);
      expect(reloaded.people[0].positionPresets['pos1']?['10.0.0.1'], 2);
      expect(reloaded.services.length, original.services.length);
      expect(reloaded.services[0].steps[0].macroNumber, 3);
      expect(reloaded.heightRanges.length, 2);
      expect(reloaded.heightRanges[0].id, 'hr1');
      expect(reloaded.heightRanges[0].positionPresets['pos1']?['10.0.0.1'], 1);
      expect(reloaded.heightRanges[1].maxHeightCm, isNull);
      expect(reloaded.presetNames['roland_10.0.1.20']?['2'], 'Entrance Hymn');
      expect(reloaded.presetNames['10.0.1.10']?['0'], 'Wide Shot');
      expect(reloaded.visibilities['roland_10.0.1.20']?['1'], 'basic');
    });
  });
}

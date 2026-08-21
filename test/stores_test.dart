import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/height_range_store.dart';
import 'package:navigation_app/services/people_store.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/services/service_store.dart';
import 'package:navigation_app/services/visibility_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PositionStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await PositionStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll returns the same positions', () async {
      final positions = [
        Position(id: '1', name: 'Lectern'),
        Position(id: '2', name: 'Pulpit'),
      ];
      await PositionStore.saveAll(positions);
      final loaded = await PositionStore.loadAll();
      expect(loaded.length, 2);
      expect(loaded[0].id, '1');
      expect(loaded[0].name, 'Lectern');
      expect(loaded[1].name, 'Pulpit');
    });

    test('overwriting with empty list clears stored positions', () async {
      await PositionStore.saveAll([Position(id: '1', name: 'Lectern')]);
      await PositionStore.saveAll([]);
      expect(await PositionStore.loadAll(), isEmpty);
    });

    test('overwrites previous save entirely', () async {
      await PositionStore.saveAll([Position(id: '1', name: 'Lectern')]);
      await PositionStore.saveAll([Position(id: '2', name: 'Pulpit')]);
      final loaded = await PositionStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].name, 'Pulpit');
    });
  });

  group('PeopleStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await PeopleStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll preserves person with positionPresets', () async {
      final person = Person(
        id: 'p1',
        name: 'Alice',
        positionPresets: {
          'pos1': {'10.0.0.1': 3, '10.0.0.2': 7},
        },
      );
      await PeopleStore.saveAll([person]);
      final loaded = await PeopleStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].name, 'Alice');
      expect(loaded[0].positionPresets['pos1']?['10.0.0.1'], 3);
      expect(loaded[0].positionPresets['pos1']?['10.0.0.2'], 7);
    });

    test('saves multiple people', () async {
      final people = [
        Person(id: 'p1', name: 'Alice'),
        Person(id: 'p2', name: 'Bob'),
      ];
      await PeopleStore.saveAll(people);
      final loaded = await PeopleStore.loadAll();
      expect(loaded.length, 2);
      expect(loaded.map((p) => p.name), containsAll(['Alice', 'Bob']));
    });
  });

  group('ServiceStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await ServiceStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll preserves service with participants and steps',
        () async {
      final service = Service(
        id: 's1',
        name: 'Standard Mass',
        participants: [
          Participant(id: 'pt1', name: 'Reader 1'),
          Participant(id: 'pt2', name: 'Priest'),
        ],
        steps: [
          const ServiceStep(
              id: 'st1', type: StepType.macro, macroNumber: 2),
          const ServiceStep(
              id: 'st2',
              type: StepType.ministry,
              participantId: 'pt1',
              positionId: 'pos1'),
          const ServiceStep(
              id: 'st3', type: StepType.block, subServiceId: 's2'),
        ],
      );
      await ServiceStore.saveAll([service]);
      final loaded = await ServiceStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].name, 'Standard Mass');
      expect(loaded[0].participants.length, 2);
      expect(loaded[0].steps.length, 3);
      expect(loaded[0].steps[0].macroNumber, 2);
      expect(loaded[0].steps[1].participantId, 'pt1');
      expect(loaded[0].steps[2].subServiceId, 's2');
    });

    test('saves multiple services', () async {
      final services = [
        Service(id: 's1', name: 'Mass'),
        Service(id: 's2', name: 'Vespers'),
      ];
      await ServiceStore.saveAll(services);
      final loaded = await ServiceStore.loadAll();
      expect(loaded.length, 2);
      expect(loaded.map((s) => s.name), containsAll(['Mass', 'Vespers']));
    });

    test('each store uses its own key (no cross-contamination)', () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Lectern')]);
      await ServiceStore.saveAll([Service(id: 's1', name: 'Mass')]);

      // loading the other store should still be unaffected
      expect(await PeopleStore.loadAll(), isEmpty);
    });
  });

  group('PresetNameStore', () {
    test('loadAll returns empty map before anything is saved', () async {
      expect(await PresetNameStore.loadAll('10.0.1.10'), isEmpty);
    });

    test('save then loadAll returns the saved name', () async {
      await PresetNameStore.save('10.0.1.10', 0, 'Wide Shot');
      final names = await PresetNameStore.loadAll('10.0.1.10');
      expect(names[0], 'Wide Shot');
    });

    test('saving empty string removes the entry', () async {
      await PresetNameStore.save('10.0.1.10', 2, 'Close Up');
      await PresetNameStore.save('10.0.1.10', 2, '');
      final names = await PresetNameStore.loadAll('10.0.1.10');
      expect(names.containsKey(2), isFalse);
    });

    test('multiple presets saved independently for same camera', () async {
      await PresetNameStore.save('10.0.1.10', 0, 'Wide');
      await PresetNameStore.save('10.0.1.10', 3, 'Tight');
      await PresetNameStore.save('10.0.1.10', 7, 'Altar');
      final names = await PresetNameStore.loadAll('10.0.1.10');
      expect(names[0], 'Wide');
      expect(names[3], 'Tight');
      expect(names[7], 'Altar');
    });

    test('different camera IPs do not share names', () async {
      await PresetNameStore.save('10.0.1.10', 0, 'Wide');
      expect(await PresetNameStore.loadAll('10.0.1.11'), isEmpty);
    });

    test('saving a name overwrites the previous value', () async {
      await PresetNameStore.save('10.0.1.10', 1, 'Old');
      await PresetNameStore.save('10.0.1.10', 1, 'New');
      expect((await PresetNameStore.loadAll('10.0.1.10'))[1], 'New');
    });

    test('Roland key is independent of camera key', () async {
      await PresetNameStore.save('roland_10.0.1.20', 5, 'Entrance');
      expect(await PresetNameStore.loadAll('10.0.1.20'), isEmpty);
      expect(
          (await PresetNameStore.loadAll('roland_10.0.1.20'))[5], 'Entrance');
    });
  });

  group('VisibilityStore', () {
    test('loadAll returns empty map before anything is saved', () async {
      expect(await VisibilityStore.loadAll('roland_10.0.1.20'), isEmpty);
    });

    test('save then loadAll returns the saved visibility', () async {
      await VisibilityStore.save(
          'roland_10.0.1.20', 1, ItemVisibility.hidden);
      final vis = await VisibilityStore.loadAll('roland_10.0.1.20');
      expect(vis[1], ItemVisibility.hidden);
    });

    test('both ItemVisibility values round-trip', () async {
      await VisibilityStore.save('10.0.1.10', 0, ItemVisibility.hidden);
      await VisibilityStore.save('10.0.1.10', 1, ItemVisibility.visible);
      final vis = await VisibilityStore.loadAll('10.0.1.10');
      expect(vis[0], ItemVisibility.hidden);
      expect(vis[1], ItemVisibility.visible);
    });

    test('saving overwrites existing visibility', () async {
      await VisibilityStore.save('10.0.1.10', 3, ItemVisibility.visible);
      await VisibilityStore.save('10.0.1.10', 3, ItemVisibility.hidden);
      expect((await VisibilityStore.loadAll('10.0.1.10'))[3],
          ItemVisibility.hidden);
    });

    test('different device keys do not share visibilities', () async {
      await VisibilityStore.save(
          'roland_10.0.1.20', 5, ItemVisibility.hidden);
      expect(await VisibilityStore.loadAll('10.0.1.10'), isEmpty);
    });
  });

  group('HeightRangeStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await HeightRangeStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll preserves bounded range with positionPresets', () async {
      final range = HeightRange(
        id: 'hr1',
        maxHeightCm: 163,
        positionPresets: {
          'pos1': {'10.0.0.1': 2, '10.0.0.2': 5},
        },
      );
      await HeightRangeStore.saveAll([range]);
      final loaded = await HeightRangeStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].id, 'hr1');
      expect(loaded[0].maxHeightCm, 163);
      expect(loaded[0].positionPresets['pos1']?['10.0.0.1'], 2);
      expect(loaded[0].positionPresets['pos1']?['10.0.0.2'], 5);
    });

    test('saveAll then loadAll preserves catch-all range (null maxHeightCm)', () async {
      final range = HeightRange(id: 'hr2');
      await HeightRangeStore.saveAll([range]);
      final loaded = await HeightRangeStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].maxHeightCm, isNull);
    });

    test('saves multiple ranges', () async {
      final ranges = [
        HeightRange(id: 'hr1', maxHeightCm: 163),
        HeightRange(id: 'hr2', maxHeightCm: 175),
        HeightRange(id: 'hr3'),
      ];
      await HeightRangeStore.saveAll(ranges);
      final loaded = await HeightRangeStore.loadAll();
      expect(loaded.length, 3);
      expect(loaded.map((r) => r.id), containsAll(['hr1', 'hr2', 'hr3']));
    });

    test('overwriting with empty list clears stored ranges', () async {
      await HeightRangeStore.saveAll([HeightRange(id: 'hr1', maxHeightCm: 163)]);
      await HeightRangeStore.saveAll([]);
      expect(await HeightRangeStore.loadAll(), isEmpty);
    });

    test('overwrites previous save entirely', () async {
      await HeightRangeStore.saveAll([HeightRange(id: 'hr1', maxHeightCm: 163)]);
      await HeightRangeStore.saveAll([HeightRange(id: 'hr2')]);
      final loaded = await HeightRangeStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].id, 'hr2');
    });

    test('HeightRangeStore uses its own key (no cross-contamination with PositionStore)', () async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Lectern')]);
      expect(await HeightRangeStore.loadAll(), isEmpty);
    });
  });
}

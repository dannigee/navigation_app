import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/config_bundle.dart';

Map<String, dynamic> valid([Map<String, dynamic> extra = const {}]) => {
      'schemaVersion': 1,
      'positions': <dynamic>[],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
      ...extra,
    };

Matcher throwsKind(BackupFailureKind k) => throwsA(
    predicate((e) => e is AppFault && e.kind == k.name, 'AppFault ${k.name}'));

void main() {
  group('version', () {
    test('a valid document parses and reports its version', () {
      expect(ConfigBundle.fromJsonValidated(valid()).schemaVersion, 1);
    });

    test('a missing schemaVersion is malformed', () {
      expect(
          () =>
              ConfigBundle.fromJsonValidated(valid()..remove('schemaVersion')),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a non-integer schemaVersion is malformed', () {
      expect(
          () => ConfigBundle.fromJsonValidated(valid({'schemaVersion': 'one'})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('schemaVersion 0 is malformed, not an implicit old schema', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'schemaVersion': 0})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a negative schemaVersion is malformed', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'schemaVersion': -1})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a newer version than this build is refused, not downgraded', () {
      expect(() => ConfigBundle.fromJsonValidated(valid({'schemaVersion': 99})),
          throwsKind(BackupFailureKind.unsupportedSchema));
    });
  });

  group('required fields', () {
    test('{} is malformed, not an empty bundle that wipes four stores', () {
      expect(() => ConfigBundle.fromJsonValidated(<String, dynamic>{}),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    for (final f in ['positions', 'people', 'services', 'heightRanges']) {
      test('missing $f is malformed', () {
        expect(() => ConfigBundle.fromJsonValidated(valid()..remove(f)),
            throwsKind(BackupFailureKind.malformedRemote));
      });

      test('$f of the wrong type is malformed', () {
        expect(() => ConfigBundle.fromJsonValidated(valid({f: 'nope'})),
            throwsKind(BackupFailureKind.malformedRemote));
      });
    }

    test('empty lists are valid — clearing everything is a legitimate edit',
        () {
      expect(ConfigBundle.fromJsonValidated(valid()).positions, isEmpty);
    });
  });

  group('optional fields', () {
    test('absent presetNames means explicitly none', () {
      expect(ConfigBundle.fromJsonValidated(valid()).presetNames, isEmpty);
    });

    test('absent visibilities means explicitly none', () {
      expect(ConfigBundle.fromJsonValidated(valid()).visibilities, isEmpty);
    });

    test('presetNames of the wrong shape is malformed, not silently empty', () {
      expect(
          () => ConfigBundle.fromJsonValidated(valid({'presetNames': 'nope'})),
          throwsKind(BackupFailureKind.malformedRemote));
    });

    test('a malformed list entry is an AppFault, not a raw TypeError', () {
      expect(
          () => ConfigBundle.fromJsonValidated(valid({
                'positions': ['nope']
              })),
          throwsKind(BackupFailureKind.malformedRemote));
    });
  });

  test('toJson stamps the current version and always emits both maps', () {
    final json = ConfigBundle.fromJsonValidated(valid()).toJson();
    expect(json['schemaVersion'], ConfigBundle.currentSchemaVersion);
    expect(json.containsKey('presetNames'), isTrue);
    expect(json.containsKey('visibilities'), isTrue);
  });

  test('a bundle round-trips through toJson and back', () {
    final original = ConfigBundle.fromJsonValidated(valid());
    final again = ConfigBundle.fromJsonValidated(original.toJson());
    expect(again.schemaVersion, original.schemaVersion);
    expect(again.positions.length, original.positions.length);
  });
}

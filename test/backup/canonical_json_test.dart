import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';

void main() {
  group('canonicalJsonEncode', () {
    test('sorts top-level keys regardless of insertion order', () {
      final a = <String, dynamic>{'b': 1, 'a': 2};
      final b = <String, dynamic>{'a': 2, 'b': 1};
      expect(canonicalJsonEncode(a), canonicalJsonEncode(b));
      expect(canonicalJsonEncode(a), '{"a":2,"b":1}');
    });

    test('sorts nested map keys too', () {
      expect(
        canonicalJsonEncode({
          'outer': {'z': 1, 'y': 2}
        }),
        canonicalJsonEncode({
          'outer': {'y': 2, 'z': 1}
        }),
      );
    });

    test('sorts maps nested inside lists', () {
      expect(
        canonicalJsonEncode({
          'items': [
            {'q': 1, 'p': 2}
          ]
        }),
        canonicalJsonEncode({
          'items': [
            {'p': 2, 'q': 1}
          ]
        }),
      );
    });

    test('preserves list order, which is meaningful', () {
      expect(
          canonicalJsonEncode({
            'l': [1, 2]
          }),
          isNot(canonicalJsonEncode({
            'l': [2, 1]
          })));
    });

    test('round-trips through jsonDecode unchanged in value', () {
      final original = <String, dynamic>{
        'b': [1, 2],
        'a': {'z': 'x'}
      };
      expect(jsonDecode(canonicalJsonEncode(original)), original);
    });
  });

  group('canonicalHash', () {
    test('is equal for equal content in different key order', () {
      expect(canonicalHash({'b': 1, 'a': 2}), canonicalHash({'a': 2, 'b': 1}));
    });

    test('differs when content differs', () {
      expect(canonicalHash({'a': 1}), isNot(canonicalHash({'a': 2})));
    });

    test('is 64 lowercase hex characters', () {
      expect(canonicalHash({'a': 1}), matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('bodyChecksumOf', () {
    test('is 32 lowercase hex characters', () {
      expect(bodyChecksumOf('{"a":1}'), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('is a function of the exact bytes, not the parsed value', () {
      expect(bodyChecksumOf('{"a":1}'), isNot(bodyChecksumOf('{"a": 1}')),
          reason: 'it mirrors a server checksum over stored bytes');
    });

    test('agrees for the canonical encoding of equal content', () {
      expect(bodyChecksumOf(canonicalJsonEncode({'b': 1, 'a': 2})),
          bodyChecksumOf(canonicalJsonEncode({'a': 2, 'b': 1})));
    });
  });
}

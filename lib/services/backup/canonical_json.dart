import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Encodes [value] to JSON with every map's keys sorted, recursively.
///
/// Two structurally equal values always produce byte-identical output, which
/// is what makes a content hash comparable across machines. `jsonEncode`
/// alone preserves insertion order, and `SharedPreferences.getKeys()` returns
/// an unordered `Set`, so bundles built on two machines from identical data
/// would otherwise hash differently and conflict forever.
String canonicalJsonEncode(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    value.forEach((k, v) => sorted['$k'] = _canonicalize(v));
    return sorted;
  }
  if (value is List) {
    // List order is meaningful — service order, position order — so it is
    // preserved. Only maps are reordered.
    return value.map(_canonicalize).toList();
  }
  return value;
}

/// Lowercase hex SHA-256 of [value]'s canonical encoding.
String canonicalHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJsonEncode(value))).toString();

/// Lowercase hex MD5 of the exact bytes of [json].
///
/// Mirrors the server-computed checksum a storage backend returns for stored
/// content. Unlike the `contentHash` this app writes into the target's own
/// metadata, a server checksum cannot go stale: it is recomputed from
/// whatever bytes are actually there, including after a hand edit in a web UI.
String bodyChecksumOf(String json) => md5.convert(utf8.encode(json)).toString();

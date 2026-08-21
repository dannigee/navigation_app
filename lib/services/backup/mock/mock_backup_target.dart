import 'dart:convert';

import '../abstract/backup_target_abstract.dart';
import '../app_fault.dart';
import '../backup_revision.dart';
import '../canonical_json.dart';

/// In-memory target for tests.
///
/// Scriptable to fail, to be slow, to have another machine write between a
/// caller's `latest()` and its `put()`, and to carry stale client metadata
/// over an honest body — each a real failure mode the engine must survive
/// and that a test could otherwise pass without exercising.
class MockBackupTarget implements BackupTargetAbstract {
  final List<BackupRevision> revisions = [];
  final Map<String, String> _bodies = {};

  AppFault? _nextFailure;
  Duration? _nextDelay;
  Map<String, String?>? _pendingConcurrentWrite;
  int _seq = 0;
  DateTime _clock = DateTime.utc(2026, 1, 1);

  /// The next call to any method throws [fault], once.
  void failNextWith(AppFault fault) => _nextFailure = fault;

  /// The next call to any method takes [d] before returning, once.
  void delayNextBy(Duration d) => _nextDelay = d;

  /// Moves the mock's clock forward, so retention can actually age things out.
  void advanceClock(Duration d) => _clock = _clock.add(d);

  /// Replace a revision's client-supplied [contentHash] with a lie, leaving
  /// its server [bodyChecksum] honest — what a hand edit in a web UI does.
  void corruptMetadataOf(String id, {required String contentHash}) {
    final i = revisions.indexWhere((r) => r.id == id);
    if (i >= 0) revisions[i] = revisions[i].copyWith(contentHash: contentHash);
  }

  /// Insert a revision by another writer immediately before the next [put],
  /// reproducing the time-of-check/time-of-use race no compare-and-swap can
  /// prevent on Drive.
  void concurrentWriterBeforePut({
    required String body,
    required String? parentRevisionId,
    required String deviceLabel,
  }) {
    _pendingConcurrentWrite = {
      'body': body,
      'parentRevisionId': parentRevisionId,
      'deviceLabel': deviceLabel,
    };
  }

  Future<void> _gate() async {
    final d = _nextDelay;
    if (d != null) {
      _nextDelay = null;
      await Future<void>.delayed(d);
    }
    final f = _nextFailure;
    if (f != null) {
      _nextFailure = null;
      throw f;
    }
  }

  BackupRevision _insert(
    String json,
    String contentHash,
    String? parentRevisionId,
    String deviceLabel,
  ) {
    final id = 'rev-${++_seq}';
    _clock = _clock.add(const Duration(seconds: 1));
    final rev = BackupRevision(
      id: id,
      filename: 'nav_config_${_clock.toIso8601String()}.json',
      createdAt: _clock,
      contentHash: contentHash,
      bodyChecksum: bodyChecksumOf(json),
      parentRevisionId: parentRevisionId,
      sizeBytes: utf8.encode(json).length,
      deviceLabel: deviceLabel,
    );
    revisions.add(rev);
    _bodies[id] = json;
    return rev;
  }

  List<BackupRevision> _ordered() {
    return [...revisions]..sort((a, b) {
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
  }

  @override
  Future<BackupRevision> put(
    String json, {
    required String contentHash,
    required String? parentRevisionId,
    required String deviceLabel,
  }) async {
    await _gate();
    final pending = _pendingConcurrentWrite;
    if (pending != null) {
      _pendingConcurrentWrite = null;
      _insert(pending['body']!, 'h-theirs', pending['parentRevisionId'],
          pending['deviceLabel']!);
    }
    return _insert(json, contentHash, parentRevisionId, deviceLabel);
  }

  @override
  Future<BackupRevision?> latest() async {
    await _gate();
    if (revisions.isEmpty) return null;
    return _ordered().first;
  }

  @override
  Future<List<BackupRevision>> list({int limit = 50}) async {
    await _gate();
    if (limit < 0) {
      throw AppFault.backup(
          BackupFailureKind.unknown, 'limit must not be negative');
    }
    return _ordered().take(limit).toList();
  }

  @override
  Future<String> fetch(BackupRevision revision) async {
    await _gate();
    final body = _bodies[revision.id];
    if (body == null) {
      throw AppFault.backup(
          BackupFailureKind.targetMissing, 'revision ${revision.id} is gone');
    }
    return body;
  }

  @override
  Future<void> prune({
    required int keepCount,
    required Duration keepFor,
  }) async {
    await _gate();
    if (keepCount < 0) {
      throw AppFault.backup(
          BackupFailureKind.unknown, 'keepCount must not be negative');
    }
    final ordered = _ordered();
    final cutoff = _clock.subtract(keepFor);
    for (var i = keepCount; i < ordered.length; i++) {
      final r = ordered[i];
      if (r.createdAt.isBefore(cutoff)) {
        revisions.remove(r);
        _bodies.remove(r.id);
      }
    }
  }
}

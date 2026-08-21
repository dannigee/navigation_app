import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_revision.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';

void main() {
  late MockBackupTarget target;

  setUp(() => target = MockBackupTarget());

  Future<BackupRevision> put(String body,
          {String? parent, String label = 'Mac mini'}) =>
      target.put(body,
          contentHash: 'h-$body',
          parentRevisionId: parent,
          deviceLabel: label);

  test('latest returns null when empty', () async {
    expect(await target.latest(), isNull);
  });

  test('put stores a revision and latest returns it', () async {
    final rev = await put('{"a":1}');
    final latest = await target.latest();
    expect(latest!.id, rev.id);
    expect(latest.deviceLabel, 'Mac mini');
    expect(latest.parentRevisionId, isNull);
  });

  test('bodyChecksum is computed from the stored bytes, not supplied', () async {
    final rev = await put('{"a":1}');
    expect(rev.bodyChecksum, bodyChecksumOf('{"a":1}'));
  });

  test('sizeBytes counts stored UTF-8 bytes', () async {
    const body = '{"name":"Beyoncé"}';
    final rev = await put(body);

    expect(rev.sizeBytes, utf8.encode(body).length);
    expect(rev.sizeBytes, isNot(body.length));
  });

  test('put never overwrites: two puts make two revisions', () async {
    final a = await put('{"a":1}');
    final b = await put('{"a":2}', parent: a.id);
    expect(a.id, isNot(b.id));
    expect((await target.list()).length, 2);
  });

  test('list is newest first', () async {
    final a = await put('{"a":1}');
    final b = await put('{"a":2}', parent: a.id);
    expect((await target.list()).map((r) => r.id).toList(), [b.id, a.id]);
  });

  test('fetch returns the exact body that was put', () async {
    final rev = await put('{"a":1}');
    expect(await target.fetch(rev), '{"a":1}');
  });

  test('failNextWith makes exactly the next call throw', () async {
    target.failNextWith(
        AppFault.backup(BackupFailureKind.offline, 'no network'));
    await expectLater(target.latest(), throwsA(isA<AppFault>()));
    expect(await target.latest(), isNull, reason: 'only the next call fails');
  });

  test('concurrentWriterBeforePut simulates another machine winning the race',
      () async {
    final base = await put('{"a":1}');
    target.concurrentWriterBeforePut(
        body: '{"a":9}', parentRevisionId: base.id, deviceLabel: 'iPad');

    final mine = await put('{"a":2}', parent: base.id);

    final siblings = (await target.list())
        .where((r) => r.parentRevisionId == base.id)
        .toList();
    expect(siblings.length, 2, reason: 'a fork now exists');
    expect(siblings.map((r) => r.id), contains(mine.id));
  });

  test('corruptMetadataOf makes contentHash lie while bodyChecksum stays true',
      () async {
    final rev = await put('{"a":1}');
    target.corruptMetadataOf(rev.id, contentHash: 'a-stale-lie');

    final latest = await target.latest();
    expect(latest!.contentHash, 'a-stale-lie');
    expect(latest.bodyChecksum, bodyChecksumOf('{"a":1}'),
        reason: 'a server checksum cannot go stale; client metadata can');
  });

  test('delayNextBy makes the next call slow, so ordering can be observed',
      () async {
    target.delayNextBy(const Duration(milliseconds: 60));
    final started = DateTime.now();
    await target.latest();
    expect(DateTime.now().difference(started).inMilliseconds,
        greaterThanOrEqualTo(50));
  });

  test('list rejects a negative limit with a backup AppFault', () async {
    await expectLater(
      target.list(limit: -1),
      throwsA(isA<AppFault>()
          .having((fault) => fault.domain, 'domain', FaultDomain.backup)
          .having((fault) => fault.kind, 'kind', BackupFailureKind.unknown.name)),
    );
  });

  group('prune', () {
    test('rejects a negative keepCount with a backup AppFault', () async {
      await expectLater(
        target.prune(keepCount: -1, keepFor: const Duration(days: 90)),
        throwsA(isA<AppFault>()
            .having((fault) => fault.domain, 'domain', FaultDomain.backup)
            .having(
                (fault) => fault.kind, 'kind', BackupFailureKind.unknown.name)),
      );
    });

    test('keeps a revision beyond keepCount when it is not yet old', () async {
      for (var i = 0; i < 5; i++) {
        await put('{"a":$i}');
      }
      await target.prune(keepCount: 2, keepFor: const Duration(days: 90));
      expect((await target.list()).length, 5,
          reason: 'deletion needs BOTH beyond count AND older than keepFor');
    });

    test('keeps an old revision that is still within keepCount', () async {
      for (var i = 0; i < 3; i++) {
        await put('{"a":$i}');
      }
      target.advanceClock(const Duration(days: 365));
      await target.prune(keepCount: 10, keepFor: const Duration(days: 90));
      expect((await target.list()).length, 3);
    });

    test('deletes only revisions that are BOTH beyond count AND old',
        () async {
      for (var i = 0; i < 5; i++) {
        await put('{"a":$i}');
      }
      target.advanceClock(const Duration(days: 365));
      await target.prune(keepCount: 2, keepFor: const Duration(days: 90));
      expect((await target.list()).length, 2,
          reason: 'the three oldest are beyond count and old, so they go');
    });
  });
}

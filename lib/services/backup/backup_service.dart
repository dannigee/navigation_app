import 'dart:async';

import 'abstract/backup_target_abstract.dart';
import 'backup_pointer.dart';
import 'backup_revision.dart';
import 'canonical_json.dart';
import 'config_mutation_notifier.dart';

enum PushOutcome { noOp, uploaded, conflict, forked }

class PushResult {
  final PushOutcome outcome;
  final BackupRevision? revision;
  final BackupRevision? remoteRevision;
  final List<BackupRevision>? siblings;

  const PushResult(this.outcome,
      {this.revision, this.remoteRevision, this.siblings});
}

/// Owns the backup protocol.
///
/// Every operation runs through one single-flight queue. Pulls, debounced
/// pushes, periodic sweeps, manual retries and the backoff timer are
/// otherwise independent callers of the same mutable state, and an older
/// operation completing after a newer one would overwrite status or
/// provenance.
class BackupService {
  final BackupTargetAbstract target;
  final String targetIdentity;
  final Future<String> Function() deviceLabel;
  final Future<Map<String, dynamic>> Function() readBundleJson;

  /// Whether local configuration is untouched — nothing worth protecting.
  /// Only consulted when the pointer is null.
  final Future<bool> Function() localIsPristine;

  Future<void> _queue = Future<void>.value();

  BackupService({
    required this.target,
    required this.targetIdentity,
    required this.deviceLabel,
    required this.readBundleJson,
    required this.localIsPristine,
  });

  /// Serializes [action] behind every operation already queued.
  Future<T> _single<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<BackupPointer> _pointer() async {
    final p = await BackupPointer.load();
    return p.matchesTarget(targetIdentity) ? p : const BackupPointer();
  }

  Future<PushResult> push() => _single(_push);

  Future<PushResult> _push() async {
    final generation = await ConfigMutationNotifier.instance.generation();
    final bundle = await readBundleJson();
    final json = canonicalJsonEncode(bundle);
    final hash = canonicalHash(bundle);
    final localChecksum = bodyChecksumOf(json);

    final head = await target.latest();
    final pointer = await _pointer();

    // 1. The bytes are already there. Judged by the SERVER checksum: the
    //    contentHash we wrote is client metadata and goes stale if the file
    //    is edited by hand at the target.
    if (head != null && head.bodyChecksum == localChecksum) {
      if (pointer.revisionId != head.id) {
        await BackupPointer.save(
          revisionId: head.id,
          recordedHash: hash,
          targetIdentity: targetIdentity,
        );
      }
      await ConfigMutationNotifier.instance.markSynced(generation);
      return const PushResult(PushOutcome.noOp);
    }

    // 2. Remote moved since we last synced.
    if (head != null && head.id != pointer.revisionId) {
      return PushResult(PushOutcome.conflict, remoteRevision: head);
    }

    // 3. Upload, recording where we branched from.
    final revision = await target.put(
      json,
      contentHash: hash,
      parentRevisionId: pointer.revisionId,
      deviceLabel: await deviceLabel(),
    );

    await BackupPointer.save(
      revisionId: revision.id,
      recordedHash: hash,
      targetIdentity: targetIdentity,
    );
    await ConfigMutationNotifier.instance.markSynced(generation);

    // 4. Fork check. No compare-and-swap exists, so a second writer can pass
    //    step 2 concurrently. Both bodies survive; say so rather than pretend
    //    the race did not happen.
    final recent = await target.list(limit: 10);
    final siblings = recent
        .where((r) =>
            r.id != revision.id &&
            r.parentRevisionId == revision.parentRevisionId)
        .toList();
    if (siblings.isNotEmpty) {
      return PushResult(PushOutcome.forked,
          revision: revision, siblings: siblings);
    }

    return PushResult(PushOutcome.uploaded, revision: revision);
  }
}

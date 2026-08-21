import 'dart:async';
import 'dart:convert';

import '../config_bundle.dart';
import 'abstract/backup_target_abstract.dart';
import 'app_fault.dart';
import 'backup_pointer.dart';
import 'backup_revision.dart';
import 'canonical_json.dart';
import 'config_mutation_notifier.dart';

enum PullOutcome {
  nothingToDo,
  adopted,
  applied,
  rebased,
  conflict,
  targetEmptied,
  needsAdoptionChoice,
}

class PullResult {
  final PullOutcome outcome;
  final BackupRevision? revision;
  const PullResult(this.outcome, {this.revision});
}

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
  static const _backoff = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

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

  /// How long to wait before retrying after [fault], or null when retrying
  /// cannot help.
  ///
  /// The schedule never terminates. A loop that exhausts its attempts and
  /// stops is a silent failure with extra steps: the pill would sit red
  /// forever with nothing trying to clear it.
  static Duration? nextRetryDelay(AppFault fault, int attempt) {
    if (!fault.isRetryable) return null;
    if (fault.sweepOnly) return const Duration(minutes: 10);
    final i = attempt.clamp(0, _backoff.length - 1).toInt();
    return _backoff[i];
  }

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

  Future<PullResult> pull() =>
      _single(() => _withStorageBoundary('pull', _pull));

  Future<PullResult> _pull() async {
    // 1. Metadata only. A pointer from another target is meaningless.
    final head = await target.latest();
    final pointer = await _pointer();

    // 2. Remote empty.
    if (head == null) {
      if (!pointer.isProvenanced) {
        return const PullResult(PullOutcome.nothingToDo);
      }
      await BackupPointer.clear();
      return const PullResult(PullOutcome.targetEmptied);
    }

    final localGeneration = await ConfigMutationNotifier.instance.generation();
    final localBundle = await readBundleJson();
    final localJson = canonicalJsonEncode(localBundle);
    final localHash = canonicalHash(localBundle);
    final localChecksum = bodyChecksumOf(localJson);

    // 3. Unprovenanced. Never auto-apply over local data.
    if (!pointer.isProvenanced) {
      if (!await localIsPristine()) {
        return PullResult(PullOutcome.needsAdoptionChoice, revision: head);
      }
      final applied = await _applyRevision(
        head,
        expectedLocalHash: localHash,
        expectedGeneration: localGeneration,
      );
      return PullResult(
        applied ? PullOutcome.adopted : PullOutcome.needsAdoptionChoice,
        revision: head,
      );
    }

    // 4. Remote has not moved.
    if (head.id == pointer.revisionId) {
      return const PullResult(PullOutcome.nothingToDo);
    }

    // 5. Equivalent content under another id. Judged by the SERVER checksum:
    //    the contentHash at the target is client-written and goes stale if
    //    someone edits the file by hand.
    if (head.bodyChecksum == localChecksum) {
      await BackupPointer.save(
        revisionId: head.id,
        recordedHash: localHash,
        targetIdentity: targetIdentity,
      );
      return PullResult(PullOutcome.rebased, revision: head);
    }

    // 6. Linear descendant, and local unchanged. The ancestry test is
    //    load-bearing: "clean" compares local against its OWN pointer and
    //    says nothing about whether remote descends from it.
    if (head.parentRevisionId == pointer.revisionId &&
        pointer.isCleanAgainst(localHash)) {
      final applied = await _applyRevision(
        head,
        expectedLocalHash: localHash,
        expectedGeneration: localGeneration,
      );
      return PullResult(
        applied ? PullOutcome.applied : PullOutcome.conflict,
        revision: head,
      );
    }

    // 7. Diverged, or local is dirty. Surface it; never a modal.
    return PullResult(PullOutcome.conflict, revision: head);
  }

  Future<bool> _applyRevision(
    BackupRevision revision, {
    required String expectedLocalHash,
    required int expectedGeneration,
  }) async {
    final raw = await target.fetch(revision);

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw AppFault.backup(
        BackupFailureKind.malformedRemote,
        'revision ${revision.id} is not valid JSON',
        operation: 'pull',
        targetIdentity: targetIdentity,
        cause: e,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AppFault.backup(
        BackupFailureKind.malformedRemote,
        'revision ${revision.id} is not a JSON object',
        operation: 'pull',
        targetIdentity: targetIdentity,
      );
    }

    // Throws AppFault on anything malformed, before a single store is touched.
    final bundle = ConfigBundle.fromJsonValidated(decoded);
    final currentGeneration =
        await ConfigMutationNotifier.instance.generation();
    final currentLocalHash = canonicalHash(await readBundleJson());
    if (currentGeneration != expectedGeneration ||
        currentLocalHash != expectedLocalHash) {
      return false;
    }
    await bundle.applyTransactionally(markAsPending: false);

    // applyTransactionally deliberately clears the pointer, because an import
    // is unprovenanced. Applying a fetched revision is the one case where we
    // know exactly what it came from, so re-establish it here.
    await BackupPointer.save(
      revisionId: revision.id,
      recordedHash: canonicalHash(decoded),
      targetIdentity: targetIdentity,
    );
    await ConfigMutationNotifier.instance.markSynced(expectedGeneration);
    return true;
  }

  Future<PushResult> push() =>
      _single(() => _withStorageBoundary('push', _push));

  Future<PushResult> _push() async {
    final generation = await ConfigMutationNotifier.instance.generation();
    final bundle = await readBundleJson();
    final json = canonicalJsonEncode(bundle);
    final hash = canonicalHash(bundle);
    final localChecksum = bodyChecksumOf(json);

    final head = await target.latest();
    final pointer = await _pointer();

    if (head == null && pointer.isProvenanced) {
      await BackupPointer.clear();
      throw AppFault.backup(
        BackupFailureKind.targetMissing,
        'The backup revision this device last synced no longer exists.',
        operation: 'push',
        targetIdentity: targetIdentity,
      );
    }

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

  Future<T> _withStorageBoundary<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on AppFault {
      rethrow;
    } on StateError catch (error) {
      throw AppFault.backup(
        BackupFailureKind.storageWriteFailed,
        'Could not persist backup state during $operation.',
        operation: operation,
        targetIdentity: targetIdentity,
        cause: error,
      );
    }
  }
}

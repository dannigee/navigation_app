import '../backup_revision.dart';

/// Append-only revision storage.
///
/// Every method throws `AppFault` and nothing else; implementations translate
/// their own exceptions at this boundary.
abstract class BackupTargetAbstract {
  /// Uploads a new immutable revision. Never overwrites an existing one.
  Future<BackupRevision> put(
    String json, {
    required String contentHash,
    required String? parentRevisionId,
    required String deviceLabel,
  });

  /// Newest revision's metadata, or null when the store is empty.
  /// Must not download the body.
  Future<BackupRevision?> latest();

  /// Revisions, newest first.
  Future<List<BackupRevision>> list({int limit = 50});

  /// Downloads a revision's body.
  Future<String> fetch(BackupRevision revision);

  /// Deletes revisions that are BOTH outside the newest [keepCount] AND
  /// older than [keepFor]. Either condition alone is not enough.
  Future<void> prune({required int keepCount, required Duration keepFor});
}

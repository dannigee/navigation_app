import 'package:shared_preferences/shared_preferences.dart';

/// Which revision the local configuration came from.
///
/// Stored beside the target identity: a pointer captured against one storage
/// folder or account says nothing about another, and comparing across them
/// would produce confident nonsense.
class BackupPointer {
  static const String revisionKey = 'backup_source_revision';
  static const String hashKey = 'backup_source_hash';
  static const String targetKey = 'backup_target_identity';

  final String? revisionId;
  final String? recordedHash;
  final String? targetIdentity;

  const BackupPointer(
      {this.revisionId, this.recordedHash, this.targetIdentity});

  bool get isProvenanced => revisionId != null;

  bool matchesTarget(String identity) => targetIdentity == identity;

  /// Whether local content is unchanged since this pointer was recorded.
  ///
  /// An unprovenanced pointer is never clean. Without that guard a fresh
  /// install compares null to null, reads as clean, and a pull would
  /// auto-apply over local state it knows nothing about.
  bool isCleanAgainst(String localHash) =>
      isProvenanced && recordedHash == localHash;

  static Future<BackupPointer> load() async {
    final prefs = await SharedPreferences.getInstance();
    return BackupPointer(
      revisionId: prefs.getString(revisionKey),
      recordedHash: prefs.getString(hashKey),
      targetIdentity: prefs.getString(targetKey),
    );
  }

  static Future<void> save({
    required String revisionId,
    required String recordedHash,
    required String targetIdentity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _requirePersisted(
        prefs.setString(revisionKey, revisionId), prefs, 'revision');
    await _requirePersisted(
        prefs.setString(hashKey, recordedHash), prefs, 'content hash');
    await _requirePersisted(
        prefs.setString(targetKey, targetIdentity), prefs, 'target identity');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [revisionKey, hashKey, targetKey]) {
      if (!await prefs.remove(key)) {
        await prefs.reload();
        throw StateError('Could not clear backup provenance');
      }
    }
  }

  static Future<void> _requirePersisted(
    Future<bool> write,
    SharedPreferences prefs,
    String field,
  ) async {
    if (!await write) {
      await prefs.reload();
      throw StateError('Could not persist backup provenance $field');
    }
  }
}

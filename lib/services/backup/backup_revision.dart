/// Immutable metadata for one stored revision.
class BackupRevision {
  /// Storage-assigned id. On Drive, the file id.
  final String id;
  final String filename;

  /// Server time where the target has one. Never the client's clock: a
  /// machine with a wrong clock would otherwise choose the wrong head.
  final DateTime createdAt;

  /// SHA-256 of the canonical body, written by the client into the target's
  /// own metadata. **Not trustworthy on its own** — it is not recomputed when
  /// the body changes, so a hand edit in a storage web UI leaves it stale.
  final String contentHash;

  /// Checksum computed by the *server* over the stored bytes. Cannot go
  /// stale. This is what the engine compares against to decide whether local
  /// content already exists at the target.
  final String bodyChecksum;

  /// The revision this one was edited from. Null for the first revision.
  /// Makes fork detection and the pull ancestry test possible.
  final String? parentRevisionId;

  final int sizeBytes;

  /// Self-declared machine name. A usability aid for the conflict UI, not an
  /// audit trail.
  final String deviceLabel;

  const BackupRevision({
    required this.id,
    required this.filename,
    required this.createdAt,
    required this.contentHash,
    required this.bodyChecksum,
    required this.parentRevisionId,
    required this.sizeBytes,
    required this.deviceLabel,
  });

  BackupRevision copyWith({String? contentHash}) => BackupRevision(
        id: id,
        filename: filename,
        createdAt: createdAt,
        contentHash: contentHash ?? this.contentHash,
        bodyChecksum: bodyChecksum,
        parentRevisionId: parentRevisionId,
        sizeBytes: sizeBytes,
        deviceLabel: deviceLabel,
      );
}

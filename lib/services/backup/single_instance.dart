import 'dart:io';

/// Refuses a second copy of the app.
///
/// Two instances share `SharedPreferences` through its cached API: one would
/// read stale values and both could race the restore journal, which is the
/// premise the journal's atomicity rests on. Refusing is far cheaper than
/// defining reload semantics for that.
class SingleInstance {
  static RandomAccessFile? _held;
  static bool _claimedInProcess = false;

  /// Attempts to become the only running instance. Returns false if another
  /// instance already holds the lock.
  static bool claim() {
    if (_claimedInProcess) return false;
    RandomAccessFile? raf;
    try {
      final file = File('${Directory.systemTemp.path}/navigation_app.lock');
      raf = file.openSync(mode: FileMode.write);
      raf.lockSync(FileLock.exclusive);
      _held = raf;
      _claimedInProcess = true;
      return true;
    } on FileSystemException {
      try {
        raf?.closeSync();
      } on FileSystemException {
        // Lock acquisition already failed; there is nothing further to claim.
      }
      return false;
    }
  }

  static void release() {
    try {
      _held?.unlockSync();
      _held?.closeSync();
    } on FileSystemException {
      // Already gone; nothing to do.
    }
    _held = null;
    _claimedInProcess = false;
  }

  /// Test seam: releases the actual lock and clears in-process state.
  static void releaseForTest() {
    release();
  }
}

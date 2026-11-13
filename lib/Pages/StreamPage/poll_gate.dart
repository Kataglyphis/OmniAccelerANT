/// Lets one poll run at a time: `/healthz` may take 8 s to fail, longer than any interval a page asks at.
class PollGate {
  bool _busy = false;

  /// Runs [poll] unless the one before still waits for its answer.
  Future<void> run(Future<void> Function() poll) async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      await poll();
    } finally {
      _busy = false;
    }
  }
}

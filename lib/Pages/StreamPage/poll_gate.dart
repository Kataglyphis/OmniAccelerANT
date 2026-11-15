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

/// The wait before the next poll: [base] while it answers and for the first three misses in a row, then doubling up
/// to [ceiling], so a page with nothing behind it, as the hosted site has, asks about once a minute.
Duration backoffDelay(
  Duration base,
  int misses, {
  Duration ceiling = const Duration(minutes: 1),
}) {
  if (misses <= 3) {
    return base;
  }
  final grown = base * (1 << (misses - 3).clamp(0, 10));
  return grown < ceiling ? grown : ceiling;
}

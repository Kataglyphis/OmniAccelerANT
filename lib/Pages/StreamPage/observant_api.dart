/// ObservANT's answer to a POST: its status and body.
typedef ObservantReply = ({int status, String body});

/// What a page asks of ObservANT; the web and the native file each implement it, so the analyzer holds them in step.
abstract interface class ObservantApi {
  /// ObservANT's `/healthz`.
  Future<String?> fetchHealthz();

  /// The body of a GET to [url] on another ObservANT, which lets this page read it (`peers`).
  Future<String?> fetchFrom(String url);

  /// ObservANT's `/visits`: the last 30 days' visits, read when the statistics open.
  Future<String?> fetchVisits();

  /// ObservANT's `/settings`.
  Future<String?> fetchObservantSettings();

  /// Changes the values in [update] on ObservANT; JSON, as it takes no other body.
  Future<bool> saveObservantSettings(Map<String, Object> update);

  /// POSTs [body] to [path] and returns the answer whatever its status; `null` when none came or [cancel] ended it.
  Future<ObservantReply?> postToObservant(
    String path,
    Map<String, Object> body, {
    Future<void>? cancel,
  });
}

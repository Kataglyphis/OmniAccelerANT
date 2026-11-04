import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// How long a request may take: one on a socket that died unnoticed would otherwise wait for minutes.
const int _timeoutMs = 8000;

/// The body of a GET to [path] on the page's own origin, ObservANT; `null` when nothing answers it.
Future<String?> _get(String path) async {
  try {
    final response = await web.window
        .fetch(
          path.toJS,
          web.RequestInit(signal: web.AbortSignal.timeout(_timeoutMs)),
        )
        .toDart;
    if (!response.ok) {
      return null;
    }
    return (await response.text().toDart).toDart;
  } on Object {
    return null;
  }
}

/// The body of a GET to [url] on another ObservANT, which lets this page read it (`peers`).
Future<String?> fetchFrom(String url) => _get(url);

/// ObservANT's `/healthz`.
Future<String?> fetchHealthz() => _get('/healthz');

/// ObservANT's `/visits`: the last 30 days' visits, read when the statistics open.
Future<String?> fetchVisits() => _get('/visits');

/// ObservANT's `/settings`.
Future<String?> fetchObservantSettings() => _get('/settings');

/// ObservANT's answer to a POST: its status and body.
typedef ObservantReply = ({int status, String body});

/// Longer than ObservANT's own 300 s, so its answer to a slow model arrives before this gives up.
const Duration _modelTimeout = Duration(seconds: 310);

/// POSTs [body] to [path] and returns the answer whatever its status; `null` when none came or [cancel] ended it.
Future<ObservantReply?> postToObservant(
  String path,
  Map<String, Object> body, {
  Future<void>? cancel,
}) async {
  final abort = web.AbortController();
  final timer = Timer(_modelTimeout, () => abort.abort());
  unawaited(cancel?.then((_) => abort.abort()));
  try {
    final response = await web.window
        .fetch(
          path.toJS,
          web.RequestInit(
            signal: abort.signal,
            method: 'POST',
            headers:
                <String, String>{'content-type': 'application/json'}.jsify()
                    as web.HeadersInit,
            body: jsonEncode(body).toJS,
          ),
        )
        .toDart;
    return (
      status: response.status,
      body: (await response.text().toDart).toDart,
    );
  } on Object {
    return null;
  } finally {
    timer.cancel();
  }
}

/// Changes the values in [update] on ObservANT; JSON, as it takes no other body.
Future<bool> saveObservantSettings(Map<String, Object> update) async {
  try {
    final response = await web.window
        .fetch(
          '/settings'.toJS,
          web.RequestInit(
            signal: web.AbortSignal.timeout(_timeoutMs),
            method: 'POST',
            headers:
                <String, String>{'content-type': 'application/json'}.jsify()
                    as web.HeadersInit,
            body: jsonEncode(update).toJS,
          ),
        )
        .toDart;
    return response.ok;
  } on Object {
    return false;
  }
}

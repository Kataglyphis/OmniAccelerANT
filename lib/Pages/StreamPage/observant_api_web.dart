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

/// ObservANT's `/settings`.
Future<String?> fetchObservantSettings() => _get('/settings');

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

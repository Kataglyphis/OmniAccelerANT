import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The body of a GET to [path] on the page's own origin, the cat cam; `null` when nothing answers it.
Future<String?> _get(String path) async {
  try {
    final response = await web.window.fetch(path.toJS).toDart;
    if (!response.ok) {
      return null;
    }
    return (await response.text().toDart).toDart;
  } on Object {
    return null;
  }
}

/// The cat cam's `/healthz`.
Future<String?> fetchHealthz() => _get('/healthz');

/// The cat cam's `/settings`.
Future<String?> fetchCatCamSettings() => _get('/settings');

/// Changes the values in [update] on the cat cam; JSON, as it takes no other body.
Future<bool> saveCatCamSettings(Map<String, Object> update) async {
  try {
    final response = await web.window
        .fetch(
          '/settings'.toJS,
          web.RequestInit(
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

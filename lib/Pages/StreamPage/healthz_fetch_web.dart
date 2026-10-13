import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The cat cam's `/settings`, or `null` when nothing answers it.
Future<String?> fetchCatCamSettings() async {
  try {
    final response = await web.window.fetch('/settings'.toJS).toDart;
    if (!response.ok) {
      return null;
    }
    return (await response.text().toDart).toDart;
  } on Object {
    return null;
  }
}

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

/// The cat cam's `/healthz` from the page's own origin; `null` when nothing answers it.
Future<String?> fetchHealthz() async {
  try {
    final response = await web.window.fetch('/healthz'.toJS).toDart;
    if (!response.ok) {
      return null;
    }
    return (await response.text().toDart).toDart;
  } on Object {
    return null;
  }
}

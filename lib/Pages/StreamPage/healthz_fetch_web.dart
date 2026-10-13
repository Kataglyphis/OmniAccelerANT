import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Turns the cat cam's picture to [degrees] clockwise; JSON, as the cat cam takes no other body.
Future<bool> rotateCatCam(int degrees) async {
  try {
    final response = await web.window
        .fetch(
          '/rotate'.toJS,
          web.RequestInit(
            method: 'POST',
            headers:
                <String, String>{'content-type': 'application/json'}.jsify()
                    as web.HeadersInit,
            body: '{"rotate": $degrees}'.toJS,
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

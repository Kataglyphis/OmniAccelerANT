import 'dart:js_interop';

import 'package:web/web.dart' as web;

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

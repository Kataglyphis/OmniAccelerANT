import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:omni_accelerant/Pages/StreamPage/observant_api.dart';

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

/// The web build's side: ObservANT is the origin that served the page.
ObservantApi createObservantApi() => const _WebObservant();

class _WebObservant implements ObservantApi {
  const _WebObservant();

  @override
  Future<String?> fetchFrom(String url) => _get(url);

  @override
  Future<String?> fetchHealthz() => _get('/healthz');

  @override
  Future<String?> fetchVisits() => _get('/visits');

  @override
  Future<String?> fetchObservantSettings() => _get('/settings');

  @override
  Future<bool> saveObservantSettings(Map<String, Object> update) =>
      _save(update);

  @override
  Future<ObservantReply?> postToObservant(
    String path,
    Map<String, Object> body, {
    Future<void>? cancel,
  }) => _post(path, body, cancel: cancel);
}

/// Longer than ObservANT's own 300 s, so its answer to a slow model arrives before this gives up.
const Duration _modelTimeout = Duration(seconds: 310);

Future<ObservantReply?> _post(
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

Future<bool> _save(Map<String, Object> update) async {
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

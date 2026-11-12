import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

/// One request the page made: its URL and what it passed with it.
typedef FetchRequest = ({String url, web.RequestInit? init});

/// Replaces the page's `fetch` for one test: [answer] makes each response, and its failure is the request's.
List<FetchRequest> fakeFetchWith(
  Future<web.Response> Function(FetchRequest request) answer,
) {
  final requests = <FetchRequest>[];
  final JSAny? real = globalContext.getProperty('fetch'.toJS);
  JSPromise<web.Response> fake(JSString url, web.RequestInit? init) {
    final request = (url: url.toDart, init: init);
    requests.add(request);
    return answer(request).toJS;
  }

  globalContext.setProperty('fetch'.toJS, fake.toJS);
  addTearDown(() => globalContext.setProperty('fetch'.toJS, real));
  return requests;
}

/// [fakeFetchWith] for answers that depend on the URL alone; `null` is a network failure.
List<FetchRequest> fakeFetch(web.Response? Function(String url) answer) =>
    fakeFetchWith(
      (request) async =>
          answer(request.url) ?? (throw StateError('network down')),
    );

/// A response with [body] and [status].
web.Response respond(String body, {int status = 200}) =>
    web.Response(body.toJS, web.ResponseInit(status: status));

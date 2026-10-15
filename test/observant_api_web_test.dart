@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:omni_accelerant/Pages/StreamPage/observant_api_web.dart';

/// One request the page made: its URL and what it passed with it.
typedef _Request = ({String url, web.RequestInit? init});

/// Replaces the page's `fetch` for one test: [answer] makes each response, `null` a network failure.
List<_Request> _fakeFetch(web.Response? Function(String url) answer) {
  final requests = <_Request>[];
  final JSAny? real = globalContext.getProperty('fetch'.toJS);
  JSPromise<web.Response> fake(JSString url, web.RequestInit? init) {
    requests.add((url: url.toDart, init: init));
    final web.Response? response = answer(url.toDart);
    return (response == null
            ? Future<web.Response>.error(StateError('network down'))
            : Future<web.Response>.value(response))
        .toJS;
  }

  globalContext.setProperty('fetch'.toJS, fake.toJS);
  addTearDown(() => globalContext.setProperty('fetch'.toJS, real));
  return requests;
}

web.Response _respond(String body, {int status = 200}) =>
    web.Response(body.toJS, web.ResponseInit(status: status));

void main() {
  test('healthz and settings are GETs on the page\'s own origin', () async {
    final requests = _fakeFetch((url) => _respond('{"from":"$url"}'));
    expect(await fetchHealthz(), '{"from":"/healthz"}');
    expect(await fetchObservantSettings(), '{"from":"/settings"}');
    expect(requests.map((r) => r.url), ['/healthz', '/settings']);
    // Every request carries a timeout, so a dead socket cannot hold the page.
    expect(requests.every((r) => r.init?.signal != null), isTrue);
  });

  test('a peer is read at its own URL', () async {
    final requests = _fakeFetch((url) => _respond('peer'));
    expect(await fetchFrom('http://192.168.1.20:8080/healthz'), 'peer');
    expect(requests.single.url, 'http://192.168.1.20:8080/healthz');
  });

  test('an error status or a failed request reads as nothing', () async {
    _fakeFetch((url) => _respond('busy', status: 503));
    expect(await fetchHealthz(), isNull);
    _fakeFetch((url) => null);
    expect(await fetchHealthz(), isNull);
    expect(await fetchFrom('http://10.0.0.9:8080/healthz'), isNull);
  });

  test(
    'saving POSTs the changed values as JSON and reports the answer',
    () async {
      final requests = _fakeFetch((url) => _respond(''));
      expect(
        await saveObservantSettings(<String, Object>{
          'name': 'Futtertrog',
          'rotate': 90,
        }),
        isTrue,
      );
      final web.RequestInit init = requests.single.init!;
      expect(requests.single.url, '/settings');
      expect(init.method, 'POST');
      final JSString type = init.headers.getProperty('content-type'.toJS);
      expect(type.toDart, 'application/json');
      expect(jsonDecode((init.body! as JSString).toDart), {
        'name': 'Futtertrog',
        'rotate': 90,
      });
      _fakeFetch((url) => _respond('no', status: 400));
      expect(
        await saveObservantSettings(<String, Object>{'rotate': 45}),
        isFalse,
      );
      _fakeFetch((url) => null);
      expect(
        await saveObservantSettings(<String, Object>{'rotate': 90}),
        isFalse,
      );
    },
  );
}

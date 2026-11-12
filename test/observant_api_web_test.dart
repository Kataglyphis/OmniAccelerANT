@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:omni_accelerant/Pages/StreamPage/observant_api_web.dart';

import 'support/fake_fetch.dart';

void main() {
  test('healthz and settings are GETs on the page\'s own origin', () async {
    final requests = fakeFetch((url) => respond('{"from":"$url"}'));
    expect(await fetchHealthz(), '{"from":"/healthz"}');
    expect(await fetchObservantSettings(), '{"from":"/settings"}');
    expect(requests.map((r) => r.url), ['/healthz', '/settings']);
    // Every request carries a timeout, so a dead socket cannot hold the page.
    expect(requests.every((r) => r.init?.signal != null), isTrue);
  });

  test('a peer is read at its own URL', () async {
    final requests = fakeFetch((url) => respond('peer'));
    expect(await fetchFrom('http://192.168.1.20:8080/healthz'), 'peer');
    expect(requests.single.url, 'http://192.168.1.20:8080/healthz');
  });

  test('an error status or a failed request reads as nothing', () async {
    fakeFetch((url) => respond('busy', status: 503));
    expect(await fetchHealthz(), isNull);
    fakeFetch((url) => null);
    expect(await fetchHealthz(), isNull);
    expect(await fetchFrom('http://10.0.0.9:8080/healthz'), isNull);
  });

  test(
    'saving POSTs the changed values as JSON and reports the answer',
    () async {
      final requests = fakeFetch((url) => respond(''));
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
      fakeFetch((url) => respond('no', status: 400));
      expect(
        await saveObservantSettings(<String, Object>{'rotate': 45}),
        isFalse,
      );
      fakeFetch((url) => null);
      expect(
        await saveObservantSettings(<String, Object>{'rotate': 90}),
        isFalse,
      );
    },
  );

  test('a question is a JSON POST whose answer keeps its status', () async {
    final requests = fakeFetch(
      (url) => respond('no language model', status: 503),
    );
    final reply = await postToObservant('/ask', <String, Object>{
      'question': 'hi',
    });
    expect(reply?.status, 503);
    expect(reply?.body, 'no language model');
    expect(requests.single.url, '/ask');
    expect(requests.single.init?.method, 'POST');
    expect(requests.single.init?.body?.dartify(), '{"question":"hi"}');
  });

  test('a question with no reply is null, not an answer', () async {
    fakeFetch((_) => null);
    expect(
      await postToObservant('/ask', <String, Object>{'question': 'hi'}),
      isNull,
    );
  });

  test('a cancelled question aborts its request', () async {
    final requests = fakeFetch((_) => respond('{}'));
    final cancel = Completer<void>()..complete();
    await postToObservant('/ask', <String, Object>{
      'question': 'hi',
    }, cancel: cancel.future);
    await Future<void>.delayed(Duration.zero);
    expect(requests.single.init?.signal?.aborted, isTrue);
  });
}

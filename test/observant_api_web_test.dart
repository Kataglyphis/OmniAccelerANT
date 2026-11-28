@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:omni_accelerant/Pages/StreamPage/observant_api.dart';
import 'package:omni_accelerant/Pages/StreamPage/observant_api_web.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_access.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_observant.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_platform_web.dart';

import 'support/fake_fetch.dart';

void main() {
  final ObservantApi api = createObservantApi();
  test('healthz and settings are GETs on the page\'s own origin', () async {
    final requests = fakeFetch((url) => respond('{"from":"$url"}'));
    expect(await api.fetchHealthz(), '{"from":"/healthz"}');
    expect(await api.fetchObservantSettings(), '{"from":"/settings"}');
    expect(requests.map((r) => r.url), ['/healthz', '/settings']);
    // Every request carries a timeout, so a dead socket cannot hold the page.
    expect(requests.every((r) => r.init?.signal != null), isTrue);
  });

  test('a peer is read at its own URL', () async {
    final requests = fakeFetch((url) => respond('peer'));
    expect(await api.fetchFrom('http://192.168.1.20:8080/healthz'), 'peer');
    expect(requests.single.url, 'http://192.168.1.20:8080/healthz');
  });

  test('an error status or a failed request reads as nothing', () async {
    fakeFetch((url) => respond('busy', status: 503));
    expect(await api.fetchHealthz(), isNull);
    fakeFetch((url) => null);
    expect(await api.fetchHealthz(), isNull);
    expect(await api.fetchFrom('http://10.0.0.9:8080/healthz'), isNull);
  });

  test(
    'saving POSTs the changed values as JSON and reports the answer',
    () async {
      final requests = fakeFetch((url) => respond(''));
      expect(
        await api.saveObservantSettings(<String, Object>{
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
        await api.saveObservantSettings(<String, Object>{'rotate': 45}),
        isFalse,
      );
      fakeFetch((url) => null);
      expect(
        await api.saveObservantSettings(<String, Object>{'rotate': 90}),
        isFalse,
      );
    },
  );

  test('a question is a JSON POST whose answer keeps its status', () async {
    final requests = fakeFetch(
      (url) => respond('no language model', status: 503),
    );
    final reply = await api.postToObservant('/ask', <String, Object>{
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
      await api.postToObservant('/ask', <String, Object>{'question': 'hi'}),
      isNull,
    );
  });

  test('a cancelled question aborts its request', () async {
    final requests = fakeFetch((_) => respond('{}'));
    final cancel = Completer<void>()..complete();
    await api.postToObservant('/ask', <String, Object>{
      'question': 'hi',
    }, cancel: cancel.future);
    await Future<void>.delayed(Duration.zero);
    expect(requests.single.init?.signal?.aborted, isTrue);
  });

  group('an explicit ObservANT address', () {
    tearDown(() => remoteObservant.setAddress(''));

    test('carries every request and stays in local storage', () async {
      final requests = fakeFetch(
        (url) => respond('{"ok":true,"name":"Futtertrog","from":"$url"}'),
      );
      await remoteObservant.setAddress('http://192.0.2.10:8080/');
      expect(remoteObservant.status, isA<ObservantConnected>());
      expect(
        web.window.localStorage.getItem(observantAddressKey),
        'http://192.0.2.10:8080',
      );
      await api.fetchHealthz();
      await api.fetchVisits();
      await api.postToObservant('/ask', <String, Object>{'question': 'hi'});
      expect(requests.map((r) => r.url), [
        'http://192.0.2.10:8080/healthz',
        'http://192.0.2.10:8080/healthz',
        'http://192.0.2.10:8080/visits',
        'http://192.0.2.10:8080/ask',
      ]);
      expect(
        observantUrl('/arrival.jpg?t=1'),
        'http://192.0.2.10:8080/arrival.jpg?t=1',
      );
      // A peer keeps its own address.
      await api.fetchFrom('http://192.168.1.20:8080/healthz');
      expect(requests.last.url, 'http://192.168.1.20:8080/healthz');
    });

    test('cleared, the page asks its own origin again', () async {
      fakeFetch((url) => respond('{"ok":true}'));
      await remoteObservant.setAddress('http://192.0.2.10:8080');
      await remoteObservant.setAddress('');
      expect(web.window.localStorage.getItem(observantAddressKey), isNull);
      final requests = fakeFetch((url) => respond(''));
      await api.fetchHealthz();
      expect(requests.single.url, '/healthz');
    });
  });

  group('the browser probe', () {
    const platform = WebRemoteObservantPlatform();
    final url = Uri.parse('http://192.0.2.10:8080/healthz');

    test('keeps an answer\'s status and body', () async {
      final requests = fakeFetch((_) => respond('forbidden', status: 403));
      final result = await platform.probe(url, const Duration(seconds: 1));
      expect((result as ProbeAnswer).status, 403);
      expect(result.body, 'forbidden');
      expect(requests.single.url, url.toString());
      expect(requests.single.init?.cache, 'no-store');
    });

    test('tells a rejected request from one that timed out', () async {
      fakeFetch((_) => null);
      expect(
        await platform.probe(url, const Duration(seconds: 1)),
        isA<ProbeNetworkError>(),
      );
      fakeFetchWith((request) {
        final aborted = Completer<web.Response>();
        request.init!.signal!.addEventListener(
          'abort',
          ((web.Event _) => aborted.completeError(StateError('aborted'))).toJS,
        );
        return aborted.future;
      });
      expect(
        await platform.probe(url, const Duration(milliseconds: 50)),
        isA<ProbeTimeout>(),
      );
    });

    test('asks the newest permission name first, then the first one Chrome shipped', () {
      expect(localNetworkPermissionNames(AddressSpace.loopback), [
        'loopback-network',
        'local-network-access',
      ]);
      expect(localNetworkPermissionNames(AddressSpace.local), [
        'local-network',
        'local-network-access',
      ]);
    });
  });
}

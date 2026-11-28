// The remote mode's connection status against a fake browser: each refusal and failure has its own typed error.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/observant_address.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_access.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_observant.dart';

import 'support/fake_remote_browser.dart';

const String _hosted = 'https://app.example.org/app/';

ObservantConnectionError? _error(RemoteObservantController c) =>
    switch (c.status) {
      ObservantFailed(:final error) => error,
      _ => null,
    };

void main() {
  test('without an address the page asks its own origin, by path', () async {
    final browser = FakeRemoteBrowser();
    final c = RemoteObservantController(browser);
    expect(c.origin, isNull);
    expect(c.status, isA<ObservantOwnOrigin>());
    expect(c.resolve('/healthz'), '/healthz');
    await c.check();
    expect(browser.probed, isEmpty);
  });

  test(
    'a valid address is saved, every path resolves against it, and it connects',
    () async {
      final browser = FakeRemoteBrowser();
      final c = RemoteObservantController(browser);
      await c.setAddress(' http://192.168.1.20:8080/ ');
      expect(browser.saved, 'http://192.168.1.20:8080');
      expect(c.resolve('/visits'), 'http://192.168.1.20:8080/visits');
      expect(
        c.resolve('/arrival.jpg?t=1'),
        'http://192.168.1.20:8080/arrival.jpg?t=1',
      );
      expect(
        browser.probed.single.toString(),
        'http://192.168.1.20:8080/healthz',
      );
      expect(c.status, isA<ObservantConnected>());
      final connected = c.status as ObservantConnected;
      expect(connected.name, 'Futtertrog');
      expect(connected.version, '2.3.4');
      // A loopback page asks nothing about the local network.
      expect(browser.asked, isEmpty);
    },
  );

  test(
    'a saved address comes back on the next visit; a broken one is dropped',
    () {
      expect(
        RemoteObservantController(
          FakeRemoteBrowser(saved: 'http://192.168.1.20:8080'),
        ).origin.toString(),
        'http://192.168.1.20:8080',
      );
      final browser = FakeRemoteBrowser(
        saved: 'http://192.168.1.20:8080/healthz',
      );
      expect(RemoteObservantController(browser).origin, isNull);
      expect(browser.saved, isNull);
    },
  );

  test(
    'an invalid address is refused with its problem and changes nothing else',
    () async {
      final browser = FakeRemoteBrowser(saved: 'http://192.168.1.20:8080');
      final c = RemoteObservantController(browser);
      await c.setAddress('catcam.local:8080');
      expect(
        (_error(c)! as InvalidObservantAddress).problem,
        ObservantAddressProblem.scheme,
      );
      expect(browser.saved, 'http://192.168.1.20:8080');
      expect(c.origin.toString(), 'http://192.168.1.20:8080');
      expect(browser.probed, isEmpty);
    },
  );

  test('clearing the field forgets the address', () async {
    final browser = FakeRemoteBrowser(saved: 'http://192.168.1.20:8080');
    final c = RemoteObservantController(browser);
    await c.setAddress('');
    expect(browser.saved, isNull);
    expect(c.origin, isNull);
    expect(c.status, isA<ObservantOwnOrigin>());
  });

  test(
    'an https page refuses an http address as mixed content, unsent',
    () async {
      final browser = FakeRemoteBrowser(page: _hosted);
      final c = RemoteObservantController(browser);
      await c.setAddress('http://192.168.1.20:8080');
      expect(_error(c), isA<MixedContentBlocked>());
      expect(browser.probed, isEmpty);
      expect(browser.asked, isEmpty);
      // The address stays saved: opening the app over http makes it work.
      expect(browser.saved, 'http://192.168.1.20:8080');
    },
  );

  test(
    'a refused local-network permission stops the request before it is sent',
    () async {
      final browser = FakeRemoteBrowser(page: _hosted)
        ..permissions = [LocalNetworkPermission.denied];
      final c = RemoteObservantController(browser);
      await c.setAddress('https://192.168.1.20:8444');
      expect((_error(c)! as LocalNetworkRefused).space, AddressSpace.local);
      expect(browser.asked, [AddressSpace.local]);
      expect(browser.probed, isEmpty);
    },
  );

  test(
    'a "Block" in the prompt reads as refused, not as unreachable',
    () async {
      final browser = FakeRemoteBrowser(page: _hosted)
        ..permissions = [
          LocalNetworkPermission.prompt,
          LocalNetworkPermission.denied,
        ]
        ..answer = (_) async => const ProbeNetworkError();
      final c = RemoteObservantController(
        browser,
        promptTimeout: const Duration(seconds: 42),
      );
      await c.setAddress('http://127.0.0.1:8080');
      expect((_error(c)! as LocalNetworkRefused).space, AddressSpace.loopback);
      expect(browser.asked, [AddressSpace.loopback, AddressSpace.loopback]);
      // The probe waits as long as the prompt may stay open.
      expect(browser.timeouts.single, const Duration(seconds: 42));
    },
  );

  test('while the prompt is open the status says so', () async {
    final answer = Completer<ProbeResult>();
    final browser = FakeRemoteBrowser(page: _hosted)
      ..permissions = [LocalNetworkPermission.prompt]
      ..answer = (_) => answer.future;
    final c = RemoteObservantController(browser);
    final done = c.setAddress('https://catcam.local:8444');
    await Future<void>.delayed(Duration.zero);
    expect((c.status as ObservantChecking).prompting, isTrue);
    answer.complete(const ProbeAnswer(200, fakeHealthz));
    await done;
    expect(c.status, isA<ObservantConnected>());
  });

  test('a granted permission connects with the ordinary timeout', () async {
    final browser = FakeRemoteBrowser(page: _hosted)
      ..permissions = [LocalNetworkPermission.granted];
    final c = RemoteObservantController(
      browser,
      timeout: const Duration(seconds: 3),
    );
    await c.setAddress('https://192.168.1.20:8444');
    expect(c.status, isA<ObservantConnected>());
    expect(browser.timeouts.single, const Duration(seconds: 3));
  });

  test('a failed request without a refusal is unreachable, with the prompt as one cause where it applies', () async {
    final lan = FakeRemoteBrowser()
      ..answer = (_) async => const ProbeNetworkError();
    final c = RemoteObservantController(lan);
    await c.setAddress('http://192.168.1.20:8080');
    expect((_error(c)! as ObservantUnreachable).localNetwork, isFalse);

    final hosted = FakeRemoteBrowser(page: _hosted)
      ..permissions = [LocalNetworkPermission.unsupported]
      ..answer = (_) async => const ProbeNetworkError();
    final d = RemoteObservantController(hosted);
    await d.setAddress('https://cam.example.org');
    expect((_error(d)! as ObservantUnreachable).localNetwork, isTrue);
    expect(hosted.asked, [AddressSpace.unknown, AddressSpace.unknown]);
  });

  test(
    'a timeout, an error status and a stranger each have their own error',
    () async {
      final browser = FakeRemoteBrowser()
        ..answer = (_) async => const ProbeTimeout();
      final c = RemoteObservantController(browser);
      await c.setAddress('http://192.168.1.20:8080');
      expect(_error(c), isA<ObservantTimedOut>());

      browser.answer = (_) async => const ProbeAnswer(
        403,
        "this host name is not the ObservANT's own; add it to allowed_hosts\n",
      );
      await c.check();
      final refused = _error(c)! as ObservantRefused;
      expect(refused.status, 403);
      expect(
        refused.body,
        "this host name is not the ObservANT's own; add it to allowed_hosts",
      );

      browser.answer = (_) async => const ProbeAnswer(200, '<!doctype html>');
      await c.check();
      expect(_error(c), isA<NotAnObservant>());
    },
  );

  test('an answer for an older address never overwrites a newer one', () async {
    final slow = Completer<ProbeResult>();
    final browser = FakeRemoteBrowser()
      ..answer = (url) => url.host == '10.0.0.9'
          ? slow.future
          : Future<ProbeResult>.value(const ProbeAnswer(200, fakeHealthz));
    final c = RemoteObservantController(browser);
    final first = c.setAddress('http://10.0.0.9:8080');
    await c.setAddress('http://192.168.1.20:8080');
    slow.complete(const ProbeAnswer(503, 'busy'));
    await first;
    expect(c.status, isA<ObservantConnected>());
    expect(c.origin.toString(), 'http://192.168.1.20:8080');
  });
}

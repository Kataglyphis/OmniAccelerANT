// The decisions the browser makes for a request to an explicit ObservANT: mixed content and Local Network Access.
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_access.dart';

RemoteAccess _decide(String page, String target) =>
    decideRemoteAccess(page: Uri.parse(page), target: Uri.parse(target));

const String _hosted = 'https://app.example.org/app/';

void main() {
  test('IP literals are placed by their ranges', () {
    for (final host in ['127.0.0.1', '127.8.9.1', '0.0.0.0', '::1']) {
      expect(addressSpaceOf(host), AddressSpace.loopback, reason: host);
    }
    for (final host in [
      '10.0.0.9',
      '172.16.0.5',
      '172.31.255.1',
      '192.168.1.20',
      '169.254.10.1',
      '100.64.0.1',
      'fd00::1',
      'fe80::1',
      '::ffff:10.0.0.9',
    ]) {
      expect(addressSpaceOf(host), AddressSpace.local, reason: host);
    }
    for (final host in [
      '192.0.2.10',
      '198.51.100.7',
      '203.0.113.1',
      '172.32.0.1',
      '100.128.0.1',
      '2001:db8::1',
      '::ffff:192.0.2.10',
    ]) {
      expect(addressSpaceOf(host), AddressSpace.public, reason: host);
    }
  });

  test('names are placed by their form, the rest only DNS can place', () {
    expect(addressSpaceOf('localhost'), AddressSpace.loopback);
    expect(addressSpaceOf('cam.localhost'), AddressSpace.loopback);
    for (final host in [
      'catcam',
      'catcam.local',
      'catcam.lan',
      'catcam.home.arpa',
      'catcam.fritz.box',
      'CatCam.Internal',
    ]) {
      expect(addressSpaceOf(host), AddressSpace.local, reason: host);
    }
    expect(addressSpaceOf('cam.example.org'), AddressSpace.unknown);
    expect(addressSpaceOf('999.1.1.1'), AddressSpace.unknown);
  });

  test('an https page to an http address is mixed content, loopback aside', () {
    expect(_decide(_hosted, 'http://192.168.1.20:8080').mixedContent, isTrue);
    expect(_decide(_hosted, 'http://catcam.local:8080').mixedContent, isTrue);
    expect(_decide(_hosted, 'http://cam.example.org').mixedContent, isTrue);
    // Browsers trust http on loopback, so only Local Network Access stands in the way.
    expect(_decide(_hosted, 'http://127.0.0.1:8080').mixedContent, isFalse);
    expect(_decide(_hosted, 'http://localhost:8080').mixedContent, isFalse);
    expect(_decide(_hosted, 'http://[::1]:8080').mixedContent, isFalse);
    expect(_decide(_hosted, 'https://catcam.local:8444').mixedContent, isFalse);
  });

  test('an http page has no mixed content', () {
    expect(
      _decide(
        'http://127.0.0.1:8000/',
        'http://192.168.1.20:8080',
      ).mixedContent,
      isFalse,
    );
    expect(
      _decide('http://192.168.1.5/', 'http://192.168.1.20:8080').mixedContent,
      isFalse,
    );
  });

  test(
    'a public page asks before it reaches the local network or loopback',
    () {
      final RemoteAccess lan = _decide(_hosted, 'https://192.168.1.20:8444');
      expect(lan.pageSpace, AddressSpace.public);
      expect(lan.targetSpace, AddressSpace.local);
      expect(lan.localNetwork, LocalNetworkAccess.prompt);
      expect(
        _decide(_hosted, 'http://127.0.0.1:8080').localNetwork,
        LocalNetworkAccess.prompt,
      );
      expect(
        _decide(_hosted, 'https://catcam.local:8444').localNetwork,
        LocalNetworkAccess.prompt,
      );
      // A public address is no more private than the page.
      expect(
        _decide(_hosted, 'https://203.0.113.1').localNetwork,
        LocalNetworkAccess.notNeeded,
      );
    },
  );

  test('a name only DNS can place may ask, unless the page is loopback', () {
    expect(
      _decide(_hosted, 'https://cam.example.org').localNetwork,
      LocalNetworkAccess.possible,
    );
    expect(
      _decide('http://localhost:8000/', 'https://cam.example.org').localNetwork,
      LocalNetworkAccess.notNeeded,
    );
  });

  test('a page in the network asks only for loopback', () {
    const String lanPage = 'http://192.168.1.5:8080/';
    expect(
      _decide(lanPage, 'http://192.168.1.20:8080').localNetwork,
      LocalNetworkAccess.notNeeded,
    );
    expect(
      _decide(lanPage, 'http://127.0.0.1:8080').localNetwork,
      LocalNetworkAccess.prompt,
    );
    expect(
      _decide('http://catcam:8080/', 'http://10.0.0.9:8080').localNetwork,
      LocalNetworkAccess.notNeeded,
    );
  });

  test('a loopback page never asks', () {
    for (final target in [
      'http://192.168.1.20:8080',
      'http://127.0.0.1:9000',
      'https://203.0.113.1',
    ]) {
      expect(
        _decide('http://127.0.0.1:8000/', target).localNetwork,
        LocalNetworkAccess.notNeeded,
        reason: target,
      );
    }
  });
}

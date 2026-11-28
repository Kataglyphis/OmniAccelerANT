// The explicit ObservANT address: what the field takes, how it is normalised, and why it refuses the rest.
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/observant_address.dart';

String? _origin(String text) => switch (checkObservantAddress(text)) {
  ObservantAddressValid(:final origin) => origin.toString(),
  _ => null,
};

ObservantAddressProblem? _problem(String text) =>
    switch (checkObservantAddress(text)) {
      ObservantAddressInvalid(:final problem) => problem,
      _ => null,
    };

void main() {
  test('an empty field means the page\'s own ObservANT', () {
    expect(checkObservantAddress(''), isA<ObservantAddressEmpty>());
    expect(checkObservantAddress('   '), isA<ObservantAddressEmpty>());
  });

  test('an origin comes back normalised, without a default port', () {
    expect(_origin('http://192.0.2.10:8080'), 'http://192.0.2.10:8080');
    expect(_origin('  HTTPS://CatCam.Local/  '), 'https://catcam.local');
    expect(_origin('http://catcam.local:80'), 'http://catcam.local');
    expect(_origin('https://catcam.local:443/'), 'https://catcam.local');
    expect(_origin('https://catcam.local:8444'), 'https://catcam.local:8444');
    expect(_origin('http://localhost:8080'), 'http://localhost:8080');
    expect(_origin('http://[::1]:8080'), 'http://[::1]:8080');
  });

  test(
    'a host without http:// or https:// is refused, as is any other scheme',
    () {
      for (final text in [
        '192.0.2.10:8080',
        'catcam.local:8080',
        'catcam',
        'ws://192.0.2.10:8080',
        'file:///etc/hosts',
        'javascript:alert(1)',
      ]) {
        expect(_problem(text), ObservantAddressProblem.scheme, reason: text);
      }
    },
  );

  test('a scheme alone has no host', () {
    expect(_problem('http://'), ObservantAddressProblem.noHost);
    expect(_problem('https:///healthz'), ObservantAddressProblem.noHost);
  });

  test('a host no browser would look up is not an address', () {
    expect(_problem('http://cat cam.local'), ObservantAddressProblem.notUrl);
    expect(_problem('http://kätzchen.local'), ObservantAddressProblem.notUrl);
    expect(_problem('http://[::1'), ObservantAddressProblem.notUrl);
  });

  test('credentials, paths, queries and fragments are refused', () {
    expect(
      _problem('http://user:secret@192.0.2.10:8080'),
      ObservantAddressProblem.credentials,
    );
    for (final text in [
      'http://192.0.2.10:8080/healthz',
      'http://192.0.2.10:8080/?x=1',
      'http://192.0.2.10:8080/#/stream',
    ]) {
      expect(_problem(text), ObservantAddressProblem.path, reason: text);
    }
  });

  test('a port outside 1 to 65535 is refused', () {
    expect(_problem('http://192.0.2.10:0'), ObservantAddressProblem.port);
    expect(_problem('http://192.0.2.10:65536'), ObservantAddressProblem.port);
    expect(_origin('http://192.0.2.10:65535'), 'http://192.0.2.10:65535');
  });
}

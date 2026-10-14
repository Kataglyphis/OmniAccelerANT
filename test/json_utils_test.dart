import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/utils/json_utils.dart';

void main() {
  test('a JSON object decodes to its map', () {
    expect(decodeJsonObject('{"ok":true,"name":"Büro"}'), {
      'ok': true,
      'name': 'Büro',
    });
  });

  test('no body, malformed JSON and any other JSON value are null', () {
    for (final body in <String?>[
      null,
      '',
      'not json',
      '<!doctype html>',
      '[1, 2]',
      '"text"',
      '42',
      'null',
    ]) {
      expect(decodeJsonObject(body), isNull, reason: body);
    }
  });

  test('fetchOrNull passes an answer on and turns a throw into null', () async {
    expect(await fetchOrNull(() async => '{"ok":true}'), '{"ok":true}');
    expect(await fetchOrNull(() async => null), isNull);
    expect(await fetchOrNull(() async => throw StateError('offline')), isNull);
  });
}

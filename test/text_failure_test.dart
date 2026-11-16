// The bridge's `kind: text` failures as the playground shows them, in both languages.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_failure.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/l10n/app_localizations_de.dart';
import 'package:omni_accelerant/l10n/app_localizations_en.dart';

void main() {
  final de = AppLocalizationsDe();
  final en = AppLocalizationsEn();

  test('a known kind reads as its sentence, the detail kept behind it', () {
    expect(
      describeTextFailure(
        'model_load_failed: the model directory could not be loaded: no genai_config.json',
        de,
      ),
      'Das Modell ließ sich nicht laden; bitte den Modellordner prüfen. '
      '(the model directory could not be loaded: no genai_config.json)',
    );
    expect(
      describeTextFailure(
        'endpoint_status: the endpoint answered HTTP 503: busy',
        en,
      ),
      'The server did not answer properly; check its address and that it runs. '
      '(the endpoint answered HTTP 503: busy)',
    );
    expect(
      describeTextFailure(
        'endpoint_timed_out: the endpoint did not answer in time: timeout: per read',
        de,
      ),
      'Der Server hat zu lange für die Antwort gebraucht; bitte erneut oder kürzer fragen. '
      '(the endpoint did not answer in time: timeout: per read)',
    );
    expect(
      describeTextFailure(
        'invalid_options: the messages or options are invalid: x',
        en,
      ),
      startsWith('The request was refused'),
    );
  });

  test('an unknown kind or a failure without one keeps the raw text', () {
    expect(
      describeTextFailure('no_such_kind: out of memory', en),
      'The model failed: no_such_kind: out of memory',
    );
    expect(
      describeTextFailure('socket closed', en),
      'The model failed: socket closed',
    );
  });

  test('every kind OxidANT names has a sentence in both languages', () {
    // The kinds as OxidANT's TextError::kind spells them, at the pin: a new kind fails here until it has a string.
    final source = File('third_party/OxidANT/crates/text/src/lib.rs')
        .readAsStringSync();
    final body = source.substring(source.indexOf('pub fn kind(&self)'));
    final kinds = RegExp(r'Self::\w+(?:\([^)]*\))? => "([a-z_]+)"')
        .allMatches(body.substring(0, body.indexOf('\n    }\n')))
        .map((match) => match.group(1)!)
        .toList();
    expect(kinds, hasLength(greaterThanOrEqualTo(14)));
    for (final kind in kinds) {
      for (final l10n in <AppLocalizations>[de, en]) {
        final failure = '$kind: detail';
        expect(
          describeTextFailure(failure, l10n),
          isNot(l10n.aiError(failure)),
          reason: '$kind has no sentence in ${l10n.localeName}',
        );
      }
    }
  }, testOn: 'vm');
}

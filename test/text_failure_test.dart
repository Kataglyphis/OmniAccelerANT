// The bridge's typed failures as the playground shows them, in both languages.
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_failure.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/l10n/app_localizations_de.dart';
import 'package:omni_accelerant/l10n/app_localizations_en.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

TextFailure _failure(TextFailureKind kind, String message, [int? status]) =>
    TextFailure(kind: kind, message: message, httpStatus: status);

void main() {
  final de = AppLocalizationsDe();
  final en = AppLocalizationsEn();

  test('a kind reads as its sentence, the detail kept behind it', () {
    expect(
      describeTextFailure(
        _failure(
          TextFailureKind.modelLoadFailed,
          'the model directory could not be loaded: no genai_config.json',
        ),
        de,
      ),
      'Das Modell ließ sich nicht laden; bitte den Modellordner prüfen. '
      '(the model directory could not be loaded: no genai_config.json)',
    );
    expect(
      describeTextFailure(
        _failure(
          TextFailureKind.endpointStatus,
          'the endpoint answered HTTP 503: busy',
          503,
        ),
        en,
      ),
      'The server did not answer properly; check its address and that it runs. '
      '(the endpoint answered HTTP 503: busy)',
    );
    expect(
      describeTextFailure(
        _failure(
          TextFailureKind.endpointTimedOut,
          'the endpoint did not answer in time: timeout: per read',
        ),
        de,
      ),
      'Der Server hat zu lange für die Antwort gebraucht; bitte erneut oder kürzer fragen. '
      '(the endpoint did not answer in time: timeout: per read)',
    );
  });

  test('a reply without words has its own sentence in both languages', () {
    final noAnswer = _failure(
      TextFailureKind.noAnswer,
      'the model gave no answer (finish_reason length)',
    );
    expect(
      describeTextFailure(noAnswer, en),
      'The model gave no answer; ask again or put the question differently. '
      '(the model gave no answer (finish_reason length))',
    );
    expect(
      describeTextFailure(noAnswer, de),
      startsWith('Das Modell hat keine Antwort gegeben'),
    );
  });

  test('every kind has a sentence of its own in both languages', () {
    for (final l10n in <AppLocalizations>[de, en]) {
      for (final kind in TextFailureKind.values) {
        expect(
          describeTextFailure(_failure(kind, 'detail'), l10n),
          isNot(l10n.aiError('detail')),
          reason: '$kind in ${l10n.localeName}',
        );
      }
    }
  });
}

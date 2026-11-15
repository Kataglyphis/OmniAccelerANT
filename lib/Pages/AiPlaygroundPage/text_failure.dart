import 'package:omni_accelerant/l10n/app_localizations.dart';

final RegExp _kinded = RegExp(r'^([a-z_]+): (.*)$', dotAll: true);

/// The bridge's `kind: text` failure (OxidANT's `TextError::kind`) as a sentence; an unknown kind keeps the raw text.
String describeTextFailure(String error, AppLocalizations l10n) {
  final match = _kinded.firstMatch(error);
  if (match == null) {
    return l10n.aiError(error);
  }
  final detail = match.group(2)!;
  return switch (match.group(1)) {
    'model_load_failed' => l10n.aiErrorModelLoad(detail),
    'library_unavailable' => l10n.aiErrorLibrary(detail),
    'provider_unavailable' => l10n.aiErrorProvider(detail),
    'endpoint_unreachable' || 'endpoint_status' => l10n.aiErrorEndpoint(detail),
    'endpoint_timed_out' => l10n.aiErrorTimedOut(detail),
    'invalid_options' => l10n.aiErrorInvalid(detail),
    _ => l10n.aiError(error),
  };
}

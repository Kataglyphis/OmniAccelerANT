import 'package:flutter/material.dart';

/// Checks if the current locale is German.
bool isGermanLocale(BuildContext context) {
  return Localizations.localeOf(context) == const Locale('de');
}

/// Checks if the current locale is English.
bool isEnglishLocale(BuildContext context) {
  return Localizations.localeOf(context) == const Locale('en');
}

/// [de] under a German locale, else [en].
T localizedValue<T>(BuildContext context, {required T de, required T en}) {
  return isGermanLocale(context) ? de : en;
}

import 'package:flutter/material.dart';

/// Checks if the current locale is German, whatever its country (de, de_AT, de_CH).
bool isGermanLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'de';
}

/// [de] under a German locale, else [en].
T localizedValue<T>(BuildContext context, {required T de, required T en}) {
  return isGermanLocale(context) ? de : en;
}

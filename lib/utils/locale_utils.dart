import 'package:flutter/material.dart';

/// Utility functions for handling locale-related operations.
///
/// This provides a consistent way to check locale across the application,
/// avoiding duplicate inline checks like `Localizations.localeOf(context) == const Locale('de')`.

/// Checks if the current locale is German.
///
/// Example:
/// ```dart
/// final filePath = isGermanLocale(context)
///     ? settings.filePathDe
///     : settings.filePathEn;
/// ```
bool isGermanLocale(BuildContext context) {
  return Localizations.localeOf(context) == const Locale('de');
}

/// Checks if the current locale is English.
bool isEnglishLocale(BuildContext context) {
  return Localizations.localeOf(context) == const Locale('en');
}

/// Returns the appropriate localized value based on current locale.
///
/// Example:
/// ```dart
/// final title = localizedValue(
///   context,
///   de: 'Hallo Welt',
///   en: 'Hello World',
/// );
/// ```
T localizedValue<T>(BuildContext context, {required T de, required T en}) {
  return isGermanLocale(context) ? de : en;
}

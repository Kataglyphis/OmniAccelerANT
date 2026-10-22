import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The OFL notice of the Noto fonts the web build serves under `fallback-fonts/`.
const String fallbackFontLicensePath =
    'assets/licenses/noto-fallback-fonts-OFL.txt';

/// The fallback font families the notice covers, as the licences page lists them.
const List<String> fallbackFontFamilies = <String>[
  'Noto Color Emoji',
  'Noto Sans Symbols 2',
];

/// The fallback fonts' licence entry, its text read from [bundle].
Stream<LicenseEntry> fallbackFontLicenses(AssetBundle bundle) async* {
  yield LicenseEntryWithLineBreaks(
    fallbackFontFamilies,
    await bundle.loadString(fallbackFontLicensePath),
  );
}

/// Adds the fallback fonts' licence to [LicenseRegistry]; the text is read only when a page lists the licences.
void registerFallbackFontLicenses() {
  LicenseRegistry.addLicense(() => fallbackFontLicenses(rootBundle));
}

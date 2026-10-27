import 'package:anthology/Licenses/bundled_licenses.dart';
import 'package:flutter/services.dart';

/// The OFL notice of the Noto fonts the web build serves under `fallback-fonts/`.
const String fallbackFontLicensePath =
    'assets/licenses/noto-fallback-fonts-OFL.txt';

/// The fallback font families the notice covers, as the licences page lists them.
const List<String> fallbackFontFamilies = <String>[
  'Noto Color Emoji',
  'Noto Sans Symbols 2',
];

/// Adds the fallback fonts' licence to the licences page; the text is read only when a page lists the licences.
void registerFallbackFontLicenses({AssetBundle? bundle}) {
  registerAssetLicense(
    fallbackFontFamilies,
    fallbackFontLicensePath,
    bundle: bundle,
  );
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The generated inventory of native code and Rust crates; Dart package texts are in Flutter's NOTICES.
const String thirdPartyLicenseIndexPath =
    'assets/licenses/third-party-licenses.json';

/// One licence entry per inventoried component that carries its own text, read from [bundle].
Stream<LicenseEntry> thirdPartyLicenses(AssetBundle bundle) async* {
  final index = jsonDecode(
    await bundle.loadString(thirdPartyLicenseIndexPath),
  ) as Map<String, dynamic>;
  final texts = <String, String>{};
  for (final file in (index['text_files'] as List<dynamic>).cast<String>()) {
    final chunk = jsonDecode(
      await bundle.loadString('assets/licenses/$file'),
    ) as Map<String, dynamic>;
    texts.addAll(chunk.cast<String, String>());
  }
  for (final component
      in (index['components'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final refs = (component['texts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    if (refs.isEmpty) {
      continue;
    }
    final version = component['version'] as String?;
    final name = component['name'] as String;
    yield LicenseEntryWithLineBreaks(<String>[
      version == null ? name : '$name $version',
    ], refs.map((ref) => texts[ref['sha256'] as String]!).join('\n\n'));
  }
}

/// Adds the inventory to [LicenseRegistry]; the texts are read only when a page lists the licences.
void registerThirdPartyLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() => thirdPartyLicenses(bundle ?? rootBundle));
}

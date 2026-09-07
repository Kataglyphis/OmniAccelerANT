import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';

class ImprintFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AnthologyLocalizations.of(context)!.imprint;
  }

  @override
  String getRoutingName() {
    return "/imprint";
  }

  @override
  String getFilePathDe() {
    return 'packages/anthology/assets/documents/footer/imprintDe.md';
  }

  @override
  String getFilePathEn() {
    return 'packages/anthology/assets/documents/footer/imprintEn.md';
  }
}

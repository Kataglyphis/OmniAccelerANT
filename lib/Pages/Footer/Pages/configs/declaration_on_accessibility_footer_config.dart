import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';

class DeclarationOnAccessibilityFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AnthologyLocalizations.of(context)!.declarationOnAccessibility;
  }

  @override
  String getRoutingName() {
    return "/declarationOnAccessibility";
  }

  @override
  String getFilePathDe() {
    return 'packages/anthology/assets/documents/footer/declarationOnAccessibilityDe.md';
  }

  @override
  String getFilePathEn() {
    return 'packages/anthology/assets/documents/footer/declarationOnAccessibilityEn.md';
  }
}

import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';

class CookieDeclarationFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AnthologyLocalizations.of(context)!.cookieStatement;
  }

  @override
  String getRoutingName() {
    return "/cookieDeclaration";
  }

  @override
  String getFilePathDe() {
    return 'packages/anthology/assets/documents/footer/cookieDeclarationDe.md';
  }

  @override
  String getFilePathEn() {
    return 'packages/anthology/assets/documents/footer/cookieDeclarationEn.md';
  }
}

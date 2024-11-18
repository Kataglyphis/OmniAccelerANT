import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer_page_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CookieDeclarationFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AppLocalizations.of(context)!.cookieStatement;
  }

  @override
  String getRoutingName() {
    return "/cookieDeclaration";
  }

  @override
  String getFilePathDe() {
    return 'assets/documents/footer/cookieDeclarationDe.md';
  }

  @override
  String getFilePathEn() {
    return 'assets/documents/footer/cookieDeclarationEn.md';
  }
}

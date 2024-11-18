import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer_page_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ImprintFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AppLocalizations.of(context)!.imprint;
  }

  @override
  String getRoutingName() {
    return "/imprint";
  }

  @override
  String getFilePathDe() {
    return 'assets/documents/footer/imprintDe.md';
  }

  @override
  String getFilePathEn() {
    return 'assets/documents/footer/imprintEn.md';
  }
}

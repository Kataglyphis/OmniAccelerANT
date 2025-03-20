import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer_page_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CopyRightFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AppLocalizations.of(context)!.copyrightFooterTitle;
  }

  @override
  String getRoutingName() {
    return "/copyright";
  }

  @override
  String getFilePathDe() {
    return 'assets/documents/footer/copyRightDe.md';
  }

  @override
  String getFilePathEn() {
    return 'assets/documents/footer/copyRightEn.md';
  }
}

import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';

class CopyRightFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AnthologyLocalizations.of(context)!.copyrightFooterTitle;
  }

  @override
  String getRoutingName() {
    return "/copyright";
  }

  @override
  String getFilePathDe() {
    return 'packages/anthology/assets/documents/footer/copyRightDe.md';
  }

  @override
  String getFilePathEn() {
    return 'packages/anthology/assets/documents/footer/copyRightEn.md';
  }
}

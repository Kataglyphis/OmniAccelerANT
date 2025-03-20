import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Home/button_names.dart';
import 'package:jotrockenmitlockenrepo/Pages/Home/home_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';

class JotrockenMitLockenHomeConfig extends HomeConfig {
  @override
  ButtonNames getButtonNames(BuildContext context) {
    return ButtonNames(
        brightness: AppLocalizations.of(context)!.toogleBrightness,
        // for now i want my app color NOT selectable in production
        color:
            (kDebugMode) ? AppLocalizations.of(context)!.selectSeedColor : null,
        language: AppLocalizations.of(context)!.switchLang);
  }
}

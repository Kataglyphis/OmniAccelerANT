import 'package:flutter/material.dart';
import 'package:anthology/Pages/AboutMePage/Widgets/about_me_table.dart';
import 'package:anthology/Widgets/skill_table.dart';
import 'package:anthology/Sqlite/sqlite3_healthcheck_widget.dart';
import 'package:anthology/locale_helpers.dart';
import 'package:omni_accelerant/src/boot/rust_core.dart';
import 'package:omni_accelerant/src/db/sqlite3_storage.dart';
import 'package:omni_accelerant/src/rust/api/simple.dart';
import 'package:anthology/Layout/ResponsiveDesign/one_two_transition_widget.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/constants.dart';
import 'package:anthology/user_settings.dart';

/// About Me page: personal info, skills, and the Rust and SQLite demos.
class AboutMePage extends StatefulWidget {
  /// The application-wide attributes for theming and layout.
  final AppAttributes appAttributes;

  /// The footer widget to display at the bottom of the page.
  final Footer footer;

  const AboutMePage({
    super.key,
    required this.appAttributes,
    required this.footer,
  });

  @override
  State<StatefulWidget> createState() => AboutMePageState();
}

class AboutMePageState extends State<AboutMePage> {
  List<List<Widget>> _createAboutMeChildPages(
    UserSettings userSettings,
    ColorSeed colorSelected,
    BuildContext context,
  ) {
    final aboutMeFile = isGermanLocale(context)
        ? userSettings.aboutMeFileDe!
        : userSettings.aboutMeFileEn!;

    final childWidgetsLeftPage = <Widget>[
      AboutMeTable(userSettings: userSettings),
      Center(
        child: Text(
          rustCoreAvailable
              ? 'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom")}`'
              : 'Action: Call Rust `greet("Tom")`\nResult: the Rust core did not load in this browser',
        ),
      ),
      const Center(
        child: Sqlite3HealthcheckWidget(check: runOmniSqliteHealthcheck),
      ),
    ];

    final childWidgetsRightPage = <Widget>[
      SkillTable(aboutMeFile: aboutMeFile, userSettings: userSettings),
    ];

    return [childWidgetsLeftPage, childWidgetsRightPage];
  }

  @override
  Widget build(BuildContext context) {
    var aboutMePagesLeftRight = _createAboutMeChildPages(
      widget.appAttributes.userSettings,
      widget.appAttributes.colorSelected,
      context,
    );
    return OneTwoTransitionPage(
      childWidgetsLeftPage: aboutMePagesLeftRight[0],
      childWidgetsRightPage: aboutMePagesLeftRight[1],
      appAttributes: widget.appAttributes,
      footer: widget.footer,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      railAnimation: widget.appAttributes.railAnimation,
    );
  }
}

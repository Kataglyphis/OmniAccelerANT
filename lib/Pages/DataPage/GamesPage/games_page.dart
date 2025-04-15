import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/GamesPage/games_list.dart';
import 'package:kataglyphis_inference_engine/blog_dependent_app_attributes.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:kataglyphis_inference_engine/l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';

class GamesPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;
  final BlogDependentAppAttributes blogDependentAppAttributes;
  const GamesPage({
    super.key,
    required this.appAttributes,
    required this.footer,
    required this.blogDependentAppAttributes,
  });

  @override
  State<StatefulWidget> createState() => GamesPageState();
}

class GamesPageState extends State<GamesPage> {
  @override
  Widget build(BuildContext context) {
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        GamesList(
          blogDependentAppAttributes: widget.blogDependentAppAttributes,
          entryRedirectText: AppLocalizations.of(context)!.entryRedirectText,
          appAttributes: widget.appAttributes,
          title: AppLocalizations.of(context)!.games,
          description:
              "${AppLocalizations.of(context)!.gamesDescription}\u{1F63A}",
          dataFilePath: "assets/data/Spiele.csv",
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/FilmsPage/films_list.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';

class FilmsPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;
  const FilmsPage(
      {super.key, required this.appAttributes, required this.footer});

  @override
  State<StatefulWidget> createState() => FilmsPageState();
}

class FilmsPageState extends State<FilmsPage> {
  @override
  Widget build(BuildContext context) {
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        FilmsList(
            entryRedirectText: AppLocalizations.of(context)!.entryRedirectText,
            title: AppLocalizations.of(context)!.films,
            description:
                "${AppLocalizations.of(context)!.filmsDescription}\u{1F63A}",
            dataFilePath: "assets/data/Filmliste_gesehen.csv"),
      ],
    );
  }
}

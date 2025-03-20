import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/data_page_entry.dart';
import 'package:jotrockenmitlockenrepo/Decoration/row_divider.dart';

import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/one_two_transition_widget.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';

class DataPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;
  const DataPage(
      {super.key, required this.appAttributes, required this.footer});

  @override
  State<StatefulWidget> createState() => DataPageState();
}

class DataPageState extends State<DataPage> {
  List<List<Widget>> _createLandingPageChildWidgets(BuildContext context) {
    List<Widget> childWidgetsLeftPage = [
      DataPageEntry(
        label: AppLocalizations.of(context)!.quotations,
        routerPath: '/quotations',
        imagePath: 'assets/images/Pages/Data/Quotes_cover.jpg',
        description: AppLocalizations.of(context)!.quotationsDescription,
        lastModified: 'babbeln',
      ),
      rowDivider,
      DataPageEntry(
        label: AppLocalizations.of(context)!.films,
        routerPath: '/films',
        imagePath: 'assets/images/Pages/Data/Film_cover.jpg',
        description: AppLocalizations.of(context)!.filmsDescription,
        lastModified: 'glotze',
      ),
      rowDivider,
    ];
    List<Widget> childWidgetsRightPage = [
      DataPageEntry(
        label: AppLocalizations.of(context)!.books,
        routerPath: '/books',
        imagePath: 'assets/images/Pages/Data/Book_cover.jpg',
        description: AppLocalizations.of(context)!.booksDescription,
        lastModified: '.._..',
      ),
      rowDivider,
      DataPageEntry(
        label: AppLocalizations.of(context)!.games,
        routerPath: '/games',
        imagePath: 'assets/images/Pages/Data/Spiele_cover.jpg',
        description: AppLocalizations.of(context)!.gamesDescription,
        lastModified: 'Go rust',
      ),
    ];

    return [childWidgetsLeftPage, childWidgetsRightPage];
  }

  @override
  Widget build(BuildContext context) {
    var homePagesLeftRight = _createLandingPageChildWidgets(context);

    return OneTwoTransitionPage(
        childWidgetsLeftPage: homePagesLeftRight[0],
        childWidgetsRightPage: homePagesLeftRight[1],
        appAttributes: widget.appAttributes,
        footer: widget.footer,
        showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
        showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
        railAnimation: widget.appAttributes.railAnimation);
  }
}

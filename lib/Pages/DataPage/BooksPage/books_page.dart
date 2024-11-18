import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/BooksPage/books_list.dart';
import 'package:kataglyphis_inference_engine/blog_dependent_app_attributes.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';

class BooksPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final BlogDependentAppAttributes blogDependentAppAttributes;
  final Footer footer;
  const BooksPage(
      {super.key,
      required this.appAttributes,
      required this.footer,
      required this.blogDependentAppAttributes});

  @override
  State<StatefulWidget> createState() => BooksPageState();
}

class BooksPageState extends State<BooksPage> {
  @override
  Widget build(BuildContext context) {
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        BooksList(
            blogDependentAppAttributes: widget.blogDependentAppAttributes,
            entryRedirectText: AppLocalizations.of(context)!.entryRedirectText,
            appAttributes: widget.appAttributes,
            title: AppLocalizations.of(context)!.books,
            description:
                "${AppLocalizations.of(context)!.booksDescription}\u{1F63A}",
            dataFilePath: "assets/data/Buecherliste_gelesen.csv"),
      ],
    );
  }
}

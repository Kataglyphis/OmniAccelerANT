import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file_table.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:jotrockenmitlockenrepo/constants.dart';

class DocumentPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;
  const DocumentPage(
      {super.key, required this.appAttributes, required this.footer});

  @override
  State<StatefulWidget> createState() => DocumentPageState();
}

class DocumentPageState extends State<DocumentPage> {
  @override
  Widget build(BuildContext context) {
    bool isMobileDevice =
        MediaQuery.of(context).size.width <= narrowScreenWidthThreshold;
    Locale currentLocale = Localizations.localeOf(context);
    List<File> docs = [
      File(
        baseDir: 'assets/documents/cv/',
        title: 'CV_Jonas_Heinle_english.pdf',
        additionalInfo: '~3.7MB English',
      ),
      File(
        baseDir: 'assets/documents/cv/',
        title: 'CV_Jonas_Heinle_german.pdf',
        additionalInfo: '~3.7MB DE',
      ),
      File(
          baseDir: 'assets/documents/thesis/',
          title: 'Bachelor_Thesis.pdf',
          additionalInfo: (isMobileDevice)
              ? '~33MB'
              : (currentLocale == const Locale("de"))
                  ? '~33MB DE\nZeitlich stabile blue noise Fehlerverteilung im Bildraum für Echtzeitanwendungen'
                  : '~33MB DE\nTemporally stable blue noise error distribution in image space for real-time applications'),
      File(
          baseDir: 'assets/documents/thesis/',
          title: 'Master_Thesis.pdf',
          additionalInfo: (isMobileDevice)
              ? '~47MB'
              : (currentLocale == const Locale("de"))
                  ? '~47MB EN\nGestaltung von nutzeradaptiven Inhalten für Mixed Reality mit Hilfe von Eye- und Hand-Tracking'
                  : '~47MB EN\nDesigning User-adaptive Content for Mixed Reality Using Eye and Hand Tracking'),
    ];
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        FileTable(
          docs: docs,
          title: AppLocalizations.of(context)!.documents,
        )
      ],
    );
  }
}

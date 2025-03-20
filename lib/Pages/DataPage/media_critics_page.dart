import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file_table.dart';
import 'package:jotrockenmitlockenrepo/Media/Markdown/markdown_page.dart';
import 'package:kataglyphis_inference_engine/my_two_cents_config.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';

class MediaCriticsPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;
  final MyTwoCentsConfig mediaCriticsPageConfig;
  const MediaCriticsPage(
      {super.key,
      required this.appAttributes,
      required this.footer,
      required this.mediaCriticsPageConfig});

  @override
  State<StatefulWidget> createState() => MediaCriticsPageState();
}

class MediaCriticsPageState extends State<MediaCriticsPage> {
  @override
  Widget build(BuildContext context) {
    List<File> docs = widget.mediaCriticsPageConfig.docsDesc
        .map(
          (fileConfig) => File(
            baseDir: fileConfig['baseDir']!,
            title: fileConfig['title']!,
            additionalInfo: fileConfig['additionalInfo']!,
          ),
        )
        .toList();
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        MarkdownFilePage(
          currentLocale: Localizations.localeOf(context),
          filePathDe: '',
          filePathEn: widget.mediaCriticsPageConfig.filePath,
          imageDirectory: widget.mediaCriticsPageConfig.imageDir,
          useLightMode: widget.appAttributes.useLightMode,
        ),
        FileTable(
          title: 'Appendix',
          docs: docs,
        )
      ],
    );
  }
}

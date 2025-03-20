import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file_table.dart';
import 'package:jotrockenmitlockenrepo/Media/Markdown/markdown_page.dart';
import 'package:kataglyphis_inference_engine/blog_page_config.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';

class BlogPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;
  final BlogPageConfig blogPageConfig;
  const BlogPage(
      {super.key,
      required this.appAttributes,
      required this.footer,
      required this.blogPageConfig});

  @override
  State<StatefulWidget> createState() => BlogPageState();
}

class BlogPageState extends State<BlogPage> {
  @override
  Widget build(BuildContext context) {
    List<File> docs = widget.blogPageConfig.docsDesc
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
          filePathEn: widget.blogPageConfig.filePath,
          imageDirectory: widget.blogPageConfig.imageDir,
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

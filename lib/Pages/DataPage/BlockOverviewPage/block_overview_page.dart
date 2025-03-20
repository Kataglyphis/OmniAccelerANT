import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/BlockOverviewPage/block_entry.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/BlockOverviewPage/block_entry_list.dart';
import 'package:kataglyphis_inference_engine/blog_dependent_app_attributes.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';

class BlockOverviewPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final BlogDependentAppAttributes blogDependentAppAttributes;
  final Footer footer;
  const BlockOverviewPage(
      {super.key,
      required this.appAttributes,
      required this.footer,
      required this.blogDependentAppAttributes});

  @override
  State<StatefulWidget> createState() => BlockOverviewPageState();
}

class BlockOverviewPageState extends State<BlockOverviewPage> {
  @override
  Widget build(BuildContext context) {
    List<BlockEntry> blockEntries =
        widget.blogDependentAppAttributes.blockSettings
            .map(
              (config) => BlockEntry(
                  title: (Localizations.localeOf(context) == const Locale("de"))
                      ? config.shortDescriptionDE
                      : config.shortDescriptionEN,
                  date: config.lastModified,
                  comment: config.routingName),
            )
            .toList();
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        BlockEntryList(
          entryRedirectText: AppLocalizations.of(context)!.entryRedirectText,
          appAttributes: widget.appAttributes,
          title: AppLocalizations.of(context)!.blockEntryOverview,
          description:
              "${AppLocalizations.of(context)!.blockEntryOverviewDescription}\u{1F63A}",
          sortColumnIndex: 2,
          dataCategories: const ["Titel", "Date", "Comment"],
          data: blockEntries,
        ),
      ],
    );
  }
}

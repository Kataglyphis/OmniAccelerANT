import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:jotrockenmitlockenrepo/Decoration/row_divider.dart';
import 'package:jotrockenmitlockenrepo/Decoration/component_group_decoration.dart';
import 'package:jotrockenmitlockenrepo/Media/Image/openable_image.dart';
import 'package:flutter/material.dart';

class DataPageEntry extends StatefulWidget {
  const DataPageEntry({
    super.key,
    required this.label,
    required this.routerPath,
    required this.imagePath,
    required this.description,
    required this.lastModified,
    this.imageCaptioning,
  });
  final String label;
  final String routerPath;
  final String imagePath;
  final String description;
  final String? imageCaptioning;
  final String lastModified;

  @override
  State<DataPageEntry> createState() => DataPageEntryState();
}

class DataPageEntryState extends State<DataPageEntry> {
  bool isDisabled = false;

  @override
  Widget build(BuildContext context) {
    List<Widget> undecoratedChilds = [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              widget.description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
      rowDivider,
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.tonal(
            onPressed: isDisabled
                ? null
                : () {
                    context.go(widget.routerPath);
                  },
            child: Text(
              AppLocalizations.of(context)!.follow,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
      rowDivider,
      OpenableImage(
        displayedImage: widget.imagePath,
        disableOpen: true,
        imageCaptioning: widget.imageCaptioning,
      ),
      rowDivider,
      Padding(
        padding: const EdgeInsets.only(right: 34.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              widget.lastModified,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ComponentGroupDecoration(
              label: widget.label, children: <Widget>[...undecoratedChilds]),
        ],
      ),
    );
  }
}

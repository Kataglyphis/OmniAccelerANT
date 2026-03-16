import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/BlockOverviewPage/block_entry.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/data_list.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/datacell_content_strategies.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';

class BlockEntryList extends DataList {
  const BlockEntryList({
    super.key,
    required super.data,
    required super.entryRedirectText,
    required super.dataCategories,
    required super.title,
    required super.description,
    // all entries with a critic should be displayed in the very beginning :)
    super.sortColumnIndex = 3,
    super.sortOnLoaded = true,
    required this.appAttributes,
  });
  //"Books worth reading"
  @override
  State<BlockEntryList> createState() => _BlockEntryListState();

  final AppAttributes appAttributes;
}

class _BlockEntryListState extends DataListState<BlockEntry, BlockEntryList> {
  /// Column spacing ratios for the data table.
  /// Currently uniform across mobile and desktop layouts.
  static const List<double> _columnSpacing = [0.3, 0.3, 0.3];

  @override
  List<double> getSpacing(bool isMobileDevice) => _columnSpacing;

  @override
  List<DataCellContentStrategies> getDataCellContentStrategies() {
    return [
      DataCellContentStrategies.text,
      DataCellContentStrategies.text,
      DataCellContentStrategies.textButton,
    ];
  }
}

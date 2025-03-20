import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/GamesPage/game.dart';
import 'package:kataglyphis_inference_engine/blog_dependent_app_attributes.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/csv_data_list.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/datacell_content_strategies.dart';
import 'package:kataglyphis_inference_engine/my_two_cents_config.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';

class GamesList extends CsvDataList {
  const GamesList(
      {super.key,
      required super.dataFilePath,
      required super.title,
      required super.entryRedirectText,
      required super.description,
      required this.blogDependentAppAttributes,
      // all entries with a critic should be displayed in the very beginning :)
      super.sortColumnIndex = 2,
      super.sortOnLoaded = true,
      // super.isAscending = true,
      required this.appAttributes});
  //"Books worth reading"
  @override
  State<GamesList> createState() => _GamesListState();

  final AppAttributes appAttributes;
  final BlogDependentAppAttributes blogDependentAppAttributes;
}

class _GamesListState extends CsvDataListState<Game, GamesList> {
  @override
  Future<(List<Game>, List<String>)> convertRawCSVDataToFinalLayout(
      List<List<dynamic>> csvListData) async {
    List<MyTwoCentsConfig> configs =
        widget.blogDependentAppAttributes.twoCentsConfigs;
    List<String> dataCategories = List<String>.from(csvListData.first);
    List<Game> convertedCsvListData =
        csvListData.getRange(1, csvListData.length).toList().map((List e) {
      int index = configs
          .indexWhere((item) => item.mediaTitle == e.elementAt(0).toString());
      return Game(
        title: e.elementAt(0).toString(),
        developer: e.elementAt(1).toString(),
        comment: index != -1 ? configs[index].routingName : "",
      );
    }).toList();
    return (convertedCsvListData, dataCategories);
  }

  @override
  List<double> getSpacing(bool isMobileDevice) {
    if (isMobileDevice) {
      return [0.3, 0.3, 0.3];
    } else {
      return [0.3, 0.3, 0.3];
    }
  }

  @override
  List<DataCellContentStrategies> getDataCellContentStrategies() {
    return [
      DataCellContentStrategies.text,
      DataCellContentStrategies.text,
      DataCellContentStrategies.textButton
    ];
  }
}

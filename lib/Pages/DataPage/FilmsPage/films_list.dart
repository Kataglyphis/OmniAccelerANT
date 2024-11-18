import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/csv_data_list.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/FilmsPage/film.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/datacell_content_strategies.dart';

class FilmsList extends CsvDataList {
  const FilmsList(
      {super.key,
      required super.dataFilePath,
      required super.title,
      required super.entryRedirectText,
      required super.description});
  // "Films/Series worth watching"
  @override
  State<FilmsList> createState() => _FilmsListState();
}

class _FilmsListState extends CsvDataListState<Film, FilmsList> {
  @override
  Future<(List<Film>, List<String>)> convertRawCSVDataToFinalLayout(
      List<List<dynamic>> csvListData) async {
    List<String> dataCategories = List<String>.from(csvListData.first);
    List<Film> convertedCsvListData = csvListData
        .getRange(1, csvListData.length)
        .toList()
        .map((List e) => Film(
              title: e.elementAt(0).toString(),
              genre: e.elementAt(1).toString(),
              actor: e.elementAt(2).toString(),
              sonstiges: e.elementAt(3).toString(),
            ))
        .toList();
    return (convertedCsvListData, dataCategories);
  }

  @override
  List<double> getSpacing(bool isMobileDevice) {
    if (isMobileDevice) {
      return [0.35, 0.3, 0.3, 0.2];
    } else {
      return [0.2, 0.2, 0.2, 0.2];
    }
  }

  @override
  List<DataCellContentStrategies> getDataCellContentStrategies() {
    return [
      DataCellContentStrategies.text,
      DataCellContentStrategies.text,
      DataCellContentStrategies.text,
      DataCellContentStrategies.text
    ];
  }
}

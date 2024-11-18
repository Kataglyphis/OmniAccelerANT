import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/BooksPage/book.dart';
import 'package:kataglyphis_inference_engine/blog_dependent_app_attributes.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/csv_data_list.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/datacell_content_strategies.dart';
import 'package:kataglyphis_inference_engine/my_two_cents_config.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';

class BooksList extends CsvDataList {
  const BooksList(
      {super.key,
      required super.dataFilePath,
      required super.title,
      required super.entryRedirectText,
      required super.description,
      // all entries with a critic should be displayed in the very beginning :)
      super.sortColumnIndex = 3,
      super.sortOnLoaded = true,
      // super.isAscending = true,
      required this.appAttributes,
      required this.blogDependentAppAttributes});
  //"Books worth reading"
  @override
  State<BooksList> createState() => _BooksListState();

  final AppAttributes appAttributes;
  final BlogDependentAppAttributes blogDependentAppAttributes;
}

class _BooksListState extends CsvDataListState<Book, BooksList> {
  @override
  Future<(List<Book>, List<String>)> convertRawCSVDataToFinalLayout(
      List<List<dynamic>> csvListData) async {
    List<MyTwoCentsConfig> configs =
        widget.blogDependentAppAttributes.twoCentsConfigs;
    List<String> dataCategories = List<String>.from(csvListData.first);
    List<Book> convertedCsvListData =
        csvListData.getRange(1, csvListData.length).toList().map((List e) {
      int index = configs
          .indexWhere((item) => item.mediaTitle == e.elementAt(0).toString());
      return Book(
        title: e.elementAt(0).toString(),
        author: e.elementAt(1).toString(),
        isbn: e.elementAt(2).toString(),
        comment: index != -1 ? configs[index].routingName : "",
      );
    }).toList();
    return (convertedCsvListData, dataCategories);
  }

  @override
  List<double> getSpacing(bool isMobileDevice) {
    if (isMobileDevice) {
      return [0.4, 0.3, 0.2, 0.3];
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
      DataCellContentStrategies.textButton
    ];
  }
}

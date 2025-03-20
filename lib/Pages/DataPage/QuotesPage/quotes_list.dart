import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/csv_data_list.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/QuotesPage/quote.dart';
import 'package:jotrockenmitlockenrepo/Media/DataTable/datacell_content_strategies.dart';

class QuotesList extends CsvDataList {
  const QuotesList({
    super.key,
    required super.entryRedirectText,
    required super.dataFilePath,
    required super.title,
    required super.description,
  });

  @override
  State<QuotesList> createState() => _QuotesListState();
}

class _QuotesListState extends CsvDataListState<Quote, QuotesList> {
  String _formatQuote(String unformattedQuote) {
    return "»$unformattedQuote«";
  }

  @override
  Future<(List<Quote>, List<String>)> convertRawCSVDataToFinalLayout(
      List<List<dynamic>> csvListData) async {
    List<String> dataCategories = List<String>.from(csvListData.first);
    List<Quote> convertedCsvListData = csvListData
        .getRange(1, csvListData.length)
        .toList()
        .map((List e) => Quote(
              author: e.elementAt(0).toString(),
              content: _formatQuote(e.elementAt(1).toString()),
            ))
        .toList();
    return (convertedCsvListData, dataCategories);
  }

  @override
  List<double> getSpacing(bool isMobileDevice) {
    if (isMobileDevice) {
      return [0.2, 0.65];
    } else {
      return [0.2, 0.65];
    }
  }

  @override
  List<DataCellContentStrategies> getDataCellContentStrategies() {
    return [
      DataCellContentStrategies.text,
      DataCellContentStrategies.text,
    ];
  }
}

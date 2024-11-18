import 'package:jotrockenmitlockenrepo/Media/DataTable/table_data.dart';

class BlockEntry extends TableData {
  String title = "placeholder";
  String date = "placeholder";
  String comment = "placeholder";

  BlockEntry({
    required this.title,
    required this.date,
    required this.comment,
  });

  @override
  List<String> getCells() {
    return [title, date, comment];
  }
}

import 'package:jotrockenmitlockenrepo/Media/DataTable/table_data.dart';

class Game extends TableData {
  String title = "placeholder";
  String developer = "placeholder";
  String comment = "placeholder";

  Game({
    required this.title,
    required this.developer,
    required this.comment,
  });

  @override
  List<String> getCells() {
    return [title, developer, comment];
  }
}

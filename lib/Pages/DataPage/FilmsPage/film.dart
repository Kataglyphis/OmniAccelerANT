import 'package:jotrockenmitlockenrepo/Media/DataTable/table_data.dart';

class Film extends TableData {
  String title = "placeholder";
  String genre = "placeholder";
  String actor = "placeholder";
  String sonstiges = "placeholder";
  Film(
      {required this.title,
      required this.genre,
      required this.actor,
      required this.sonstiges});

  @override
  List<String> getCells() {
    return [title, genre, actor, sonstiges];
  }
}

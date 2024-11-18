import 'package:jotrockenmitlockenrepo/Media/DataTable/table_data.dart';

class Book extends TableData {
  String title = "placeholder";
  String author = "placeholder";
  String isbn = "placeholder";
  String comment = "placeholder";

  Book({
    required this.title,
    required this.author,
    required this.isbn,
    required this.comment,
  });

  @override
  List<String> getCells() {
    return [title, author, isbn, comment];
  }
}

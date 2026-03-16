import 'package:jotrockenmitlockenrepo/Media/DataTable/table_data.dart';

/// Represents a single blog/data entry in the overview table.
///
/// Each entry has a title, date, and comment that are displayed
/// in the block overview data table.
class BlockEntry extends TableData {
  /// Creates a block entry with the required fields.
  BlockEntry({required this.title, required this.date, required this.comment});

  /// The title of the entry.
  final String title;

  /// The date associated with the entry.
  final String date;

  /// Additional comment or description.
  final String comment;

  @override
  List<String> getCells() => [title, date, comment];
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:jotrockenmitlockenrepo/Decoration/centered_box_decoration.dart';
import 'package:jotrockenmitlockenrepo/constants.dart';
import 'package:jotrockenmitlockenrepo/user_settings.dart';
import 'package:jotrockenmitlockenrepo/Decoration/row_divider.dart';

class SkillTable extends StatefulWidget {
  const SkillTable(
      {super.key, required this.userSettings, required this.aboutMeFile});

  final UserSettings userSettings;
  final String aboutMeFile; //= widget.userSettings.aboutMeFileEn!;

  @override
  State<SkillTable> createState() => _SkillTableState();
}

class _SkillTableState extends State<SkillTable> {
  late Future<(List<String>, List<List<dynamic>>)> _skillTableJson;

  @override
  void initState() {
    super.initState();
    _skillTableJson = _readJson();
  }

  // Fetch content from the json file
  Future<(List<String>, List<List<dynamic>>)> _readJson() async {
    final jsonData = await rootBundle.loadString(widget.aboutMeFile);
    final Map<String, dynamic> list = json.decode(jsonData);
    List<List<dynamic>> values = [];
    List<String> keys = list.keys.toList();
    for (int i = 0; i < keys.length; i++) {
      var val = list[keys[i]];
      // no support right now for nested object notations
      if (val is List) {
        values.add(val);
      } else if (val == null) {
        values.add(["not known"]);
      } else {
        values.add([val]);
      }
    }

    return (keys, values);
  }

  List<Widget> getSkillTableKeys(dynamic key) {
    // this means string contains sub informations
    if ((key.toString().contains("("))) {
      return <Widget>[
        Text(
          key.substring(0, key.toString().indexOf("(")).trim(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          key.substring(key.toString().indexOf("(")).trim(),
          style: Theme.of(context).textTheme.titleMedium,
        )
      ];
    } else {
      return [
        Text(
          key,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final double currentWith = MediaQuery.of(context).size.width;
    double betweenColumnPadding =
        (currentWith <= narrowScreenWidthThreshold) ? 40.0 : 80.0;

    return FutureBuilder(
        future: _skillTableJson,
        builder: (context, data) {
          if (data.hasData) {
            List<String> keys = data.requireData.$1;
            List<List<dynamic>> values = data.requireData.$2;
            List<TableRow> skills = [];
            for (int i = 0; i < keys.length; i++) {
              String entryVal = "";
              var entryList = values[i];
              for (int j = 0; j < entryList.length; j++) {
                entryVal += "• ${entryList[j]}${"\n"}";
              }
              skills.add(TableRow(children: [
                TableCell(
                    child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: getSkillTableKeys(keys[i]),
                  ),
                )),
                TableCell(
                    child: Padding(
                  padding: EdgeInsets.fromLTRB(betweenColumnPadding, 8, 0, 0),
                  child: Text(entryVal,
                      style: Theme.of(context).textTheme.titleMedium),
                ))
              ]));
              skills.add(TableRow(children: [
                rowDivider,
                rowDivider,
              ]));
            }
            final double currentWidth = MediaQuery.of(context).size.width;
            double skillTableWidth = currentWidth;
            if (currentWidth >= mediumWidthBreakpoint) {
              skillTableWidth = skillTableWidth * 0.4;
            } else {
              skillTableWidth = skillTableWidth * 0.9;
            }
            return CenteredBoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              child: SizedBox(
                width: skillTableWidth,
                child: Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.top,
                    children: skills),
              ),
            );
          } else if (data.hasError) {
            return Center(child: Text("${data.error}"));
          } else {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
        });
  }
}

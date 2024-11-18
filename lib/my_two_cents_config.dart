import 'package:jotrockenmitlockenrepo/Pages/stateful_branch_info_provider.dart';

class MyTwoCentsConfig extends StatefulBranchInfoProvider {
  MyTwoCentsConfig.fromJsonFile(Map<String, dynamic> jsonFile)
      : routingName = jsonFile["routingName"] as String,
        filePath = jsonFile["filePath"] as String,
        imageDir = jsonFile["imageDir"] as String,
        mediaTitle = jsonFile["mediaTitle"] as String,
        fileBaseDir = jsonFile["fileBaseDir"] as String {
    var docsDescJsonFile = jsonFile["docsDesc"] as List<dynamic>;
    for (var element in docsDescJsonFile) {
      docsDesc.add({
        'baseDir': element['baseDir'],
        'title': element['title'],
        'additionalInfo': element['additionalInfo'],
      });
    }
  }
  String routingName;
  String filePath;
  String imageDir;
  String mediaTitle;
  String fileBaseDir;
  List<Map<String, String>> docsDesc = [];

  @override
  String getRoutingName() {
    return routingName;
  }
}

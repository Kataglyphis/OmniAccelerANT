import 'package:jotrockenmitlockenrepo/Pages/stateful_branch_info_provider.dart';

enum LandingPageAlignment { left, right }

class BlogPageConfig extends StatefulBranchInfoProvider {
  BlogPageConfig.fromJsonFile(Map<String, dynamic> jsonFile)
      : routingName = jsonFile["routingName"] as String,
        shortDescriptionEN = jsonFile["shortDescriptionEN"] as String,
        shortDescriptionDE = jsonFile["shortDescriptionDE"] as String,
        filePath = jsonFile["filePath"] as String,
        imageDir = jsonFile["imageDir"] as String,
        githubRepo = jsonFile["githubRepo"] as String,
        landingPageAlignment = jsonFile["landingPageAlignment"] as String,
        landingPageEntryImagePath =
            jsonFile["landingPageEntryImagePath"] as String,
        landingPageEntryImageCaptioning =
            jsonFile["landingPageEntryImageCaptioning"] as String,
        lastModified = jsonFile["lastModified"] as String,
        fileTitle = jsonFile["fileTitle"] as String,
        fileAdditionalInfo = jsonFile["fileAdditionalInfo"] as String,
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
  String shortDescriptionEN;
  String shortDescriptionDE;
  String filePath;
  String imageDir;
  String githubRepo;
  String landingPageAlignment;
  String landingPageEntryImagePath;
  String? landingPageEntryImageCaptioning;
  String lastModified;
  String fileTitle;
  String fileAdditionalInfo;
  String fileBaseDir;
  List<Map<String, String>> docsDesc = [];

  @override
  String getRoutingName() {
    return routingName;
  }
}

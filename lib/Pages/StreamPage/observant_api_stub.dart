// Native builds have no ObservANT origin to ask or change; keep the signatures in step with `observant_api_web.dart`.

Future<String?> fetchHealthz() async => null;

Future<String?> fetchFrom(String url) async => null;

Future<String?> fetchVisits() async => null;

Future<String?> fetchObservantSettings() async => null;

Future<bool> saveObservantSettings(Map<String, Object> update) async => false;

/// ObservANT's answer to a POST: its status and body.
typedef ObservantReply = ({int status, String body});

Future<ObservantReply?> postToObservant(
  String path,
  Map<String, Object> body, {
  Future<void>? cancel,
}) async => null;

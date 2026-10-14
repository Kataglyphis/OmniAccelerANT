// Native builds have no ObservANT origin to ask or change; keep the signatures in step with `observant_api_web.dart`.

Future<String?> fetchHealthz() async => null;

Future<String?> fetchFrom(String url) async => null;

Future<String?> fetchObservantSettings() async => null;

Future<bool> saveObservantSettings(Map<String, Object> update) async => false;

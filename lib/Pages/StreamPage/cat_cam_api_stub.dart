// Native builds have no cat cam origin to ask or change; keep the signatures in step with `cat_cam_api_web.dart`.

Future<String?> fetchHealthz() async => null;

Future<String?> fetchCatCamSettings() async => null;

Future<bool> saveCatCamSettings(Map<String, Object> update) async => false;

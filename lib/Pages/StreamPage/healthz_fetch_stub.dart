/// Native builds have no cat cam origin to ask; keep the signature in step with `healthz_fetch_web.dart`.
Future<String?> fetchHealthz() async => null;

/// Native builds have no cat cam origin to ask.
Future<String?> fetchCatCamSettings() async => null;

/// Native builds have no cat cam origin to change.
Future<bool> saveCatCamSettings(Map<String, Object> update) async => false;

/// Native builds have no cat cam origin to ask; keep the signature in step with `healthz_fetch_web.dart`.
Future<String?> fetchHealthz() async => null;

/// Native builds have no cat cam origin to turn.
Future<bool> rotateCatCam(int degrees) async => false;

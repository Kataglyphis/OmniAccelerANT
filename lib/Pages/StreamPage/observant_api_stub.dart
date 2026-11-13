import 'package:omni_accelerant/Pages/StreamPage/observant_api.dart';

/// The native build's side: no ObservANT origin to ask or change.
ObservantApi createObservantApi() => const _NoObservant();

class _NoObservant implements ObservantApi {
  const _NoObservant();

  @override
  Future<String?> fetchHealthz() async => null;

  @override
  Future<String?> fetchFrom(String url) async => null;

  @override
  Future<String?> fetchVisits() async => null;

  @override
  Future<String?> fetchObservantSettings() async => null;

  @override
  Future<bool> saveObservantSettings(Map<String, Object> update) async => false;

  @override
  Future<ObservantReply?> postToObservant(
    String path,
    Map<String, Object> body, {
    Future<void>? cancel,
  }) async => null;
}

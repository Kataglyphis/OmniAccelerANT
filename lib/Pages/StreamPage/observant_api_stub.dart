import 'package:flutter/widgets.dart';

import 'package:omni_accelerant/Pages/StreamPage/observant_api.dart';

/// The native build's side: no ObservANT origin to ask or change.
ObservantApi createObservantApi() => const _NoObservant();

/// A native build has no page origin to replace, so a path stays as it is.
String observantUrl(String path) => path;

/// Only the web build asks an explicit ObservANT address.
Widget? remoteObservantPanel() => null;

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

  @override
  Future<ObservantStream?> streamFromObservant(
    String path,
    Map<String, Object> body, {
    Future<void>? cancel,
  }) async => null;
}

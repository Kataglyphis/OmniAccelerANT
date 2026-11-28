import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:omni_accelerant/Pages/StreamPage/remote/remote_access.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_observant.dart';

/// The browser's local storage key for the explicit ObservANT address.
const String observantAddressKey = 'omni_accelerant.observant_address';

/// The browser half of the remote mode: local storage, the Permissions API and `fetch`.
class WebRemoteObservantPlatform implements RemoteObservantPlatform {
  const WebRemoteObservantPlatform();

  @override
  Uri get page => Uri.base;

  // Storage can throw when the visitor blocks site data; the address then lasts only this visit.
  @override
  String? loadAddress() {
    try {
      return web.window.localStorage.getItem(observantAddressKey);
    } on Object {
      return null;
    }
  }

  @override
  void saveAddress(String? origin) {
    try {
      if (origin == null) {
        web.window.localStorage.removeItem(observantAddressKey);
      } else {
        web.window.localStorage.setItem(observantAddressKey, origin);
      }
    } on Object {
      return;
    }
  }

  @override
  Future<LocalNetworkPermission> localNetworkPermission(
    AddressSpace space,
  ) async {
    for (final String name in localNetworkPermissionNames(space)) {
      try {
        final web.PermissionStatus status = await web
            .window
            .navigator
            .permissions
            .query(<String, String>{'name': name}.jsify()! as JSObject)
            .toDart;
        return switch (status.state) {
          'granted' => LocalNetworkPermission.granted,
          'denied' => LocalNetworkPermission.denied,
          _ => LocalNetworkPermission.prompt,
        };
      } on Object {
        // A name this browser does not know throws a TypeError; the next one may be its name.
        continue;
      }
    }
    return LocalNetworkPermission.unsupported;
  }

  @override
  Future<ProbeResult> probe(Uri url, Duration timeout) async {
    final web.AbortSignal signal = web.AbortSignal.timeout(
      timeout.inMilliseconds,
    );
    try {
      final web.Response response = await web.window
          .fetch(
            url.toString().toJS,
            web.RequestInit(signal: signal, cache: 'no-store'),
          )
          .toDart;
      return ProbeAnswer(
        response.status,
        (await response.text().toDart).toDart,
      );
    } on Object {
      return signal.aborted ? const ProbeTimeout() : const ProbeNetworkError();
    }
  }
}

/// The Permissions API names to try, newest first: Chrome split `local-network-access` into these two.
List<String> localNetworkPermissionNames(AddressSpace space) => <String>[
  if (space == AddressSpace.loopback) 'loopback-network' else 'local-network',
  'local-network-access',
];

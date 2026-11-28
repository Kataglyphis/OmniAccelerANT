import 'package:flutter/foundation.dart';

import 'package:omni_accelerant/Pages/StreamPage/observant_health.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/observant_address.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_access.dart';

/// What the browser says about Local Network Access for this page.
enum LocalNetworkPermission { granted, denied, prompt, unsupported }

/// The answer to one probe: a status and body, or why none came.
sealed class ProbeResult {
  const ProbeResult();
}

final class ProbeAnswer extends ProbeResult {
  const ProbeAnswer(this.status, this.body);

  final int status;
  final String body;
}

/// `fetch` rejected: unreachable, a CORS refusal or a local-network refusal, which the page cannot tell apart.
final class ProbeNetworkError extends ProbeResult {
  const ProbeNetworkError();
}

final class ProbeTimeout extends ProbeResult {
  const ProbeTimeout();
}

/// The browser half of the remote mode; the web file implements it, tests fake it.
abstract interface class RemoteObservantPlatform {
  /// The page's own address, `Uri.base` on the web.
  Uri get page;

  /// The address this browser saved, or `null`.
  String? loadAddress();

  /// Saves [origin] for the next visit; `null` forgets it.
  void saveAddress(String? origin);

  /// The visitor's Local Network Access choice for a request into [space].
  Future<LocalNetworkPermission> localNetworkPermission(AddressSpace space);

  /// A GET of [url] that gives up after [timeout].
  Future<ProbeResult> probe(Uri url, Duration timeout);
}

/// Why the explicit ObservANT gave no status; each kind has its own message and fix on the panel.
sealed class ObservantConnectionError {
  const ObservantConnectionError();
}

final class InvalidObservantAddress extends ObservantConnectionError {
  const InvalidObservantAddress(this.problem);

  final ObservantAddressProblem problem;
}

/// An https page and an http address: refused before any request, since the browser would block it.
final class MixedContentBlocked extends ObservantConnectionError {
  const MixedContentBlocked();
}

/// The visitor refused Chrome's local-network prompt for this site, or the site settings block it.
final class LocalNetworkRefused extends ObservantConnectionError {
  const LocalNetworkRefused(this.space);

  final AddressSpace space;
}

/// No answer the page may read: wrong address, ObservANT down, or this page's origin not in its `read_origins`.
final class ObservantUnreachable extends ObservantConnectionError {
  const ObservantUnreachable({required this.localNetwork});

  /// Whether a dismissed local-network prompt could be the cause too.
  final bool localNetwork;
}

final class ObservantTimedOut extends ObservantConnectionError {
  const ObservantTimedOut();
}

/// ObservANT answered with an error status, such as 403 for a host name it does not know.
final class ObservantRefused extends ObservantConnectionError {
  const ObservantRefused(this.status, this.body);

  final int status;
  final String body;
}

/// Something answered, but not with an ObservANT `/healthz`.
final class NotAnObservant extends ObservantConnectionError {
  const NotAnObservant();
}

/// Where the remote mode stands.
sealed class ObservantConnectionStatus {
  const ObservantConnectionStatus();
}

/// No address: the page asks the ObservANT that served it.
final class ObservantOwnOrigin extends ObservantConnectionStatus {
  const ObservantOwnOrigin();
}

final class ObservantChecking extends ObservantConnectionStatus {
  const ObservantChecking({this.prompting = false});

  /// Chrome's local-network prompt is open, or about to open, for this request.
  final bool prompting;
}

final class ObservantConnected extends ObservantConnectionStatus {
  const ObservantConnected({required this.name, required this.version});

  final String name;
  final String version;
}

final class ObservantFailed extends ObservantConnectionStatus {
  const ObservantFailed(this.error);

  final ObservantConnectionError error;
}

/// The explicit ObservANT address, kept per browser, and the state of the connection to it.
class RemoteObservantController extends ChangeNotifier {
  RemoteObservantController(
    this._platform, {
    this.timeout = const Duration(seconds: 8),
    this.promptTimeout = const Duration(seconds: 60),
  }) {
    final String? saved = _platform.loadAddress();
    if (saved == null) return;
    // A saved value that no longer passes is dropped, so no request ever goes to it.
    final ObservantAddressCheck parsed = checkObservantAddress(saved);
    if (parsed is ObservantAddressValid) {
      _origin = parsed.origin;
    } else {
      _platform.saveAddress(null);
    }
  }

  final RemoteObservantPlatform _platform;

  /// How long one probe may take; one on a socket that died unnoticed would otherwise wait for minutes.
  final Duration timeout;

  /// How long a probe may wait while Chrome's local-network prompt asks the visitor.
  final Duration promptTimeout;

  Uri? _origin;
  ObservantConnectionStatus _status = const ObservantOwnOrigin();

  /// Counts checks, so the answer to an older address cannot overwrite a newer one's.
  int _generation = 0;

  /// The explicit address; `null` while the page asks its own origin.
  Uri? get origin => _origin;

  ObservantConnectionStatus get status => _status;

  /// The page's own address, for the panel's hints.
  Uri get page => _platform.page;

  /// What the browser will do with a request to [origin]; `null` without one.
  RemoteAccess? get access {
    final Uri? origin = _origin;
    return origin == null
        ? null
        : decideRemoteAccess(page: _platform.page, target: origin);
  }

  /// [path] on the explicit ObservANT, or [path] itself, which the browser resolves against the page.
  String resolve(String path) => _origin?.resolve(path).toString() ?? path;

  /// Takes a typed address: an invalid one changes nothing but the status, a valid one is saved and checked.
  Future<void> setAddress(String text) async {
    switch (checkObservantAddress(text)) {
      case ObservantAddressInvalid(:final problem):
        _generation++;
        _set(ObservantFailed(InvalidObservantAddress(problem)));
      case ObservantAddressEmpty():
        _origin = null;
        _platform.saveAddress(null);
        _generation++;
        _set(const ObservantOwnOrigin());
      case ObservantAddressValid(:final origin):
        _origin = origin;
        _platform.saveAddress(origin.toString());
        await check();
    }
  }

  /// Probes `/healthz` at the explicit address, after the decisions the browser would make anyway.
  Future<void> check() async {
    final int generation = ++_generation;
    final Uri? origin = _origin;
    final RemoteAccess? access = this.access;
    if (origin == null || access == null) {
      _set(const ObservantOwnOrigin());
      return;
    }
    if (access.mixedContent) {
      _set(const ObservantFailed(MixedContentBlocked()));
      return;
    }
    final bool asks = access.localNetwork != LocalNetworkAccess.notNeeded;
    final LocalNetworkPermission before = asks
        ? await _platform.localNetworkPermission(access.targetSpace)
        : LocalNetworkPermission.unsupported;
    if (generation != _generation) return;
    if (before == LocalNetworkPermission.denied) {
      _set(ObservantFailed(LocalNetworkRefused(access.targetSpace)));
      return;
    }
    final bool prompting = before == LocalNetworkPermission.prompt;
    _set(ObservantChecking(prompting: prompting));
    // The request waits while Chrome's prompt is open, so the visitor gets time to read it.
    final ProbeResult result = await _platform.probe(
      origin.resolve('/healthz'),
      prompting ? promptTimeout : timeout,
    );
    if (generation != _generation) return;
    final ObservantConnectionStatus next = switch (result) {
      ProbeAnswer(status: 200, :final body) => _connected(body),
      ProbeAnswer(:final status, :final body) => ObservantFailed(
        ObservantRefused(status, _excerpt(body)),
      ),
      ProbeTimeout() => const ObservantFailed(ObservantTimedOut()),
      ProbeNetworkError() => await _networkError(access, asks),
    };
    if (generation == _generation) _set(next);
  }

  /// A "Block" in Chrome's prompt rejects the request like a dead host; the permission after it tells them apart.
  Future<ObservantConnectionStatus> _networkError(
    RemoteAccess access,
    bool asks,
  ) async {
    if (asks &&
        await _platform.localNetworkPermission(access.targetSpace) ==
            LocalNetworkPermission.denied) {
      return ObservantFailed(LocalNetworkRefused(access.targetSpace));
    }
    return ObservantFailed(ObservantUnreachable(localNetwork: asks));
  }

  static ObservantConnectionStatus _connected(String body) {
    final ObservantHealth? health = ObservantHealth.parse(body);
    return health == null
        ? const ObservantFailed(NotAnObservant())
        : ObservantConnected(name: health.name, version: health.version);
  }

  /// The start of an error body, enough for ObservANT's one-line reasons.
  static String _excerpt(String body) {
    final String line = body.trim().split('\n').first;
    return line.length <= 160 ? line : '${line.substring(0, 160)}…';
  }

  void _set(ObservantConnectionStatus status) {
    _status = status;
    notifyListeners();
  }
}

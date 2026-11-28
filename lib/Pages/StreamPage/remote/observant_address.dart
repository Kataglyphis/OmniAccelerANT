/// Why a typed ObservANT address was refused; the panel names each in its own words.
enum ObservantAddressProblem {
  /// Not a URL at all, such as a space in the host.
  notUrl,

  /// No `http://` or `https://` in front, or another scheme such as `ws://`.
  scheme,

  /// A scheme with no host, such as `http://`.
  noHost,

  /// A user or password in the URL, which `fetch` refuses and a page must not keep.
  credentials,

  /// A path, query or fragment: ObservANT is an origin, as its `peers` are.
  path,

  /// A port outside 1 to 65535.
  port,
}

/// What a typed address comes to: nothing (the page's own ObservANT), an origin, or the problem with it.
sealed class ObservantAddressCheck {
  const ObservantAddressCheck();
}

/// The field is empty: the page asks the ObservANT that served it, as before there was a field.
final class ObservantAddressEmpty extends ObservantAddressCheck {
  const ObservantAddressEmpty();
}

/// A usable address, as the origin `scheme://host[:port]` every request is resolved against.
final class ObservantAddressValid extends ObservantAddressCheck {
  const ObservantAddressValid(this.origin);

  final Uri origin;
}

/// A refused address and why.
final class ObservantAddressInvalid extends ObservantAddressCheck {
  const ObservantAddressInvalid(this.problem);

  final ObservantAddressProblem problem;
}

/// A scheme and `//` first: `192.0.2.10:8080` does not parse at all, and `catcam.local:8080` parses with a scheme `catcam.local`.
final RegExp _schemeInFront = RegExp(
  r'^[a-z][a-z0-9+.-]*://',
  caseSensitive: false,
);

/// Checks a typed ObservANT address; a trailing `/` is the only path it takes, and the default port is dropped.
ObservantAddressCheck checkObservantAddress(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return const ObservantAddressEmpty();
  if (!_schemeInFront.hasMatch(trimmed)) {
    return const ObservantAddressInvalid(ObservantAddressProblem.scheme);
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return const ObservantAddressInvalid(ObservantAddressProblem.notUrl);
  }
  final String scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return const ObservantAddressInvalid(ObservantAddressProblem.scheme);
  }
  if (uri.host.isEmpty) {
    return const ObservantAddressInvalid(ObservantAddressProblem.noHost);
  }
  // Dart percent-encodes a space or a non-ASCII letter into the host, which no browser would look up.
  if (!RegExp(r'^[A-Za-z0-9.:-]+$').hasMatch(uri.host)) {
    return const ObservantAddressInvalid(ObservantAddressProblem.notUrl);
  }
  if (uri.userInfo.isNotEmpty) {
    return const ObservantAddressInvalid(ObservantAddressProblem.credentials);
  }
  if ((uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return const ObservantAddressInvalid(ObservantAddressProblem.path);
  }
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
    return const ObservantAddressInvalid(ObservantAddressProblem.port);
  }
  final int defaultPort = scheme == 'https' ? 443 : 80;
  return ObservantAddressValid(
    Uri(
      scheme: scheme,
      host: uri.host.toLowerCase(),
      port: uri.hasPort && uri.port != defaultPort ? uri.port : null,
    ),
  );
}

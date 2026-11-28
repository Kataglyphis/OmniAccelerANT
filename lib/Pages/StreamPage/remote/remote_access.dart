/// What the browser does with a request from this page to an explicit ObservANT, decided before it is sent:
/// mixed content, and Chrome's Local Network Access (formerly Private Network Access).
library;

/// The address spaces of Local Network Access, most private first; [unknown] is a name only DNS can place.
enum AddressSpace { loopback, local, public, unknown }

/// Whether Chrome asks the visitor before this page may reach the address.
enum LocalNetworkAccess {
  /// The address is no more private than the page: nothing to ask.
  notNeeded,

  /// The address is more private than the page: Chrome asks once, and refuses every request after a "Block".
  prompt,

  /// The address is a name: Chrome asks only if it resolves to a more private address than the page's.
  possible,
}

/// The decision for one page and one address.
final class RemoteAccess {
  const RemoteAccess({
    required this.pageSpace,
    required this.targetSpace,
    required this.mixedContent,
    required this.localNetwork,
  });

  final AddressSpace pageSpace;
  final AddressSpace targetSpace;

  /// An `https` page and an `http` address the browser does not trust: every browser blocks the request unsent.
  final bool mixedContent;

  final LocalNetworkAccess localNetwork;
}

/// Names that only resolve inside a home network, as ObservANT's own `LOCAL_SUFFIXES`.
const List<String> _localSuffixes = <String>[
  '.local',
  '.lan',
  '.home',
  '.internal',
  '.home.arpa',
  '.fritz.box',
];

/// [host]'s address space: IP literals by their ranges, `localhost` and home-network names by their form.
AddressSpace addressSpaceOf(String host) {
  final String name = host.toLowerCase();
  final List<int>? v4 = _ipv4(name);
  if (v4 != null) return _ipv4Space(v4);
  final List<int>? v6 = _ipv6(name);
  if (v6 != null) return _ipv6Space(v6);
  if (name == 'localhost' || name.endsWith('.localhost')) {
    return AddressSpace.loopback;
  }
  if (!name.contains('.') || _localSuffixes.any(name.endsWith)) {
    return AddressSpace.local;
  }
  return AddressSpace.unknown;
}

/// Whether the browser treats `http://[host]` as trustworthy: loopback is never mixed content.
bool trustworthyHttpHost(String host) =>
    addressSpaceOf(host) == AddressSpace.loopback;

/// The decision for a request from [page] to [target], both absolute `http(s)` URLs.
RemoteAccess decideRemoteAccess({required Uri page, required Uri target}) {
  // A page under a public name is the case that matters (the hosted site), so an unplaceable page counts as public.
  final AddressSpace pageSpace = switch (addressSpaceOf(page.host)) {
    AddressSpace.unknown => AddressSpace.public,
    final AddressSpace space => space,
  };
  final AddressSpace targetSpace = addressSpaceOf(target.host);
  final bool mixedContent =
      page.scheme == 'https' &&
      target.scheme == 'http' &&
      !trustworthyHttpHost(target.host);
  return RemoteAccess(
    pageSpace: pageSpace,
    targetSpace: targetSpace,
    mixedContent: mixedContent,
    localNetwork: _localNetwork(pageSpace, targetSpace),
  );
}

LocalNetworkAccess _localNetwork(AddressSpace page, AddressSpace target) {
  if (page == AddressSpace.loopback) return LocalNetworkAccess.notNeeded;
  if (target == AddressSpace.unknown) return LocalNetworkAccess.possible;
  return _rank(target) < _rank(page)
      ? LocalNetworkAccess.prompt
      : LocalNetworkAccess.notNeeded;
}

int _rank(AddressSpace space) => switch (space) {
  AddressSpace.loopback => 0,
  AddressSpace.local => 1,
  AddressSpace.public || AddressSpace.unknown => 2,
};

List<int>? _ipv4(String host) {
  if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return null;
  final List<int> parts = host.split('.').map(int.parse).toList();
  return parts.every((int p) => p <= 255) ? parts : null;
}

List<int>? _ipv6(String host) {
  if (!host.contains(':')) return null;
  try {
    return Uri.parseIPv6Address(host);
  } on FormatException {
    return null;
  }
}

AddressSpace _ipv4Space(List<int> a) {
  if (a[0] == 127 || a[0] == 0) return AddressSpace.loopback;
  final bool local =
      a[0] == 10 ||
      (a[0] == 100 && a[1] >= 64 && a[1] < 128) ||
      (a[0] == 172 && a[1] >= 16 && a[1] < 32) ||
      (a[0] == 192 && a[1] == 168) ||
      (a[0] == 198 && (a[1] == 18 || a[1] == 19)) ||
      (a[0] == 169 && a[1] == 254);
  return local ? AddressSpace.local : AddressSpace.public;
}

AddressSpace _ipv6Space(List<int> b) {
  final bool zeroPrefix = b.take(10).every((int x) => x == 0);
  if (zeroPrefix && b[10] == 0 && b[11] == 0) {
    final bool loopback =
        b.sublist(12, 15).every((int x) => x == 0) && b[15] == 1;
    if (loopback) return AddressSpace.loopback;
  }
  // An IPv4-mapped address (`::ffff:a.b.c.d`) is placed by its IPv4 part.
  if (zeroPrefix && b[10] == 0xff && b[11] == 0xff) {
    return _ipv4Space(b.sublist(12));
  }
  if ((b[0] & 0xfe) == 0xfc || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80)) {
    return AddressSpace.local;
  }
  return AddressSpace.public;
}

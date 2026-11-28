import 'package:omni_accelerant/Pages/StreamPage/remote/remote_access.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_observant.dart';

/// An ObservANT `/healthz` the fake answers by default.
const String fakeHealthz =
    '{"ok":true,"name":"Futtertrog","version":"2.3.4","detection":{"recent":[]}}';

/// A browser for the remote mode: a page address, storage, permission answers in order and probe answers.
class FakeRemoteBrowser implements RemoteObservantPlatform {
  FakeRemoteBrowser({String page = 'http://127.0.0.1:8000/', this.saved})
    : page = Uri.parse(page);

  @override
  final Uri page;
  String? saved;
  final List<Uri> probed = <Uri>[];
  final List<Duration> timeouts = <Duration>[];
  final List<AddressSpace> asked = <AddressSpace>[];

  /// The permission before the probe, then after it.
  List<LocalNetworkPermission> permissions = <LocalNetworkPermission>[
    LocalNetworkPermission.unsupported,
  ];
  Future<ProbeResult> Function(Uri url) answer = (_) async =>
      const ProbeAnswer(200, fakeHealthz);

  @override
  String? loadAddress() => saved;

  @override
  void saveAddress(String? origin) => saved = origin;

  @override
  Future<LocalNetworkPermission> localNetworkPermission(
    AddressSpace space,
  ) async {
    asked.add(space);
    return permissions.length > 1
        ? permissions.removeAt(0)
        : permissions.single;
  }

  @override
  Future<ProbeResult> probe(Uri url, Duration timeout) {
    probed.add(url);
    timeouts.add(timeout);
    return answer(url);
  }
}

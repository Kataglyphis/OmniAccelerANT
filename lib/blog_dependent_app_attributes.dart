import 'package:anthology/blog_dependent_app_attributes.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// Omni's blog attributes: the shared three fields plus the WebRTC settings
/// that only this app's stream page consumes.
///
/// Subclassing keeps [WebRTCSettings] - an Omni-only type - out of the shared
/// package, while the shared landing and block-overview pages keep accepting
/// this instance through their [BlogDependentAppAttributes] parameter.
class OmniBlogDependentAppAttributes extends BlogDependentAppAttributes {
  WebRTCSettings webrtcSettings;

  OmniBlogDependentAppAttributes({
    required super.blogDependentScreenConfigurations,
    required super.twoCentsConfigs,
    required super.blockSettings,
    required this.webrtcSettings,
  });
}

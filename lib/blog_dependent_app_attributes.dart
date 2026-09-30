import 'package:anthology/blog_dependent_app_attributes.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// The shared blog attributes plus the Omni-only [WebRTCSettings], kept out of the shared package.
class OmniBlogDependentAppAttributes extends BlogDependentAppAttributes {
  WebRTCSettings webrtcSettings;

  OmniBlogDependentAppAttributes({
    required super.blogDependentScreenConfigurations,
    required super.twoCentsConfigs,
    required super.blockSettings,
    required this.webrtcSettings,
  });
}

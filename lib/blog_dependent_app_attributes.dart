import 'package:anthology/blog_dependent_app_attributes.dart';
import 'package:anthology/my_two_cents_config.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// The shared blog attributes plus the Omni-only [WebRTCSettings], kept out of the shared package.
class OmniBlogDependentAppAttributes extends BlogDependentAppAttributes {
  WebRTCSettings webrtcSettings;

  // No media reviews here; the shared attributes carry them for jotrockenmitlocken.
  OmniBlogDependentAppAttributes({
    required super.blogDependentScreenConfigurations,
    required super.blockSettings,
    required this.webrtcSettings,
  }) : super(twoCentsConfigs: <MyTwoCentsConfig>[]);
}

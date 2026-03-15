import 'package:kataglyphis_inference_engine/Pages/blog_dependent_screen_configurations.dart';
import 'package:kataglyphis_inference_engine/blog_page_config.dart';
import 'package:kataglyphis_inference_engine/my_two_cents_config.dart';
import 'package:kataglyphis_inference_engine/settings/webrtc_settings.dart';

class BlogDependentAppAttributes {
  List<MyTwoCentsConfig> twoCentsConfigs;
  List<BlogPageConfig> blockSettings;
  WebRTCSettings webrtcSettings;

  BlogDependentScreenConfigurations blogDependentScreenConfigurations;

  BlogDependentAppAttributes({
    required this.blogDependentScreenConfigurations,
    required this.twoCentsConfigs,
    required this.blockSettings,
    required this.webrtcSettings,
  });
}

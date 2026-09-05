import 'package:omni_accelerant/Pages/blog_dependent_screen_configurations.dart';
import 'package:omni_accelerant/blog_page_config.dart';
import 'package:omni_accelerant/my_two_cents_config.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

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

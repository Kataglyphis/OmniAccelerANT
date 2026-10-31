import 'package:omni_accelerant/Pages/AboutMePage/about_me_page_navbar_config.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_navbar_config.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings_navbar_config.dart';
import 'package:omni_accelerant/Pages/DevicePage/device_page_navbar_config.dart';
import 'package:omni_accelerant/Pages/DataPage/BlockOverviewPage/block_overview_page_config.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_page_navbar_config.dart';
import 'package:anthology/Pages/ErrorPage/error_page_stateful_branch_info_provider.dart';
import 'package:omni_accelerant/Pages/LandingPage/landing_page_navbar_page_config.dart';
import 'package:anthology/Pages/blog_dependent_screen_configurations.dart';
import 'package:anthology/blog_page_config.dart';
import 'package:anthology/Pages/Footer/default_footer_pages.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';
import 'package:anthology/my_two_cents_config.dart';
import 'package:anthology/Pages/navbar_page_config.dart';
import 'package:anthology/Pages/stateful_branch_info_provider.dart';
import 'package:anthology/Routing/screen_configurations.dart';

class OmniScreenConfigurations extends ScreenConfigurations
    with BlogDependentScreenConfigurations {
  List<BlogPageConfig> blogPageConfigs;
  OmniScreenConfigurations({required this.blogPageConfigs});

  @override
  List<NavBarPageConfig> getNavRailPagesConfig() {
    return [
      StreamPageNavBarConfig(),
      CameraSettingsNavBarConfig(),
      DeviceNavBarConfig(),
      AiPlaygroundNavBarConfig(),
      LandingPageNavBarConfig(),
      AboutMePageNavBarConfig(),
    ];
  }

  @override
  List<StatefulBranchInfoProvider> getErrorPagesConfig() {
    return [ErrorPageStatefulBranchInfoProvider()];
  }

  @override
  List<FooterPageConfig> getFooterPagesConfig() => defaultFooterPageConfigs();

  // from here on everything is blog dependend
  @override
  List<BlogPageConfig> getBlogPagesConfig() {
    return blogPageConfigs;
  }

  // No media reviews here; the shared mixin asks every site for its list.
  @override
  List<MyTwoCentsConfig> getMediaCriticsPagesConfig() =>
      const <MyTwoCentsConfig>[];

  @override
  List<StatefulBranchInfoProvider> getDataPagesConfig() {
    return [BlockOverviewPageConfig()];
  }
}

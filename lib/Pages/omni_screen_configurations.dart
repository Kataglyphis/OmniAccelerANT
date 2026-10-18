import 'package:omni_accelerant/Pages/AboutMePage/about_me_page_navbar_config.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings_navbar_config.dart';
import 'package:omni_accelerant/Pages/DevicePage/device_page_navbar_config.dart';
import 'package:omni_accelerant/Pages/DataPage/BlockOverviewPage/block_overview_page_config.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_page_navbar_config.dart';
import 'package:anthology/Pages/ErrorPage/error_page_stateful_branch_info_provider.dart';
import 'package:omni_accelerant/Pages/Footer/Pages/configs/contact_footer_config.dart';
import 'package:omni_accelerant/Pages/Footer/Pages/configs/cookie_declaration_footer_config.dart';
import 'package:omni_accelerant/Pages/Footer/Pages/configs/copyright_footer_config.dart';
import 'package:omni_accelerant/Pages/Footer/Pages/configs/declaration_on_accessibility_footer_config.dart';
import 'package:omni_accelerant/Pages/Footer/Pages/configs/imprint_footer_config.dart';
import 'package:omni_accelerant/Pages/Footer/Pages/configs/open_source_licenses_footer_config.dart';
import 'package:omni_accelerant/Pages/Footer/Pages/configs/privacy_policy_config.dart';
import 'package:omni_accelerant/Pages/LandingPage/landing_page_navbar_page_config.dart';
import 'package:anthology/Pages/blog_dependent_screen_configurations.dart';
import 'package:anthology/blog_page_config.dart';
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
  List<StatefulBranchInfoProvider> getAllPagesConfigs() {
    List<StatefulBranchInfoProvider> pagesConfigs = [];
    for (StatefulBranchInfoProvider navRailPageConfig
        in getNavRailPagesConfig()) {
      pagesConfigs.add(navRailPageConfig);
    }
    for (StatefulBranchInfoProvider navRailPageConfig
        in getFooterPagesConfig()) {
      pagesConfigs.add(navRailPageConfig);
    }
    for (StatefulBranchInfoProvider blogPageConfig in getBlogPagesConfig()) {
      pagesConfigs.add(blogPageConfig);
    }
    for (StatefulBranchInfoProvider errorPageConfig in getErrorPagesConfig()) {
      pagesConfigs.add(errorPageConfig);
    }
    for (StatefulBranchInfoProvider dataPageConfig in getDataPagesConfig()) {
      pagesConfigs.add(dataPageConfig);
    }
    return pagesConfigs;
  }

  @override
  List<NavBarPageConfig> getNavRailPagesConfig() {
    return [
      StreamPageNavBarConfig(),
      CameraSettingsNavBarConfig(),
      DeviceNavBarConfig(),
      LandingPageNavBarConfig(),
      AboutMePageNavBarConfig(),
    ];
  }

  @override
  List<StatefulBranchInfoProvider> getErrorPagesConfig() {
    return [ErrorPageStatefulBranchInfoProvider()];
  }

  @override
  List<FooterPageConfig> getFooterPagesConfig() {
    return [
      ImprintFooterConfig(),
      ContactFooterConfig(),
      PrivacyPolicyFooterConfig(),
      CookieDeclarationFooterConfig(),
      DeclarationOnAccessibilityFooterConfig(),
      CopyRightFooterConfig(),
      OpenSourceLicensesFooterConfig(),
    ];
  }

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

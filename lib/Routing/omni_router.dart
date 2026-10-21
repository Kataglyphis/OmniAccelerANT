import 'package:flutter/material.dart';
import 'package:omni_accelerant/Pages/AboutMePage/about_me_page.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings_page.dart';
import 'package:omni_accelerant/Pages/DevicePage/device_page.dart';
import 'package:anthology/Pages/DataPage/BlockOverviewPage/block_overview_page.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_page.dart';
import 'package:omni_accelerant/blog_dependent_app_attributes.dart';
import 'package:anthology/Pages/LandingPage/landing_page.dart';
import 'package:anthology/Routing/router_creater.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/Pages/stateful_branch_info_provider.dart';

/// All OmniAccelerANT routes, each paired with its [StatefulBranchInfoProvider]; the footer, blog and error pages come from ANThology's helpers.
class OmniRoutes extends RoutesCreator {
  OmniBlogDependentAppAttributes blogDependentAppAttributes;

  OmniRoutes({required this.blogDependentAppAttributes});

  @override
  List<(Widget, StatefulBranchInfoProvider)> getAllPagesWithConfigs(
    AppAttributes appAttributes,
  ) {
    final screens =
        blogDependentAppAttributes.blogDependentScreenConfigurations;
    return [
      ..._getNavBarPagesAndConfigs(appAttributes),
      ...footerPagesWithConfigs(appAttributes),
      ...blogPagesWithConfigs(appAttributes, screens.getBlogPagesConfig()),
      ...pairPagesWithConfigs([
        BlockOverviewPage(
          footer: getFooter(appAttributes),
          appAttributes: appAttributes,
          blogDependentAppAttributes: blogDependentAppAttributes,
        ),
      ], screens.getDataPagesConfig()),
      ...errorPagesWithConfigs(appAttributes),
    ];
  }

  List<(Widget, StatefulBranchInfoProvider)> _getNavBarPagesAndConfigs(
    AppAttributes appAttributes,
  ) {
    return pairPagesWithConfigs([
      StreamPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
        webrtcSettings: blogDependentAppAttributes.webrtcSettings,
      ),
      CameraSettingsPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
      ),
      DevicePage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
      ),
      LandingPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
        blogDependentAppAttributes: blogDependentAppAttributes,
      ),
      AboutMePage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
      ),
    ], appAttributes.screenConfigurations.getNavRailPagesConfig());
  }
}

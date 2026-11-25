import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_accelerant/app_pages.dart';
import 'package:anthology/Pages/DataPage/BlockOverviewPage/block_overview_page.dart';
import 'package:omni_accelerant/blog_dependent_app_attributes.dart';
import 'package:anthology/Routing/router_creater.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/Pages/stateful_branch_info_provider.dart';
import 'package:omni_accelerant/src/boot/url_options.dart';

/// All OmniAccelerANT routes, each paired with its [StatefulBranchInfoProvider]; the footer, blog and error pages come from ANThology's helpers.
class OmniRoutes extends RoutesCreator {
  OmniBlogDependentAppAttributes blogDependentAppAttributes;

  OmniRoutes({required this.blogDependentAppAttributes});

  /// Opens on [hostedStartRoute] when the build names one: the camera page would poll a server the static host lacks.
  @override
  GoRouter getRouterConfig(
    AppAttributes appAttributes,
    AnimationController controller,
    void Function(int value) handleChangedPageIndex,
    int currentPageIndex,
  ) {
    return super.getRouterConfig(
      appAttributes,
      controller,
      handleChangedPageIndex,
      startPageIndex(hostedStartRoute, currentPageIndex),
    );
  }

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
      for (final page in appPages)
        page.build(
          getFooter(appAttributes),
          appAttributes,
          blogDependentAppAttributes,
        ),
    ], appPages);
  }
}

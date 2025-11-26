import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/AboutMePage/about_me_page.dart';
import 'package:kataglyphis_inference_engine/Pages/Blog/blog_page.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/BlockOverviewPage/block_overview_page.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/BooksPage/books_page.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/FilmsPage/films_page.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/GamesPage/games_page.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/data_page.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/media_critics_page.dart';
import 'package:kataglyphis_inference_engine/Pages/StreamPage/stream_page.dart';
import 'package:kataglyphis_inference_engine/Pages/ErrorPage/error_page.dart';
import 'package:kataglyphis_inference_engine/blog_dependent_app_attributes.dart';

import 'package:jotrockenmitlockenrepo/Pages/Footer/footer_page.dart';
import 'package:kataglyphis_inference_engine/Pages/LandingPage/landing_page.dart';
import 'package:kataglyphis_inference_engine/Pages/DataPage/QuotesPage/quotes_page.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer_page_config.dart';
import 'package:kataglyphis_inference_engine/blog_page_config.dart';
import 'package:kataglyphis_inference_engine/my_two_cents_config.dart';
import 'package:jotrockenmitlockenrepo/Routing/router_creater.dart';

import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:jotrockenmitlockenrepo/Pages/stateful_branch_info_provider.dart';

class JotrockenMitLockenRoutes extends RoutesCreator {
  BlogDependentAppAttributes blogDependentAppAttributes;

  JotrockenMitLockenRoutes({required this.blogDependentAppAttributes});

  @override
  List<(Widget, StatefulBranchInfoProvider)> getAllPagesWithConfigs(
    AppAttributes appAttributes,
  ) {
    List<(Widget, StatefulBranchInfoProvider)> allPagesAndConfigs = [];
    allPagesAndConfigs += _getNavBarPagesAndConfigs(appAttributes);
    allPagesAndConfigs += _getFooterPagesAndConfigs(appAttributes);
    allPagesAndConfigs += _getBlogPagesAndConfigs(appAttributes);
    allPagesAndConfigs += _getDataPagesAndConfigs(appAttributes);
    allPagesAndConfigs += _getMediaCriticsPagesAndConfigs(appAttributes);
    allPagesAndConfigs += _getErrorPagesAndConfigs(appAttributes);

    return allPagesAndConfigs;
  }

  List<(Widget, StatefulBranchInfoProvider)> _getErrorPagesAndConfigs(
    appAttributes,
  ) {
    List<StatefulBranchInfoProvider> errorPageConfigs = appAttributes
        .screenConfigurations
        .getErrorPagesConfig();
    List<Widget> errorPages = [
      ErrorPage(footer: getFooter(appAttributes), appAttributes: appAttributes),
    ];
    assert(errorPages.length == errorPageConfigs.length);
    return [
      for (int i = 0; i < errorPages.length; i += 1)
        (errorPages[i], errorPageConfigs[i]),
    ];
  }

  List<(Widget, StatefulBranchInfoProvider)> _getDataPagesAndConfigs(
    AppAttributes appAttributes,
  ) {
    List<StatefulBranchInfoProvider> dataPagesConfigs =
        blogDependentAppAttributes.blogDependentScreenConfigurations
            .getDataPagesConfig();
    List<Widget> dataPages = [
      QuotesPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
      ),
      BooksPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
        blogDependentAppAttributes: blogDependentAppAttributes,
      ),
      FilmsPage(footer: getFooter(appAttributes), appAttributes: appAttributes),
      GamesPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
        blogDependentAppAttributes: blogDependentAppAttributes,
      ),
      BlockOverviewPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
        blogDependentAppAttributes: blogDependentAppAttributes,
      ),
    ];
    assert(dataPages.length == dataPagesConfigs.length);
    return [
      for (int i = 0; i < dataPages.length; i += 1)
        (dataPages[i], dataPagesConfigs[i]),
    ];
  }

  List<(Widget, StatefulBranchInfoProvider)> _getNavBarPagesAndConfigs(
    AppAttributes appAttributes,
  ) {
    List<StatefulBranchInfoProvider> navBarPageConfigs = appAttributes
        .screenConfigurations
        .getNavRailPagesConfig();
    List<Widget> navBarPages = [
      LandingPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
        blogDependentAppAttributes: blogDependentAppAttributes,
      ),
      AboutMePage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
      ),
      DataPage(footer: getFooter(appAttributes), appAttributes: appAttributes),
      StreamPage(
        footer: getFooter(appAttributes),
        appAttributes: appAttributes,
      ),
    ];
    assert(navBarPages.length == navBarPageConfigs.length);
    return [
      for (int i = 0; i < navBarPages.length; i += 1)
        (navBarPages[i], navBarPageConfigs[i]),
    ];
  }

  List<(Widget, StatefulBranchInfoProvider)> _getMediaCriticsPagesAndConfigs(
    AppAttributes appAttributes,
  ) {
    List<MyTwoCentsConfig> blogPagesConfigs = blogDependentAppAttributes
        .blogDependentScreenConfigurations
        .getMediaCriticsPagesConfig();
    List<(Widget, StatefulBranchInfoProvider)> footerPages = blogPagesConfigs
        .map(
          (pageConfig) => (
            MediaCriticsPage(
              footer: getFooter(appAttributes),
              appAttributes: appAttributes,
              mediaCriticsPageConfig: pageConfig,
            ),
            pageConfig,
          ),
        )
        .toList();

    return footerPages;
  }

  List<(Widget, StatefulBranchInfoProvider)> _getBlogPagesAndConfigs(
    AppAttributes appAttributes,
  ) {
    List<BlogPageConfig> blogPagesConfigs = blogDependentAppAttributes
        .blogDependentScreenConfigurations
        .getBlogPagesConfig();
    List<(Widget, StatefulBranchInfoProvider)> footerPages = blogPagesConfigs
        .map(
          (pageConfig) => (
            BlogPage(
              footer: getFooter(appAttributes),
              appAttributes: appAttributes,
              blogPageConfig: pageConfig,
            ),
            pageConfig,
          ),
        )
        .toList();

    return footerPages;
  }

  List<(Widget, StatefulBranchInfoProvider)> _getFooterPagesAndConfigs(
    AppAttributes appAttributes,
  ) {
    List<FooterPageConfig> footerPagesConfigs = appAttributes
        .screenConfigurations
        .getFooterPagesConfig();
    List<(Widget, StatefulBranchInfoProvider)> footerPages = footerPagesConfigs
        .map(
          (pageConfig) => (
            FooterPage(
              footer: getFooter(appAttributes),
              appAttributes: appAttributes,
              filePathDe: pageConfig.getFilePathDe(),
              filePathEn: pageConfig.getFilePathEn(),
            ),
            pageConfig,
          ),
        )
        .toList();

    return footerPages;
  }

  @override
  Footer getFooter(AppAttributes appAttributes) {
    return Footer(
      footerPagesConfigs: appAttributes.screenConfigurations
          .getFooterPagesConfig(),
      userSettings: appAttributes.userSettings,
      footerConfig: appAttributes.footerConfig,
    );
  }
}

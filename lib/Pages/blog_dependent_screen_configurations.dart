import 'package:omni_accelerant/blog_page_config.dart';
import 'package:omni_accelerant/my_two_cents_config.dart';
import 'package:anthology/Pages/stateful_branch_info_provider.dart';

mixin BlogDependentScreenConfigurations {
  List<StatefulBranchInfoProvider> getDataPagesConfig();
  List<BlogPageConfig> getBlogPagesConfig();
  List<MyTwoCentsConfig> getMediaCriticsPagesConfig();
}

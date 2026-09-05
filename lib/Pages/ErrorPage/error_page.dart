import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/Layout/ResponsiveDesign/single_page.dart';
import 'package:omni_accelerant/Pages/ErrorPage/error_page_widget.dart';
import 'package:anthology/app_attributes.dart';

class ErrorPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;
  const ErrorPage({
    super.key,
    required this.appAttributes,
    required this.footer,
  });

  @override
  State<StatefulWidget> createState() => ErrorPageState();
}

class ErrorPageState extends State<ErrorPage> {
  @override
  Widget build(BuildContext context) {
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: const [ErrorPageWidget()],
    );
  }
}

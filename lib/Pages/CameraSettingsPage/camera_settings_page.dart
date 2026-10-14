import 'package:flutter/material.dart';
import 'package:anthology/Layout/ResponsiveDesign/single_page.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/app_attributes.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings.dart';
import 'package:omni_accelerant/Pages/StreamPage/observant_api_stub.dart'
    if (dart.library.js_interop) 'package:omni_accelerant/Pages/StreamPage/observant_api_web.dart';

/// ObservANT's settings, on a page of their own: only an ObservANT camera's own page has them to change.
class CameraSettingsPage extends StatelessWidget {
  const CameraSettingsPage({
    super.key,
    required this.appAttributes,
    required this.footer,
  });

  final AppAttributes appAttributes;
  final Footer footer;

  @override
  Widget build(BuildContext context) {
    return SinglePage(
      footer: footer,
      appAttributes: appAttributes,
      showMediumSizeLayout: appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: appAttributes.showLargeSizeLayout,
      children: const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: CameraSettingsPanel(
              fetchSettings: fetchObservantSettings,
              saveSettings: saveObservantSettings,
              fetchHealthz: fetchHealthz,
            ),
          ),
        ),
      ],
    );
  }
}

// The settings main() reads before the first frame, as shipped; VM only, as a Chrome test serves no app assets to rootBundle.
@TestOn('vm')
library;

import 'package:anthology/SocialMedia/Settings/social_media_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the shipped settings load, and every blog post names an asset that exists', () async {
    final (appSettings, userSettings, blogConfigs, webrtcSettings) =
        await loadAppSettings();

    expect(appSettings.appTitleEn, 'OmniAccelerANT');
    expect(
      appSettings.supportedLocales,
      unorderedEquals(
        AppLocalizations.supportedLocales.map((l) => l.languageCode),
      ),
      reason: 'a language the app offers must have its translations, and the other way round',
    );

    expect(blogConfigs, isNotEmpty);
    final routes = blogConfigs.map((c) => c.routingName).toList();
    expect(
      routes.toSet(),
      hasLength(routes.length),
      reason: 'two posts on one route: $routes',
    );
    for (final config in blogConfigs) {
      expect(config.routingName, startsWith('/'));
      final ByteData post = await rootBundle.load(config.filePath);
      expect(post.lengthInBytes, greaterThan(0), reason: config.filePath);
    }

    // A network without an icon in ANThology renders as an empty footer button.
    expect(socialNetworksWithoutIcon(userSettings), isEmpty);

    // Host-relative, so one build serves a board under any address; only web resolves it to wss://<host>.
    expect(webrtcSettings.signalingServerUrl, endsWith('/webrtc-ws'));
    expect(webrtcSettings.texture.width, isPositive);
    expect(webrtcSettings.texture.height, isPositive);
  });
}

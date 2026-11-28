// The web build's licences page over a fixture inventory, in English and German, and the route that shows it.
import 'dart:convert';

import 'package:anthology/Pages/Footer/default_footer_config.dart';
import 'package:anthology/Pages/Footer/default_footer_pages.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/Pages/Footer/open_source_licenses_page.dart';
import 'package:anthology/Pages/Home/default_home_config.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/app_settings.dart';
import 'package:anthology/constants.dart';
import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:anthology/material_compatibility.dart';
import 'package:anthology/user_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_accelerant/Pages/WebLicensesPage/web_licenses_page.dart';
import 'package:omni_accelerant/Pages/omni_screen_configurations.dart';
import 'package:omni_accelerant/Routing/omni_router.dart';
import 'package:omni_accelerant/blog_dependent_app_attributes.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';
import 'package:omni_accelerant/web_license_inventory.dart';

const String _asyncText = 'BSD 3-Clause, the Dart project authors';
const String _ortText = 'MIT License, Microsoft Corporation';

/// Serves [entries] by key; a missing key fails as a missing web asset does.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.entries);

  final Map<String, String> entries;
  final List<String> loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final String? text = entries[key];
    if (text == null) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(utf8.encode(text));
  }
}

/// An inventory as the generator writes it: three groups, four components, texts in one chunk.
Map<String, String> _inventory() {
  Map<String, Object> text(String title, String sha) => <String, Object>{
    'title': title,
    'sha256': sha,
    'file': 'texts-1.json',
  };
  final Map<String, Object> index = <String, Object>{
    'schema': 1,
    'file_count': 7,
    'groups': <String, int>{'engine': 1, 'dart': 2, 'ort': 1},
    'components': <Map<String, Object>>[
      <String, Object>{
        'group': 'engine',
        'id': 'flutter-web-engine',
        'name': 'Flutter web engine (CanvasKit, Skwasm) and build output',
        'license': 'BSD-3-Clause',
        'files': <String>['canvaskit/canvaskit.wasm', 'flutter.js'],
        'includes': <String>['angle', 'harfbuzz', 'icu', 'skia'],
        'texts': <Object>[
          text('angle', 'c' * 64),
          text('harfbuzz', 'd' * 64),
          text('icu', 'f' * 64),
          text('skia', 'e' * 64),
        ],
      },
      <String, Object>{
        'group': 'dart',
        'id': 'dart:async',
        'name': 'async',
        'version': '2.13.0',
        'source': 'https://pub.dev/packages/async',
        'files': <String>['main.dart.js', 'main.dart.wasm'],
        'texts': <Object>[text('async', 'a' * 64)],
      },
      <String, Object>{
        'group': 'dart',
        'id': 'dart:web',
        'name': 'web',
        'files': <String>['main.dart.js'],
        'texts': <Object>[text('web', 'a' * 64)],
      },
      <String, Object>{
        'group': 'ort',
        'id': 'ort-web:jspi',
        'name': 'ONNX Runtime Web (jspi)',
        'version': '1.24.0',
        'license': 'MIT',
        'files': <String>[
          'ort/1.24.0-0123456789abcdef/LICENSE',
          'ort/manifest.json',
        ],
        'texts': <Object>[text('LICENSE', 'b' * 64)],
      },
    ],
  };
  return <String, String>{
    webLicenseIndexKey: jsonEncode(index),
    'web-licenses/texts-1.json': jsonEncode(<String, String>{
      'a' * 64: _asyncText,
      'b' * 64: _ortText,
      'c' * 64: 'BSD, ANGLE',
      'd' * 64: 'Old MIT, HarfBuzz',
      'e' * 64: 'BSD, Google',
      'f' * 64: 'Unicode License V3, ICU',
    }),
  };
}

UserSettings _userSettings() => UserSettings(
  socialMediaLinksConfig: const {},
  businessEmail: 'test@example.com',
  myQuotation: '',
  firstName: 'Jane',
  lastName: 'Doe',
  aboutMeFileDe: 'about_de.md',
  aboutMeFileEn: 'about_en.md',
  assetPathImgOfMe: 'me.jpg',
);

AppAttributes _appAttributes() => AppAttributes(
  footerConfig: DefaultFooterConfig(),
  homeConfig: DefaultHomeConfig(),
  appSettings: AppSettings(
    appNameDe: 'OmniAccelerANT',
    appNameEn: 'OmniAccelerANT',
    appTitleDe: 'OmniAccelerANT',
    appTitleEn: 'OmniAccelerANT',
    disableFooter: true,
  ),
  userSettings: _userSettings(),
  screenConfigurations: OmniScreenConfigurations(blogPageConfigs: const []),
  railAnimation: CurvedAnimation(
    parent: kAlwaysCompleteAnimation,
    curve: Curves.linear,
  ),
  showMediumSizeLayout: false,
  showLargeSizeLayout: false,
  colorSelected: ColorSeed.baseColor,
  useLightMode: true,
);

/// The page alone in [locale], footer off, over [bundle].
Future<void> _pumpPage(
  WidgetTester tester,
  AssetBundle bundle,
  Locale locale,
) async {
  tester.view.physicalSize = const Size(1280, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final AppAttributes appAttributes = _appAttributes();
  await tester.pumpWidget(
    MaterialApp(
      builder: anthologyMaterialBuilder,
      locale: locale,
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...anthologyLocalizationsDelegates,
        AnthologyLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: WebLicensesPage(
          key: ValueKey<Locale>(locale),
          footer: Footer(
            footerPagesConfigs: const [],
            userSettings: appAttributes.userSettings,
            footerConfig: appAttributes.footerConfig,
          ),
          appAttributes: appAttributes,
          bundle: bundle,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('English: groups, counts and a text loaded on opening', (
    tester,
  ) async {
    final _MapBundle bundle = _MapBundle(_inventory());
    await _pumpPage(tester, bundle, const Locale('en'));

    expect(
      find.textContaining('Everything this web app ships'),
      findsOneWidget,
    );
    expect(find.text('7 files in 4 components'), findsOneWidget);
    expect(find.text('Flutter web engine (1)'), findsOneWidget);
    expect(find.text('Dart packages (2)'), findsOneWidget);
    expect(find.text('ONNX Runtime Web (1)'), findsOneWidget);
    expect(find.text('async 2.13.0'), findsOneWidget);
    expect(find.text('ONNX Runtime Web (jspi) 1.24.0'), findsOneWidget);
    expect(bundle.loaded, isNot(contains('web-licenses/texts-1.json')));

    await tester.tap(find.text('async 2.13.0'));
    await tester.pumpAndSettle();
    expect(find.text('Shipped files (2)'), findsOneWidget);
    expect(find.text('main.dart.js\nmain.dart.wasm'), findsOneWidget);
    expect(find.text('Source: https://pub.dev/packages/async'), findsOneWidget);
    expect(find.text(_asyncText), findsOneWidget);

    await tester.tap(
      find.text('Flutter web engine (CanvasKit, Skwasm) and build output'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Notices included: angle, harfbuzz, icu, skia'),
      findsOneWidget,
    );
    // Four texts fold into tiles of their own; one opens without the others.
    expect(find.text('icu'), findsOneWidget);
    expect(find.text('Unicode License V3, ICU'), findsNothing);
    await tester.tap(find.text('icu'));
    await tester.pumpAndSettle();
    expect(find.text('Unicode License V3, ICU'), findsOneWidget);
    expect(find.text('BSD, ANGLE'), findsNothing);
  });

  testWidgets('German: the same inventory in German', (tester) async {
    await _pumpPage(tester, _MapBundle(_inventory()), const Locale('de'));

    expect(
      find.textContaining('Alles, was diese Web-App ausliefert'),
      findsOneWidget,
    );
    expect(find.text('7 Dateien in 4 Komponenten'), findsOneWidget);
    expect(find.text('Flutter-Web-Engine (1)'), findsOneWidget);
    expect(find.text('Dart-Pakete (2)'), findsOneWidget);

    await tester.tap(find.text('ONNX Runtime Web (jspi) 1.24.0'));
    await tester.pumpAndSettle();
    expect(find.text('Ausgelieferte Dateien (2)'), findsOneWidget);
    expect(find.text(_ortText), findsOneWidget);
  });

  testWidgets('a build without an inventory says so in both languages', (
    tester,
  ) async {
    await _pumpPage(tester, _MapBundle(<String, String>{}), const Locale('en'));
    expect(
      find.text('This build carries no license inventory of its web files.'),
      findsOneWidget,
    );
    await _pumpPage(tester, _MapBundle(<String, String>{}), const Locale('de'));
    expect(
      find.text(
        'Dieser Build enthält kein Lizenzverzeichnis seiner Web-Dateien.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a text that does not load is named, not hidden', (tester) async {
    final Map<String, String> entries = _inventory()
      ..remove('web-licenses/texts-1.json');
    await _pumpPage(tester, _MapBundle(entries), const Locale('en'));
    await tester.tap(find.text('async 2.13.0'));
    await tester.pumpAndSettle();
    expect(find.text('The license text could not be loaded.'), findsOneWidget);
  });

  test('an inventory of an unknown schema is refused', () {
    expect(
      () => WebLicenseInventory.fromJson(<String, dynamic>{'schema': 2}),
      throwsFormatException,
    );
  });

  test('the licences route shows the web inventory only on the web', () {
    // Inline: a Chrome test serves no app assets to rootBundle.
    final WebRTCSettings webrtcSettings = WebRTCSettings.fromJsonFile(
      <String, dynamic>{
        'signalingServerUrl': '/webrtc-ws',
        'reconnectionTimeoutMs': 5000,
        'stunServers': <String>[],
        'turnServers': <String>[],
        'video': <String, int>{
          'defaultWidth': 1280,
          'defaultHeight': 720,
          'defaultFramerate': 30,
          'defaultBitrateKbps': 2000,
        },
        'texture': <String, int>{'width': 640, 'height': 480},
        'android': <String, int>{'width': 320, 'height': 240, 'fps': 15},
      },
    );
    final AppAttributes appAttributes = _appAttributes();
    Widget licencesPage(bool web) {
      final OmniRoutes routes = OmniRoutes(
        blogDependentAppAttributes: OmniBlogDependentAppAttributes(
          blogDependentScreenConfigurations: OmniScreenConfigurations(
            blogPageConfigs: const [],
          ),
          blockSettings: const [],
          webrtcSettings: webrtcSettings,
        ),
        webLicenses: web,
      );
      return routes
          .footerPagesWithConfigs(appAttributes)
          .firstWhere(
            (page) => page.$2.getRoutingName() == openSourceLicensesRoute,
          )
          .$1;
    }

    expect(licencesPage(true), isA<WebLicensesPage>());
    expect(licencesPage(false), isA<OpenSourceLicensesPage>());
  });
}

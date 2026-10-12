import 'package:flutter/services.dart';

/// Loads the theme's Roboto, so text measures as in the app: the test font's square glyphs overflow rows real text fits.
Future<void> loadRealFonts() async {
  const String dir = 'packages/anthology/assets/fonts/Roboto';
  final FontLoader roboto = FontLoader('packages/anthology/Roboto');
  for (final String face in <String>['Regular', 'Medium', 'Bold', 'Italic']) {
    roboto.addFont(rootBundle.load('$dir/Roboto-$face.ttf'));
  }
  await roboto.load();
}

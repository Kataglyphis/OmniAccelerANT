// A network the settings link to without an icon in ANThology's map renders as an empty footer button.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:anthology/SocialMedia/Settings/social_media_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every social link in the user settings has an icon', () {
    final Map<String, dynamic> settings = jsonDecode(
      File('assets/settings/user_settings/global_user_settings.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final Iterable<String> networks =
        (settings['socialMediaLinksConfig'] as Map<String, dynamic>).keys;
    expect(networks, isNotEmpty);
    expect(
      networks.where(
        (String network) => !socialMediaIcons.containsKey(network),
      ),
      isEmpty,
      reason: "ANThology's socialMediaIcons has no icon for these networks",
    );
  });
}

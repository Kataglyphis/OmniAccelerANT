import 'package:web/web.dart' as web;

/// The overlay markup lives in `web/index.html`; these are its hooks.
const String _loadingSelector = '.loading';
const String _backgroundId = 'background-animation';

void dismissBootOverlayImpl() {
  web.document.querySelector(_loadingSelector)?.remove();
  web.document.getElementById(_backgroundId)?.remove();
}

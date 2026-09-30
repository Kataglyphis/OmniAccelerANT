import 'package:web/web.dart' as web;

/// The overlay markup lives in `web/index.html`; these are its hooks.
const String _loadingSelector = '.loading';
const String _backgroundId = 'background-animation';

void dismissBootOverlayImpl() {
  web.document.querySelector(_loadingSelector)?.remove();
  web.document.getElementById(_backgroundId)?.remove();
}

void showBootFailureImpl(Object error, StackTrace stackTrace) {
  // Replace the spinner but keep the gradient.
  final web.Element? loading = web.document.querySelector(_loadingSelector);
  if (loading == null) return;

  while (loading.firstChild != null) {
    loading.removeChild(loading.firstChild!);
  }

  final web.HTMLDivElement box = web.HTMLDivElement()
    ..style.maxWidth = '38rem'
    ..style.padding = '1.5rem'
    ..style.borderRadius = '8px'
    ..style.background = 'rgba(255, 255, 255, 0.92)'
    ..style.color = '#0B1220'
    ..style.fontFamily = 'system-ui, -apple-system, sans-serif'
    ..style.textAlign = 'center';

  final web.HTMLHeadingElement title = web.HTMLHeadingElement.h2()
    ..textContent = 'This build could not start'
    ..style.margin = '0 0 0.75rem 0'
    ..style.fontSize = '1.25rem';

  // The likeliest cause: a build published without the generated, gitignored web/pkg/.
  final web.HTMLParagraphElement hint = web.HTMLParagraphElement()
    ..textContent =
        'The WebAssembly core did not load. If you are serving this build '
        'yourself, check that pkg/oxidant.js and the .wasm files were '
        'published next to index.html, and that they are served as '
        'application/wasm.'
    ..style.margin = '0 0 0.75rem 0'
    ..style.fontSize = '0.95rem';

  // package:web has no constructor for <pre>.
  final web.HTMLPreElement detail =
      web.document.createElement('pre') as web.HTMLPreElement
        ..textContent = '$error'
        ..style.margin = '0'
        ..style.padding = '0.5rem'
        ..style.overflow = 'auto'
        ..style.maxHeight = '9rem'
        ..style.textAlign = 'left'
        ..style.fontSize = '0.75rem'
        ..style.background = 'rgba(11, 18, 32, 0.06)'
        ..style.borderRadius = '4px';

  box.append(title);
  box.append(hint);
  box.append(detail);
  loading.append(box);
}

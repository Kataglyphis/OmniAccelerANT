import 'boot_overlay_native.dart'
    if (dart.library.js_interop) 'boot_overlay_web.dart';

/// Removes the HTML loading overlay `web/index.html` paints before Flutter boots.
///
/// No-op off the web. On the web it deletes `<div class="loading">` and the
/// gradient behind it. Nothing else in the app ever removed them: the overlay
/// went up on page load and stayed up for the lifetime of the document, so a
/// visitor whose boot failed sat under a spinner with no timeout and no message.
void dismissBootOverlay() => dismissBootOverlayImpl();

/// Replaces the loading overlay with a boot failure the visitor can act on.
///
/// Off the web this only prints, because a native build that gets this far has
/// a console and a Flutter error screen. On the web it is the ONLY channel left:
/// if [RustLib.init] throws, `runApp` is never reached, so there is no Flutter
/// tree to render an error into.
void showBootFailure(Object error, StackTrace stackTrace) =>
    showBootFailureImpl(error, stackTrace);

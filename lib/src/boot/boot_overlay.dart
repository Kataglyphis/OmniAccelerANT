import 'boot_overlay_native.dart'
    if (dart.library.js_interop) 'boot_overlay_web.dart';

/// Removes the loading overlay `web/index.html` paints before Flutter boots; no-op off the web.
void dismissBootOverlay() => dismissBootOverlayImpl();

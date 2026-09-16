import 'package:flutter/foundation.dart';

/// No-op: there is no HTML document behind a native build.
void dismissBootOverlayImpl() {}

/// Native builds keep the default behaviour — the error reaches the console and
/// Flutter's own error widget. This exists so `main()` can stay platform-free.
void showBootFailureImpl(Object error, StackTrace stackTrace) {
  debugPrint('Boot failed: $error\n$stackTrace');
}

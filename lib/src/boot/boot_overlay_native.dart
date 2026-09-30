import 'package:flutter/foundation.dart';

/// No-op: there is no HTML document behind a native build.
void dismissBootOverlayImpl() {}

/// Prints only; exists so `main()` can stay platform-free.
void showBootFailureImpl(Object error, StackTrace stackTrace) {
  debugPrint('Boot failed: $error\n$stackTrace');
}

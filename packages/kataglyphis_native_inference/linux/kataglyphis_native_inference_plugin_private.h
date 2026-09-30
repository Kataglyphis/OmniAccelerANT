#include <flutter_linux/flutter_linux.h>

#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin.h"

// Plugin internals exposed for unit tests; works around flutter/flutter#88724.

// Handles the getPlatformVersion method call.
FlMethodResponse *get_platform_version();

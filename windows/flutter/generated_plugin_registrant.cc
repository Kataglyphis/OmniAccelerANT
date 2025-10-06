//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <kataglyphis_native_inference/kataglyphis_native_inference_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  KataglyphisNativeInferencePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("KataglyphisNativeInferencePluginCApi"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}

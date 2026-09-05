#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "kataglyphis_native_inference_plugin.h"

void KataglyphisNativeInferencePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  kataglyphis_native_inference::KataglyphisNativeInferencePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

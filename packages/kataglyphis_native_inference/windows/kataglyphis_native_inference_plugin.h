#ifndef FLUTTER_PLUGIN_KATAGLYPHIS_NATIVE_INFERENCE_PLUGIN_H_
#define FLUTTER_PLUGIN_KATAGLYPHIS_NATIVE_INFERENCE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>

#include <memory>

namespace kataglyphis_native_inference {

class KataglyphisTexture;

class KataglyphisNativeInferencePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  KataglyphisNativeInferencePlugin();

  virtual ~KataglyphisNativeInferencePlugin();

  KataglyphisNativeInferencePlugin(const KataglyphisNativeInferencePlugin&) =
      delete;
  KataglyphisNativeInferencePlugin& operator=(
      const KataglyphisNativeInferencePlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  flutter::TextureRegistrar* texture_registrar_;
  KataglyphisTexture* texture_;
  // Owns the variant registered with Flutter; the engine keeps the pointer
  // for the texture's lifetime, so it must not be a stack temporary.
  std::unique_ptr<flutter::TextureVariant> texture_variant_;
};

}  // namespace kataglyphis_native_inference

#endif  // FLUTTER_PLUGIN_KATAGLYPHIS_NATIVE_INFERENCE_PLUGIN_H_

#include "kataglyphis_native_inference_plugin.h"

#include <windows.h>

#include <VersionHelpers.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <memory>
#include <sstream>

#include "kataglyphis_c_api.h"
#include "kataglyphis_texture.h"

namespace kataglyphis_native_inference {

// static
void KataglyphisNativeInferencePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "kataglyphis_native_inference",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<KataglyphisNativeInferencePlugin>();
  plugin->texture_registrar_ = registrar->texture_registrar();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

KataglyphisNativeInferencePlugin::KataglyphisNativeInferencePlugin()
    : texture_registrar_(nullptr), texture_(nullptr) {}

KataglyphisNativeInferencePlugin::~KataglyphisNativeInferencePlugin() {
  if (texture_) {
    if (texture_->texture_id() >= 0) {
      UnregisterPushTarget(texture_->texture_id());
      if (texture_registrar_) {
        texture_registrar_->UnregisterTexture(texture_->texture_id());
      }
    }
    delete texture_;
  }
}

namespace {

bool TextureMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                       KataglyphisTexture* texture,
                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "setPipeline") {
    if (!texture) {
      result->Error("no_texture", "No texture created. Call 'create' first.");
      return true;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args) {
      auto it = args->find(flutter::EncodableValue("pipeline"));
      if (it != args->end()) {
        const std::string* pipeline =
            std::get_if<std::string>(&it->second);
        if (pipeline) {
          std::string error;
          bool success = texture->SetPipeline(pipeline->c_str(), &error);
          if (success) {
            result->Success(flutter::EncodableValue());
          } else {
            result->Error("pipeline_error",
                          error.empty() ? "Failed to set pipeline" : error);
          }
          return true;
        }
      }
    }
    result->Error("bad_args", "Expected map with 'pipeline' string");
    return true;
  } else if (method == "play") {
    if (!texture) {
      result->Error("no_texture", "No texture created");
      return true;
    }
    texture->Play();
    result->Success(flutter::EncodableValue());
    return true;
  } else if (method == "pause") {
    if (!texture) {
      result->Error("no_texture", "No texture created");
      return true;
    }
    texture->Pause();
    result->Success(flutter::EncodableValue());
    return true;
  } else if (method == "stop") {
    if (!texture) {
      result->Error("no_texture", "No texture created");
      return true;
    }
    texture->Stop();
    result->Success(flutter::EncodableValue());
    return true;
  } else if (method == "setColor") {
    if (!texture) {
      result->Error("no_texture", "No texture created");
      return true;
    }
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    if (args && args->size() == 3) {
      int r = 0, g = 0, b = 0;
      const int* r_val = std::get_if<int>(&(*args)[0]);
      const int* g_val = std::get_if<int>(&(*args)[1]);
      const int* b_val = std::get_if<int>(&(*args)[2]);
      if (r_val) r = *r_val;
      if (g_val) g = *g_val;
      if (b_val) b = *b_val;
      texture->SetColor(static_cast<uint8_t>(r), static_cast<uint8_t>(g),
                        static_cast<uint8_t>(b));
      result->Success(flutter::EncodableValue());
      return true;
    }
    result->Error("bad_args", "Expected [r, g, b] list");
    return true;
  }

  return false;
}

}  // namespace

void KataglyphisNativeInferencePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "getPlatformVersion") {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method == "add") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      int a = 0, b = 0;
      auto itA = args->find(flutter::EncodableValue("a"));
      auto itB = args->find(flutter::EncodableValue("b"));
      if (itA != args->end()) a = std::get<int>(itA->second);
      if (itB != args->end()) b = std::get<int>(itB->second);

      int sum = kataglyphis_add(a, b);
      result->Success(flutter::EncodableValue(sum));
    } else {
      result->Error("bad_args", "Expected map with a and b");
    }
  } else if (method == "create") {
    if (texture_) {
      result->Success(flutter::EncodableValue(texture_->texture_id()));
      return;
    }
    const auto* args =
        std::get_if<flutter::EncodableList>(method_call.arguments());
    if (!args || args->size() != 2) {
      result->Error("bad_args", "Expected [width, height]");
      return;
    }
    const int* width_val = std::get_if<int>(&(*args)[0]);
    const int* height_val = std::get_if<int>(&(*args)[1]);
    if (!width_val || !height_val) {
      result->Error("bad_args", "Expected integer width and height");
      return;
    }
    uint32_t width = static_cast<uint32_t>(*width_val);
    uint32_t height = static_cast<uint32_t>(*height_val);
    if (width == 0 || height == 0) {
      result->Error("bad_args", "Width and height must be > 0");
      return;
    }

    texture_ = new KataglyphisTexture(width, height, 5, 83, 177);
    texture_->SetTextureRegistrar(texture_registrar_);

    OutputDebugStringA("[kataglyphis] About to register texture\n");
    texture_variant_ = std::make_unique<flutter::TextureVariant>(
        texture_->GetTextureVariant());
    const int64_t texture_id =
        texture_registrar_->RegisterTexture(texture_variant_.get());
    if (texture_id < 0) {
      OutputDebugStringA("[kataglyphis] RegisterTexture failed\n");
      delete texture_;
      texture_ = nullptr;
      texture_variant_.reset();
      result->Error("texture_error", "Failed to register texture");
      return;
    }
    texture_->set_texture_id(texture_id);
    RegisterPushTarget(texture_id, texture_);
    OutputDebugStringA("[kataglyphis] Texture registered successfully\n");

    result->Success(flutter::EncodableValue(texture_id));
  } else if (TextureMethodCall(method_call, texture_, std::move(result))) {
  } else {
    result->NotImplemented();
  }
}

}  // namespace kataglyphis_native_inference

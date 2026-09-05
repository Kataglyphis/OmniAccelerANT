#ifndef KATAGLYPHIS_TEXTURE_H_
#define KATAGLYPHIS_TEXTURE_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <flutter_texture_registrar.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

namespace kataglyphis_native_inference {

// A CPU pixel-buffer texture fed from outside (Rust pushes RGBA frames via the
// exported `knt_push_frame` C ABI; see bottom of this header). The old
// pipeline-string methods remain as no-ops for method-channel compatibility.
class KataglyphisTexture {
 public:
  KataglyphisTexture(uint32_t width, uint32_t height, uint8_t r, uint8_t g,
                     uint8_t b);
  ~KataglyphisTexture();

  bool SetPipeline(const char* pipeline_description, std::string* error);
  void Play();
  void Pause();
  void Stop();
  void SetColor(uint8_t r, uint8_t g, uint8_t b);

  // Copies one tightly packed RGBA frame into the texture and marks it
  // available. Thread-safe; callable from any thread (Rust worker).
  bool PushFrame(const uint8_t* rgba, uint32_t width, uint32_t height);

  int64_t texture_id() const { return texture_id_; }
  void set_texture_id(int64_t id) { texture_id_ = id; }

  void SetTextureRegistrar(flutter::TextureRegistrar* registrar);
  flutter::TextureVariant GetTextureVariant();

 private:
  static constexpr size_t kBytesPerPixel = 4;

  int64_t texture_id_;
  uint32_t width_;
  uint32_t height_;
  std::unique_ptr<uint8_t[]> buffer_;

  // Raster-thread copy handed to Flutter; must outlive the callback return.
  uint32_t present_width_ = 0;
  uint32_t present_height_ = 0;
  std::unique_ptr<uint8_t[]> present_buffer_;
  FlutterDesktopPixelBuffer pixel_buffer_ = {};

  // Guards buffer_/width_/height_ between PushFrame (any thread) and the
  // raster-thread pixel-buffer callback.
  std::mutex frame_mutex_;

  flutter::TextureRegistrar* texture_registrar_;

  const FlutterDesktopPixelBuffer* CopyPixelBufferCallback(size_t width,
                                                           size_t height);
};

// Global id → texture registry backing the C ABI. The plugin registers a
// texture after RegisterTexture assigns its id and unregisters it before
// destruction.
void RegisterPushTarget(int64_t texture_id, KataglyphisTexture* texture);
void UnregisterPushTarget(int64_t texture_id);

}  // namespace kataglyphis_native_inference

// C ABI consumed by the Rust webcam engine (resolved with GetProcAddress /
// libloading against this plugin DLL — keep names and signatures stable).
extern "C" {

// Returns 0 on success, negative on error (unknown texture, bad args).
__declspec(dllexport) int32_t knt_push_frame(int64_t texture_id,
                                             const uint8_t* rgba,
                                             uint32_t width, uint32_t height);

// ABI version for sanity checks from the Rust side.
__declspec(dllexport) int32_t knt_api_version();

}  // extern "C"

#endif  // KATAGLYPHIS_TEXTURE_H_

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

#include "kataglyphis_texture_abi.h"

namespace kataglyphis_native_inference {

/// CPU pixel-buffer texture fed by `knt_push_frame`; the Rust view drives the camera, so it has no pipeline methods.
class KataglyphisTexture
{
  public:
    KataglyphisTexture(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b);
    ~KataglyphisTexture();

    void SetColor(uint8_t r, uint8_t g, uint8_t b);

    /// Copies one packed RGBA frame in and marks it available; callable from any thread.
    bool PushFrame(const uint8_t *rgba, uint32_t width, uint32_t height);

    int64_t texture_id() const { return texture_id_; }
    void set_texture_id(int64_t id) { texture_id_ = id; }

    void SetTextureRegistrar(flutter::TextureRegistrar *registrar);
    flutter::TextureVariant GetTextureVariant();

    /// Bytes of one packed RGBA frame, in size_t so a frame of 2^32 pixels or more does not wrap.
    static constexpr size_t BufferBytes(uint32_t width, uint32_t height)
    {
        return static_cast<size_t>(width) * height * kBytesPerPixel;
    }

  private:
    static constexpr size_t kBytesPerPixel = 4;

    // Caller holds frame_mutex_, or owns the texture alone.
    void FillBuffer(uint8_t r, uint8_t g, uint8_t b);

    int64_t texture_id_;
    uint32_t width_;
    uint32_t height_;
    std::unique_ptr<uint8_t[]> buffer_;

    // Raster-thread copy handed to Flutter; must outlive the callback return.
    uint32_t present_width_ = 0;
    uint32_t present_height_ = 0;
    std::unique_ptr<uint8_t[]> present_buffer_;
    FlutterDesktopPixelBuffer pixel_buffer_ = {};

    // Guards buffer_/width_/height_ between PushFrame and the raster-thread callback.
    std::mutex frame_mutex_;

    flutter::TextureRegistrar *texture_registrar_;

    const FlutterDesktopPixelBuffer *CopyPixelBufferCallback(size_t width, size_t height);
};

/// Id-to-texture registry behind the C ABI; register after RegisterTexture, unregister before destruction.
void RegisterPushTarget(int64_t texture_id, KataglyphisTexture *texture);
void UnregisterPushTarget(int64_t texture_id);

}// namespace kataglyphis_native_inference

#endif// KATAGLYPHIS_TEXTURE_H_

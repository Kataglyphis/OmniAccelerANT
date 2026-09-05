#include "kataglyphis_texture.h"

#include <windows.h>

#include <algorithm>
#include <cstring>
#include <unordered_map>

namespace kataglyphis_native_inference {

KataglyphisTexture::KataglyphisTexture(uint32_t width, uint32_t height, uint8_t r,
                                       uint8_t g, uint8_t b)
    : texture_id_(-1),
      width_(width),
      height_(height),
      buffer_(new uint8_t[width * height * kBytesPerPixel]),
      texture_registrar_(nullptr) {
  OutputDebugStringA("[kataglyphis_texture] Constructor called\n");
  const uint32_t pixels = width * height;
  for (uint32_t i = 0; i < pixels; ++i) {
    uint8_t* p = buffer_.get() + i * kBytesPerPixel;
    p[0] = r;
    p[1] = g;
    p[2] = b;
    p[3] = 255;
  }
}

KataglyphisTexture::~KataglyphisTexture() {
  OutputDebugStringA("[kataglyphis_texture] Destructor called\n");
  buffer_.reset();
}

void KataglyphisTexture::SetTextureRegistrar(
    flutter::TextureRegistrar* registrar) {
  texture_registrar_ = registrar;
}

bool KataglyphisTexture::PushFrame(const uint8_t* rgba, uint32_t width,
                                   uint32_t height) {
  if (!rgba || width == 0 || height == 0) {
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    const size_t size = static_cast<size_t>(width) * height * kBytesPerPixel;
    if (width != width_ || height != height_) {
      buffer_.reset(new uint8_t[size]);
      width_ = width;
      height_ = height;
    }
    std::memcpy(buffer_.get(), rgba, size);
  }
  if (texture_registrar_ && texture_id_ >= 0) {
    texture_registrar_->MarkTextureFrameAvailable(texture_id_);
  }
  return true;
}

const FlutterDesktopPixelBuffer* KataglyphisTexture::CopyPixelBufferCallback(
    size_t /*width*/, size_t /*height*/) {
  std::lock_guard<std::mutex> lock(frame_mutex_);
  const size_t size = static_cast<size_t>(width_) * height_ * kBytesPerPixel;
  if (present_width_ != width_ || present_height_ != height_) {
    present_buffer_.reset(new uint8_t[size]);
    present_width_ = width_;
    present_height_ = height_;
  }
  // Copy so the returned pointer stays stable after the lock is released,
  // even if PushFrame overwrites (or resizes) the write buffer meanwhile.
  std::memcpy(present_buffer_.get(), buffer_.get(), size);
  pixel_buffer_.buffer = present_buffer_.get();
  pixel_buffer_.width = present_width_;
  pixel_buffer_.height = present_height_;
  pixel_buffer_.release_callback = nullptr;
  pixel_buffer_.release_context = nullptr;
  return &pixel_buffer_;
}

flutter::TextureVariant KataglyphisTexture::GetTextureVariant() {
  return flutter::TextureVariant(flutter::PixelBufferTexture(
      [this](size_t width, size_t height) -> const FlutterDesktopPixelBuffer* {
        return this->CopyPixelBufferCallback(width, height);
      }));
}

bool KataglyphisTexture::SetPipeline(const char* /*pipeline_description*/,
                                     std::string* /*error*/) {
  OutputDebugStringA("[kataglyphis_texture] SetPipeline called (noop)\n");
  return true;
}

void KataglyphisTexture::Play() {
  OutputDebugStringA("[kataglyphis_texture] Play called (noop)\n");
}

void KataglyphisTexture::Pause() {
  OutputDebugStringA("[kataglyphis_texture] Pause called (noop)\n");
}

void KataglyphisTexture::Stop() {
  OutputDebugStringA("[kataglyphis_texture] Stop called (noop)\n");
}

void KataglyphisTexture::SetColor(uint8_t r, uint8_t g, uint8_t b) {
  OutputDebugStringA("[kataglyphis_texture] SetColor called\n");
  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    const uint32_t pixels = width_ * height_;
    for (uint32_t i = 0; i < pixels; ++i) {
      uint8_t* p = buffer_.get() + i * kBytesPerPixel;
      p[0] = r;
      p[1] = g;
      p[2] = b;
      p[3] = 255;
    }
  }
  if (texture_registrar_ && texture_id_ >= 0) {
    texture_registrar_->MarkTextureFrameAvailable(texture_id_);
  }
}

namespace {

std::mutex g_push_targets_mutex;
std::unordered_map<int64_t, KataglyphisTexture*>& PushTargets() {
  static std::unordered_map<int64_t, KataglyphisTexture*> targets;
  return targets;
}

}  // namespace

void RegisterPushTarget(int64_t texture_id, KataglyphisTexture* texture) {
  std::lock_guard<std::mutex> lock(g_push_targets_mutex);
  PushTargets()[texture_id] = texture;
}

void UnregisterPushTarget(int64_t texture_id) {
  std::lock_guard<std::mutex> lock(g_push_targets_mutex);
  PushTargets().erase(texture_id);
}

}  // namespace kataglyphis_native_inference

int32_t knt_push_frame(int64_t texture_id, const uint8_t* rgba, uint32_t width,
                       uint32_t height) {
  using namespace kataglyphis_native_inference;
  if (!rgba || width == 0 || height == 0) {
    return -1;
  }
  // Held across PushFrame so the texture cannot be destroyed mid-copy;
  // contention is only with create/destroy, never frame-vs-frame.
  std::lock_guard<std::mutex> lock(g_push_targets_mutex);
  auto it = PushTargets().find(texture_id);
  if (it == PushTargets().end()) {
    return -2;
  }
  return it->second->PushFrame(rgba, width, height) ? 0 : -3;
}

int32_t knt_api_version() { return 1; }

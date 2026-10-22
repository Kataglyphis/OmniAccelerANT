module;

#include "kataglyphis_texture_abi.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <flutter_linux/flutter_linux.h>
#include <iterator>
#include <map>
#include <string.h>

module kataglyphis.my_texture;

typedef struct _MyTexture MyTexture;
typedef struct _MyTextureClass MyTextureClass;

struct _MyTextureClass
{ FlPixelBufferTextureClass parent_class; };

#define MY_TYPE_TEXTURE (my_texture_get_type())
#define MY_TEXTURE(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), MY_TYPE_TEXTURE, MyTexture))
#define MY_IS_TEXTURE(obj) (G_TYPE_CHECK_INSTANCE_TYPE((obj), MY_TYPE_TEXTURE))

struct _MyTexture
{
    FlPixelBufferTexture parent_instance;

    uint32_t width;
    uint32_t height;
    uint8_t *buffer;

    // Callback for texture updates
    FlTextureRegistrar *texture_registrar;

    // knt_push_frame frames: packed RGBA, so no stride/caps handling; once set they win over the colour.
    uint8_t *pushed_buffer;
    size_t pushed_capacity;
    uint32_t pushed_width;
    uint32_t pushed_height;
    gboolean has_pushed;
    GMutex pushed_mutex;

    gboolean logged_no_registrar;
    gboolean logged_first_push;

    // set_color queues here: copy_pixels (raster thread) is the only writer of `buffer`.
    GMutex buffer_mutex;
    gboolean has_pending_color;
    uint8_t pending_r;
    uint8_t pending_g;
    uint8_t pending_b;
};

G_DEFINE_TYPE(MyTexture, my_texture, fl_pixel_buffer_texture_get_type())

// Defined with the knt_push_frame ABI below; dispose needs it first.
void my_texture_forget_push_target(FlTexture *texture);

static gboolean mark_texture_frame_available_on_main(gpointer user_data)
{
    MyTexture *self = MY_TEXTURE(user_data);
    if (self->texture_registrar) {
        fl_texture_registrar_mark_texture_frame_available(self->texture_registrar, FL_TEXTURE(self));
    }
    g_object_unref(self);
    return G_SOURCE_REMOVE;
}

static void request_texture_frame_available(MyTexture *self, const char *source)
{
    if (!self->texture_registrar) {
        if (!self->logged_no_registrar) {
            g_warning("[my_texture] no texture registrar yet; skip frame update from %s", source);
            self->logged_no_registrar = TRUE;
        }
        return;
    }

    g_main_context_invoke(nullptr, mark_texture_frame_available_on_main, g_object_ref(self));
}

static void force_alpha_opaque(uint8_t *buffer, uint32_t width, uint32_t height)
{
    const uint64_t pixel_count = static_cast<uint64_t>(width) * static_cast<uint64_t>(height);
    for (uint64_t index = 0; index < pixel_count; ++index) { buffer[index * 4U + 3U] = 255U; }
}

// Runs only from copy_pixels, which is the one writer of `buffer`.
static void apply_pending_color(MyTexture *self)
{
    g_mutex_lock(&self->buffer_mutex);
    if (self->has_pending_color && self->buffer) {
        const size_t pixels = static_cast<size_t>(self->width) * static_cast<size_t>(self->height);
        for (size_t index = 0; index < pixels; ++index) {
            uint8_t *pixel = self->buffer + index * 4U;
            pixel[0] = self->pending_r;
            pixel[1] = self->pending_g;
            pixel[2] = self->pending_b;
            pixel[3] = 255U;
        }
        self->has_pending_color = FALSE;
    }
    g_mutex_unlock(&self->buffer_mutex);
}

static void my_texture_dispose(GObject *object)
{
    MyTexture *self = MY_TEXTURE(object);

    // The push registry holds raw pointers; backstop for paths that bypass the plugin's unregister.
    my_texture_forget_push_target(FL_TEXTURE(self));

    g_mutex_lock(&self->pushed_mutex);
    if (self->pushed_buffer) {
        free(self->pushed_buffer);
        self->pushed_buffer = nullptr;
    }
    self->pushed_capacity = 0U;
    self->has_pushed = FALSE;
    g_mutex_unlock(&self->pushed_mutex);
    g_mutex_clear(&self->pushed_mutex);

    g_mutex_lock(&self->buffer_mutex);
    if (self->buffer) {
        free(self->buffer);
        self->buffer = nullptr;
    }
    g_mutex_unlock(&self->buffer_mutex);
    g_mutex_clear(&self->buffer_mutex);

    G_OBJECT_CLASS(my_texture_parent_class)->dispose(object);
}

static gboolean my_texture_copy_pixels(FlPixelBufferTexture *texture,
  const uint8_t **out_buffer,
  uint32_t *width,
  uint32_t *height,
  GError **error)
{
    (void)error;
    MyTexture *self = MY_TEXTURE(texture);

    // A failed allocation leaves buffer null; failing makes Flutter skip the frame instead of crashing.
    if (!self->buffer) { return FALSE; }

    const size_t buffer_size = static_cast<size_t>(self->width) * static_cast<size_t>(self->height) * 4U;

    // A pushed frame wins over the colour; copied row-wise since its geometry is the camera's.
    g_mutex_lock(&self->pushed_mutex);
    if (self->has_pushed && self->pushed_buffer) {
        const size_t row_bytes =
          std::min(static_cast<size_t>(self->width), static_cast<size_t>(self->pushed_width)) * 4U;
        const uint32_t copy_rows = std::min(self->height, self->pushed_height);

        memset(self->buffer, 0, buffer_size);
        for (uint32_t row = 0; row < copy_rows; ++row) {
            const size_t src_offset = static_cast<size_t>(row) * static_cast<size_t>(self->pushed_width) * 4U;
            const size_t dst_offset = static_cast<size_t>(row) * static_cast<size_t>(self->width) * 4U;
            if (src_offset + row_bytes <= self->pushed_capacity && dst_offset + row_bytes <= buffer_size) {
                memcpy(self->buffer + dst_offset, self->pushed_buffer + src_offset, row_bytes);
            }
        }
        g_mutex_unlock(&self->pushed_mutex);

        force_alpha_opaque(self->buffer, self->width, self->height);
        *out_buffer = self->buffer;
        *width = self->width;
        *height = self->height;
        return TRUE;
    }
    g_mutex_unlock(&self->pushed_mutex);

    // Until a frame arrives, the queued colour.
    apply_pending_color(self);

    *out_buffer = self->buffer;
    *width = self->width;
    *height = self->height;
    return TRUE;
}

void my_texture_set_color(FlTexture *texture, uint8_t r, uint8_t g, uint8_t b)
{
    MyTexture *self = MY_TEXTURE(texture);
    g_return_if_fail(MY_IS_TEXTURE(self));
    if (!self->buffer) return;

    // Queue for copy_pixels; writing `buffer` here would race the raster thread.
    g_mutex_lock(&self->buffer_mutex);
    self->pending_r = r;
    self->pending_g = g;
    self->pending_b = b;
    self->has_pending_color = TRUE;
    g_mutex_unlock(&self->buffer_mutex);

    if (self->texture_registrar) { request_texture_frame_available(self, "set_color"); }
}

static void my_texture_class_init(MyTextureClass *klass)
{
    G_OBJECT_CLASS(klass)->dispose = my_texture_dispose;
    FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = my_texture_copy_pixels;
}

static void my_texture_init(MyTexture *self)
{
    self->buffer = nullptr;
    self->texture_registrar = nullptr;
    self->pushed_buffer = nullptr;
    self->pushed_capacity = 0U;
    self->pushed_width = 0U;
    self->pushed_height = 0U;
    self->has_pushed = FALSE;
    self->logged_no_registrar = FALSE;
    self->logged_first_push = FALSE;
    self->has_pending_color = FALSE;
    self->pending_r = 0U;
    self->pending_g = 0U;
    self->pending_b = 0U;
    g_mutex_init(&self->pushed_mutex);
    g_mutex_init(&self->buffer_mutex);
}

FlTexture *my_texture_new(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b)
{
    MyTexture *self = MY_TEXTURE(g_object_new(my_texture_get_type(), nullptr));
    self->width = width;
    self->height = height;
    // size_t: the 32-bit product wraps past ~4096x4096 and would under-allocate.
    const size_t buffer_bytes = static_cast<size_t>(width) * static_cast<size_t>(height) * 4U;
    self->buffer = static_cast<uint8_t *>(malloc(buffer_bytes));
    if (!self->buffer) {
        g_warning("[my_texture] out of memory for a %ux%u texture (%zu bytes)", width, height, buffer_bytes);
        return FL_TEXTURE(self);
    }
    memset(self->buffer, 0, buffer_bytes);

    my_texture_set_color(FL_TEXTURE(self), r, g, b);
    return FL_TEXTURE(self);
}

void my_texture_set_texture_registrar(FlTexture *texture, FlTextureRegistrar *registrar)
{
    MyTexture *self = MY_TEXTURE(texture);
    g_return_if_fail(MY_IS_TEXTURE(self));
    self->texture_registrar = registrar;
    self->logged_no_registrar = FALSE;
    g_message("[my_texture] texture registrar assigned");
}
// knt_push_frame C ABI, identical to the Windows one. See docs/source/camera-streaming.md § Rust-owned webcam inference

namespace {

// Raw pointers: the plugin unregisters before destruction, and my_texture_dispose sweeps as a backstop.
std::map<int64_t, MyTexture *> &PushTargets()
{
    static std::map<int64_t, MyTexture *> targets;
    return targets;
}

GMutex *PushTargetsMutex()
{
    static GMutex mutex;
    static gsize initialised = 0;
    if (g_once_init_enter(&initialised)) {
        g_mutex_init(&mutex);
        g_once_init_leave(&initialised, 1);
    }
    return &mutex;
}

}// namespace

void my_texture_register_push_target(int64_t texture_id, FlTexture *texture)
{
    g_return_if_fail(MY_IS_TEXTURE(texture));
    g_mutex_lock(PushTargetsMutex());
    PushTargets()[texture_id] = MY_TEXTURE(texture);
    g_mutex_unlock(PushTargetsMutex());
}

void my_texture_unregister_push_target(int64_t texture_id)
{
    g_mutex_lock(PushTargetsMutex());
    PushTargets().erase(texture_id);
    g_mutex_unlock(PushTargetsMutex());
}

gboolean my_texture_has_pushed_frame(int64_t texture_id)
{
    gboolean pushed = FALSE;
    g_mutex_lock(PushTargetsMutex());
    auto it = PushTargets().find(texture_id);
    if (it != PushTargets().end()) {
        g_mutex_lock(&it->second->pushed_mutex);
        pushed = it->second->has_pushed;
        g_mutex_unlock(&it->second->pushed_mutex);
    }
    g_mutex_unlock(PushTargetsMutex());
    return pushed;
}

void my_texture_forget_push_target(FlTexture *texture)
{
    if (!MY_IS_TEXTURE(texture)) return;
    MyTexture *self = MY_TEXTURE(texture);
    g_mutex_lock(PushTargetsMutex());
    for (auto it = PushTargets().begin(); it != PushTargets().end();) {
        it = (it->second == self) ? PushTargets().erase(it) : std::next(it);
    }
    g_mutex_unlock(PushTargetsMutex());
}

extern "C" {

// 0 on success; -1 bad arguments, -2 unknown texture id, -3 copy failed (the Windows codes).
int32_t knt_push_frame(int64_t texture_id, const uint8_t *rgba, uint32_t width, uint32_t height)
{
    if (!rgba || width == 0U || height == 0U) { return KNT_BAD_ARGUMENTS; }

    // Held across the copy so the texture cannot be destroyed mid-memcpy.
    g_mutex_lock(PushTargetsMutex());
    auto it = PushTargets().find(texture_id);
    if (it == PushTargets().end()) {
        g_mutex_unlock(PushTargetsMutex());
        return KNT_UNKNOWN_TEXTURE;
    }
    MyTexture *self = it->second;

    const size_t needed = static_cast<size_t>(width) * static_cast<size_t>(height) * 4U;

    g_mutex_lock(&self->pushed_mutex);
    if (self->pushed_capacity < needed) {
        uint8_t *grown = static_cast<uint8_t *>(realloc(self->pushed_buffer, needed));
        if (!grown) {
            g_mutex_unlock(&self->pushed_mutex);
            g_mutex_unlock(PushTargetsMutex());
            return KNT_COPY_FAILED;
        }
        self->pushed_buffer = grown;
        self->pushed_capacity = needed;
    }
    memcpy(self->pushed_buffer, rgba, needed);
    self->pushed_width = width;
    self->pushed_height = height;
    self->has_pushed = TRUE;

    if (!self->logged_first_push) {
        g_message("[my_texture] first pushed frame: %ux%u -> texture %" G_GINT64_FORMAT, width, height, texture_id);
        self->logged_first_push = TRUE;
    }
    g_mutex_unlock(&self->pushed_mutex);

    // Must run on the main loop, not the capture thread; the ref keeps the texture alive until then.
    g_object_ref(self);
    g_idle_add(mark_texture_frame_available_on_main, self);

    g_mutex_unlock(PushTargetsMutex());
    return KNT_OK;
}

int32_t knt_api_version() { return KNT_API_VERSION; }

}// extern "C"

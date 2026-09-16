module;

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <iterator>
#include <map>
#include <string.h>

module kataglyphis.my_texture;

typedef struct _MyTexture MyTexture;
typedef struct _MyTextureClass MyTextureClass;

struct _MyTextureClass {
  FlPixelBufferTextureClass parent_class;
};

#define MY_TYPE_TEXTURE (my_texture_get_type())
#define MY_TEXTURE(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), MY_TYPE_TEXTURE, MyTexture))
#define MY_IS_TEXTURE(obj) \
  (G_TYPE_CHECK_INSTANCE_TYPE((obj), MY_TYPE_TEXTURE))

struct _MyTexture {
  FlPixelBufferTexture parent_instance;

  uint32_t width;
  uint32_t height;
  uint8_t* buffer;
  
  // GStreamer components
  GstElement* pipeline;
  GstElement* appsink;
  GstSample* last_sample;
  GMutex sample_mutex;
  
  // Callback for texture updates
  FlTextureRegistrar* texture_registrar;

  // Frames pushed in over the knt_push_frame C ABI by the Rust webcam engine.
  // Kept separate from last_sample rather than faked as a GstSample: the two
  // producers are mutually exclusive per texture, and a pushed frame is already
  // tightly packed RGBA, so it needs none of the stride/caps handling the
  // GStreamer path does. When has_pushed is set, copy_pixels ignores GStreamer.
  uint8_t* pushed_buffer;
  size_t pushed_capacity;
  uint32_t pushed_width;
  uint32_t pushed_height;
  gboolean has_pushed;
  GMutex pushed_mutex;

  guint64 frame_counter;
  gboolean logged_no_registrar;
  gboolean logged_first_sample;
  gboolean logged_first_push;
};

G_DEFINE_TYPE(MyTexture, my_texture, fl_pixel_buffer_texture_get_type())

// Forward declarations
static GstFlowReturn on_new_sample(GstAppSink* appsink, gpointer user_data);

// Defined with the knt_push_frame ABI at the bottom of this file; dispose needs
// it long before that, so the texture cannot outlive its registry entry.
void my_texture_forget_push_target(FlTexture* texture);

static gboolean mark_texture_frame_available_on_main(gpointer user_data) {
  MyTexture* self = MY_TEXTURE(user_data);
  if (self->texture_registrar) {
    fl_texture_registrar_mark_texture_frame_available(self->texture_registrar,
                                                      FL_TEXTURE(self));
  }
  g_object_unref(self);
  return G_SOURCE_REMOVE;
}

static void request_texture_frame_available(MyTexture* self, const char* source) {
  if (!self->texture_registrar) {
    if (!self->logged_no_registrar) {
      g_warning("[my_texture] no texture registrar yet; skip frame update from %s",
                source);
      self->logged_no_registrar = TRUE;
    }
    return;
  }

  g_main_context_invoke(nullptr, mark_texture_frame_available_on_main,
                        g_object_ref(self));
}

static void force_alpha_opaque(uint8_t* buffer, uint32_t width, uint32_t height) {
  const uint64_t pixel_count = static_cast<uint64_t>(width) * static_cast<uint64_t>(height);
  for (uint64_t index = 0; index < pixel_count; ++index) {
    buffer[index * 4U + 3U] = 255U;
  }
}

static void my_texture_dispose(GObject* object) {
  MyTexture* self = MY_TEXTURE(object);

  g_mutex_lock(&self->sample_mutex);

  if (self->appsink) {
    GstAppSinkCallbacks callbacks = {};
    gst_app_sink_set_callbacks(GST_APP_SINK(self->appsink), &callbacks, nullptr,
                               nullptr);
    gst_object_unref(self->appsink);
    self->appsink = nullptr;
  }

  if (self->pipeline) {
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
    gst_object_unref(self->pipeline);
    self->pipeline = nullptr;
  }

  if (self->last_sample) {
    gst_sample_unref(self->last_sample);
    self->last_sample = nullptr;
  }

  g_mutex_unlock(&self->sample_mutex);
  g_mutex_clear(&self->sample_mutex);

  // The push registry holds a raw pointer, so a texture MUST be out of it
  // before it is freed. The plugin unregisters explicitly; this is the backstop
  // for any path that destroys a texture without going through the plugin.
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

  if (self->buffer) {
    free(self->buffer);
    self->buffer = nullptr;
  }

  G_OBJECT_CLASS(my_texture_parent_class)->dispose(object);
}

static gboolean my_texture_copy_pixels(FlPixelBufferTexture* texture,
                                       const uint8_t** out_buffer,
                                       uint32_t* width, uint32_t* height,
                                       GError** error) {
  (void)error;
  MyTexture* self = MY_TEXTURE(texture);

  // my_texture_new leaves buffer null if its allocation failed, and every
  // branch below memcpys into it. Failing the callback is the honest answer;
  // Flutter then skips the frame instead of the process dying here.
  if (!self->buffer) {
    return FALSE;
  }

  const size_t buffer_size =
      static_cast<size_t>(self->width) * static_cast<size_t>(self->height) * 4U;

  // A frame pushed over the C ABI wins over anything GStreamer has. The Rust
  // engine owns the camera in that mode, so last_sample is stale by definition.
  // The copy is row-wise and clipped rather than a straight memcpy because the
  // pushed geometry is the camera's, which need not match the texture's.
  g_mutex_lock(&self->pushed_mutex);
  if (self->has_pushed && self->pushed_buffer) {
    const size_t row_bytes =
        std::min(static_cast<size_t>(self->width),
                 static_cast<size_t>(self->pushed_width)) *
        4U;
    const uint32_t copy_rows = std::min(self->height, self->pushed_height);

    memset(self->buffer, 0, buffer_size);
    for (uint32_t row = 0; row < copy_rows; ++row) {
      const size_t src_offset =
          static_cast<size_t>(row) * static_cast<size_t>(self->pushed_width) * 4U;
      const size_t dst_offset =
          static_cast<size_t>(row) * static_cast<size_t>(self->width) * 4U;
      if (src_offset + row_bytes <= self->pushed_capacity &&
          dst_offset + row_bytes <= buffer_size) {
        memcpy(self->buffer + dst_offset, self->pushed_buffer + src_offset,
               row_bytes);
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

  g_mutex_lock(&self->sample_mutex);
  GstSample* sample = self->last_sample ? gst_sample_ref(self->last_sample) : nullptr;
  g_mutex_unlock(&self->sample_mutex);

  if (sample) {
    GstBuffer* buffer = gst_sample_get_buffer(sample);
    GstCaps* caps = gst_sample_get_caps(sample);
    GstMapInfo map;

    if (buffer && gst_buffer_map(buffer, &map, GST_MAP_READ)) {
      GstVideoInfo info;
      if (caps && gst_video_info_from_caps(&info, caps)) {
        const gint src_width_signed = GST_VIDEO_INFO_WIDTH(&info);
        const gint src_height_signed = GST_VIDEO_INFO_HEIGHT(&info);
        const uint32_t src_width =
          static_cast<uint32_t>(std::max(src_width_signed, 0));
        const uint32_t src_height =
          static_cast<uint32_t>(std::max(src_height_signed, 0));
        const int src_stride = GST_VIDEO_INFO_PLANE_STRIDE(&info, 0);
        const size_t row_bytes =
            std::min(static_cast<size_t>(self->width), static_cast<size_t>(src_width)) * 4U;
        const uint32_t copy_rows = std::min(self->height, src_height);

        memset(self->buffer, 0, buffer_size);
        if (src_stride > 0 && row_bytes > 0U) {
          for (uint32_t row = 0; row < copy_rows; ++row) {
            const size_t src_offset = static_cast<size_t>(row) * static_cast<size_t>(src_stride);
            const size_t dst_offset = static_cast<size_t>(row) * static_cast<size_t>(self->width) * 4U;
            if (src_offset + row_bytes <= static_cast<size_t>(map.size) &&
                dst_offset + row_bytes <= buffer_size) {
              memcpy(self->buffer + dst_offset, map.data + src_offset, row_bytes);
            }
          }
        }

        force_alpha_opaque(self->buffer, self->width, self->height);

        if (!self->logged_first_sample) {
          const gchar* format_name =
              gst_video_format_to_string(GST_VIDEO_INFO_FORMAT(&info));
          g_message("[my_texture] first sample: src=%ux%u stride=%d format=%s dst=%ux%u",
                    src_width, src_height, src_stride,
                    format_name ? format_name : "unknown", self->width, self->height);
          self->logged_first_sample = TRUE;
        }
      } else {
        const size_t copy_size = std::min(buffer_size, static_cast<size_t>(map.size));
        memcpy(self->buffer, map.data, copy_size);
        if (copy_size < buffer_size) {
          memset(self->buffer + copy_size, 0, buffer_size - copy_size);
        }

        force_alpha_opaque(self->buffer, self->width, self->height);

        if (!self->logged_first_sample) {
          g_message("[my_texture] first sample (fallback copy): bytes=%zu dst=%ux%u",
                    static_cast<size_t>(map.size), self->width, self->height);
          self->logged_first_sample = TRUE;
        }
      }
      gst_buffer_unmap(buffer, &map);
    }

    gst_sample_unref(sample);
  }
  
  *out_buffer = self->buffer;
  *width = self->width;
  *height = self->height;
  return TRUE;
}

void my_texture_set_color(FlTexture* texture, uint8_t r, uint8_t g, uint8_t b) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_if_fail(MY_IS_TEXTURE(self));
  if (!self->buffer) return;

  // size_t throughout: both the pixel count and the byte offset overflow a
  // uint32_t on a large texture, and the offset does so first.
  const size_t pixels =
      static_cast<size_t>(self->width) * static_cast<size_t>(self->height);
  for (size_t i = 0; i < pixels; ++i) {
    uint8_t* p = self->buffer + i * 4U;
    p[0] = r;
    p[1] = g;
    p[2] = b;
    p[3] = 255;
  }

  if (self->texture_registrar) {
    request_texture_frame_available(self, "set_color");
  }
}

static void my_texture_class_init(MyTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = my_texture_dispose;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = my_texture_copy_pixels;
}

static void my_texture_init(MyTexture* self) {
  self->pipeline = nullptr;
  self->appsink = nullptr;
  self->last_sample = nullptr;
  self->buffer = nullptr;
  self->texture_registrar = nullptr;
  self->pushed_buffer = nullptr;
  self->pushed_capacity = 0U;
  self->pushed_width = 0U;
  self->pushed_height = 0U;
  self->has_pushed = FALSE;
  self->frame_counter = 0U;
  self->logged_no_registrar = FALSE;
  self->logged_first_sample = FALSE;
  self->logged_first_push = FALSE;
  g_mutex_init(&self->sample_mutex);
  g_mutex_init(&self->pushed_mutex);
}

FlTexture* my_texture_new(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b) {
  MyTexture* self = MY_TEXTURE(g_object_new(my_texture_get_type(), nullptr));
  self->width = width;
  self->height = height;
  // size_t, not the uint32_t product: `width * height * 4` promotes to a
  // 32-bit int, so anything past ~4096x4096 wraps and mallocs far less than
  // copy_pixels then writes. The malloc result is checked because the
  // set_color below writes width*height*4 bytes unconditionally.
  const size_t buffer_bytes =
      static_cast<size_t>(width) * static_cast<size_t>(height) * 4U;
  self->buffer = static_cast<uint8_t*>(malloc(buffer_bytes));
  if (!self->buffer) {
    g_warning("[my_texture] out of memory for a %ux%u texture (%zu bytes)",
              width, height, buffer_bytes);
    return FL_TEXTURE(self);
  }
  memset(self->buffer, 0, buffer_bytes);

  gst_init(nullptr, nullptr);

  my_texture_set_color(FL_TEXTURE(self), r, g, b);
  return FL_TEXTURE(self);
}

// Callback wenn ein neues Frame verfügbar ist
static GstFlowReturn on_new_sample(GstAppSink* appsink, gpointer user_data) {
  MyTexture* self = MY_TEXTURE(user_data);
  
  GstSample* sample = gst_app_sink_pull_sample(appsink);
  if (!sample) {
    return GST_FLOW_ERROR;
  }
  
  g_mutex_lock(&self->sample_mutex);

  // Altes Sample freigeben
  if (self->last_sample) {
    gst_sample_unref(self->last_sample);
  }
  
  self->last_sample = sample;
  self->frame_counter += 1U;

  g_mutex_unlock(&self->sample_mutex);
  
  // Flutter benachrichtigen, dass ein neues Frame verfügbar ist
  request_texture_frame_available(self, "appsink");

  if ((self->frame_counter % 120U) == 0U) {
    g_message("[my_texture] frame counter=%" G_GUINT64_FORMAT, self->frame_counter);
  }
  
  return GST_FLOW_OK;
}

gboolean my_texture_set_pipeline(FlTexture* texture, const gchar* pipeline_description, GError** error) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_val_if_fail(MY_IS_TEXTURE(self), FALSE);

  g_message("[my_texture] set_pipeline called: %s", pipeline_description ? pipeline_description : "<null>");

  g_mutex_lock(&self->sample_mutex);

  if (self->appsink) {
    GstAppSinkCallbacks callbacks = {};
    gst_app_sink_set_callbacks(GST_APP_SINK(self->appsink), &callbacks, nullptr,
                               nullptr);
    gst_object_unref(self->appsink);
    self->appsink = nullptr;
  }
  
  // Alte Pipeline aufräumen
  if (self->pipeline) {
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
    gst_object_unref(self->pipeline);
    self->pipeline = nullptr;
  }

  if (self->last_sample) {
    gst_sample_unref(self->last_sample);
    self->last_sample = nullptr;
  }

  g_mutex_unlock(&self->sample_mutex);
  
  // Neue Pipeline erstellen
  self->pipeline = gst_parse_launch(pipeline_description, error);
  if (!self->pipeline) {
    return FALSE;
  }

  // gst_parse_launch sets `error` on a RECOVERABLE problem too, and still
  // returns a pipeline. Every caller treats a non-NULL return as success and
  // only frees the GError on the failure path, so leaving it set leaks it — and
  // would make the next `if (error && *error)` reader believe this call failed.
  g_clear_error(error);

  if (!GST_IS_BIN(self->pipeline)) {
    if (error) {
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                  "Pipeline muss ein Bin/Pipeline sein und appsink name='sink' enthalten");
    }
    gst_object_unref(self->pipeline);
    self->pipeline = nullptr;
    return FALSE;
  }
  
  // AppSink finden
  self->appsink = gst_bin_get_by_name(GST_BIN(self->pipeline), "sink");
  if (!self->appsink || !GST_IS_APP_SINK(self->appsink)) {
    if (self->appsink) {
      gst_object_unref(self->appsink);
      self->appsink = nullptr;
    }
    if (error) {
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                  "Pipeline muss ein appsink Element mit name='sink' enthalten");
    }
    gst_object_unref(self->pipeline);
    self->pipeline = nullptr;
    return FALSE;
  }
  
  // AppSink konfigurieren
  GstCaps* caps = gst_caps_new_simple("video/x-raw",
                                      "format", G_TYPE_STRING, "RGBA", nullptr);
  g_object_set(self->appsink,
               "caps", caps,
               "emit-signals", TRUE,
               "sync", FALSE,
               "max-buffers", 1,
               "drop", TRUE,
               nullptr);
  gst_caps_unref(caps);
  
  // Callback registrieren
  GstAppSinkCallbacks callbacks = {};
  callbacks.new_sample = on_new_sample;
  gst_app_sink_set_callbacks(GST_APP_SINK(self->appsink), &callbacks, self, nullptr);
  
  return TRUE;
}

// Drains the first ERROR off the pipeline's bus into `error`.
//
// Returns TRUE when it found one. The caller supplies a fallback message for
// the FALSE case so the response is never blank — a state change can fail
// without ever posting a bus message, and "" is the one answer that helps
// nobody.
static gboolean take_first_bus_error(GstElement* pipeline, GError** error) {
  GstBus* bus = gst_element_get_bus(pipeline);
  if (!bus) {
    return FALSE;
  }

  // The pipeline has already failed by the time we get here, so the message is
  // either queued or it is never coming; half a second is a bounded wait for
  // the posting thread to get there, not a poll.
  GstMessage* msg =
      gst_bus_timed_pop_filtered(bus, 500 * GST_MSECOND, GST_MESSAGE_ERROR);
  gboolean found = FALSE;

  if (msg) {
    GError* err = nullptr;
    gchar* dbg = nullptr;
    gst_message_parse_error(msg, &err, &dbg);
    if (error && err) {
      // The debug string is where the useful half lives ("Cannot identify
      // device '/dev/video0'", the failing element's name), so it is carried
      // through to Dart rather than logged and dropped.
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "%s (%s)", err->message,
                  dbg ? dbg : "no debug info");
      found = TRUE;
    }
    if (err) g_error_free(err);
    if (dbg) g_free(dbg);
    gst_message_unref(msg);
  }

  gst_object_unref(bus);
  return found;
}

gboolean my_texture_play(FlTexture* texture, GError** error) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_val_if_fail(MY_IS_TEXTURE(self), FALSE);

  if (!self->pipeline) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "No pipeline set. Call 'setPipeline' first.");
    return FALSE;
  }

  GstStateChangeReturn result =
      gst_element_set_state(self->pipeline, GST_STATE_PLAYING);
  g_message("[my_texture] set PLAYING result=%d", static_cast<int>(result));

  // The two failures that actually happen here look different on the way out,
  // and only one of them is visible from the return value above:
  //   - a missing device (no /dev/video0) fails the state change synchronously
  //     and returns GST_STATE_CHANGE_FAILURE;
  //   - a caps negotiation failure (the camera cannot do the requested
  //     resolution/framerate, or jpegdec gets something that is not JPEG)
  //     returns GST_STATE_CHANGE_ASYNC here and only resolves later, on the
  //     bus.
  // So the blocking get_state below is not belt-and-braces, it is the half that
  // catches the more common of the two. 3s is long enough for a local V4L2
  // device to negotiate and short enough that the platform-channel reply does
  // not look hung.
  if (result != GST_STATE_CHANGE_FAILURE) {
    result = gst_element_get_state(self->pipeline, nullptr, nullptr,
                                   3 * GST_SECOND);
  }

  if (result == GST_STATE_CHANGE_FAILURE) {
    if (!take_first_bus_error(self->pipeline, error)) {
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                  "Pipeline failed to reach PLAYING and posted no error on its "
                  "bus. Run with GST_DEBUG=3 for the element-level reason.");
    }
    // Leave the pipeline in a clean state rather than half-open: a failed
    // v4l2src that stays in READY keeps the camera node claimed, and the next
    // setPipeline then fails for a second, unrelated-looking reason.
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
    return FALSE;
  }

  return TRUE;
}

void my_texture_pause(FlTexture* texture) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_if_fail(MY_IS_TEXTURE(self));
  
  if (self->pipeline) {
    gst_element_set_state(self->pipeline, GST_STATE_PAUSED);
  }
}

void my_texture_stop(FlTexture* texture) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_if_fail(MY_IS_TEXTURE(self));
  
  if (self->pipeline) {
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
  }
}

// Hilfsfunktion um den TextureRegistrar zu setzen
void my_texture_set_texture_registrar(FlTexture* texture, FlTextureRegistrar* registrar) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_if_fail(MY_IS_TEXTURE(self));
  self->texture_registrar = registrar;
  self->logged_no_registrar = FALSE;
  g_message("[my_texture] texture registrar assigned");
}
// ===========================================================================
// knt_push_frame C ABI
// ===========================================================================
//
// The Linux twin of the Windows export in
// packages/kataglyphis_native_inference/windows/kataglyphis_texture.{h,cpp}.
// Same names, same signatures, same return codes on purpose: the Rust webcam
// engine resolves them with libloading and must not care which platform it is
// on. See docs/source/camera-streaming.md § Rust-owned webcam inference.

namespace {

// id -> texture. Raw pointers: the plugin owns the lifetime and unregisters
// before destruction, and my_texture_dispose sweeps as a backstop.
std::map<int64_t, MyTexture*>& PushTargets() {
  static std::map<int64_t, MyTexture*> targets;
  return targets;
}

GMutex* PushTargetsMutex() {
  static GMutex mutex;
  static gsize initialised = 0;
  if (g_once_init_enter(&initialised)) {
    g_mutex_init(&mutex);
    g_once_init_leave(&initialised, 1);
  }
  return &mutex;
}

}  // namespace

void my_texture_register_push_target(int64_t texture_id, FlTexture* texture) {
  g_return_if_fail(MY_IS_TEXTURE(texture));
  g_mutex_lock(PushTargetsMutex());
  PushTargets()[texture_id] = MY_TEXTURE(texture);
  g_mutex_unlock(PushTargetsMutex());
}

void my_texture_unregister_push_target(int64_t texture_id) {
  g_mutex_lock(PushTargetsMutex());
  PushTargets().erase(texture_id);
  g_mutex_unlock(PushTargetsMutex());
}

void my_texture_forget_push_target(FlTexture* texture) {
  if (!MY_IS_TEXTURE(texture)) return;
  MyTexture* self = MY_TEXTURE(texture);
  g_mutex_lock(PushTargetsMutex());
  for (auto it = PushTargets().begin(); it != PushTargets().end();) {
    it = (it->second == self) ? PushTargets().erase(it) : std::next(it);
  }
  g_mutex_unlock(PushTargetsMutex());
}

extern "C" {

// Returns 0 on success, negative on error — the codes are the Windows ones:
// -1 bad arguments, -2 unknown texture id, -3 the copy itself failed.
__attribute__((visibility("default"))) int32_t knt_push_frame(
    int64_t texture_id, const uint8_t* rgba, uint32_t width, uint32_t height) {
  if (!rgba || width == 0U || height == 0U) {
    return -1;
  }

  // Held across the copy so the texture cannot be unregistered and destroyed
  // mid-memcpy. Contention is with create/destroy only, never frame-vs-frame.
  g_mutex_lock(PushTargetsMutex());
  auto it = PushTargets().find(texture_id);
  if (it == PushTargets().end()) {
    g_mutex_unlock(PushTargetsMutex());
    return -2;
  }
  MyTexture* self = it->second;

  const size_t needed =
      static_cast<size_t>(width) * static_cast<size_t>(height) * 4U;

  g_mutex_lock(&self->pushed_mutex);
  if (self->pushed_capacity < needed) {
    uint8_t* grown = static_cast<uint8_t*>(realloc(self->pushed_buffer, needed));
    if (!grown) {
      g_mutex_unlock(&self->pushed_mutex);
      g_mutex_unlock(PushTargetsMutex());
      return -3;
    }
    self->pushed_buffer = grown;
    self->pushed_capacity = needed;
  }
  memcpy(self->pushed_buffer, rgba, needed);
  self->pushed_width = width;
  self->pushed_height = height;
  self->has_pushed = TRUE;

  if (!self->logged_first_push) {
    g_message("[my_texture] first pushed frame: %ux%u -> texture %" G_GINT64_FORMAT,
              width, height, texture_id);
    self->logged_first_push = TRUE;
  }
  g_mutex_unlock(&self->pushed_mutex);

  // mark_texture_frame_available must run on the main loop; the Rust capture
  // thread is not it. The ref keeps the texture alive until the idle fires.
  g_object_ref(self);
  g_idle_add(mark_texture_frame_available_on_main, self);

  g_mutex_unlock(PushTargetsMutex());
  return 0;
}

__attribute__((visibility("default"))) int32_t knt_api_version() { return 1; }

}  // extern "C"

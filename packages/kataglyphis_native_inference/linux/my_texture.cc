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

  // knt_push_frame frames: packed RGBA, so no stride/caps handling; once set they win over GStreamer.
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

  // set_color queues here: copy_pixels (raster thread) is the only writer of `buffer`.
  GMutex buffer_mutex;
  gboolean has_pending_color;
  uint8_t pending_r;
  uint8_t pending_g;
  uint8_t pending_b;
};

G_DEFINE_TYPE(MyTexture, my_texture, fl_pixel_buffer_texture_get_type())

// Forward declarations
static GstFlowReturn on_new_sample(GstAppSink* appsink, gpointer user_data);

// Defined with the knt_push_frame ABI below; dispose needs it first.
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

// Runs only from copy_pixels, which is the one writer of `buffer`.
static void apply_pending_color(MyTexture* self) {
  g_mutex_lock(&self->buffer_mutex);
  if (self->has_pending_color && self->buffer) {
    const size_t pixels =
        static_cast<size_t>(self->width) * static_cast<size_t>(self->height);
    for (size_t index = 0; index < pixels; ++index) {
      uint8_t* pixel = self->buffer + index * 4U;
      pixel[0] = self->pending_r;
      pixel[1] = self->pending_g;
      pixel[2] = self->pending_b;
      pixel[3] = 255U;
    }
    self->has_pending_color = FALSE;
  }
  g_mutex_unlock(&self->buffer_mutex);
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

static gboolean my_texture_copy_pixels(FlPixelBufferTexture* texture,
                                       const uint8_t** out_buffer,
                                       uint32_t* width, uint32_t* height,
                                       GError** error) {
  (void)error;
  MyTexture* self = MY_TEXTURE(texture);

  // A failed allocation leaves buffer null; failing makes Flutter skip the frame instead of crashing.
  if (!self->buffer) {
    return FALSE;
  }

  const size_t buffer_size =
      static_cast<size_t>(self->width) * static_cast<size_t>(self->height) * 4U;

  // A pushed frame wins (Rust owns the camera then); copied row-wise since its geometry is the camera's.
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

  // A queued colour must survive a run without a frame and never overwrite one.
  gboolean copied_frame = FALSE;
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
          copied_frame = TRUE;
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
        copied_frame = TRUE;

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

  if (!copied_frame) {
    apply_pending_color(self);
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

  // Queue for copy_pixels; writing `buffer` here would race the raster thread.
  g_mutex_lock(&self->buffer_mutex);
  self->pending_r = r;
  self->pending_g = g;
  self->pending_b = b;
  self->has_pending_color = TRUE;
  g_mutex_unlock(&self->buffer_mutex);

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
  self->has_pending_color = FALSE;
  self->pending_r = 0U;
  self->pending_g = 0U;
  self->pending_b = 0U;
  g_mutex_init(&self->sample_mutex);
  g_mutex_init(&self->pushed_mutex);
  g_mutex_init(&self->buffer_mutex);
}

FlTexture* my_texture_new(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b) {
  MyTexture* self = MY_TEXTURE(g_object_new(my_texture_get_type(), nullptr));
  self->width = width;
  self->height = height;
  // size_t: the 32-bit product wraps past ~4096x4096 and would under-allocate.
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

static GstFlowReturn on_new_sample(GstAppSink* appsink, gpointer user_data) {
  MyTexture* self = MY_TEXTURE(user_data);
  
  GstSample* sample = gst_app_sink_pull_sample(appsink);
  if (!sample) {
    return GST_FLOW_ERROR;
  }
  
  g_mutex_lock(&self->sample_mutex);

  if (self->last_sample) {
    gst_sample_unref(self->last_sample);
  }

  self->last_sample = sample;
  self->frame_counter += 1U;

  g_mutex_unlock(&self->sample_mutex);
  
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
  
  self->pipeline = gst_parse_launch(pipeline_description, error);
  if (!self->pipeline) {
    return FALSE;
  }

  // A recoverable problem sets `error` next to a valid pipeline; left set, it leaks and reads as failure.
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
  
  GstAppSinkCallbacks callbacks = {};
  callbacks.new_sample = on_new_sample;
  gst_app_sink_set_callbacks(GST_APP_SINK(self->appsink), &callbacks, self, nullptr);
  
  return TRUE;
}

// Drains the first bus ERROR into `error`; FALSE when a failed state change posted none.
static gboolean take_first_bus_error(GstElement* pipeline, GError** error) {
  GstBus* bus = gst_element_get_bus(pipeline);
  if (!bus) {
    return FALSE;
  }

  // The pipeline already failed: the message is queued or never coming, so a short bounded wait.
  GstMessage* msg =
      gst_bus_timed_pop_filtered(bus, 500 * GST_MSECOND, GST_MESSAGE_ERROR);
  gboolean found = FALSE;

  if (msg) {
    GError* err = nullptr;
    gchar* dbg = nullptr;
    gst_message_parse_error(msg, &err, &dbg);
    if (error && err) {
      // The debug string names the device and element, so it goes through to Dart.
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

  // A caps failure returns ASYNC and fails only later, so wait for it; a missing device fails synchronously.
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
    // A failed v4l2src left in READY keeps the camera claimed and fails the next setPipeline.
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

void my_texture_set_texture_registrar(FlTexture* texture, FlTextureRegistrar* registrar) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_if_fail(MY_IS_TEXTURE(self));
  self->texture_registrar = registrar;
  self->logged_no_registrar = FALSE;
  g_message("[my_texture] texture registrar assigned");
}
// knt_push_frame C ABI, identical to the Windows one. See docs/source/camera-streaming.md § Rust-owned webcam inference

namespace {

// Raw pointers: the plugin unregisters before destruction, and my_texture_dispose sweeps as a backstop.
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

// 0 on success; -1 bad arguments, -2 unknown texture id, -3 copy failed (the Windows codes).
__attribute__((visibility("default"))) int32_t knt_push_frame(
    int64_t texture_id, const uint8_t* rgba, uint32_t width, uint32_t height) {
  if (!rgba || width == 0U || height == 0U) {
    return -1;
  }

  // Held across the copy so the texture cannot be destroyed mid-memcpy.
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

  // Must run on the main loop, not the capture thread; the ref keeps the texture alive until then.
  g_object_ref(self);
  g_idle_add(mark_texture_frame_available_on_main, self);

  g_mutex_unlock(PushTargetsMutex());
  return 0;
}

__attribute__((visibility("default"))) int32_t knt_api_version() { return 1; }

}  // extern "C"

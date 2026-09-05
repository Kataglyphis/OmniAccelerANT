module;

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <algorithm>
#include <cstdint>
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

  guint64 frame_counter;
  gboolean logged_no_registrar;
  gboolean logged_first_sample;
};

G_DEFINE_TYPE(MyTexture, my_texture, fl_pixel_buffer_texture_get_type())

// Forward declarations
static GstFlowReturn on_new_sample(GstAppSink* appsink, gpointer user_data);

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
  
  const size_t buffer_size =
      static_cast<size_t>(self->width) * static_cast<size_t>(self->height) * 4U;

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

  const uint32_t pixels = self->width * self->height;
  for (uint32_t i = 0; i < pixels; ++i) {
    uint8_t* p = self->buffer + i * 4;
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
  self->frame_counter = 0U;
  self->logged_no_registrar = FALSE;
  self->logged_first_sample = FALSE;
  g_mutex_init(&self->sample_mutex);
}

FlTexture* my_texture_new(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b) {
  MyTexture* self = MY_TEXTURE(g_object_new(my_texture_get_type(), nullptr));
  self->width = width;
  self->height = height;
  self->buffer = static_cast<uint8_t*>(malloc(width * height * 4));
  memset(self->buffer, 0, width * height * 4);

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

void my_texture_play(FlTexture* texture) {
  MyTexture* self = MY_TEXTURE(texture);
  g_return_if_fail(MY_IS_TEXTURE(self));
  
  if (self->pipeline) {
    const GstStateChangeReturn result =
        gst_element_set_state(self->pipeline, GST_STATE_PLAYING);
    g_message("[my_texture] set PLAYING result=%d", static_cast<int>(result));
  }
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
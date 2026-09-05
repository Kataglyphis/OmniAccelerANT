module;

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>
#include <cstdint>

export module kataglyphis.my_texture;

export FlTexture* my_texture_new(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b);

export void my_texture_set_color(FlTexture* texture, uint8_t r, uint8_t g, uint8_t b);

export void my_texture_set_texture_registrar(FlTexture* texture, FlTextureRegistrar* registrar);

export gboolean my_texture_set_pipeline(FlTexture* texture, const gchar* pipeline_description, GError** error);

export void my_texture_play(FlTexture* texture);
export void my_texture_pause(FlTexture* texture);
export void my_texture_stop(FlTexture* texture);
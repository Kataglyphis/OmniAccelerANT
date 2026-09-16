module;

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>
#include <cstdint>

export module kataglyphis.my_texture;

export FlTexture* my_texture_new(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b);

export void my_texture_set_color(FlTexture* texture, uint8_t r, uint8_t g, uint8_t b);

export void my_texture_set_texture_registrar(FlTexture* texture, FlTextureRegistrar* registrar);

// Registry backing the knt_push_frame C ABI. The plugin registers a texture
// once fl_texture_registrar_register_texture has assigned its id, and
// unregisters it before the texture is destroyed — otherwise a frame pushed
// from the Rust capture thread could reach a freed object.
export void my_texture_register_push_target(int64_t texture_id, FlTexture* texture);
export void my_texture_unregister_push_target(int64_t texture_id);

export gboolean my_texture_set_pipeline(FlTexture* texture, const gchar* pipeline_description, GError** error);

// Returns FALSE and sets `error` when the pipeline does not reach PLAYING.
// pause/stop stay void: a failure there is not what leaves the page showing a
// blank texture with no explanation, and widening them would churn three more
// call sites for no reported symptom.
export gboolean my_texture_play(FlTexture* texture, GError** error);
export void my_texture_pause(FlTexture* texture);
export void my_texture_stop(FlTexture* texture);
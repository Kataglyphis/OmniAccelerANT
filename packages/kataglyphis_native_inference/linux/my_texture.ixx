module;

#include <cstddef>
#include <cstdint>
#include <flutter_linux/flutter_linux.h>

export module kataglyphis.my_texture;

// Bytes of one packed RGBA frame, or 0 for a zero side or a count size_t cannot hold.
export size_t my_texture_frame_bytes(uint32_t width, uint32_t height);

// nullptr when the frame's bytes do not fit or cannot be allocated.
export FlTexture *my_texture_new(uint32_t width, uint32_t height, uint8_t r, uint8_t g, uint8_t b);

export void my_texture_set_color(FlTexture *texture, uint8_t r, uint8_t g, uint8_t b);

export void my_texture_set_texture_registrar(FlTexture *texture, FlTextureRegistrar *registrar);

// Registry backing the knt_push_frame C ABI. The plugin registers a texture
// once fl_texture_registrar_register_texture has assigned its id, and
// unregisters it before the texture is destroyed — otherwise a frame pushed
// from the Rust capture thread could reach a freed object.
export void my_texture_register_push_target(int64_t texture_id, FlTexture *texture);
export void my_texture_unregister_push_target(int64_t texture_id);
// TRUE once knt_push_frame has filled this texture: the proof the integration test reads.
export gboolean my_texture_has_pushed_frame(int64_t texture_id);
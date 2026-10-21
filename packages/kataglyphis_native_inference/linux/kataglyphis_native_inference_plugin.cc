import kataglyphis.my_texture;
import kataglyphis.c_api;

#include "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <array>
#include <cstring>
#include <limits>

#include "kataglyphis_native_inference_plugin_private.h"

#define KATAGLYPHIS_NATIVE_INFERENCE_PLUGIN(obj) \
    (G_TYPE_CHECK_INSTANCE_CAST(                 \
      (obj), kataglyphis_native_inference_plugin_get_type(), KataglyphisNativeInferencePlugin))

struct _KataglyphisNativeInferencePlugin
{
    GObject parent_instance;
    char **dart_entrypoint_arguments;

    /* Channel to receive general method calls from Flutter. */
    FlMethodChannel *channel;

    /* Channel to receive texture requests from Flutter (optional, only when a view is present). */
    FlMethodChannel *texture_channel;

    /* Texture we've created (optional). */
    FlTexture *texture;

    /* The FlView associated with the registrar (may be NULL). */
    FlView *view;
};

G_DEFINE_TYPE(KataglyphisNativeInferencePlugin, kataglyphis_native_inference_plugin, g_object_get_type())

using MethodHandler = FlMethodResponse *(*)(KataglyphisNativeInferencePlugin *, FlMethodCall *);

static bool is_fl_type(const FlValue *value, int expected)
{
    if (value == nullptr) { return false; }
    return static_cast<int>(fl_value_get_type(const_cast<FlValue *>(value))) == expected;
}

static uint32_t clamp_to_u32(gint64 value)
{
    if (value < 0) { return 0U; }
    if (value > static_cast<gint64>(std::numeric_limits<uint32_t>::max())) {
        return std::numeric_limits<uint32_t>::max();
    }
    return static_cast<uint32_t>(value);
}

FlMethodResponse *get_platform_version(void);

// Whether knt_push_frame has filled the texture yet; false before one exists.
static FlMethodResponse *handle_has_pushed_frame(KataglyphisNativeInferencePlugin *self, FlMethodCall * /*method_call*/)
{
    const gboolean pushed = self->texture != nullptr && my_texture_has_pushed_frame(fl_texture_get_id(self->texture));
    g_autoptr(FlValue) result = fl_value_new_bool(pushed);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Handle request to create the texture.
static FlMethodResponse *handle_create(KataglyphisNativeInferencePlugin *self, FlMethodCall *method_call)
{
    if (self->texture != nullptr) {
        g_autoptr(FlValue) id = fl_value_new_int(fl_texture_get_id(self->texture));
        return FL_METHOD_RESPONSE(fl_method_success_response_new(id));
    }

    FlValue *args = fl_method_call_get_args(method_call);
    if (!is_fl_type(args, FL_VALUE_TYPE_LIST) || fl_value_get_length(args) != 2) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("Invalid args", "Invalid create args", nullptr));
    }
    FlValue *width_value = fl_value_get_list_value(args, 0);
    FlValue *height_value = fl_value_get_list_value(args, 1);
    if (!is_fl_type(width_value, FL_VALUE_TYPE_INT) || !is_fl_type(height_value, FL_VALUE_TYPE_INT)) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("Invalid args", "Invalid create args", nullptr));
    }

    const uint32_t width = clamp_to_u32(fl_value_get_int(width_value));
    const uint32_t height = clamp_to_u32(fl_value_get_int(height_value));
    if (width == 0U || height == 0U) {
        return FL_METHOD_RESPONSE(
          fl_method_error_response_new("Invalid args", "Width and height must be > 0", nullptr));
    }

    FlEngine *engine = fl_view_get_engine(self->view);
    FlTextureRegistrar *texture_registrar = fl_engine_get_texture_registrar(engine);

    self->texture = my_texture_new(width, height, 0x05U, 0x53U, 0xb1U);

    // Pushed frames reach Flutter through the registrar.
    my_texture_set_texture_registrar(self->texture, texture_registrar);

    if (!fl_texture_registrar_register_texture(texture_registrar, self->texture)) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("Error", "Failed to register texture", nullptr));
    }

    // Lets knt_push_frame reach this texture.
    const int64_t texture_id = fl_texture_get_id(self->texture);
    my_texture_register_push_target(texture_id, self->texture);

    // Return the texture ID to Flutter so it can use this texture.
    g_autoptr(FlValue) id = fl_value_new_int(texture_id);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(id));
}

static FlMethodResponse *handle_get_platform_version(KataglyphisNativeInferencePlugin * /*self*/,
  FlMethodCall * /*method_call*/)
{ return get_platform_version(); }

static FlMethodResponse *handle_add(KataglyphisNativeInferencePlugin * /*self*/, FlMethodCall *method_call)
{
    FlValue *args = fl_method_call_get_args(method_call);
    if (!is_fl_type(args, FL_VALUE_TYPE_MAP)) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("bad_args", "Expected argument map", nullptr));
    }

    FlValue *a_val = fl_value_lookup_string(args, "a");
    FlValue *b_val = fl_value_lookup_string(args, "b");
    if (!is_fl_type(a_val, FL_VALUE_TYPE_INT) || !is_fl_type(b_val, FL_VALUE_TYPE_INT)) {
        return FL_METHOD_RESPONSE(
          fl_method_error_response_new("bad_args", "Expected integer 'a' and 'b' in the argument map", nullptr));
    }

    const gint64 raw_a = fl_value_get_int(a_val);
    const gint64 raw_b = fl_value_get_int(b_val);
    const gint64 min_int = static_cast<gint64>(std::numeric_limits<int>::min());
    const gint64 max_int = static_cast<gint64>(std::numeric_limits<int>::max());
    const gint64 clamped_a = raw_a < min_int ? min_int : (raw_a > max_int ? max_int : raw_a);
    const gint64 clamped_b = raw_b < min_int ? min_int : (raw_b > max_int ? max_int : raw_b);

    const int result = kataglyphis_add(static_cast<int>(clamped_a), static_cast<int>(clamped_b));
    g_autoptr(FlValue) result_value = fl_value_new_int(result);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
}

/* Handles general plugin method calls on the single channel; the Rust core drives the camera, so no pipeline calls. */
static void kataglyphis_native_inference_plugin_handle_method_call(KataglyphisNativeInferencePlugin *self,
  FlMethodCall *method_call)
{
    g_autoptr(FlMethodResponse) response = NULL;

    const gchar *method = fl_method_call_get_name(method_call);

    static constexpr std::array<std::pair<const char *, MethodHandler>, 4> kHandlers = { {
      { "getPlatformVersion", handle_get_platform_version },
      { "add", handle_add },
      { "create", handle_create },
      { "hasPushedFrame", handle_has_pushed_frame },
    } };

    for (const auto &handler : kHandlers) {
        if (std::strcmp(method, handler.first) == 0) {
            response = handler.second(self, method_call);
            break;
        }
    }

    if (response == nullptr) { response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()); }

    /* Single call to respond. response must be a valid FlMethodResponse*. */
    fl_method_call_respond(method_call, response, NULL);
}


FlMethodResponse *get_platform_version()
{
    struct utsname uname_data = {};
    uname(&uname_data);
    g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
    g_autoptr(FlValue) result = fl_value_new_string(version);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void kataglyphis_native_inference_plugin_dispose(GObject *object)
{
    KataglyphisNativeInferencePlugin *self = KATAGLYPHIS_NATIVE_INFERENCE_PLUGIN(object);

    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    g_clear_object(&self->channel);
    g_clear_object(&self->texture_channel);
    // Unregister before the unref, so an in-flight Rust frame cannot find a freed texture.
    if (self->texture) { my_texture_unregister_push_target(fl_texture_get_id(self->texture)); }
    g_clear_object(&self->texture);
    if (self->view) { g_clear_object(&self->view); }

    G_OBJECT_CLASS(kataglyphis_native_inference_plugin_parent_class)->dispose(object);
}

static void kataglyphis_native_inference_plugin_class_init(KataglyphisNativeInferencePluginClass *klass)
{ G_OBJECT_CLASS(klass)->dispose = kataglyphis_native_inference_plugin_dispose; }

static void kataglyphis_native_inference_plugin_init(KataglyphisNativeInferencePlugin *self)
{
    self->dart_entrypoint_arguments = nullptr;
    self->channel = nullptr;
    self->texture_channel = nullptr;
    self->texture = nullptr;
    self->view = nullptr;
}

static void method_call_cb(FlMethodChannel * /*channel*/, FlMethodCall *method_call, gpointer user_data)
{
    KataglyphisNativeInferencePlugin *plugin = KATAGLYPHIS_NATIVE_INFERENCE_PLUGIN(user_data);
    kataglyphis_native_inference_plugin_handle_method_call(plugin, method_call);
}

void kataglyphis_native_inference_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
    KataglyphisNativeInferencePlugin *plugin =
      KATAGLYPHIS_NATIVE_INFERENCE_PLUGIN(g_object_new(kataglyphis_native_inference_plugin_get_type(), nullptr));

    /* Save a reference to the FlView if present (texture features require a view). */
    FlView *view = fl_plugin_registrar_get_view(registrar);
    if (view) { plugin->view = FL_VIEW(g_object_ref(view)); }

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "kataglyphis_native_inference", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(channel, method_call_cb, g_object_ref(plugin), g_object_unref);

    g_object_unref(plugin);
}

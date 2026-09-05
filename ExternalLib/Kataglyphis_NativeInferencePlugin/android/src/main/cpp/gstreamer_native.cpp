#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/log.h>

#include <gst/gst.h>
#include <gst/video/videooverlay.h>
#include <gst/app/gstappsink.h>

#include <glib.h>

#include <thread>

// The GStreamer Android SDK provides JNI helpers (libgstandroidmedia) that need the JavaVM
// to be set before plugins like androidmedia can initialize/register correctly.
// The SDK doesn't always ship public headers for these helpers; declare what we use.
extern "C" {
#ifdef GST_ANDROIDMEDIA_AVAILABLE
void gst_amc_jni_set_java_vm(JavaVM *java_vm);
void gst_amc_jni_initialize(void);
#endif
}

// Register the static plugins we link in.
// Wrap in extern "C" so the symbols keep C linkage and match the plugin archives.
extern "C" {
GST_PLUGIN_STATIC_DECLARE(coreelements);  // Contains videoconvert, videoscale, appsink, appsrc
GST_PLUGIN_STATIC_DECLARE(app);
GST_PLUGIN_STATIC_DECLARE(videotestsrc);
#ifdef GST_AUTODETECT_AVAILABLE
GST_PLUGIN_STATIC_DECLARE(autodetect);
#endif
#ifdef GST_ANDROIDMEDIA_AVAILABLE
GST_PLUGIN_STATIC_DECLARE(androidmedia);  // Android media plugin (Camera1) - if available
#endif
#ifdef GST_VIDEOCONVERT_AVAILABLE
// Many GStreamer Android SDKs ship videoconvert/videoscale in the combined plugin "videoconvertscale".
GST_PLUGIN_STATIC_DECLARE(videoconvertscale);
#endif
#ifdef GST_AHC_AVAILABLE
GST_PLUGIN_STATIC_DECLARE(ahc);           // Android Camera NDK (Camera2) - modern camera source
// Some GStreamer Android SDK builds ship the Camera2 NDK source under the plugin name "ndk".
// Our CMake already keeps `gst_plugin_ndk_register` alive, but we must also declare/register it
// here to make elements like `ahc2src`/`ahcsrc` available at runtime.
GST_PLUGIN_STATIC_DECLARE(ndk);
#endif
GST_PLUGIN_STATIC_DECLARE(opengl);
}

#include <mutex>
#include <string>

namespace {
constexpr const char *kTag = "KataglyphisGStreamer";

#ifdef GST_ANDROIDMEDIA_AVAILABLE
constexpr const char *kFlagAndroidMedia = "1";
#else
constexpr const char *kFlagAndroidMedia = "0";
#endif

#ifdef GST_AHC_AVAILABLE
constexpr const char *kFlagAhc = "1";
#else
constexpr const char *kFlagAhc = "0";
#endif

// Track if the JNI VM has been set for GStreamer Android media plugins.
bool g_jni_vm_set = false;

struct GstContextState {
    GstElement *pipeline = nullptr;
    ANativeWindow *window = nullptr;
    bool initialized = false;

    // Some Android camera sources rely on a running GLib main loop.
    // We start one once per process and keep it running.
    GMainContext *main_context = nullptr;
    GMainLoop *main_loop = nullptr;
    bool main_loop_started = false;
};

std::mutex g_mutex;
GstContextState g_state;
std::string g_last_error;

void setLastError(const std::string &msg) {
    g_last_error = msg;
    __android_log_print(ANDROID_LOG_ERROR, kTag, "%s", msg.c_str());
}

void appendLastError(const std::string &msg) {
    if (!g_last_error.empty()) g_last_error += "\n";
    g_last_error += msg;
    __android_log_print(ANDROID_LOG_ERROR, kTag, "%s", msg.c_str());
}

void logError(const char *msg) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "%s", msg);
}

void logInfo(const char *msg) {
    __android_log_print(ANDROID_LOG_INFO, kTag, "%s", msg);
}

const char *stateToStr(GstState state) {
    switch (state) {
        case GST_STATE_VOID_PENDING: return "VOID_PENDING";
        case GST_STATE_NULL: return "NULL";
        case GST_STATE_READY: return "READY";
        case GST_STATE_PAUSED: return "PAUSED";
        case GST_STATE_PLAYING: return "PLAYING";
        default: return "UNKNOWN";
    }
}

void logBusMessages(GstBus *bus) {
    if (!bus) return;
    while (GstMessage *msg = gst_bus_pop_filtered(
               bus, static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_WARNING))) {
        switch (GST_MESSAGE_TYPE(msg)) {
            case GST_MESSAGE_ERROR: {
                GError *err = nullptr;
                gchar *dbg = nullptr;
                gst_message_parse_error(msg, &err, &dbg);
                const std::string line = std::string("bus error: ") +
                                         (err ? err->message : "unknown") +
                                         " (" + (dbg ? dbg : "no debug") + ")";
                appendLastError(line);
                if (err) g_error_free(err);
                if (dbg) g_free(dbg);
                break;
            }
            case GST_MESSAGE_WARNING: {
                GError *err = nullptr;
                gchar *dbg = nullptr;
                gst_message_parse_warning(msg, &err, &dbg);
                const std::string line = std::string("bus warning: ") +
                                         (err ? err->message : "unknown") +
                                         " (" + (dbg ? dbg : "no debug") + ")";
                appendLastError(line);
                if (err) g_error_free(err);
                if (dbg) g_free(dbg);
                break;
            }
            default:
                break;
        }
        gst_message_unref(msg);
    }
}

void logBusMessagesWithWait(GstBus *bus, guint64 timeoutNanos) {
    if (!bus) return;
    const GstMessageType mask = static_cast<GstMessageType>(
        GST_MESSAGE_ERROR | GST_MESSAGE_WARNING | GST_MESSAGE_INFO |
        GST_MESSAGE_ASYNC_DONE | GST_MESSAGE_STATE_CHANGED);

    while (GstMessage *msg = gst_bus_timed_pop_filtered(bus, timeoutNanos, mask)) {
        switch (GST_MESSAGE_TYPE(msg)) {
            case GST_MESSAGE_ERROR: {
                GError *err = nullptr;
                gchar *dbg = nullptr;
                gst_message_parse_error(msg, &err, &dbg);
                const std::string line = std::string("bus error: ") +
                                         (err ? err->message : "unknown") +
                                         " (" + (dbg ? dbg : "no debug") + ")";
                appendLastError(line);
                if (err) g_error_free(err);
                if (dbg) g_free(dbg);
                break;
            }
            case GST_MESSAGE_WARNING: {
                GError *err = nullptr;
                gchar *dbg = nullptr;
                gst_message_parse_warning(msg, &err, &dbg);
                const std::string line = std::string("bus warning: ") +
                                         (err ? err->message : "unknown") +
                                         " (" + (dbg ? dbg : "no debug") + ")";
                appendLastError(line);
                if (err) g_error_free(err);
                if (dbg) g_free(dbg);
                break;
            }
            case GST_MESSAGE_INFO: {
                GError *err = nullptr;
                gchar *dbg = nullptr;
                gst_message_parse_info(msg, &err, &dbg);
                const std::string line = std::string("bus info: ") +
                                         (err ? err->message : "unknown") +
                                         " (" + (dbg ? dbg : "no debug") + ")";
                __android_log_print(ANDROID_LOG_INFO, kTag, "%s", line.c_str());
                if (err) g_error_free(err);
                if (dbg) g_free(dbg);
                break;
            }
            case GST_MESSAGE_ASYNC_DONE: {
                __android_log_print(ANDROID_LOG_INFO, kTag, "bus async-done");
                break;
            }
            case GST_MESSAGE_STATE_CHANGED: {
                GstState oldState, newState, pending;
                gst_message_parse_state_changed(msg, &oldState, &newState, &pending);
                __android_log_print(ANDROID_LOG_INFO, kTag,
                                    "bus state-changed: %s -> %s (pending %s)",
                                    stateToStr(oldState), stateToStr(newState), stateToStr(pending));
                break;
            }
            default:
                break;
        }
        gst_message_unref(msg);
    }
}

const char *stateChangeReturnToStr(GstStateChangeReturn ret) {
    switch (ret) {
        case GST_STATE_CHANGE_FAILURE: return "FAILURE";
        case GST_STATE_CHANGE_SUCCESS: return "SUCCESS";
        case GST_STATE_CHANGE_ASYNC: return "ASYNC";
        case GST_STATE_CHANGE_NO_PREROLL: return "NO_PREROLL";
        default: return "UNKNOWN";
    }
}

void ensure_gst_init_unlocked() {
    if (g_state.initialized) return;
    int argc = 0;
    char **argv = nullptr;
    gst_init(&argc, &argv);

    __android_log_print(ANDROID_LOG_INFO, kTag,
                        "Compile flags: androidmedia=%s ahc=%s",
                        kFlagAndroidMedia, kFlagAhc);

    // Start a GLib main loop in the background. This is frequently required for Android
    // camera sources (Camera1/Camera2) to post callbacks and state changes.
    if (!g_state.main_loop_started) {
        g_state.main_context = g_main_context_new();
        g_state.main_loop = g_main_loop_new(g_state.main_context, FALSE);
        GMainContext *ctx = g_state.main_context;
        GMainLoop *loop = g_state.main_loop;
        std::thread([ctx, loop]() {
            g_main_context_push_thread_default(ctx);
            g_main_loop_run(loop);
            g_main_context_pop_thread_default(ctx);
        }).detach();
        g_state.main_loop_started = true;
        logInfo("Started GLib main loop thread");
    }

#ifdef GST_ANDROIDMEDIA_AVAILABLE
    // Initialize GStreamer Android JNI subsystem BEFORE registering androidmedia plugin.
    // This ensures gst_amc_jni_get_env() works during plugin registration and that
    // Java classes (Camera, MediaCodec, etc.) can be loaded via the application class loader.
    // NOTE: gst_amc_jni_set_java_vm() must have been called before this point (in init()).
    if (g_jni_vm_set) {
        gst_amc_jni_initialize();
        __android_log_print(ANDROID_LOG_INFO, kTag, "gst_amc_jni_initialize called");
    } else {
        __android_log_print(ANDROID_LOG_WARN, kTag, 
            "JavaVM not set - androidmedia plugin may not work. Call init() first!");
    }
#endif

    // Register all necessary plugins
    GST_PLUGIN_STATIC_REGISTER(coreelements);  // videoconvert, appsink, appsrc, videoscale
    GST_PLUGIN_STATIC_REGISTER(app);           // app elements
    GST_PLUGIN_STATIC_REGISTER(videotestsrc);  // test patterns
#ifdef GST_AUTODETECT_AVAILABLE
    {
        gst_plugin_autodetect_register();
        GstPlugin *plugin = gst_registry_find_plugin(gst_registry_get(), "autodetect");
        __android_log_print(ANDROID_LOG_INFO, kTag, "Static register autodetect: %s", plugin ? "ok" : "fail");
        if (plugin) gst_object_unref(plugin);
    }
#endif
#ifdef GST_ANDROIDMEDIA_AVAILABLE
    {
        gst_plugin_androidmedia_register();
        GstPlugin *plugin = gst_registry_find_plugin(gst_registry_get(), "androidmedia");
        __android_log_print(ANDROID_LOG_INFO, kTag, "Static register androidmedia: %s", plugin ? "ok" : "fail");
        if (plugin) gst_object_unref(plugin);
        
        // Check if camera elements are now available
        GstElementFactory *ahcsrc_factory = gst_element_factory_find("ahcsrc");
        GstElementFactory *ahc2src_factory = gst_element_factory_find("ahc2src");
        __android_log_print(ANDROID_LOG_INFO, kTag, "Camera elements: ahcsrc=%s ahc2src=%s",
                            ahcsrc_factory ? "yes" : "no", ahc2src_factory ? "yes" : "no");
        if (ahcsrc_factory) gst_object_unref(ahcsrc_factory);
        if (ahc2src_factory) gst_object_unref(ahc2src_factory);
    }
#endif
#ifdef GST_VIDEOCONVERT_AVAILABLE
    // Video format conversion + scaling (combined plugin in many Android SDK builds).
    GST_PLUGIN_STATIC_REGISTER(videoconvertscale);
#endif
#ifdef GST_AHC_AVAILABLE
    GST_PLUGIN_STATIC_REGISTER(ahc);           // Android Camera2 NDK (modern, preferred for Pixel 4+)
    GST_PLUGIN_STATIC_REGISTER(ndk);           // Android Camera2 NDK (alternate plugin name)
#endif
    GST_PLUGIN_STATIC_REGISTER(opengl);        // glimagesink, etc
    
    // Log available elements for debugging
    GstRegistry *registry = gst_registry_get();
    GList *plugins = gst_registry_get_plugin_list(registry);
    __android_log_print(ANDROID_LOG_INFO, kTag, "Registered %d GStreamer plugins", g_list_length(plugins));
    
    // Log plugin details for troubleshooting
    for (GList *item = plugins; item != nullptr; item = item->next) {
        GstPlugin *plugin = GST_PLUGIN(item->data);
        const char *name = gst_plugin_get_name(plugin);
        const char *version = gst_plugin_get_version(plugin);
        __android_log_print(ANDROID_LOG_INFO, kTag, "  Plugin: %s (v%s)", name, version);
    }
    
    g_list_free(plugins);
    
    g_state.initialized = true;
    logInfo("GStreamer initialized");
}

bool has_element_factory(const char *name) {
    if (!name) return false;
    GstElementFactory *factory = gst_element_factory_find(name);
    if (!factory) return false;
    gst_object_unref(factory);
    return true;
}

std::string diagnose_gstreamer_unlocked() {
    std::string out;
    out += "plugins:";

    const char *pluginNames[] = {
        "coreelements",
        "app",
        "videotestsrc",
        "autodetect",
        "opengl",
        "videoconvertscale",
        "androidmedia",
        "ahc",
        "ndk",
    };
    for (const char *p : pluginNames) {
        GstPlugin *plugin = gst_registry_find_plugin(gst_registry_get(), p);
        out += "\n- ";
        out += p;
        out += ": ";
        out += (plugin ? "yes" : "no");
        if (plugin) gst_object_unref(plugin);
    }

    out += "\n\nelements:";
    const char *elementNames[] = {
        "ahc2src",
        "ahcsrc",
        "androidvideosource",
        "autovideosrc",
        "videotestsrc",
        "videoconvert",
        "videoscale",
        "glimagesink",
        "glupload",
        "glcolorconvert",
        "appsink",
    };
    for (const char *e : elementNames) {
        out += "\n- ";
        out += e;
        out += ": ";
        out += (has_element_factory(e) ? "yes" : "no");
    }

    return out;
}

bool ensure_first_element_exists_unlocked(const std::string &pipelineDesc) {
    // We only inspect the first element name (up to first whitespace or '!'),
    // which matches how the app builds pipelines.
    std::string first = pipelineDesc;
    const size_t bang = first.find('!');
    if (bang != std::string::npos) first = first.substr(0, bang);

    const size_t start = first.find_first_not_of(" \t\n\r");
    if (start == std::string::npos) {
        setLastError("Pipeline string has no elements");
        return false;
    }
    first = first.substr(start);

    const size_t end = first.find_last_not_of(" \t\n\r");
    if (end != std::string::npos) first = first.substr(0, end + 1);

    const size_t ws = first.find_first_of(" \t\n\r");
    const std::string factoryName = (ws == std::string::npos) ? first : first.substr(0, ws);

    GstElementFactory *factory = gst_element_factory_find(factoryName.c_str());
    if (!factory) {
        setLastError(std::string("Missing GStreamer element: ") + factoryName);
        appendLastError("Diagnose:\n" + diagnose_gstreamer_unlocked());
        return false;
    }
    gst_object_unref(factory);
    return true;
}

void release_pipeline_unlocked() {
    if (g_state.pipeline) {
        gst_element_set_state(g_state.pipeline, GST_STATE_NULL);
        gst_object_unref(g_state.pipeline);
        g_state.pipeline = nullptr;
    }
}

void release_window_unlocked() {
    if (g_state.window) {
        ANativeWindow_release(g_state.window);
        g_state.window = nullptr;
    }
}

bool bind_overlay(GstElement *pipeline, ANativeWindow *window) {
    GstElement *overlay = nullptr;
    GstElement *appsink = nullptr;
    
    GstIterator *it = gst_bin_iterate_elements(GST_BIN(pipeline));
    GValue item = G_VALUE_INIT;
    while (gst_iterator_next(it, &item) == GST_ITERATOR_OK) {
        GstElement *element = GST_ELEMENT(g_value_get_object(&item));
        const gchar *element_name = gst_element_get_name(element);
        
        // Check for video overlay sink (e.g., glimagesink)
        if (GST_IS_VIDEO_OVERLAY(element)) {
            overlay = element;
            __android_log_print(ANDROID_LOG_INFO, kTag, "Found glimagesink: %s", element_name ? element_name : "unknown");
            g_value_reset(&item);
            break;
        }
        
        // Check for appsink by element factory name or by element name
        if (!appsink) {
            bool is_appsink = false;
            
            // Check by factory name
            GstElementFactory *factory = gst_element_get_factory(element);
            if (factory) {
                const gchar *factory_name = gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory));
                if (factory_name && std::string(factory_name) == "appsink") {
                    is_appsink = true;
                }
            }
            
            // Also check by element name (in case factory lookup fails)
            if (!is_appsink && element_name && std::string(element_name) == "sink") {
                is_appsink = true;
                __android_log_print(ANDROID_LOG_WARN, kTag, "Assuming element 'sink' is appsink based on name");
            }
            
            if (is_appsink) {
                appsink = element;
                __android_log_print(ANDROID_LOG_INFO, kTag, "Found appsink: %s", element_name ? element_name : "unknown");
            }
        }
        
        g_value_reset(&item);
    }
    gst_iterator_free(it);

    // If we have a video overlay, bind the window handle to it
    if (overlay) {
        gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(overlay), reinterpret_cast<guintptr>(window));
        logInfo("Bound window to glimagesink overlay");
        return true;
    }
    
    // If we have an appsink but no video overlay, that's OK (appsink doesn't need window handle)
    if (appsink) {
        logInfo("Using appsink sink (no window overlay required)");
        return true;
    }
    
    // Neither glimagesink nor appsink found
    __android_log_print(ANDROID_LOG_ERROR, kTag, "No video sink (glimagesink or appsink) found in pipeline");
    return false;
}

GstStateChangeReturn wait_for_state(GstElement *element, GstState target, GstClockTime timeout) {
    GstStateChangeReturn ret = GST_STATE_CHANGE_ASYNC;
    guint64 timeoutMs = timeout / 1000000;  // Convert nanoseconds to milliseconds
    guint64 maxWait = 15000;  // 15 seconds maximum
    if (timeoutMs > maxWait) timeoutMs = maxWait;
    
    // Use polling instead of blocking wait
    guint64 startMs = g_get_monotonic_time() / 1000;
    guint64 pollIntervalMs = 100;  // Poll every 100ms
    
    while (ret == GST_STATE_CHANGE_ASYNC) {
        GstState current, pending;
        ret = gst_element_get_state(element, &current, &pending, 0);  // Non-blocking query
        
        if (current == target) {
            return GST_STATE_CHANGE_SUCCESS;
        }
        
        guint64 elapsedMs = (g_get_monotonic_time() / 1000) - startMs;
        if (elapsedMs >= timeoutMs) {
            break;  // Timeout reached
        }
        
        // Small sleep to avoid busy-waiting
        g_usleep(pollIntervalMs * 1000);
    }
    
    return ret;
}

GstElement *find_factory(GstElement *pipeline, const char *factoryName) {
    GstElement *found = nullptr;
    GstIterator *it = gst_bin_iterate_elements(GST_BIN(pipeline));
    GValue item = G_VALUE_INIT;
    while (gst_iterator_next(it, &item) == GST_ITERATOR_OK) {
        GstElement *element = GST_ELEMENT(g_value_get_object(&item));
        const gchar *factory = gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(gst_element_get_factory(element)));
        if (factory && std::string(factory) == factoryName) {
            found = GST_ELEMENT(gst_object_ref(element));
            g_value_reset(&item);
            break;
        }
        g_value_reset(&item);
    }
    gst_iterator_free(it);
    return found;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_init(
        JNIEnv *env,
        jclass /*clazz*/,
        jobject context) {
    std::lock_guard<std::mutex> lock(g_mutex);

#ifdef GST_ANDROIDMEDIA_AVAILABLE
    // Ensure GStreamer Android JNI helpers can attach threads and access Java APIs.
    // gst_amc_jni_set_java_vm MUST be called before gst_amc_jni_initialize() 
    // (which is called in ensure_gst_init_unlocked) so that the androidmedia
    // plugin can access Java classes (Camera, MediaCodec, etc.).
    if (!g_jni_vm_set) {
        JavaVM *vm = nullptr;
        if (env && env->GetJavaVM(&vm) == JNI_OK && vm) {
            gst_amc_jni_set_java_vm(vm);
            g_jni_vm_set = true;
            __android_log_print(ANDROID_LOG_INFO, kTag, "Set JavaVM for GStreamer: %p", vm);
        } else {
            __android_log_print(ANDROID_LOG_ERROR, kTag, "Failed to get JavaVM from JNIEnv");
        }
    }
#endif

    (void)context;
    ensure_gst_init_unlocked();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_create(
        JNIEnv *env,
        jclass /*clazz*/,
        jobject surface) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!surface) {
        setLastError("Surface is null");
        return JNI_FALSE;
    }

    g_state.window = ANativeWindow_fromSurface(env, surface);
    if (!g_state.window) {
        setLastError("Failed to acquire ANativeWindow");
        return JNI_FALSE;
    }
    return JNI_TRUE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_getLastError(
        JNIEnv *env,
        jclass /*clazz*/) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return env->NewStringUTF(g_last_error.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_diagnose(
        JNIEnv *env,
        jclass /*clazz*/) {
    std::lock_guard<std::mutex> lock(g_mutex);
    ensure_gst_init_unlocked();
    const std::string report = diagnose_gstreamer_unlocked();
    return env->NewStringUTF(report.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_setPipeline(
        JNIEnv *env,
        jclass /*clazz*/,
        jstring pipelineStr) {
    std::lock_guard<std::mutex> lock(g_mutex);
    ensure_gst_init_unlocked();
    g_last_error.clear();

    if (!g_state.window) {
        setLastError("Window not created before setPipeline");
        return JNI_FALSE;
    }

    const char *cStr = env->GetStringUTFChars(pipelineStr, nullptr);
    std::string pipelineDesc(cStr ? cStr : "");
    if (cStr) env->ReleaseStringUTFChars(pipelineStr, cStr);

    if (pipelineDesc.empty()) {
        setLastError("Pipeline string is empty");
        return JNI_FALSE;
    }

    // Fast-fail for missing source elements to avoid 20s ASYNC waits.
    if (!ensure_first_element_exists_unlocked(pipelineDesc)) return JNI_FALSE;

    release_pipeline_unlocked();

    GError *err = nullptr;
    GstElement *pipeline = gst_parse_launch(pipelineDesc.c_str(), &err);
    if (!pipeline) {
        setLastError("gst_parse_launch returned null");
        if (err) {
            __android_log_print(ANDROID_LOG_ERROR, kTag, "parse error: %s", err->message);
            setLastError(std::string("parse error: ") + err->message);
            g_error_free(err);
        }
        return JNI_FALSE;
    }

    // Check if we have either a video overlay sink (glimagesink) or an app sink (appsink)
    // For Flutter textures with appsink, we don't need to bind a window overlay
    GstElement *overlay = nullptr;
    GstIterator *it = gst_bin_iterate_elements(GST_BIN(pipeline));
    GValue item = G_VALUE_INIT;
    bool hasVideoSink = false;
    
    while (gst_iterator_next(it, &item) == GST_ITERATOR_OK) {
        GstElement *element = GST_ELEMENT(g_value_get_object(&item));
        // Check for both overlay sinks (glimagesink) and app sinks
        if (GST_IS_VIDEO_OVERLAY(element) || GST_IS_APP_SINK(element)) {
            hasVideoSink = true;
            if (overlay == nullptr && GST_IS_VIDEO_OVERLAY(element)) {
                overlay = element;
            }
        }
        g_value_reset(&item);
    }
    gst_iterator_free(it);
    
    if (!hasVideoSink) {
        setLastError("No video sink (glimagesink or appsink) found in pipeline");
        gst_object_unref(pipeline);
        return JNI_FALSE;
    }
    
    // Only bind overlay if we found a video overlay sink
    if (overlay && g_state.window) {
        if (!bind_overlay(pipeline, g_state.window)) {
            setLastError("Failed to bind video overlay");
            gst_object_unref(pipeline);
            return JNI_FALSE;
        }
    }

    // Force READY first to avoid sticky pending states on reuse
    gst_element_set_state(pipeline, GST_STATE_READY);

    GstStateChangeReturn ret = gst_element_set_state(pipeline, GST_STATE_PAUSED);
    __android_log_print(ANDROID_LOG_INFO, kTag, "setPipeline set_state(PAUSED): %s",
                        stateChangeReturnToStr(ret));
    if (ret == GST_STATE_CHANGE_FAILURE) {
        setLastError("Failed to preroll pipeline");

        // Capture detailed element errors (e.g. camera open failures) from the bus.
        GstBus *bus = gst_element_get_bus(pipeline);
        logBusMessagesWithWait(bus, 500000000);  // 500ms
        if (bus) gst_object_unref(bus);

        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        return JNI_FALSE;
    }

    if (ret == GST_STATE_CHANGE_ASYNC) {
        // Increased timeout to 20s for slower devices and caps negotiation
        GstStateChangeReturn waitRet = wait_for_state(pipeline, GST_STATE_PAUSED, GST_SECOND * 20);
        __android_log_print(ANDROID_LOG_INFO, kTag, "setPipeline wait_for_state(PAUSED): %s",
                            stateChangeReturnToStr(waitRet));
        ret = waitRet;
        
        if (ret == GST_STATE_CHANGE_ASYNC) {
            setLastError("Pipeline still ASYNC after 20s - caps negotiation failed or source unavailable");

            // Try to get more detailed error info from bus
            GstBus *bus = gst_element_get_bus(pipeline);
            logBusMessagesWithWait(bus, 100000000);  // 100ms
            if (bus) gst_object_unref(bus);

            appendLastError("Diagnose:\n" + diagnose_gstreamer_unlocked());
        }
    }

    // Only accept SUCCESS or NO_PREROLL as valid results
    if (ret == GST_STATE_CHANGE_FAILURE || ret == GST_STATE_CHANGE_ASYNC) {
        if (g_last_error.empty()) {
            setLastError("Pipeline failed to reach PAUSED state");
        } else {
            appendLastError("Pipeline failed to reach PAUSED state");
        }
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        return JNI_FALSE;
    }

    g_state.pipeline = pipeline;
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_play(
        JNIEnv * /*env*/,
        jclass /*clazz*/) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.pipeline) return JNI_FALSE;
    GstStateChangeReturn ret = gst_element_set_state(g_state.pipeline, GST_STATE_PLAYING);
    __android_log_print(ANDROID_LOG_INFO, kTag, "play set_state(PLAYING): %s",
                        stateChangeReturnToStr(ret));

    if (ret == GST_STATE_CHANGE_ASYNC) {
        GstStateChangeReturn waitRet = wait_for_state(g_state.pipeline, GST_STATE_PLAYING, GST_SECOND * 10);
        __android_log_print(ANDROID_LOG_INFO, kTag, "play wait_for_state(PLAYING): %s",
                            stateChangeReturnToStr(waitRet));
        ret = waitRet;
    }

    if (ret == GST_STATE_CHANGE_FAILURE) {
        setLastError("Failed to set pipeline to PLAYING");
        GstBus *bus = gst_element_get_bus(g_state.pipeline);
        logBusMessagesWithWait(bus, 500000000);  // 500ms
        if (bus) gst_object_unref(bus);
    }

    return ret != GST_STATE_CHANGE_FAILURE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_pause(
        JNIEnv * /*env*/,
        jclass /*clazz*/) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.pipeline) return JNI_FALSE;
    GstStateChangeReturn ret = gst_element_set_state(g_state.pipeline, GST_STATE_PAUSED);
    __android_log_print(ANDROID_LOG_INFO, kTag, "pause set_state(PAUSED): %s",
                        stateChangeReturnToStr(ret));

    if (ret == GST_STATE_CHANGE_ASYNC) {
        GstStateChangeReturn waitRet = wait_for_state(g_state.pipeline, GST_STATE_PAUSED, GST_SECOND * 10);
        __android_log_print(ANDROID_LOG_INFO, kTag, "pause wait_for_state(PAUSED): %s",
                            stateChangeReturnToStr(waitRet));
        ret = waitRet;
    }

    return ret != GST_STATE_CHANGE_FAILURE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_stop(
        JNIEnv * /*env*/,
        jclass /*clazz*/) {
    std::lock_guard<std::mutex> lock(g_mutex);
    release_pipeline_unlocked();
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_setColor(
        JNIEnv * /*env*/,
        jclass /*clazz*/,
        jint r,
        jint g,
        jint b) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.pipeline) return JNI_FALSE;

    GstElement *src = find_factory(g_state.pipeline, "videotestsrc");
    if (!src) return JNI_FALSE;

    guint32 color = (0xFFu << 24) | ((static_cast<guint32>(r) & 0xFFu) << 16) |
                    ((static_cast<guint32>(g) & 0xFFu) << 8) |
                    (static_cast<guint32>(b) & 0xFFu);
    g_object_set(src, "foreground-color", color, NULL);
    gst_object_unref(src);
    return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_kataglyphis_1native_1inference_GStreamerNative_dispose(
        JNIEnv * /*env*/,
        jclass /*clazz*/) {
    std::lock_guard<std::mutex> lock(g_mutex);
    release_pipeline_unlocked();
    release_window_unlocked();
    g_state.initialized = true; // keep gst initialized to avoid re-init issues
}

} // namespace

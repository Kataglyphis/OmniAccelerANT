// ELF constructor: runs at load, before any reader. See docs/source/camera-streaming.md § Relocatable Linux bundles

#include <dlfcn.h>
#include <sys/stat.h>

#include <cstdio>
#include <cstdlib>
#include <string>

namespace {

bool path_exists(const std::string &path)
{
    struct stat info{};
    return ::stat(path.c_str(), &info) == 0;
}

void set_if_present(const char *name, const std::string &value)
{
    if (value.empty() || ::getenv(name) != nullptr) { return; }
    ::setenv(name, value.c_str(), 1);
}

// This shared object's directory; empty (trust nothing) when dladdr cannot say.
std::string module_directory()
{
    Dl_info info{};
    if (::dladdr(reinterpret_cast<void *>(&module_directory), &info) == 0 || info.dli_fname == nullptr) { return {}; }
    const std::string path = info.dli_fname;
    const std::size_t slash = path.find_last_of('/');
    if (slash == std::string::npos) { return {}; }
    return path.substr(0, slash);
}

void configure_bundle_paths()
{
#ifdef KATAGLYPHIS_DEFAULT_ORT_DEVICE
    set_if_present("KATAGLYPHIS_ORT_DEVICE", KATAGLYPHIS_DEFAULT_ORT_DEVICE);
    const char *device = ::getenv("KATAGLYPHIS_ORT_DEVICE");
    if (device != nullptr) {
        std::string normalized_device(device);
        for (char &character : normalized_device) {
            if (character >= 'A' && character <= 'Z') { character += 'a' - 'A'; }
        }
        if (normalized_device != "cpu" && normalized_device != "auto"
            && normalized_device != KATAGLYPHIS_DEFAULT_ORT_DEVICE) {
            std::fprintf(stderr, "Unsupported KATAGLYPHIS_ORT_DEVICE for this GPU package: %s\n", device);
            std::exit(EXIT_FAILURE);
        }
        if (normalized_device == "cuda" || normalized_device == "migraphx") {
            set_if_present("KATAGLYPHIS_ONNX_BACKEND", "ort");
        }
    }
#endif
    const std::string dir = module_directory();
    if (dir.empty()) { return; }
    const std::string gst_plugins = dir + "/gstreamer-1.0";
    if (path_exists(gst_plugins)) {
        set_if_present("GST_PLUGIN_PATH", gst_plugins);
        // Only the bundled plugins: a distro's are built against another GStreamer than the one bundled here.
        if (::getenv("GST_PLUGIN_SYSTEM_PATH_1_0") == nullptr) { ::setenv("GST_PLUGIN_SYSTEM_PATH_1_0", "", 1); }
        if (::getenv("GST_PLUGIN_SYSTEM_PATH") == nullptr) { ::setenv("GST_PLUGIN_SYSTEM_PATH", "", 1); }
        // The bundle ships no plugin scanner, so a fork would fail, warn and scan in-process anyway.
        set_if_present("GST_REGISTRY_FORK", "no");
    }
    const std::string onnxruntime = dir + "/libonnxruntime.so";
    if (path_exists(onnxruntime)) { set_if_present("ORT_DYLIB_PATH", onnxruntime); }
    const std::string model = dir + "/../data/resources/models/deim_dfine_n_coco.onnx";
    if (path_exists(model)) { set_if_present("KATAGLYPHIS_ONNX_MODEL", model); }
}

}// namespace

__attribute__((constructor)) static void kataglyphis_configure_bundle_paths() { configure_bundle_paths(); }

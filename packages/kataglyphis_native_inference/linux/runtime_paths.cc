// ELF constructor: runs at load, before any reader. See docs/source/camera-streaming.md § Relocatable Linux bundles

#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

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

// Started through bundle-loader.sh's launcher, the process image is the bundled ld.so itself.
bool running_under_bundled_loader()
{
    char buffer[4096];
    const ssize_t length = ::readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
    if (length <= 0) { return false; }
    const std::string exe(buffer, static_cast<std::size_t>(length));
    return exe.find("/ld-linux") != std::string::npos;
}

void configure_bundle_paths()
{
    // GStreamer hands its plugin scanner /proc/self/exe, the loader here; it fails, warns, then scans in-process anyway.
    if (running_under_bundled_loader()) { set_if_present("GST_REGISTRY_FORK", "no"); }

    const std::string dir = module_directory();
    if (dir.empty()) { return; }
    const std::string gst_plugins = dir + "/gstreamer-1.0";
    if (path_exists(gst_plugins)) { set_if_present("GST_PLUGIN_PATH", gst_plugins); }
    const std::string onnxruntime = dir + "/libonnxruntime.so";
    if (path_exists(onnxruntime)) { set_if_present("ORT_DYLIB_PATH", onnxruntime); }
    const std::string model = dir + "/../data/resources/models/deim_dfine_n_coco.onnx";
    if (path_exists(model)) { set_if_present("KATAGLYPHIS_ONNX_MODEL", model); }
}

}// namespace

__attribute__((constructor)) static void kataglyphis_configure_bundle_paths() { configure_bundle_paths(); }

// Relocatable-bundle runtime paths. The packaged app keeps GStreamer, ONNX
// Runtime and the detector model inside its own tree, so the absolute
// build-image paths baked into these ELFs must not be required at runtime.
//
// Why an ELF constructor: GStreamer reads GST_PLUGIN_PATH when its registry
// loads, ort reads ORT_DYLIB_PATH when it dlopens, and KATAGLYPHIS_ONNX_MODEL
// when the engine initialises - all after this library is loaded, none before.
// Each variable is only set when the sibling exists and the environment does
// not already name one, so a user override always wins.
// Rationale: docs/source/camera-streaming.md.

#include <dlfcn.h>
#include <sys/stat.h>

#include <cstdlib>
#include <string>

namespace {

bool path_exists(const std::string& path) {
  struct stat info {};
  return ::stat(path.c_str(), &info) == 0;
}

void set_if_present(const char* name, const std::string& value) {
  if (value.empty() || ::getenv(name) != nullptr) {
    return;
  }
  ::setenv(name, value.c_str(), 1);
}

// The directory this shared object was loaded from; empty when dladdr cannot
// say (a bare-name load), in which case nothing below can be trusted.
std::string module_directory() {
  Dl_info info{};
  if (::dladdr(reinterpret_cast<void*>(&module_directory), &info) == 0 ||
      info.dli_fname == nullptr) {
    return {};
  }
  const std::string path = info.dli_fname;
  const std::size_t slash = path.find_last_of('/');
  if (slash == std::string::npos) {
    return {};
  }
  return path.substr(0, slash);
}

void configure_bundle_paths() {
  const std::string dir = module_directory();
  if (dir.empty()) {
    return;
  }
  const std::string gst_plugins = dir + "/gstreamer-1.0";
  if (path_exists(gst_plugins)) {
    set_if_present("GST_PLUGIN_PATH", gst_plugins);
  }
  const std::string onnxruntime = dir + "/libonnxruntime.so";
  if (path_exists(onnxruntime)) {
    set_if_present("ORT_DYLIB_PATH", onnxruntime);
  }
  const std::string model = dir + "/../data/resources/models/yolov10m.onnx";
  if (path_exists(model)) {
    set_if_present("KATAGLYPHIS_ONNX_MODEL", model);
  }
}

}  // namespace

__attribute__((constructor)) static void kataglyphis_configure_bundle_paths() {
  configure_bundle_paths();
}

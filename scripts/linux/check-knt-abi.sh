#!/usr/bin/env bash
# Verifies the knt_* C ABI the Rust webcam engine depends on, headlessly.
#
# That ABI is resolved BY NAME at runtime with libloading, so a rename or a
# dropped export is not a compile error on either side: the app builds and then
# silently never shows a frame. This dlopens the plugin the way Rust does.
#
#   scripts/linux/check-knt-abi.sh [--bundle-lib DIR]
#
# Rationale and limits: docs/source/camera-streaming.md § Checking the knt ABI
set -euo pipefail

bundle_lib="build/linux/x64/release/bundle/lib"

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle-lib) bundle_lib="${2:?--bundle-lib needs a value}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--bundle-lib DIR]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

plugin="${bundle_lib}/libkataglyphis_native_inference_plugin.so"
[ -f "${plugin}" ] || {
  printf 'no plugin at %s — run a native build first\n' "${plugin}" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# The expected contract, copied from the Windows header so the two cannot
# drift silently:
#   int32_t knt_api_version(void)                     -> 1
#   int32_t knt_push_frame(int64_t, const uint8_t*,
#                          uint32_t, uint32_t)
#     0 ok | -1 bad arguments | -2 unknown texture id | -3 copy failed
cat > "${work}/check.c" <<'EOF'
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

typedef int32_t (*api_version_fn)(void);
typedef int32_t (*push_frame_fn)(int64_t, const uint8_t*, uint32_t, uint32_t);

int main(int argc, char** argv) {
  if (argc < 2) return 2;

  // RTLD_NOW so an unresolved symbol fails here rather than on first call,
  // which is also how a missing GTK/GStreamer dependency would surface.
  void* handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!handle) {
    fprintf(stderr, "FAIL dlopen: %s\n", dlerror());
    return 1;
  }

  api_version_fn api_version = (api_version_fn)dlsym(handle, "knt_api_version");
  if (!api_version) {
    fprintf(stderr, "FAIL knt_api_version not exported: %s\n", dlerror());
    return 1;
  }
  push_frame_fn push_frame = (push_frame_fn)dlsym(handle, "knt_push_frame");
  if (!push_frame) {
    fprintf(stderr, "FAIL knt_push_frame not exported: %s\n", dlerror());
    return 1;
  }

  const int32_t version = api_version();
  if (version != 1) {
    fprintf(stderr, "FAIL knt_api_version returned %d, expected 1\n", version);
    return 1;
  }
  printf("ok   knt_api_version   = %d\n", version);

  // Bad arguments: null buffer, and zero dimensions. Both must be -1, and must
  // not touch the registry — this is the branch that runs before any lookup.
  const uint8_t pixel[4] = {0, 0, 0, 255};
  if (push_frame(0, NULL, 1, 1) != -1) {
    fprintf(stderr, "FAIL knt_push_frame(null buffer) should be -1\n");
    return 1;
  }
  if (push_frame(0, pixel, 0, 1) != -1) {
    fprintf(stderr, "FAIL knt_push_frame(width 0) should be -1\n");
    return 1;
  }
  printf("ok   knt_push_frame    bad args -> -1\n");

  // No texture has been created in this process, so every id is unknown. -2
  // rather than a crash is what proves the registry lookup is guarded.
  if (push_frame(424242, pixel, 1, 1) != -2) {
    fprintf(stderr, "FAIL knt_push_frame(unknown id) should be -2\n");
    return 1;
  }
  printf("ok   knt_push_frame    unknown texture -> -2\n");

  dlclose(handle);
  return 0;
}
EOF

cc="${CC:-cc}"
command -v "${cc}" >/dev/null 2>&1 || cc=gcc
"${cc}" -O0 -o "${work}/check" "${work}/check.c" -ldl

printf 'checking %s\n' "${plugin}"
"${work}/check" "$(cd "$(dirname "${plugin}")" && pwd)/$(basename "${plugin}")"
printf 'knt ABI OK\n'

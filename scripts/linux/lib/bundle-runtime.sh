#!/usr/bin/env bash
# Shared by bundle-runtime-closure.sh and the bundle gates; sourced, never run.

# What the .deb's Depends provide, only what every GTK desktop has; not libstdc++, whose GCC 16.2 build no distro ships.
SYSTEM_SONAME_ALLOWLIST=(
  'libc.so.6' 'libm.so.6'
  'libpthread.so.0' 'libdl.so.2' 'librt.so.1'
  'ld-linux*.so*'
  # The rest of glibc: the bundled loader finds it through --library-path, never through a RUNPATH.
  'libmvec.so.1' 'libresolv.so.2' 'libutil.so.1' 'libanl.so.1' 'libnss_*.so.2'
  'libglib-2.0.so.0' 'libgobject-2.0.so.0' 'libgio-2.0.so.0'
  'libgmodule-2.0.so.0' 'libgthread-2.0.so.0' 'libz.so.1'
  'libgtk-3.so.0' 'libgdk-3.so.0' 'libatk-1.0.so.0'
  'libcairo.so.2' 'libcairo-gobject.so.2' 'libgdk_pixbuf-2.0.so.0'
  'libpango-1.0.so.0' 'libpangocairo-1.0.so.0' 'libharfbuzz.so.0'
  'libepoxy.so.0' 'libfontconfig.so.1'
)

select_gpu_runtime() {
  local lib="${1:?library directory required}" requested="${KATAGLYPHIS_ORT_PROVIDER:-}"
  GPU_RUNTIME_KIND=""
  if [[ -e "$lib/libonnxruntime_providers_cuda.so" ]]; then GPU_RUNTIME_KIND=cuda; fi
  if [[ -e "$lib/libonnxruntime_providers_migraphx.so" ]]; then
    [[ -z "$GPU_RUNTIME_KIND" ]] || { echo 'Error: bundle contains both CUDA and MIGraphX providers' >&2; return 1; }
    GPU_RUNTIME_KIND=migraphx
  fi
  if [[ -n "$requested" && "$requested" != "${GPU_RUNTIME_KIND:-cpu}" ]]; then
    printf 'Error: requested ORT provider %s does not match the bundled provider %s\n' "$requested" "${GPU_RUNTIME_KIND:-cpu}" >&2
    return 1
  fi
}

load_gpu_runtime_helpers() {
  local helper closure loader
  helper="$(antfrastructure_path linux/scripts/06-packaging/ort-runtime-bundle.sh)" || return 1
  closure="$(antfrastructure_path linux/scripts/06-packaging/elf-closure.sh)" || return 1
  loader="$(antfrastructure_path linux/scripts/06-packaging/bundle-loader.sh)" || return 1
  # shellcheck disable=SC1090
  source "$helper"
  if ! declare -F ort_host_runtime_needed >/dev/null || ! declare -F ort_assert_no_bundled_host_runtime >/dev/null ||
    ! grep -Fq -- '--direct-only' "$closure" || ! grep -Fq -- '--reject-source-root' "$closure" ||
    ! grep -Fq -- '--external-library-path' "$loader"; then
    echo 'Error: GPU bundles require ANTfrastructure host-runtime packaging support' >&2
    return 1
  fi
}

# The GPU provider loads vendor libraries from the user's host SDK.
prepare_gpu_host_runtime() {
  local bundle="${1:?bundle required}" lib="$1/lib" provider needed
  GPU_RUNTIME_SONAMES=()
  select_gpu_runtime "$lib" || return 1
  [[ -n "$GPU_RUNTIME_KIND" ]] || return 0
  [[ -f "$lib/libonnxruntime_providers_shared.so" ]] || { echo 'Error: shared ORT provider is missing' >&2; return 1; }
  load_gpu_runtime_helpers || return 1
  provider="$lib/libonnxruntime_providers_${GPU_RUNTIME_KIND}.so"
  needed="$(ort_host_runtime_needed "$provider" "$GPU_RUNTIME_KIND")" || return 1
  [[ -n "$needed" ]] || { echo 'Error: GPU provider has no host-runtime dependencies' >&2; return 1; }
  while IFS= read -r needed; do
    [[ -n "$needed" ]] || continue
    GPU_RUNTIME_SONAMES+=("$needed")
    SYSTEM_SONAME_ALLOWLIST+=("$needed")
  done <<< "$needed"
  ort_assert_no_bundled_host_runtime "$bundle" "$GPU_RUNTIME_KIND"
}

# Both loader branches must see the bundled libraries and the caller's host SDK path.
verify_gpu_host_launchers() {
  local bundle="${1:?bundle required}" launcher count=0
  for launcher in "$bundle"/*; do
    [[ -f "$launcher" && -x "$launcher" ]] || continue
    case "${launcher##*/}" in *.bin|ld-linux*.so*) continue ;; esac
    if [[ "$(head -c 2 -- "$launcher")" != '#!' ]] || [[ ! -f "${launcher}.bin" ]]; then
      echo 'FAIL GPU bundle executable is not an external-runtime launcher' >&2
      return 1
    fi
    count=$((count + 1))
    if ! grep -Fxq 'export LD_LIBRARY_PATH="$here/lib${external_library_path}"' "$launcher" ||
      ! grep -Fq -- '--library-path "$here/lib/glibc:$here/lib${external_library_path}"' "$launcher"; then
      echo 'FAIL GPU bundle launcher does not preserve its bundled and host library paths' >&2
      return 1
    fi
  done
  if [[ "$count" -eq 0 ]]; then
    echo 'FAIL GPU bundle has no external-runtime launcher' >&2
    return 1
  fi
}

gpu_package_name() {
  local name="${1:?name required}" kind="${2:?GPU provider required}" suffix
  case "$kind" in cuda) suffix=nvidia ;; migraphx) suffix=amd ;; *) return 2 ;; esac
  if [[ "$name" != *"-${suffix}" ]]; then name="${name}-${suffix}"; fi
  printf '%s\n' "$name"
}

is_system_soname() {
  local soname="$1" pattern
  for pattern in "${SYSTEM_SONAME_ALLOWLIST[@]}"; do
    # shellcheck disable=SC2254  # the glob is the point: ld-linux*.so*
    case "$soname" in $pattern) return 0 ;; esac
  done
  return 1
}

# Every plugin the Rust capture uses, the app's only pipeline on Linux; shared so none silently stops travelling.
# shellcheck disable=SC2034  # read by bundle-runtime-closure.sh and check-bundle-closure.sh
GST_BUNDLED_PLUGIN_NAMES=(
  coreelements app videoconvertscale videotestsrc autodetect video4linux2
)

# The elements OxidANT's capture.rs names (pinned_artefacts_test.dart reads it).
# shellcheck disable=SC2034  # read by check-bundle-gst-elements.sh
GST_PIPELINE_ELEMENTS=(
  appsink autovideosrc v4l2src videoconvert videoscale videotestsrc
)

# Exact token match: `$ORIGIN/lib` must not count as `$ORIGIN`.
runpath_has_token() {
  local file="$1" wanted="$2" dir
  local -a dirs=()
  IFS=':' read -r -a dirs <<< "$(elf_runpath "$file")"
  for dir in "${dirs[@]}"; do
    if [[ "$dir" == "$wanted" ]]; then
      return 0
    fi
  done
  return 1
}

# One DT_NEEDED soname per line.
elf_needed() {
  readelf -d "$1" 2>/dev/null | awk '/\(NEEDED\)/ {gsub(/[][\n]/,""); print $NF}'
}

elf_runpath() {
  readelf -d "$1" 2>/dev/null | awk '/\(RUNPATH\)/ {gsub(/[][\n]/,""); print $NF}'
}

# The chain's ORT_SRC_DIR, embedded via __FILE__; it only picks the directory, the verdict is G6's.
ORT_CHAIN_SOURCE_MARKER='/opt/onnxruntime/onnxruntime/core/'

# True when $1 (symlinks followed) was compiled from the chain's ORT checkout.
is_chain_ort_file() {
  grep -aqF -e "$ORT_CHAIN_SOURCE_MARKER" -- "$(readlink -f -- "$1")" 2>/dev/null
}

# The only dir a bundle may take ORT from; rc 1 unless its libonnxruntime.so is the chain's.
chain_ort_lib_dir() {
  local dir="${ORT_LIB_LOCATION:-/usr/local/lib/onnxruntime-cpu/lib}"
  if ! is_chain_ort_file "$dir/libonnxruntime.so"; then
    printf 'Error: %s/libonnxruntime.so is missing or not the chain-built ONNX Runtime (no %s in it)\n' \
      "$dir" "$ORT_CHAIN_SOURCE_MARKER" >&2
    return 1
  fi
  printf '%s\n' "$dir"
}

# Asks the GStreamer that built the plugin; the plugin's build already requires pkg-config.
gst_pkgconfig_var() {
  pkg-config --variable="$1" gstreamer-1.0 2>/dev/null
}

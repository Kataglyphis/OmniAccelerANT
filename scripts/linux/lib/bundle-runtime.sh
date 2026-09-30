#!/usr/bin/env bash
# Shared by bundle-runtime-closure.sh and check-bundle-closure.sh; sourced, never run.

# What the .deb's declared dependencies provide; extend only with what every GTK desktop has.
SYSTEM_SONAME_ALLOWLIST=(
  'libc.so.6' 'libm.so.6' 'libstdc++.so.6' 'libgcc_s.so.1'
  'libpthread.so.0' 'libdl.so.2' 'librt.so.1'
  'ld-linux*.so*'
  'libglib-2.0.so.0' 'libgobject-2.0.so.0' 'libgio-2.0.so.0'
  'libgmodule-2.0.so.0' 'libgthread-2.0.so.0' 'libz.so.1'
  'libgtk-3.so.0' 'libgdk-3.so.0' 'libatk-1.0.so.0'
  'libcairo.so.2' 'libcairo-gobject.so.2' 'libgdk_pixbuf-2.0.so.0'
  'libpango-1.0.so.0' 'libpangocairo-1.0.so.0' 'libharfbuzz.so.0'
  'libepoxy.so.0' 'libfontconfig.so.1'
)

is_system_soname() {
  local soname="$1" pattern
  for pattern in "${SYSTEM_SONAME_ALLOWLIST[@]}"; do
    # shellcheck disable=SC2254  # the glob is the point: ld-linux*.so*
    case "$soname" in $pattern) return 0 ;; esac
  done
  return 1
}

# Every plugin the Dart/C++ pipelines and the Rust capture use; shared so none silently stops travelling.
# shellcheck disable=SC2034  # read by bundle-runtime-closure.sh and check-bundle-closure.sh
GST_BUNDLED_PLUGIN_NAMES=(
  coreelements app videoconvertscale videotestsrc autodetect jpeg video4linux2
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

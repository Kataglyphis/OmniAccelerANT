#!/usr/bin/env bash
# Shared pieces of the bundle relocatability pair: bundle-runtime-closure.sh
# moves the closure into the bundle, check-bundle-closure.sh grades it. Sourced,
# never invoked — scripts/linux/lib/ holds no entry points.

# The sonames a target provides through the desktop stack the .deb's declared
# dependencies stand for: libc6 and libstdc++6 (the C/C++ runtime) plus the
# glib/GTK family libgtk-3-0 pulls, including its direct NEEDED and the display
# stack beneath it. Everything else a bundled ELF needs must travel in the
# bundle — GStreamer, ONNX Runtime, libjpeg/libunwind and the camera stack do.
# Extend this list only with something every GTK desktop has; the closure gate
# exists so a new dependency cannot slip in unnoticed.
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

# The GStreamer plugin libraries the app's pipelines can ask for. The C++/Dart
# pipelines (v4l2src jpegdec videoconvert appsink autovideosrc videotestsrc) and
# the Rust capture (crates/media) between them use exactly these. Bundler and
# gate share the list so a plugin cannot silently stop travelling.
GST_BUNDLED_PLUGIN_NAMES=(
  coreelements app videoconvertscale videotestsrc autodetect jpeg video4linux2
)

# True when the colon-separated RUNPATH of $1 contains $2 as an exact token -
# `$ORIGIN/lib` does not count as `$ORIGIN` for a same-directory dependency.
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

# One shared soname per line, no brackets or spacing. Empty output is a failure
# only if the caller expects dependencies at all — callers guard.
elf_needed() {
  readelf -d "$1" 2>/dev/null | awk '/\(NEEDED\)/ {gsub(/[][\n]/,""); print $NF}'
}

elf_runpath() {
  readelf -d "$1" 2>/dev/null | awk '/\(RUNPATH\)/ {gsub(/[][\n]/,""); print $NF}'
}

# The GStreamer prefix of whichever tree built the plugin: the image's
# /opt/gstreamer or a host's distro install. pkg-config is already a build
# requirement of the plugin (packages/kataglyphis_native_inference/linux),
# so it is present wherever a bundle can exist.
gst_pkgconfig_var() {
  pkg-config --variable="$1" gstreamer-1.0 2>/dev/null
}

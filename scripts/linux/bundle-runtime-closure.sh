#!/usr/bin/env bash
# Makes the built Flutter bundle relocatable: GStreamer, the runtime-loaded ONNX
# Runtime and the detector model travel inside it, and every bundled ELF gets an
# $ORIGIN rpath. RUNPATH is not transitive, so a dlopen'd plugin cannot reach a
# sibling through the runner's $ORIGIN/lib - each lib needs its own $ORIGIN.
# The closure resolves from DT_NEEDED against pkg-config, never from ldd.
#
# Usage: scripts/linux/bundle-runtime-closure.sh [--arch x64|arm64]
#            [--build-mode MODE] [--bundle-dir DIR] [--no-model]
# Detail: docs/source/camera-streaming.md § Relocatable Linux bundles.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/cli-common.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "$SCRIPT_DIR/lib/bundle-runtime.sh"

MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
BUNDLE_DIR=""
WITH_MODEL=1

# The model is 59 MB in every artifact; `KATAGLYPHIS_BUNDLE_MODEL=0` drops it
# and leaves the UI to demand KATAGLYPHIS_ONNX_MODEL at runtime. --no-model wins.
case "${KATAGLYPHIS_BUNDLE_MODEL:-1}" in
  0|false|no|off) WITH_MODEL=0 ;;
esac

usage() {
  cat <<'EOF'
Usage:
  scripts/linux/bundle-runtime-closure.sh [options]

Options:
  -a, --arch <x64|arm64>      Target architecture (default: auto-detect)
      --build-mode <mode>     debug|profile|release (default: release)
      --bundle-dir <path>     Bundle root (default: build/linux/<arch>/<mode>/bundle)
      --no-model              Do not bundle resources/models/yolov10m.onnx
  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch) MATRIX_ARCH="${2:-}"; shift 2 ;;
    --build-mode) BUILD_MODE="${2:-}"; shift 2 ;;
    --bundle-dir) BUNDLE_DIR="${2:-}"; shift 2 ;;
    --no-model) WITH_MODEL=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ! validate_arch "$MATRIX_ARCH"; then
  exit 2
fi
case "$BUILD_MODE" in
  debug|profile|release) ;;
  *) printf 'Error: --build-mode must be debug, profile or release (got: %s)\n' "${BUILD_MODE:-<empty>}" >&2; exit 2 ;;
esac

if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$REPO_ROOT/build/linux/$MATRIX_ARCH/$BUILD_MODE/bundle"
fi
if [[ ! -d "$BUNDLE_DIR/lib" ]]; then
  printf 'Error: no bundle at %s (run the Flutter build first)\n' "$BUNDLE_DIR" >&2
  exit 1
fi
bundle_lib="$BUNDLE_DIR/lib"

gst_lib_dir="$(gst_pkgconfig_var libdir)"
gst_plugins_dir="$(gst_pkgconfig_var pluginsdir)"
if [[ -z "$gst_lib_dir" || -z "$gst_plugins_dir" || ! -d "$gst_plugins_dir" ]]; then
  printf 'Error: pkg-config cannot locate GStreamer (libdir=%s pluginsdir=%s)\n' \
    "${gst_lib_dir:-<empty>}" "${gst_plugins_dir:-<empty>}" >&2
  printf '       The plugin links GStreamer, so the same prefix must be visible here.\n' >&2
  exit 1
fi

require_cmd readelf
require_cmd patchelf

# Which plugin libraries the app's pipelines can ask for - GST_BUNDLED_PLUGIN_NAMES
# in lib/bundle-runtime.sh, shared with the closure gate.

mkdir -p "$bundle_lib/gstreamer-1.0"

declare -A seen=()
declare -A bundled=()
queue=()
copied_count=0

resolve_soname() {
  local soname="$1" path chain
  # ONNX Runtime comes from the proven chain dir or not at all - never the ld.so cache.
  if [[ "$soname" == libonnxruntime* ]]; then
    chain="$(chain_ort_lib_dir)" || return 1
    if [[ -e "$chain/$soname" ]] && is_chain_ort_file "$chain/$soname"; then
      printf '%s\n' "$chain/$soname"
      return 0
    fi
    return 1
  fi
  if [[ -e "$gst_lib_dir/$soname" ]]; then
    printf '%s\n' "$gst_lib_dir/$soname"
    return 0
  fi
  path="$(ldconfig -p 2>/dev/null | awk -v n="$soname" '$1 == n {print $NF; exit}' || true)"
  if [[ -n "$path" && -e "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  return 1
}

# Walk the DT_NEEDED graph of everything already in the bundle. Non-system
# dependencies are copied in as real files under the name the loader asks for,
# so no soname symlink is ever needed; each copy joins the queue in turn.
walk_queue() {
  local file soname src
  while ((${#queue[@]})); do
    file="${queue[0]}"
    queue=("${queue[@]:1}")
    while IFS= read -r soname; do
      [[ -n "$soname" ]] || continue
      if is_system_soname "$soname" || [[ -n "${seen[$soname]:-}" ]]; then
        continue
      fi
      if ! src="$(resolve_soname "$soname")"; then
        printf 'Error: %s needs %s and it resolves nowhere\n' "$(basename "$file")" "$soname" >&2
        exit 1
      fi
      cp -L "$src" "$bundle_lib/$soname"
      seen[$soname]=1
      bundled[$soname]="$src"
      copied_count=$((copied_count + 1))
      queue+=("$bundle_lib/$soname")
    done < <(elf_needed "$file")
  done
}

for file in "$bundle_lib"/* "$bundle_lib"/gstreamer-1.0/* "$BUNDLE_DIR"/*; do
  [[ -f "$file" ]] || continue
  base="$(basename "$file")"
  [[ "$base" == *.so* || -x "$file" ]] || continue
  if [[ -z "${seen[$base]:-}" ]]; then
    seen[$base]=1
    queue+=("$file")
  fi
done
walk_queue

# Plugin libraries are runtime-loaded, never DT_NEEDED, so the walk above
# cannot reach them; they are copied by the fixed list and their own closure
# is walked immediately after.
for plugin in "${GST_BUNDLED_PLUGIN_NAMES[@]}"; do
  src="$gst_plugins_dir/libgst${plugin}.so"
  dest="$bundle_lib/gstreamer-1.0/libgst${plugin}.so"
  if [[ ! -e "$src" ]]; then
    printf 'Warning: GStreamer plugin libgst%s.so not found in %s\n' "$plugin" "$gst_plugins_dir" >&2
    continue
  fi
  if [[ ! -e "$dest" ]]; then
    cp -L "$src" "$dest"
    copied_count=$((copied_count + 1))
  fi
  seen["libgst${plugin}.so"]=1
  queue+=("$dest")
  walk_queue
done

# Prepend $ORIGIN, keep whatever rpath is there: in the image the old entries
# still resolve (libstdc++ from /opt/gcc), on a target they are dead strings.
patch_origin_rpath() {
  local file="$1" origin="$2" old
  old="$(elf_runpath "$file")"
  case "$old" in
    *'$ORIGIN'*) return 0 ;;
  esac
  if [[ -n "$old" ]]; then
    patchelf --set-rpath "${origin}:${old}" "$file"
  else
    patchelf --set-rpath "$origin" "$file"
  fi
}

# Every bundle lib that needs a sibling gets an $ORIGIN rpath: RUNPATH is not
# transitive, so a lib that is present but unreachable is the exact failure the
# closure gate rejects. This covers the copies above, the app-owned ELFs the
# Flutter build produced (whose RUNPATHs name build-image paths) and Flutter's
# own plugin libs (url_launcher reached libflutter_linux_gtk.so no other way).
needs_sibling_rpath() {
  local file="$1" soname
  while IFS= read -r soname; do
    [[ -n "$soname" ]] || continue
    if [[ -e "$bundle_lib/$soname" ]]; then
      return 0
    fi
  done < <(elf_needed "$file")
  # A dlopen-only ORT user too (liboxidant.so without GStreamer): G6 resolves its ORT via RUNPATH,
  # as a bare dlopen would. Never an ORT copy: G6 proves its bytes, and patchelf would change them.
  case "$(basename "$file")" in libonnxruntime*) return 1 ;; esac
  if [[ -e "$bundle_lib/libonnxruntime.so" ]] && grep -aqF -e OrtGetApiBase -- "$file"; then
    return 0
  fi
  return 1
}

for file in "$bundle_lib"/*.so*; do
  [[ -f "$file" ]] || continue
  if needs_sibling_rpath "$file"; then
    patch_origin_rpath "$file" '$ORIGIN'
  fi
done

# The runner sits at the bundle root for tar/deb/AppImage, but flatpak installs
# the binary into /app/bin with the libs in /app/lib (AGENTS.md § 5, flatpak
# RUNPATH). ".." resolves both layouts; the entry order keeps Flutter's own
# $ORIGIN/lib first everywhere it is correct.
for file in "$BUNDLE_DIR"/*; do
  [[ -f "$file" && -x "$file" ]] || continue
  if readelf -h "$file" >/dev/null 2>&1 && ! runpath_has_token "$file" '$ORIGIN/../lib'; then
    patchelf --set-rpath "\$ORIGIN/lib:\$ORIGIN/../lib:$(elf_runpath "$file")" "$file"
  fi
done

# GStreamer's plugin loader dlopens these from GST_PLUGIN_PATH; their GStreamer
# and system deps sit one directory up.
for file in "$bundle_lib"/gstreamer-1.0/*.so; do
  [[ -f "$file" ]] || continue
  patch_origin_rpath "$file" '$ORIGIN/..'
done

if [[ "$WITH_MODEL" -eq 1 ]]; then
  model_src="$REPO_ROOT/third_party/OxidANT/resources/models/yolov10m.onnx"
  if [[ ! -s "$model_src" ]]; then
    printf 'Error: model not found at %s (use --no-model to build without it)\n' "$model_src" >&2
    exit 1
  fi
  mkdir -p "$BUNDLE_DIR/data/resources/models"
  cp -L "$model_src" "$BUNDLE_DIR/data/resources/models/yolov10m.onnx"
  printf 'Bundled model: data/resources/models/yolov10m.onnx (%s)\n' \
    "$(du -h "$BUNDLE_DIR/data/resources/models/yolov10m.onnx" | cut -f1)"
else
  printf 'Info: model not bundled (--no-model); KATAGLYPHIS_ONNX_MODEL must be set at runtime.\n'
fi

printf 'Runtime closure: %d file(s) copied, bundle now %s\n' \
  "$copied_count" "$(du -sh "$BUNDLE_DIR" | cut -f1)"
if [[ "$copied_count" -gt 0 ]]; then
  printf 'Copied (soname <- source):\n'
  for name in "${!bundled[@]}"; do
    printf '  %s <- %s\n' "$name" "${bundled[$name]}"
  done
fi
# rust_builder's CMake stages ORT when the Rust features ask for it; the walk skips a file already here.
for file in "$bundle_lib"/libonnxruntime*; do
  [[ -f "$file" && -z "${bundled[$(basename "$file")]:-}" ]] || continue
  printf 'Kept (already in bundle/lib, not copied): %s sha256 %s\n' \
    "$(basename "$file")" "$(sha256sum "$file" | cut -d' ' -f1)"
done

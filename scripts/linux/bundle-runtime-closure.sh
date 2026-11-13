#!/usr/bin/env bash
# Makes the Flutter bundle relocatable. See docs/source/camera-streaming.md § Relocatable Linux bundles
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/bundle-script-env.sh
source "$SCRIPT_DIR/lib/bundle-script-env.sh"
REPO_ROOT="$KATAGLYPHIS_REPO_ROOT"

MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
BUNDLE_DIR=""
WITH_MODEL=1

# KATAGLYPHIS_BUNDLE_MODEL=0 drops the 15 MB model (the UI then needs KATAGLYPHIS_ONNX_MODEL); --no-model wins.
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
      --no-model              Do not fetch and bundle OxidANT's models.lock models
  -h, --help                  Show this help
EOF
}

parse_closure_options usage '+--no-model=WITH_MODEL=0' -- "$@"

if ! validate_arch "$MATRIX_ARCH"; then
  exit 2
fi
validate_build_mode "$BUILD_MODE" || exit 2

if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$REPO_ROOT/build/linux/$MATRIX_ARCH/$BUILD_MODE/bundle"
fi
if [[ ! -d "$BUNDLE_DIR/lib" ]]; then
  printf 'Error: no bundle at %s (run the Flutter build first)\n' "$BUNDLE_DIR" >&2
  exit 1
fi
bundle_lib="$BUNDLE_DIR/lib"
require_cmd readelf
prepare_gpu_host_runtime "$BUNDLE_DIR"

gst_lib_dir="$(gst_pkgconfig_var libdir)"
gst_plugins_dir="$(gst_pkgconfig_var pluginsdir)"
if [[ -z "$gst_lib_dir" || -z "$gst_plugins_dir" || ! -d "$gst_plugins_dir" ]]; then
  printf 'Error: pkg-config cannot locate GStreamer (libdir=%s pluginsdir=%s)\n' \
    "${gst_lib_dir:-<empty>}" "${gst_plugins_dir:-<empty>}" >&2
  printf '       The Rust core links GStreamer, so the same prefix must be visible here.\n' >&2
  exit 1
fi

require_cmd patchelf

# Plugins are dlopen'd, never DT_NEEDED: the hub copies the fixed list (GST_BUNDLED_PLUGIN_NAMES), and a missing one fails.
mkdir -p "$bundle_lib/gstreamer-1.0"
gst_copy_bundle_plugins "$bundle_lib/gstreamer-1.0" --plugin-dir "$gst_plugins_dir" -- "${GST_BUNDLED_PLUGIN_NAMES[@]}"

# cxx_lib_dir <soname>: where the compiler's own copy sits; the image's distro libstdc++ is not the one the code links.
cxx_lib_dir() {
  local path
  path="$("${CXX:-clang++}" -print-file-name="$1")"
  [[ "$path" == /* && -e "$path" ]] || return 1
  dirname "$path"
}

declare -A kept=()
for file in "$bundle_lib"/*; do
  if [[ -f "$file" ]]; then kept[$(basename "$file")]=1; fi
done

# ONNX Runtime comes from the proven chain dir or not at all, never the ld.so cache; check-bundle-closure.sh's G6 proves the bytes.
ort_dir="$(chain_ort_lib_dir 2>/dev/null)" || ort_dir=/var/empty
closure_args=(--bundle "$BUNDLE_DIR" --lib-dir "$bundle_lib" --relocatable --no-runpath --no-default-system
  --from "libonnxruntime*=$ort_dir")
if [[ -n "$GPU_RUNTIME_KIND" ]]; then
  closure_args+=(--direct-only "$GPU_RUNTIME_MODULE")
  for sdk_root in /opt/rocm /usr/local/cuda; do
    [[ ! -d "$sdk_root" ]] || closure_args+=(--reject-source-root "$sdk_root")
  done
fi
for soname in "${SYSTEM_SONAME_ALLOWLIST[@]}"; do closure_args+=(--system "$soname"); done
for soname in libstdc++.so.6 libgcc_s.so.1; do
  if dir="$(cxx_lib_dir "$soname")"; then closure_args+=(--from "$soname=$dir"); fi
done
bash "$(antfrastructure_path linux/scripts/06-packaging/elf-closure.sh)" "${closure_args[@]}" --search "$gst_lib_dir" --ldconfig
if [[ -n "$GPU_RUNTIME_KIND" ]]; then
  ort_assert_no_bundled_host_runtime "$BUNDLE_DIR" "$GPU_RUNTIME_KIND"
fi
copied_count=0
for file in "$bundle_lib"/*; do
  if [[ -f "$file" && -z "${kept[$(basename "$file")]:-}" ]]; then copied_count=$((copied_count + 1)); fi
done

# Prepend $ORIGIN, keep the old entries: dead on a target, they still resolve in the image.
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

# RUNPATH is not transitive, so every lib that needs a sibling gets its own $ORIGIN.
needs_sibling_rpath() {
  local file="$1" soname
  if is_gpu_ort_file "$file"; then return 1; fi
  while IFS= read -r soname; do
    [[ -n "$soname" ]] || continue
    if [[ -e "$bundle_lib/$soname" ]]; then
      return 0
    fi
  done < <(elf_needed "$file")
  # dlopen-only ORT users need it too; never an ORT copy, whose bytes G6 proves.
  case "$(basename "$file")" in libonnxruntime*) return 1 ;; esac
  if [[ -e "$bundle_lib/libonnxruntime.so" ]] && grep -aqF -e OrtGetApiBase -- "$file"; then
    return 0
  fi
  return 1
}

mapfile -t lib_files < <(bundle_lib_files "$bundle_lib")
for file in "${lib_files[@]}"; do
  if needs_sibling_rpath "$file"; then
    patch_origin_rpath "$file" '$ORIGIN'
  fi
done

# flatpak puts the runner in /app/bin and the libs in /app/lib, hence $ORIGIN/../lib (AGENTS.md § 5).
mapfile -t root_programs < <(bundle_root_programs "$BUNDLE_DIR")
for file in "${root_programs[@]}"; do
  if readelf -h "$file" >/dev/null 2>&1 && ! runpath_has_token "$file" '$ORIGIN/../lib'; then
    patchelf --set-rpath "\$ORIGIN/lib:\$ORIGIN/../lib:$(elf_runpath "$file")" "$file"
  fi
done

# Loaded from GST_PLUGIN_PATH; their dependencies sit one directory up.
for file in "$bundle_lib"/gstreamer-1.0/*.so; do
  [[ -f "$file" ]] || continue
  patch_origin_rpath "$file" '$ORIGIN/..'
done

# glibc 2.43 is newer than Debian 13's: there the runner starts through the image's loader, kept beside it for data/.
for file in "$BUNDLE_DIR"/*; do
  [[ -f "$file" && -x "$file" && "$file" != *.bin ]] || continue
  is_system_soname "$(basename "$file")" && continue
  loader_args=(--beside)
  if [[ -n "$GPU_RUNTIME_KIND" ]]; then loader_args+=(--external-library-path); fi
  bash "$(antfrastructure_path linux/scripts/06-packaging/bundle-loader.sh)" "${loader_args[@]}" "$BUNDLE_DIR" "$bundle_lib" "$(basename "$file")"
done

if [[ "$WITH_MODEL" -eq 1 ]]; then
  # The model, its license and notice, checked against OxidANT's models.lock.
  bash "$REPO_ROOT/third_party/OxidANT/scripts/linux/fetch-models.sh" --dest "$BUNDLE_DIR/data/resources/models"
  printf 'Bundled models: data/resources/models (%s)\n' "$(du -sh "$BUNDLE_DIR/data/resources/models" | cut -f1)"
else
  printf 'Info: model not bundled (--no-model); KATAGLYPHIS_ONNX_MODEL must be set at runtime.\n'
fi

printf 'Runtime closure: %d file(s) copied, bundle now %s\n' \
  "$copied_count" "$(du -sh "$BUNDLE_DIR" | cut -f1)"
# rust_builder's CMake stages ORT on every build; the walk skips a file already here.
for file in "$bundle_lib"/libonnxruntime*; do
  [[ -f "$file" && -n "${kept[$(basename "$file")]:-}" ]] || continue
  printf 'Kept (already in bundle/lib, not copied): %s sha256 %s\n' \
    "$(basename "$file")" "$(sha256sum "$file" | cut -d' ' -f1)"
done
# Match notices only after all bundle transformations are complete.
antfrastructure_source linux/scripts/06-packaging/ort-wheel-licenses.sh
stage_ort_wheel_licenses "$BUNDLE_DIR"
if [[ "$GPU_RUNTIME_KIND" == migraphx ]]; then
  # No wheel carries the plugin: the image's module, unpatched, and the texts beside it in the image are its proof.
  ort_assert_plugin_module "$BUNDLE_DIR/$GPU_RUNTIME_MODULE"
  # shellcheck source=third_party/OxidANT/scripts/linux/lib/ort-runtime-bundle.sh
  source "$REPO_ROOT/third_party/OxidANT/scripts/linux/lib/ort-runtime-bundle.sh"
  stage_amdgpu_ep_notices "$BUNDLE_DIR"
fi

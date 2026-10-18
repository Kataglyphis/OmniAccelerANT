#!/usr/bin/env bash
# Every pipeline element must load from the bundle's own plugins, as the app loads them. See docs/source/camera-streaming.md § Relocatable Linux bundles
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/cli-common.sh
source "$SCRIPT_DIR/lib/cli-common.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "$SCRIPT_DIR/lib/bundle-runtime.sh"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$SCRIPT_DIR/lib/antfrastructure.sh"

matrix_arch="$(detect_arch)"
build_mode="release"
bundle_dir=""
# The suite swaps in a stub; the lane uses the image's, from the GStreamer build the bundle carries.
gst_inspect="${GST_INSPECT:-gst-inspect-1.0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --arch) matrix_arch="${2:?--arch needs a value}"; shift 2 ;;
    --build-mode) build_mode="${2:?--build-mode needs a value}"; shift 2 ;;
    --bundle-dir) bundle_dir="${2:?--bundle-dir needs a value}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--arch x64|arm64] [--build-mode debug|profile|release] [--bundle-dir DIR]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ! validate_arch "$matrix_arch"; then
  exit 2
fi
case "$build_mode" in
  debug|profile|release) ;;
  *) printf 'Error: --build-mode must be debug, profile or release (got: %s)\n' "${build_mode:-<empty>}" >&2; exit 2 ;;
esac
if [ -z "$bundle_dir" ]; then
  bundle_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)/build/linux/${matrix_arch}/${build_mode}/bundle"
fi
plugin_dir="${bundle_dir}/lib/gstreamer-1.0"
if [ ! -d "$plugin_dir" ]; then
  printf 'Error: no bundled plugins at %s; run bundle-runtime-closure.sh first\n' "$plugin_dir" >&2
  exit 2
fi
require_cmd "$gst_inspect" || exit 2

# The hub's check, under runtime_paths.cc's environment; a missing element's plugin goes into GST_BUNDLED_PLUGIN_NAMES.
GST_INSPECT="$gst_inspect" bash "$(antfrastructure_path linux/scripts/06-packaging/gstreamer-bundle.sh)" check \
  --plugins "$plugin_dir" --lib-dir "${bundle_dir}/lib" "${GST_PIPELINE_ELEMENTS[@]}"

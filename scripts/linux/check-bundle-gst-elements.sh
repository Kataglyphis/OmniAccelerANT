#!/usr/bin/env bash
# Every pipeline element must load from the bundle's own plugins, as the app loads them. See docs/source/camera-streaming.md § Relocatable Linux bundles
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/cli-common.sh
source "$SCRIPT_DIR/lib/cli-common.sh"
# shellcheck source=scripts/linux/lib/bundle-options.sh
source "$SCRIPT_DIR/lib/bundle-options.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "$SCRIPT_DIR/lib/bundle-runtime.sh"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$SCRIPT_DIR/lib/antfrastructure.sh"

matrix_arch="$(detect_arch)"
build_mode="release"
bundle_dir=""
# The suite swaps in a stub; the lane uses the image's, from the GStreamer build the bundle carries.
gst_inspect="${GST_INSPECT:-gst-inspect-1.0}"

parse_bundle_gate_options gst "$@"

if ! validate_arch "$matrix_arch"; then
  exit 2
fi
validate_build_mode "$build_mode" || exit 2
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

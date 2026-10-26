#!/usr/bin/env bash
# check-bundle-gst-elements.sh against a stub gst-inspect: one green, and each way it must go red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
antfrastructure_source linux/scripts/tests/gst-inspect-fixture.sh || exit 1
gate="${SCRIPT_DIR}/../check-bundle-gst-elements.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "${SCRIPT_DIR}/../lib/bundle-runtime.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bundle/lib/gstreamer-1.0" "${work}/no-plugins/lib"

t_write_gst_inspect_stub "${work}/gst-inspect" --with-name

# elements <bundle dir> <VAR=value>...: the gate on that bundle with the stub, its output also kept in ${work}/out.
elements() {
  local bundle="$1"
  shift
  env GST_INSPECT="${work}/gst-inspect" "$@" bash "${gate}" --bundle-dir "${bundle}" 2>&1 | tee "${work}/out"
}

all="${GST_PIPELINE_ELEMENTS[*]}"
t_case "every element from the bundle, whatever the caller's plugin paths"
t_assert_rc 0 elements "${work}/bundle" \
  STUB_ELEMENTS="${all}" GST_PLUGIN_SYSTEM_PATH=/usr/lib/gstreamer-1.0 GST_PLUGIN_PATH_1_0=/usr/lib/gstreamer-1.0
t_case "an element no bundled plugin provides"
t_assert_rc 1 elements "${work}/bundle" STUB_ELEMENTS="${all/v4l2src/}"
t_case "the missing element is named"
t_assert_grep "${work}/out" '^FAIL v4l2src'
t_case "an element loaded from outside the bundle"
t_assert_rc 1 elements "${work}/bundle" STUB_ELEMENTS="${all}" STUB_DIR=/opt/gstreamer/lib/gstreamer-1.0
t_case "a bundle without plugins"
t_assert_rc 2 elements "${work}/no-plugins" STUB_ELEMENTS="${all}"

t_summary

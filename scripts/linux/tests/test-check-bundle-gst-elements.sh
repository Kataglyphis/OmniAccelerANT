#!/usr/bin/env bash
# check-bundle-gst-elements.sh against a stub gst-inspect: one green, and each way it must go red.
set -uo pipefail

# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
antfrastructure_source linux/scripts/tests/gst-inspect-fixture.sh || exit 1
gate="${KATAGLYPHIS_REPO_ROOT}/scripts/linux/check-bundle-gst-elements.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "${KATAGLYPHIS_REPO_ROOT}/scripts/linux/lib/bundle-runtime.sh"
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
t_case "webrtcsink in a bundle that scans in process"
mkdir -p "${work}/webrtc/lib/gstreamer-1.0"
: >"${work}/webrtc/lib/gstreamer-1.0/libgstrswebrtc.so"
t_assert_rc 1 elements "${work}/webrtc" STUB_ELEMENTS="${all}"
t_case "the refused plugin is named"
t_assert_grep "${work}/out" 'FAIL libgstrswebrtc.so'
t_case "the Windows plugin list carries no webrtcsink either: that bundle has no scanner"
t_assert_rc 0 grep -q 'gstvideotestsrc.dll' "${KATAGLYPHIS_REPO_ROOT}/scripts/windows/Build-Windows.ps1"
t_assert_rc 1 grep -q 'gstrswebrtc' "${KATAGLYPHIS_REPO_ROOT}/scripts/windows/Build-Windows.ps1"
t_case "the producer bundle refuses to ship without its scanner"
t_assert_rc 0 grep -q "gst-plugin-scanner not found in the image.*exit 1" \
  "${KATAGLYPHIS_REPO_ROOT}/scripts/linux/observant/package-producer-bundle.sh"

t_summary

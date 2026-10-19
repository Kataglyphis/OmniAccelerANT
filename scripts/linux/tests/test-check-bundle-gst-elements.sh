#!/usr/bin/env bash
# check-bundle-gst-elements.sh against a stub gst-inspect: one green, and each way it must go red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
gate="${SCRIPT_DIR}/../check-bundle-gst-elements.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "${SCRIPT_DIR}/../lib/bundle-runtime.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bundle/lib/gstreamer-1.0" "${work}/no-plugins/lib"

# Answers like gst-inspect-1.0 for STUB_ELEMENTS from STUB_DIR, and only under the app's plugin environment.
cat > "${work}/gst-inspect" <<'STUB'
#!/usr/bin/env bash
[ "${GST_PLUGIN_SYSTEM_PATH-unset}" = "" ] && [ "${GST_PLUGIN_SYSTEM_PATH_1_0-unset}" = "" ] || exit 3
[ -z "${GST_PLUGIN_PATH_1_0+x}" ] || exit 3
case " ${STUB_ELEMENTS} " in *" $1 "*) ;; *) exit 255 ;; esac
printf 'Plugin Details:\n  Name                     stub\n  Filename                 %s/libgststub.so\n' "${STUB_DIR:-${GST_PLUGIN_PATH}}"
STUB
chmod +x "${work}/gst-inspect"

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
t_assert_rc 1 elements "${work}/bundle" STUB_ELEMENTS="${all/jpegdec/}"
t_case "the missing element is named"
t_assert_grep "${work}/out" '^FAIL jpegdec'
t_case "an element loaded from outside the bundle"
t_assert_rc 1 elements "${work}/bundle" STUB_ELEMENTS="${all}" STUB_DIR=/opt/gstreamer/lib/gstreamer-1.0
t_case "a bundle without plugins"
t_assert_rc 2 elements "${work}/no-plugins" STUB_ELEMENTS="${all}"

t_summary

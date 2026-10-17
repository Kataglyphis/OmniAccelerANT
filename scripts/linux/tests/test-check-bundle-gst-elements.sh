#!/usr/bin/env bash
# check-bundle-gst-elements.sh against a stub gst-inspect: one green, and each way it must go red.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

passed=0
out=""
# expect <rc> <name> <bundle dir> <VAR=value>...: the gate on that bundle, with the stub and this environment.
expect() {
  local want="$1" name="$2" bundle="$3" got=0
  shift 3
  out="$(env GST_INSPECT="${work}/gst-inspect" "$@" bash "${gate}" --bundle-dir "${bundle}" 2>&1)" || got=$?
  if [ "${got}" -ne "${want}" ]; then
    printf 'FAIL %s: expected rc %s, got %s\n%s\n' "${name}" "${want}" "${got}" "${out}" >&2
    exit 1
  fi
  passed=$((passed + 1))
  printf 'ok   %s\n' "${name}"
}

all="${GST_PIPELINE_ELEMENTS[*]}"
expect 0 "every element from the bundle, whatever the caller's plugin paths" "${work}/bundle" \
  STUB_ELEMENTS="${all}" GST_PLUGIN_SYSTEM_PATH=/usr/lib/gstreamer-1.0 GST_PLUGIN_PATH_1_0=/usr/lib/gstreamer-1.0
expect 1 "an element no bundled plugin provides" "${work}/bundle" STUB_ELEMENTS="${all/jpegdec/}"
grep -q '^FAIL jpegdec' <<<"${out}" || { printf 'FAIL the missing element is not named:\n%s\n' "${out}" >&2; exit 1; }
expect 1 "an element loaded from outside the bundle" "${work}/bundle" \
  STUB_ELEMENTS="${all}" STUB_DIR=/opt/gstreamer/lib/gstreamer-1.0
expect 2 "a bundle without plugins" "${work}/no-plugins" STUB_ELEMENTS="${all}"
printf '%s case(s) passed\n' "${passed}"

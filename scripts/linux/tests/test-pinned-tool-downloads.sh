#!/usr/bin/env bash
# A fake curl and container engine serve fixtures; it does not cover the real release bytes, the asset mirror or a firmware build.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${repo}/scripts/linux/lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
pins="${repo}/scripts/linux/tool-pins.env"
codeql_lib="${PINNED_TOOLS_CODEQL:-${repo}/scripts/linux/codeql/codeql-common.sh}"
firmware="${PINNED_TOOLS_FIRMWARE:-${repo}/scripts/linux/esp32/build-firmware.sh}"
work="$(mktemp -d "${TMPDIR:-/tmp}/pinned-tool-downloads.XXXXXX")" || exit 1
trap 'rm -rf -- "${work}"' EXIT

pin() { sed -n "s/^$1=//p" "${pins}"; }
is_sha256() {
  if [[ "$1" =~ ^[0-9a-f]{64}$ ]]; then return 0; fi
  return 1
}
sha_of() { sha256sum "$1" | cut -d' ' -f1; }
# zip_tree <archive> <dir> <top>: zipfile keeps each member's mode, so a tool stays executable.
zip_tree() {
  mkdir -p "$(dirname "$1")"
  (cd "$2" && python3 -m zipfile -c "$1" "$3")
}

case "$(uname -m)" in
  x86_64) codeql_asset=codeql-linux64.zip; codeql_var=CODEQL_CLI_LINUX64_SHA256; host=x86_64; esp_var=X86_64 ;;
  aarch64) codeql_asset=codeql-linux-arm64.zip; codeql_var=CODEQL_CLI_LINUX_ARM64_SHA256; host=aarch64; esp_var=AARCH64 ;;
  *) echo "no pinned tool assets for $(uname -m)" >&2; exit 1 ;;
esac
fake="${work}/bin"
t_fake_curl "${fake}"
export FAKE_CURL_ROOT="${work}/served" KATAGLYPHIS_ASSET_MIRROR=off
served="${FAKE_CURL_ROOT}/github.com"

t_case 'no script or firmware file fetches a moving latest release'
t_assert_rc 1 grep -rnE -e '(curl|wget)[^|]*releases/latest' -- "${repo}/scripts" "${repo}/firmware"

t_case 'every tool has a version and a sha256 per host'
for tool in CODEQL_CLI ESPUP ESPFLASH; do
  t_assert_contains "$(pin "${tool}_VERSION")" v
done
for key in CODEQL_CLI_LINUX64 CODEQL_CLI_LINUX_ARM64 ESPUP_X86_64 ESPUP_AARCH64 ESPFLASH_X86_64 ESPFLASH_AARCH64; do
  t_assert_ok is_sha256 "$(pin "${key}_SHA256")"
done

codeql_url="github/codeql-cli-binaries/releases/download/$(pin CODEQL_CLI_VERSION)/${codeql_asset}"
mkdir -p "${work}/tree/codeql/codeql"
printf '#!/bin/sh\necho "codeql $*"\n' > "${work}/tree/codeql/codeql/codeql"
chmod +x "${work}/tree/codeql/codeql/codeql"
zip_tree "${served}/${codeql_url}" "${work}/tree/codeql" codeql
install_codeql() {
  local label="$1"
  shift
  env PATH="${fake}:${PATH}" CODEQL_INSTALL_DIR="${work}/cli-${label}" "$@" bash -c '
    set -euo pipefail
    source "$1"
    source "$2"
    codeql_install_cli "$3"
  ' _ "${repo}/scripts/linux/lib/antfrastructure.sh" "${codeql_lib}" "${work}/dl-${label}"
}

t_case 'the CodeQL CLI is refused when its bytes miss the pinned sha256'
refused="$(install_codeql refused 2>&1)" && refused_rc=0 || refused_rc=$?
t_assert_eq 1 "${refused_rc}"
t_assert_contains "${refused}" 'Checksum verification FAILED'
t_assert_fails test -e "${work}/cli-refused"

t_case 'the CodeQL CLI installs from the pinned release URL when its sha256 matches'
: > "${FAKE_CURL_ROOT}/requested"
t_assert_contains "$(install_codeql accepted "${codeql_var}=$(sha_of "${served}/${codeql_url}")" 2>&1)" 'codeql resolve languages'
t_assert_eq "https://github.com/${codeql_url}" "$(cat "${FAKE_CURL_ROOT}/requested")"

espup_url="esp-rs/espup/releases/download/$(pin ESPUP_VERSION)/espup-${host}-unknown-linux-gnu"
espflash_url="esp-rs/espflash/releases/download/$(pin ESPFLASH_VERSION)/espflash-${host}-unknown-linux-gnu.zip"
mkdir -p "$(dirname "${served}/${espup_url}")"
cat > "${served}/${espup_url}" <<EOF
#!/bin/sh
if [ "\$1" = --version ]; then echo "espup $(pin ESPUP_VERSION | sed 's/^v//')"; exit 0; fi
while [ "\$1" != --export-file ]; do shift; done
echo 'cargo() { echo cargo-ran "\$@"; }' > "\$2"
EOF
mkdir -p "${work}/tree/espflash"
printf '#!/bin/sh\necho "espflash %s"\n' "$(pin ESPFLASH_VERSION | sed 's/^v//')" > "${work}/tree/espflash/espflash"
chmod +x "${work}/tree/espflash/espflash"
zip_tree "${served}/${espflash_url}" "${work}/tree/espflash" espflash
cat > "${fake}/engine" <<'STUB'
#!/usr/bin/env bash
case " $* " in *" -lc "*) ;; *) exit 0 ;; esac
script="${*: -1}"
script="${script//\/opt\/esp32/${FAKE_ESP}}"
script="${script//\/opt\/antfrastructure/${ANTFRASTRUCTURE_DIR}}"
exec bash -c "${script//\/workspace/${FAKE_WORKSPACE}}"
STUB
chmod +x "${fake}/engine"
build_firmware() {
  env PATH="${fake}:${PATH}" FAKE_ESP="${work}/esp-$1" FAKE_WORKSPACE="${repo}" KATAGLYPHIS_IMAGE=fixture "${@:2}" \
    bash "${firmware}" --engine engine
}

t_case 'the firmware tools are refused when their bytes miss the pinned sha256'
refused="$(build_firmware refused 2>&1)" && refused_rc=0 || refused_rc=$?
t_assert_eq 1 "${refused_rc}"
t_assert_contains "${refused}" 'Checksum verification FAILED'
t_assert_fails test -e "${work}/esp-refused/bin/espup"
t_assert_fails test -e "${work}/esp-refused/bin/espflash"

espup_sha="ESPUP_${esp_var}_SHA256=$(sha_of "${served}/${espup_url}")"
espflash_sha="ESPFLASH_${esp_var}_SHA256=$(sha_of "${served}/${espflash_url}")"
t_case 'espflash is refused on its own when only its bytes miss the pinned sha256'
refused="$(build_firmware espflash-refused "${espup_sha}" 2>&1)" && refused_rc=0 || refused_rc=$?
t_assert_eq 1 "${refused_rc}"
t_assert_contains "${refused}" 'Checksum verification FAILED'
t_assert_ok test -x "${work}/esp-espflash-refused/bin/espup"
t_assert_fails test -e "${work}/esp-espflash-refused/bin/espflash"

t_case 'the firmware tools install from their pinned release URLs and the build runs'
: > "${FAKE_CURL_ROOT}/requested"
t_assert_contains "$(build_firmware accepted "${espup_sha}" "${espflash_sha}" 2>&1)" 'cargo-ran +esp build --release --locked'
t_assert_eq "https://github.com/${espup_url} https://github.com/${espflash_url}" "$(xargs < "${FAKE_CURL_ROOT}/requested")"

t_case 'a firmware tool from another pin on the volume is replaced'
printf '#!/bin/sh\necho "espup 0.0.1"\n' > "${work}/esp-accepted/bin/espup"
: > "${FAKE_CURL_ROOT}/requested"
t_assert_contains "$(build_firmware accepted "${espup_sha}" "${espflash_sha}" 2>&1)" 'cargo-ran'
t_assert_eq "https://github.com/${espup_url}" "$(xargs < "${FAKE_CURL_ROOT}/requested")"

t_summary

#!/usr/bin/env bash
# build-docs-site.sh: the hosted app's settings carry no STUN server, the app lands at /app/, and docs.yml isolates it.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
script="${BUILD_DOCS_SITE_SCRIPT:-${repo}/scripts/linux/build-docs-site.sh}"
t_workdir

eval "$(t_fn_src "${script}" hosted_webrtc_settings)"
# _field <file> <python expression over s>: one value of the JSON file, printed by Python.
_field() { python3 -I -c "import json, sys; s = json.load(open(sys.argv[1])); print($2)" "$1"; }

t_case "the hosted settings drop every STUN server and keep everything else"
cp "${repo}/assets/settings/webrtc_settings.json" "${work}/settings.json"
t_assert_ok hosted_webrtc_settings "${work}/settings.json"
t_assert_eq "[]" "$(_field "${work}/settings.json" 's["stunServers"]')"
t_assert_eq "$(_field "${repo}/assets/settings/webrtc_settings.json" '{k: v for k, v in s.items() if k != "stunServers"}')" \
  "$(_field "${work}/settings.json" '{k: v for k, v in s.items() if k != "stunServers"}')"

t_case "the app is built for /app/ and copied into the site's app/, the checkout's settings restored on exit"
t_assert_ok grep -qx 'omni_web_app_build --base-href /app/' "${script}"
t_assert_ok grep -qx 'APP_DIR="${SITE_DIR}/app"' "${script}"
t_assert_ok grep -q '^trap .*cp "${settings_backup}" "${WEBRTC_SETTINGS}"' "${script}"
t_assert_ok grep -q 'names ${built_stun} STUN server(s)' "${script}"

t_case "docs.yml builds through it and has the hub isolate app/"
t_assert_ok grep -qx '      command: bash scripts/linux/build-docs-site.sh' "${repo}/.github/workflows/docs.yml"
t_assert_ok grep -qx '      isolated-apps: app' "${repo}/.github/workflows/docs.yml"

t_summary

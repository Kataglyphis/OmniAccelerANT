#!/usr/bin/env bash
# The docs site with the browser app: dart doc into doc/api, then the web app into doc/api/app. See docs/source/browser-port.md#hosting
set -euo pipefail

_docs_site_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/ci-lane-libs.sh
source "${_docs_site_dir}/lib/ci-lane-libs.sh"
# shellcheck source=scripts/linux/lib/web-app-build.sh
source "${_docs_site_dir}/lib/web-app-build.sh"

SITE_DIR="doc/api"
APP_DIR="${SITE_DIR}/app"
WEBRTC_SETTINGS="assets/settings/webrtc_settings.json"

# hosted_webrtc_settings <file>: the settings without STUN servers; the public app asks no third party for a visitor's address.
hosted_webrtc_settings() {
	python3 -I - "$1" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    settings = json.load(f)
settings["stunServers"] = []
with open(path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent="\t")
    f.write("\n")
PY
}

bash "${_docs_site_dir}/generate-docs.sh"

omni_ci_enter_workspace
flutter_lane_prepare_env "${FLUTTER_DIR:-/opt/flutter}"
export_toolchain_env
bash "$(antfrastructure_path linux/scripts/05-frameworks/flutter/setup-sqlite3-wasm.sh)" "$PWD"

# Before the build, so the service worker's hash list names the bytes the site serves; the checkout's file comes back after.
settings_backup="$(mktemp)"
cp "${WEBRTC_SETTINGS}" "${settings_backup}"
trap 'cp "${settings_backup}" "${WEBRTC_SETTINGS}"; rm -f "${settings_backup}"' EXIT
hosted_webrtc_settings "${WEBRTC_SETTINGS}"

# The static host has no ObservANT, so the showcase opens on the local-AI page instead of the camera.
omni_web_app_build --base-href /app/ --dart-define=OMNI_START_ROUTE=/aiPlayground

built_stun="$(python3 -I -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["stunServers"]))' \
	"build/web/assets/${WEBRTC_SETTINGS}")"
if [[ "${built_stun}" != 0 ]]; then
	echo "Error: build/web/assets/${WEBRTC_SETTINGS} names ${built_stun} STUN server(s); the hosted app sets none." >&2
	exit 1
fi

rm -rf "${APP_DIR}"
cp -R build/web "${APP_DIR}"
echo "[Info] The web app is in ${APP_DIR}, served at /app/"

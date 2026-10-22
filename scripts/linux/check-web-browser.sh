#!/usr/bin/env bash
# The built web app in the hub's real Chrome check, with an idle ObservANT fixture instead of a physical camera.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$SCRIPT_DIR/lib/antfrastructure.sh"
antfrastructure_source linux/scripts/01-core/http-readiness.sh
cd "$SCRIPT_DIR/../.."

build_dir="${1:-build/web}"
port="${OMNI_WEB_SMOKE_PORT:-8081}"
base="http://127.0.0.1:${port}"
log="$(mktemp)"
node "$SCRIPT_DIR/tests/web-smoke-server.js" "$build_dir" "$port" >"$log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; cat "$log"; rm -f "$log"' EXIT
wait_for_http "$base/" "web smoke fixture (pid $server)"

# Hash paths are the app's GoRouter URL strategy; all branches, including every configured blog post.
routes=(/ /#/stream /#/cameraSettings /#/device /#/landingPage /#/aboutMe
  /#/imprint /#/contact /#/privacyPolicy /#/cookieDeclaration /#/declarationOnAccessibility
  /#/copyright /#/openSourceLicenses /#/errorPage /#/blockEntries)
while IFS= read -r route; do routes+=("/#${route}"); done < <(
  python3 -c 'import json; print("\n".join(item["routingName"] for item in json.load(open("assets/settings/blog_settings.json"))))'
)
# The hub rejects every external host, so gstatic.com, googleapis.com and google.com also fail.
node "$(antfrastructure_path linux/scripts/check-live-site.js)" "$base/" "${routes[@]}" \
  --files "$build_dir" --scrolls 10 --settle-ms 2000

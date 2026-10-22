#!/usr/bin/env bash
# The compiled-app browser gate must reject console errors, Google requests and missing assets.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$SCRIPT_DIR/../lib/antfrastructure.sh"
antfrastructure_source linux/scripts/01-core/http-readiness.sh
cd "$SCRIPT_DIR/../../.."
work="$(mktemp -d)"
server=""
trap '[ -z "$server" ] || { kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; }; rm -rf "$work"' EXIT
cp -R "${1:-build/web}" "$work/web"
cp "$work/web/index.html" "$work/original.html"
port="${OMNI_WEB_MUTATION_PORT:-8082}"
node "$SCRIPT_DIR/web-smoke-server.js" "$work/web" "$port" >"$work/server.log" 2>&1 &
server=$!
wait_for_http "http://127.0.0.1:${port}/" "browser gate mutation fixture (pid $server)"
check="$(antfrastructure_path linux/scripts/check-live-site.js)"
export CHECK_LIVE_SITE_VIEWPORTS=1280x800
for mutation in console google asset; do
  python3 - "$work/original.html" "$work/web/index.html" "$mutation" <<'PY'
import pathlib
import sys
source, target, mutation = sys.argv[1:]
scripts = {
    'console': "console.error('omni-browser-smoke-mutation');",
    'google': "fetch('https://www.google.com/omni-browser-smoke-mutation', {mode:'no-cors'}).catch(() => {});",
    'asset': "document.body.appendChild(Object.assign(document.createElement('img'), {src:'missing-smoke-fixture.png'}));",
}
pathlib.Path(target).write_text(pathlib.Path(source).read_text().replace('</body>', f'<script>{scripts[mutation]}</script></body>'))
PY
  if node "$check" "http://127.0.0.1:${port}/" /#/stream --scrolls 0 --settle-ms 300 >"$work/result" 2>&1; then
    cat "$work/result"
    echo "FAIL: the browser gate accepted the $mutation mutation" >&2
    exit 1
  fi
  case "$mutation" in
    console) expected='console.error: omni-browser-smoke-mutation' ;;
    google) expected='third-party host: www.google.com' ;;
    asset) expected="HTTP 404: http://127.0.0.1:${port}/missing-smoke-fixture.png" ;;
  esac
  if ! grep -qF "$expected" "$work/result"; then
    cat "$work/result"
    echo "FAIL: the $mutation mutation failed without its expected diagnosis" >&2
    exit 1
  fi
  echo "PASS: browser gate rejects $mutation ($expected)"
done

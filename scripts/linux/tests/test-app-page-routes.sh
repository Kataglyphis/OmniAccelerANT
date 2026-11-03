#!/usr/bin/env bash
# The page-table route reader and its web-check caller; not covered: whether the built site serves each route, which check-web-browser.sh proves.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
reader="$root/scripts/linux/app-page-routes.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

routes="$(bash "$reader")"
for route in /stream /cameraSettings /device /aiPlayground /landingPage /aboutMe; do
  grep -qxF -e "$route" <<<"$routes" || { echo "FAIL: $route is not read from the table" >&2; exit 1; }
done

printf "    route: '/onlyThis',\n" > "$work/table.dart"
[ "$(bash "$reader" "$work/table.dart")" = /onlyThis ] || { echo 'FAIL: the reader ignores its table' >&2; exit 1; }

: > "$work/empty.dart"
if bash "$reader" "$work/empty.dart" 2>/dev/null; then
  echo 'FAIL: a table with no routes must fail' >&2
  exit 1
fi

caller="$root/scripts/linux/check-web-browser.sh"
grep -qF -e 'app-page-routes.sh' "$caller" || { echo 'FAIL: the web check does not read the table' >&2; exit 1; }
if grep -qF -e '/#/cameraSettings' "$caller"; then
  echo 'FAIL: the web check keeps its own copy of a table route' >&2
  exit 1
fi
echo 'Page-table routes passed'

#!/usr/bin/env bash
# Prints each navigation route of lib/app_pages.dart, one per line; a table it cannot read fails, so a check never covers nothing.
set -euo pipefail
table="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/app_pages.dart}"
routes="$(sed -n "s|^    route: '\(/[A-Za-z]*\)',\$|\1|p" "$table")"
if [ -z "$routes" ]; then
  echo "app-page-routes: no routes in $table" >&2
  exit 1
fi
printf '%s\n' "$routes"

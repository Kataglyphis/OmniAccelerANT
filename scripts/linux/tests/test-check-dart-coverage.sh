#!/usr/bin/env bash
# Feeds the coverage gate synthetic lcov reports: it must pass at the floor, fail below it, and ignore generated code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="${SCRIPT_DIR}/../check-dart-coverage.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failures=0

# One record per file: $1 path, $2 lines hit, $3 lines missed.
record() {
  printf 'SF:%s\n' "$1"
  for ((i = 1; i <= $2; i++)); do printf 'DA:%d,3\n' "$i"; done
  for ((i = 1; i <= $3; i++)); do printf 'DA:%d,0\n' "$(($2 + i))"; done
  printf 'end_of_record\n'
}

expect() {
  local want="$1" name="$2"; shift 2
  "$gate" "$@" >"${work}/out" 2>&1
  local got=$?
  if { [ "$want" = pass ] && [ "$got" -eq 0 ]; } || { [ "$want" = fail ] && [ "$got" -ne 0 ]; }; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s (exit %d)\n' "$name" "$got"; sed 's/^/      /' "${work}/out"
    failures=$((failures + 1))
  fi
}

{ record /ws/lib/a.dart 7 3; record /ws/lib/b.dart 0 0; } >"${work}/seventy.info"
expect pass "70 % passes a 70 % floor" --lcov "${work}/seventy.info" --min 70 --repo-root /ws
expect fail "70 % fails a 71 % floor" --lcov "${work}/seventy.info" --min 71 --repo-root /ws

{ record /ws/lib/a.dart 7 3; record /ws/lib/src/rust/frb_generated.dart 0 500; record /ws/lib/l10n/app_localizations.dart 0 200; } >"${work}/generated.info"
expect pass "generated bridge and l10n lines do not count" --lcov "${work}/generated.info" --min 70 --repo-root /ws

{ record /ws/lib/a.dart 7 3; record /ws/test/helper.dart 0 50; record /pub-cache/flutter/lib/src/x.dart 0 50; } >"${work}/foreign.info"
expect pass "test/ and another package's lib/ do not count" --lcov "${work}/foreign.info" --min 70 --repo-root /ws

{ record lib/a.dart 7 3; } >"${work}/relative.info"
expect pass "a path relative to the repo counts" --lcov "${work}/relative.info" --min 70 --repo-root /ws
expect fail "a missing --min is refused" --lcov "${work}/seventy.info"
expect fail "a fractional --min is refused" --lcov "${work}/seventy.info" --min 70.5
: >"${work}/empty.info"
expect fail "an empty report fails" --lcov "${work}/empty.info" --min 0

printf '%d failure(s)\n' "$failures"
exit "$failures"

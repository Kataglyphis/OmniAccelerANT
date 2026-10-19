#!/usr/bin/env bash
# Feeds the coverage gate synthetic lcov reports: it must pass at the floor, fail below it, and ignore generated code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
gate="${SCRIPT_DIR}/../check-dart-coverage.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# One record per file: $1 path, $2 lines hit, $3 lines missed.
record() {
  printf 'SF:%s\n' "$1"
  for ((i = 1; i <= $2; i++)); do printf 'DA:%d,3\n' "$i"; done
  for ((i = 1; i <= $3; i++)); do printf 'DA:%d,0\n' "$(($2 + i))"; done
  printf 'end_of_record\n'
}

{ record /ws/lib/a.dart 7 3; record /ws/lib/b.dart 0 0; } >"${work}/seventy.info"
t_case "70 % passes a 70 % floor"
t_assert_ok "$gate" --lcov "${work}/seventy.info" --min 70 --repo-root /ws
t_case "70 % fails a 71 % floor"
t_assert_fails "$gate" --lcov "${work}/seventy.info" --min 71 --repo-root /ws

{ record /ws/lib/a.dart 7 3; record /ws/lib/src/rust/frb_generated.dart 0 500; record /ws/lib/l10n/app_localizations.dart 0 200; } >"${work}/generated.info"
t_case "generated bridge and l10n lines do not count"
t_assert_ok "$gate" --lcov "${work}/generated.info" --min 70 --repo-root /ws

{ record /ws/lib/a.dart 7 3; record /ws/test/helper.dart 0 50; record /pub-cache/flutter/lib/src/x.dart 0 50; } >"${work}/foreign.info"
t_case "test/ and another package's lib/ do not count"
t_assert_ok "$gate" --lcov "${work}/foreign.info" --min 70 --repo-root /ws

{ record lib/a.dart 7 3; } >"${work}/relative.info"
t_case "a path relative to the repo counts"
t_assert_ok "$gate" --lcov "${work}/relative.info" --min 70 --repo-root /ws
t_case "a missing --min is refused"
t_assert_fails "$gate" --lcov "${work}/seventy.info"
t_case "a fractional --min is refused"
t_assert_fails "$gate" --lcov "${work}/seventy.info" --min 70.5
: >"${work}/empty.info"
t_case "an empty report fails"
t_assert_fails "$gate" --lcov "${work}/empty.info" --min 0

t_summary

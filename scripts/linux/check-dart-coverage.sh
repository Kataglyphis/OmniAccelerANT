#!/usr/bin/env bash
# The app's own Dart (lib/, generated code aside) must stay covered by test/ at --min percent or more.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${SCRIPT_DIR}/../.." && pwd)"
lcov=""
min=""

while [ $# -gt 0 ]; do
  case "$1" in
    --lcov) lcov="${2:?--lcov needs a file}"; shift 2 ;;
    --min) min="${2:?--min needs a percentage}"; shift 2 ;;
    --repo-root) repo_root="${2:?--repo-root needs a path}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s --min PERCENT [--lcov FILE] [--repo-root DIR]\n' "$0"
      printf 'Without --lcov it runs flutter test --coverage in the repo root first.\n'
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$min" in
  '' ) printf 'check-dart-coverage: --min is required\n' >&2; exit 2 ;;
  *[!0-9]* ) printf 'check-dart-coverage: --min takes a whole percentage, not %s\n' "$min" >&2; exit 2 ;;
esac

if [ -z "$lcov" ]; then
  lcov="${repo_root}/build/coverage/lcov.info"
  rm -f "$lcov"
  (cd "$repo_root" && flutter test --coverage --coverage-path "$lcov")
fi
[ -s "$lcov" ] || { printf 'check-dart-coverage: no coverage data in %s\n' "$lcov" >&2; exit 1; }

# Generated code (the bridge, the localizations) is not this repo's to test.
awk -v min="$min" -v root="$repo_root" '
  /^SF:/ {
    file = substr($0, 4)
    if (index(file, root "/") == 1) file = substr(file, length(root) + 2)
    own = (file ~ /^lib\//) && (file !~ /^lib\/src\/rust\//) && (file !~ /^lib\/l10n\//)
    next
  }
  /^DA:/ && own {
    split(substr($0, 4), da, ",")
    total[file]++
    if (da[2] > 0) hit[file]++
    next
  }
  END {
    for (f in total) { all += total[f]; covered += hit[f] }
    if (all == 0) { print "check-dart-coverage: no lib/ lines in the report" > "/dev/stderr"; exit 1 }
    pct = 100 * covered / all
    printf "Dart coverage of lib/ (generated code aside): %d of %d lines, %.1f %% (floor %d %%)\n", covered, all, pct, min
    for (f in total) printf "  %5.1f %%  %4d/%-4d %s\n", 100 * hit[f] / total[f], hit[f], total[f], f | "sort -n | head -5"
    close("sort -n | head -5")
    if (pct < min) { printf "FAIL: below the floor; test what the lowest files above leave out, or justify a lower --min\n"; exit 1 }
  }
' "$lcov"

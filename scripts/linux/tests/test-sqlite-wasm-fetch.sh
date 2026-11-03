#!/usr/bin/env bash
# The wasm stays out of git and both lanes fetch it before grading it; the web lane's run proves the fetch itself.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
native="${SQLITE_WASM_NATIVE_LANE:-${repo}/scripts/linux/ci/lane-native-linux.sh}"
web="${SQLITE_WASM_WEB_LANE:-${repo}/scripts/linux/ci/ci-container-run-web-linux.sh}"

# first_line <file> <fixed-text>: the first line holding the text, or nothing.
first_line() { grep -nF -e "$2" "$1" | head -1 | cut -d: -f1; }

t_case "the wasm is ignored and untracked"
t_assert_ok git -C "${repo}" check-ignore -q web/sqlite3.wasm
t_assert_eq "" "$(git -C "${repo}" ls-files web/sqlite3.wasm)"

for lane in "${native}" "${web}"; do
  t_case "${lane##*/} fetches before it grades"
  fetch="$(first_line "${lane}" 'setup-sqlite3-wasm.sh')"
  grade="$(first_line "${lane}" 'check_flutter_launcher_artifacts')"
  t_assert_ok test -n "${fetch}"
  t_assert_ok test -n "${grade}"
  t_assert_ok test "${fetch:-0}" -lt "${grade:-0}"
done

t_case "the web lane fails a build that lost the wasm"
t_assert_ok grep -qE '^for artefact in .* sqlite3\.wasm' "${web}"

t_summary

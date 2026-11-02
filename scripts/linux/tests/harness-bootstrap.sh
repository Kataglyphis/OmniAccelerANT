#!/usr/bin/env bash
# Sourced at a suite's top level, so the hub harness's functions and counters land in the suite's own shell.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"

# t_mutant_breaks_suite <case> <lib-variable> <mutant-lib> <suite-flag>: reruns this suite on the mutant; the rerun must fail.
t_mutant_breaks_suite() {
  local output rc
  t_case "$1"
  output="$(env "$2=$3" bash "$0" "$4" 2>&1)" && rc=0 || rc=$?
  t_assert_eq 1 "$rc"
  t_assert_contains "$output" 'FAIL'
}

# t_mutant_dir <suite-name>: a directory under the repo's logs, so a mutant still resolves the checkout's relative paths.
t_mutant_dir() {
  mkdir -p "${KATAGLYPHIS_REPO_ROOT}/logs/test-results" &&
    mktemp -d "${KATAGLYPHIS_REPO_ROOT}/logs/test-results/$1-mutant.XXXXXX"
}

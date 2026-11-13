#!/usr/bin/env bash
# The script suites, as the native lane runs them before its build (--lane) and the hub's push hook runs them before a push.
set -euo pipefail

_pre_push_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${_pre_push_dir}/lib/antfrastructure.sh"
# shellcheck source=scripts/linux/lib/suite-inventory.sh
source "${_pre_push_dir}/lib/suite-inventory.sh"
antfrastructure_source linux/scripts/01-core/gates.sh
# From this file's place, never the inherited KATAGLYPHIS_REPO_ROOT: a suite's fixture copy must grade its own tree.
root="$(cd "${_pre_push_dir}/../.." && pwd)"

lane=0
case "${1:-}" in
  '') ;;
  --lane) lane=1 ;;
  *)
    echo "usage: pre-push-checks.sh [--lane]" >&2
    exit 2
    ;;
esac

# The fixtures build ELF files and Debian packages; on another system the lane is their first run.
if [[ "$(uname -s)" != Linux ]]; then
  echo "pre-push-checks: skipped on $(uname -s); the native Linux lane runs the script suites"
  exit 0
fi

gate_reset "script suites"
# Discovered, not listed: a new suite runs here unless it names another runner that names it back.
run_gate "suite inventory" suite_inventory_report "${root}"
while IFS= read -r suite; do
  lane_only="$(suite_inventory_lane_only "${root}/${suite}")"
  # A host outside the image lacks what such a suite names; the lane runs every one.
  if [[ "${lane}" -eq 0 && -n "${lane_only}" ]]; then
    gate_skip "suite ${suite##*/}" "the lane runs it: it needs ${lane_only}"
    continue
  fi
  run_gate "suite ${suite##*/}" suite_inventory_run "${root}" "${suite}"
done < <(suite_inventory_native "${root}")
if [[ "${lane}" -eq 1 ]]; then
  assert_gates
else
  assert_gates --tolerate-skips
fi

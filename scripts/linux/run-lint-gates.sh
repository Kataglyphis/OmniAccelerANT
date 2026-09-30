#!/usr/bin/env bash
# This repo's lint gates, the one command CI and a developer both run; the hub owns every gate.
set -euo pipefail

_run_lint_gates_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${_run_lint_gates_dir}/lib/antfrastructure.sh"

# Not --exclude rust_builder: it would drop first-party secrets from the scan; --ratchets must match CI's ratchets: true.
antfrastructure_exec linux/scripts/run-lint-gates.sh "${KATAGLYPHIS_REPO_ROOT}" \
  --exclude third_party \
  --ratchets \
  "$@"

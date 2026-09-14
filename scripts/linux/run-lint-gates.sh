#!/usr/bin/env bash
# run-lint-gates.sh - this repo's lint gates, in the one command CI and a
# developer both run. Thin wrapper; the hub owns every gate and the resolver
# convention - third_party/ANTfrastructure/docs/shared-script-libraries.md.
set -euo pipefail

_run_lint_gates_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${_run_lint_gates_dir}/lib/antfrastructure.sh"

# WHY --exclude third_party AND NOT rust_builder, although every other gate in
# this repo exempts rust_builder/cargokit/: upstream's --exclude drops a
# TOP-LEVEL directory, and cargokit is one level further down. Excluding
# rust_builder would also drop 13 tracked first-party files from the SECRET
# scope — including rust_builder/android/gradle.properties, which is precisely
# where an Android signing password lives. Losing secret coverage to spare a
# vendored file a shell lint is the wrong trade. Measured, not assumed: both
# vendored Cargokit scripts (build_pod.sh, run_build_tool.sh) pass this repo's
# shell gate today — 19 tracked *.sh, `-S error` clean. If a future Cargokit
# bump breaks that, the fix is an upstream --exclude that takes a path prefix,
# not a suppression here.
antfrastructure_exec linux/scripts/run-lint-gates.sh "${KATAGLYPHIS_REPO_ROOT}" --exclude third_party "$@"

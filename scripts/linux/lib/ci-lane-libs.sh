#!/usr/bin/env bash
# The libraries every CI lane entry needs; a lane adds its own beside this, and sourcing them runs no lane work.
_ci_lane_libs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/cli-common.sh
source "${_ci_lane_libs_dir}/cli-common.sh"
# shellcheck source=scripts/linux/lib/ci-options.sh
source "${_ci_lane_libs_dir}/ci-options.sh"
# shellcheck source=scripts/linux/lib/container-steps.sh
source "${_ci_lane_libs_dir}/container-steps.sh"

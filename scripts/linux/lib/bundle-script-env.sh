#!/usr/bin/env bash
# The libraries both bundle closure scripts need, in the order their definitions depend on; it does no bundle work.
_bundle_script_env_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/cli-common.sh
source "${_bundle_script_env_dir}/cli-common.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "${_bundle_script_env_dir}/bundle-runtime.sh"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${_bundle_script_env_dir}/antfrastructure.sh"
# shellcheck source=scripts/linux/lib/entry-options.sh
source "${_bundle_script_env_dir}/entry-options.sh"

# parse_closure_options <usage> <extra-spec>... -- "$@": the flags both closure scripts take, plus the caller's own.
parse_closure_options() {
  local usage="$1"
  shift
  parse_entry_options "$usage" '' '--arch=MATRIX_ARCH' '-a=MATRIX_ARCH' '--build-mode=BUILD_MODE' '--bundle-dir=BUNDLE_DIR' "$@"
}

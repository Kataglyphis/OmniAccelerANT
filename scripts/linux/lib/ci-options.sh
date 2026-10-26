#!/usr/bin/env bash

# Per-lane maps keep one wrapper from silently accepting another lane's flags.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/antfrastructure.sh"
antfrastructure_source linux/scripts/lib/cli-value-options.sh

_omni_ci_other_arg() {
  case "$1" in
    --no-package)
      if [[ "${_omni_ci_flavor}" == lane-native-linux ]]; then
        # shellcheck disable=SC2034
        RUN_PACKAGING=0
        return 1
      fi
      ;;
    -h|--help) usage; exit 0 ;;
  esac
  echo "Error: unknown argument: $1" >&2
  usage >&2
  exit 2
}

parse_omni_ci_options() {
  local _omni_ci_flavor="$1"
  shift
  local -A _omni_ci_values=([-a]=MATRIX_ARCH [--arch]=MATRIX_ARCH [--flutter-dir]=FLUTTER_DIR)
  local -a _omni_ci_remainder=()

  case "${_omni_ci_flavor}" in
    ci-container-run-android|lane-android)
      _omni_ci_values[--build-mode]=BUILD_MODE
      _omni_ci_values[-n]=APP_NAME
      _omni_ci_values[--app-name]=APP_NAME
      _omni_ci_values[--emulator-smoke]=EMULATOR_SMOKE
      if [[ "${_omni_ci_flavor}" == ci-container-run-android ]]; then
        _omni_ci_values[--run-codeql]=RUN_CODEQL
      fi
      ;;
    ci-container-run-native-linux|lane-native-linux)
      _omni_ci_values[--build-mode]=BUILD_MODE
      _omni_ci_values[-n]=APP_NAME
      _omni_ci_values[--app-name]=APP_NAME
      _omni_ci_values[--package-formats]=PACKAGE_FORMATS
      _omni_ci_values[--strict-checks]=STRICT_CHECKS
      _omni_ci_values[--run-docs]=RUN_DOCS
      if [[ "${_omni_ci_flavor}" == ci-container-run-native-linux ]]; then
        _omni_ci_values[--install-packaging-deps]=INSTALL_PACKAGING_DEPS
        _omni_ci_values[--run-codeql]=RUN_CODEQL
      fi
      ;;
    ci-container-run-web-linux)
      _omni_ci_values[--strict-checks]=STRICT_CHECKS
      _omni_ci_values[--run-codeql]=RUN_CODEQL
      ;;
    *) echo "Error: unknown CI lane: ${_omni_ci_flavor}" >&2; return 2 ;;
  esac

  parse_cli_value_options _omni_ci_values _omni_ci_remainder _omni_ci_other_arg "$@"
}

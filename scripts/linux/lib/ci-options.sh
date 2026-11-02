#!/usr/bin/env bash

# Per-lane maps keep one wrapper from silently accepting another lane's flags.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/antfrastructure.sh"
antfrastructure_source linux/scripts/lib/cli-value-options.sh

# omni_ci_usage <lane> <option-key>...; each help line lives once below, so lanes cannot describe one flag differently by accident.
_omni_ci_option_help() {
  case "$1" in
    arch-label-required) printf '%s\n' '  -a, --arch <x64|arm64>        Target architecture label (required)' ;;
    build-mode-apk-image) printf '%s\n' '  --build-mode <debug|profile|release> Build mode for flutter build apk (default: release)' ;;
    flutter-dir-image) printf '%s\n' '      --flutter-dir <path>      Flutter SDK directory (default: /opt/flutter, baked into the image)' ;;
    app-name-required) printf '%s\n' '  -n, --app-name <name>         Artifact base name (required)' ;;
    emulator-smoke) printf '%s\n' '      --emulator-smoke <bool>   Run the APK on the image'\''s AVD (needs /dev/kvm; default: false)' ;;
    run-codeql-manual) printf '%s\n' '      --run-codeql <bool>       Run CodeQL scan (default: false; the scan is' '                                hours and is a manual/local run since 2026-09-17)' ;;
    help) printf '%s\n' '  -h, --help                    Show this help' ;;
    arch-required) printf '%s\n' '  -a, --arch <x64|arm64>        Target architecture (required)' ;;
    build-mode-linux) printf '%s\n' '  --build-mode <debug|profile|release> Build mode for flutter build linux (default: release)' ;;
    package-formats-tar) printf '%s\n' '      --package-formats <csv>   Packaging formats (default: tar)' ;;
    install-packaging-deps) printf '%s\n' '      --install-packaging-deps <bool> Install the flathub runtime; only consulted when --package-formats has flatpak (default: false)' ;;
    strict-checks) printf '%s\n' '      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)' ;;
    run-codeql-refused) printf '%s\n' '      --run-codeql <bool>       Must be false: no CodeQL scan is implemented here' ;;
    run-docs) printf '%s\n' '      --run-docs <bool>         Run generate-docs.sh, x64 only (default: false; docs.yml builds the site)' ;;
    arch-label-auto) printf '%s\n' '  -a, --arch <x64|arm64>        Host architecture label for artifact naming (default: auto-detect)' ;;
    build-mode-apk) printf '%s\n' '      --build-mode <debug|profile|release> Build mode for flutter build apk (default: release)' ;;
    app-name-apk) printf '%s\n' '  -n, --app-name <name>         Artifact base name (default: pubspec name + -apk)' ;;
    flutter-dir-optional) printf '%s\n' '      --flutter-dir <path>      Optional Flutter SDK directory (uses <path>/bin/flutter)' ;;
    arch-auto) printf '%s\n' '  -a, --arch <x64|arm64>        Target architecture (default: auto-detect)' ;;
    app-name-default) printf '%s\n' '  -n, --app-name <name>         Artifact base name (default: pubspec name)' ;;
    package-formats-all) printf '%s\n' '      --package-formats <csv>   Packaging formats (default: tar,appimage,flatpak,deb)' ;;
    no-package) printf '%s\n' '      --no-package              Build only (skip packaging)' ;;
    *) echo "Error: unknown usage key: $1" >&2; return 2 ;;
  esac
}

omni_ci_usage() {
  local lane="$1" key
  shift
  printf 'Usage:\n  bash scripts/linux/ci/%s.sh [options]\n\nOptions:\n' "$lane"
  for key in "$@"; do _omni_ci_option_help "$key"; done
}

# omni_ci_lane_notes <body-sentence>: the two note lines a direct lane adds under its options.
omni_ci_lane_notes() {
  printf '\nNotes:\n  - %s\n  - Requires flutter + dart available (either on PATH or via --flutter-dir).\n' "$1"
}

# omni_ci_validate_lane_args <app-name> <arch> <build-mode>: the direct lanes' refusals, in the order they always ran.
omni_ci_validate_lane_args() {
  if [[ -z "$1" ]]; then
    echo "Error: --app-name must not be empty" >&2
    exit 2
  fi
  if ! validate_arch "$2"; then
    exit 2
  fi
  omni_ci_validate_build_mode "$3"
}

omni_ci_validate_build_mode() {
  case "$1" in
    debug|profile|release) ;;
    *)
      echo "Error: --build-mode must be one of: debug, profile, release (got: ${1:-<empty>})" >&2
      return 2
      ;;
  esac
}

# omni_ci_require <check> <args>...: a container wrapper refuses bad input with its usage on stderr.
omni_ci_require() {
  if ! "$@"; then
    usage >&2
    exit 2
  fi
}

# omni_ci_lane_args <arch> <build-mode> <app-name> <flutter-dir>: one argument per line, what every wrapper hands its lane.
omni_ci_lane_args() {
  printf '%s\n' --arch "$1" --build-mode "$2" --app-name "$3" --flutter-dir "$4"
}

# omni_ci_enter_workspace: sets REPO_ROOT, says when /workspace is absent, and changes into it.
omni_ci_enter_workspace() {
  REPO_ROOT="$(resolve_repo_root /workspace)"
  if [[ "$REPO_ROOT" != "/workspace" ]]; then
    echo "[Info] /workspace nicht gefunden, benutze stattdessen $REPO_ROOT als Arbeitsverzeichnis."
  fi
  cd "$REPO_ROOT" || exit
}

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

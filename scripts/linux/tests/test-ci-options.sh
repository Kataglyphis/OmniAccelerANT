#!/usr/bin/env bash
# Parser-only checks do not run Flutter, Android or container builds.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${repo}/scripts/linux/lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"

probe() {
  local library="${OMNI_CI_OPTIONS_LIB:-${repo}/scripts/linux/lib/ci-options.sh}"
  KATAGLYPHIS_REPO_ROOT="${repo}" ANTFRASTRUCTURE_DIR="${repo}/third_party/ANTfrastructure" \
    bash -c '
      set -euo pipefail
      source "$1"
      usage() { printf "Usage: probe\n"; }
      MATRIX_ARCH=arch0 BUILD_MODE=mode0 FLUTTER_DIR=flutter0 APP_NAME=app0
      RUN_CODEQL=codeql0 EMULATOR_SMOKE=smoke0 PACKAGE_FORMATS=formats0
      INSTALL_PACKAGING_DEPS=deps0 STRICT_CHECKS=strict0 RUN_DOCS=docs0 RUN_PACKAGING=1
      flavor="$2"
      shift 2
      parse_omni_ci_options "$flavor" "$@"
      printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "$MATRIX_ARCH" "$BUILD_MODE" "$FLUTTER_DIR" "$APP_NAME" "$RUN_CODEQL" \
        "$EMULATOR_SMOKE" "$PACKAGE_FORMATS" "$INSTALL_PACKAGING_DEPS" \
        "$STRICT_CHECKS" "$RUN_DOCS" "$RUN_PACKAGING"
    ' _ "$library" "$@"
}

value_cases() {
  t_case 'android aliases and values beginning with a dash retain caller order'
  t_assert_eq 'x64|profile|-sdk|-app|false|true|formats0|deps0|strict0|docs0|1' \
    "$(probe ci-container-run-android -a arm64 --arch x64 --build-mode profile \
      --flutter-dir -sdk -n old --app-name -app --emulator-smoke true --run-codeql false)"

  t_case 'native container accepts only its option set'
  t_assert_eq 'arm64|debug|/flutter|demo|false|smoke0|tar,flatpak|true|1|yes|1' \
    "$(probe ci-container-run-native-linux --arch arm64 --build-mode debug \
      --flutter-dir /flutter --app-name demo --package-formats tar,flatpak \
      --install-packaging-deps true --strict-checks 1 --run-codeql false --run-docs yes)"

  t_case 'web container retains defaults and its own options'
  t_assert_eq 'x64|mode0|/sdk|app0|true|smoke0|formats0|deps0|false|docs0|1' \
    "$(probe ci-container-run-web-linux -a x64 --flutter-dir /sdk --strict-checks false --run-codeql true)"

  t_case 'android lane keeps its container-only CodeQL value untouched'
  t_assert_eq 'arm64|release|/sdk|demo|codeql0|yes|formats0|deps0|strict0|docs0|1' \
    "$(probe lane-android --arch arm64 --build-mode release --flutter-dir /sdk \
      --app-name demo --emulator-smoke yes)"

  t_case 'native lane consumes no-package before later value options'
  t_assert_eq 'x64|release|-sdk|demo|codeql0|smoke0|tar|deps0|true|no|0' \
    "$(probe lane-native-linux --no-package -a x64 --build-mode release \
      --flutter-dir -sdk -n demo --package-formats tar --strict-checks true --run-docs no)"
}

value_cases
if [[ "${1:-}" == --value-only ]]; then t_summary; exit; fi

t_case 'a missing value is fatal with the flag named'
t_assert_rc 1 probe ci-container-run-android --arch
missing="$(probe ci-container-run-android --arch 2>&1)" || :
t_assert_contains "$missing" '--arch expects a value'

t_case 'end-of-options was never accepted by these lanes'
t_assert_rc 2 probe lane-android --
t_assert_rc 2 probe ci-container-run-web-linux --no-package
t_assert_rc 2 probe lane-native-linux --run-codeql true
t_assert_rc 2 probe lane-android --run-codeql true
t_assert_rc 2 probe ci-container-run-web-linux --build-mode release
t_assert_rc 2 probe lane-native-linux --install-packaging-deps true
t_assert_rc 2 probe ci-container-run-android --strict-checks true

t_case 'help and unknown flags retain their original verdicts'
t_assert_eq 'Usage: probe' "$(probe lane-native-linux --help)"
t_assert_rc 2 probe ci-container-run-android --unknown

for flavor in ci-container-run-android ci-container-run-native-linux ci-container-run-web-linux \
              lane-android lane-native-linux; do
  script="${repo}/scripts/linux/ci/${flavor}.sh"
  t_case "${flavor} sources the parser before work starts"
  t_assert_rc 0 bash -n "$script"
  t_assert_rc 0 bash "$script" --help
  t_assert_rc 1 bash "$script" --arch
  t_assert_rc 2 bash "$script" --
done

t_case 'web rejects a requested scan that does not exist'
web="${repo}/scripts/linux/ci/ci-container-run-web-linux.sh"
t_assert_rc 2 bash "$web" --arch x64 --run-codeql true
web_error="$(bash "$web" --arch x64 --run-codeql true 2>&1)" || :
t_assert_contains "$web_error" 'implements no CodeQL scan'
t_assert_rc 0 bash "$web" --run-codeql false --help

mkdir -p "${repo}/logs/test-results"
mutant_dir="$(mktemp -d "${repo}/logs/test-results/ci-options-mutant.XXXXXX")" || exit 1
trap 'rm -rf -- "${mutant_dir}"' EXIT
cp "${repo}/scripts/linux/lib/"{ci-options.sh,antfrastructure.sh,renovate-git-mode.sh} "${mutant_dir}/"
sed -i 's/_omni_ci_values\[--run-codeql\]=RUN_CODEQL/_omni_ci_values[--run-codeql]=FLUTTER_DIR/g' "${mutant_dir}/ci-options.sh"
grep -Fq '_omni_ci_values[--run-codeql]=FLUTTER_DIR' "${mutant_dir}/ci-options.sh" || exit 1
t_case 'a changed value destination fails the real parser assertions'
mutant_output="$(OMNI_CI_OPTIONS_LIB="${mutant_dir}/ci-options.sh" bash "$0" --value-only 2>&1)" && mutant_rc=0 || mutant_rc=$?
t_assert_eq 1 "$mutant_rc"
t_assert_contains "$mutant_output" 'FAIL'

t_summary

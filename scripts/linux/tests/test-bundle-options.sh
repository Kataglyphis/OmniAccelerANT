#!/usr/bin/env bash
# Parser checks run without a built bundle; they do not prove ELF, GStreamer or ABI behavior.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${repo}/scripts/linux/lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"

probe() {
  local library="${BUNDLE_OPTIONS_LIB:-${repo}/scripts/linux/lib/bundle-options.sh}"
  KATAGLYPHIS_REPO_ROOT="${repo}" ANTFRASTRUCTURE_DIR="${repo}/third_party/ANTfrastructure" \
    bash -c '
      set -euo pipefail
      source "$1"
      source "$2"
      matrix_arch=arch0 build_mode=mode0 bundle_dir=dir0 bundle_lib=lib0
      kind="$3"
      shift 3
      parse_bundle_gate_options "$kind" "$@"
      validate_arch "$matrix_arch" || exit 2
      validate_build_mode "$build_mode" || exit 2
      printf "%s|%s|%s|%s\n" "$matrix_arch" "$build_mode" "$bundle_dir" "$bundle_lib"
    ' _ "${repo}/scripts/linux/lib/cli-common.sh" "$library" "$@"
}

value_cases() {
  t_case 'GStreamer gate assigns repeated values in caller order'
  t_assert_eq 'x64|profile|/bundle|lib0' \
    "$(probe gst --arch arm64 --arch x64 --build-mode profile --bundle-dir /bundle)"

  t_case 'ABI gate retains its distinct bundle-lib option'
  t_assert_eq 'arm64|debug|dir0|/plugin' \
    "$(probe knt --arch arm64 --build-mode debug --bundle-lib /plugin)"
}

value_cases
if [[ "${1:-}" == --values-only ]]; then t_summary; exit; fi

for gate in check-bundle-gst-elements check-knt-abi; do
  entry="${repo}/scripts/linux/${gate}.sh"
  t_case "${gate} retains help and unknown-option behavior"
  t_assert_rc 0 bash "$entry" --help
  t_assert_rc 2 bash "$entry" --unknown
  t_assert_rc 2 bash "$entry" --

  t_case "${gate} retains missing and empty value failures"
  t_assert_rc 1 bash "$entry" --arch
  t_assert_rc 1 bash "$entry" --build-mode ''
  missing="$(bash "$entry" --arch 2>&1)" || :
  t_assert_contains "$missing" '--arch needs a value'

  t_case "${gate} rejects invalid architecture and build mode"
  t_assert_rc 2 bash "$entry" --arch invalid
  t_assert_rc 2 bash "$entry" --build-mode invalid
done

t_case 'each gate keeps its own bundle path option'
t_assert_rc 2 bash "${repo}/scripts/linux/check-bundle-gst-elements.sh" --bundle-lib /plugin
t_assert_rc 2 bash "${repo}/scripts/linux/check-knt-abi.sh" --bundle-dir /bundle

t_case 'the closure builder uses the same build-mode validator'
t_assert_rc 2 bash "${repo}/scripts/linux/bundle-runtime-closure.sh" --build-mode invalid
t_assert_rc 0 bash "${repo}/scripts/linux/bundle-runtime-closure.sh" --help

mkdir -p "${repo}/logs/test-results"
mutant_dir="$(mktemp -d "${repo}/logs/test-results/bundle-options-mutant.XXXXXX")" || exit 1
trap 'rm -rf -- "${mutant_dir}"' EXIT
cp "${repo}/scripts/linux/lib/"{bundle-options.sh,antfrastructure.sh,renovate-git-mode.sh} "${mutant_dir}/"
sed -i 's/_bundle_gate_values\[--bundle-lib\]=bundle_lib/_bundle_gate_values[--bundle-lib]=bundle_dir/' \
  "${mutant_dir}/bundle-options.sh"
grep -Fq '_bundle_gate_values[--bundle-lib]=bundle_dir' "${mutant_dir}/bundle-options.sh" || exit 1
t_case 'a wrong ABI option destination fails the real parser assertions (mutation)'
mutant_output="$(BUNDLE_OPTIONS_LIB="${mutant_dir}/bundle-options.sh" bash "$0" --values-only 2>&1)" && mutant_rc=0 || mutant_rc=$?
t_assert_eq 1 "$mutant_rc"
t_assert_contains "$mutant_output" 'FAIL'

t_summary

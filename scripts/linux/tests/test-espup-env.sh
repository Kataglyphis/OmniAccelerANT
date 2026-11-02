#!/usr/bin/env bash
# Fake export files cover host setup only; firmware and flashing need hardware.
# shellcheck disable=SC1091,SC2016
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf -- "${work}"' EXIT
helper="${ESPUP_ENV_LIB:-${repo}/scripts/linux/lib/espup-env.sh}"

probe() {
  env -u RUSTUP_HOME -u CARGO_HOME HOME="${work}/home" ESPUP_HOME="${work}/espup" bash -c '
    set -euo pipefail
    source "$1"
    omni_espup_environment
    printf "%s|%s|%s|%s\n" "${ESPUP_MARK:-}" "${RUSTUP_HOME:-}" "${CARGO_HOME:-}" "$PATH"
  ' _ "$helper"
}

mkdir -p "${work}/home" "${work}/espup"
printf 'export ESPUP_MARK=preferred\n' > "${work}/espup/export.sh"
printf 'export ESPUP_MARK=fallback\n' > "${work}/home/export-esp.sh"
t_case 'the pinned espup export wins over the home fallback'
preferred="$(probe)"
t_assert_contains "$preferred" "preferred|${work}/espup/rustup|${work}/espup/cargo|${work}/espup/cargo/bin:${work}/espup/bin:"

rm -- "${work}/espup/export.sh"
t_case 'the home export is used when the pinned export is absent'
t_assert_contains "$(probe)" 'fallback|||'

printf 'return 7\n' > "${work}/espup/export.sh"
t_case 'a failed export stays fatal when a caller tests the helper status'
t_assert_rc 7 env HOME="${work}/home" ESPUP_HOME="${work}/espup" bash -c '
  source "$1"
  if omni_espup_environment; then exit 0; else exit $?; fi
' _ "$helper"

rm -- "${work}/espup/export.sh"
rm -- "${work}/home/export-esp.sh"
t_case 'a missing toolchain fails with the setup instruction'
t_assert_rc 2 probe
missing="$(probe 2>&1)" || :
t_assert_contains "$missing" "espup install --targets esp32s3"

if [[ "${1:-}" == --values-only ]]; then t_summary; fi

printf 'export ESPUP_MARK=preferred\n' > "${work}/espup/export.sh"
sed 's|export CARGO_HOME="${espup_home}/cargo"|export CARGO_HOME=broken|' "$helper" > "${work}/mutant.sh"
grep -Fq 'export CARGO_HOME=broken' "${work}/mutant.sh" || exit 1
t_mutant_breaks_suite 'a wrong Cargo home breaks the shared environment assertions' \
  ESPUP_ENV_LIB "${work}/mutant.sh" --values-only

t_summary

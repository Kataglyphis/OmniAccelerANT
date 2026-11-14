#!/usr/bin/env bash
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
# Every ObservANT package path builds and takes OxidANT's observant profile (release, panic = "unwind"); not covered: a build.
set -uo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${script_dir}/../../.." && pwd)"
# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "${script_dir}/harness-bootstrap.sh"

linux="$(cat "${root}/scripts/linux/observant/package-observant.sh")"
bundle="$(cat "${root}/scripts/linux/observant/package-producer-bundle.sh")"
windows="$(cat "${root}/scripts/windows/observant/Package-ObservANT.ps1")"
workspace="$(cat "${root}/third_party/OxidANT/Cargo.toml")"

t_case 'the pinned OxidANT has the profile'
t_assert_contains "${workspace}" '[profile.observant]'
t_assert_contains "${workspace}" 'panic = "unwind"'

t_case 'the Linux package builds and takes it'
t_assert_contains "${linux}" 'cargo build --profile observant --locked -p kataglyphis_observant'
t_assert_contains "${linux}" 'producer="${CARGO_TARGET_DIR}/observant/kataglyphis_observant"'

t_case 'the producer bundle takes it'
t_assert_contains "${bundle}" 'producer="/cargo-target/observant/kataglyphis_observant"'
t_assert_contains "${bundle}" 'install -m 755 /cargo-target/observant/kataglyphis_observant /out/bin/'

t_case 'the Windows package builds and takes it, arm64 too'
t_assert_contains "${windows}" "@('build', '--profile', 'observant', '--locked', '-p', 'kataglyphis_observant')"
t_assert_contains "${windows}" "\$releaseDir = 'aarch64-pc-windows-msvc\\observant'"

t_case 'no path still builds the service with --release'
stale="$(printf '%s\n' "${linux}" "${bundle}" "${windows}" \
  | grep -cE -- "--release --locked -p kataglyphis_observant|'--release', '--locked'|release/kataglyphis_observant" || true)"
t_assert_eq "${stale}" 0

t_summary

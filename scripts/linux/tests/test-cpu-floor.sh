#!/usr/bin/env bash
# The amd64 CPU floor's exports and its CMake-cache gate; it does not read the Rust codegen of a built liboxidant.so.
set -uo pipefail

# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
# shellcheck source=scripts/linux/lib/cpu-floor.sh
source "${KATAGLYPHIS_REPO_ROOT}/scripts/linux/lib/cpu-floor.sh"
t_workdir

cat > "${work}/export.sh" <<'EOF'
source "$1" && omni_export_cpu_floor "$2" || exit 1
exec bash "$3"
EOF
# A child process, so a variable the export sets but does not export reads as unset.
cat > "${work}/print.sh" <<'EOF'
printf 'C=%s\nCXX=%s\nRUST=%s\n' "${CFLAGS-unset}" "${CXXFLAGS-unset}" "${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS-unset}"
EOF

# floor_env <arch> [VAR=value...]: the three variables after the export, one per line, or the export's failure.
floor_env() {
  local arch="$1"
  shift
  env -u CFLAGS -u CXXFLAGS -u RUSTFLAGS -u CARGO_ENCODED_RUSTFLAGS -u CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS \
    "$@" bash "${work}/export.sh" "${KATAGLYPHIS_REPO_ROOT}/scripts/linux/lib/cpu-floor.sh" "${arch}" "${work}/print.sh"
}

for arch in x64 x86_64 amd64; do
  t_case "${arch} gets the floor for clang and Rust"
  t_assert_eq $'C=-march=x86-64-v3\nCXX=-march=x86-64-v3\nRUST=-C target-cpu=x86-64-v3' "$(floor_env "${arch}")"
done
for arch in arm64 aarch64 riscv64; do
  t_case "${arch} keeps its own level"
  t_assert_eq $'C=unset\nCXX=unset\nRUST=unset' "$(floor_env "${arch}")"
done

t_case "a caller's flags stay, and a second export adds nothing"
t_assert_eq $'C=-O2 -march=x86-64-v3\nCXX=-g -march=x86-64-v3\nRUST=-C debuginfo=1 -C target-cpu=x86-64-v3' \
  "$(floor_env x64 CFLAGS='-O2 -march=x86-64-v3' CXXFLAGS=-g CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS='-C debuginfo=1')"

t_case "RUSTFLAGS would replace the target flags, so the export refuses it"
t_assert_rc 1 floor_env x64 RUSTFLAGS='-C opt-level=3'
t_case "CARGO_ENCODED_RUSTFLAGS is refused the same way"
t_assert_rc 1 floor_env x64 CARGO_ENCODED_RUSTFLAGS='-Copt-level=3'
t_case "RUSTFLAGS on arm64 is none of the floor's business"
t_assert_rc 0 floor_env arm64 RUSTFLAGS='-C opt-level=3'

# cache_with <c-flags> <cxx-flags>: a build directory whose CMakeCache.txt records them.
cache_with() {
  local dir
  dir="$(mktemp -d "${work}/build.XXXXXX")"
  printf 'CMAKE_BUILD_TYPE:STRING=Release\nCMAKE_C_FLAGS:STRING=%s\nCMAKE_CXX_FLAGS:STRING=%s\n' "$1" "$2" > "${dir}/CMakeCache.txt"
  printf '%s' "${dir}"
}

t_case "a configure that took the floor passes"
t_assert_rc 0 omni_check_cpu_floor "$(cache_with '-march=x86-64-v3' '-march=x86-64-v3 --gcc-toolchain=/opt/gcc')"
t_case "C++ without the floor fails"
t_assert_rc 1 omni_check_cpu_floor "$(cache_with '-march=x86-64-v3' '')"
t_case "C without the floor fails"
t_assert_rc 1 omni_check_cpu_floor "$(cache_with '-O2' '-march=x86-64-v3')"
t_case "a longer level is not the floor"
t_assert_rc 1 omni_check_cpu_floor "$(cache_with '-march=x86-64-v3x' '-march=x86-64-v3x')"
t_case "a build directory without a cache fails, and says so"
t_assert_rc 1 omni_check_cpu_floor "${work}"
t_assert_contains "$(omni_check_cpu_floor "${work}" 2>&1)" "no ${work}/CMakeCache.txt"

t_summary

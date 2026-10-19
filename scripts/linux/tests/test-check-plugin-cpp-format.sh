#!/usr/bin/env bash
# The plugin's C++ format gate on a throwaway package: one green, and each way it must go red or refuse.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
gate="${SCRIPT_DIR}/../check-plugin-cpp-format.sh"
config="${SCRIPT_DIR}/../../../packages/kataglyphis_native_inference/.clang-format"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

[ -f "${config}" ] || { printf 'FAIL no plugin .clang-format at %s\n' "${config}" >&2; exit 1; }

# make_pkg <dir>: a git package with the plugin's config, one clean source and the example runner the gate skips.
make_pkg() {
  local dir="$1"
  mkdir -p "${dir}/linux" "${dir}/example/linux/runner"
  cp "${config}" "${dir}/.clang-format"
  printf 'int answer();\n' > "${dir}/linux/clean.cc"
  printf 'int runner_main();\n' > "${dir}/example/linux/runner/main.cc"
  git -C "${dir}" init -q
  git -C "${dir}" add -A
}

# fake_clang_format <dir> <version line>: a clang-format on PATH that only reports a version.
fake_clang_format() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$2" > "$1/clang-format"
  chmod +x "$1/clang-format"
}

# gate_out <args...>: the gate, its output also kept in ${work}/out for the case after it.
gate_out() {
  bash "${gate}" "$@" 2>&1 | tee "${work}/out"
}

# named_and_kept: the gate's output names the planted file, and the file is as it was.
named_and_kept() {
  if grep -q -e 'linux/clean.cc' "${work}/out" && [ "$(sha256sum "${work}/planted/linux/clean.cc")" = "${before}" ]; then
    return 0
  fi
  return 1
}

make_pkg "${work}/clean"
t_case "a package that matches its .clang-format"
t_assert_rc 0 bash "${gate}" --package-dir "${work}/clean"

make_pkg "${work}/planted"
printf 'int  answer();\n' > "${work}/planted/linux/clean.cc"
before="$(sha256sum "${work}/planted/linux/clean.cc")"
t_case "a planted deviation in a hand-written file"
t_assert_rc 1 gate_out --package-dir "${work}/planted"
t_case "the deviating file is named and left as it was"
t_assert_ok named_and_kept

make_pkg "${work}/runner"
printf 'int  runner_main();\n' > "${work}/runner/example/linux/runner/main.cc"
t_case "a deviation only in the example runner, which is generated"
t_assert_rc 0 bash "${gate}" --package-dir "${work}/runner"

make_pkg "${work}/noconfig"
rm "${work}/noconfig/.clang-format"
t_case "no .clang-format, so the LLVM fallback would grade"
t_assert_rc 2 bash "${gate}" --package-dir "${work}/noconfig"

mkdir -p "${work}/empty"
cp "${config}" "${work}/empty/.clang-format"
git -C "${work}/empty" init -q
t_case "no tracked C/C++ to grade"
t_assert_rc 2 bash "${gate}" --package-dir "${work}/empty"

t_case "a package directory that does not exist"
t_assert_rc 2 bash "${gate}" --package-dir "${work}/absent"

t_case "a clang-format other than LLVM_RELEASE"
LLVM_RELEASE=99.9.9 t_assert_rc 2 bash "${gate}" --package-dir "${work}/clean"

fake_clang_format "${work}/bin-21" "Ubuntu clang-format version 21.1.8 (6ubuntu1)"
t_case "the distro's clang-format 21"
PATH="${work}/bin-21:${PATH}" LLVM_RELEASE=23.1.3 t_assert_rc 2 bash "${gate}" --package-dir "${work}/clean"

fake_clang_format "${work}/bin-prefix" "clang-format version 23.1.30 (https://github.com/llvm/llvm-project.git)"
t_case "23.1.30 is not 23.1.3"
PATH="${work}/bin-prefix:${PATH}" LLVM_RELEASE=23.1.3 t_assert_rc 2 bash "${gate}" --package-dir "${work}/clean"

t_summary

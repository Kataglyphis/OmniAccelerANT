#!/usr/bin/env bash
# The plugin's C++ format gate on a throwaway package: one green, and each way it must go red or refuse.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

passed=0
expect() {
  local want="$1" name="$2" got=0
  shift 2
  bash "${gate}" "$@" >"${work}/out" 2>&1 || got=$?
  if [ "${got}" -ne "${want}" ]; then
    printf 'FAIL %s: expected rc %s, got %s\n' "${name}" "${want}" "${got}" >&2
    sed 's/^/     /' "${work}/out" >&2
    return 1
  fi
  passed=$((passed + 1))
  printf 'ok   %s\n' "${name}"
}

make_pkg "${work}/clean"
expect 0 "a package that matches its .clang-format" --package-dir "${work}/clean"

make_pkg "${work}/planted"
printf 'int  answer();\n' > "${work}/planted/linux/clean.cc"
before="$(sha256sum "${work}/planted/linux/clean.cc")"
expect 1 "a planted deviation in a hand-written file" --package-dir "${work}/planted"
grep -q -e 'linux/clean.cc' "${work}/out" || { printf 'FAIL the deviating file is not named\n' >&2; exit 1; }
[ "$(sha256sum "${work}/planted/linux/clean.cc")" = "${before}" ] || { printf 'FAIL the gate rewrote a file\n' >&2; exit 1; }
passed=$((passed + 1))
printf 'ok   %s\n' "the deviating file is named and left as it was"

make_pkg "${work}/runner"
printf 'int  runner_main();\n' > "${work}/runner/example/linux/runner/main.cc"
expect 0 "a deviation only in the example runner, which is generated" --package-dir "${work}/runner"

make_pkg "${work}/noconfig"
rm "${work}/noconfig/.clang-format"
expect 2 "no .clang-format, so the LLVM fallback would grade" --package-dir "${work}/noconfig"

mkdir -p "${work}/empty"
cp "${config}" "${work}/empty/.clang-format"
git -C "${work}/empty" init -q
expect 2 "no tracked C/C++ to grade" --package-dir "${work}/empty"

expect 2 "a package directory that does not exist" --package-dir "${work}/absent"

LLVM_RELEASE=99.9.9 expect 2 "a clang-format other than LLVM_RELEASE" --package-dir "${work}/clean"

fake_clang_format "${work}/bin-21" "Ubuntu clang-format version 21.1.8 (6ubuntu1)"
PATH="${work}/bin-21:${PATH}" LLVM_RELEASE=23.1.3 expect 2 "the distro's clang-format 21" --package-dir "${work}/clean"

fake_clang_format "${work}/bin-prefix" "clang-format version 23.1.30 (https://github.com/llvm/llvm-project.git)"
PATH="${work}/bin-prefix:${PATH}" LLVM_RELEASE=23.1.3 expect 2 "23.1.30 is not 23.1.3" --package-dir "${work}/clean"

printf '  %d assertion(s) passed\n' "${passed}"

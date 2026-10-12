#!/usr/bin/env bash
# The native plugin's hand-written C/C++ against its .clang-format: it checks and never rewrites, and only LLVM_RELEASE grades.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/lib/antfrastructure.sh"
antfrastructure_source linux/scripts/01-core/load-versions-env.sh
antfrastructure_source linux/scripts/lib/code-quality.sh

package_dir="${KATAGLYPHIS_REPO_ROOT}/packages/kataglyphis_native_inference"

while [ $# -gt 0 ]; do
  case "$1" in
    --package-dir) package_dir="${2:?--package-dir needs a path}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--package-dir DIR]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# Exit 2 is "could not grade", which is red too: a gate that did not run must not read as a clean tree.
refuse() {
  printf 'REFUSED %s\n' "$*" >&2
  exit 2
}

[ -d "${package_dir}" ] || refuse "no package at ${package_dir}"
cd "${package_dir}"
[ -f .clang-format ] || refuse "no .clang-format in ${package_dir}; clang-format would grade against its LLVM fallback"

# The environment first, then the pinned hub's versions.env: the order load_versions_env gives every hub script.
versions_env="$(antfrastructure_path linux/scripts/01-core/versions.env)"
llvm_release="$(load_versions_env "${versions_env}"; printf '%s' "${LLVM_RELEASE:-}")"
[ -n "${llvm_release}" ] || refuse "LLVM_RELEASE is unset; ${versions_env} no longer publishes it"

command -v clang-format >/dev/null 2>&1 || refuse "clang-format is not on PATH"
version="$(clang-format --version)"
# Releases format differently, so 23.1.30 must not pass for 23.1.3.
if ! grep -Eq -e "clang-format version ${llvm_release//./\\.}([^0-9.]|\$)" <<<"${version}"; then
  refuse "clang-format reports '${version}', not LLVM_RELEASE ${llvm_release}"
fi

# The extension set code_quality_find_cpp_files uses, as pathspecs for the tracked-file walk.
exts=("${CODE_QUALITY_CPP_FORMAT_EXTENSIONS[@]:-}")
[ -n "${exts[0]:-}" ] || exts=(c cc cpp cxx h hh hpp hxx ixx cppm ccm cxxm mpp)
patterns=("${exts[@]/#/*.}")

# Tracked files only; runner/ is the example app's Flutter scaffolding, which the comment-size gate skips as generated.
files=()
while IFS= read -r f; do
  case "${f}" in
    runner/*|*/runner/*) continue ;;
  esac
  files+=("${f}")
done < <(code_quality_find_tracked_files . "${patterns[@]}")
[ "${#files[@]}" -gt 0 ] || refuse "no tracked C/C++ under ${package_dir}; an empty set is a discovery bug, not a clean tree"

code_quality_check_clang_format "${files[@]}"
if [ "${CODE_QUALITY_CLANG_FORMAT_DEVIATIONS}" -gt 0 ]; then
  shown=0
  for f in "${files[@]}"; do
    [ "${shown}" -lt 5 ] || break
    out="$(clang-format --dry-run -Werror "${f}" 2>&1 || true)"
    if [ -n "${out}" ]; then
      head -n 12 <<<"${out}"
      shown=$((shown + 1))
    fi
  done
  printf 'FAIL %s of %s file(s) deviate; rewrite them with clang-format %s -i\n' \
    "${CODE_QUALITY_CLANG_FORMAT_DEVIATIONS}" "${#files[@]}" "${llvm_release}" >&2
  exit 1
fi
printf 'OK   %s file(s) in %s match .clang-format under clang-format %s\n' "${#files[@]}" "${package_dir}" "${llvm_release}"

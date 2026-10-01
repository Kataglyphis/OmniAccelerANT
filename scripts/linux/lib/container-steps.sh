#!/usr/bin/env bash

_container_steps_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${_container_steps_dir}/antfrastructure.sh"

antfrastructure_source linux/scripts/01-core/platform.sh
antfrastructure_source linux/scripts/01-core/logging.sh
# Sourced here for every checking driver; only drivers open a batch, never a helper below.
antfrastructure_source linux/scripts/01-core/gates.sh
# flutter_lane_prepare_env / flutter_build_web - see the block below.
antfrastructure_source linux/scripts/05-frameworks/flutter/lane-prologue.sh

# is_truthy plus a bare "y" and mixed case.
maybe_truthy() {
  local value="${1:-}"
  is_truthy "${value,,}" || [[ "${value,,}" == "y" ]]
}

# Tracked files only (AGENTS.md § 4); the driver resolves on its own line, as set -e is off inside run_gate.
run_flutter_common_checks() {
  local strict_mode="${1:-0}" strict_flag checks
  shift || true
  if maybe_truthy "$strict_mode"; then strict_flag=true; else strict_flag=false; fi
  checks="$(antfrastructure_path linux/scripts/05-frameworks/flutter/flutter_checks.sh)" || return 1
  bash "$checks" --strict "$strict_flag" "$@" || return 1
  run_plugin_dart_tests "$strict_flag"
}

KATAGLYPHIS_PLUGIN_PACKAGE="packages/kataglyphis_native_inference"

# The hub's checks test the root package only; the plugin's own suite is graded with the same strictness.
run_plugin_dart_tests() {
  local strict_flag="${1:-true}"
  echo "[Info] Dart tests of ${KATAGLYPHIS_PLUGIN_PACKAGE}"
  if (cd "$KATAGLYPHIS_PLUGIN_PACKAGE" && flutter pub get && flutter test); then
    return 0
  fi
  if [[ "$strict_flag" == true ]]; then
    return 1
  fi
  echo "[Warn] the plugin's Dart tests failed (non-strict, continuing)." >&2
}

# EXCLUDE_FROM_ALL keeps the gtest out of the app build, so this builds it by name; KATAGLYPHIS_PLUGIN_TESTS=1 must reach the configure.
run_plugin_gtest() {
  local build_dir="${1:?app build dir required}"
  cmake --build "$build_dir" --target kataglyphis_native_inference_test || return 1
  ctest --test-dir "${build_dir}/plugins/kataglyphis_native_inference" --output-on-failure --no-tests=error
}

# The executable CMake names, read where it is set rather than guessed from the package name.
linux_binary_name() {
  sed -n 's/^set(BINARY_NAME "\([^"]*\)")$/\1/p' linux/CMakeLists.txt
}

# A missing library or a startup crash ends the app at once; timeout's 124 means it was still up.
run_launch_smoke() {
  local exe="${1:?executable required}" seconds="${2:-20}" rc=0
  if [[ ! -x "$exe" ]]; then
    echo "[Error] no executable at ${exe}" >&2
    return 1
  fi
  xvfb-run -a timeout "$seconds" "$exe" || rc=$?
  if [[ "$rc" -eq 124 ]]; then
    echo "[Info] $(basename "$exe") still running after ${seconds} s"
    return 0
  fi
  echo "[Error] $(basename "$exe") exited with ${rc} within ${seconds} s" >&2
  return 1
}

# A debug build under build/linux/<arch>/debug, so the release bundle stays as packaged; non-incremental cargo is sccache-cacheable.
run_integration_test() {
  local target="${1:-integration_test/simple_test.dart}"
  CARGO_INCREMENTAL=0 xvfb-run -a flutter test "$target" -d linux
}

_cmake_format_venv_create() {
  antfrastructure_source linux/scripts/01-core/python_uv.sh
  # Empty python version: honour UV_PYTHON, which the CI images export.
  uv_venv_create .venv ""
}

_cmake_format_install_requirements() {
  antfrastructure_source linux/scripts/01-core/python_uv.sh
  local requirements
  requirements="$(antfrastructure_path linux/scripts/cmake-format.requirements.txt)" || return 1
  uv_pip_install_requirements .venv "$requirements"
}

# No strictness switch: wrap it in run_gate. See docs/source/project-operations.md § The CMake format gate
run_cmake_format_check() {
  if [ "$#" -gt 0 ]; then
    echo "Error: run_cmake_format_check takes no arguments (got: $*)." >&2
    echo "       It used to take a strictness flag and IGNORE the verdict when that" >&2
    echo "       flag was false. Wrap the call in run_gate instead of passing one." >&2
    return 2
  fi
  antfrastructure_source linux/scripts/lib/code-quality.sh || return 1

  CODE_QUALITY_VENV_DIR="${PWD}/.venv"
  CODE_QUALITY_UV_VENV_CREATE_SCRIPT=_cmake_format_venv_create
  CODE_QUALITY_UV_INSTALL_REQUIREMENTS_SCRIPT=_cmake_format_install_requirements
  # Bare call: its failures exit via err(), and only run_gate's subshell turns that into a recorded failure.
  code_quality_ensure_cmake_format

  if [[ ! -f .cmake-format.yaml ]]; then
    echo "Error: no .cmake-format.yaml at the repo root; without it cmake-format silently" >&2
    echo "       falls back to its built-in defaults. Restore the consumer copy with" >&2
    echo "       ANTfrastructure shared/config/Sync-SharedConfig.ps1 -Write (AGENTS.md § 5)." >&2
    return 1
  fi

  # shellcheck disable=SC2034  # read by code_quality_find_cmake_files.
  local CODE_QUALITY_CMAKE_EXCLUDE_PATHS=(
    './third_party/*'           # submodules: vendored, formatted by their own repos
    '*/build/*'                 # build output at ANY depth: the root Flutter/cargokit tree
                                # and example builds too, since find walks the working tree
    '*/ephemeral/*'             # Flutter tool rewrites these on every pub get
    '*/.plugin_symlinks/*'      # pub's junction farm into packages/
    '*/.cxx/*'                  # Android Gradle CMake build trees (compiler probes etc.)
    '*/flutter/CMakeLists.txt'  # header: "It should not be edited."
    '*/generated_plugins.cmake' # header: "Generated file, do not edit."
    './rust_builder/cargokit/*' # vendored Cargokit (rust_builder/cargokit/README)
    './.venv/*'                 # the venv this very gate bootstraps
    './.pub-cache/*'            # pub's download cache. fe93f5a moved PUB_CACHE to
                                # <repo>/.pub-cache, so dependency CMake lands in-tree.
  )
  local -a cmake_files
  mapfile -t cmake_files < <(code_quality_find_cmake_files | sort)
  if [[ ${#cmake_files[@]} -eq 0 ]]; then
    echo "Error: the CMake format gate matched no files; the exclude globs are over-broad." >&2
    return 1
  fi

  echo "[Info] cmake-format --check on ${#cmake_files[@]} CMake files."
  # Upstream's runner passes -c only when the config exists; the caller's run_gate records the status.
  code_quality_run_cmake_format --check "${cmake_files[@]}"
}

# AGENTS.md § 4.
setup_compiler_cache() {
  antfrastructure_source linux/scripts/01-core/compiler-cache.sh
  setup_sccache
  echo "[Info] SCCACHE_DIR=${SCCACHE_DIR:-<unset>}  RUSTC_WRAPPER=${RUSTC_WRAPPER:-<unset>}"
}

# The image's clang cfg selects the source-built GCC; verified, as an older image links the distro one (AGENTS.md § 4).
export_toolchain_env() {
  export CC=clang CXX=clang++
  antfrastructure_source linux/scripts/01-core/cross-gcc.sh || return 1
  local want got
  want="$(gcc_toolchain_resolve_prefix)" || {
    echo "[Error] no source-built GCC in this image; clang cannot link the image's libraries." >&2
    return 1
  }
  got="$("$CXX" -v -x c++ /dev/null -fsyntax-only 2>&1 | sed -n 's/^Selected GCC installation: //p')"
  case "$got" in
    "$want"/*) echo "[Info] CC=$CC CXX=$CXX, selecting ${got}" ;;
    *)
      echo "[Error] clang++ selects '${got:-no GCC}', not ${want}: this image predates hub CON16 (the clang cfg)." >&2
      return 1 ;;
  esac
}

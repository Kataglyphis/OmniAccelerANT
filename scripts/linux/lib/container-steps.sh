#!/usr/bin/env bash

_container_steps_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_container_steps_dir}/containerhub.sh"

containerhub_source linux/scripts/01-core/platform.sh
containerhub_source linux/scripts/01-core/logging.sh

# is_truthy plus a bare "y" and mixed case.
maybe_truthy() {
  local value="${1:-}"
  is_truthy "${value,,}" || [[ "${value,,}" == "y" ]]
}

run_check_cmd() {
  local strict_mode="${1:-0}"
  shift
  if maybe_truthy "$strict_mode"; then
    "$@"
  else
    "$@" || true
  fi
}

git_safe_dirs() {
  local flutter_dir="${1:-}"
  git config --global --add safe.directory /workspace || true
  if [[ -n "$flutter_dir" ]]; then
    git config --global --add safe.directory "$flutter_dir" || true
  fi
}

source_bashrc_and_add_flutter_to_path() {
  local flutter_dir="${1:-}"
  local original_flags="$-"
  set +u
  source ~/.bashrc 2>/dev/null || true
  if [[ "$original_flags" =~ u ]]; then set -u; fi
  if [[ -n "$flutter_dir" ]]; then
    export PATH="${flutter_dir}/bin:$PATH"
  fi
}

# The image owns the Flutter SDK; nothing here installs one — AGENTS.md § 3.
assert_flutter_available() {
  local flutter_dir="${1:?flutter_dir is required}"
  if [[ ! -x "${flutter_dir}/bin/flutter" ]]; then
    echo "Error: no Flutter at ${flutter_dir}. The image provides it; this repo" >&2
    echo "       never installs one. Check --flutter-dir and the image tag." >&2
    return 1
  fi
  local version
  version="$(sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "${flutter_dir}/bin/cache/flutter.version.json" 2>/dev/null | head -1)"
  echo "[Info] Flutter ${version:-<unknown>} from the image at ${flutter_dir}."
}
# Lists tracked files rather than walking the tree — AGENTS.md § 3.
run_flutter_common_checks() {
  local strict_mode="${1:-0}" strict_flag
  shift || true
  if maybe_truthy "$strict_mode"; then strict_flag=true; else strict_flag=false; fi
  bash "$(containerhub_path linux/scripts/05-frameworks/flutter/flutter_checks.sh)" --strict "$strict_flag" "$@"
}

# CMake format gate for the hand-maintained native build files. Enumeration and
# exclude-glob handling come from ContainerHub's code-quality.sh; the globs keep
# the gate off generated trees (Flutter's flutter/CMakeLists.txt +
# generated_plugins.cmake + ephemeral, Android's .cxx) and vendored Cargokit —
# the gate must never fight the generator. Windows twin: the "CMake Format
# Verification" step in scripts/windows/Build-Windows.ps1. AGENTS.md § 4.
run_cmake_format_check() {
  local strict_mode="${1:-0}"
  containerhub_source linux/scripts/lib/code-quality.sh

  # cmake-format from PATH if the image ships it, else a uv venv fed by the
  # root requirements.txt — same provisioning the Windows step uses.
  if ! command -v cmake-format >/dev/null 2>&1; then
    containerhub_source linux/scripts/01-core/python_uv.sh
    if ! command -v uv >/dev/null 2>&1; then
      echo "Error: cmake-format is not on PATH and uv is missing, so it cannot be bootstrapped." >&2
      return 1
    fi
    # Empty python version: honour UV_PYTHON, which the CI images export.
    # Only create when absent — uv_venv_create deletes an existing venv.
    if [[ ! -d .venv ]]; then
      uv_venv_create .venv ""
    fi
    uv_pip_install_requirements .venv requirements.txt
    uv_venv_activate .venv
    if ! command -v cmake-format >/dev/null 2>&1; then
      echo "Error: cmake-format still unavailable after installing requirements.txt into .venv." >&2
      return 1
    fi
  fi

  if [[ ! -f .cmake-format.yaml ]]; then
    echo "Error: no .cmake-format.yaml at the repo root; without it cmake-format silently" >&2
    echo "       falls back to its built-in defaults. Restore the consumer copy with" >&2
    echo "       ContainerHub shared/config/Sync-SharedConfig.ps1 -Write (AGENTS.md § 4)." >&2
    return 1
  fi

  # shellcheck disable=SC2034  # read by code_quality_find_cmake_files.
  local CODE_QUALITY_CMAKE_EXCLUDE_PATHS=(
    './third_party/*'           # submodules: vendored, formatted by their own repos
    '*/build/*'                 # build output at ANY depth: the root Flutter/cargokit tree
                                # AND e.g. packages/*/example/build from a local example
                                # build (find walks the working tree, not git ls-files -
                                # no hand-maintained CMake lives under a build/ dir)
    '*/ephemeral/*'             # Flutter tool rewrites these on every pub get
    '*/.plugin_symlinks/*'      # pub's junction farm into packages/
    '*/.cxx/*'                  # Android Gradle CMake build trees (compiler probes etc.)
    '*/flutter/CMakeLists.txt'  # header: "It should not be edited."
    '*/generated_plugins.cmake' # header: "Generated file, do not edit."
    './rust_builder/cargokit/*' # vendored Cargokit (rust_builder/cargokit/README)
    './.venv/*'                 # the venv this very gate bootstraps
  )
  local -a cmake_files
  mapfile -t cmake_files < <(code_quality_find_cmake_files | sort)
  if [[ ${#cmake_files[@]} -eq 0 ]]; then
    echo "Error: the CMake format gate matched no files; the exclude globs are over-broad." >&2
    return 1
  fi

  echo "[Info] cmake-format --check on ${#cmake_files[@]} CMake files."
  run_check_cmd "$strict_mode" cmake-format -c .cmake-format.yaml --check "${cmake_files[@]}"
}

# AGENTS.md § 3.
setup_compiler_cache() {
  containerhub_source linux/scripts/01-core/compiler-cache.sh
  setup_sccache
  echo "[Info] SCCACHE_DIR=${SCCACHE_DIR:-<unset>}  RUSTC_WRAPPER=${RUSTC_WRAPPER:-<unset>}"
}

# The image ships the SDK but announces it nowhere — AGENTS.md § 3.
export_android_gstreamer_env() {
  if [ -n "${GSTREAMER_ROOT_ANDROID:-}" ] && [ -d "${GSTREAMER_ROOT_ANDROID}" ]; then
    return 0
  fi
  local candidate
  for candidate in /opt/android/gstreamer /opt/gstreamer-android; do
    if [ -d "$candidate" ]; then
      export GSTREAMER_ROOT_ANDROID="$candidate"
      echo "[Info] GSTREAMER_ROOT_ANDROID=$candidate"
      return 0
    fi
  done
  echo "[Warn] No Android GStreamer SDK found; the native plugin will not configure." >&2
  return 0
}

# Points clang at the image's source-built GCC. ContainerHub deleted the helper
# that did this; the wrappers it named as the replacement are not in this image
# — AGENTS.md § 3.
export_toolchain_env() {
  local arch="${1:-${MATRIX_ARCH:-amd64}}"
  case "$arch" in x64) arch=amd64 ;; esac

  if [ -x "/usr/local/bin/clang-${arch}" ] && [ -x "/usr/local/bin/clang++-${arch}" ]; then
    export CC="/usr/local/bin/clang-${arch}" CXX="/usr/local/bin/clang++-${arch}"
    echo "[Info] CC=$CC (wrapper, --gcc-toolchain baked in)"
    return 0
  fi

  export CC=clang CXX=clang++
  containerhub_source linux/scripts/01-core/cross-gcc.sh || return 1
  local root
  root="$(gcc_toolchain_prefix)"
  if [ ! -d "$root" ]; then
    echo "[Warn] no GCC toolchain at ${root}; clang falls back to its own discovery." >&2
    return 0
  fi
  export CFLAGS="--gcc-toolchain=${root} ${CFLAGS:-}"
  export CXXFLAGS="--gcc-toolchain=${root} ${CXXFLAGS:-}"
  local lib=""
  [ -d "$root/lib64" ] && lib="$root/lib64" || { [ -d "$root/lib" ] && lib="$root/lib"; }
  if [ -n "$lib" ]; then
    export LDFLAGS="-L${lib} -Wl,-rpath,${lib} --gcc-toolchain=${root} ${LDFLAGS:-}"
  else
    export LDFLAGS="--gcc-toolchain=${root} ${LDFLAGS:-}"
  fi
  echo "[Info] CC=$CC --gcc-toolchain=${root}"
}

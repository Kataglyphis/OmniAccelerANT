#!/usr/bin/env bash

_container_steps_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_container_steps_dir}/containerhub.sh"

containerhub_source linux/scripts/01-core/platform.sh
containerhub_source linux/scripts/01-core/logging.sh
# gate_reset / run_gate / gate_skip / assert_gates. Sourced HERE rather than in
# each driver because every driver that runs a check already sources this file,
# and the batch itself is built by the driver - never by a helper below, which
# would silently reset a batch its caller had opened.
containerhub_source linux/scripts/01-core/gates.sh

# is_truthy plus a bare "y" and mixed case.
maybe_truthy() {
  local value="${1:-}"
  is_truthy "${value,,}" || [[ "${value,,}" == "y" ]]
}

# run_check_cmd IS GONE (2026-09-09). It was:
#
#   if maybe_truthy "$strict_mode"; then "$@"; else "$@" || true; fi
#
# and the second arm did not "report and move on" - it destroyed the result.
# No name, no exit status, no record: a caller could not tell a pass from a
# failure afterwards, and neither could CI, whose only input is the exit code.
# fc8b65c had already found the one gate it covered ("ran, printed, and could
# never fail CI") and worked around it by flipping the workflow flags; this
# removes the mechanism instead. Its two call sites went two different ways,
# because they were never the same kind of thing:
#
#   * `flutter config --enable-android` is a STEP, not a check. It is now a bare
#     call, like `flutter config --enable-web` in ci-container-run-web-linux.sh
#     and `flutter config --enable-android` in run-android.sh, which were never
#     wrapped. A config command that fails and is ignored just moves the failure
#     into the build that follows it.
#   * the cmake-format check is a GATE, and now runs as one - see
#     run_cmake_format_check below and the run_gate batches in its two callers.

# No `|| true` on either line any more, for the reason the web lane already
# records above its `cargo install`: the failure only resurfaced later, wearing
# somebody else's name. `git config --global --add` fails when the global config
# cannot be written at all (unset or read-only HOME) — and in exactly that state
# this function has NOT registered the safe directory, so the next git command
# against /workspace dies with "detected dubious ownership", including the
# `git ls-files` that upstream's flutter_checks.sh builds its file list from.
git_safe_dirs() {
  local flutter_dir="${1:-}" dir
  local -a dirs=(/workspace)
  if [[ -n "$flutter_dir" ]]; then
    dirs+=("$flutter_dir")
  fi
  for dir in "${dirs[@]}"; do
    if ! git config --global --add safe.directory "$dir"; then
      echo "Error: could not record '$dir' as a git safe.directory." >&2
      echo "       git could not write the global config (HOME=${HOME:-<unset>})." >&2
      echo "       Every later git call against that tree would fail as 'dubious ownership'." >&2
      return 1
    fi
  done
}

source_bashrc_and_add_flutter_to_path() {
  local flutter_dir="${1:-}"
  local original_flags="$-"
  set +u
  # The one `|| true` in this file that is KEPT, and it is not a suppressed
  # gate: a stock Ubuntu ~/.bashrc `return`s early in a non-interactive shell
  # and the status it returns is whatever ran last, so non-zero here carries no
  # meaning. `2>/dev/null` is gone, though — that part hid the diagnostics of a
  # genuinely broken rc file, and the PATH this sets up is what the whole lane
  # then runs flutter from. Absence is handled by the -f test, not by silence.
  if [[ -f ~/.bashrc ]]; then
    source ~/.bashrc || true
  fi
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
#
# The driver resolution is a statement of its own, not a substitution inside the
# command line: this function is called from inside run_gate, i.e. from a `||`
# list, where `set -e` does NOT abort. A failing containerhub_path there left an
# EMPTY first argument behind and ran `bash "" --strict false`, so a missing
# upstream file reported as bash's own "No such file or directory" instead of
# the path-and-fix message containerhub_path prints.
run_flutter_common_checks() {
  local strict_mode="${1:-0}" strict_flag checks
  shift || true
  if maybe_truthy "$strict_mode"; then strict_flag=true; else strict_flag=false; fi
  checks="$(containerhub_path linux/scripts/05-frameworks/flutter/flutter_checks.sh)" || return 1
  bash "$checks" --strict "$strict_flag" "$@"
}

_cmake_format_venv_create() {
  containerhub_source linux/scripts/01-core/python_uv.sh
  # Empty python version: honour UV_PYTHON, which the CI images export.
  uv_venv_create .venv ""
}

_cmake_format_install_requirements() {
  containerhub_source linux/scripts/01-core/python_uv.sh
  local requirements
  requirements="$(containerhub_path linux/scripts/cmake-format.requirements.txt)" || return 1
  uv_pip_install_requirements .venv "$requirements"
}

# CMake format gate for the hand-maintained native build files. Enumeration and
# exclude-glob handling come from ContainerHub's code-quality.sh; the globs keep
# the gate off generated trees (Flutter's flutter/CMakeLists.txt +
# generated_plugins.cmake + ephemeral, Android's .cxx) and vendored Cargokit —
# the gate must never fight the generator. Windows twin: the "CMake Format
# Verification" step in scripts/windows/Build-Windows.ps1. AGENTS.md § 4.
#
# NO STRICTNESS SWITCH ANY MORE, and this is a behaviour change: the check used
# to run through run_check_cmd, so a non-strict caller (the Android lane, and
# any local `run-native-linux.sh` without --strict-checks) ran it and threw the
# verdict away. What survives of that switch is what it was actually for: the
# Dart checks still take --strict, because that flag belongs to upstream's
# flutter_checks.sh and MEANS something there.
# Measured before flipping, the same way fc8b65c measured it: the gate's 13
# files are clean under this repo's .cmake-format.yaml, and the native-Linux
# lane has passed --strict-checks true since fc8b65c - so any drift this now
# catches on the Android lane is drift that already blocks the merge on the
# native lane. AGENTS.md § "The Linux checks stage" now says the same.
run_cmake_format_check() {
  if [ "$#" -gt 0 ]; then
    echo "Error: run_cmake_format_check takes no arguments (got: $*)." >&2
    echo "       It used to take a strictness flag and IGNORE the verdict when that" >&2
    echo "       flag was false. Wrap the call in run_gate instead of passing one." >&2
    return 2
  fi
  containerhub_source linux/scripts/lib/code-quality.sh || return 1

  # cmake-format from PATH if the image ships it, else a uv venv fed by
  # ContainerHub's pinned bootstrap set — same provisioning the Windows step
  # uses. This repo carries no root requirements.txt: the pins (cmake-format
  # plus the pyyaml it cannot read .cmake-format.yaml without) live upstream in
  # linux/scripts/cmake-format.requirements.txt, so both platforms and every
  # consumer repo install the same versions. docs/source/project-operations.md.
  #
  # The bootstrap itself is upstream's code_quality_ensure_cmake_format, not a
  # local copy of it. The two knobs below are FUNCTION names, exactly as
  # ContainerHub's own preflight.sh sets them. What the hand-rolled version this
  # replaces did NOT do, and what adopting buys: a `.venv` created on the other
  # platform (Scripts/python.exe in this bind-mounted tree, or bin/python on the
  # Windows host) was reused by an `[[ ! -d .venv ]]` guard and then died inside
  # uv with "Exec format error"; upstream probes the interpreter and recreates
  # it. It also finds Scripts/activate as well as bin/activate.
  CODE_QUALITY_VENV_DIR="${PWD}/.venv"
  CODE_QUALITY_UV_VENV_CREATE_SCRIPT=_cmake_format_venv_create
  CODE_QUALITY_UV_INSTALL_REQUIREMENTS_SCRIPT=_cmake_format_install_requirements
  # Bare call, and no `|| return 1`: upstream's bootstrap has no non-zero RETURN
  # path to guard. Every failure inside it is err() (01-core/logging.sh), which
  # is `exit 1` - so the guard that used to stand here was unreachable, and the
  # fall-through to the .cmake-format.yaml check that its comment described
  # could not happen.
  #
  # That exit is only a RECORDED gate failure, rather than a dead driver, if
  # run_gate runs its command in a subshell. That is a REQUIREMENT this file
  # places on ContainerHub, not something the pin necessarily satisfies: it was
  # added upstream on 2026-09-09 and reaches this repo only when the gitlink is
  # bumped. Under an older pin the batch still exits non-zero (no false green),
  # but it dies here and every finding already recorded is lost, so one push
  # names one failure instead of all of them.
  # third_party/ContainerHub/docs/shared-script-libraries.md#gate-aggregation-01-coregatessh
  code_quality_ensure_cmake_format

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
  # Upstream's runner, not a bare `cmake-format` line: it is the same one that
  # grades ContainerHub's own tree, and it is what makes the -c flag conditional
  # on the config actually existing instead of passing a path that may not.
  # Its exit status is this function's exit status - the caller's run_gate is
  # what records it, and that caller's assert_gates is what raises it.
  code_quality_run_cmake_format --check "${cmake_files[@]}"
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

#!/usr/bin/env bash
# The amd64 packages' x86-64-v3 floor for this app's own clang and Rust code; sourced, sets no shell options. See docs/source/camera-streaming.md § The amd64 CPU floor

OMNI_AMD64_MARCH='-march=x86-64-v3'
OMNI_AMD64_RUST_CPU='-C target-cpu=x86-64-v3'

_omni_is_amd64() {
  case "${1:?arch required}" in
    x64|x86_64|amd64) return 0 ;;
    *) return 1 ;;
  esac
}

# _omni_with_flag <current> <flag>: prints current with flag appended once.
_omni_with_flag() {
  case " $1 " in
    *" $2 "*) printf '%s' "$1" ;;
    *) printf '%s' "${1:+$1 }$2" ;;
  esac
}

# omni_export_cpu_floor <arch>: on amd64, exports the floor to clang and to cargo's x86_64 target; other arches keep theirs.
omni_export_cpu_floor() {
  _omni_is_amd64 "$1" || return 0
  # Cargo lets either of these replace the target-scoped flags, which would drop the floor without a word.
  if [[ -n "${RUSTFLAGS:-}" || -n "${CARGO_ENCODED_RUSTFLAGS:-}" ]]; then
    printf 'cpu floor: RUSTFLAGS or CARGO_ENCODED_RUSTFLAGS is set and would override %s\n' "${OMNI_AMD64_RUST_CPU}" >&2
    return 1
  fi
  CFLAGS="$(_omni_with_flag "${CFLAGS:-}" "${OMNI_AMD64_MARCH}")"
  CXXFLAGS="$(_omni_with_flag "${CXXFLAGS:-}" "${OMNI_AMD64_MARCH}")"
  # Target-scoped, so the wasm32 build and a cross target keep their own flags.
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="$(_omni_with_flag "${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS:-}" "${OMNI_AMD64_RUST_CPU}")"
  export CFLAGS CXXFLAGS CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS
}

# omni_check_cpu_floor <cmake-build-dir>: fails unless the configure that built the runner and plugins took the floor.
omni_check_cpu_floor() {
  local cache="${1:?build directory required}/CMakeCache.txt" var line
  [[ -f "${cache}" ]] || { printf 'cpu floor: no %s\n' "${cache}" >&2; return 1; }
  for var in CMAKE_C_FLAGS CMAKE_CXX_FLAGS; do
    line="$(grep -e "^${var}:STRING=" "${cache}" || true)"
    case " ${line#*=} " in
      *" ${OMNI_AMD64_MARCH} "*) ;;
      *) printf 'cpu floor: %s in %s is "%s", without %s\n' "${var}" "${cache}" "${line#*=}" "${OMNI_AMD64_MARCH}" >&2
         return 1 ;;
    esac
  done
  printf 'cpu floor: CMAKE_C_FLAGS and CMAKE_CXX_FLAGS carry %s\n' "${OMNI_AMD64_MARCH}"
}

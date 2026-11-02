#!/usr/bin/env bash
# Stubs and refusal checks for suites that stop at their first failure; they prove test wiring, not the real tools.

# fixture_root: the checkout this suite belongs to, from wherever it was started.
fixture_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || return 1
  pwd
}

# fixture_workdir: sets and exports work, removed when the suite exits however it ends.
fixture_workdir() {
  work="$(mktemp -d)"
  export work
  trap 'rm -rf -- "$work"' EXIT
}

# fixture_xvfb_workdir: a workdir whose bin/ already holds the xvfb stub, for suites that start a display-needing app.
fixture_xvfb_workdir() {
  fixture_workdir
  mkdir -p "$work/bin"
  fixture_xvfb_stub "$work/bin"
}

# fixture_stub <path> <<'BODY': a strict Bash executable, so a stub cannot pass by ignoring its own failing check.
fixture_stub() {
  { printf '#!/usr/bin/env bash\nset -euo pipefail\n'; cat; } > "$1"
  chmod +x "$1"
}

# fixture_xvfb_stub <bin-dir>: runs the command directly, because the checks under test need no display here.
fixture_xvfb_stub() {
  cat > "$1/xvfb-run" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -a ]] && shift
exec "$@"
STUB
  chmod +x "$1/xvfb-run"
}

# fixture_refuses <message> <command>...: stops the suite with message when the command unexpectedly succeeds.
fixture_refuses() {
  local message="$1"
  shift
  if "$@"; then
    echo "$message" >&2
    exit 1
  fi
}

# fixture_refuses_quiet <message> <command>...: as fixture_refuses, for a command whose own refusal is expected noise.
fixture_refuses_quiet() {
  local message="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "$message" >&2
    exit 1
  fi
}

# fixture_refuses_logged <log> <needle> <message> <command>...: as fixture_refuses, and the refusal must say needle.
fixture_refuses_logged() {
  local log="$1" needle="$2" message="$3"
  shift 3
  if "$@" > "$log" 2>&1; then
    echo "$message" >&2
    exit 1
  fi
  grep -Fq "$needle" "$log"
}

# fixture_real_provider_dir: the operator-supplied runtime directory for a real-provider run, after validating its provider.
fixture_real_provider_dir() {
  case "$ORT_TEST_REAL_PROVIDER" in cuda|migraphx) ;; *) echo 'Invalid real provider' >&2; exit 2 ;; esac
  printf '%s\n' "${ORT_TEST_REAL_DIR:?ORT_TEST_REAL_DIR is required}"
}

# fixture_write_models <dir>: the detector's three locked files, with placeholder bytes.
fixture_write_models() {
  local name
  for name in fixture_detector.onnx fixture_detector.LICENSE fixture_detector.NOTICE; do
    printf 'fixture %s\n' "$name" > "$1/$name"
  done
}

# fixture_lock_models <dir> <lock>: appends a models.lock row per file, so a later byte change fails verification.
fixture_lock_models() {
  local file
  for file in "$1"/fixture_detector.onnx "$1"/fixture_detector.LICENSE "$1"/fixture_detector.NOTICE; do
    printf '%s  %s  https://example.invalid/%s\n' "$(sha256sum "$file" | cut -d ' ' -f1)" "${file##*/}" "${file##*/}" >> "$2"
  done
}

# fixture_gpu_launcher <path>: an external-runtime launcher with both loader branches, which the host-runtime gate looks for.
fixture_gpu_launcher() {
  cat > "$1" <<'EOF_LAUNCHER'
#!/bin/bash
external_library_path=""
export LD_LIBRARY_PATH="$here/lib${external_library_path}"
exec "$here/loader" --library-path "$here/lib/glibc:$here/lib${external_library_path}" "$@"
EOF_LAUNCHER
  chmod +x "$1"
}

# fixture_make_apk <out> <member[=file]>...: a zip of those members; a member without a file holds one zero byte.
fixture_make_apk() {
  local out="$1"
  shift
  python3 - "$out" "$@" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for spec in sys.argv[2:]:
        member, _, path = spec.partition("=")
        if path:
            z.write(path, member)
        else:
            z.writestr(member, b"\0")
PY
}

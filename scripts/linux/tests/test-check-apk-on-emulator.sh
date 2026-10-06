#!/usr/bin/env bash
# The emulator gate against stub adb/android-avd.sh: one green run, and each way it must go red.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="${SCRIPT_DIR}/../check-apk-on-emulator.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
pkg="org.example.app"
printf 'apk' > "${work}/app.apk"

mkdir -p "${work}/bin"
# Answers like a booted emulator; STUB_* pick the device's state, and every call is logged.
cat > "${work}/bin/adb" <<'EOF'
#!/usr/bin/env bash
printf 'adb %s\n' "$*" >> "${STUB_CALLS}"
[ "$1" = -s ] && shift 2
case "$1 ${2:-}" in
  "install "*) exit 0 ;;
  "logcat -c") exit 0 ;;
  "logcat -d") printf '%b' "${STUB_LOGCAT:-}" ;;
  "shell dumpsys") printf '  primaryCpuAbi=%s\n' "${STUB_ABI}" ;;
  "shell cmd") printf 'priority=0 preferredOrder=0\n%s\n' "${STUB_ACTIVITY}" ;;
  "shell am") exit 0 ;;
  "shell pidof") [ -n "${STUB_PID}" ] && printf '%s\n' "${STUB_PID}" ;;
  *) printf 'stub adb: unexpected %s\n' "$*" >&2; exit 3 ;;
esac
EOF
cat > "${work}/bin/android-avd.sh" <<'EOF'
#!/usr/bin/env bash
printf 'avd %s\n' "$1" >> "${STUB_CALLS}"
[ "$1" = start ] && exit "${STUB_BOOT_RC:-0}"
exit 0
EOF
chmod +x "${work}/bin/adb" "${work}/bin/android-avd.sh"
export PATH="${work}/bin:${PATH}" STUB_CALLS="${work}/calls"

passed=0
# expect pass|fail NAME [VAR=value ...]: the defaults are a healthy device, each case overrides one thing.
expect() {
  local want="$1" name="$2" got=0
  shift 2
  : > "${STUB_CALLS}"
  env STUB_ABI=arm64-v8a STUB_ACTIVITY="${pkg}/.MainActivity" STUB_PID=4242 STUB_LOGCAT='' "$@" \
    bash "$gate" --apk "${work}/app.apk" --package "$pkg" --seconds 0 >/dev/null 2>&1 || got=$?
  if [ "$want" = pass ] && [ "$got" -ne 0 ]; then
    printf 'FAIL %s: the gate refused a healthy run (exit %s)\n' "$name" "$got" >&2
    return 1
  fi
  if [ "$want" = fail ] && [ "$got" -ne 1 ]; then
    printf 'FAIL %s: want exit 1, got %s\n' "$name" "$got" >&2
    return 1
  fi
  # Every path that started the AVD must stop it, or the next lane step inherits a running emulator.
  if grep -q '^avd start' "${STUB_CALLS}" && ! grep -q '^avd stop' "${STUB_CALLS}"; then
    printf 'FAIL %s: the AVD was left running\n' "$name" >&2
    return 1
  fi
  passed=$((passed + 1))
  printf 'ok   %s\n' "$name"
}

expect pass "the app stays up as arm64-v8a"
expect pass "another process's fatal signal is not the app's" \
  STUB_LOGCAT='F libc    : Fatal signal 11 (SIGSEGV) in tid 77 (surfaceflinger), pid 77 (surfaceflinger)\n'
expect fail "the app is gone after the wait" STUB_PID=
expect fail "the app crashed in Java while a pid lingers" \
  STUB_LOGCAT="E AndroidRuntime: FATAL EXCEPTION: main\nE AndroidRuntime: Process: ${pkg}, PID: 4242\n"
expect fail "the app took a fatal signal" \
  STUB_LOGCAT='F libc    : Fatal signal 4 (SIGILL), code 1 in tid 4250 (1.ui), pid 4242 (example.app)\n'
expect fail "the arm64 translator met an unknown instruction" \
  STUB_LOGCAT='E ndk_translation: Undefined instruction 0x7ee1b800\n'
expect fail "installed as x86_64" STUB_ABI=x86_64
expect fail "no launcher activity" STUB_ACTIVITY='No activity found'
expect fail "the emulator does not boot" STUB_BOOT_RC=1

got=0
bash "$gate" --apk "${work}/app.apk" >/dev/null 2>&1 || got=$?
[ "$got" -eq 2 ] || { printf 'FAIL --package missing: want exit 2, got %s\n' "$got" >&2; exit 1; }
passed=$((passed + 1))
printf 'ok   --package missing is a usage error\n'

got=0
bash "$gate" --apk "${work}/app.apk" --package "${pkg}"$'\r' >/dev/null 2>&1 || got=$?
[ "$got" -eq 2 ] || { printf 'FAIL a CR in --package: want exit 2, got %s\n' "$got" >&2; exit 1; }
passed=$((passed + 1))
printf 'ok   a CR in --package is a usage error\n'

printf '  %d assertion(s) passed\n' "$passed"

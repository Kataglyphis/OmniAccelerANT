#!/usr/bin/env bash
# The emulator gate against stub adb/android-avd.sh: one green run, and each way it must go red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
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

# emulator [VAR=value ...]: the gate's rc on a healthy device, each VAR overriding one thing; 99 when the AVD was left running.
emulator() {
  local rc=0
  : > "${STUB_CALLS}"
  env STUB_ABI=arm64-v8a STUB_ACTIVITY="${pkg}/.MainActivity" STUB_PID=4242 STUB_LOGCAT='' "$@" \
    bash "$gate" --apk "${work}/app.apk" --package "$pkg" --seconds 0 || rc=$?
  # Every path that started the AVD must stop it, or the next lane step inherits a running emulator.
  if grep -q '^avd start' "${STUB_CALLS}" && ! grep -q '^avd stop' "${STUB_CALLS}"; then
    printf 'the AVD was left running\n'
    return 99
  fi
  return "${rc}"
}

t_case "the app stays up as arm64-v8a"
t_assert_rc 0 emulator
t_case "another process's fatal signal is not the app's"
t_assert_rc 0 emulator STUB_LOGCAT='F libc    : Fatal signal 11 (SIGSEGV) in tid 77 (surfaceflinger), pid 77 (surfaceflinger)\n'
t_case "the app is gone after the wait"
t_assert_rc 1 emulator STUB_PID=
t_case "the app crashed in Java while a pid lingers"
t_assert_rc 1 emulator STUB_LOGCAT="E AndroidRuntime: FATAL EXCEPTION: main\nE AndroidRuntime: Process: ${pkg}, PID: 4242\n"
t_case "the app took a fatal signal"
t_assert_rc 1 emulator STUB_LOGCAT='F libc    : Fatal signal 4 (SIGILL), code 1 in tid 4250 (1.ui), pid 4242 (example.app)\n'
t_case "the arm64 translator met an unknown instruction"
t_assert_rc 1 emulator STUB_LOGCAT='E ndk_translation: Undefined instruction 0x7ee1b800\n'
t_case "installed as x86_64"
t_assert_rc 1 emulator STUB_ABI=x86_64
t_case "no launcher activity"
t_assert_rc 1 emulator STUB_ACTIVITY='No activity found'
t_case "the emulator does not boot"
t_assert_rc 1 emulator STUB_BOOT_RC=1

t_case "--package missing is a usage error"
t_assert_rc 2 bash "$gate" --apk "${work}/app.apk"
t_case "a CR in --package is a usage error"
t_assert_rc 2 bash "$gate" --apk "${work}/app.apk" --package "${pkg}"$'\r'

t_summary

#!/usr/bin/env bash
# The ABI gate proves what the APK holds, not that it runs: boot the image's AVD, launch the app, require it to stay up.
set -euo pipefail

apk=""
package=""
seconds=20
while [ $# -gt 0 ]; do
  case "$1" in
    --apk) apk="${2:?--apk needs a path}"; shift 2 ;;
    --package) package="${2:?--package needs an application id}"; shift 2 ;;
    --seconds) seconds="${2:?--seconds needs a number}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s --apk FILE --package APPLICATION_ID [--seconds N]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$apk" ] || [ -z "$package" ]; then
  printf 'Error: --apk and --package are required\n' >&2
  exit 2
fi
# A CRLF checkout once handed in "id\r", which every adb query then silently missed.
case "$package" in
  *[!A-Za-z0-9_.]*)
    printf 'Error: --package %q is not an application id\n' "$package" >&2
    exit 2
    ;;
esac
if [ ! -f "$apk" ]; then
  printf 'Error: no APK at %s\n' "$apk" >&2
  exit 1
fi

adb="$(command -v adb || printf '%s/platform-tools/adb' "${ANDROID_HOME:?ANDROID_HOME is not set}")"
serial="emulator-${AVD_PORT:-5554}"
logcat="$(mktemp)"
fail() {
  printf 'FAIL %s\n' "$1" >&2
  return 1
}
cleanup() {
  android-avd.sh stop >/dev/null 2>&1 || true
  rm -f "$logcat"
}
trap cleanup EXIT

android-avd.sh start
"$adb" -s "$serial" install -r --abi arm64-v8a "$apk"

# The device lists x86_64 first: without --abi an x86_64 slice would win, and the plugin exists for arm64 only.
abi="$("$adb" -s "$serial" shell dumpsys package "$package" | tr -d '\r' | sed -n 's/.*primaryCpuAbi=\([^ ]*\).*/\1/p' | head -n 1)"
[ "$abi" = "arm64-v8a" ] || fail "$package installed as '${abi:-nothing}', not arm64-v8a"

activity="$("$adb" -s "$serial" shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$package" | tr -d '\r' | tail -n 1)"
case "$activity" in
  */*) ;;
  *) fail "$package has no launcher activity (resolve-activity said '${activity}')" ;;
esac

"$adb" -s "$serial" logcat -c
"$adb" -s "$serial" shell am start -W -n "$activity"
sleep "$seconds"
pid="$("$adb" -s "$serial" shell pidof "$package" | tr -d '\r' || true)"
"$adb" -s "$serial" logcat -d > "$logcat"

# Only the app's own crashes count: a system process may die on a fresh emulator without it being ours.
crash_pattern="Process: ${package}|ANR in ${package}|ndk_translation: Undefined instruction"
[ -z "$pid" ] || crash_pattern="${crash_pattern}|Fatal signal .* pid ${pid} "
crashes="$(grep -E -B2 "$crash_pattern" "$logcat" || true)"
if [ -z "$pid" ] || [ -n "$crashes" ]; then
  printf '%s\n' "$crashes" >&2
  printf -- '--- logcat, last 40 lines\n' >&2
  tail -n 40 "$logcat" >&2
  fail "$package did not stay up ${seconds}s on ${serial} (pid '${pid}')"
fi
# threadtime format: the third field is the pid.
printf 'OK %s stayed up %ss on %s as arm64-v8a (pid %s, %s logcat line(s) of its own)\n' \
  "$package" "$seconds" "$serial" "$pid" "$(awk -v p="$pid" '$3 == p' "$logcat" | wc -l)"

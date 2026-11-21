#!/usr/bin/env bash
# The ABI gate proves what the APK holds; this proves it runs on the image's AVD, plugin and GStreamer included.
set -euo pipefail

apk=""
package=""
seconds=20
# shellcheck source=scripts/linux/lib/entry-options.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/entry-options.sh"
parse_entry_options '--apk FILE --package APPLICATION_ID [--seconds N]' '' \
  '--apk=apk:a path' '--package=package:an application id' '--seconds=seconds:a number' -- "$@"

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
logcat_pid=""
fail() {
  printf 'FAIL %s\n' "$1" >&2
  return 1
}
cleanup() {
  [ -z "$logcat_pid" ] || kill "$logcat_pid" 2>/dev/null || true
  android-avd.sh stop >/dev/null 2>&1 || true
  rm -f "$logcat"
}
trap cleanup EXIT

android-avd.sh start
# -g grants the camera, so the Stream page's start runs the plugin's create, its JNI and gst_init.
"$adb" -s "$serial" install -r -g --abi arm64-v8a "$apk"

# The device lists x86_64 first: without --abi an x86_64 slice would win, and the plugin exists for arm64 only.
abi="$("$adb" -s "$serial" shell dumpsys package "$package" | tr -d '\r' | sed -n 's/.*primaryCpuAbi=\([^ ]*\).*/\1/p' | head -n 1)"
[ "$abi" = "arm64-v8a" ] || fail "$package installed as '${abi:-nothing}', not arm64-v8a"

activity="$("$adb" -s "$serial" shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$package" | tr -d '\r' | tail -n 1)"
case "$activity" in
  */*) ;;
  *) fail "$package has no launcher activity (resolve-activity said '${activity}')" ;;
esac

"$adb" -s "$serial" logcat -c
# Streamed from the start: a fresh emulator's ring buffer had dropped the plugin's first lines by the end (run 44813920781).
"$adb" -s "$serial" logcat -v threadtime > "$logcat" 2>/dev/null &
logcat_pid=$!
"$adb" -s "$serial" shell am start -W -n "$activity"
sleep "$seconds"
pid="$("$adb" -s "$serial" shell pidof "$package" | tr -d '\r' || true)"
# A second for adb to hand over its last lines before the stream ends.
sleep 1
kill "$logcat_pid" 2>/dev/null || true
wait "$logcat_pid" 2>/dev/null || true
logcat_pid=""

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
# An APK whose library cannot load, or whose create fails, stays up too: the plugin's own lines decide.
plugin_faults="$(grep -E 'Create failed|UnsatisfiedLinkError' "$logcat" || true)"
# A bus error the source chain recovers from is the chain at work (run 44842086289); one no later PLAYING follows is a fault.
last_bus_error="$(grep -n 'bus error' "$logcat" | tail -n 1 | cut -d: -f1)" || true
# awk, not sed | grep -q: under pipefail grep's early exit leaves sed a SIGPIPE on a long log (run 44901902135).
if [ -n "$last_bus_error" ] && ! awk -v from="$last_bus_error" 'NR > from && /play set_state\(PLAYING\): SUCCESS/ { found = 1 } END { exit !found }' "$logcat"; then
  plugin_faults="${plugin_faults}${plugin_faults:+$'\n'}$(grep 'bus error' "$logcat")"
fi
plugin_problem=""
grep -q 'GStreamer initialized' "$logcat" || plugin_problem="no 'GStreamer initialized': create, the JNI or gst_init did not run"
if [ -z "$plugin_problem" ] && [ -n "$plugin_faults" ]; then plugin_problem="a fault in the plugin's lines above"; fi
if [ -n "$plugin_problem" ]; then
  printf '%s\n' "$plugin_faults" >&2
  printf -- '--- logcat, the plugin'"'"'s last 40 lines\n' >&2
  grep -E 'KataglyphisGStreamer|GStreamer' "$logcat" | tail -n 40 >&2
  fail "$package's plugin on ${serial}: ${plugin_problem}"
fi
# threadtime format: the third field is the pid.
printf 'OK %s stayed up %ss on %s as arm64-v8a (pid %s, %s logcat line(s) of its own)\n' \
  "$package" "$seconds" "$serial" "$pid" "$(awk -v p="$pid" '$3 == p' "$logcat" | wc -l)"

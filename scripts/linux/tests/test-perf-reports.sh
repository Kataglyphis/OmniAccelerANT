#!/usr/bin/env bash
# The frontend performance scripts on synthetic input: the CI report's table and warnings, and the trace summary's self times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
report="${SCRIPT_DIR}/../frontend-perf-report.py"
summary="${SCRIPT_DIR}/../flutter-trace-summary.py"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

passed=0
# check <name> <output file> <grep -E pattern> [absent]: the output holds the pattern, or with "absent" does not.
check() {
  local name="$1" file="$2" pattern="$3" mode="${4:-present}"
  if [ "$mode" = absent ] && grep -qE -- "$pattern" "$file"; then
    printf 'FAIL %s: unexpected /%s/ in\n' "$name" "$pattern" >&2
    sed 's/^/  | /' "$file" >&2
    return 1
  fi
  if [ "$mode" = present ] && ! grep -qE -- "$pattern" "$file"; then
    printf 'FAIL %s: no /%s/ in\n' "$name" "$pattern" >&2
    sed 's/^/  | /' "$file" >&2
    return 1
  fi
  passed=$((passed + 1))
  printf 'ok   %s\n' "$name"
}

# timings <file> <start build avg ms> <start build worst ms>: a frontend.json with one scenario.
timings() {
  printf '{"start":{"frame_count":3,"average_frame_build_time_millis":%s,"90th_percentile_frame_build_time_millis":6.0,"worst_frame_build_time_millis":%s,"missed_frame_build_budget_count":1,"old_gen_gc_count":0}}\n' "$2" "$3" > "$1"
}

timings "${work}/base.json" 10.0 20.0
timings "${work}/slower.json" 14.0 21.0
timings "${work}/same.json" 11.0 20.0

python3 "$report" "${work}/slower.json" "${work}/base.json" 0.25 > "${work}/out" 2> "${work}/err"
check "the table compares each value" "${work}/out" '^\| `start` \| 3 \| 14\.0 \(\+40 %\) \| 6\.0 \(\+0 %\) \| 21\.0 \(\+5 %\) \| 1 \| 0 \|$'
check "a slowdown over the threshold warns" "${work}/err" '^::warning title=Frontend slower::start build avg ms \+40 %'
check "a slowdown under the threshold does not" "${work}/err" 'build worst ms' absent

python3 "$report" "${work}/same.json" "${work}/base.json" 0.25 > "${work}/out" 2> "${work}/err"
check "within the threshold, no warning at all" "${work}/err" 'warning' absent

python3 "$report" "${work}/slower.json" "${work}/missing.json" > "${work}/out" 2> "${work}/err"
check "no baseline: plain values" "${work}/out" '^\| `start` \| 3 \| 14\.0 \| 6\.0 \| 21\.0 \| 1 \| 0 \|$'

python3 "$report" "${work}/missing.json" > "${work}/out"
check "no timings: says so" "${work}/out" '^No frame timings found\.$'

# Two UI frames; the slow one holds a 900 ms widget build and a zero-length span, whose B and E share a timestamp.
cat > "${work}/trace.json" <<'EOF'
{"traceEvents": [
  {"ph": "B", "name": "Animator::BeginFrame", "ts": 1000, "pid": 1, "tid": 7},
  {"ph": "B", "name": "BUILD", "ts": 1000, "pid": 1, "tid": 7},
  {"ph": "B", "name": "SlowPage", "ts": 1100, "pid": 1, "tid": 7},
  {"ph": "B", "name": "Dart_NewInteger", "ts": 1100, "pid": 1, "tid": 7},
  {"ph": "E", "ts": 1100, "pid": 1, "tid": 7},
  {"ph": "E", "ts": 901100, "pid": 1, "tid": 7},
  {"ph": "E", "ts": 950000, "pid": 1, "tid": 7},
  {"ph": "X", "name": "LAYOUT", "ts": 950000, "dur": 30000, "pid": 1, "tid": 7},
  {"ph": "E", "ts": 1000000, "pid": 1, "tid": 7},
  {"ph": "X", "name": "GPURasterizer::Draw", "ts": 1000000, "dur": 2000000, "pid": 1, "tid": 9},
  {"ph": "B", "name": "Animator::BeginFrame", "ts": 3100000, "pid": 1, "tid": 7},
  {"ph": "E", "ts": 3104000, "pid": 1, "tid": 7}
]}
EOF
python3 "$summary" "${work}/trace.json" --top 5 > "${work}/out"
check "both UI frames, the slow one first" "${work}/out" '^Slowest UI frames \(2 in the timeline\):'
check "the slow frame's length" "${work}/out" '^  at +0\.0 ms +999\.0 ms$'
check "the raster frame" "${work}/out" '^  at +999\.0 ms +2000\.0 ms$'
check "the widget's own time leads" "${work}/out" '^ +900\.0 ms  SlowPage$'
check "its parent's time is net of it" "${work}/out" '^ +49\.0 ms  BUILD$'
check "the frame keeps what no child took" "${work}/out" '^ +20\.0 ms  Animator::BeginFrame$'
check "the zero-length span closes only itself" "${work}/out" '^ +0\.0 ms  Dart_NewInteger$'
check "X events count as spans" "${work}/out" '^ +30\.0 ms  LAYOUT$'

printf '{"traceEvents": []}\n' > "${work}/empty.json"
rc=0
python3 "$summary" "${work}/empty.json" > "${work}/out" || rc=$?
printf '%s\n' "rc=${rc}" >> "${work}/out"
check "an empty timeline fails" "${work}/out" '^rc=1$'

printf '  %d assertion(s) passed\n' "$passed"

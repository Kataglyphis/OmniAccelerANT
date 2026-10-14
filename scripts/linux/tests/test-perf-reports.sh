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

# report <current> <history> -> rc in ${work}/rc, table in ${work}/out, annotations in ${work}/err.
report() {
  local rc=0
  python3 "$report" "$@" > "${work}/out" 2> "${work}/err" || rc=$?
  printf '%s\n' "$rc" > "${work}/rc"
}

mkdir -p "${work}/history" "${work}/two"
timings "${work}/history/00000001-a.json" 10.0 20.0
timings "${work}/history/00000002-b.json" 9.0 30.0
timings "${work}/history/00000003-c.json" 11.0 20.0
cp "${work}/history/00000001-a.json" "${work}/history/00000002-b.json" "${work}/two/"
timings "${work}/slower.json" 14.0 21.0
timings "${work}/far.json" 25.0 21.0
timings "${work}/spiky.json" 10.0 150.0
timings "${work}/same.json" 11.0 20.0

report "${work}/slower.json" "${work}/history"
check "the table compares with the median" "${work}/out" '^\| `start` \| 3 \| 14\.0 \(\+40 %\) \| 6\.0 \(\+0 %\) \| 21\.0 \(\+5 %\) \| 1 \| 0 \|$'
check "it names how many runs the median spans" "${work}/out" '^Against the median of 3 earlier run\(s\)\.$'
check "a slowdown over the warning threshold warns" "${work}/err" '^::warning title=Frontend slower::start build avg ms \+40 % against the median of 3 runs$'
check "a slowdown under it does not" "${work}/err" 'build worst ms' absent
check "a warning alone passes" "${work}/rc" '^0$'

report "${work}/far.json" "${work}/history"
check "a doubling of a gated metric fails" "${work}/rc" '^1$'
check "and says so as an error" "${work}/err" '^::error title=Frontend far slower::start build avg ms \+150 %'

report "${work}/far.json" "${work}/two"
check "two earlier runs are not enough to fail" "${work}/rc" '^0$'
check "but still warn" "${work}/err" '^::warning title=Frontend slower::start build avg ms \+163 % against the median of 2 runs$'

report "${work}/spiky.json" "${work}/history"
check "a spike in the worst frame only warns" "${work}/rc" '^0$'

report "${work}/same.json" "${work}/history"
check "within the threshold, no annotation at all" "${work}/err" '::' absent

report "${work}/slower.json" "${work}/missing"
check "no history: plain values" "${work}/out" '^\| `start` \| 3 \| 14\.0 \| 6\.0 \| 21\.0 \| 1 \| 0 \|$'

report "${work}/slower.json" "${work}/history/00000001-a.json"
check "one earlier file stands in for a history" "${work}/out" '^\| `start` \| 3 \| 14\.0 \(\+40 %\)'

report "${work}/missing.json"
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

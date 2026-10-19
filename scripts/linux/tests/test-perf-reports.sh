#!/usr/bin/env bash
# The frontend performance scripts on synthetic input: the CI report's table and warnings, and the trace summary's self times.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
report="${SCRIPT_DIR}/../frontend-perf-report.py"
summary="${SCRIPT_DIR}/../flutter-trace-summary.py"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

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
t_case "the table compares with the median"
t_assert_grep "${work}/out" '^\| `start` \| 3 \| 14\.0 \(\+40 %\) \| 6\.0 \(\+0 %\) \| 21\.0 \(\+5 %\) \| 1 \| 0 \|$'
t_case "it names how many runs the median spans"
t_assert_grep "${work}/out" '^Against the median of 3 earlier run\(s\)\.$'
t_case "a slowdown over the warning threshold warns"
t_assert_grep "${work}/err" '^::warning title=Frontend slower::start build avg ms \+40 % against the median of 3 runs$'
t_case "a slowdown under it does not"
t_assert_no_grep "${work}/err" 'build worst ms'
t_case "a warning alone passes"
t_assert_grep "${work}/rc" '^0$'

report "${work}/far.json" "${work}/history"
t_case "a doubling of a gated metric fails"
t_assert_grep "${work}/rc" '^1$'
t_case "and says so as an error"
t_assert_grep "${work}/err" '^::error title=Frontend far slower::start build avg ms \+150 %'

report "${work}/far.json" "${work}/two"
t_case "two earlier runs are not enough to fail"
t_assert_grep "${work}/rc" '^0$'
t_case "but still warn"
t_assert_grep "${work}/err" '^::warning title=Frontend slower::start build avg ms \+163 % against the median of 2 runs$'

report "${work}/spiky.json" "${work}/history"
t_case "a spike in the worst frame only warns"
t_assert_grep "${work}/rc" '^0$'

report "${work}/same.json" "${work}/history"
t_case "within the threshold, no annotation at all"
t_assert_no_grep "${work}/err" '::'

report "${work}/slower.json" "${work}/missing"
t_case "no history: plain values"
t_assert_grep "${work}/out" '^\| `start` \| 3 \| 14\.0 \| 6\.0 \| 21\.0 \| 1 \| 0 \|$'

report "${work}/slower.json" "${work}/history/00000001-a.json"
t_case "one earlier file stands in for a history"
t_assert_grep "${work}/out" '^\| `start` \| 3 \| 14\.0 \(\+40 %\)'

report "${work}/missing.json"
t_case "no timings: says so"
t_assert_grep "${work}/out" '^No frame timings found\.$'

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
t_case "both UI frames, the slow one first"
t_assert_grep "${work}/out" '^Slowest UI frames \(2 in the timeline\):'
t_case "the slow frame's length"
t_assert_grep "${work}/out" '^  at +0\.0 ms +999\.0 ms$'
t_case "the raster frame"
t_assert_grep "${work}/out" '^  at +999\.0 ms +2000\.0 ms$'
t_case "the widget's own time leads"
t_assert_grep "${work}/out" '^ +900\.0 ms  SlowPage$'
t_case "its parent's time is net of it"
t_assert_grep "${work}/out" '^ +49\.0 ms  BUILD$'
t_case "the frame keeps what no child took"
t_assert_grep "${work}/out" '^ +20\.0 ms  Animator::BeginFrame$'
t_case "the zero-length span closes only itself"
t_assert_grep "${work}/out" '^ +0\.0 ms  Dart_NewInteger$'
t_case "X events count as spans"
t_assert_grep "${work}/out" '^ +30\.0 ms  LAYOUT$'

printf '{"traceEvents": []}\n' > "${work}/empty.json"
t_case "an empty timeline fails"
t_assert_rc 1 python3 "$summary" "${work}/empty.json"

t_summary

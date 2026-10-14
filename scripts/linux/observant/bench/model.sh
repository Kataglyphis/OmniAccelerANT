#!/usr/bin/env bash
# On an ObservANT board: the installed service runs each model nonstop on a still picture, on a spare port.
set -euo pipefail

if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
  printf 'usage: %s PICTURE MODEL.onnx...  (no camera, no state: the live service is untouched)\n' "$0"
  exit 2
fi
picture="$1"
shift
observant="${OBSERVANT:-/opt/omni-observant/observant}"
port="${BENCH_PORT:-18080}"

# Prints one model's medians from the healthz samples in $1.
summarise() {
  python3 - "$1" "$2" <<'PY'
import json, statistics, sys
rows = [json.loads(line)["stats"] for line in open(sys.argv[1]) if line.strip()]
med = lambda k: statistics.median(r[k] for r in rows if r.get(k) is not None)
print(f"{sys.argv[2]:28s} model_ms={med('model_ms'):6.1f} runs/s={med('model_runs_per_s'):4.2f} "
      f"cpu%={med('cpu_percent'):5.1f} rss_mb={med('rss_mb'):5.1f} temp_c={med('temperature_c')}")
PY
  return 0
}

for model in "$@"; do
  work="$(mktemp -d)"
  # inference_fps = 0 with a higher idle rate turns the motion gate off, so the model never rests.
  printf 'http_port = %s\nsignalling_port = %s\nname = "Bench"\nmodel = "%s"\ninference = "on"\ninference_fps = 0\nidle_inference_fps = 100\n' \
    "${port}" "$((port + 1))" "${model}" > "${work}/bench.toml"
  env -u STATE_DIRECTORY "${observant}" --config "${work}/bench.toml" --image "${picture}" > "${work}/observant.log" 2>&1 &
  pid=$!
  for _ in $(seq 90); do
    curl -sf -m 2 "http://localhost:${port}/healthz" > /dev/null && break
    sleep 1
  done
  sleep 20
  for _ in $(seq 30); do
    curl -s -m 2 "http://localhost:${port}/healthz" >> "${work}/samples.json" || true
    echo >> "${work}/samples.json"
    sleep 2
  done
  kill "${pid}"
  wait "${pid}" 2> /dev/null || true
  summarise "${work}/samples.json" "$(basename "${model}")"
  rm -rf "${work}"
done

#!/usr/bin/env bash
# From another host: an ObservANT board's API times, its cost idle and with one phone-sized Chrome watching, and the page's cold load.
set -euo pipefail

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  printf 'usage: %s BOARD[:PORT] [SECONDS]  (needs curl, python3, and nerdctl or docker with the :latest image)\n' "$0"
  exit 2
fi
board="$1"
[[ "${board}" == *:* ]] || board="${board}:8080"
seconds="${2:-60}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine="${ENGINE:-$(command -v nerdctl || command -v docker)}"
# The image ref comes only from the hub; two assignments, since set -e misses a substitution failing mid-expansion.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${here}/../../lib/antfrastructure.sh"
_ci_image_ref_sh="$(antfrastructure_path linux/scripts/ci-image-ref.sh)"
image="${IMAGE:-$(bash "${_ci_image_ref_sh}")}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# The median of 20 timed GETs of $1.
median_s() {
  for _ in $(seq 20); do
    curl -s -o /dev/null -m 5 -w '%{time_total}\n' "http://${board}$1"
  done | sort -n | sed -n 10p
  return 0
}

# $2 samples of /healthz, 2 s apart, into $1.
sample() {
  for _ in $(seq "$2"); do
    curl -s -m 2 "http://${board}/healthz" >> "$1" || true
    echo >> "$1"
    sleep 2
  done
  return 0
}

echo "API: /healthz $(median_s /healthz) s, /snapshot.jpg $(median_s /snapshot.jpg) s (median of 20)"
sample "${work}/idle.json" 15
"${engine}" run --rm --network host -e URL="http://${board}/" -e SECONDS_TOTAL="${seconds}" \
  -v "${here}:/bench:ro" "${image}" bash -c '
    chrome="$(find /opt/chrome-for-testing -maxdepth 3 -type f -name chrome -perm -u+x 2>/dev/null | head -1)"
    "${chrome}" --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --autoplay-policy=no-user-gesture-required \
      --remote-debugging-port=9471 --user-data-dir=/tmp/chrome-bench --window-size=390,844 about:blank > /dev/null 2>&1 &
    sleep 3
    node /bench/page-perf.mjs 9471 "${URL}" "${SECONDS_TOTAL}"' > "${work}/page.txt" 2>&1 &
viewer=$!
sleep $((seconds / 2 + 5))
sample "${work}/viewing.json" $((seconds / 6))
wait "${viewer}" || true
grep -v 'level=warning' "${work}/page.txt"
python3 - "${work}" <<'PY'
import json, statistics, sys
def summary(name):
    rows = [json.loads(line) for line in open(f"{sys.argv[1]}/{name}.json") if line.strip()]
    stats = [r["stats"] for r in rows]
    med = lambda k: statistics.median(s[k] for s in stats if s.get(k) is not None)
    return (f"cpu%={med('cpu_percent'):5.1f} capture_fps={med('capture_fps'):4.1f} rss_mb={med('rss_mb'):5.1f} "
            f"temp_c={med('temperature_c')} viewers={max(r.get('viewers', 0) for r in rows)}")
print("board idle     ", summary("idle"))
print("board 1 viewer ", summary("viewing"))
PY

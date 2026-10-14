"""integration_test/performance_test.dart's frame timings as a Markdown table against the median of earlier runs: warns when slower, fails when far slower."""
import argparse
import json
import pathlib
import statistics
import sys

# FrameTimingSummarizer's keys that say most; its raster times stay 0 under Xvfb's software rendering.
METRICS = [
    ("frame_count", "frames"),
    ("average_frame_build_time_millis", "build avg ms"),
    ("90th_percentile_frame_build_time_millis", "build p90 ms"),
    ("worst_frame_build_time_millis", "build worst ms"),
    ("missed_frame_build_budget_count", "missed build budget"),
    ("old_gen_gc_count", "old-gen GCs"),
]
# Only these may fail the run: a single worst frame is too noisy to judge on.
GATED = {"average_frame_build_time_millis", "90th_percentile_frame_build_time_millis"}
# Fewer earlier runs than this only warn, so one odd runner cannot become the yardstick.
MIN_HISTORY_TO_FAIL = 3


def load(path):
    p = pathlib.Path(path)
    return json.loads(p.read_text()) if p.is_file() else {}


def history(path):
    """Earlier runs: every *.json in a directory, or a single file."""
    p = pathlib.Path(path)
    if p.is_dir():
        return [load(f) for f in sorted(p.glob("*.json"))]
    return [load(p)] if p.is_file() else []


def judge(name, key, value, earlier, args):
    """One table cell, and a failure message when the value is far over the median of `earlier`."""
    if value is None:
        return "-", None
    cell = f"{value:.1f}" if isinstance(value, float) else str(value)
    median = statistics.median(earlier) if earlier else None
    if not median or not key.endswith("millis"):
        return cell, None
    change = value / median - 1
    cell += f" ({change * 100:+.0f} %)"
    against = f"{change * 100:+.0f} % against the median of {len(earlier)} runs"
    # Frame times on a shared runner are noisy: a moderate slowdown warns, only a doubling fails.
    if key in GATED and change > args.fail and len(earlier) >= MIN_HISTORY_TO_FAIL:
        print(f"::error title=Frontend far slower::{name} {against}", file=sys.stderr)
        return cell, f"{name} {change * 100:+.0f} %"
    if change > args.warn:
        print(f"::warning title=Frontend slower::{name} {against}", file=sys.stderr)
    return cell, None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("current", nargs="?", default="out/perf/frontend.json")
    parser.add_argument("history", nargs="?", default=".perf-baseline", help="a directory of earlier runs' JSON, or one file")
    parser.add_argument("--warn", type=float, default=0.25, help="slower than the median by this fraction warns")
    parser.add_argument("--fail", type=float, default=1.0, help="slower than the median by this fraction fails (gated metrics)")
    args = parser.parse_args()

    current = load(args.current)
    runs = [r for r in history(args.history) if r]
    if not current:
        print("No frame timings found.")
        return 0
    print(f"Against the median of {len(runs)} earlier run(s).\n")
    print("| Scenario | " + " | ".join(label for _, label in METRICS) + " |")
    print("| --- |" + " --- |" * len(METRICS))
    failed = []
    for scenario, summary in sorted(current.items()):
        cells = []
        for key, label in METRICS:
            earlier = [r[scenario][key] for r in runs if isinstance(r.get(scenario, {}).get(key), (int, float))]
            cell, failure = judge(f"{scenario} {label}", key, summary.get(key), earlier, args)
            cells.append(cell)
            if failure:
                failed.append(failure)
        print(f"| `{scenario}` | " + " | ".join(cells) + " |")
    if failed:
        print(f"\nFar slower than before: {', '.join(failed)}.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

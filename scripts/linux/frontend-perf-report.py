"""integration_test/performance_test.dart's frame timings as a Markdown table, each against a baseline, warning when slower."""
import json
import pathlib
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


def load(path):
    p = pathlib.Path(path)
    return json.loads(p.read_text()) if p.is_file() else {}


def main():
    current = load(sys.argv[1] if len(sys.argv) > 1 else "out/perf/frontend.json")
    baseline = load(sys.argv[2]) if len(sys.argv) > 2 else {}
    threshold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
    if not current:
        print("No frame timings found.")
        return 0
    print("| Scenario | " + " | ".join(label for _, label in METRICS) + " |")
    print("| --- |" + " --- |" * len(METRICS))
    for scenario, summary in sorted(current.items()):
        old = baseline.get(scenario, {})
        cells = []
        for key, label in METRICS:
            value = summary.get(key)
            if value is None:
                cells.append("-")
                continue
            before = old.get(key)
            cell = f"{value:.1f}" if isinstance(value, float) else str(value)
            if isinstance(before, (int, float)) and before > 0 and key.endswith("millis"):
                change = value / before - 1
                cell += f" ({change * 100:+.0f} %)"
                # Frame times on a shared runner are noisy, so a slowdown warns rather than fails.
                if change > threshold:
                    print(f"::warning title=Frontend slower::{scenario} {label} {change * 100:+.0f} % against the baseline", file=sys.stderr)
            cells.append(cell)
        print(f"| `{scenario}` | " + " | ".join(cells) + " |")
    return 0


if __name__ == "__main__":
    sys.exit(main())

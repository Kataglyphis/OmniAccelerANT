"""A Flutter timeline's slowest frames, and where the slowest UI frame spent its own time (widgets, with debugProfileBuildsEnabled)."""
import argparse
import collections
import json
import sys

UI_FRAME = "Animator::BeginFrame"
RASTER_FRAME = "GPURasterizer::Draw"


def load_events(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return data["traceEvents"] if isinstance(data, dict) else data


def spans(events):
    """Every B/E pair and X event as (start, duration, self time, name, thread), self time net of direct children."""
    marks = []
    for i, e in enumerate(events):
        ph, ts = e.get("ph"), e.get("ts")
        if ts is None:
            continue
        key = (e.get("pid"), e.get("tid"))
        if ph == "B":
            marks.append((ts, i, True, key, e.get("name", "?")))
        elif ph == "E":
            marks.append((ts, i, False, key, None))
        elif ph == "X":
            dur = e.get("dur", 0)
            marks.append((ts, i, True, key, e.get("name", "?")))
            marks.append((ts + dur, i + 0.5, False, key, None))
    # Ties keep the file's order: a zero-length span's B and E share a timestamp, and swapping them closes its parent.
    marks.sort(key=lambda m: (m[0], m[1]))
    stacks = collections.defaultdict(list)
    out = []
    for ts, _, is_begin, key, name in marks:
        stack = stacks[key]
        if is_begin:
            stack.append([ts, name, 0])
        elif stack:
            start, span_name, children = stack.pop()
            dur = ts - start
            if stack:
                stack[-1][2] += dur
            out.append((start, dur, dur - children, span_name, key))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("timeline", help="e.g. build/start_up_timeline.json from flutter run --profile --trace-startup")
    parser.add_argument("--top", type=int, default=10, help="rows per table")
    args = parser.parse_args()

    all_spans = spans(load_events(args.timeline))
    if not all_spans:
        print("No timeline events found.")
        return 1
    t0 = min(s[0] for s in all_spans)

    def frames(name):
        return sorted((s for s in all_spans if s[3] == name), key=lambda s: -s[1])

    for title, name in (("UI frames", UI_FRAME), ("Raster frames", RASTER_FRAME)):
        found = frames(name)
        print(f"Slowest {title} ({len(found)} in the timeline):")
        for start, dur, _, _, _ in found[: args.top]:
            print(f"  at {(start - t0) / 1000:9.1f} ms  {dur / 1000:9.1f} ms")

    ui = frames(UI_FRAME)
    if not ui:
        return 0
    start, dur, _, _, thread = ui[0]
    inside = [s for s in all_spans if s[4] == thread and s[0] >= start and s[0] + s[1] <= start + dur]
    own = collections.Counter()
    for s in inside:
        own[s[3]] += s[2]
    print(f"Self time inside the slowest UI frame ({dur / 1000:.1f} ms):")
    for name, us in own.most_common(args.top):
        print(f"  {us / 1000:9.1f} ms  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

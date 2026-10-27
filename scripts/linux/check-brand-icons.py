#!/usr/bin/env python3
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
"""Check every committed launcher icon is the repo logo: the SVG copy is byte-identical and each raster matches the master downscaled; it does not render the SVG."""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

LOGO_SVG = "images/logo.svg"
SVG_COPIES = ["assets/icons/kataglyphis_app_icon.svg"]
MASTER = "assets/icons/kataglyphis_app_icon.png"
DERIVED = [
    "images/logo.png",
    "web/icons/Icon-192.png",
    "web/icons/Icon-512.png",
    "web/icons/Icon-maskable-192.png",
    "web/icons/Icon-maskable-512.png",
    *(
        f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
    ),
]
ICONS = ["windows/runner/resources/app_icon.ico"]
TOLERANCE = 6.0


def png_chunks(data: bytes) -> tuple[tuple[int, ...], bytes]:
    """Return the IHDR fields and the joined IDAT payload."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, header = 8, b"", None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    if header is None:
        raise ValueError("PNG has no IHDR")
    return header, idat


def paeth(left: int, up: int, corner: int) -> int:
    guess = left + up - corner
    return min(
        (abs(guess - left), 0, left),
        (abs(guess - up), 1, up),
        (abs(guess - corner), 2, corner),
    )[2]


def unfilter(
    kind: int, line: bytearray, previous: bytearray, channels: int
) -> bytearray:
    if kind not in (0, 1, 2, 3, 4):
        raise ValueError(f"bad PNG filter {kind}")
    for x in range(len(line) if kind else 0):
        left = line[x - channels] if x >= channels else 0
        up = previous[x]
        corner = previous[x - channels] if x >= channels else 0
        predictor = (0, left, up, (left + up) >> 1, paeth(left, up, corner))[kind]
        line[x] = (line[x] + predictor) & 0xFF
    return line


def decode_png(data: bytes) -> tuple[int, int, list[bytearray]]:
    """Return width, height and RGBA rows of an 8-bit RGB or RGBA, non-interlaced PNG."""
    (width, height, depth, color, _, _, interlace), idat = png_chunks(data)
    if depth != 8 or color not in (2, 6) or interlace:
        raise ValueError(
            f"unsupported PNG layout depth={depth} color={color} interlace={interlace}"
        )
    channels = 4 if color == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * channels
    rows: list[bytearray] = []
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        line = unfilter(
            raw[start],
            bytearray(raw[start + 1 : start + 1 + stride]),
            previous,
            channels,
        )
        previous = line
        if channels == 3:
            line = bytearray(
                b for i in range(width) for b in (*line[i * 3 : i * 3 + 3], 255)
            )
        rows.append(line)
    return width, height, rows


def ico_frames(data: bytes) -> list[bytes]:
    _, kind, count = struct.unpack("<HHH", data[:6])
    if kind != 1 or count == 0:
        raise ValueError("not an icon file")
    frames = []
    for index in range(count):
        size, offset = struct.unpack(
            "<II", data[6 + 16 * index + 8 : 6 + 16 * index + 16]
        )
        frame = data[offset : offset + size]
        if frame[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError("icon frame is not PNG")
        frames.append(frame)
    return frames


def premultiplied(
    rows: list[bytearray], width: int, height: int, size: int
) -> list[float]:
    """Box-average to size x size, premultiplied by alpha, as flat RGBA floats."""
    out: list[float] = []
    for ty in range(size):
        y0, y1 = (
            ty * height // size,
            max(ty * height // size + 1, (ty + 1) * height // size),
        )
        for tx in range(size):
            x0, x1 = (
                tx * width // size,
                max(tx * width // size + 1, (tx + 1) * width // size),
            )
            total = [0.0, 0.0, 0.0, 0.0]
            for y in range(y0, y1):
                row = rows[y]
                for x in range(x0, x1):
                    r, g, b, a = row[x * 4 : x * 4 + 4]
                    total[0] += r * a / 255
                    total[1] += g * a / 255
                    total[2] += b * a / 255
                    total[3] += a
            count = (y1 - y0) * (x1 - x0)
            out.extend(value / count for value in total)
    return out


def distance(master: tuple[int, int, list[bytearray]], data: bytes) -> float:
    width, height, rows = decode_png(data)
    if width != height:
        raise ValueError(f"icon is not square: {width}x{height}")
    probe = min(width, 48)
    left = premultiplied(master[2], master[0], master[1], probe)
    right = premultiplied(rows, width, height, probe)
    return sum(abs(a - b) for a, b in zip(left, right)) / len(left)


def check(root: Path) -> list[str]:
    errors = []
    logo = (root / LOGO_SVG).read_bytes()
    for copy in SVG_COPIES:
        if (root / copy).read_bytes() != logo:
            errors.append(f"{copy} is not byte-identical to {LOGO_SVG}")
    master = decode_png((root / MASTER).read_bytes())
    samples = [(path, (root / path).read_bytes()) for path in DERIVED]
    for path in ICONS:
        samples += [
            (f"{path}[{n}]", frame)
            for n, frame in enumerate(ico_frames((root / path).read_bytes()))
        ]
    for name, data in samples:
        score = distance(master, data)
        if score > TOLERANCE:
            errors.append(
                f"{name} differs from {MASTER} (mean difference {score:.1f} > {TOLERANCE})"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root", type=Path, default=Path(__file__).resolve().parents[2]
    )
    args = parser.parse_args()
    try:
        errors = check(args.repo_root)
    except (OSError, ValueError, zlib.error, struct.error) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    print("PASS: every launcher icon derives from the repo logo")
    return 0


if __name__ == "__main__":
    sys.exit(main())

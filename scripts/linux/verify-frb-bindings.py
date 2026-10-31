#!/usr/bin/env python3
"""Run the pinned OxidANT checker over the committed Rust and Dart bridge sides."""

import runpy
import sys
from pathlib import Path

CHECKER = (
    Path(__file__).resolve().parents[2]
    / "third_party/OxidANT/scripts/linux/verify-frb-bindings.py"
)

if __name__ == "__main__":
    sys.argv[0] = str(CHECKER)
    runpy.run_path(str(CHECKER), run_name="__main__")

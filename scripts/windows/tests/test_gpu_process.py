#!/usr/bin/env python3
"""Exercise GPU process timeout cleanup with a harmless child process."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "gpu_process", Path(__file__).resolve().parents[1] / "gpu_process.py"
)
if SPEC is None or SPEC.loader is None:
    raise ImportError("cannot load GPU process helper")
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


class GpuProcess(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "requires Windows taskkill")
    def test_timeout_terminates_child_tree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            child = (
                "import pathlib,sys,time; p=pathlib.Path(sys.argv[1]); "
                "(p/'started').write_text('yes'); time.sleep(3); (p/'survived').write_text('yes')"
            )
            parent = (
                "import subprocess,sys,time; "
                "subprocess.Popen([sys.executable, '-c', sys.argv[1], sys.argv[2]]); time.sleep(20)"
            )
            with self.assertRaises(subprocess.TimeoutExpired):
                HELPER.run_process(
                    [sys.executable, "-c", parent, child, str(root)], timeout=1.5
                )
            self.assertTrue((root / "started").is_file())
            time.sleep(2)
            self.assertFalse((root / "survived").exists())


if __name__ == "__main__":
    unittest.main()

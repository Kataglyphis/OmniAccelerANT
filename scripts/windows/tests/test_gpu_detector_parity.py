#!/usr/bin/env python3
"""Exercise profile orchestration using real lock, profile and parity verifiers."""

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "omni_parity", ROOT / "scripts/windows/check_gpu_detector_parity.py"
)
if spec is None or spec.loader is None:
    raise RuntimeError("cannot load GPU parity helper")
parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parity)


class WindowsParity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo, self.stage = self.base / "repo", self.base / "installed app"
        self.stage.mkdir()
        (self.stage / "omni_accelerant.exe").touch()
        (self.stage / "onnxruntime.dll").touch()
        self.repo.mkdir()
        paths = (
            "scripts/windows/verify_detector_model.py",
            "third_party/ANTfrastructure/linux/scripts/lib/fetch-data-lock.py",
            "third_party/ANTfrastructure/shared/python/compare_detector_parity.py",
            "third_party/ANTfrastructure/shared/python/verify_ort_profile.py",
            "third_party/ANTfrastructure/windows/scripts/diagnostics/verify-dxgi-adapter.py",
            "third_party/OxidANT/crates/inference/tests/fixtures/two_cats.jpg",
        )
        for name in paths:
            dest = self.repo / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, dest)
        models = self.stage / "resources/models"
        models.mkdir(parents=True)
        lock = self.repo / "third_party/OxidANT/resources/models/models.lock"
        lock.parent.mkdir(parents=True)
        rows = []
        for name in (
            "deim_dfine_n_coco.onnx",
            "deim_dfine_n_coco.LICENSE",
            "deim_dfine_n_coco.NOTICE",
        ):
            content = name.encode()
            (models / name).write_bytes(content)
            rows.append(
                f"{hashlib.sha256(content).hexdigest()}  {name}  https://example.invalid/{name}\n"
            )
        lock.write_text("".join(rows), encoding="utf-8")
        self.fault = ""
        self.selected = []
        self.dxgi = []
        self.real_run = parity.run

    def run_fixture(self, command, **kwargs):
        if Path(command[0]).name == "omni_accelerant.exe":
            return self.run_application(command, kwargs)
        if "verify-dxgi-adapter.py" in command[2]:
            self.dxgi.append(command[-1])
            if self.fault == "wrong-adapter":
                raise subprocess.CalledProcessError(1, command)
            return
        self.real_run(command, **kwargs)

    def run_application(self, command, kwargs):
        env = kwargs["env"]
        device = env["KATAGLYPHIS_ORT_DEVICE"]
        self.selected.append(device)
        self.assertNotIn("KATAGLYPHIS_ONNX_MODEL", env)
        self.assertEqual(env["ORT_DYLIB_PATH"], str(self.stage / "onnxruntime.dll"))
        if device == "directml":
            self.assertEqual(env["KATAGLYPHIS_DIRECTML_DEVICE_ID"], "2")
        else:
            self.assertNotIn("KATAGLYPHIS_DIRECTML_DEVICE_ID", env)
        if self.fault == "child":
            raise subprocess.CalledProcessError(1, command)
        provider = {
            "cpu": "CPUExecutionProvider",
            "cuda": "CUDAExecutionProvider",
            "directml": "DmlExecutionProvider",
        }[device]
        if self.fault == "fallback" and device != "cpu":
            provider = "CPUExecutionProvider"
        score = 0.75 if self.fault == "parity" and device != "cpu" else 0.9
        result = {
            "schema_version": 1,
            "width": 480,
            "height": 659,
            "detections": [
                {"class": 15, "score": score, "box": [0, 250, 450, 640]},
                {"class": 15, "score": 0.8, "box": [0, 0, 250, 200]},
            ],
        }
        for output in command[3:5]:
            Path(output).write_text(json.dumps(result), encoding="utf-8")
        if self.fault == "repeat" and device != "cpu":
            result["detections"][0]["score"] = 0.75
            Path(command[4]).write_text(json.dumps(result), encoding="utf-8")
        profile: list[dict[str, object]] = [
            {
                "cat": "Session",
                "name": "model_run",
                "ph": "X",
                "pid": 42,
                "ts": start,
                "dur": 10,
            }
            for start in (0, 20)
        ]
        profile += [
            {
                "cat": "Node",
                "ph": "X",
                "pid": 42,
                "ts": start,
                "dur": 1,
                "args": {"provider": provider, "op_name": "Conv"},
            }
            for start in (1, 21)
        ]
        if self.fault == "second-fallback" and device != "cpu":
            arguments = profile[-1]["args"]
            if not isinstance(arguments, dict):
                raise TypeError("profile fixture arguments must be a dictionary")
            arguments["provider"] = "CPUExecutionProvider"
        if self.fault != "missing-profile":
            Path(command[5] + "_0.json").write_text(
                json.dumps(profile), encoding="utf-8"
            )

    def check(self, device="cuda", index="0"):
        with (
            mock.patch.object(parity, "run", side_effect=self.run_fixture),
            mock.patch.dict(
                os.environ,
                {
                    "KATAGLYPHIS_ONNX_MODEL": "wrong",
                    "KATAGLYPHIS_DIRECTML_DEVICE_ID": "99",
                },
            ),
        ):
            return parity.check(self.stage, device, index, self.repo, self.base)

    def test_cuda_and_directml_run_real_verifiers(self):
        for device, index in (("cuda", "0"), ("directml", "2")):
            with self.subTest(device=device):
                self.selected = []
                self.check(device, index)
                self.assertEqual(self.selected, ["cpu", device, device])
        self.assertEqual(self.dxgi, ["2"])

    def test_failures_are_not_accepted(self):
        for fault in (
            "child",
            "fallback",
            "second-fallback",
            "parity",
            "repeat",
            "missing-profile",
            "wrong-adapter",
        ):
            with self.subTest(fault=fault):
                self.fault = fault
                with self.assertRaises((ValueError, subprocess.SubprocessError)):
                    self.check("directml", "2")

    def test_changed_model_and_invalid_selection_are_rejected(self):
        (self.stage / "resources/models/deim_dfine_n_coco.onnx").write_text(
            "changed", encoding="utf-8"
        )
        with self.assertRaises(subprocess.SubprocessError):
            self.check()
        for device, index in (
            ("migraphx", "0"),
            ("directml", "-1"),
            ("directml", "01"),
            ("directml", "2147483648"),
        ):
            with self.assertRaises(ValueError):
                self.check(device, index)


if __name__ == "__main__":
    unittest.main()

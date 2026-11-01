#!/usr/bin/env python3
"""Prototype: verify Omni profile evidence; this does not authorize release."""

import argparse
import hashlib
import importlib.util
import json
import re
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

FORMATS = ("tar", "deb", "appimage")
MAX_TOTAL = 1024**3
MAX_ENTRY = 128 * 1024**2
BLOCK = 1024**2
COMPONENT = re.compile(r'^[^<>:"\\|?*\x00-\x1f]+$')
RESERVED = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    "CONIN$",
    "CONOUT$",
    *(f"{prefix}{digit}" for prefix in ("COM", "LPT") for digit in "123456789¹²³"),
}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"missing trusted helper: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_object(path, unique, stage):
    with stage.open_regular(path) as stream:
        payload = stream.read(65537)
    if len(payload) > 65536:
        raise ValueError("invalid metadata file")
    return json.loads(payload, object_pairs_hook=unique)


def require_equal(actual, expected, label):
    if actual != expected:
        raise ValueError(f"{label} mismatch")


def checked_metadata(repo, args, stage):
    meta = load_module(
        "omni_profile_metadata", repo / "scripts/linux/gpu-profile-metadata.py"
    )
    expected = meta.identity()
    candidate = read_object(args.candidate_metadata, meta.unique, stage)
    evidence = read_object(args.evidence_metadata, meta.unique, stage)
    meta.validate(candidate, expected, False)
    meta.validate(evidence, expected, True)
    for key in (*meta.IDENTITY, "artifact_id", "files"):
        require_equal(evidence[key], candidate[key], key)
    require_equal(
        evidence["artifact_digest"].removeprefix("sha256:"),
        candidate["artifact_digest"].removeprefix("sha256:"),
        "candidate digest",
    )
    require_equal(candidate["artifact_id"], args.candidate_id, "candidate ID")
    require_equal(
        candidate["artifact_digest"].removeprefix("sha256:"),
        args.candidate_digest.removeprefix("sha256:"),
        "trusted candidate digest",
    )
    require_equal(evidence["profile_artifact_id"], args.profile_id, "profile ID")
    require_equal(
        evidence["profile_artifact_digest"].removeprefix("sha256:"),
        args.profile_digest.removeprefix("sha256:"),
        "trusted profile digest",
    )
    return candidate, evidence


def digest(path, stage):
    with stage.open_regular(path) as stream:
        return stage.stream_digest(stream)


def safe_component(component):
    stem = component.split(".", 1)[0].rstrip(" ").upper()
    return (
        component not in ("", ".", "..")
        and bool(COMPONENT.fullmatch(component))
        and not component.endswith((".", " "))
        and stem not in RESERVED
    )


def check_entry(info):
    name = info.filename
    parts = name.split("/")
    mode = info.external_attr >> 16
    if (
        not name
        or "\\" in name
        or name.startswith("/")
        or any(not safe_component(part) for part in parts)
        or info.orig_filename != name
        or info.is_dir()
        or info.external_attr & 0x10
        or stat.S_IFMT(mode) not in (0, stat.S_IFREG)
        or info.flag_bits & 1
    ):
        raise ValueError("unsafe evidence entry")
    if info.file_size > MAX_ENTRY or (
        info.file_size
        and (not info.compress_size or info.file_size > 1000 * info.compress_size)
    ):
        raise ValueError("evidence expansion limit exceeded")


def check_entries(archive):
    entries = archive.infolist()
    if len(entries) > 512:
        raise ValueError("too many evidence entries")
    seen = set()
    total = 0
    for info in entries:
        check_entry(info)
        name = info.filename
        if name.casefold() in seen:
            raise ValueError("duplicate evidence entry")
        seen.add(name.casefold())
        total += info.file_size
        if total > MAX_TOTAL:
            raise ValueError("evidence expansion limit exceeded")
    return {info.filename: info for info in entries}


def required_entries(entries):
    required = {"receipt.json", "clean-host-receipt.json"}
    for fmt in FORMATS:
        for mode in ("cpu", "gpu"):
            required.update(f"{fmt}/{mode}-{n}.json" for n in (1, 2))
            profiles = [
                name
                for name in entries
                if re.fullmatch(rf"{fmt}/{mode}-profile[^/]*\.json", name)
            ]
            loaders = [
                name
                for name in entries
                if re.fullmatch(rf"{fmt}/{mode}-loader\.[0-9]+", name)
            ]
            if len(profiles) != 1 or not loaders:
                raise ValueError("missing or ambiguous profile/loader evidence")
            required.add(profiles[0])
            required.update(loaders)
    if not required.issubset(entries):
        raise ValueError("missing required evidence")
    return required


def extract_selected(archive, entries, names, root):
    for name in names:
        dest = root.joinpath(*PurePosixPath(name).parts)
        dest.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(entries[name]) as source, dest.open("xb") as target:
            while chunk := source.read(BLOCK):
                target.write(chunk)


def run(*args):
    subprocess.run(
        [sys.executable, "-I", *(str(arg) for arg in args)],
        check=True,
        capture_output=True,
    )


def verify_loader_traces(path, fmt, vendor, mode):
    variant = f"omni-accelerant-{vendor}"
    locations = {
        "tar": rf"tar/{re.escape(variant)}-bundle/lib",
        "deb": rf"deb/opt/{re.escape(variant)}/lib",
        "appimage": rf"image-tmp/appimage_extracted_[0-9a-f]{{32}}/usr/lib/{re.escape(variant)}/lib",
    }
    pattern = re.compile(
        rf"^/(?:[^/\r\n]+/)*omni-gpu-packages\.[^/\r\n]+/{locations[fmt]}/libonnxruntime\.so(?:\.[0-9]+)*$"
    )
    found = []
    for trace in path.glob(f"{mode}-loader.*"):
        for line in trace.read_text(encoding="utf-8", errors="strict").splitlines():
            marker = "calling init: "
            if marker in line and "libonnxruntime.so" in line:
                loaded = line.split(marker, 1)[1].strip()
                if ".." in PurePosixPath(loaded).parts or not pattern.fullmatch(loaded):
                    raise ValueError("ORT loader evidence points outside the package")
                found.append(loaded)
    if not found:
        raise ValueError("missing ONNX Runtime loader evidence")


def verify_profiles(shared, root, vendor):
    device = "cuda" if vendor == "nvidia" else "migraphx"
    for fmt in FORMATS:
        path = root / fmt
        for mode, expected in (("cpu", "cpu"), ("gpu", device)):
            verify_loader_traces(path, fmt, vendor, mode)
            profiles = list(path.glob(f"{mode}-profile*.json"))
            if len(profiles) != 1:
                raise ValueError("ambiguous profile")
            run(
                shared / "verify_ort_profile.py",
                profiles[0],
                "--device",
                expected,
                "--min-runs",
                "2",
            )
        for left, right, pairwise in (
            ("cpu-1", "cpu-2", False),
            ("cpu-1", "gpu-1", False),
            ("cpu-1", "gpu-2", False),
            ("gpu-1", "gpu-2", True),
        ):
            tail = ("--pairwise",) if pairwise else ()
            run(
                shared / "compare_detector_parity.py",
                path / f"{left}.json",
                path / f"{right}.json",
                *tail,
            )


def verify_candidate_archive(stage, archive, candidate, root):
    identity = {
        key: candidate[key]
        for key in (
            "repository",
            "revision",
            "run_id",
            "run_attempt",
            "artifact_id",
            "artifact_digest",
            "arch",
            "vendor",
        )
    }
    identity["platform"] = "linux"
    stage.receipt.validate_identity({**identity, "check": "gpu-model-inference"})
    identity["artifact_digest"] = identity["artifact_digest"].removeprefix("sha256:")
    names = stage.receipt.validate_files(candidate["files"])
    hashes = stage.checked_receipts(
        [root / "clean-host-receipt.json", root / "receipt.json"], identity, names
    )
    with stage.open_regular(archive) as stream:
        require_equal(
            stage.stream_digest(stream),
            identity["artifact_digest"],
            "candidate archive digest",
        )
        stream.seek(0)
        with zipfile.ZipFile(stream) as zipped:
            entries = stage.archive_entries(zipped, names, 40 * 1024**3, 1000)
            for entry in entries:
                hasher = hashlib.sha256()
                with zipped.open(entry) as payload:
                    for chunk in iter(lambda: payload.read(BLOCK), b""):
                        hasher.update(chunk)
                require_equal(
                    hasher.hexdigest(),
                    hashes[entry.filename],
                    f"package {entry.filename}",
                )
        require_equal(
            stage.stream_digest(stream),
            identity["artifact_digest"],
            "candidate archive changed during check",
        )


def verify(args):
    repo = args.repo.resolve(strict=True)
    shared = repo / "third_party/ANTfrastructure/shared/python"
    stage = load_module("omni_stage_gpu_artifact", shared / "stage_gpu_artifact.py")
    candidate, evidence = checked_metadata(repo, args, stage)
    profile_digest = args.profile_digest.removeprefix("sha256:")
    with tempfile.TemporaryDirectory(prefix="omni-evidence-review-") as tmp:
        root = Path(tmp)
        with stage.open_regular(args.profile_archive) as source:
            require_equal(
                stage.stream_digest(source), profile_digest, "profile archive digest"
            )
            source.seek(0)
            with zipfile.ZipFile(source) as archive:
                entries = check_entries(archive)
                extract_selected(archive, entries, required_entries(entries), root)
            require_equal(
                stage.stream_digest(source),
                profile_digest,
                "profile archive changed during check",
            )
        require_equal(
            digest(root / "receipt.json", stage),
            evidence["receipt_sha256"],
            "profile receipt hash",
        )
        verify_candidate_archive(stage, args.candidate_archive, candidate, root)
        verify_profiles(shared, root, candidate["vendor"])
    print(
        "Evidence checks passed; GPU hardware identity and release eligibility remain unverified"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in (
        "repo",
        "candidate-metadata",
        "evidence-metadata",
        "candidate-archive",
        "profile-archive",
    ):
        parser.add_argument("--" + name, type=Path, required=True)
    for name in ("candidate-id", "candidate-digest", "profile-id", "profile-digest"):
        parser.add_argument("--" + name, required=True)
    try:
        verify(parser.parse_args())
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        zipfile.BadZipFile,
        subprocess.CalledProcessError,
    ) as error:
        print(f"Profile evidence rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

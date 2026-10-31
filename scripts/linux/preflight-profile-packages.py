#!/usr/bin/env python3
"""Measure trusted same-run package payloads and reserve profiling scratch space."""

import argparse
import json
import os
import posixpath
import re
import shutil
import struct
import subprocess
import tarfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

MAX_BYTES = 4 * 1024**3
MAX_ENTRIES = 100_000
CUSHION = 1024**3
DEFAULT_FLOOR = 31 * 1024**3 // 2
LISTING = re.compile(
    r"^([dl-])[rwxstST-]{9}\s+\d+/\d+\s+(\d+)\s+"
    r"\d{4}-\d\d-\d\d\s+\d\d:\d\d\s+(.+)$"
)


def clean_path(name: str) -> str:
    if not name or name.startswith("/") or any(ord(char) < 32 for char in name):
        raise ValueError("unsafe package path")
    normalized = posixpath.normpath(name)
    if normalized == ".." or normalized.startswith("../"):
        raise ValueError("package path escapes its root")
    return normalized


def check_link(name: str, target: str) -> None:
    if not target or target.startswith("/") or any(ord(char) < 32 for char in target):
        raise ValueError("unsafe package link")
    clean_path(posixpath.join(posixpath.dirname(clean_path(name)), target))


def tar_size(stream) -> int:
    total = count = 0
    with tarfile.open(fileobj=stream, mode="r|*") as archive:
        for member in archive:
            count += 1
            if count > MAX_ENTRIES:
                raise ValueError("package has too many members")
            clean_path(member.name)
            if member.isfile():
                total += member.size
                if total > MAX_BYTES:
                    raise ValueError("package exceeds expanded-size cap")
            elif member.issym():
                check_link(member.name, member.linkname)
            elif member.islnk():
                clean_path(member.linkname)
            elif not member.isdir():
                raise ValueError("unsupported package member")
    return total


def deb_size(path: Path) -> int:
    process = subprocess.Popen(
        ["dpkg-deb", "--fsys-tarfile", str(path)], stdout=subprocess.PIPE
    )
    assert process.stdout is not None
    try:
        size = tar_size(process.stdout)
        if process.wait() != 0:
            raise ValueError("cannot read DEB payload")
        return size
    except BaseException:
        process.kill()
        process.wait()
        raise


def image_offset(path: Path) -> int:
    with path.open("rb") as stream:
        header = stream.read(64)
        if header[:6] != b"\x7fELF\x02\x01" or header[8:11] != b"AI\x02":
            raise ValueError("expected a little-endian ELF64 type-2 AppImage")
        section_offset = struct.unpack_from("<Q", header, 40)[0]
        entry_size, count = struct.unpack_from("<HH", header, 58)
        if entry_size != 64 or not 0 < count < 65535:
            raise ValueError("unsupported AppImage ELF section table")
        offset = section_offset + entry_size * count
        if offset + 4 > path.stat().st_size:
            raise ValueError("AppImage ELF section table is outside file")
        stream.seek(offset)
        if stream.read(4) != b"hsqs":
            raise ValueError("AppImage has no SquashFS at the ELF boundary")
    return offset


def image_size(path: Path) -> int:
    if shutil.which("unsquashfs") is None:
        raise ValueError("unsquashfs is required for AppImage profile preflight")
    process = subprocess.Popen(
        ["unsquashfs", "-offset", str(image_offset(path)), "-lln", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert process.stdout is not None
    total = count = 0
    try:
        for line in process.stdout:
            if len(line) > 4096:
                raise ValueError("oversized SquashFS listing entry")
            match = LISTING.fullmatch(line.rstrip("\n"))
            if not match:
                raise ValueError("ambiguous SquashFS listing")
            count += 1
            if count > MAX_ENTRIES:
                raise ValueError("AppImage has too many members")
            kind, size, name = match.groups()
            if kind == "l":
                name, separator, target = name.partition(" -> ")
                if not separator:
                    raise ValueError("ambiguous SquashFS link")
                check_link(name, target)
            clean_path(name)
            if kind == "-":
                total += int(size)
                if total > MAX_BYTES:
                    raise ValueError("AppImage exceeds expanded-size cap")
        if process.wait() != 0 or not count:
            raise ValueError("cannot inspect AppImage SquashFS")
        return total
    except BaseException:
        process.kill()
        process.wait()
        raise


def floor() -> int:
    value = os.environ.get("PROFILE_DISK_FLOOR_BYTES", str(DEFAULT_FLOOR))
    if not value.isdecimal() or int(value) < DEFAULT_FLOOR:
        raise ValueError("PROFILE_DISK_FLOOR_BYTES must be at least 15.5 GiB")
    return int(value)


def reserve(root: Path, size: int) -> None:
    free = shutil.disk_usage(root).free
    required = floor() + CUSHION + size
    if free < required:
        raise ValueError(f"insufficient scratch space: need {required}, have {free}")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Keep the artifact API token on the requested GitHub host."""

    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        return None


def checked_artifact_size(data, artifact_id: str, run: str, sha: str) -> int:
    if not isinstance(data, dict) or not isinstance(data.get("workflow_run"), dict):
        raise TypeError("candidate artifact metadata has an invalid shape")
    workflow = data.get("workflow_run") or {}
    size = data.get("size_in_bytes")
    if (
        data.get("id") != int(artifact_id)
        or data.get("expired") is not False
        or workflow.get("id") != int(run)
        or workflow.get("head_sha") != sha
        or type(size) is not int
        or not 0 < size <= 3 * MAX_BYTES
    ):
        raise ValueError("candidate artifact metadata does not match this run")
    return size


def artifact_size(artifact_id: str) -> int:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run = os.environ.get("GITHUB_RUN_ID", "")
    sha = os.environ.get("GITHUB_SHA", "")
    token = os.environ.get("GH_TOKEN", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("invalid repository identity")
    if (
        not artifact_id.isdecimal()
        or not run.isdecimal()
        or not re.fullmatch(r"[0-9a-f]{40}", sha)
        or not token
    ):
        raise ValueError("missing or invalid artifact identity")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/actions/artifacts/{artifact_id}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
    )
    try:
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(request, timeout=30) as response:
            raw = response.read(1_048_577)
    except (OSError, urllib.error.URLError) as error:
        raise ValueError("cannot query candidate artifact metadata") from error
    if len(raw) > 1_048_576:
        raise ValueError("candidate artifact metadata is too large")
    return checked_artifact_size(json.loads(raw), artifact_id, run, sha)


def outer_size(path: Path) -> int:
    with zipfile.ZipFile(path) as archive:
        members = archive.infolist()
        if len(members) != 3 or any(
            member.is_dir() or not 0 < member.file_size <= MAX_BYTES
            for member in members
        ):
            raise ValueError(
                "candidate archive must contain three bounded package files"
            )
        return sum(member.file_size for member in members)


def check(plan: dict, stage: str, root: Path) -> None:
    image = plan["image"]
    remaining = {
        "initial": max(plan["tar"], plan["deb"], 3 * image + plan["image_file"]),
        "tar": plan["tar"],
        "deb": plan["deb"],
        "image": 3 * image + plan["image_file"],
        "extract": 3 * image,
        "runtime": 0,
        "launch": 2 * image,
    }[stage]
    required = floor() + CUSHION + remaining
    free = shutil.disk_usage(root).free
    if free < required:
        raise ValueError(
            f"insufficient scratch space for {stage}: need {required}, have {free}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="operation", required=True)
    create = sub.add_parser("create")
    for name in ("tar", "deb", "image", "plan", "root"):
        create.add_argument(f"--{name}", type=Path, required=True)
    validate = sub.add_parser("check")
    validate.add_argument("--plan", type=Path, required=True)
    validate.add_argument("--root", type=Path, required=True)
    validate.add_argument(
        "--stage",
        choices=("initial", "tar", "deb", "image", "extract", "runtime", "launch"),
        required=True,
    )
    download = sub.add_parser("download")
    download.add_argument("--artifact-id", required=True)
    download.add_argument("--root", type=Path, required=True)
    stage = sub.add_parser("stage")
    stage.add_argument("--archive", type=Path, required=True)
    stage.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.operation == "create":
            if shutil.which("unsquashfs") is None:
                raise ValueError(
                    "unsquashfs is required for AppImage profile preflight"
                )
            with args.tar.open("rb") as stream:
                tar = tar_size(stream)
            plan = {
                "tar": tar,
                "deb": deb_size(args.deb),
                "image": image_size(args.image),
                "image_file": args.image.stat().st_size,
            }
            check(plan, "initial", args.root)
            with args.plan.open("x", encoding="utf-8") as output:
                json.dump(plan, output)
                output.write("\n")
        elif args.operation == "check":
            plan = json.loads(args.plan.read_text(encoding="utf-8"))
            if set(plan) != {"tar", "deb", "image", "image_file"} or any(
                type(value) is not int or not 0 <= value <= MAX_BYTES
                for value in plan.values()
            ):
                raise ValueError("invalid package space plan")
            check(plan, args.stage, args.root)
        elif args.operation == "download":
            reserve(args.root, artifact_size(args.artifact_id))
        else:
            reserve(args.root, outer_size(args.archive))
    except (
        OSError,
        TypeError,
        ValueError,
        struct.error,
        tarfile.TarError,
        zipfile.BadZipFile,
    ) as error:
        parser.exit(1, f"GPU profile preflight: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

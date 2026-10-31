#!/usr/bin/env python3
"""Bind each Omni GPU candidate upload to the current tuple and run."""

import argparse
import json
import os
import re
from pathlib import Path

TUPLES = {("nvidia", "x64"), ("nvidia", "arm64"), ("amd", "x64")}
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+~-]*\Z")
NUMBER = re.compile(r"[1-9][0-9]*\Z")
DIGEST = re.compile(r"(?:sha256:)?[0-9a-f]{64}\Z")
IDENTITY = ("repository", "revision", "run_id", "run_attempt", "vendor", "arch")


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate metadata key")
        result[key] = value
    return result


def identity():
    env = os.environ
    data = dict(
        zip(
            IDENTITY,
            (
                env["GITHUB_REPOSITORY"],
                env["GITHUB_SHA"],
                env["GITHUB_RUN_ID"],
                env["GITHUB_RUN_ATTEMPT"],
                env["GPU_VENDOR"],
                env["GPU_ARCH"],
            ),
        )
    )
    if (
        (data["vendor"], data["arch"]) not in TUPLES
        or not re.fullmatch(r"[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+", data["repository"])
        or not re.fullmatch(r"[0-9a-f]{40}", data["revision"])
        or not NUMBER.fullmatch(data["run_id"])
        or not NUMBER.fullmatch(data["run_attempt"])
    ):
        raise ValueError("invalid tuple or run identity")
    return data


def validate_files(files, vendor, arch):
    if (
        not isinstance(files, list)
        or len(files) != 3
        or any(not isinstance(name, str) or not NAME.fullmatch(name) for name in files)
        or len({name.casefold() for name in files}) != 3
    ):
        raise ValueError("expected three distinct portable filenames")
    prefix = f"omni-accelerant-{vendor}"
    machine = "x86_64" if arch == "x64" else "aarch64"
    deb = "amd64" if arch == "x64" else "arm64"
    if (
        f"{prefix}-linux-{arch}.tar.gz" not in files
        or sum(
            name.startswith(prefix + "_") and name.endswith("_" + deb + ".deb")
            for name in files
        )
        != 1
        or sum(
            name.startswith(prefix + "-") and name.endswith("-" + machine + ".AppImage")
            for name in files
        )
        != 1
    ):
        raise ValueError("package filenames do not match tuple and format")
    return sorted(files)


def select(path, ident):
    vendor, arch = ident["vendor"], ident["arch"]
    prefix = f"omni-accelerant-{vendor}"
    patterns = (
        f"{prefix}-linux-{arch}.tar.gz",
        f"{prefix}_*.deb",
        f"{prefix}-*.AppImage",
    )
    files = []
    for pattern in patterns:
        matches = list(path.glob(pattern))
        if len(matches) != 1 or matches[0].is_symlink() or not matches[0].is_file():
            raise ValueError("expected one regular file per package format")
        files.append(matches[0].name)
    return validate_files(files, vendor, arch)


def output(data, directory=None):
    with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
        if directory is not None:
            stream.write("paths<<OMNI_PACKAGE_PATHS\n")
            stream.writelines(
                f"{directory.as_posix()}/{name}\n" for name in data["files"]
            )
            stream.write("OMNI_PACKAGE_PATHS\n")
        else:
            stream.write(
                f"artifact_id={data['artifact_id']}\nartifact_digest={data['artifact_digest']}\n"
            )
            if "profile_artifact_id" in data:
                stream.write(f"profile_artifact_id={data['profile_artifact_id']}\n")
                stream.write(
                    f"profile_artifact_digest={data['profile_artifact_digest']}\n"
                )
                stream.write(f"receipt_sha256={data['receipt_sha256']}\n")
        stream.write(
            "files<<OMNI_PACKAGE_FILES\n"
            + "\n".join(data["files"])
            + "\nOMNI_PACKAGE_FILES\n"
        )


def validate_evidence(data):
    if (
        not isinstance(data["profile_artifact_id"], str)
        or not NUMBER.fullmatch(data["profile_artifact_id"])
        or not isinstance(data["profile_artifact_digest"], str)
        or not DIGEST.fullmatch(data["profile_artifact_digest"])
        or not isinstance(data["receipt_sha256"], str)
        or not re.fullmatch(r"[0-9a-f]{64}", data["receipt_sha256"])
    ):
        raise ValueError("invalid profile evidence identity")


def validate(data, expected, evidence):
    keys = set(IDENTITY) | {"artifact_id", "artifact_digest", "files"}
    if evidence:
        keys |= {"profile_artifact_id", "profile_artifact_digest", "receipt_sha256"}
    if (
        not isinstance(data, dict)
        or set(data) != keys
        or any(data.get(key) != value for key, value in expected.items())
        or not isinstance(data["artifact_id"], str)
        or not NUMBER.fullmatch(data["artifact_id"])
        or not isinstance(data["artifact_digest"], str)
        or not DIGEST.fullmatch(data["artifact_digest"])
    ):
        raise ValueError("invalid immutable artifact identity")
    if evidence:
        validate_evidence(data)
    data["files"] = validate_files(data["files"], expected["vendor"], expected["arch"])
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", choices=("select", "create", "resolve", "evidence", "resolve-evidence")
    )
    parser.add_argument("path", type=Path)
    parser.add_argument("--candidate-metadata", type=Path)
    args = parser.parse_args()
    expected = identity()
    if args.mode == "select":
        output({"files": select(args.path, expected)}, args.path)
        return
    evidence = args.mode in ("evidence", "resolve-evidence")
    if args.mode in ("create", "evidence"):
        data = {
            **expected,
            "artifact_id": os.environ["GPU_ARTIFACT_ID"],
            "artifact_digest": os.environ["GPU_ARTIFACT_DIGEST"],
            "files": os.environ["GPU_ARTIFACT_FILES"].splitlines(),
        }
        if evidence:
            data.update(
                profile_artifact_id=os.environ["GPU_PROFILE_ARTIFACT_ID"],
                profile_artifact_digest=os.environ["GPU_PROFILE_ARTIFACT_DIGEST"],
                receipt_sha256=os.environ["GPU_PROFILE_RECEIPT_SHA256"],
            )
    else:
        data = json.loads(
            args.path.read_text(encoding="utf-8"), object_pairs_hook=unique
        )
    validate(data, expected, evidence)
    if args.mode == "resolve-evidence":
        if args.candidate_metadata is None:
            raise ValueError("independently resolved candidate metadata is required")
        candidate = json.loads(
            args.candidate_metadata.read_text(encoding="utf-8"),
            object_pairs_hook=unique,
        )
        validate(candidate, expected, False)
        for key in ("artifact_id", "files"):
            if data[key] != candidate[key]:
                raise ValueError("evidence candidate identity does not match")
        if data["artifact_digest"].removeprefix("sha256:") != candidate[
            "artifact_digest"
        ].removeprefix("sha256:"):
            raise ValueError("evidence candidate digest does not match")
    if args.mode in ("create", "evidence"):
        with args.path.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(data, stream, sort_keys=True)
            stream.write("\n")
    else:
        output(data)


if __name__ == "__main__":
    main()

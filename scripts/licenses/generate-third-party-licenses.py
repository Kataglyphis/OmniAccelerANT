#!/usr/bin/env python3
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
"""Generate or check the shipped third-party license inventory; native file coverage is check-native-coverage.py's job."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NATIVE = HERE / "native-components.json"
POLICY = HERE / "cargo-policy.json"
CARGO_TEXTS = HERE / "texts" / "cargo"
ASSET_DIR = ROOT / "assets" / "licenses"
INDEX = ASSET_DIR / "third-party-licenses.json"
TEXT_PREFIX = "third-party-license-texts-"
DOC = ROOT / "docs" / "source" / "third-party-components.md"
STAGER = (
    ROOT
    / "third_party/ANTfrastructure/linux/scripts/06-packaging/stage-cargo-licenses.py"
)
CHUNK_BYTES = 400_000
DESKTOP = [
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
    "x86_64-pc-windows-msvc",
    "aarch64-pc-windows-msvc",
]
WORKSPACES: list[dict[str, Any]] = [
    {
        "path": "third_party/OxidANT",
        "roots": ["oxidant", "kataglyphis_observant"],
        "targets": [
            *DESKTOP,
            "riscv64gc-unknown-linux-gnu",
            "aarch64-linux-android",
            "wasm32-unknown-unknown",
        ],
        "license": None,
    },
    # Older rusty_code revisions omit the MIT license; newer ones declare it themselves.
    {
        "path": "third_party/AccelerANTgine/Src/rusty_code",
        "roots": ["rusty_code"],
        "targets": DESKTOP,
        "license": "third_party/AccelerANTgine/LICENSE",
    },
]
INPUTS = [
    "pubspec.lock",
    "third_party/OxidANT/Cargo.lock",
    "third_party/AccelerANTgine/Src/rusty_code/Cargo.lock",
    "scripts/licenses/native-components.json",
    "scripts/licenses/cargo-policy.json",
]


def normalized(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n")


def digest(data: bytes) -> str:
    return hashlib.sha256(normalized(data)).hexdigest()


def decode(data: bytes) -> str:
    try:
        return normalized(data).decode("utf-8")
    except UnicodeDecodeError:
        return normalized(data).decode("latin-1")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def input_digests() -> dict[str, str]:
    return {name: digest((ROOT / name).read_bytes()) for name in INPUTS}


def native_components(texts: dict[str, str]) -> list[dict[str, Any]]:
    result = []
    for item in load_json(NATIVE)["components"]:
        refs = []
        for text in item["texts"]:
            data = (ROOT / text["path"]).read_bytes()
            if digest(data) != text["sha256"]:
                raise ValueError(f"{text['path']} does not match its pinned sha256")
            texts[text["sha256"]] = decode(data)
            refs.append(
                {
                    "name": Path(text["path"]).name,
                    "sha256": text["sha256"],
                    "provenance": text["provenance"],
                }
            )
        if not refs and not item.get("note"):
            raise ValueError(
                f"native component {item['id']} has neither texts nor a note"
            )
        entry = {
            "ecosystem": "native",
            "name": item["name"],
            "license": item["license"],
            "source": item["source"],
            "files": item["files"],
            "texts": refs,
        }
        for key in ("note", "license_url"):
            if key in item:
                entry[key] = item[key]
        result.append(entry)
    return result


def dart_packages() -> list[dict[str, Any]]:
    packages: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    section = None
    for line in (ROOT / "pubspec.lock").read_text(encoding="utf-8").splitlines():
        if not line.startswith(" "):
            section = line.rstrip(":")
            continue
        if section != "packages":
            continue
        if line.startswith("  ") and not line.startswith("   "):
            current = {"name": line.strip().rstrip(":")}
            packages.append(current)
        elif (
            current is not None
            and line.startswith("    ")
            and not line.startswith("     ")
        ):
            key, _, value = line.strip().partition(":")
            current[key] = value.strip().strip('"')
        elif current is not None and line.startswith("      url:"):
            current["url"] = line.split(":", 1)[1].strip().strip('"')
    result = []
    for package in packages:
        if package.get("dependency") == "direct dev":
            continue
        source = package.get("source", "")
        origin = package.get("url", source) if source in ("hosted", "git") else source
        result.append(
            {
                "ecosystem": "dart",
                "name": package["name"],
                "version": package.get("version", ""),
                "source": origin,
                "texts": [],
                "note": "Text in Flutter's NOTICES; dev-only transitive packages are included.",
            }
        )
    return sorted(result, key=lambda item: item["name"])


def ensure_workspace_mit_license(manifest: Path) -> None:
    content = manifest.read_text(encoding="utf-8")
    package = tomllib.loads(content).get("package")
    if not isinstance(package, dict):
        raise TypeError(f"{manifest}: missing package table")
    declared = package.get("license")
    if "license-file" in package or declared not in (None, "MIT"):
        raise ValueError(f"{manifest}: expected MIT package license, got {declared!r}")
    if declared is None:
        header = re.search(r"(?m)^\[\s*package\s*\][ \t]*(?:#.*)?$", content)
        if header is None:
            raise ValueError(f"{manifest}: cannot locate package table")
        content = content[: header.end()] + '\nlicense = "MIT"' + content[header.end() :]
        manifest.write_text(content, encoding="utf-8")


def stage_workspace(
    spec: dict[str, Any],
    scratch: Path,
    texts: dict[str, str],
    crates: dict[str, dict[str, Any]],
) -> None:
    source = ROOT / spec["path"]
    copy = scratch / Path(spec["path"]).name
    shutil.copytree(source, copy, ignore=shutil.ignore_patterns(".git", "target"))
    shutil.copytree(CARGO_TEXTS, copy / ".omni-cargo-licenses")
    # Policy digests are of LF text, whatever core.autocrlf checked out.
    if (copy / "LICENSE").is_file():
        (copy / "LICENSE").write_bytes(normalized((copy / "LICENSE").read_bytes()))
    if spec["license"]:
        ensure_workspace_mit_license(copy / "Cargo.toml")
        (copy / "LICENSE").write_bytes(
            normalized((ROOT / spec["license"]).read_bytes())
        )
    subprocess.run(["cargo", "fetch", "--locked"], cwd=copy, check=True)
    for root in spec["roots"]:
        for target in spec["targets"]:
            out = scratch / f"out-{root}-{target}"
            subprocess.run(
                [
                    sys.executable,
                    str(STAGER),
                    "--workspace",
                    str(copy),
                    "--root-package",
                    root,
                    "--target",
                    target,
                    "--policy",
                    str(POLICY),
                    "--output-dir",
                    str(out),
                ],
                check=True,
            )
            for package in load_json(out / "manifest.json")["packages"]:
                key = f"{package['name']}@{package['version']}"
                entry = crates.setdefault(
                    key,
                    {
                        "ecosystem": "cargo",
                        "name": package["name"],
                        "version": package["version"],
                        "license": package.get("license") or "",
                        "source": package.get("repository")
                        or package.get("source")
                        or "path",
                        "texts": [],
                        "used_by": set(),
                        "targets": set(),
                    },
                )
                entry["used_by"].add(root)
                entry["targets"].add(target)
                names = {text["name"] for text in entry["texts"]}
                for copied in package["files"]:
                    data = (out / copied["path"]).read_bytes()
                    name = copied["path"].split("/", 1)[1]
                    if name in names:
                        continue
                    sha = digest(data)
                    texts[sha] = decode(data)
                    entry["texts"].append(
                        {
                            "name": name,
                            "sha256": sha,
                            "provenance": copied.get("provenance")
                            or f"crates.io {key}",
                        }
                    )


def cargo_crates(texts: dict[str, str]) -> list[dict[str, Any]]:
    crates: dict[str, dict[str, Any]] = {}
    with tempfile.TemporaryDirectory(prefix="omni-cargo-licenses-") as scratch:
        for spec in WORKSPACES:
            stage_workspace(spec, Path(scratch), texts, crates)
    for entry in crates.values():
        entry["used_by"] = sorted(entry["used_by"])
        entry["targets"] = sorted(entry["targets"])
        entry["texts"].sort(key=lambda text: text["name"])
    return [crates[key] for key in sorted(crates)]


def chunk_texts(texts: dict[str, str]) -> list[dict[str, str]]:
    chunks: list[dict[str, str]] = [{}]
    size = 0
    for sha in sorted(texts):
        cost = len(json.dumps({sha: texts[sha]}, ensure_ascii=False).encode("utf-8"))
        if chunks[-1] and size + cost > CHUNK_BYTES:
            chunks.append({})
            size = 0
        chunks[-1][sha] = texts[sha]
        size += cost
    return chunks


def dump(value: Any) -> str:
    return json.dumps(value, indent=1, ensure_ascii=False, sort_keys=True) + "\n"


def cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render_doc(index: dict[str, Any]) -> str:
    groups = {
        name: [c for c in index["components"] if c["ecosystem"] == name]
        for name in ("native", "cargo", "dart")
    }
    lines = [
        "<!-- Generated by scripts/licenses/generate-third-party-licenses.py --write; do not edit. -->",
        "# Third-party components",
        "",
        "Every open-source component that OmniAccelerANT and ObservANT packages ship, generated from the",
        "lockfiles and `scripts/licenses/native-components.json`. The texts ship in every package as",
        "`assets/licenses/third-party-licenses.json` and its text files, and the app's licenses page lists them;",
        "Dart package texts are in Flutter's `NOTICES`. Maintenance and limits:",
        "[project operations](project-operations.md#third-party-license-inventory).",
        "",
        f"## Native code and data ({len(groups['native'])})",
        "",
        "| Component | License | Source | Shipped files |",
        "| --- | --- | --- | --- |",
    ]
    for c in groups["native"]:
        files = "; ".join(
            f"{platform}: {', '.join(f'`{p}`' for p in patterns)}"
            for platform, patterns in sorted(c["files"].items())
        )
        lines.append(
            f"| {cell(c['name'])} | {cell(c['license'])} | {c['source']} | {cell(files) or cell(c.get('note', ''))} |"
        )
    lines += [
        "",
        f"## Rust crates ({len(groups['cargo'])})",
        "",
        "| Crate | Version | License | Used by |",
        "| --- | --- | --- | --- |",
    ]
    for c in groups["cargo"]:
        lines.append(
            f"| {cell(c['name'])} | {c['version']} | {cell(c['license'])} | {', '.join(c['used_by'])} |"
        )
    lines += [
        "",
        f"## Dart packages ({len(groups['dart'])})",
        "",
        "| Package | Version | Source |",
        "| --- | --- | --- |",
    ]
    for c in groups["dart"]:
        lines.append(f"| {cell(c['name'])} | {c['version']} | {cell(c['source'])} |")
    return "\n".join(lines) + "\n"


def asset_paths(index: dict[str, Any]) -> list[Path]:
    return [INDEX, *(ASSET_DIR / name for name in index["text_files"])]


def write() -> None:
    texts: dict[str, str] = {}
    components = native_components(texts) + cargo_crates(texts) + dart_packages()
    chunks = chunk_texts(texts)
    names = [f"{TEXT_PREFIX}{number}.json" for number in range(1, len(chunks) + 1)]
    for stale in ASSET_DIR.glob(f"{TEXT_PREFIX}*.json"):
        stale.unlink()
    for name, chunk in zip(names, chunks):
        (ASSET_DIR / name).write_text(dump(chunk), encoding="utf-8", newline="\n")
    index = {
        "schema": 1,
        "inputs": input_digests(),
        "text_files": names,
        "components": components,
    }
    INDEX.write_text(dump(index), encoding="utf-8", newline="\n")
    DOC.write_text(render_doc(index), encoding="utf-8", newline="\n")


def check_sources(index: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if index.get("inputs") != input_digests():
        errors.append(
            "an input changed since the inventory was generated (lockfile, native table or cargo policy)"
        )
    if native_components({}) != [
        c for c in index["components"] if c["ecosystem"] == "native"
    ]:
        errors.append(
            "native components differ from scripts/licenses/native-components.json"
        )
    if dart_packages() != [c for c in index["components"] if c["ecosystem"] == "dart"]:
        errors.append("Dart packages differ from pubspec.lock")
    return errors


def check_store(index: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    store: dict[str, str] = {}
    for name in index["text_files"]:
        store.update(load_json(ASSET_DIR / name))
    errors += [
        f"text {sha} does not match its digest"
        for sha, text in store.items()
        if sha
        not in (digest(text.encode("utf-8")), digest(text.encode("latin-1", "replace")))
    ]
    for component in index["components"]:
        errors += [
            f"{component['name']}: missing text {text['name']}"
            for text in component["texts"]
            if text["sha256"] not in store
        ]
        if component["ecosystem"] == "cargo" and not component["texts"]:
            errors.append(
                f"{component['name']}@{component['version']}: no license text"
            )
    expected = {INDEX.name, *index["text_files"]}
    actual = {path.name for path in ASSET_DIR.glob("third-party-licen*.json")}
    if actual != expected:
        errors.append(f"asset files differ from the index: {sorted(actual ^ expected)}")
    return errors


def check() -> list[str]:
    index = load_json(INDEX)
    errors = check_sources(index) + check_store(index)
    if not DOC.is_file() or normalized(DOC.read_bytes()).decode("utf-8") != render_doc(
        index
    ):
        errors.append(
            f"{DOC.relative_to(ROOT).as_posix()} is not the rendering of the index"
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--write",
        action="store_true",
        help="regenerate; needs cargo and the crate sources",
    )
    mode.add_argument("--check", action="store_true", help="offline drift check")
    mode.add_argument(
        "--list-assets",
        action="store_true",
        help="print the shipped asset paths, repo-relative",
    )
    args = parser.parse_args()
    try:
        if args.write:
            write()
            errors = check()
        elif args.list_assets:
            names = (
                path.relative_to(ROOT).as_posix()
                for path in asset_paths(load_json(INDEX))
            )
            # Bytes, so a Windows interpreter does not hand Bash a carriage return.
            sys.stdout.buffer.write(
                "".join(f"{name}\n" for name in names).encode("utf-8")
            )
            return 0
        else:
            errors = check()
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        json.JSONDecodeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        print(
            "Regenerate with: python3 scripts/licenses/generate-third-party-licenses.py --write",
            file=sys.stderr,
        )
        return 1
    print(
        f"PASS: third-party license inventory matches its inputs ({INDEX.relative_to(ROOT).as_posix()})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

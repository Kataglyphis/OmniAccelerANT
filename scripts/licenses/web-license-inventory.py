#!/usr/bin/env python3
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
"""Write or check the license inventory of the browser app, derived from the files its build directory ships."""

from __future__ import annotations

import argparse
import functools
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[2]
TABLE = Path(__file__).resolve().parent / "web-components.json"
STORE = "assets/web-licenses"
INDEX = f"{STORE}/index.json"
NOTICES = "assets/NOTICES"
NOTICE_SEPARATOR = "\n" + "-" * 80 + "\n"
# The page loads one chunk per opened text, so chunks stay small; few files keep the FTP upload short.
CHUNK_BYTES = 400_000
NATIVE_INDEX = Path("assets/licenses/third-party-licenses.json")
GROUPS = ("app", "engine", "dart", "wasm", "cargo", "ort", "models", "fonts", "javascript")
# Each compiled Dart output and the depfile its compiler wrote beside the build.
DEPFILES = {"main.dart.js": "dart2js.d", "main.dart.wasm": "dart2wasm.d"}
ORT_REQUIRED_TEXTS = {"LICENSE", "ThirdPartyNotices.txt"}
NODE_MODULE = re.compile(r"node_modules/((?:@[^/]+/)?[^/]+)/")


class InventoryError(Exception):
    """An input the inventory needs is missing or malformed."""


def text_of(data: bytes) -> str:
    data = data.replace(b"\r\n", b"\n")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def shipped_files(app: Path) -> list[str]:
    """Every file below app, repo-style relative, without the inventory's own store."""
    if not app.is_dir():
        raise InventoryError(f"{app} is not a directory")
    found = []
    for path in app.rglob("*"):
        rel = path.relative_to(app).as_posix()
        # Apache never serves .ht* files, so the hub's .htaccess is server configuration, not shipped content.
        if path.is_dir() or path.name.startswith(".ht") or rel.startswith(f"{STORE}/"):
            continue
        found.append(rel)
    return sorted(found)


def parse_notices(text: str) -> list[tuple[tuple[str, ...], str]]:
    """Flutter's NOTICES as (package names, text) blocks, split the way LicenseRegistry splits them."""
    blocks = []
    for block in text.replace("\r\n", "\n").split(NOTICE_SEPARATOR):
        head, _, body = block.partition("\n\n")
        names = tuple(name for name in head.split("\n") if name.strip())
        if names and body.strip():
            blocks.append((names, body))
    return blocks


def depfile_inputs(path: Path) -> list[str]:
    """The inputs of a Make-style depfile that Flutter's build writes."""
    text = path.read_text(encoding="utf-8").replace("\\\n", " ")
    _, separator, inputs = text.partition(": ")
    if not separator:
        raise InventoryError(f"{path} is not a depfile")
    return [item.replace("\\ ", " ") for item in re.split(r"(?<!\\)\s+", inputs.strip()) if item]


def package_roots(project: Path) -> dict[str, str]:
    """Each package of .dart_tool/package_config.json and its root directory."""
    config_path = project / ".dart_tool" / "package_config.json"
    if not config_path.is_file():
        raise InventoryError(f"{config_path} is missing: run the inventory in the tree that built the app")
    roots = {}
    for package in load_json(config_path)["packages"]:
        uri = package["rootUri"]
        path = unquote(urlparse(uri).path) if uri.startswith("file:") else str(config_path.parent / unquote(uri))
        roots[package["name"]] = os.path.normpath(path)
    return roots


def locked_packages(lock: Path) -> dict[str, dict[str, str]]:
    """version and source of each package in pubspec.lock."""
    packages: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    for line in lock.read_text(encoding="utf-8").splitlines():
        if re.fullmatch(r"  [A-Za-z0-9_]+:", line):
            current = packages.setdefault(line.strip()[:-1], {})
        elif current is not None and (match := re.fullmatch(r'    (version|source): "?([^"]*)"?', line)):
            current[match[1]] = match[2]
    return packages


@functools.cache
def glob_regex(pattern: str) -> re.Pattern[str]:
    """A rule's glob as a regex: * and ? stay within a path segment, ** spans segments."""
    parts, at = [], 0
    while at < len(pattern):
        for token, regex in (("**/", "(?:.*/)?"), ("**", ".*"), ("*", "[^/]*"), ("?", "[^/]")):
            if pattern.startswith(token, at):
                parts.append(regex)
                at += len(token)
                break
        else:
            parts.append(re.escape(pattern[at]))
            at += 1
    return re.compile("".join(parts))


def flutter_root(roots: dict[str, str]) -> str:
    """The Flutter SDK's directory, two levels above its flutter package."""
    return os.path.dirname(os.path.dirname(roots.get("flutter", "/")))


def glob_match(rel: str, patterns: list[str]) -> bool:
    return any(glob_regex(pattern).fullmatch(rel) for pattern in patterns)


class Inventory:
    """The components /app/ ships, built from its files and the build's own outputs; errors are collected, not raised."""

    def __init__(self, app: Path, project: Path, table: dict[str, Any]) -> None:
        self.app, self.project, self.table = app, project, table
        self.files = shipped_files(app)
        self.file_set = set(self.files)
        self.errors: list[str] = []
        self.texts: dict[str, str] = {}
        self.components: dict[str, dict[str, Any]] = {}
        self.notices: list[tuple[tuple[str, ...], str]] = []
        if NOTICES in self.file_set:
            self.notices = parse_notices(text_of((app / NOTICES).read_bytes()))

    def error(self, message: str) -> None:
        self.errors.append(message)

    def add_text(self, title: str, text: str) -> dict[str, str]:
        sha = sha256_text(text)
        self.texts[sha] = text
        return {"title": title, "sha256": sha}

    def shipped_text(self, rel: str) -> dict[str, str] | None:
        if rel not in self.file_set:
            self.error(f"{rel} is named as a license text but not shipped")
            return None
        return self.add_text(rel, text_of((self.app / rel).read_bytes()))

    def add_component(self, component: dict[str, Any]) -> None:
        """Adds or merges one component; a crate in two wasm modules is one entry with both files."""
        known = self.components.get(component["id"])
        if known is None:
            self.components[component["id"]] = component
            return
        known["files"] = sorted(set(known["files"]) | set(component["files"]))
        shas = {text["sha256"] for text in known["texts"]}
        known["texts"] += [text for text in component["texts"] if text["sha256"] not in shas]

    def notice_texts(self, keep: Any, key: Any) -> list[dict[str, str]]:
        """The NOTICES blocks keep selects, merged into one text per key, each block under its names as in NOTICES."""
        merged: dict[str, list[str]] = {}
        for names, body in self.notices:
            if keep(names):
                merged.setdefault(key(names), []).append("\n".join(names) + "\n\n" + body)
        return [self.add_text(title, NOTICE_SEPARATOR.join(blocks)) for title, blocks in sorted(merged.items())]

    def build(self) -> None:
        roots: dict[str, str] = {}
        try:
            roots = package_roots(self.project)
        except (InventoryError, OSError, KeyError, json.JSONDecodeError) as error:
            self.error(str(error))
        self.dart_components(roots)
        self.rule_components(roots)
        self.manifest_components("ort", self.ort_component)
        self.manifest_components("models", self.model_component)
        self.store_files()
        covered = {rel for component in self.components.values() for rel in component["files"]}
        self.errors += [f"{rel} is shipped but has no license entry" for rel in self.files if rel not in covered]
        self.errors += [f"{c['name']}: no license text" for c in self.components.values() if not c["texts"]]

    def build_dir(self) -> Path | None:
        if ".last_build_id" not in self.file_set:
            self.error(".last_build_id is not shipped, so the build's depfiles cannot be found")
            return None
        build_id = (self.app / ".last_build_id").read_text(encoding="utf-8").strip()
        return self.project / ".dart_tool" / "flutter_build" / build_id

    def compiled_packages(self, roots: dict[str, str]) -> dict[str, set[str]]:
        """Each package whose sources a shipped compiled output was built from, by that output."""
        outputs = [output for output in DEPFILES if output in self.file_set]
        build_dir = self.build_dir() if outputs else None
        if build_dir is None or not roots:
            return {}
        flutter_cache = os.path.join(flutter_root(roots), "bin", "cache")
        ordered = sorted(roots.items(), key=lambda item: len(item[1]), reverse=True)
        compiled: dict[str, set[str]] = {}
        for output in outputs:
            depfile = build_dir / DEPFILES[output]
            if not depfile.is_file():
                self.error(f"{depfile} is missing: run the inventory in the tree that built {output}")
                continue
            for source in depfile_inputs(depfile):
                owner = next((name for name, root in ordered if source.startswith(root + os.sep)), None)
                if owner is None and not source.startswith(flutter_cache + os.sep):
                    self.error(f"{output} was compiled from {source}, which belongs to no package")
                compiled.setdefault(owner or "", set()).add(output)
        compiled.pop("", None)
        return compiled

    def dart_components(self, roots: dict[str, str]) -> None:
        shipped = self.compiled_packages(roots)
        for rel in self.files:
            match = re.fullmatch(r"assets/packages/([^/]+)/.+", rel)
            if match:
                shipped.setdefault(match[1], set()).add(rel)
        lock = self.project / "pubspec.lock"
        locked = locked_packages(lock) if lock.is_file() else {}
        for name, files in sorted(shipped.items()):
            if name not in roots:
                self.error(f"assets/packages/{name}/ ships, but {name} is no package of this build")
            texts = self.notice_texts(lambda names, name=name: name in names, lambda _, name=name: name)
            # Flutter's NOTICES gives the SDK's own packages (flutter_localizations, flutter_web_plugins) no block: flutter's covers them.
            if not texts and roots.get(name, "").startswith(flutter_root(roots) + os.sep):
                texts = self.notice_texts(lambda names: "flutter" in names, lambda _: "flutter")
            if not texts:
                self.error(f"Dart package {name} ships in {', '.join(sorted(files))} but {NOTICES} has no text for it")
            entry = locked.get(name, {})
            component = {"group": "dart", "id": f"dart:{name}", "name": name, "files": sorted(files), "texts": texts}
            if entry.get("version"):
                component["version"] = entry["version"]
            if entry.get("source") == "hosted":
                component["source"] = f"https://pub.dev/packages/{name}"
            self.add_component(component)

    def rule_texts(self, rule: dict[str, Any], spec: dict[str, str], roots: dict[str, str]) -> list[dict[str, str]]:
        if "shipped" in spec:
            ref = self.shipped_text(spec["shipped"])
            return [ref] if ref else []
        if "notices" in spec:
            keep = spec["notices"]
            if keep == "engine":
                texts = self.notice_texts(
                    lambda names: any(name not in roots for name in names),
                    lambda names: next(name for name in names if name not in roots),
                )
            else:
                texts = self.notice_texts(lambda names: keep in names, lambda _: keep)
            if not texts:
                self.error(f"{rule['id']}: {NOTICES} has no {keep} notice")
            return texts
        data = (ROOT / spec["path"]).read_bytes()
        if hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest() != spec["sha256"]:
            self.error(f"{spec['path']} does not match its pinned sha256")
        path = PurePosixPath(spec["path"])
        return [self.add_text(f"{path.parent.name}/{path.name}".lstrip("/"), text_of(data))]

    def check_embeds(self, rule: dict[str, Any], files: list[str]) -> None:
        """A shipped source map names every npm package its bundle embeds; each must be one the rule licenses."""
        for rel in files:
            if not rel.endswith(".map"):
                continue
            sources = load_json(self.app / rel).get("sources", [])
            for package in sorted({m[1] for source in sources if (m := NODE_MODULE.search(source))}):
                if package not in rule.get("embeds", []):
                    self.error(f"{rel} embeds the npm package {package}, which {rule['id']} does not license")

    def rule_components(self, roots: dict[str, str]) -> None:
        for rule in self.table["components"]:
            files = [rel for rel in self.files if glob_match(rel, rule["files"])]
            if not files:
                continue
            texts = [ref for spec in rule["texts"] for ref in self.rule_texts(rule, spec, roots)]
            self.check_embeds(rule, files)
            component = {key: rule[key] for key in ("group", "id", "name", "license", "source")}
            component.update(files=files, texts=texts)
            if any(spec.get("notices") == "engine" for spec in rule["texts"]):
                component["includes"] = sorted({n for names, _ in self.notices for n in names if n not in roots})
            self.add_component(component)
            if "cargo_root" in rule:
                self.crate_components(rule, [rel for rel in files if rel.endswith(".wasm")])

    def native_inventory(self) -> tuple[dict[str, Any], dict[str, str]]:
        directory = self.project / NATIVE_INDEX.parent
        index = load_json(self.project / NATIVE_INDEX)
        store: dict[str, str] = {}
        for name in index["text_files"]:
            store.update(load_json(directory / name))
        return index, store

    def crate_components(self, rule: dict[str, Any], wasm_files: list[str]) -> None:
        """The crates of a wasm module's root on wasm32, with their texts from the native inventory."""
        root = rule["cargo_root"]
        if not wasm_files:
            self.error(f"{rule['id']}: no .wasm file among its shipped files")
            return
        index, store = self.native_inventory()
        crates = [c for c in index["components"] if root in c.get("wasm_roots", [])]
        if not crates:
            self.error(f"{rule['id']}: {NATIVE_INDEX} records no wasm32 crate of {root}; regenerate it")
        for crate in crates:
            texts = [self.add_text(text["name"], store[text["sha256"]]) for text in crate["texts"]]
            self.add_component({
                "group": "cargo", "id": f"cargo:{crate['name']}@{crate['version']}", "name": crate["name"],
                "version": crate["version"], "license": crate["license"], "source": crate["source"],
                "files": wasm_files, "texts": texts,
            })

    def listed_file(self, rel: str, entry: dict[str, Any]) -> bool:
        """A manifest's file is shipped with the manifest's size and sha256."""
        if rel not in self.file_set:
            self.error(f"{rel} is listed in its manifest but not shipped")
            return False
        path = self.app / rel
        if path.stat().st_size != entry.get("size") or sha256_file(path) != entry.get("sha256"):
            self.error(f"{rel} differs from its manifest's size or sha256")
        return True

    def manifest_entry(self, base: str, item: dict[str, Any]) -> tuple[list[str], list[dict[str, str]]]:
        """The shipped files of one ORT build, and the texts its license-role files hold."""
        files, texts = [], []
        for entry in item["files"]:
            rel = base + entry["file"]
            files.append(rel)
            if self.listed_file(rel, entry) and entry.get("role") == "license":
                texts.append(self.add_text(entry["file"], text_of((self.app / rel).read_bytes())))
        return files, texts

    def manifest_components(self, directory: str, build: Any) -> None:
        manifest = f"{directory}/manifest.json"
        if not any(rel.startswith(f"{directory}/") for rel in self.files):
            return
        if manifest not in self.file_set:
            self.error(f"{directory}/ ships without {manifest}")
            return
        try:
            build(load_json(self.app / manifest), manifest)
        except (KeyError, TypeError, AttributeError, json.JSONDecodeError) as error:
            self.error(f"{manifest} is malformed: {error!r}")

    def ort_component(self, manifest: dict[str, Any], manifest_path: str) -> None:
        """One component per staged ORT Web build, after the hub's stage-ort-web.py manifest."""
        ort = manifest["ort"]
        for build in manifest["builds"]:
            files, texts = self.manifest_entry(build["path"], build)
            missing = ORT_REQUIRED_TEXTS - {text["title"] for text in texts}
            if missing:
                self.error(f"ORT Web {build['build']}: {', '.join(sorted(missing))} not shipped beside the build")
            self.add_component({
                "group": "ort", "id": f"ort-web:{build['build']}", "name": f"ONNX Runtime Web ({build['build']})",
                "version": ort["version"], "license": "MIT",
                "source": f"https://github.com/microsoft/onnxruntime/tree/{ort['revision']}",
                "files": sorted([*files, manifest_path]), "texts": texts,
            })

    def model_component(self, manifest: dict[str, Any], manifest_path: str) -> None:
        """One component per model the hub's mirror-app-models.py wrote, with its license texts required."""
        for model in manifest["models"]:
            files = [model["path"]]
            self.listed_file(model["path"], model)
            texts = []
            for text in model["licenses"]:
                files.append(text["path"])
                if self.listed_file(text["path"], text):
                    texts.append(self.add_text(text["file"], text_of((self.app / text["path"]).read_bytes())))
            if not texts:
                self.error(f"model {model['name']}: no license text shipped beside it")
            component = {"group": "models", "id": f"model:{model['name']}", "name": model["name"],
                         "files": sorted([*files, manifest_path]), "texts": texts}
            release = model.get("release")
            if release:
                component["version"] = release["tag"]
                component["source"] = f"https://github.com/{release['repository']}/releases/tag/{release['tag']}"
            self.add_component(component)

    def text_files(self) -> tuple[list[dict[str, str]], dict[str, str]]:
        """The texts in chunks of about CHUNK_BYTES, in sha order, and the chunk file of each text."""
        chunks: list[dict[str, str]] = [{}]
        size = 0
        for sha in sorted(self.texts):
            cost = len(json.dumps(self.texts[sha], ensure_ascii=False).encode("utf-8"))
            if chunks[-1] and size + cost > CHUNK_BYTES:
                chunks.append({})
                size = 0
            chunks[-1][sha] = self.texts[sha]
            size += cost
        where = {sha: f"texts-{number}.json" for number, chunk in enumerate(chunks, 1) for sha in chunk}
        return chunks, where

    def store_files(self) -> None:
        """The index and text files this script writes ship too, so the rule that owns its store lists them."""
        chunks, _ = self.text_files()
        own = [INDEX, *(f"{STORE}/texts-{number}.json" for number in range(1, len(chunks) + 1))]
        owners = [rule["id"] for rule in self.table["components"] if glob_match(INDEX, rule["files"])]
        if not owners or owners[0] not in self.components:
            self.error(f"no shipped component owns {STORE}/")
            return
        self.add_component({**self.components[owners[0]], "files": own, "texts": []})
        self.files += own

    def index(self) -> dict[str, Any]:
        _, where = self.text_files()
        ordered = [
            {**c, "texts": [{**text, "file": where[text["sha256"]]} for text in c["texts"]]}
            for c in sorted(
                self.components.values(),
                key=lambda c: (GROUPS.index(c["group"]) if c["group"] in GROUPS else len(GROUPS), c["name"].lower(), c["id"]),
            )
        ]
        groups = {group: sum(1 for c in ordered if c["group"] == group) for group in GROUPS}
        return {
            "schema": 1,
            "file_count": len(self.files),
            "groups": {group: count for group, count in groups.items() if count},
            "components": ordered,
        }


def dump(value: Any) -> str:
    return json.dumps(value, indent=1, ensure_ascii=False, sort_keys=True) + "\n"


def build(app: Path, project: Path, table: Path) -> Inventory:
    inventory = Inventory(app, project, load_json(table))
    inventory.build()
    return inventory


def index_files(index: dict[str, Any]) -> set[str]:
    return {rel for component in index.get("components", []) for rel in component.get("files", [])}


def drift(written: dict[str, Any], expected: dict[str, Any]) -> list[str]:
    """Why the written index is not the one the shipped files give."""
    if written == expected:
        return []
    errors = [f"{rel} is shipped but missing from {INDEX}" for rel in sorted(index_files(expected) - index_files(written))]
    errors += [f"{rel} is in {INDEX} but not shipped" for rel in sorted(index_files(written) - index_files(expected))]
    return errors or [f"{INDEX} differs from what the shipped files give: regenerate it with --write"]


def check_store(app: Path, inventory: Inventory) -> list[str]:
    """The store holds exactly the index and the text chunks, each with the texts the shipped files give."""
    chunks, _ = inventory.text_files()
    expected = {f"texts-{number}.json": chunk for number, chunk in enumerate(chunks, 1)}
    store = app / STORE
    actual = {p.relative_to(store).as_posix() for p in store.rglob("*") if p.is_file()} - {"index.json"}
    errors = [f"{STORE}/{name} is missing" for name in sorted(set(expected) - actual)]
    errors += [f"{STORE}/{name} is no file of the inventory" for name in sorted(actual - set(expected))]
    for name in sorted(set(expected) & actual):
        if load_json(store / name) != expected[name]:
            errors.append(f"{STORE}/{name} does not hold the texts the shipped files give")
    return errors


def check(app: Path, project: Path, table: Path) -> tuple[Inventory, list[str]]:
    inventory = build(app, project, table)
    errors = list(inventory.errors)
    if not (app / INDEX).is_file():
        return inventory, [*errors, f"{INDEX} is missing: write it with --write"]
    errors += drift(load_json(app / INDEX), inventory.index())
    return inventory, errors + check_store(app, inventory)


def write(app: Path, project: Path, table: Path) -> tuple[Inventory, list[str]]:
    inventory = build(app, project, table)
    if inventory.errors:
        return inventory, inventory.errors
    store = app / STORE
    shutil.rmtree(store, ignore_errors=True)
    store.mkdir(parents=True)
    chunks, _ = inventory.text_files()
    for number, chunk in enumerate(chunks, 1):
        (store / f"texts-{number}.json").write_text(dump(chunk), encoding="utf-8", newline="\n")
    (app / INDEX).write_text(dump(inventory.index()), encoding="utf-8", newline="\n")
    return check(app, project, table)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help=f"write {INDEX} and its texts into the app, then check")
    mode.add_argument("--check", action="store_true", help="fail on a shipped file without an entry or an entry without a file")
    parser.add_argument("--app", type=Path, required=True, help="the built app directory, as /app/ ships it")
    parser.add_argument("--project", type=Path, default=ROOT, help="the tree that built it (default: this repository)")
    parser.add_argument("--table", type=Path, default=TABLE, help="the rules for files no build output describes")
    args = parser.parse_args(argv)
    try:
        inventory, errors = (write if args.write else check)(args.app, args.project, args.table)
    except (InventoryError, OSError, KeyError, TypeError, ValueError) as error:
        print(f"WEB-LICENSES FAIL: {error}", file=sys.stderr)
        return 1
    for message in errors:
        print(f"WEB-LICENSES FAIL: {message}", file=sys.stderr)
    if errors:
        return 1
    index = inventory.index()
    counts = ", ".join(f"{group} {count}" for group, count in index["groups"].items())
    print(f"WEB-LICENSES PASS: {args.app} ships {index['file_count']} files in {len(index['components'])} components ({counts})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

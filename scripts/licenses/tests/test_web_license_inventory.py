#!/usr/bin/env python3
"""The web license inventory over fixture builds: what it lists, and every way the gate fails."""

import contextlib
import hashlib
import importlib.util
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("omni_web_licenses", HERE / "web-license-inventory.py")
assert spec and spec.loader
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)

BUILD_ID = "0123456789abcdef0123456789abcdef"
SEPARATOR = "\n" + "-" * 80 + "\n"
NOTICES = SEPARATOR.join([
    "omni_accelerant\n\nMIT License, the app",
    "async\n\nBSD, the Dart project",
    "flutter\n\nBSD, the Flutter Authors",
    "skia\nharfbuzz\n\nBSD, Google",
    "icu\n\nUnicode license",
    "cupertino_icons\n\nMIT, Vladimir Kharlampidi",
    "sqlite3\n\nMIT, Simon Binder",
    "lints\n\nBSD, a dev dependency never compiled in",
])


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Fixture:
    """A built app and the tree that built it, as the docs job has them after flutter build web."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.app = root / "app"
        self.project = root / "project"
        self.flutter = root / "sdk" / "flutter"
        self.pub = root / "pub"
        self.build = self.project / ".dart_tool" / "flutter_build" / BUILD_ID
        self.write_project()
        self.write_app()

    def put(self, rel: str, data: bytes | str, base: Path | None = None) -> Path:
        path = (base or self.app) / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data.encode() if isinstance(data, str) else data)
        return path

    def write_project(self) -> None:
        packages = [
            {"name": "omni_accelerant", "rootUri": "../"},
            {"name": "anthology", "rootUri": "../third_party/ANThology"},
            {"name": "flutter", "rootUri": (self.flutter / "packages" / "flutter").as_uri()},
            {"name": "flutter_web_plugins", "rootUri": (self.flutter / "packages" / "flutter_web_plugins").as_uri()},
            {"name": "async", "rootUri": (self.pub / "async-2.13.0").as_uri()},
            {"name": "cupertino_icons", "rootUri": (self.pub / "cupertino_icons-1.0.8").as_uri()},
            {"name": "lints", "rootUri": (self.pub / "lints-6.0.0").as_uri()},
            {"name": "sqlite3", "rootUri": (self.pub / "sqlite3-3.0.0").as_uri()},
        ]
        self.put(".dart_tool/package_config.json", json.dumps({"configVersion": 2, "packages": packages}), self.project)
        sources = [
            self.flutter / "bin/cache/dart-sdk/lib/libraries.json",
            self.project / "lib/main.dart",
            self.build / "web_plugin_registrant.dart",
            self.pub / "async-2.13.0/lib/async.dart",
            self.flutter / "packages/flutter/lib/material.dart",
            self.flutter / "packages/flutter_web_plugins/lib/url strategy.dart",
        ]
        self.write_depfile("dart2js.d", "main.dart.js", sources)
        self.write_depfile("dart2wasm.d", "main.dart.wasm", sources[1:4])
        self.put("pubspec.lock", 'packages:\n  async:\n    source: hosted\n    version: "2.13.0"\n', self.project)
        crates = [
            {"ecosystem": "cargo", "name": "wasm-bindgen", "version": "0.2.100", "license": "MIT OR Apache-2.0",
             "source": "https://github.com/rustwasm/wasm-bindgen", "texts": [{"name": "LICENSE-MIT", "sha256": "a" * 64}],
             "wasm_roots": ["kataglyphis_vision_core_web", "oxidant"]},
            {"ecosystem": "cargo", "name": "oxidant", "version": "3.0.0", "license": "MIT", "source": "path",
             "texts": [{"name": "LICENSE", "sha256": "b" * 64}], "wasm_roots": ["oxidant"]},
            {"ecosystem": "cargo", "name": "tokio", "version": "1.0.0", "license": "MIT", "source": "crates.io",
             "texts": [{"name": "LICENSE", "sha256": "c" * 64}]},
        ]
        index = {"schema": 1, "text_files": ["texts-1.json"], "components": crates}
        self.put("assets/licenses/third-party-licenses.json", json.dumps(index), self.project)
        store = {"a" * 64: "MIT, wasm-bindgen", "b" * 64: "MIT, OxidANT", "c" * 64: "MIT, tokio"}
        self.put("assets/licenses/texts-1.json", json.dumps(store), self.project)

    def write_depfile(self, name: str, output: str, sources: list[Path]) -> None:
        inputs = " ".join(str(source).replace(" ", "\\ ") for source in sources)
        self.put(name, f"{self.build / output}: {inputs}\n", self.build)

    def write_app(self) -> None:
        for rel in ("index.html", "flutter.js", "flutter_bootstrap.js", "main.dart.js", "main.dart.wasm",
                    "main.dart.mjs", "canvaskit/canvaskit.wasm", "canvaskit/chromium/canvaskit.js",
                    "assets/FontManifest.json", "assets/assets/settings/app_settings.json",
                    "assets/packages/cupertino_icons/assets/CupertinoIcons.ttf", "pkg/oxidant.js",
                    "pkg/oxidant_bg.wasm", "sqlite3.wasm", "vision/kataglyphis_vision_core_web_bg.wasm",
                    "vision/kataglyphis_vision_core_web.js", "javascript/webrtc/gstwebrtc-api-3.0.0.esm.js"):
            self.put(rel, f"bytes of {rel}")
        self.put(".last_build_id", BUILD_ID + "\n")
        self.put(".htaccess", "Header set Cross-Origin-Opener-Policy same-origin\n")
        self.put("assets/NOTICES", NOTICES)
        self.put("pkg/LICENSE", "MIT, OxidANT as shipped\n")
        self.put_map(["webpack://gstwebrtc-api/./node_modules/sdp/sdp.js",
                      "webpack://gstwebrtc-api/./node_modules/webrtc-adapter/src/js/utils.js",
                      "webpack://gstwebrtc-api/./src/index.js"])
        self.put_manifest("ort", {"schema_version": 1, "ort": {"version": "1.24.0", "revision": "f" * 40}, "builds": [
            {"build": "jspi", "path": "ort/1.24.0-0123456789abcdef/", "files": self.manifest_files(
                "ort/1.24.0-0123456789abcdef/", {"ort-wasm-simd-threaded.jspi.wasm": "wasm", "LICENSE": "license",
                                                 "ThirdPartyNotices.txt": "license",
                                                 "ort-webgpu-factory-probe.LICENSE": "license"})}]})
        model, *licenses = (self.mirrored(name) for name in ("deim.onnx", "deim.LICENSE", "deim.NOTICE"))
        release = {"repository": "Kataglyphis/ModelANT", "tag": "deim-v2"}
        self.put_manifest("models", {"schema_version": 1, "models": [
            {"name": "deim", **model, "release": release, "licenses": licenses}]})

    def put_map(self, sources: list[str]) -> None:
        self.put("javascript/webrtc/gstwebrtc-api-3.0.0.esm.js.map", json.dumps({"version": 3, "sources": sources}))

    def manifest_files(self, base: str, roles: dict[str, str]) -> list[dict[str, object]]:
        entries: list[dict[str, object]] = []
        for name, role in roles.items():
            data = f"{role} {name}\n".encode()
            self.put(base + name, data)
            entries.append({"file": name, "role": role, "sha256": sha256(data), "size": len(data)})
        return entries

    def mirrored(self, name: str) -> dict[str, object]:
        """A file as the hub's mirror-app-models.py places it: under its own sha256, with its manifest entry."""
        data = f"bytes of {name}\n".encode()
        path = f"models/{sha256(data)}/{name}"
        self.put(path, data)
        return {"file": name, "path": path, "sha256": sha256(data), "size": len(data)}

    def put_manifest(self, directory: str, manifest: dict[str, object]) -> None:
        self.put(f"{directory}/manifest.json", json.dumps(manifest))

    def manifest(self, directory: str) -> dict:
        return json.loads((self.app / directory / "manifest.json").read_text())


class WebLicenseInventoryTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.fixture = Fixture(Path(temporary.name))

    def run_mode(self, mode) -> list[str]:
        _, errors = mode(self.fixture.app, self.fixture.project, inventory.TABLE)
        return errors

    def write_ok(self) -> dict:
        self.assertEqual([], self.run_mode(inventory.write))
        return json.loads((self.fixture.app / inventory.INDEX).read_text())

    def assert_fails(self, mode, needle: str) -> None:
        errors = self.run_mode(mode)
        self.assertTrue(any(needle in error for error in errors), f"no error with {needle!r} in {errors}")

    def test_lists_each_source_from_the_build_outputs(self) -> None:
        index = self.write_ok()
        by_id = {component["id"]: component for component in index["components"]}
        dart = sorted(c["name"] for c in index["components"] if c["group"] == "dart")
        self.assertEqual(["async", "cupertino_icons", "flutter", "flutter_web_plugins", "omni_accelerant"], dart)
        self.assertEqual(["main.dart.js"], by_id["dart:flutter_web_plugins"]["files"])
        self.assertEqual(["flutter"], [text["title"] for text in by_id["dart:flutter_web_plugins"]["texts"]])
        self.assertEqual("2.13.0", by_id["dart:async"]["version"])
        engine = by_id["flutter-web-engine"]
        self.assertEqual(["icu", "skia"], [text["title"] for text in engine["texts"]])
        self.assertEqual(["harfbuzz", "icu", "skia"], engine["includes"])
        cargo = by_id["cargo:wasm-bindgen@0.2.100"]
        self.assertEqual(["pkg/oxidant_bg.wasm", "vision/kataglyphis_vision_core_web_bg.wasm"], cargo["files"])
        self.assertNotIn("cargo:tokio@1.0.0", by_id)
        ort = by_id["ort-web:jspi"]
        self.assertIn("ort/manifest.json", ort["files"])
        self.assertEqual({"LICENSE", "ThirdPartyNotices.txt", "ort-webgpu-factory-probe.LICENSE"},
                         {text["title"] for text in ort["texts"]})
        model = by_id["model:deim"]
        self.assertEqual(["deim.LICENSE", "deim.NOTICE"], [text["title"] for text in model["texts"]])
        self.assertEqual("deim-v2", model["version"])
        self.assertEqual(4, len(model["files"]))
        listed = {rel for component in index["components"] for rel in component["files"]}
        self.assertNotIn(".htaccess", listed)
        self.assertIn(inventory.INDEX, listed)
        self.assertEqual(len(listed), index["file_count"])
        self.assertEqual([], self.run_mode(inventory.check))

    def test_texts_are_stored_once_under_their_sha256(self) -> None:
        index = self.write_ok()
        store = self.fixture.app / inventory.STORE
        texts: dict[str, str] = {}
        for chunk in sorted(store.glob("texts-*.json")):
            texts.update(json.loads(chunk.read_text()))
        for component in index["components"]:
            for text in component["texts"]:
                held = json.loads((store / text["file"]).read_text())[text["sha256"]]
                self.assertEqual(text["sha256"], sha256(held.encode()))
        self.assertEqual("MIT, OxidANT as shipped\n", texts[sha256(b"MIT, OxidANT as shipped\n")])

    def test_a_file_added_after_the_inventory_fails_the_check(self) -> None:
        self.write_ok()
        self.fixture.put("canvaskit/extra.wasm", "late")
        self.assert_fails(inventory.check, "canvaskit/extra.wasm is shipped but missing from")

    def test_a_listed_file_that_is_gone_fails_the_check(self) -> None:
        self.write_ok()
        (self.fixture.app / "sqlite3.wasm").unlink()
        self.assert_fails(inventory.check, "sqlite3.wasm is in assets/web-licenses/index.json but not shipped")

    def test_a_file_no_rule_covers_fails_and_nothing_is_written(self) -> None:
        self.fixture.put("mystery.bin", "?")
        self.assert_fails(inventory.write, "mystery.bin is shipped but has no license entry")
        self.assertFalse((self.fixture.app / inventory.STORE).exists())

    def test_an_ort_file_outside_its_manifest_fails(self) -> None:
        self.fixture.put("ort/1.24.0-0123456789abcdef/ort.jspi.min.mjs", "bundle")
        self.assert_fails(inventory.write, "ort/1.24.0-0123456789abcdef/ort.jspi.min.mjs is shipped but has no")

    def test_ort_bytes_that_differ_from_the_manifest_fail(self) -> None:
        self.fixture.put("ort/1.24.0-0123456789abcdef/ort-wasm-simd-threaded.jspi.wasm", "other bytes")
        self.assert_fails(inventory.write, "differs from its manifest's size or sha256")

    def test_an_ort_build_without_its_notices_fails(self) -> None:
        manifest = self.fixture.manifest("ort")
        files = manifest["builds"][0]["files"]
        manifest["builds"][0]["files"] = [entry for entry in files if entry["file"] != "ThirdPartyNotices.txt"]
        self.fixture.put_manifest("ort", manifest)
        (self.fixture.app / "ort/1.24.0-0123456789abcdef/ThirdPartyNotices.txt").unlink()
        self.assert_fails(inventory.write, "ThirdPartyNotices.txt not shipped beside the build")

    def test_ort_without_a_manifest_fails(self) -> None:
        (self.fixture.app / "ort/manifest.json").unlink()
        self.assert_fails(inventory.write, "ort/ ships without ort/manifest.json")

    def test_a_model_listed_but_not_shipped_fails(self) -> None:
        (self.fixture.app / self.fixture.manifest("models")["models"][0]["path"]).unlink()
        self.assert_fails(inventory.write, "deim.onnx is listed in its manifest but not shipped")

    def test_a_model_without_a_license_text_fails(self) -> None:
        manifest = self.fixture.manifest("models")
        for text in manifest["models"][0]["licenses"]:
            (self.fixture.app / text["path"]).unlink()
        manifest["models"][0]["licenses"] = []
        self.fixture.put_manifest("models", manifest)
        self.assert_fails(inventory.write, "model deim: no license text shipped beside it")

    def test_model_bytes_that_differ_from_the_manifest_fail(self) -> None:
        self.fixture.put(self.fixture.manifest("models")["models"][0]["licenses"][1]["path"], "edited notice")
        self.assert_fails(inventory.write, "deim.NOTICE differs from its manifest's size or sha256")

    def test_a_compiled_package_without_a_notice_fails(self) -> None:
        self.fixture.put("assets/NOTICES", NOTICES.replace("async\n\nBSD, the Dart project", "other\n\nBSD"))
        self.assert_fails(inventory.write, "Dart package async ships in main.dart.js, main.dart.wasm but")

    def test_a_source_outside_every_package_fails(self) -> None:
        self.fixture.write_depfile("dart2js.d", "main.dart.js", [self.fixture.root / "elsewhere" / "x.dart"])
        self.assert_fails(inventory.write, "which belongs to no package")

    def test_missing_depfiles_fail(self) -> None:
        shutil.rmtree(self.fixture.build)
        self.assert_fails(inventory.write, "dart2js.d is missing")

    def test_an_embedded_npm_package_without_a_license_fails(self) -> None:
        self.fixture.put_map(["webpack://gstwebrtc-api/./node_modules/left-pad/index.js"])
        self.assert_fails(inventory.write, "embeds the npm package left-pad")

    def test_wasm_crates_need_the_regenerated_native_inventory(self) -> None:
        path = self.fixture.project / "assets/licenses/third-party-licenses.json"
        index = json.loads(path.read_text())
        for crate in index["components"]:
            crate.pop("wasm_roots", None)
        path.write_text(json.dumps(index))
        self.assert_fails(inventory.write, "records no wasm32 crate of oxidant; regenerate it")

    def test_a_named_shipped_text_that_is_missing_fails(self) -> None:
        (self.fixture.app / "pkg/LICENSE").unlink()
        self.assert_fails(inventory.write, "pkg/LICENSE is named as a license text but not shipped")

    def test_a_tampered_or_stray_store_file_fails(self) -> None:
        self.write_ok()
        chunk = self.fixture.app / inventory.STORE / "texts-1.json"
        texts = json.loads(chunk.read_text())
        texts[next(iter(texts))] = "edited"
        chunk.write_text(json.dumps(texts))
        self.assert_fails(inventory.check, "texts-1.json does not hold the texts")
        self.fixture.put(f"{inventory.STORE}/texts-9.json", "{}")
        self.assert_fails(inventory.check, "texts-9.json is no file of the inventory")

    def test_a_check_without_an_inventory_fails(self) -> None:
        self.assert_fails(inventory.check, "index.json is missing")

    def test_a_pinned_text_that_changed_fails(self) -> None:
        table = json.loads(inventory.TABLE.read_text())
        next(r for r in table["components"] if r["id"] == "sqlite3-wasm")["texts"][0]["sha256"] = "0" * 64
        changed = self.fixture.root / "table.json"
        changed.write_text(json.dumps(table))
        _, errors = inventory.write(self.fixture.app, self.fixture.project, changed)
        self.assertTrue(any("does not match its pinned sha256" in error for error in errors), errors)

    def test_the_command_line_passes_and_fails(self) -> None:
        args = ["--app", str(self.fixture.app), "--project", str(self.fixture.project)]
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(0, inventory.main(["--write", *args]))
        self.assertIn("WEB-LICENSES PASS", out.getvalue())
        self.fixture.put("late.txt", "x")
        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(1, inventory.main(["--check", *args]))
        self.assertIn("WEB-LICENSES FAIL: late.txt", err.getvalue())


class ParserTest(unittest.TestCase):
    def test_notices_split_like_the_license_registry(self) -> None:
        blocks = inventory.parse_notices(NOTICES)
        self.assertEqual(("skia", "harfbuzz"), blocks[3][0])
        self.assertEqual("BSD, Google", blocks[3][1])

    def test_a_depfile_keeps_escaped_spaces(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "x.d"
            path.write_text("/b/main.dart.js: /a/one.dart /a/two\\ words.dart \\\n /a/three.dart\n")
            self.assertEqual(["/a/one.dart", "/a/two words.dart", "/a/three.dart"], inventory.depfile_inputs(path))

    def test_globs_keep_single_stars_within_a_segment(self) -> None:
        self.assertTrue(inventory.glob_match("canvaskit/chromium/canvaskit.wasm", ["canvaskit/**"]))
        self.assertTrue(inventory.glob_match("a/b/kataglyphis_vision_core_web.js", ["**/kataglyphis_vision_core_web.js"]))
        self.assertTrue(inventory.glob_match("kataglyphis_vision_core_web.js", ["**/kataglyphis_vision_core_web.js"]))
        self.assertFalse(inventory.glob_match("icons/sub/a.png", ["icons/*"]))
        self.assertFalse(inventory.glob_match("mainxdart.js", ["main.dart.js"]))


if __name__ == "__main__":
    unittest.main()

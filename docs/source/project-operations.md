# Project Operations

Operational guide for contributors and maintainers.

## Daily Developer Flow

1. Update branch and submodules.
2. Run local checks (`flutter analyze`, selected tests, docs generation).
3. Verify at least one target runtime (web, linux, windows, or android).
4. Open pull request with clear scope and verification notes.

## Quality Gates

### Static checks

```bash
dart analyze
dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
```

**Never `dart format .`.** It ignores `analysis_options.yaml` entirely, so the
recursive walk reaches `flutter/`, `third_party/` and `build/` — directories
`dart format` cannot be told to skip. It is not theoretical: back when the lanes
installed the Flutter SDK *inside* the mounted workspace, run 33810449411
(2026-09-03) reported `Formatted 7404 files (627 changed)` with 604 of them
under `flutter/`. That alone fails `--set-exit-if-changed`, and it rewrote the
SDK on disk on the way.

Both lanes list tracked files instead — `code_quality_find_dart_files` on Linux,
`Get-ProjectDartFiles` on Windows, the same 60 files — which is what the command
above reproduces. Keep the tracked-file listing even now that the SDK comes from
`/opt/flutter` in the image: a stray `flutter/` from an older run is git-ignored
and still on disk, and `third_party/` and `build/` would be walked regardless.

`dart analyze` is **not** affected and never was: it honours the
`analyzer.exclude` list in `analysis_options.yaml`, which already names
`flutter/**`, `third_party/**` and `rust_builder/**`. `dart format` ignores that
file entirely — which is the whole reason the file list has to be built outside
it, and why the two helpers use exactly those three exclusions.

### Lint gates (shell, workflows, secrets)

```bash
bash scripts/linux/run-lint-gates.sh
```

The exact command the `lint` job of `dart_on_native_linux.yml` runs — shellcheck,
actionlint (plus the CI image-reference check) and the gitleaks secret scan, all
three bootstrapped pinned from ANTfrastructure, all three run even after one fails.
These used to exist only as `run:` blocks inside the workflow, so a failing merge
gate could not be reproduced locally at all. The gitleaks arm self-tests first: an
empty tree must scan clean and a planted token must be reported and must make the
gate exit non-zero, so "found nothing" cannot be confused with "never ran".

The shared-config drift check is one of that command's gates, not a separate
step: `bash scripts/linux/run-lint-gates.sh` runs it. The workflow's `pwsh`
`Sync-SharedConfig.ps1 -Check` step is the PowerShell twin of the same gate,
kept so both halves stay exercised and are required to agree.

### The CMake format gate

The gate is **fatal** in the native-Linux lane and the Android lane, and
`run_cmake_format_check` takes no arguments at all: it used to accept a
strictness flag and ignore its own verdict when that flag was false, so it now
errors (exit 2) if handed one rather than letting a stale caller pass silently.
That is safe for a measured reason, not an optimistic one — the gate's 13 files
are already clean and the native-Linux lane has passed `--strict-checks true`
since fc8b65c, so the Android lane can only catch drift that already blocks the
merge on the other lane. The web lane builds no native CMake code and does not
run it.

**The CMake format gate covers hand-maintained CMake only — 13 files today.**
Both lanes build the same list (`run_cmake_format_check` in
`scripts/linux/lib/container-steps.sh`; the `CMake Format Verification` step in
`Build-Windows.ps1`) and both exclude, each verified generated or vendored:
`third_party/` and `build/`; `*/flutter/CMakeLists.txt` (header: "It should not
be edited"); `*/generated_plugins.cmake` ("Generated file, do not edit");
`*/ephemeral/` (rewritten on every `pub get`); `*/.cxx/` (Android Gradle's CMake
build trees); `*/.plugin_symlinks/` (pub's junction farm);
`rust_builder/cargokit/` (vendored — its README opens with "copied from
Cargokit"); `.venv/` (created by the gate's own bootstrap). Do not widen the
gate onto any of those: it would fight the generator or upstream.

`.cmake-format.yaml` at the root is the consumer copy of ANTfrastructure's
canonical config — `shared/config/README.md` owns why it is a copy. Refresh it
with `pwsh -File third_party/ANTfrastructure/shared/config/Sync-SharedConfig.ps1
-RepoRoot . -Write` (or `bash
third_party/ANTfrastructure/shared/config/sync-shared-config.sh --repo-root .
--write`) — no `-Ignore`: what this repo takes is declared in
[`.antfrastructure-shared.manifest`](.antfrastructure-shared.manifest), three rows,
and the scripts refuse `-Ignore` while that file exists. cmake-format itself
comes from `PATH` or a
uv venv fed by ANTfrastructure's pinned
`third_party/ANTfrastructure/linux/scripts/cmake-format.requirements.txt` — there
is no root `requirements.txt` (`pyyaml` sits in that pinned set because
cmake-format cannot read its own YAML config without it). Both bootstraps read
that one file: `run_cmake_format_check` in
`scripts/linux/lib/container-steps.sh` and the "CMake Format Verification" step
in `scripts/windows/Build-Windows.ps1`. The config's
`line_ending: unix` is why `.gitattributes` pins `CMakeLists.txt` and `*.cmake`
to LF — a `core.autocrlf=true` checkout would otherwise fail `--check` on every
file.

### Tests

```bash
flutter test
flutter test integration_test/simple_test.dart
```

## Documentation Workflow

Generate docs:

```bash
bash scripts/linux/generate-docs.sh
```

Preview docs:

```bash
dhttpd --path doc/api --host 127.0.0.1 --port 8080
```

### There is no Sphinx site here

`docs/source/` is Markdown source for exactly one consumer: the `dart doc` site
that `scripts/linux/generate-docs.sh` builds, which stages each guide listed in
that script's `DARTDOC_BUILD_GUIDES` array. The `docs/Makefile`, `docs/make.bat`,
`docs/source/conf.py` and `docs/source/index.rst` that used to sit beside it were
scaffolding from `sphinx-quickstart` that no lane, workflow or script ever
invoked; they were deleted on 2026-09-15 and git history keeps them. Add a guide
by adding the file and one array row, not by reviving a second doc builder.

If a Sphinx site is ever wanted, take the shared theme rather than the
standalone `press` theme the deleted `conf.py` named: it lives in
[DocumANTation](https://github.com/Kataglyphis/DocumANTation), consumers vendor
it as `third_party/DocumANTation` and install it through a docs-scoped
requirements file (`-e ./third_party/DocumANTation/sphinx-kataglyphis-theme`),
and `conf.py` then reduces to
`from sphinx_kataglyphis import setup_theme; setup_theme(globals(), ...)`.

This repo carries no root `requirements.txt`: the only thing it ever fed was the
cmake-format gate, which now takes its pinned bootstrap set from
`third_party/ANTfrastructure/linux/scripts/cmake-format.requirements.txt`. A docs
requirements file would be docs-scoped for the same reason — an unpinned root
file next to a pinned shared one is exactly the drift that removal closed.

## Large tracked binaries

Measured 2026-09-15: **148 MiB across 451 tracked files**, of which roughly
141 MiB is binary assets. The inventory, so nobody has to re-derive it:

| What | Size | Why it is tracked |
|------|------|-------------------|
| `dummy_assets/` | 79.7 MiB, 16 files | Fixture corpus mirroring the shape of `assets/`. 82.9 MiB of it is two PDFs, `documents/thesis/{Master,Bachelor}_Thesis.pdf`. **Nothing references it** — not `pubspec.yaml`'s asset list, not `lib/`, not a test, not a script. It is sample content for trying the document pages against. |
| `assets/fonts/Noto_Sans/` | 47.9 MiB, 76 files | The complete Noto Sans family as shipped by Google Fonts: 2 variable fonts plus all 72 static faces. `pubspec.yaml` declares **4** of them (Regular, Italic, Bold, BoldItalic). The other 72 files are the download, not a requirement. |
| `assets/videos/funnyandsummy.mp4` | 12.3 MiB | Demo clip. Not in `pubspec.yaml`'s asset list and not referenced from `lib/`. |
| `assets/icons/kataglyphis_app_icon.png` | 1.9 MiB | Load-bearing: `flutter_launcher_icons` generates every platform icon set from it (`pubspec.yaml` names it five times), so it must stay at source resolution. |
| `images/overview.gif` | 1.6 MiB | README illustration. |
| `web/sqlite3.wasm` | 0.7 MiB | The sqlite3 WASM build the web app loads. Fetched and checksum-verified by ANTfrastructure's `setup-sqlite3-wasm.sh`; the committed copy is a convenience, and it has been wrong before (see [Getting Started](getting-started.md)). |

**The history is not being rewritten.** No `git filter-repo`, no BFG, no LFS
migration. Four repositories pin this one by gitlink or consume it in a
recursive checkout; a rewrite changes every commit sha and every one of those
pins, plus every clone anyone holds, to save clone time nobody has complained
about. The decision is to document what is there and stop it growing.

Stopping it growing is `.gitignore`: media, archives, documents and model
weights are ignored by extension. Already-tracked files are unaffected —
`.gitignore` never untracks anything — so this changes nothing about the table
above. It changes the next one: a new asset the app genuinely ships is added
with `git add -f <path>` and earns a row here saying what it is for. Having to
type `-f` is the whole mechanism.

If the tree is ever trimmed, the order is obvious from the table and needs no
history rewrite to be worth doing: the 72 undeclared font faces, then
`dummy_assets/`, then the video. All three are deletions in a normal commit.

## CI/CD Notes

- Linux native, Windows native, Web, and Android pipelines are available via GitHub Actions.
- Keep generated artifacts deterministic to reduce CI diffs and flaky builds.
- Prefer script-driven commands from `scripts/` over ad-hoc commands for reproducibility.

## Release Hygiene

- Keep dependency upgrades and feature changes in separate pull requests.
- Regenerate bridge code when Rust API signatures change.
- Update docs in the same pull request for any user-facing behavior changes.

## Dependency upgrades, in detail

AGENTS.md § 5 has the commands and the report-first rule. These are the
behaviours that surprise people.

**Why the container still downloads its own Node.** Renovate's `engines.node`
range excludes the image's Node, so the bootstrap pulls a checksum-pinned one
onto the `kataglyphis-renovate-cache` volume — the versions and the rationale
are ANTfrastructure's:
[`docs/dependency-updates.md`](third_party/ANTfrastructure/docs/dependency-updates.md).

**The runner passes `gh`'s token as `GITHUB_COM_TOKEN` when `gh` is
authenticated.** Without it Renovate's GitHub API lookups are rate-limited and it
can report stale GitHub Actions as up to date — DocumANTation's action majors
were invisible until a token was supplied.

Renovate is a local CLI and only **detects** — `--platform=local` cannot write —
so the `--apply` half is this repo's own code: git for gitlinks and a located
line rewrite for the manifests it reported. Managers default to **every manager
whose file patterns match this tree** (eight today), so `--managers` narrows the
run rather than enabling it. `--apply` needs the git that *wrote* the working
tree; the script sorts that out itself and refuses up front rather than
half-applying. Why any of it —
[`third_party/ANTfrastructure/docs/dependency-updates.md`](third_party/ANTfrastructure/docs/dependency-updates.md).

## Troubleshooting

### The Linux lane, locally

`scripts/windows/Invoke-LinuxLane.ps1` runs the same image, script and arguments
as the Linux workflows; AGENTS.md § 5 holds the lane table and the rules. What
follows is the evidence behind those rules — each cost at least one run to find,
and each has a symptom that names something other than its cause.

**arm64 locally needs QEMU registered once per VM boot.** Rancher's VM starts
with no emulators at all — `binfmt` reports `"emulators": null` and only
`linux/amd64` variants under `supported`, so an arm64 container would run
x86-64 binaries and die exactly as CI did before the image went multi-arch
(`rustc: 1: ELF: not found`). Register it with:

```powershell
nerdctl run --rm --privileged tonistiigi/binfmt --install arm64
nerdctl run --rm --privileged tonistiigi/binfmt          # verify: qemu-aarch64 listed
nerdctl run --rm --platform linux/arm64 alpine uname -m  # verify: aarch64
```

Like the `D:` mount in containerd's namespace, this does not survive a VM
restart. The arm64 layers are a separate pull — about 6 GB over the wire, 30 GB
on disk next to the amd64 copy (`nerdctl pull --platform linux/arm64 …`) — and
every compile then runs under emulation, so expect it to be far slower than the
native x64 lane.

**Emulated arm64 produces tar and deb, never flatpak or AppImage.** Both fail
inside `qemu-user`, for reasons that have nothing to do with this repo or the
image, and both were verified 2026-09-05 after a full arm64 build that compiled
Rust and C++ without a single error:

- `bwrap: Creating new namespace failed, likely because the kernel does not
  support user namespaces` — the kernel does support them
  (`/proc/sys/user/max_user_namespaces` is 123100) and `--privileged` is passed;
  qemu-user simply does not carry `unshare(CLONE_NEWUSER)` through, and
  flatpak-builder sandboxes every module with bubblewrap.
- `/usr/local/bin/appimagetool: cannot execute binary file: Exec format error` —
  the binary is the correct architecture (`ELF aarch64, static-pie linked`);
  qemu-user cannot load static-PIE executables.

CI is unaffected: its arm64 row runs on a real `ubuntu-26.04-arm` runner, so
neither restriction applies. Locally, treat a failing flatpak/AppImage step on
arm64 as expected and check the two messages above before investigating.

**`error: fchmod` after `Pruning cache` is not the prune.** That combination cost
hours. `Pruning cache` is merely flatpak-builder's *last* output line; it exits
0. The error underneath came from `flatpak build-bundle`, which chmods the file
it writes — and that file was `out/…flatpak`, on the host mount. The bundle is
now written under `/tmp/flatpak-work` and copied out afterwards. `set -x` around
the function answered this in one run, after three rounds of eliminating
plausible-looking causes had only moved the symptom.

The step also does **not** gate on flatpak-builder's exit code any more. It asks
`ostree --repo=<repo> refs` whether the app is committed, because the export can
be complete while a later stage fails. The exit code is reported in the warning,
never used as the verdict.

All four formats build locally on x64: tar, deb, flatpak and AppImage. The
appimagetool mode-711 problem that used to break the last one is fixed in the
image.

**`-v name:/path` is not a named volume on Windows nerdctl.** It is a bind of
`$PWD/name`, created silently, and `nerdctl volume create` beforehand changes
nothing — the volume is made and never mounted. Proof: after five lane runs,
`%TEMP%` held `kataglyphis-lane-native-x64-workspace-build/` and four siblings,
729 MB each, while the volume of that name mounted through
`--mount type=volume,…` was empty. One run started from the repo root even left
a 151 MB directory of that name *in the checkout*. So the whole point of the
volumes — keeping the write-heavy build tree off drvfs — was never in effect
locally, and the failures it prevents were only avoided because the packaging
steps had already been moved to `/tmp`. `Invoke-LinuxLane.ps1` now always uses
`--mount type=volume,source=…,target=…`, which nerdctl cannot reinterpret as a
path. CI is unaffected: there the Linux engine resolves the short form
correctly.

`flutter clean` then logs `Failed to remove /workspace/build … Device or
resource busy (errno 16)` on every run and keeps going: it empties the
directory but cannot unlink the mount point itself. Cosmetic, and the direct
consequence of mounting `build/` — not a failure to chase.

There is no separate host-side driver any more. The legacy
`ci-dart-on-native-linux.sh` / `ci-dart-build-android-app.sh` pair and their
`ci-common.sh` were removed on 2026-09-04: no workflow ever referenced them,
they carried a third copy of the CodeQL logic, and they re-implemented what CI
actually runs instead of invoking it. Use `Invoke-LinuxLane.ps1` (§ 5), which
runs the very script CI runs.

**Flutter comes from the image, and this repo does not have an opinion about

Why it went: the lanes were re-running ANTfrastructure's `setup-flutter.sh` at
*run* time. That script is a build-stage script — its last step strips
`bin/cache` on purpose — so every Android run re-extracted Flutter over the
image's copy and then re-downloaded the 227 MB Dart SDK it had just deleted.
Upstream now returns early when the requested version is already bootstrapped,
and this repo no longer calls it at all.

That flip is safe for a measured reason, not an optimistic one: the gate's 13 files
are already clean under this repo's `.cmake-format.yaml`, and the native-Linux lane
has passed `--strict-checks true` since fc8b65c — so any drift the Android lane now
catches is drift that already blocks the merge on the other lane. Wrap the call in
`run_gate` when you want the batch to decide, rather than reaching for a flag.


`--flutter-dir` only says *where* to look; it defaults to `/opt/flutter`. There
is no `--install-flutter` and no `--flutter-version` — see *Flutter comes from
the image* below.

which version.** It used to: three lanes resolved `FLUTTER_VERSION` and
`FLUTTER_SDK_SHA256` out of ANTfrastructure's `versions.env`, exported the sha, and
handed both to an installer. That machinery is gone — `resolve_flutter_pin`,
`setup_flutter_sdk`, `install-flutter.sh` and the `--flutter-version` /
`--install-flutter` flags with it. `assert_flutter_available` replaces all of
it: it fails if `--flutter-dir` holds no `bin/flutter`, and otherwise reports
the `frameworkVersion` it found and moves on.

To change the Flutter version, change the image.

### flutter_rust_bridge Version Mismatch

If you encounter this error at runtime:
```
oxidant's codegen version (2.11.1) should be the same as runtime version (2.12.0)
```

**Cause:** The generated Dart binding files (in `lib/src/rust/`) are out of sync with the `pubspec.yaml` dependency version.

**Fix:** Regenerate the Flutter Rust Bridge bindings:

```bash
flutter_rust_bridge_codegen generate
```

It is a cargo binary baked into the build image, not a pub dependency — on a
bare host install it first, at the version this repo pins rather than at latest:
`cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen` (the
`flutter_rust_bridge` pin in `third_party/OxidANT/Cargo.toml`; the image exports
the same number as `FLUTTER_RUST_BRIDGE_VERSION`). Installing latest is how the
mismatch above happens in the first place.

Then rebuild the project:
```bash
# For Windows
.\scripts\windows\Build-Windows.ps1 -BuildRootDir build
```

**Prevention:** Always regenerate bindings after updating `flutter_rust_bridge` version in `pubspec.yaml` or modifying Rust API signatures.

## Contribution Checklist

- [ ] Scope is focused and documented.
- [ ] Build/test commands were run locally.
- [ ] Relevant docs were updated.
- [ ] No secrets, machine-specific paths, or temporary artifacts were committed.
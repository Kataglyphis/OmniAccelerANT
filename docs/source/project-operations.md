# Project Operations

Operational guide for contributors and maintainers.

## Daily Developer Flow

1. Update branch and submodules: `git pull` and
   `git submodule update --checkout --recursive` give the recorded commits;
   `bash third_party/ANTfrastructure/linux/scripts/git-sync-branches.sh` puts
   every checkout, third-party ones included, on its branch tip instead (AGENTS.md § 3).
2. Run local checks (`flutter analyze`, selected tests, docs generation).
3. Verify at least one target runtime (web, linux, windows, or android).
4. Open pull request with clear scope and verification notes.

## Quality Gates

### Static checks

```bash
dart analyze
dart format --output=none --set-exit-if-changed $(git ls-files -- '*.dart' ':!:rust_builder/**')
```

**Never `dart format .`.** It ignores `analysis_options.yaml` entirely, so the
recursive walk reaches `flutter/`, `third_party/` and `build/` — directories
`dart format` cannot be told to skip. It is not theoretical: back when the lanes
installed the Flutter SDK *inside* the mounted workspace, run 33810449411
(2026-09-03) reported `Formatted 7404 files (627 changed)` with 604 of them
under `flutter/`. That alone fails `--set-exit-if-changed`, and it rewrote the
SDK on disk on the way.

Both lanes list tracked files instead — `code_quality_find_dart_files` on Linux,
`Get-ProjectDartFiles` on Windows, the same list — which is what the command
above reproduces (tracked files minus `rust_builder/`, Cargokit's 19; `flutter/`
is untracked and `third_party/` holds gitlinks, so `git ls-files` lists neither).
Keep the tracked-file listing even now that the SDK comes from
`/opt/flutter` in the image: a stray `flutter/` from an older run is git-ignored
and still on disk, and `third_party/` and `build/` would be walked regardless.

`dart analyze` is **not** affected and never was: it honours the
`analyzer.exclude` list in `analysis_options.yaml`, which already names
`flutter/**`, `third_party/**` and `rust_builder/**`. `dart format` ignores that
file entirely — which is the whole reason the file list has to be built outside
it, and why the two helpers exclude those three trees (plus build output and
the old `ExternalLib/`).

### Lint gates (shell, workflows, secrets)

```bash
bash scripts/linux/run-lint-gates.sh
```

The same gates the `lint` job of `linux-x64.yml` runs: since 2026-09-15 that job
calls ANTfrastructure's reusable `lint-gates.yml` with `ratchets: true`, and both
it and this wrapper run the hub's `linux/scripts/run-lint-gates.sh` over this
tree with `--exclude third_party --ratchets`. The gates are shell lint, workflow
lint (plus the CI image-reference check), the gitleaks secret scan, Python lint,
the shared-config drift check and the consumer pin-forwarding check, all
bootstrapped pinned from ANTfrastructure and all run even after one fails;
`--ratchets` adds the eight measurement gates (freeze files: the `*.allow` at the
root) and the doc-links gate over this repo's Markdown. These used to exist only
as `run:` blocks inside the workflow, so a failing merge gate could not be
reproduced locally at all. The gitleaks arm self-tests first: an empty tree must
scan clean and a planted token must be reported and must make the gate exit
non-zero, so "found nothing" cannot be confused with "never ran".

The shared-config drift check is one of that command's gates, not a separate
step: `bash scripts/linux/run-lint-gates.sh` runs it. The workflow's
`shared-config` job (`pwsh` `Sync-SharedConfig.ps1 -Check`) is the PowerShell
twin of the same gate, kept so both halves stay exercised and are required to
agree.

### The CMake format gate

The gate is **fatal** in the native-Linux lane and the Android lane, and
`run_cmake_format_check` takes no arguments at all: it used to accept a
strictness flag and ignore its own verdict when that flag was false, so it now
errors (exit 2) if handed one rather than letting a stale caller pass silently.
That is safe for a measured reason, not an optimistic one — the gate's 13 files
are already clean and the native-Linux lane has passed `--strict-checks true`
since fc8b65c, so the Android lane can only catch drift that already blocks the
merge on the other lane. Wrap the call in `run_gate` when you want the batch to
decide, rather than reaching for a flag. The web lane builds no native CMake
code and does not run it.

**The CMake format gate covers hand-maintained CMake only — 13 files today.**
Both lanes build the same list (`run_cmake_format_check` in
`scripts/linux/lib/container-steps.sh`; the `CMake Format Verification` step in
`Build-Windows.ps1`) and both exclude, each verified generated or vendored:
`third_party/` and `build/`; `*/flutter/CMakeLists.txt` (header: "It should not
be edited"); `*/generated_plugins.cmake` ("Generated file, do not edit");
`*/ephemeral/` (rewritten on every `pub get`); `*/.cxx/` (Android Gradle's CMake
build trees); `*/.plugin_symlinks/` (pub's junction farm);
`rust_builder/cargokit/` (vendored — its README opens with "copied from
Cargokit"); `.venv/` (created by the gate's own bootstrap). The Linux walk also
excludes `.pub-cache/`, pub's download cache, which sits in the tree since
`PUB_CACHE` moved to `<repo>/.pub-cache`; the Windows step lists tracked files
only, so neither of the last two can reach it. Do not widen the
gate onto any of those: it would fight the generator or upstream.

`.cmake-format.yaml` at the root is the consumer copy of ANTfrastructure's
canonical config — `shared/config/README.md` owns why it is a copy. Refresh it
with `pwsh -File third_party/ANTfrastructure/shared/config/Sync-SharedConfig.ps1
-RepoRoot . -Write` (or `bash
third_party/ANTfrastructure/shared/config/sync-shared-config.sh --repo-root .
--write`) — no `-Ignore`: what this repo takes is declared in
[`.antfrastructure-shared.manifest`](../../.antfrastructure-shared.manifest), four rows,
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

### The plugin's C++ format gate

`scripts/linux/check-plugin-cpp-format.sh` checks the native plugin's tracked,
hand-written C/C++: 15 files under `android/`, `linux/` and `windows/` of
`packages/kataglyphis_native_inference`. It runs `clang-format --dry-run
-Werror` through the hub's `code_quality_check_clang_format`, never rewrites,
and fails on a single deviating file. It refuses to grade (exit 2, also red) on
three conditions:

- a clang-format other than the hub's `LLVM_RELEASE` (the environment's value,
  else the pinned `versions.env`), because releases format differently;
- no `.clang-format` beside the sources, where clang-format would fall back to
  LLVM style without a word;
- no tracked files at all.

`example/*/runner/` is Flutter's generated scaffolding and is not graded, just
as the comment-size gate skips it.

The config is `packages/kataglyphis_native_inference/.clang-format`, the hub's
canonical one, declared in `.antfrastructure-shared.manifest` with that path:
the drift gate watches it, and the app's own generated runner sources stay
outside it. The gate runs in the native-Linux lane's code-quality batch on both
architectures, beside `scripts/linux/tests/test-check-plugin-cpp-format.sh`,
which plants a deviation and provokes each refusal. Windows has no C++ format
step.

To clear a red run, rewrite the named files with `clang-format -i` from the
image (23.1.3). The canonical config leaves comments as written
(`ReflowComments: Never` since hub 0b774f12, 2026-10-12): reflow put a comment
past 120 columns onto a second line, which the comment-size gate rejects.
The 2026-10-12 sweep is in `.git-blame-ignore-revs`.

### Tests

What each kind of test proves, how to run it and what is not covered yet:
[Testing](testing.md). Which lane runs which test is the table in AGENTS.md
§ *What each lane tests*.

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

Measured 2026-10-12: **6.6 MiB across 424 tracked files**, after that day removed
every tracked binary nothing referenced (below); 2026-09-15 counted 148 MiB across
451. The inventory, so nobody has to re-derive it:

| What | Size | Why it is tracked |
|------|------|-------------------|
| `assets/icons/kataglyphis_app_icon.png` | 1.9 MiB | Load-bearing: `flutter_launcher_icons` generates every platform icon set from it (`pubspec.yaml` names it four times, one of them msix's `logo_path`), so it must stay at source resolution. |
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

**The trim happened on 2026-10-12, in normal commits.** What went:
- all 76 Noto Sans files (47.9 MiB), the four faces `pubspec.yaml` declared included.
  No code ever rendered with the family (the theme font is ANThology's Roboto), and
  Flutter web downloaded those four, about 1.2 MB, before every cold load's first frame;
- `dummy_assets/` (79.7 MiB, 16 files, two thesis PDFs most of it), the fixture corpus
  nothing read;
- `assets/videos/funnyandsummy.mp4` (12.3 MiB), in no asset list;
- `assets/images/barbell.png`, the folder's last file, and the folder's `pubspec.yaml`
  entry with it;
- gstwebrtc-api's demo page `web/javascript/webrtc/index.html` with the UMD build only
  it loaded. Every web build had published both; the app imports the ESM module.

What the table lists now is load-bearing.

## Serving the web build

Two servers, one contract. Both send `Cross-Origin-Opener-Policy: same-origin`
and `Cross-Origin-Embedder-Policy: require-corp`, and both must serve `.wasm` as
`application/wasm`, because `WebAssembly.compileStreaming()` refuses anything
else. The headers make the page cross-origin isolated, which only the Rust
core's shared-memory wasm (`pkg/`) needs, and only in Firefox and Safari. The
Stream page streams without them, and on web `main()` boots without the core
when it does not load (`lib/src/boot/rust_core.dart`), so `serve.sh --http`
serves a plain-HTTP LAN page with no certificate warning; there only the About
page's Rust demo goes dark.

| Where | Config |
| --- | --- |
| The ObservANT demo, any board | `scripts/linux/observant/serve.sh` (generates its own nginx.conf) |
| The hosted site | [`nginx.conf`](../../third_party/ANTfrastructure/linux/webserver/nginx.conf) + [`security-headers.conf`](../../third_party/ANTfrastructure/linux/webserver/security-headers.conf) |

**There is no `web/.htaccess` any more.** It was deleted on 2026-09-16: the site
is served by nginx, which never reads one, so every rule in it — the headers, the
wasm MIME type, the caching — was inert. Keeping it was worse than not having it,
because it read like the deployment's source of truth while changing nothing. Two
things it got wrong are worth recording so they are not reintroduced: it sent
`Cross-Origin-Embedder-Policy: credentialless`, which Safari does not implement,
and it matched `\.(js|wasm|…)$` with `max-age=31536000, immutable`, which covers
`main.dart.js`, `flutter_bootstrap.js` and `main.dart.wasm` — none of which are
content-hashed, so a redeploy would never have reached a returning visitor.
Upstream's nginx config gets both right.

`web/index.html` also carries three `<meta http-equiv>` COOP/COEP tags' worth of
explanation and no tags: browsers honour those headers only as real HTTP
responses, never as `<meta>`, so the ones that used to sit there had never done
anything.

## The web lane's CanvasKit source

`scripts/linux/ci/ci-container-run-web-linux.sh` builds with
`--no-web-resources-cdn`. The flag defaults to **on** in `flutter build web`,
and leaving it on bakes `https://www.gstatic.com/flutter-canvaskit/<engineRevision>`
into two independent places:

1. the `flutter.js` loader's base URL — a single URL shared by the canvaskit and
   skwasm branches, so `--wasm` does **not** escape it; and
2. the `FLUTTER_WEB_CANVASKIT_URL` dart-define compiled into the app.

The renderer files ship in `build/web/canvaskit/` either way, so the default
buys nothing but a CDN round trip — and the whole point of the ObservANT
runbook is a Raspberry Pi serving `build/web` on a LAN. A host with no route to
`gstatic.com` renders a blank page with nothing in the console.

**Verify it with the bootstrap key, not with grep:**

```bash
grep -o '"useLocalCanvasKit":[a-z]*' build/web/flutter_bootstrap.js   # => "useLocalCanvasKit":true
```

The key is emitted **only** when true, so its absence is the regression.

**Do not verify by grepping for `gstatic`.** `flutter.js` and
`flutter_bootstrap.js` each keep exactly one hit whether the flag is on or off,
because the URL is a string literal in the *untaken* arm of the loader's own
ternary:

```js
e.engineRevision && !e.useLocalCanvasKit
  ? W("https://www.gstatic.com/flutter-canvaskit", e.engineRevision)
  : "canvaskit"
```

`useLocalCanvasKit` flips that branch to the local `canvaskit` directory; it does
not delete the string. Measured 2026-09-16 on a `--wasm` build: 1 hit in each of
those two files before and after, 0 in `main.dart.mjs`. A "gstatic must be 0"
check would fail forever and teach the next reader that the flag does not work.

## CI/CD Notes

- Linux native, Windows native, Web, and Android pipelines are available via GitHub Actions.
- Keep generated artifacts deterministic to reduce CI diffs and flaky builds.
- Prefer script-driven commands from `scripts/` over ad-hoc commands for reproducibility.

## Release Hygiene

**Branches.** `develop` is the default branch and the only one work lands on. `main` is the
release branch: it moves only when the owner merges a release (the latest tag is `1.1.0+1`), so
between releases it trails `develop` by design (416 commits on 2026-10-05). Nothing deploys from
`main` alone. Every lane runs on pushes to either branch, except that a push touching only
`docs/**` or root-level `*.md` runs Linux x64 alone (`paths-ignore`, 2026-10-12), and the API
docs deploy over FTP on any push. Neither branch is protected, by the owner's decision of 2026-10-05.

- Keep dependency upgrades and feature changes in separate pull requests.
- Regenerate bridge code when Rust API signatures change.
- Update docs in the same pull request for any user-facing behavior changes.

## Dependency upgrades, in detail

AGENTS.md § 5 (Build, run, test) has the commands and the report-first rule. These are the
behaviours that surprise people.

**Why the container still downloads its own Node.** Renovate's `engines.node`
range excludes the image's Node, so the bootstrap pulls a checksum-pinned one
onto the `kataglyphis-renovate-cache` volume — the versions and the rationale
are ANTfrastructure's:
[`third_party/ANTfrastructure/docs/dependency-updates.md`](../../third_party/ANTfrastructure/docs/dependency-updates.md).

**The runner passes `gh`'s token as `GITHUB_COM_TOKEN` when `gh` is
authenticated.** Without it Renovate's GitHub API lookups are rate-limited and it
can report stale GitHub Actions as up to date — DocumANTation's action majors
were invisible until a token was supplied.

Renovate is a local CLI and only **detects** — `--platform=local` cannot write —
so the `--apply` half is the family's own code, ANTfrastructure's
`renovate-local.sh` behind this repo's wrapper: git for gitlinks and a located
line rewrite for the manifests it reported (`pubspec.yaml` included, with its
lockfile refreshed). Managers default to **every manager
whose file patterns match this tree** (eight today), so `--managers` narrows the
run rather than enabling it. `--apply` needs the git that *wrote* the working
tree; the script sorts that out itself and refuses up front rather than
half-applying. Why any of it —
[`third_party/ANTfrastructure/docs/dependency-updates.md`](../../third_party/ANTfrastructure/docs/dependency-updates.md).

## The Linux lanes, run locally

The detail behind the rules in AGENTS.md's § 5, moved here on 2026-10-15 to keep AGENTS.md
short.

Each entry mirrors its workflow's `extra-args` and `script`, so change the pair
together. The argument sets are meant to match exactly — the android lane also
matches in *not* passing `--privileged`. The native lane's step lives in
`reusable-linux.yml`, and its values in the `with:` block of the per-arch
caller; keep that block flat `key: value` lines, which is what `-CheckParity`
reads.

The native lane sets `KATAGLYPHIS_RUST_FEATURES=gstreamer,onnxruntime_dynamic`
before `flutter build linux` — set it to the empty string to opt out — and
`KATAGLYPHIS_PLUGIN_TESTS=1`, which `linux/CMakeLists.txt` turns into the plugin's
gtest target. For a release build it runs `bundle-runtime-closure.sh`, then the
`knt ABI`, `runtime closure` and `plugin gtest` gates, then the launch smoke and
the integration test under the image's `xvfb-run`, all between the build and
packaging.

**`KATAGLYPHIS_LINKER=lld|mold` is an opt-in for the native lane** (2026-10-05):
`.\scripts\windows\Invoke-LinuxLane.ps1 -Env KATAGLYPHIS_LINKER=lld`. `setup_linker`
runs it after `export_toolchain_env`, so clang links the C++ and the host Rust target
with that linker. Unset leaves GNU ld for C++ and rust-lld for x64 Rust. The switch is
the hub's [`linker-select.sh`](../../third_party/ANTfrastructure/docs/shared-script-libraries.md#linker-selectsh--an-opt-in-linker);
it fails rather than falls back, and it fetches the pinned mold 3.0.0 when the image has
none. The measurement behind it is there too. lld is the useful value: about 1.3 s
off a Debug relink, and nothing off a ~48 s release app build, which mold does not
beat. CI never sets it, and the android and web lanes do not read it.

`Invoke-LinuxLane.ps1
-CheckParity` diffs the *values* it would send — `script` and `extra-args` —
against the lane's workflow (change driver and workflow together); for
`native` it grades `-Arch`'s own file, resolving `reusable-linux.yml`'s
`${{ inputs.* }}` from it. It runs before the engine is looked up, so it needs
no nerdctl and starts nothing. A real run refuses to start while another Linux
lane's container is up or a Windows build is running, and
`Build-Windows-Container.ps1` refuses while a Linux lane is up (`-Force`
overrides both; `scripts/windows/modules/WindowsLaneGuard.Common.psm1`). The two
lanes sit on two engines: the Windows build container is Stevedore's, idles on
`ping` between builds, and counts as busy only while a `pwsh` runs in it.

**arm64 locally needs QEMU registered once per VM boot**, and an emulated
arm64 run produces tar and deb but never flatpak or AppImage: `qemu-user` does
not carry `unshare(CLONE_NEWUSER)` through for bubblewrap, and cannot load the
static-PIE `appimagetool`. Neither restriction touches CI, whose arm64 build
(`linux-arm64.yml`) runs on a real `ubuntu-26.04-arm` runner. The `binfmt`
registration commands, the pull sizes, and both error messages verbatim:
[`docs/source/project-operations.md`](project-operations.md)
§ *The Linux lane, locally*.

**Everything write-heavy must stay off the host mount.** A bind-mounted Windows
drive cannot do `utime`, `chmod` or `fchmod` for the container uid, and each of
those surfaces as a different, misleading error:

| What | Where it lives now | Symptom when it did not |
| --- | --- | --- |
| CMake/ninja build tree | named volume on `/workspace/build` | — |
| pub's download cache | named volume on `/workspace/.pub-cache` | `Rename failed, path = '/workspace/.pub-cache/_temp/…' (OS Error: Permission denied, errno = 13)`, then `Failed to update packages` — **but only on a run that downloads something.** A warm cache resolves from disk and renames nothing, so the local lane passed for as long as nobody edited `pubspec.yaml` |
| cargo's target tree | named volume on `/workspace/third_party/OxidANT/target` | `error: failed to build archive at '…/libwasm_bindgen_macro_support-*.rlib': failed to remove temporary directory: Permission denied (os error 13) at path '…/out/.tmpXXXXXX.temp-archive'`. Same class as the row above, one verb over: the mount refuses the **remove**, not the write. The web lane hits it hardest because `-Z build-std` recompiles the standard library |
| flatpak repo, build tree, builder state, manifest staging **and the finished bundle** | `/tmp/flatpak-work` | `fchmod: Operation not permitted`, first from the OSTree repo, later from `build-bundle` |
| ccache / sccache | `/var/cache/{ccache,sccache}`, set by the image | `Can't initialize ccache use: Failed to set permissions` |

Only the finished artifacts are written into `out/`. This is ANTfrastructure's
documented rule for build directories and caches, applied to the packaging
steps as well.

**`pubspec.lock` cannot move off the mount, so its mtime can red the web lane.**
When a workspace member's `pubspec.yaml` is newer than the root `pubspec.lock`
(a submodule pull does that: on 2026-10-05 ANThology's was, by 19 s), the
`dart run` inside `flutter_rust_bridge_codegen build-web` re-validates and
touches the lock, and the mount refuses the `utime`: `FileSystemException:
Failed to set file modification time, path = '/workspace/pubspec.lock' (OS
Error: Operation not permitted, errno = 1)`. Touch the lock on the host —
`(Get-Item pubspec.lock).LastWriteTime = Get-Date` — and rerun; the next run
passed. CI's fresh clone never has the skew.

**The flatpak bundle is written under `/tmp/flatpak-work` and copied out**, and
the step asks `ostree --repo=<repo> refs` whether the app is committed rather
than trusting flatpak-builder's exit code. Both come out of one hunt —
`error: fchmod` after `Pruning cache`, which is not the prune — written up in
[`docs/source/project-operations.md`](project-operations.md)
§ *The Linux lane, locally*. All four formats build locally on x64.

It drives Rancher Desktop's `nerdctl` (found on `PATH`, else under
`%ProgramFiles%`), because that is the local Linux engine on this box; CI uses
`docker` through ANTfrastructure's `run-in-linux-container`. Everything inside the
container is identical.

**`-v name:/path` is not a named volume on Windows nerdctl.** It silently binds
`$PWD/name`, so `Invoke-LinuxLane.ps1` always spells the mount
`--mount type=volume,source=…,target=…`, which nerdctl cannot reinterpret as a
path. CI is unaffected. The measurement that settled it, and the cosmetic
`flutter clean … Device or resource busy (errno 16)` that mounting `build/`
produces on every run, are in
[`docs/source/project-operations.md`](project-operations.md)
§ *The Linux lane, locally*.

**Two traps, both of which produce a mount that resolves but is empty:** `D:`
must exist inside *containerd's own* mount namespace, which is not the distro's
and is gone after every VM restart — the fix is ANTfrastructure's
[`docs/rancher-desktop-linux-containers.md` § *An empty mount is not a missing drive*](../../third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#an-empty-mount-is-not-a-missing-drive)
— and the path you pass must be the **Windows** one (`D:\…`), because nerdctl
translates it itself and handing it the already-translated `/mnt/d/…` binds
nothing. A `wsl: Failed to translate '<cwd>'` line in the output is noise, not a
failed mount.

No Linux lane installs Flutter (the Windows workflows clone it onto the runner for
`flutter drive`). ANTfrastructure's `flutter_lane_prepare_env`
([`05-frameworks/flutter/lane-prologue.sh`](../../third_party/ANTfrastructure/linux/scripts/05-frameworks/flutter/lane-prologue.sh))
checks that one exists at `--flutter-dir`, puts it on `PATH`, registers the
workspace `safe.directory`, points `PUB_CACHE` at `.pub-cache` and reports the
version it found; whatever the image carries is what gets used. A multi-GB
`flutter/` in the repo is a leftover from before that — git-ignored, and safe to
remove.

Linux builds run containerized. CI's path is the ANTfrastructure composite
action `.github/actions/run-in-linux-container@develop`, which runs
`scripts/linux/ci/ci-container-run-native-linux.sh` *inside* the container with
CLI flags, not env vars (the *Run container* step of
[`reusable-linux.yml`](../../.github/workflows/reusable-linux.yml), which
`linux-x64.yml` and `linux-arm64.yml` both call). For x64 it resolves to:

```bash
bash /workspace/scripts/linux/ci/ci-container-run-native-linux.sh \
  --arch x64 --build-mode release --flutter-dir /opt/flutter \
  --app-name omni-accelerant \
  --package-formats tar,deb,flatpak,appimage \
  --install-packaging-deps true --strict-checks true \
  --run-codeql false --run-docs true
```

`--flutter-dir` only says *where* to look; it defaults to `/opt/flutter`. There
is no `--install-flutter` and no `--flutter-version`.

**Flutter comes from the image, and this repo does not have an opinion about
which version.** `flutter_lane_prepare_env` returns non-zero if `--flutter-dir`
holds no `bin/flutter`, and otherwise prints the `flutter --version` this run
got and moves on. To change the Flutter version, change the image. Why the pin-and-install
machinery went, and what it was costing every Android run:
[`docs/source/project-operations.md`](project-operations.md)
§ *The Linux lane, locally*.

The lane scripts take their inputs as CLI flags and exit 2 on a missing
required one rather than guessing — `--arch` in all three, `--app-name` in the
native and android lanes (the web lane takes none). `--package-formats` defaults
to `tar` and `--flutter-dir` to `/opt/flutter`. The values
CI passes are the `with:` blocks of
[`linux-x64.yml`](../../.github/workflows/linux-x64.yml) and
[`linux-arm64.yml`](../../.github/workflows/linux-arm64.yml).

**`--app-name` derives from `pubspec.yaml`; do not hard-code it again.**
`resolve_app_name` in `scripts/linux/lib/cli-common.sh` reads the `name:` entry
and swaps `_` for `-`, so `omni_accelerant` yields `omni-accelerant`.
`lane-native-linux.sh`, `lane-android.sh` (which appends `-apk`) and
`package-linux.sh` default through it, and `Invoke-LinuxLane.ps1` reads the same
`name:` line itself. Before
2026-09-05 the literal sat in all four plus the workflows, seven copies that a
rename had to find. The workflows still pass the value explicitly, which is
what keeps CI independent of a host's `pwd`.

`FLUTTER_DIR` defaults to `/opt/flutter` — the image's SDK, shared by every
lane and never written to. It used to default inside the workspace, which made
an x64 and an arm64 run in the same tree overwrite each other's SDK; that is
gone along with the installer.

## CodeQL, only on request

**CodeQL runs only when asked for, and never in CI (owner directive
2026-09-17).** `scripts/linux/codeql/codeql-android.sh` installs the CLI, builds
a `--db-cluster` for **c, cpp and rust** around `flutter build apk` and runs two
`database analyze` suites — budget hours, not minutes, which is why the android
workflow and `Invoke-LinuxLane.ps1` both send `--run-codeql false` and the
driver's local opt-in is `-RunCodeQL`. Java and Kotlin are deliberately not in
that cluster: CodeQL's Java extractor refuses this repo's KGP and kills the
Gradle build with it — AGENTS.md § 4, the built-in-Kotlin bullet. The native lane
implements none and its driver *refuses* `--run-codeql true` with exit 2 rather
than reporting success over a scan that never happened. So CI's android lane is
the plain `flutter build apk` plus the plugin's JVM test, and the native build
(both architectures) is the plain `flutter clean && flutter build linux
--release` (its `pub get` ran in the checks batch before it).

The scan is scoped by
[`.github/codeql/codeql-config.yml`](../../.github/codeql/codeql-config.yml) —
`paths-ignore` for build output, AccelerANTgine's vendored libraries, the
non-inference submodules and Cargokit — passed to `database create` as
`--codescanning-config`; the filters travel in the database to
`database analyze`. It scopes the *analysis*, not extraction: a built
language's extractor still sees those files, and the Rust extractor indexes the
cargo registry under `usr/local/cargo` (21k files on the 2026-09-17 run), which
no source-root-relative path filter can reach. What it buys is the outcome:
that run produced 10 Rust findings, all under `third_party/OxidANT`, and none
from an ignored path. The Windows `-CodeQL` path passes the same file since
2026-09-28, through the hub's `Invoke-BuildCodeQL -CodeScanningConfig` (hub
4dbf68b9); `Build-Windows.ps1` stops rather than scan unscoped on an older pin,
because the unscoped run of 2026-09-17 indexed every vendored tree. A reused
`codeql-db-cluster` keeps the scope it was created with: pass `-CleanCodeQLDb`.
`database analyze` does **not** apply the config to traced C++: the first complete Windows
run (2026-10-05) reported 39 of its 63 cpp results from the ignored
`third_party/AccelerANTgine/third_party`. Since hub 09c3f983, `Invoke-BuildCodeQL` drops
results under the config's `paths-ignore` from each SARIF and logs the count.

`-CodeQL` starts from any tree. The untraced bootstrap runs first. Every preset's CMake
folder and the cargo target are then cleared, and the traced build compiles cold with
sccache off (hub `Disable-SccacheForTrace`): under the tracer, the image's never-exiting
sccache server hangs `database create`. `Build-Windows-Container.ps1 -Configurations
clangcl-release -CodeQL -CodeQLDownload -CleanCodeQLDb -FreshContainer` ran that way on
2026-10-05 in about 37 min. It left 24 cpp and 10 rust results, all in owned code. The
driver brings back only `logs` and the runner: the SARIFs stay in the container's
`C:\ws\codeql-results`, readable with `docker exec omniaccelerant-agentic-build pwsh
-Command "Get-Content -Raw C:\ws\codeql-results\cpp.sarif"`.

## Gate strictness and the pre-commit hook

**A pre-commit hook runs CI's first gates** (2026-10-05). Enable it once per clone with
`git config core.hooksPath scripts/git-hooks`. It runs `scripts/linux/run-lint-gates.sh`,
the same lint gates `lint-gates.yml` runs (about 10 s on the Windows box). When a staged
file is a `scripts/**/*.ps1` or `.psm1`, it also runs the hub's `Invoke-Lint.ps1 -Path
scripts`, the step `windows-x64.yml` stops on before its image pull (`windows-arm64.yml`
has no such step). That step once reached CI uncaught: e904182's chained `[switch]` assignment failed
windows-x64 run 37324782889. It grades the working tree, like the hub's hook.
`--no-verify` skips it.

Quality gates — `Build-Windows.ps1` runs these by default (skip with
`-SkipFormat` / `-SkipTests` / `-SkipDocs`). Note the format command is **not**
`dart format .`, the form that crashes on Windows (AGENTS.md § 4).

```bash
dart format --output=none --set-exit-if-changed $(git ls-files -- '*.dart' ':!:rust_builder/**')
cmake-format -c .cmake-format.yaml --check <the hand-maintained CMake files>
flutter analyze
flutter test
dart pub global run dartdoc --output doc/api
```

The Linux `checks` stage runs the same three (with `dart analyze` rather than
`flutter analyze`), and **whether a failure is fatal depends on the lane**, not
on the stage:

| Lane | `--strict-checks` | A failing format/analyze/test |
| --- | --- | --- |
| native Linux ([`reusable-linux.yml`](../../.github/workflows/reusable-linux.yml), both architectures) | `true` | reds the lane |
| web ([`web.yml`](../../.github/workflows/web.yml)) | `true` | reds the lane |
| android (`ci-container-run-android.sh`) | not passed; always strict | reds the lane |

Every lane is strict since 2026-10-01: the android lane was the last that
reported a failing check and moved on, and `lane-android.sh` now calls
`run_flutter_common_checks true` like the others. All three also run the
plugin's own Dart tests through that function, under the same strictness. The
`|| warn` arm still exists upstream in `flutter_checks.sh`, for a local
`--strict-checks false` run only.

`Invoke-LinuxLane.ps1` passes `-StrictChecks true` by default (since
2026-09-16) so a local run grades exactly as CI does. It defaulted to `false`
before that, which is the failure mode the driver exists to prevent: the lane
you run to reproduce CI was the more forgiving of the two.

The CMake gate NO LONGER follows that switch.
`run_cmake_format_check` takes no arguments at all now: it used to accept a
strictness flag and IGNORE its own verdict when that flag was false, so it errors
(exit 2) if handed one rather than letting a stale caller pass silently. It runs in
the native-Linux lane and the Android lane and is FATAL in both; the web lane builds
no native CMake code and does not run it.

That flip is safe for a measured reason, not an optimistic one — the gate's 13
files are already clean and the native-Linux lane has passed
`--strict-checks true` since fc8b65c, so the Android lane can only catch drift
that already blocks the merge elsewhere.

## Troubleshooting

### The Linux lane, locally

`scripts/windows/Invoke-LinuxLane.ps1` runs the same image, script and arguments
as the Linux workflows; AGENTS.md § 5 (Build, run, test) holds the lane table and the rules. What
follows is the evidence behind those rules — each cost at least one run to find,
and each has a symptom that names something other than its cause.

**The android lane needs KVM in Rancher's VM, once per VM boot.** Its emulator
smoke boots the image's AVD, and the VM starts without the KVM module even though
the CPU flags (`svm`/`vmx`) reach it. nerdctl then refuses the run with `error
stating device path: stat /dev/kvm: no such file or directory`. Load the module and
open the node to the container's uid 1001, the same mode GitHub's runners get from
`android.yml`'s udev rule (measured 2026-10-06, AMD host: AVD boot 20 s):

```bash
wsl -d rancher-desktop -u root -- modprobe kvm_amd    # kvm_intel on Intel
wsl -d rancher-desktop -u root -- chmod 0666 /dev/kvm
```

**arm64 locally needs QEMU registered once per VM boot.** Rancher's VM starts
with no emulators at all — `binfmt` reports `"emulators": null` and only
`linux/amd64` variants under `supported`, so an arm64 container would run
x86-64 binaries and die exactly as CI did before the image went multi-arch
(`rustc: 1: ELF: not found`). Register it with:

```powershell
nerdctl run --rm --privileged tonistiigi/binfmt --install arm64
nerdctl run --rm --privileged tonistiigi/binfmt          # verify: qemu-aarch64 listed
nerdctl run --rm --platform linux/arm64 --entrypoint uname ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest -m  # verify: aarch64
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

CI is unaffected: its arm64 build (`linux-arm64.yml`) runs on a real
`ubuntu-26.04-arm` runner, so neither restriction applies. Locally, treat a
failing flatpak/AppImage step on arm64 as expected and check the two messages
above before investigating.

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
which version.** It used to: three lanes resolved `FLUTTER_VERSION` and
`FLUTTER_SDK_SHA256` out of ANTfrastructure's `versions.env`, exported the sha, and
handed both to an installer. That machinery is gone — `resolve_flutter_pin`,
`setup_flutter_sdk`, `install-flutter.sh` and the `--flutter-version` /
`--install-flutter` flags with it. ANTfrastructure's
`flutter_lane_prepare_env` replaces all of it: it returns non-zero if
`--flutter-dir` holds no `bin/flutter`, and otherwise puts the SDK on `PATH`,
registers the workspace `safe.directory`, sets `PUB_CACHE` and prints the
`flutter --version` this run got. Until 2026-09-15 this repo did the same three
things itself, in `scripts/linux/lib/container-steps.sh` and in a different
order per lane.

Why it went: the lanes were re-running ANTfrastructure's `setup-flutter.sh` at
*run* time. That script is a build-stage script — its last step strips
`bin/cache` on purpose — so every Android run re-extracted Flutter over the
image's copy and then re-downloaded the 227 MB Dart SDK it had just deleted.
Upstream now returns early when the requested version is already bootstrapped,
and this repo no longer calls it at all.

`--flutter-dir` only says *where* to look; it defaults to `/opt/flutter`. There
is no `--install-flutter` and no `--flutter-version`.

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

Then rebuild the project — on Windows in the build container, never on the host
(the command and why: AGENTS.md § 5). A reused container once kept a stale Dart
AOT snapshot that still reported the old codegen version. `Build-Windows.ps1`'s
*Flutter AOT Freshness* step now catches that and rebuilds the snapshot
(`scripts/windows/modules/WindowsFlutterAot.Common.psm1`); if it still fails,
start a fresh container (`Build-Windows-Container.ps1 -FreshContainer`).

**Prevention:** Always regenerate bindings after updating `flutter_rust_bridge` version in `pubspec.yaml` or modifying Rust API signatures.

## Contribution Checklist

- [ ] Scope is focused and documented.
- [ ] Build/test commands were run locally.
- [ ] Relevant docs were updated.
- [ ] No secrets, machine-specific paths, or temporary artifacts were committed.
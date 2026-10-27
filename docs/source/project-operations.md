# Project Operations

## Daily Developer Flow

1. `git pull`, then `git submodule update --checkout --recursive` for the recorded commits, or
   `bash third_party/ANTfrastructure/linux/scripts/git-sync-branches.sh` for every checkout,
   third-party ones included, on its branch tip (AGENTS.md § 3).
2. Run local checks: `flutter analyze`, selected tests, docs generation.
3. Verify at least one target runtime: web, Linux, Windows or Android.
4. Open a pull request with a clear scope and how you verified it.

## Quality Gates

### Package license and launcher checks

Android CI checks the manifest and launcher resources through ANTfrastructure before building,
then verifies the complete project `LICENSE` in Flutter's compressed `NOTICES.Z` in the APK.
Omni's TAR, DEB, AppImage, Flatpak, MSI and MSIX checks inspect that notice in the finished
package; ObservANT uses its web `NOTICES` for the same formats. AppImage checks run on the
matching native architecture; MSI file identifiers are resolved from each installer, and
ambiguous names fail. These checks establish the project text is present; they do not establish
that all native dependency licenses are included.

Windows MSI and MSIX packages, and ObservANT's ZIP, also carry the original ONNX Runtime
license and notices from the image wheel whose `onnxruntime.dll` exactly matches the packaged
DLL. Missing or ambiguous wheel matches and missing or altered package texts fail packaging.

Linux Omni, ObservANT and its Pi bundle match every bundled `libonnxruntime*.so*`
to one wheel, either directly or after target-compatible stripping. The wheel's
original license and notices are checked in each finished package. Set
`ORT_CHAIN_WHEEL_DIR` to override `/opt/onnxruntime-wheels` and `STRIP` to choose
the target's strip tool. A missing, changed or ambiguous match fails; this does
not establish coverage of other native dependencies.

### Third-party license inventory

[Third-party components](third-party-components.md) lists every component the packages ship:
native libraries and data (`scripts/licenses/native-components.json`), Rust crates of OxidANT
and AccelerANTgine for every shipped target, and Dart packages from `pubspec.lock`. Native and
crate license texts ship in every APK, TAR, DEB, AppImage, Flatpak, MSI and MSIX as
`assets/licenses/third-party-licenses.json` plus its text files, and the app's licenses page shows
them; Dart package texts stay in Flutter's `NOTICES`. Each package check requires those assets
byte for byte.

- **Regenerate after a lockfile, submodule or native-table change**:
  `python3 scripts/licenses/generate-third-party-licenses.py --write`. It copies each Cargo
  workspace and runs ANTfrastructure's `stage-cargo-licenses.py` per root crate and target, so
  it needs `cargo` and the crate sources. `--check` is the offline drift gate the Linux and
  Android lanes run through `scripts/linux/tests/test-third-party-licenses.sh`.
- **Crates without a license file** take the original text from their upstream repository,
  vendored under `scripts/licenses/texts/cargo/` and pinned in `scripts/licenses/cargo-policy.json`
  with its commit URL and SHA-256. OxidANT's workspace crates point at its `LICENSE`.
  AccelerANTgine's `rusty_code` declares no license; the generator's copy states its repository's
  MIT until AccelerANTgine adds `license = "MIT"`.
- **Native texts** are upstream originals under `scripts/licenses/texts/native/`, pinned by
  SHA-256 with their source URL. Each component names the file globs it covers per platform.
- **Coverage gate**: `scripts/licenses/check-native-coverage.py` fails Linux packaging, the APK
  build and the Windows MSI/MSIX build when a shipped `.so`, ELF, `.dll`, `.exe` or `.lib` has no
  component. A new library therefore needs an entry and its text before it ships.

What it does not establish: code linked statically or header-only is listed by hand (the
Android plugin's GStreamer SDK, AccelerANTgine's C++ dependencies); corresponding-source offers
for LGPL components are not produced; DirectML and the Visual C++ runtime are proprietary
redistributables, listed with their terms' URL; ObservANT's native payload is not yet gated.

### Launcher icons from one logo

`images/logo.svg` is the source. `assets/icons/kataglyphis_app_icon.svg` must stay a byte copy,
and `flutter_launcher_icons` renders every platform set from its 1024 px PNG.
`scripts/linux/check-brand-icons.py` compares the web, Android and `images/logo.png` rasters and
every frame of `windows/runner/resources/app_icon.ico` with that PNG; a foreign or mirrored icon
fails. Linux packages take `web/icons/Icon-512.png`, the MSIX logos come from the same file, the
MSI's Start menu shortcut and Apps & Features entry use the exe's icon, and ObservANT's Linux
packages install `images/logo.svg`. The SVG-to-PNG render itself is not compared.

### Static checks

```bash
dart analyze
dart format --output=none --set-exit-if-changed $(git ls-files -- '*.dart' ':!:rust_builder/**')
```

**Never `dart format .`**: format the tracked files, as the command above and both lanes do
(`code_quality_find_dart_files`, `Get-ProjectDartFiles`). Why, with this repo's run 33810449411
(`Formatted 7404 files (627 changed)`):
[`code-quality-tooling.md` § *`dart format`: the tracked files, in the floor's style*](../../third_party/ANTfrastructure/docs/code-quality-tooling.md#dart-format-the-tracked-files-in-the-floors-style).
The list leaves out `rust_builder/` (Cargokit's 19 files); `flutter/` is untracked and
`third_party/` holds gitlinks, so `git ls-files` lists neither. `dart analyze` honours the
`analyzer.exclude` list in `analysis_options.yaml` and is not affected.

### Lint gates (shell, workflows, secrets)

```bash
bash scripts/linux/run-lint-gates.sh
```

The same gates the `lint` job of `linux-x64.yml` runs: since 2026-09-15 that job calls
ANTfrastructure's reusable `lint-gates.yml` with `ratchets: true`, and job and wrapper both run
the hub's `linux/scripts/run-lint-gates.sh` over this tree with `--exclude third_party
--ratchets`. They used to be `run:` blocks inside the workflow, so a failing merge gate could
not be reproduced locally at all.

- **The gates**, all bootstrapped pinned from ANTfrastructure, all run even after one fails:
  shell lint, workflow lint (plus the CI image-reference check), the gitleaks secret scan,
  Python lint, the shared-config drift check and the consumer pin-forwarding check.
  Python lint reads heredocs inside Bash scripts as well as `.py` files; the app's ESP32 patcher,
  browser test and ObservANT benchmarks follow the same Ruff rules.
- **`--ratchets`** adds the eight measurement gates (freeze files: the `*.allow` at the root)
  and the doc-links gate over this repo's Markdown.
- **gitleaks self-tests first**: an empty tree must scan clean, and a planted token must be
  reported and make the gate exit non-zero, so "found nothing" cannot be confused with "never
  ran".
- **The shared-config drift check is one of these gates**, not a separate step. The workflow's
  `shared-config` job (`pwsh` `Sync-SharedConfig.ps1 -Check`) is its PowerShell twin, kept so
  both halves stay exercised and must agree.

### The CMake format gate

**Fatal in the native-Linux and Android lanes, and `run_cmake_format_check` takes no
arguments.** It used to accept a strictness flag and ignore its own verdict when that flag was
false, so it now errors (exit 2) if handed one rather than let a stale caller pass silently. That
is safe for a measured reason: the gate's 13 files are already clean and the native-Linux lane
has passed `--strict-checks true` since f2e7118, so the Android lane can only catch drift that
already blocks the merge on the other lane. Wrap the call in `run_gate` when you want the batch
to decide; never reach for a flag. The web lane builds no native CMake code and does not run it.

**It covers hand-maintained CMake only, 13 files today.** Both lanes build the same list
(`run_cmake_format_check` in `scripts/linux/lib/container-steps.sh`; the
`CMake Format Verification` step in `scripts/windows/Build-Windows.ps1`) and exclude the same
trees, each verified generated or vendored. Never widen the gate onto one: it would fight the
generator or upstream.

On Windows, the step gets its `uv` command and log callbacks from ANTfrastructure's
`New-UvBuildDelegates -Context $context`; the shared runner keeps external command failures fatal.

| Excluded | Why |
| --- | --- |
| `third_party/`, `build/` | vendored, build output |
| `*/flutter/CMakeLists.txt` | header: "It should not be edited" |
| `*/generated_plugins.cmake` | "Generated file, do not edit" |
| `*/ephemeral/` | rewritten on every `pub get` |
| `*/.cxx/` | Android Gradle's CMake build trees |
| `*/.plugin_symlinks/` | pub's junction farm |
| `rust_builder/cargokit/` | vendored: its README opens with "copied from Cargokit" |
| `.venv/` | created by the gate's own bootstrap |
| `.pub-cache/`, Linux walk only | pub's download cache, in the tree since `PUB_CACHE` moved to `<repo>/.pub-cache`; the Windows step lists tracked files only, so neither this nor `.venv/` can reach it |

`.cmake-format.yaml` at the root is the consumer copy of ANTfrastructure's canonical config
(`shared/config/README.md` owns why it is a copy). Refresh it with `pwsh -File
third_party/ANTfrastructure/shared/config/Sync-SharedConfig.ps1 -RepoRoot . -Write` or `bash
third_party/ANTfrastructure/shared/config/sync-shared-config.sh --repo-root . --write`, without
`-Ignore`: what this repo takes is declared in
[`.antfrastructure-shared.manifest`](../../.antfrastructure-shared.manifest), four rows, and the
scripts refuse `-Ignore` while that file exists.

cmake-format comes from `PATH` or a uv venv fed by ANTfrastructure's locked
`third_party/ANTfrastructure/quality/cmake-format` project on both platforms.
`pyyaml` is in that set because
cmake-format cannot read its own YAML config without it. The config's `line_ending: unix` is why
`.gitattributes` pins `CMakeLists.txt` and `*.cmake` to LF: a `core.autocrlf=true` checkout would
otherwise fail `--check` on every file.

### The plugin's C++ format gate

`scripts/linux/check-plugin-cpp-format.sh` checks the native plugin's tracked, hand-written
C/C++: 15 files under `android/`, `linux/` and `windows/` of
`packages/kataglyphis_native_inference`. It runs `clang-format --dry-run -Werror` through the
hub's `code_quality_check_clang_format`, never rewrites, and fails on a single deviating file.
It refuses to grade (exit 2, also red) on:

- a clang-format other than the hub's `LLVM_RELEASE` (the environment's value, else the pinned
  `versions.env`), because releases format differently;
- no `.clang-format` beside the sources, where clang-format would silently fall back to LLVM
  style;
- no tracked files at all.

`example/*/runner/` is Flutter's generated scaffolding and is not graded, as the comment-size
gate skips it.

The config, `packages/kataglyphis_native_inference/.clang-format`, is the hub's canonical one,
declared in `.antfrastructure-shared.manifest` with that path: the drift gate watches it, and
the app's own generated runner sources stay outside it. The gate runs in the native-Linux
lane's code-quality batch on both architectures, beside
`scripts/linux/tests/test-check-plugin-cpp-format.sh`, which plants a deviation and provokes
each refusal. Windows has no C++ format step.

To clear a red run, rewrite the named files with `clang-format -i` from the image (23.1.3).
The canonical config leaves comments as written (`ReflowComments: Never` since hub a5443e2c,
2026-10-12): reflow put a comment past 120 columns onto a second line, which the comment-size
gate rejects. The 2026-10-12 sweep is in `.git-blame-ignore-revs`.

### Tests

What each kind of test proves, how to run it and what is not covered yet:
[Testing](testing.md). Which lane runs which test: the table in AGENTS.md
§ *What each lane tests*.

## Documentation Workflow

Generate the docs, then preview them:

```bash
bash scripts/linux/generate-docs.sh
dhttpd --path doc/api --host 127.0.0.1 --port 8080
```

**CI builds and publishes the site in [`docs.yml`](../../.github/workflows/docs.yml)**
(2026-10-19) through the hub's reusable `build-docs.yml`
([`docs-sites.md`](../../third_party/ANTfrastructure/docs/docs-sites.md)): it runs
`generate-docs.sh` in the family image, adds the hub's `.htaccess` and 404 page, fails on a dead
internal link or anchor in `doc/api`, and uploads the site over FTP on a push to `develop` or
`main`, never from a pull request. The Linux lane builds no docs (`--run-docs false`);
`Invoke-LinuxLane.ps1 -Docs` still runs `generate-docs.sh` at the end of a local x64 lane.

**Planned work lives in [`BACKLOG.md`](../../BACKLOG.md)**, in the format ANTfrastructure's
agentic loop consumes. `docs/source/roadmap.md`, which the README's *Roadmap* pointed at, was
never filled in and was deleted on 2026-09-15; git history keeps it.

### There is no Sphinx site here

`docs/source/` is Markdown source for one consumer: the `dart doc` site that
`scripts/linux/generate-docs.sh` builds, staging each guide listed in its `DARTDOC_BUILD_GUIDES`
array. Add a guide by adding the file and one array row, never by reviving a second doc
builder. `docs/Makefile`, `docs/make.bat`, `docs/source/conf.py` and `docs/source/index.rst`
were `sphinx-quickstart` scaffolding that no lane, workflow or script ever invoked; they were
deleted on 2026-09-15 and git history keeps them.

If a Sphinx site is ever wanted, take the shared theme, not the standalone `press` theme the
deleted `conf.py` named: it lives in [DocumANTation](https://github.com/Kataglyphis/DocumANTation),
consumers vendor it as `third_party/DocumANTation` and install it through a docs-scoped
requirements file (`-e ./third_party/DocumANTation/sphinx-kataglyphis-theme`), and `conf.py`
reduces to `from sphinx_kataglyphis import setup_theme; setup_theme(globals(), ...)`.
Docs-scoped because the root `requirements.txt` is gone for a reason: it only ever fed the
cmake-format gate, which now takes its pinned set from the hub (§ *The CMake format gate*), and
an unpinned root file next to a pinned shared one is exactly the drift that removal closed.

## Large tracked binaries

Measured 2026-10-17: **1.5 MiB in 22 tracked binary files**, after the 8-bit app icon and the
removal of two images nothing referenced (below); 2026-10-12 counted 4.7 MiB and 2026-09-15
148 MiB. The inventory:

| What | Size | Why it is tracked |
|------|------|-------------------|
| `web/sqlite3.wasm` | 0.7 MiB | The sqlite3 WASM build the web app loads. Fetched and checksum-verified by ANTfrastructure's `setup-sqlite3-wasm.sh`; the committed copy is a convenience, and it has been wrong before (see [Getting Started](getting-started.md)). |
| `assets/icons/kataglyphis_app_icon.png` | 0.26 MiB | Load-bearing: `flutter_launcher_icons` generates every platform icon set from it (`pubspec.yaml` names it four times, one of them msix's `logo_path`), so it stays at its 1024 px source resolution. It was 1.9 MiB as 16-bit RGBA until 2026-10-17; the 8-bit file is pixel-identical to what every icon tool decodes from that one. |

**The history was rewritten on 2026-10-17** (owner, reversing the earlier "document it and stop
it growing"), family-wide ([`data-repositories.md` § *What moved, and why*](../../third_party/ANTfrastructure/docs/data-repositories.md#what-moved-and-why)):
this pack went from 167 to 12 MiB. Move a checkout from before with the hub's
`git-adopt-rewritten-history.sh`
([`adopting-in-a-new-project.md` § *After a history rewrite*](../../third_party/ANTfrastructure/docs/adopting-in-a-new-project.md#after-a-history-rewrite)),
never a plain `git pull`.

**`.gitignore` stops it growing**: media, archives, documents and model weights are ignored by
extension. It never untracks anything, so the table above is unaffected; a new asset the app
genuinely ships is added with `git add -f <path>` and earns a row here saying what it is for.
Having to type `-f` is the whole mechanism.

**The trim happened on 2026-10-12, in normal commits.** What went:
- all 76 Noto Sans files (47.9 MiB), the four faces `pubspec.yaml` declared included. No code
  ever rendered with the family (the theme font is ANThology's Roboto), and Flutter web
  downloaded those four, about 1.2 MB, before every cold load's first frame;
- `dummy_assets/` (79.7 MiB, 16 files, two thesis PDFs most of it), the fixture corpus nothing
  read;
- `assets/videos/funnyandsummy.mp4` (12.3 MiB), in no asset list;
- `assets/images/barbell.png`, the folder's last file, and the folder's `pubspec.yaml` entry;
- gstwebrtc-api's demo page `web/javascript/webrtc/index.html` with the UMD build only it
  loaded. Every web build had published both; the app imports the ESM module.

On 2026-10-17 `images/overview.gif` (1.6 MiB) and `images/Engine_logo.png` went too: no README
or page ever showed either.

What the table lists now is load-bearing. Its one entry over 500 KiB is frozen in
`large-files.allow` for ANTfrastructure's `large-files` gate, which fails on any new data file
over 500 KiB once the hub pin moves past the gate: a new model, scene or document goes to
ModelANT or AssetANT and is fetched by lock instead.

## Serving the web build

Two servers, one contract: both send `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`, and both must serve `.wasm` as `application/wasm`,
because `WebAssembly.compileStreaming()` refuses anything else. The headers make the page
cross-origin isolated, which only the Rust core's shared-memory wasm (`pkg/`) needs, and only in
Firefox and Safari. The Stream page streams without them, and on web `main()` boots without the
core when it does not load (`lib/src/boot/rust_core.dart`), so `serve.sh --http` serves a
plain-HTTP LAN page with no certificate warning, where only the About page's Rust demo goes
dark.

| Where | Config |
| --- | --- |
| The ObservANT demo, any board | `scripts/linux/observant/serve.sh` (generates its own nginx.conf) |
| The hosted site | [`nginx.conf`](../../third_party/ANTfrastructure/linux/webserver/nginx.conf) + [`security-headers.conf`](../../third_party/ANTfrastructure/linux/webserver/security-headers.conf) |

**There is no `web/.htaccess` any more** (deleted 2026-09-16). The site is served by nginx,
which never reads one, so every rule in it (the headers, the wasm MIME type, the caching) was
inert. Keeping it was worse than none: it read like the deployment's source of truth while
changing nothing. Two of its mistakes, not to reintroduce: it sent
`Cross-Origin-Embedder-Policy: credentialless`, which Safari does not implement, and it matched
`\.(js|wasm|…)$` with `max-age=31536000, immutable`, which covers `main.dart.js`,
`flutter_bootstrap.js` and `main.dart.wasm`; none is content-hashed, so a redeploy would never
have reached a returning visitor. Upstream's nginx config gets both right.

`web/index.html` carries three `<meta http-equiv>` COOP/COEP tags' worth of explanation and no
tags: browsers honour those headers only as real HTTP responses, never as `<meta>`, so the tags
that used to sit there never did anything.

## The web lane's CanvasKit source

`scripts/linux/ci/ci-container-run-web-linux.sh` builds with `--no-web-resources-cdn`. The flag
defaults to **on** in `flutter build web`, which bakes
`https://www.gstatic.com/flutter-canvaskit/<engineRevision>` into two independent places:

1. the `flutter.js` loader's base URL, one URL shared by the canvaskit and skwasm branches, so
   `--wasm` does **not** escape it;
2. the `FLUTTER_WEB_CANVASKIT_URL` dart-define compiled into the app.

The renderer files ship in `build/web/canvaskit/` either way, so the default buys only a CDN
round trip, and the ObservANT runbook's point is a Raspberry Pi serving `build/web` on a LAN: a
host with no route to `gstatic.com` renders a blank page with nothing in the console.

**Verify it with the bootstrap key, not with grep:**

```bash
grep -o '"useLocalCanvasKit":[a-z]*' build/web/flutter_bootstrap.js   # => "useLocalCanvasKit":true
```

The key is emitted **only** when true, so its absence is the regression.

**Do not verify by grepping for `gstatic`.** `flutter.js` and `flutter_bootstrap.js` each keep
exactly one hit whether the flag is on or off, because the URL is a string literal in the
*untaken* arm of the loader's ternary:

```js
e.engineRevision && !e.useLocalCanvasKit
  ? W("https://www.gstatic.com/flutter-canvaskit", e.engineRevision)
  : "canvaskit"
```

`useLocalCanvasKit` flips that branch to the local `canvaskit` directory; it does not delete the
string. Measured 2026-09-16 on a `--wasm` build: 1 hit in each of those two files before and
after, 0 in `main.dart.mjs`. A "gstatic must be 0" check would fail forever and teach the next
reader that the flag does not work.

**Nothing goes to Google** (owner, 2026-10-21). The CanvasKit flag also bundles fallback Roboto,
but emoji and symbol fonts still need `web/flutter_bootstrap.js`'s `fontFallbackBaseUrl` and the
hub's locked [fallback-font fetcher](../../third_party/ANTfrastructure/linux/webserver/README.md#fallback-fonts-from-the-site).
The lane copies those fonts from the image store into `build/web/fallback-fonts`, checks them
over HTTP (`CHECK_FALLBACK_FONTS=1`) and lists their OFL notice on the licences page.

`bash scripts/linux/check-web-browser.sh` runs the hub's
[Node/Chrome check](../../third_party/ANTfrastructure/docs/ftp-deploys.md#the-live-site-check)
over all branches and configured blog routes. It serves an idle ObservANT fixture with the
real signalling handshake, empty producer lists, settings, health and a valid snapshot; a
physical camera is unnecessary. External hosts and browser errors stay forbidden. The fixture
does not test media playback; the ObservANT package tests do.
Its empty producer list makes no WebRTC peer connection, so the network assertion covers
HTTP(S); live media follows the STUN/TURN configuration in `webrtc_settings.json`.

The web lane runs that check after its build and HTTP smoke, then
`bash scripts/linux/tests/test-check-web-browser.sh` proves it rejects a console error, a
Google request and a missing asset. Both commands accept a build directory as their first argument.

Measured on 2026-10-22 in image digest `sha256:3c558d8828553ea2e3feedb97c99e15bb89a0820c6a056813876da4cd968d92c`
(Flutter 3.47.7, Chrome 155.0.8059.79): all 18 URLs at 1280x800 and 390x844 passed, all 127
build files returned 200 and `version.json` matched. The HTTP smoke served all 18 locked fonts;
all three planted failures were rejected. The new scrolling check caught fallback-font
requests on About and the blog overview before the local-font fix.

## CI/CD Notes

- API docs use the hub's pinned generator and isolated tool cache; `generate-docs.sh` leaves
  that default intact. The image's bundled dartdoc can lag fixes independently of Flutter.
- GitHub Actions runs the Linux native, Windows native, Web and Android pipelines.
- Keep generated artifacts deterministic: fewer CI diffs and flaky builds.
- Run the scripts in `scripts/`, not ad-hoc commands, so a run is reproducible.

## Release Hygiene

**Branches, CI rounds and releases** follow the family's rule (owner, 2026-10-15):
[`branch-and-release-strategy.md`](../../third_party/ANTfrastructure/docs/branch-and-release-strategy.md).
Here every push to `develop` runs `linux-x64.yml` and `docs.yml`, and `on-request.yml` reads the
`[ci <lane>]` tokens. Between releases `main` trails `develop` by design (416 commits on
2026-10-05). Neither branch is protected (owner, 2026-10-05).

- Keep dependency upgrades and feature changes in separate pull requests.
- Regenerate bridge code when Rust API signatures change.
- Update docs in the same pull request as any user-facing behaviour change.

**Publishing a release** (2026-10-15). A push to `main` starts `release.yml`: the version check
(`v<version>` is `pubspec.yaml`'s version without its `+build`), all six lanes, then the release
job. The check and the release job call the hub's [`release-publish.yml`](../../third_party/ANTfrastructure/docs/branch-and-release-strategy.md#the-reusable-release-workflow),
which picks the packages from the lanes' uploads by the options in `release.yml`'s `collect:`
block. What a release carries (2.2.0 on; 2.1.0 carried only ObservANT):

| Platform | The app | ObservANT |
| --- | --- | --- |
| Linux x64 and arm64 | `.deb`, AppImage, flatpak (named for its arch), tarball | `.deb`, AppImage, flatpak, tarball |
| Windows x64 and arm64 | MSI, MSIX (with its test certificate), the app folder as a `.zip` | MSI, MSIX (with its test certificate), `.zip` |
| Android | the arm64-v8a APK | |

The options skip logs, debug builds, the arm64 natives and the web build, and fail the release
on an upload no option names (`--strict`) or when a platform's package is missing (`--expect`).
The hub's `test-collect-release-assets.sh` runs the same options over a release run's uploads
([§ *Collecting the release files*](../../third_party/ANTfrastructure/docs/branch-and-release-strategy.md#collecting-the-release-files)).
riscv64 has no package in a release, since no CI lane builds one.

**To release**, follow the hub's
[§ *Merging into `main`*](../../third_party/ANTfrastructure/docs/branch-and-release-strategy.md#merging-into-main)
with this repo's version files: bump `version:` in `pubspec.yaml` and `msix_config.msix_version`
together (AGENTS.md § 4) beside the CHANGELOG section, commit with `[ci all]`, or dry-run the
round with `gh workflow run release.yml --ref develop -f dry-run=true`, which lists the release's
files with their checksums in the run's summary. The owner then fast-forwards `main`
(`git push origin <sha>:main`), as for 2.1.0 (2026-10-15, `3b4344c`).

## Dependency upgrades, in detail

AGENTS.md § 5 (Build, run, test) has the commands and the report-first rule (owner directive
2026-09-11). How Renovate detects and `--apply` writes is the hub's
[`dependency-updates.md`](../../third_party/ANTfrastructure/docs/dependency-updates.md). This
repo's part:

- **`scripts/windows/Invoke-Renovate.ps1` runs `scripts/linux/renovate-local.sh` in `:latest`**
  through `nerdctl`; a Linux host calls the wrapper directly, and nothing in CI runs either. It
  mounts the repo at `/workspace`, adds the `safe.directory` entries the root-owned bind mount
  needs (`/workspace` and `/workspace/*`), and forwards
  `-Apply`/`-DryRun`/`-Refresh`/`-Managers`/`-PrintBin`.
- **Managers default to every manager whose file patterns match this tree** (eight today), so
  `-Managers` narrows a run rather than enabling one.
- **A real apply bootstraps an absent pinned hub**, then the shared driver updates selected direct
  submodules to each remote default tip regardless of `.gitmodules branch`. Report and dry-run
  calls leave missing checkouts absent; initialize the hub or provide another checkout to preview.
  The copied Git mode helper selects Windows Git for a Windows-authored WSL checkout during
  bootstrap and the driver run.
- **Renovate's Node lives on the `kataglyphis-renovate-cache` volume**: its `engines.node` range
  excludes the image's Node, so the bootstrap pulls a checksum-pinned one.
- **The runner passes `gh`'s token as `GITHUB_COM_TOKEN`** when `gh` is authenticated. A live
  scan now stops before dependency lookup if no GitHub token is available.
- **`-Recurse` runs the hub's `renovate-fleet.sh --vendored`**: in this one-superproject mount
  every repo is vendored, so it writes into the submodule worktrees (what follows an `-Apply`:
  AGENTS.md § 5). This repo's own 135-line submodule walker went on 2026-09-15.

## The Linux lanes, run locally

The detail behind the rules in AGENTS.md § 5, moved here on 2026-10-15 to keep AGENTS.md short.
The evidence behind them, error messages included: § *The Linux lane, locally*.

**Driver and workflow change together.** Each lane entry mirrors its workflow's `extra-args` and
`script`, and the argument sets match exactly: the android lane also matches in *not* passing
`--privileged`. The native lane's step lives in `reusable-linux.yml`, its values in the `with:`
block of the per-arch caller; keep that block flat `key: value` lines, which is what
`-CheckParity` reads. `Invoke-LinuxLane.ps1 -CheckParity` diffs the *values* it would send,
`script` and `extra-args`, against the lane's workflow; for `native` it grades `-Arch`'s own
file, resolving `reusable-linux.yml`'s `${{ inputs.* }}` from it. It runs before the engine is
looked up, so it needs no nerdctl and starts nothing.

**One lane at a time.** A real run refuses to start while another Linux lane's container is up
or a Windows build is running, and `Build-Windows-Container.ps1` refuses while a Linux lane is up
(`-Force` overrides both; `scripts/windows/modules/WindowsLaneGuard.Common.psm1`). The two sit on
two engines: the Windows build container is Stevedore's, idles on `ping` between builds, and
counts as busy only while a `pwsh` runs in it. The driver uses Rancher Desktop's `nerdctl`
(the hub's `Resolve-NerdctlExe`: `NERDCTL_EXE`, `PATH` without Stevedore's copy, then
`%ProgramFiles%`), the local Linux engine on this box; CI uses
`docker` through ANTfrastructure's `run-in-linux-container`. Everything inside the container is
identical.

**Linux builds run containerized.** CI's path is the ANTfrastructure composite action
`.github/actions/run-in-linux-container@develop`, which runs
`scripts/linux/ci/ci-container-run-native-linux.sh` *inside* the container with CLI flags, not
env vars (the *Run container* step of
[`reusable-linux.yml`](../../.github/workflows/reusable-linux.yml), which `linux-x64.yml` and
`linux-arm64.yml` both call). For x64 it resolves to:

```bash
bash /workspace/scripts/linux/ci/ci-container-run-native-linux.sh \
  --arch x64 --build-mode release --flutter-dir /opt/flutter \
  --app-name omni-accelerant \
  --package-formats tar,deb,flatpak,appimage \
  --install-packaging-deps true --strict-checks true \
  --run-codeql false --run-docs false
```

The lane scripts take their inputs as CLI flags and exit 2 on a missing required one rather than
guessing: `--arch` in all three, `--app-name` in the native and android lanes (the web lane takes
none). `--package-formats` defaults to `tar`; only a requested flatpak installs the ~1.9 GB flathub
runtimes. The values CI passes are the `with:` blocks of
[`linux-x64.yml`](../../.github/workflows/linux-x64.yml) and
[`linux-arm64.yml`](../../.github/workflows/linux-arm64.yml).

**`--app-name` derives from `pubspec.yaml`; do not hard-code it again.** `resolve_app_name` in
`scripts/linux/lib/cli-common.sh` reads the `name:` entry and swaps `_` for `-`, so
`omni_accelerant` yields `omni-accelerant`. `lane-native-linux.sh`, `lane-android.sh` (which
appends `-apk`) and `package-linux.sh` default through it, and `Invoke-LinuxLane.ps1` reads the
same `name:` line itself. Before 2026-09-05 the literal sat in all four plus the workflows, seven
copies a rename had to find. The workflows still pass the value explicitly, which keeps CI
independent of a host's `pwd`.

**The native lane** sets `KATAGLYPHIS_PLUGIN_TESTS=1` before `flutter build linux`, which
`linux/CMakeLists.txt` turns into the plugin's gtest target; the Rust core takes no feature
variable (it has none since 2026-10-21). For a release build it runs
`bundle-runtime-closure.sh`, then the `knt ABI`, `runtime closure` and `plugin gtest` gates, then
the launch smoke, the integration test and the webcam frame test under the image's `xvfb-run`,
all between the build and packaging.

Linux and Windows disable optional JNI discovery before Flutter's generated plugin rules.
PathProvider's Android implementation brings that FFI plugin into the dependency graph, but
desktop targets use their platform implementations. Finding a build-host JDK would otherwise
build an unused `libdartjni.so` or `dartjni.dll` whose JVM dependency is absent from the runtime
bundle. The Linux closure and Windows PE import-walk gates remain strict.

**`KATAGLYPHIS_LINKER=lld|mold` is an opt-in for the native lane** (2026-10-05):
`.\scripts\windows\Invoke-LinuxLane.ps1 -Env KATAGLYPHIS_LINKER=lld`. `setup_linker` runs it
after `export_toolchain_env`, so clang links the C++ and the host Rust target with that linker;
unset leaves GNU ld for C++ and rust-lld for x64 Rust. The switch is the hub's
[`linker-select.sh`](../../third_party/ANTfrastructure/docs/shared-script-libraries.md#linker-selectsh--an-opt-in-linker),
with the measurement behind it: it fails rather than falls back, and it fetches the pinned mold
3.0.0 when the image has none. lld is the useful value: about 1.3 s off a Debug relink, and
nothing off a ~48 s release app build, which mold does not beat. CI never sets it, and the
android and web lanes do not read it.

**arm64 locally needs QEMU registered once per VM boot**, and an emulated arm64 run produces tar
and deb, never flatpak or AppImage: bubblewrap and static-PIE fail under `qemu-user`. CI's arm64
build runs on a real `ubuntu-26.04-arm` runner. The registration, the pull sizes and both error
messages: [§ *Registering arm64 emulation*](../../third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#registering-arm64-emulation-in-ranchers-vm-per-vm-boot)
and [§ *Emulated arm64 cannot run bubblewrap or static-PIE*](../../third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#emulated-arm64-cannot-run-bubblewrap-or-static-pie).

**Everything write-heavy must stay off the host mount.** A bind-mounted Windows drive cannot do
`utime`, `chmod` or `fchmod` for the container uid, and each surfaces as a different, misleading
error:

| What | Where it lives now | Symptom when it did not |
| --- | --- | --- |
| CMake/ninja build tree | named volume on `/workspace/build` | — |
| pub's download cache | named volume on `/workspace/.pub-cache` | `Rename failed, path = '/workspace/.pub-cache/_temp/…' (OS Error: Permission denied, errno = 13)`, then `Failed to update packages` — **but only on a run that downloads something.** A warm cache resolves from disk and renames nothing, so the local lane passed for as long as nobody edited `pubspec.yaml` |
| cargo's target tree | named volume on `/workspace/third_party/OxidANT/target` | `error: failed to build archive at '…/libwasm_bindgen_macro_support-*.rlib': failed to remove temporary directory: Permission denied (os error 13) at path '…/out/.tmpXXXXXX.temp-archive'`. Same class as the row above, one verb over: the mount refuses the **remove**, not the write. The web lane hits it hardest because `-Z build-std` recompiles the standard library |
| flatpak repo, build tree, builder state, manifest staging **and the finished bundle** | `/tmp/flatpak-work`, the bundle copied out | `fchmod: Operation not permitted`, first from the OSTree repo, later from `build-bundle` (§ *The Linux lane, locally*) |
| ccache | `/var/cache/ccache`, set by the image | `Can't initialize ccache use: Failed to set permissions` |
| sccache's disk level | named volume on `/var/cache/sccache` (2026-10-17) | none: it lived in the container and died with it, so every run after `flutter clean` compiled cold |

Only the finished artifacts are written into `out/`: ANTfrastructure's documented rule for build
directories and caches, applied to the packaging steps as well.

**`pubspec.lock` cannot move off the mount, so its mtime can red the web lane.** When a
workspace member's `pubspec.yaml` is newer than the root `pubspec.lock` (a submodule pull does
that: on 2026-10-05 ANThology's was, by 19 s), the `dart run` inside
`flutter_rust_bridge_codegen build-web` re-validates and touches the lock, and the mount refuses
the `utime`: `FileSystemException: Failed to set file modification time, path =
'/workspace/pubspec.lock' (OS Error: Operation not permitted, errno = 1)`. Touch the lock on the
host, `(Get-Item pubspec.lock).LastWriteTime = Get-Date`, and rerun; the next run passed. CI's
fresh clone never has the skew.

**`-v name:/path` is a bind under Windows nerdctl**
([§ *`-v name:/path` is a bind*](../../third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#-v-namepath-is-a-bind-under-windows-nerdctl); the
measurement was this lane's), so `Invoke-LinuxLane.ps1` always spells the mount
`--mount type=volume,source=…,target=…`. Mounting `build/` makes `flutter clean` log `Device or
resource busy (errno 16)` on every run: cosmetic.

**A mount that resolves but is empty** is `D:` missing from containerd's own mount namespace, or
a WSL path where nerdctl wants `D:\…`:
[§ *An empty mount is not a missing drive*](../../third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#an-empty-mount-is-not-a-missing-drive). A `wsl:
Failed to translate '<cwd>'` line in the output is noise, not a failed mount.

**Flutter comes from the image, and this repo does not have an opinion about which version.**
No Linux lane installs it (the Windows workflows clone it onto the runner for `flutter drive`).
ANTfrastructure's `flutter_lane_prepare_env`
([`05-frameworks/flutter/lane-prologue.sh`](../../third_party/ANTfrastructure/linux/scripts/05-frameworks/flutter/lane-prologue.sh))
returns non-zero if `--flutter-dir` holds no `bin/flutter`; otherwise it puts the SDK on `PATH`,
registers the workspace `safe.directory`, points `PUB_CACHE` at `.pub-cache` and prints the
`flutter --version` this run got. Whatever the image carries is what gets used: to change the
Flutter version, change the image.

`--flutter-dir` only says *where* to look; it defaults to `/opt/flutter`. There is no
`--install-flutter` and no `--flutter-version`. `FLUTTER_DIR` defaults to `/opt/flutter` too,
the image's SDK, shared by every lane and never written to. It used to default inside the
workspace, which made an x64 and an arm64 run in the same tree overwrite each other's SDK; that
went with the installer. A multi-GB `flutter/` in the repo is a leftover from before:
git-ignored, and safe to remove. Why the pin-and-install machinery went, and what it cost every
Android run: § *The Linux lane, locally*.

## CodeQL, only on request

**CodeQL runs only when asked for, and never in CI (owner directive 2026-09-17).**
`scripts/linux/codeql/codeql-android.sh` installs the CLI, builds a `--db-cluster` for **c, cpp
and rust** around `flutter build apk` and runs two `database analyze` suites. Budget hours, not
minutes: that is why the android workflow and `Invoke-LinuxLane.ps1` both send `--run-codeql
false` and the driver's local opt-in is `-RunCodeQL`. Java and Kotlin are deliberately not in
that cluster: CodeQL's Java extractor refuses this repo's KGP and kills the Gradle build with it
(AGENTS.md § 4, the built-in-Kotlin bullet). The native and web lanes implement none; both
*refuse* `--run-codeql true` with exit 2 rather than report success over a scan that never
happened. So CI's android lane is the plain `flutter build apk` plus the plugin's JVM test, and
the native build (both architectures) the plain `flutter clean && flutter build linux --release`
(its `pub get` ran in the checks batch before it).

**The scan is scoped by
[`.github/codeql/codeql-config.yml`](../../.github/codeql/codeql-config.yml)**: `paths-ignore`
for build output, AccelerANTgine's vendored libraries, the non-inference submodules and
Cargokit, passed to `database create` as `--codescanning-config`; the filters travel in the
database to `database analyze`. It scopes the *analysis*, not extraction: a built language's
extractor still sees those files, and the Rust extractor indexes the cargo registry under
`usr/local/cargo` (21k files on the 2026-09-17 run), which no source-root-relative path filter
can reach. What it buys is the outcome: that run produced 10 Rust findings, all under
`third_party/OxidANT`, none from an ignored path.

**Windows** (`-CodeQL`) passes the same file since 2026-09-28, through the hub's
`Invoke-BuildCodeQL -CodeScanningConfig` (hub 56df8c81); `Build-Windows.ps1` stops rather than
scan unscoped on an older pin, because the unscoped run of 2026-09-17 indexed every vendored
tree. A reused `codeql-db-cluster` keeps the scope it was created with: pass `-CleanCodeQLDb`.
`database analyze` does **not** apply the config to traced C++: the first complete Windows run
(2026-10-05) reported 39 of its 63 cpp results from the ignored
`third_party/AccelerANTgine/third_party`. Since hub 92b58c8d, `Invoke-BuildCodeQL` drops results
under the config's `paths-ignore` from each SARIF and logs the count.

`-CodeQL` starts from any tree: the untraced bootstrap runs first, then every preset's CMake
folder and the cargo target are cleared, and the traced build compiles cold with sccache off (hub
`Disable-SccacheForTrace`), because under the tracer the image's never-exiting sccache server
hangs `database create`. `Build-Windows-Container.ps1 -Configurations clangcl-release -CodeQL
-CodeQLDownload -CleanCodeQLDb -FreshContainer` ran that way on 2026-10-05 in about 37 min and
left 24 cpp and 10 rust results, all in owned code. The driver brings back only `logs` and the
runner: the SARIFs stay in the container's `C:\ws\codeql-results`, readable with `docker exec
omniaccelerant-agentic-build pwsh -Command "Get-Content -Raw C:\ws\codeql-results\cpp.sarif"`.

## Gate strictness and the pre-commit hook

**A pre-commit hook runs CI's first gates** (2026-10-05). Enable it once per clone with
`git config core.hooksPath scripts/git-hooks`. It runs `scripts/linux/run-lint-gates.sh`, the
lint gates `lint-gates.yml` runs (about 10 s on the Windows box), and, when a staged file is a
`scripts/**/*.ps1` or `.psm1`, the hub's `Invoke-Lint.ps1 -Path scripts`, the step
`windows-x64.yml` stops on before its image pull (`windows-arm64.yml` has no such step). That
step once reached CI uncaught: 46fe49a's chained `[switch]` assignment failed windows-x64 run
37324782889. The hook grades the working tree, like the hub's; `--no-verify` skips it.

`Build-Windows.ps1` runs these quality gates by default (skip with `-SkipFormat` /
`-SkipTests` / `-SkipDocs`). The format command is **not** `dart format .`, the form that
crashes on Windows (AGENTS.md § 4; § *Static checks*).

```bash
dart format --output=none --set-exit-if-changed $(git ls-files -- '*.dart' ':!:rust_builder/**')
cmake-format -c .cmake-format.yaml --check <the hand-maintained CMake files>
flutter analyze
flutter test
dart pub global run dartdoc --output doc/api
```

The Linux `checks` stage runs the same three (with `dart analyze` rather than `flutter
analyze`), and **whether a failure is fatal depends on the lane**, not on the stage:

| Lane | `--strict-checks` | A failing format/analyze/test |
| --- | --- | --- |
| native Linux ([`reusable-linux.yml`](../../.github/workflows/reusable-linux.yml), both architectures) | `true` | reds the lane |
| web ([`web.yml`](../../.github/workflows/web.yml)) | `true` | reds the lane |
| android (`ci-container-run-android.sh`) | not passed; always strict | reds the lane |

The five Linux entry points use `scripts/linux/lib/ci-options.sh` for their own accepted flags;
that library calls ANTfrastructure's `parse_cli_value_options` to move argument values. Values
starting with `-` remain values, `--` is still unknown, and `--no-package` works only in the
native lane. `bash scripts/linux/tests/test-ci-options.sh` checks the parser and all five entry
scripts; native, Android and web CI invoke the same suite before their builds.

The Linux GStreamer-element and knt-ABI gates use `scripts/linux/lib/bundle-options.sh` for
their distinct bundle path flags and the same ANTfrastructure value parser. Their architecture
and build-mode checks share `cli-common.sh`. The native lane runs
`bash scripts/linux/tests/test-bundle-options.sh` before building; it checks both gate CLIs,
the closure builder's build-mode verdict, and a wrong option-target mutation.

The Windows OmniAccelerANT and ObservANT MSIX checks read signature, manifest and archive
entries through ANTfrastructure's shared MSIX archive reader. A missing or malformed
`AppxManifest.xml` fails the check before product-specific assertions run.

Every lane is strict since 2026-10-01: the android lane was the last that reported a failing
check and moved on, and `lane-android.sh` now calls `run_flutter_common_checks true` like the
others. All three also run the plugin's own Dart tests through that function, under the same
strictness. The `|| warn` arm still exists upstream in `flutter_checks.sh`, for a local
`--strict-checks false` run only.

`Invoke-LinuxLane.ps1` passes `-StrictChecks true` by default (since 2026-09-16), so a local run
grades exactly as CI does. It defaulted to `false` before, the failure mode the driver exists to
prevent: the lane you ran to reproduce CI was the more forgiving of the two.

**The CMake gate no longer follows that switch**: it takes no arguments and is fatal wherever it
runs. Why that is safe: § *The CMake format gate*.

## The web lane's nightly toolchain

Moved here from AGENTS.md on 2026-10-15, which keeps the rule and links this detail.

**The web lane needs the nightly toolchain's `rust-src`.** `flutter_rust_bridge_codegen
build-web` runs `wasm-pack … -Z build-std=std,panic_abort`, so cargo compiles the standard
library itself and stops without the component:
`".../nightly-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/library/Cargo.lock"
does not exist, unable to build with the standard library`.
- **The toolchain is the image's dated nightly** (since 2026-10-01). The lane reads
  `RUST_NIGHTLY_TOOLCHAIN` from the pinned hub's `versions.env` (`nightly-2026-06-28`
  today) and passes it to `build-web` as `--wasm-pack-rustup-toolchain`.
- **The image installs that toolchain with both components.** It does not export the
  variable, hence the read from `versions.env`.
- **The floating `nightly` is not in the image.** Naming it, as the lane did before, made
  rustup download a fresh channel on every run (web run 36154744073). Installing it over
  a present one updates the channel, and on the read-only image layer that update dies
  with `Invalid cross-device link`.
- **The install step stays, guarded** on the two components being absent. It covers a
  bare host, and the image's best-effort `try_rustup` install.

## The Dart gate without a lane

Moved here from AGENTS.md on 2026-10-15, which keeps the rules and links this detail.

**There is no Flutter or Dart SDK on the Windows dev box** (`flutter` is not on `PATH`, and
there is no host SDK to put there), yet the smallest unit of feedback is not a whole container
lane: the image carries the SDK at `/opt/flutter`, and running *only* the Dart gate against a
bind-mounted checkout costs **23 s warm** (measured 2026-09-16; 214 s the first time, which is
`flutter pub get` populating the cache volume).

```powershell
# once: the cache volume must belong to the container's uid, like every other
# volume this repo mounts — see Invoke-LinuxLane.ps1's chown step. The image
# does the chown itself: no stock image, not even alpine (owner rule 2026-10-05).
nerdctl run --rm --platform linux/amd64 --user root --entrypoint chown `
  --mount "type=volume,source=oa-fastloop-pub,target=/vol" `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest -R 1001:1001 /vol

# then, per edit:
nerdctl run --rm --platform linux/amd64 `
  -v "C:\GitHub\OmniAccelerANT:/workspace" -w /workspace `
  --mount "type=volume,source=oa-fastloop-pub,target=/pubcache" -e PUB_CACHE=/pubcache `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest `
  bash -lc 'export PATH=/opt/flutter/bin:$PATH; git config --global --add safe.directory "*"; flutter test'
```

Swap `flutter test` for `flutter analyze` (~164 s; it analyses the whole workspace) or run
both. `PUB_CACHE` on a named volume makes the second run cheap, and follows AGENTS.md § 5,
which keeps write-heavy paths off the host mount.

`scripts/windows/Invoke-DartChecks.ps1` is the same loop as a script (`-SkipFormat`,
`-SkipAnalyze`, `-SkipTest`, `-Fix`; its pub cache is the `omni-dart-checks-pubcache` volume),
run through the hub's `Invoke-InLinuxContainerBuild`, which creates that volume and chowns it
with the image.
Its format step covers `lib test integration_test test_driver`, every tracked file the lanes
grade except the plugin's under `packages/`; its test step runs the plugin's suite too. It runs
the plugin's `pub get` before any step: analyze reads the plugin's `package_config.json`, which a
lane run leaves pointing at the lane's pub cache.
`-Engine wslc` runs it in WSL 3's `wslc` instead of nerdctl (hub CON62's pilot, 2026-10-06).
Measured warm on this box: format + test 23 s against nerdctl's 32 s, analyze 146 s against
371 s. The first run pulls `:latest` into wslc's own image store, about 30 GB and 554 s. wslc
has no `--platform`, so the switch refuses any `-Platform` but `linux/amd64`.

**This is not a substitute for the lane.** It runs the Dart gate and nothing else: no `dart
format` file listing, no CMake gate, no build, no packaging, no C++ or Rust. Use it to iterate;
use `Invoke-LinuxLane.ps1` to believe the result. It is also why "add a test" is a cheap
proposal in this repo.

## Troubleshooting

### The Linux lane, locally

`scripts/windows/Invoke-LinuxLane.ps1` runs the same image, script and arguments as the Linux
workflows; AGENTS.md § 5 (Build, run, test) holds the lane table and the rules,
§ *The Linux lanes, run locally* their detail. Below is the evidence: each cost at least one run
to find, and each has a symptom that names something other than its cause.

**sccache: a volume, and the shared S3 level behind it (2026-10-17).** The native lane runs
`flutter clean` before its build, so the C++ build tree is gone on every run, and the lane's
sccache cache, which lived in the container, went with it. It now has its own named volume,
backed by the S3 bucket the image chain and the Windows builds share:

- `New-LaneSccacheS3Secret` (`scripts/windows/modules/WindowsLaneSccache.Common.psm1`) reads
  the host's key: the `KATAGLYPHIS_SCCACHE_S3_*` variables on Windows, or
  `~/.config/kataglyphis/sccache-s3.env` on Linux. It asks the hub's `Get-HostSccacheS3ExecEnv`
  whether the level is complete and answers, then writes the six names to a 0644 file in a
  0700 directory. The driver binds that file at `/run/secrets/sccache_s3`.
- In the container, the hub's `sccache_start_server` hands the key to the server alone.
  `setup_compiler_cache` prints the server's `Cache location` (`Multi-level (2 levels)`) and
  waits for the uploads on exit. The container's end would otherwise drop them.
- CI has no route to the bucket and gets none of this. Its sccache cache moves between runs
  through `actions/cache` instead, and its native lane hits about 95 %. The rest are CMake's
  configure probes ([`platforms.md`](platforms.md) § *Image gaps and image-tag history*).

Measured on the Linux host, native lane x64, `-PackageFormats tar -SkipDocs`, 2026-10-17:

| Run | sccache | Wall time |
| --- | --- | --- |
| Cold: empty volume, nothing in the bucket for this lane | 1,172 misses, all 1,172 uploaded, 0 failed; the drain took 15 s | 6 min 50 s |
| The sccache and cargo-target volumes deleted | 1,232 hits of 1,235 (99.76 %), Rust 100 %, all from the bucket | 5 min 48 s |

**A Linux host's rootless engine runs the lane as root**: the driver passes `--user 0:0` and
`TAR_OPTIONS=--no-same-owner` when `nerdctl info` reports `name=rootless` on a non-Windows host.
Why, with both error messages:
[`linux-build-basics.md` § *A lane under a rootless engine*](../../third_party/ANTfrastructure/docs/linux-build-basics.md#a-lane-under-a-rootless-engine-on-a-linux-host-runs-as-root).

**The android lane needs KVM in Rancher's VM, once per VM boot**
([§ *KVM in Rancher's VM*](../../third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#kvm-in-ranchers-vm-for-the-android-emulator-per-vm-boot));
without it nerdctl refuses the run with `error stating device path: stat /dev/kvm`. CI's runners
get the node's mode from `android.yml`'s udev rule; `-EmulatorSmoke false` skips the emulator.

**`error: fchmod` after `Pruning cache` is not the prune.** That combination cost hours.
`Pruning cache` is merely flatpak-builder's *last* output line; it exits 0. The error underneath
came from `flatpak build-bundle`, which chmods the file it writes, and that file was
`out/…flatpak`, on the host mount. The bundle is now written under `/tmp/flatpak-work` and
copied out afterwards. `set -x` around the function answered this in one run, after three rounds
of eliminating plausible-looking causes had only moved the symptom.

The step also does **not** gate on flatpak-builder's exit code any more. It asks
`ostree --repo=<repo> refs` whether the app is committed, because the export can be complete
while a later stage fails. The exit code is reported in the warning, never used as the verdict.

All four formats build locally on x64: tar, deb, flatpak and AppImage. The appimagetool mode-711
problem that used to break the last one is fixed in the image.

**There is no separate host-side driver any more.** The legacy `ci-dart-on-native-linux.sh` /
`ci-dart-build-android-app.sh` pair and their `ci-common.sh` were removed on 2026-09-04: no
workflow ever referenced them, they carried a third copy of the CodeQL logic, and they
re-implemented what CI actually runs instead of invoking it. Use `Invoke-LinuxLane.ps1` (§ 5),
which runs the very script CI runs.

**Flutter used to be pinned and installed by the lanes** (today's rule:
§ *The Linux lanes, run locally*). Three lanes resolved `FLUTTER_VERSION` and
`FLUTTER_SDK_SHA256` out of ANTfrastructure's `versions.env`, exported the sha, and handed both
to an installer. That machinery is gone: `resolve_flutter_pin`, `setup_flutter_sdk`,
`install-flutter.sh` and the `--flutter-version` / `--install-flutter` flags with it.
ANTfrastructure's `flutter_lane_prepare_env` replaces all of it. Until 2026-09-15 this repo put
the SDK on `PATH`, registered `safe.directory` and set `PUB_CACHE` itself, in
`scripts/linux/lib/container-steps.sh` and in a different order per lane.

Why it went: the lanes were re-running ANTfrastructure's `setup-flutter.sh` at *run* time. That
is a build-stage script whose last step strips `bin/cache` on purpose, so every Android run
re-extracted Flutter over the image's copy and then re-downloaded the 227 MB Dart SDK it had
just deleted. Upstream now returns early when the requested version is already bootstrapped,
and this repo no longer calls it at all.

### flutter_rust_bridge Version Mismatch

The error, at runtime:
```
oxidant's codegen version (2.11.1) should be the same as runtime version (2.12.0)
```

**Cause:** the generated Dart binding files (in `lib/src/rust/`) are out of sync with the
`pubspec.yaml` dependency version.

**Fix:** regenerate the Flutter Rust Bridge bindings:

```bash
flutter_rust_bridge_codegen generate
```

It is a cargo binary baked into the build image, not a pub dependency. On a bare host install it
first, at the version this repo pins, never at latest:
`cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen` (the `flutter_rust_bridge`
pin in `third_party/OxidANT/Cargo.toml`; the image exports the same number as
`FLUTTER_RUST_BRIDGE_VERSION`). Installing latest is how the mismatch above happens.

Then rebuild, on Windows in the build container, never on the host (the command and why:
AGENTS.md § 5). A reused container once kept a stale Dart AOT snapshot that still reported the
old codegen version; `Build-Windows.ps1`'s *Flutter AOT Freshness* step now catches that and
rebuilds the snapshot (`scripts/windows/modules/WindowsFlutterAot.Common.psm1`). If it still
fails, start a fresh container (`Build-Windows-Container.ps1 -FreshContainer`).

**Prevention:** always regenerate bindings after updating the `flutter_rust_bridge` version in
`pubspec.yaml` or modifying Rust API signatures.

## Contribution Checklist

- [ ] Scope is focused and documented.
- [ ] Build/test commands were run locally.
- [ ] Relevant docs were updated.
- [ ] No secrets, machine-specific paths, or temporary artifacts were committed.

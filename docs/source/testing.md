# Testing

What each test in OmniAccelerANT, OxidANT (the Rust core) and AccelerANTgine (the C++ core)
proves, the rules that keep a green run honest, how to run them, and what is not covered yet.
Which lane runs which test is AGENTS.md § *What each lane tests*; this page is the why behind
that table (written after the test audit of 2026-10-15).

## What runs, and what it proves

| Kind | Where | What a pass means | Runs in |
| --- | --- | --- | --- |
| Dart unit and widget tests | `test/`, the plugin's `test/` | Page logic and state; the shipped settings files load and name assets that exist; every page lays out at a phone's, a tablet's and a desktop's size, at 150 % and 200 % text, and lands on its own route rather than the error page | Every lane on the Dart VM; the web lane in Chrome |
| Built web app | `scripts/linux/check-web-browser.sh` | Every branch boots in real Chrome at desktop and phone sizes; scrolling triggers no external font fetch, console error or missing asset; every build file and version is served | `web.yml`, after the WASM and Flutter build; an idle ObservANT fixture answers signalling and API requests |
| Rust unit tests | OxidANT `crates/*`, `src/` | ObservANT's motion, arrival, clip and HTTP rules; the webcam engine on `videotestsrc` with the real model, headless; the detector on a real photo | OxidANT's Linux and Windows lanes |
| Property tests | OxidANT `crates/observant` (`mod properties`) | A rule holds for every input, not a few examples: no request path, however encoded, leaves the web root; a served byte range stays inside the file; a public host name is refused; a config that validates keeps its numbers in range | With the Rust unit tests, 256 random inputs per rule and run |
| C++ unit tests | AccelerANTgine `Test/commit` (97 gtests) | The ONNX engine, the detector's decoding, the config loaders, the GStreamer pipeline; under ASan and UBSan, and once more under TSan | AccelerANTgine's Linux and Windows lanes |
| C++ fuzz tests | AccelerANTgine `Test/fuzz` (FuzzTest) | The JSON and TOML config readers and the box decoder survive arbitrary input | Linux clang lane, about a second per property |
| Integration tests | `integration_test/` | The app starts in a real window; a test-pattern frame travels Rust → `knt_push_frame` → the Linux texture | Linux under Xvfb; Windows through `flutter drive` |
| End-to-end | `scripts/linux/observant/test-observant-package.sh`, `scripts/windows/observant/Test-ObservANTWindows.ps1` | The installed .deb, AppImage, flatpak and MSI start, answer every endpoint, detect, notify, and a real headless Chrome plays at least 200 frames of the stream | `web.yml`'s `observant` jobs; the Windows arm64 MSI on `windows-11-arm` |
| Clean host | the `clean-host` job of `linux-x64.yml` and `linux-arm64.yml` (ANTfrastructure's `clean-host-package-check`) | The `.deb` installs with apt on a bare Ubuntu 26.04, every ELF it installs resolves, and the app stays up 20 s under Xvfb from the `.deb`, the AppImage and the unpacked tarball. Inside the image every library exists, so only a bare host shows a missing one: its first run caught the `.deb` lacking `libegl1` (2026-10-16) | Linux x64 and arm64, on the bare runner after the lane |
| Performance | `integration_test/performance_test.dart`; OxidANT's Criterion benches | The app's frame build times at start, page switches and resizes; what a frame costs before the model, and a whole detection | Linux x64 (Flutter); OxidANT's Linux lanes |
| Gate suites | `scripts/linux/tests/`, OxidANT's `scripts/linux/tests/`, `scripts/windows/tests/` | The CI gates themselves: each suite plants the failure its gate exists for and expects it to go red | The lanes' code-quality batches, OxidANT's lint workflow, the Pester jobs |

## What the app's Dart suite checks

From the README (2026-10-19). `test/` checks, among the rest:
- every main page laid out at phone, tablet and desktop size, on a phone with its system font at
  150 % and 200 %, and on a desktop at 200 %, with the real font (`app_layout_test.dart`, using
  ANThology's dev-only `anthology_test_support` package);
- actual bottom-navigation, brightness and language taps, followed by a breakpoint change,
  preserve the selected route and router; ANThology also tests retained form state, localized
  asset reloads and native file extraction through injectable system actions;
- the camera stream's state across remounts, page changes, lost signalling and failed sessions
  (`webrtc_stream_controller_test.dart`);
- the cat status line, its visits, its arrival picture and video, and the earlier videos
  (`detection_status_test.dart`), and the visit statistics per day and hour (`visit_stats_test.dart`);
- in Chrome, the requests the Camera page sends ObservANT (`observant_api_web_test.dart`), and the
  Stream page's video view against the gstwebrtc-api build the page ships (`webrtc_view_test.dart`,
  `webrtc_view_first_view_test.dart`; § *The WebRTC view in Chrome*);
- the Camera page: what it reads from an ObservANT camera, what each button, the slider and the
  name field send, a refused change, and the page off an ObservANT camera (`camera_settings_test.dart`);
- the Stream page's calls to the plugin, its camera fallback, its buttons and its error
  messages, on Android (camera permission included), macOS and the rest, against a fake plugin
  (`stream_page_native_test.dart`); Windows and Linux handing the camera to the Rust view by
  target (`stream_page_rust_test.dart`); and the Rust camera view's calls to the core, against
  a fake core (`rust_webcam_view_test.dart`);
- the GStreamer pipeline strings, which otherwise fail only on a machine with a camera
  (`gstreamer_pipeline_builder_test.dart`);
- the settings files: a malformed key named in the error, and the web's signalling URL resolved
  against the page (`webrtc_settings_test.dart`, `settings_asset_paths_test.dart`);
- the web booting without the Rust core, and native refusing to (`rust_core_test.dart`);
- what no build step checks: the bridge's versions, the version written twice, and the browser
  database's name (`pinned_artefacts_test.dart`); and that every social link has an icon
  (`bootstrap_settings_test.dart`).

The SQLite line, the boot overlay, the locale helpers, the footer list and the routing helpers are
ANThology's since 2026-10-21, and so are their tests. The sqlite3 wasm, the icons and the title are
the hub's `check-web-artefacts.py`, which the native lane runs.

The native Linux lane measures how much of `lib/` these reach (without the generated bridge and
localizations) and fails below a floor of 96 % (`--min` in `lane-native-linux.sh`, stated once
and moved up as tests are added; the hub's `check-dart-coverage.sh`). Measured: 96.5 % on 2026-10-13 (62 %
the morning before, ahead of the native Stream page and Rust camera view tests), 97.2 % on
2026-10-16. A file no test imports is not in the report at all. The web-only files are tested in
Chrome and stay outside the figure (*Known gaps* below).

`flutter test` in the `:latest` image runs the suite in under a minute
([AGENTS.md § 5](../../AGENTS.md#5-build-run-test), *The Dart gate in 23 seconds*).

## Rules that keep a green run honest

- **Nothing skips silently.** A test that cannot run (no GPU, no model, a missing GStreamer
  element) skips locally, but CI sets `KATAGLYPHIS_REQUIRE_GPU`, `_MODEL` and `_GST` to 1 and the
  skip becomes a failure; `cargo test` hides a passing test's skip line, so nobody would see it
  otherwise. AccelerANTgine's Linux lane fails on any skipped ctest test, since ctest reports
  "100% tests passed" with skips in it, and UBSan reports are fatal (`halt_on_error=1`).
- **Coverage has floors, per part.** Dart `lib/` fails below 96 % (§ *What the app's Dart suite
  checks*). OxidANT's workspace fails below 70 %, and each crate below its own floor
  (`COVERAGE_FLOORS` in OxidANT's `ci-container-steps.sh`), so one well-tested crate cannot hide
  a weak one. Floors only move up.
- **Performance is judged against a median.** Each Linux x64 run's frame timings, and each
  OxidANT bench, are compared with the median of the default branch's last 20 runs: above +25 %
  the run warns, and a stable value at double the median fails it once 3 earlier runs exist (for
  the frame timings: an average or 90th-percentile build time at more than double). A run that
  failed never joins the history (camera-streaming.md § *Measuring performance*).
- **Mutation testing checks the checks.** Coverage says a line ran, not that a test would notice
  it change. cargo-mutants plants small bugs one at a time (a flipped comparison, a deleted
  branch, a constant return) and reruns the tests. Caught in ObservANT, at first → now:
  - network-facing code (`web.rs`, `static_files.rs`): about 84 % of 145 compiling mutants on
    2026-10-15 → 142 after tests for every gap it named;
  - arrival logic (`motion.rs`, `presence.rs`, `status.rs`): about 92 % → 375 of 379;
  - camera choice, config and webhook (`camera.rs`, `config.rs`, `notify.rs`): about 90 % → 134
    of 145;
  - frames, clips and stats (`frame.rs`, `clip.rs`, `stats.rs`, `output.rs`, `precompress.rs`):
    376 → 400 of 412; the privacy filter's colour planes had never been checked;
  - the capture loop (`capture.rs`), the weakest: 87 of 124 → 98, because most of what is left
    needs a real camera or a loaded model.

  What is left elsewhere changes nothing a client can see, or reads a real camera device, which
  no CI host has. How to run it: OxidANT's AGENTS.md.
- **A new test proves it can fail.** Each gate and property added on 2026-10-15 was run against a
  planted bug first: `..` let through the path check, an unclamped range end, a route no page
  answers, a skipped ctest test, a slowdown in the perf reports. A test that stays green against
  its own bug is not added.

## Why a lane cannot run a test

The notes under AGENTS.md's lane table, moved here on 2026-10-15.

- Android and Web build no desktop runner, so the desktop rows do not apply; Android adds the
  plugin's JVM test and the emulator run. The image carries the emulator and Chrome (hub CON50,
  owner 2026-10-01); `android.yml` opens `/dev/kvm` to the container and boots the AVD with
  `android-avd.sh` (since 2026-10-06).
- ObservANT checks live with ObservANT packages, which only `web.yml` builds, since they wrap its
  web build. They run as root in `:latest` and drive headless Chrome against the installed
  service. The MSI's run in `:winamd64` as ContainerAdministrator, where a `webrtcsrc` viewer
  plays the installed exe.
- The integration test runs on both Windows architectures by driving the app the build made
  (`flutter drive --use-application-binary`): x64 from the `-FlutterTarget` build
  `Build-WindowsDebugApps.ps1` makes on the Debug tree, arm64 from `Build-WindowsArm64App.ps1 -FlutterTarget`,
  because `flutter test -d windows` would build with Flutter's MSVC default.
- The mutation suite builds synthetic ELFs for the Linux closure gate; Windows has no ELF and no
  such gate. The element gate asks the bundle's plugins through `gst-inspect-1.0`; only a Linux
  bundle loads its plugins alone. Pester tests PowerShell that only Windows lanes run.
- The plugin's C++ format gate needs only the sources, so one lane grades them for every
  platform; Windows has no C++ format step. The coverage floor is the same kind of check: one
  lane's `flutter test --coverage` measures the same Dart everywhere. Since 2026-10-15 that is the
  Dart gate's own test run (the hub's `flutter_checks.sh --coverage`), not a second one, which had
  cost 55 s on every push.
- The rustc stamp lives in an ELF `.comment`, which a Windows PE does not have. The web lane
  builds its wasm with `build-web` and the dated nightly it names (AGENTS.md § 4), not Cargokit.
- The clean-host job is Linux's: the Windows lanes already check the runner outside `:winamd64`
  (C ABI, import walk, launch smoke), Android's run is the emulator's, and the web lane's
  packages are ObservANT's, whose checks install them as well. A Debian 13 start is checked by
  hand on a Raspberry Pi (camera-streaming.md § *Relocatable Linux bundles*).
- The frame timings run on Linux x64 alone: a profile build costs minutes, and one arch is enough
  to see the Dart side get slower. `reusable-linux.yml` keeps the default branch's last 20
  `out/perf/frontend.json` in `.perf-baseline/` and writes the comparison with their median into
  the run's summary (thresholds: § *Rules that keep a green run honest*).
- The webcam frame test is Linux-only: `hasPushedFrame` is the Linux plugin's, and the Windows
  drives run `simple_test.dart`.
- The web lane runs both Dart suites in Chrome since 2026-10-05 (`--test-platform chrome` to the
  hub's gate); the VM-only files are `@TestOn('vm')` and still run on every native lane. Chrome
  still *compiles* them, so a VM-only test must compile for web too: a plain `int` for a Rust
  `i64` field failed web run 38255398872 (AGENTS.md § 4, `PlatformInt64Util.from`).
  `flutter test --platform chrome` in `:latest` shows it before a push.
- Every lane runs the plugin's Dart tests through the same strict gate as the app's:
  `run_flutter_common_checks` on Linux, *Plugin Flutter Tests* in `Build-Windows.ps1`,
  `Invoke-FlutterTests.ps1` on arm64.
- **When a lane runs** is the family's rule (owner, 2026-10-15):
  [`branch-and-release-strategy.md`](../../third_party/ANTfrastructure/docs/branch-and-release-strategy.md).
  A push to `develop` runs Linux x64 alone, so a test that only another column runs is proved by
  asking for that lane: `[ci windows]`, `[ci arm64]`, `[ci android]`, `[ci web]` or `[ci all]` in
  the commit message. `release.yml` runs every lane on each push to `main`
  (project-operations.md § *Release Hygiene*).

## Running them

```bash
# Dart: the app's suites, the plugin's, and the integration test (needs a display).
flutter test
(cd packages/kataglyphis_native_inference && flutter pub get && flutter test)
xvfb-run -a flutter test integration_test/simple_test.dart -d linux

# Frame timings in profile mode, and where a slow frame spends its time.
xvfb-run -a flutter drive --profile -d linux --driver=test_driver/perf_driver.dart \
  --target=integration_test/performance_test.dart
python3 third_party/ANTfrastructure/linux/scripts/05-frameworks/flutter/frontend-perf-report.py out/perf/frontend.json

# Rust, as CI runs it (fetches the model, demands GPU, model and GStreamer), in :latest:
(cd third_party/OxidANT && bash scripts/linux/ci-container-steps.sh test)
# More random inputs per property, for a deeper look than CI's 256:
(cd third_party/OxidANT && PROPTEST_CASES=100000 cargo test -p kataglyphis_observant properties)
```

The plugin is its own package with its own lock, so the root's `flutter test` never reaches its
suite. `flutter test --platform chrome` shows before a push what the web lane will say; it
compiles every test file for Chrome, the VM-only ones too (§ *Why a lane cannot run a test*).

## The WebRTC view in Chrome

`webrtc_view_test.dart` and `webrtc_view_first_view_test.dart` (2026-10-20) run `webrtc_view.dart`
on the real gstwebrtc-api: a hybrid isolate reads the build `web/index.html` imports, so a new
version is tested as it ships. Only ObservANT is stood in for, by
`test/support/gst_signalling_stand_in.js`: a WebSocket that speaks the gst-plugins-rs signalling
protocol, and a producer that offers a 64×48 canvas over an in-page `RTCPeerConnection`, so ICE,
the data channel and the decoded frames are Chrome's own. They check each stage's overlay, the
frames in the view's video and stats, the ICE servers reaching the peer connection (a TURN entry
with its credentials; none when none are set; a TURN entry without them dropped, which Chrome would
refuse), a camera leaving and coming back, lost signalling, an offer Chrome rejects, a session that
cannot start, a session the camera ends while still announced (caught by its frozen picture), a
hidden tab, a remount, the control data channel and the 30 s keep-alive. Of 22 bugs planted in the
view on 2026-10-20 (a stream never attached, a callback dropped, the frame reports cut, the tab's
visibility unwired), 21 fail them. The one left crashes where `createConsumerSession` returns
`null` and ends the same: gstwebrtc-api returns `null` only between a socket's close and the
disconnect it announces next, and swallows a listener's exception.

```bash
flutter test --platform chrome test/webrtc_view_test.dart test/webrtc_view_first_view_test.dart
```

- **About 70 s**, 30 of them the keep-alive.
- **The tests share one page.** The view's video, API and controller are process-wide, so
  `webrtc_view_test.dart` runs in order, each test starting where the last left the stream; what
  only a page's first view decides (producer, ICE servers, URL) has its own file.
- **`flutter test` renders no platform views**, so the stand-in finds the video where the view sets
  its stream, and the remount test puts it into the page itself.
- **A gstwebrtc-api bump keeps the import line's shape** (`import GstWebRTCAPI from
  './javascript/webrtc/gstwebrtc-api-<version>.esm.js'`), or the tests fail at load with
  `web/index.html no longer imports a gstwebrtc-api build`.

## Known gaps

As found on 2026-10-15, so a green run is read for what it is:

- **Tarpaulin skipped feature-gated Rust code** (`crates/media`, the webcam engine) until
  OxidANT dropped its features on 2026-10-20; its coverage report is OxidANT's (its AGENTS.md).
- **The native plugin's Windows and Android C++ is barely tested:** one `GetPlatformVersion`
  gtest on Windows, one JVM test on Android, nothing for the Android GStreamer glue. The Linux
  texture has two gtests since its GStreamer pipeline went on 2026-10-21 (the colour before a
  frame; the `knt_push_frame` codes and registry, a transparent frame shown opaque); its four
  pipeline gtests of 2026-10-15 went with the pipeline.
- **Web-only Dart is outside the coverage figure.** `webrtc_view.dart` and the other files behind
  `dart.library.js_interop` (`*_web.dart`, the gstwebrtc interop) never load on the VM, and
  `flutter test --platform chrome --coverage` runs the tests, writes no lcov and exits 1 (Flutter
  3.47.6), so their Chrome tests count towards no floor. `webrtc_view.dart` has them since
  2026-10-20 (§ *The WebRTC view in Chrome*); measured once through Chrome's V8 coverage, they run
  218 of its 221 mapped lines, all but overlay texts for a stage that never shows them.
  `observant_api_web.dart`, through which the Camera page reads and saves ObservANT's settings, has
  a Chrome-only test since 2026-10-15 (`observant_api_web_test.dart`, `@TestOn('browser')`): it
  swaps the page's `fetch` for a fake and checks each request's URL, method, header, JSON body and
  timeout, and that an error status or a failed request reads as nothing.
- **ANThology's own tests run in its repository only** (on the VM, and in Chrome since
  2026-10-21), and a third of its `lib/` files have none. Its sortable table, behind the blog overview here and four lists on the website, got its
  first tests on 2026-10-15, and they found three sorting bugs.
- **C++ fuzzing runs in unit mode only**, about a second per property, without coverage feedback.
  AccelerANTgine forces `FUZZTEST_FUZZING_MODE` off (`third_party/CMakeLists.txt`): FuzzTest's
  coverage flags recursed with AddressSanitizer. Its targets read config files and decode boxes;
  what a network peer sends is parsed in Rust, where the property tests above run.
- **Windows does not demand the model**, so its real-model tests pass by skipping: its unit tests
  run before the model is fetched (OxidANT's `BACKLOG.md`). The riscv64 lane fetches and demands
  it since 2026-10-15.

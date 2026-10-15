# Testing

What each kind of test in OmniAccelerANT, OxidANT (the Rust core) and AccelerANTgine (the
C++ core) proves, the rules that keep a green run honest, how to run them, and what is not
covered yet. Which lane runs which test is AGENTS.md § *What each lane tests*; this page is
the why behind that table (written after the test audit of 2026-10-15).

## What runs, and what it proves

| Kind | Where | What a pass means | Runs in |
| --- | --- | --- | --- |
| Dart unit and widget tests | `test/`, the plugin's `test/` | Page logic and state; the shipped settings files load and name assets that exist; every page lays out at a phone's, a tablet's and a desktop's size, at 150 % and 200 % text, and lands on its own route rather than the error page | Every lane on the Dart VM; the web lane in Chrome |
| Rust unit tests | OxidANT `crates/*`, `src/` | ObservANT's motion, arrival, clip and HTTP rules; the webcam engine on `videotestsrc` with the real model, headless; the detector on a real photo | OxidANT's Linux and Windows lanes |
| Property tests | OxidANT `crates/observant` (`mod properties`) | A rule holds for every input, not a few examples: no request path, however encoded, leaves the web root; a served byte range stays inside the file; a public host name is refused; a config that validates keeps its numbers in range | With the Rust unit tests, 256 random inputs per rule and run |
| C++ unit tests | AccelerANTgine `Test/commit` (97 gtests) | The ONNX engine, the detector's decoding, the config loaders, the GStreamer pipeline; under ASan and UBSan, and once more under TSan | AccelerANTgine's Linux and Windows lanes |
| C++ fuzz tests | AccelerANTgine `Test/fuzz` (FuzzTest) | The JSON and TOML config readers and the box decoder survive arbitrary input | Linux clang lane, about a second per property |
| Integration tests | `integration_test/` | The app starts in a real window; a test-pattern frame travels Rust → `knt_push_frame` → the Linux texture | Linux under Xvfb; Windows through `flutter drive` |
| End-to-end | `scripts/linux/observant/test-observant-package.sh`, `scripts/windows/observant/Test-ObservANTWindows.ps1` | The installed .deb, AppImage, flatpak and MSI start, answer every endpoint, detect, notify, and a real headless Chrome plays at least 200 frames of the stream | `web.yml`'s `observant` jobs |
| Performance | `integration_test/performance_test.dart`; OxidANT's Criterion benches | The app's frame build times at start, page switches and resizes; what a frame costs before the model, and a whole detection | Linux x64 (Flutter); OxidANT's Linux lanes |
| Gate suites | `scripts/linux/tests/`, OxidANT's `scripts/linux/tests/`, `scripts/windows/tests/` | The CI gates themselves: each suite plants the failure its gate exists for and expects it to go red | The lanes' code-quality batches, OxidANT's lint workflow, the Pester jobs |

## Rules that keep a green run honest

- **Nothing skips silently.** A test that cannot run (no GPU, no model, a missing
  GStreamer element) skips locally, but CI sets `KATAGLYPHIS_REQUIRE_GPU`, `_MODEL` and
  `_GST` to 1 and the skip becomes a failure; `cargo test` hides a passing test's skip
  line, so nobody would see it otherwise. AccelerANTgine's Linux lane fails on any skipped
  ctest test, since ctest reports "100% tests passed" with skips in it, and UBSan reports
  are fatal (`halt_on_error=1`).
- **Coverage has floors, per part.** Dart `lib/` fails below 95 % (97.1 % on 2026-10-14).
  OxidANT's workspace fails below 70 %, and each crate below its own floor
  (`COVERAGE_FLOORS` in OxidANT's `ci-container-steps.sh`), so one well-tested crate cannot
  hide a weak one. Floors only move up.
- **Performance is judged against a median.** Each Linux x64 run's frame timings, and each
  OxidANT bench, are compared with the median of the default branch's last 20 runs: above
  +25 % the run warns, and a stable value at double the median fails it once 3 earlier
  runs exist. A run that failed never joins the history (camera-streaming.md § *Measuring
  performance*).
- **Mutation testing checks the checks.** Coverage says a line ran, not that a test would
  notice it change. cargo-mutants plants small bugs one at a time (a flipped comparison, a
  deleted branch, a constant return) and reruns the tests: on ObservANT's network-facing code
  (`web.rs`, `static_files.rs`) they caught about 84 % of 145 compiling mutants on 2026-10-15,
  and 142 after tests for every gap it named. The 3 left change nothing a client can see.
  How to run it: OxidANT's AGENTS.md.
- **A new test proves it can fail.** Each gate and property added on 2026-10-15 was run
  against a planted bug first: `..` let through the path check, an unclamped range end, a
  route no page answers, a skipped ctest test, a slowdown in the perf reports. A test that
  stays green against its own bug is not added.

## Running them

```bash
# Dart: the app's suites, the plugin's, and the integration test (needs a display).
flutter test
(cd packages/kataglyphis_native_inference && flutter pub get && flutter test)
xvfb-run -a flutter test integration_test/simple_test.dart -d linux

# Frame timings in profile mode, and where a slow frame spends its time.
xvfb-run -a flutter drive --profile -d linux --driver=test_driver/perf_driver.dart \
  --target=integration_test/performance_test.dart
python3 scripts/linux/frontend-perf-report.py out/perf/frontend.json

# Rust, as CI runs it (fetches the model, demands GPU, model and GStreamer), in :latest:
(cd third_party/OxidANT && bash scripts/linux/ci-container-steps.sh test)
# More random inputs per property, for a deeper look than CI's 256:
(cd third_party/OxidANT && PROPTEST_CASES=100000 cargo test -p kataglyphis_observant properties)
```

The plugin is its own package with its own lock, so the root's `flutter test` never reaches
its suite. `flutter test --platform chrome` shows before a push what the web lane will say;
it compiles every test file for Chrome, the VM-only ones too.

## Known gaps

As found on 2026-10-15, so a green run is read for what it is:

- **Tarpaulin does not measure feature-gated Rust code.** Every module behind
  `#[cfg(feature = …)]` is missing from its report, `crates/media` and the webcam engine
  among them, although their tests run. `cargo llvm-cov` would see them; the image does
  not carry it (OxidANT's AGENTS.md).
- **The native plugin's Windows and Android C++ is barely tested:** one `GetPlatformVersion`
  gtest on Windows, one JVM test on Android, and nothing for the Android GStreamer glue. The
  Linux texture has six gtests since 2026-10-15 (pipeline errors as Dart sees them, a
  transparent test pattern shown opaque, the `knt_push_frame` codes and registry), each
  checked against a planted bug.
- **Web-only Dart is outside the coverage figure.** `webrtc_view.dart` and the other files
  behind `dart.library.js_interop` never load on the VM, and the Chrome run measures
  nothing; the ObservANT package test's real browser is what covers them.
- **ANThology's own tests run in its repository only**, and a third of its `lib/` files have
  none.
- **C++ fuzzing runs in unit mode only**, about a second per property, without coverage
  feedback. AccelerANTgine forces `FUZZTEST_FUZZING_MODE` off (`third_party/CMakeLists.txt`):
  FuzzTest's coverage flags recursed with AddressSanitizer. Its targets read config files and
  decode boxes; what a network peer sends is parsed in Rust, where the property tests above run.
- **Windows and riscv64 do not demand the model**, so the real-model tests may skip there.

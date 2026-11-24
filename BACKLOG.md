# Backlog

Follows the protocol ANTfrastructure's agentic loop (`shared/agentic-loop/`)
consumes, so the loop this repo adopted on 2026-09-13 (`scripts/agentic-loop/`,
§ *Agentic loop* below) reads it unchanged.

## Protocol

- `- [ ]` actionable — the planner may pick it up
- `- [b]` blocked — skipped, and excluded from the pending count, so a
  backlog containing only blocked items still lets the planner run again
- `- [x]` completed — pruned on sight; the history lives in git

## Open — ObservANT

The installable ObservANT: `docs/source/camera-streaming.md` § *The ObservANT package*.
Linux amd64/arm64 ship as a .deb and an AppImage, proven on a Raspberry Pi 5 on
2026-10-05, and as a flatpak, proven in `:latest` on 2026-10-06. Windows x64 ships as an MSI
and an MSIX, proven on a Windows 11 host (2026-10-06); arm64 ships the same pair, its MSI
installed and tested on `windows-11-arm` and its MSIX checked (2026-10-16). These rows are
what the owner's goal still lacks.

- [b] **A USB webcam through `camera = "auto"` on amd64 or arm64.** Proven on riscv64:
  on 2026-10-13 mintberrycrunch's unit found its C270 by itself (`v4l2src /dev/video9 (C270
  HD WEBCAM)`), `/healthz` named it and headless Chrome played 767 frames. The test Pi and
  tabblscatcam have Pi cameras only. Blocked on a UVC camera at an amd64 or arm64 board.
  Done when `/healthz` names it there and a browser plays it.
- [b] **A real cat's arrival on the owner's phone, picture first and video after.** Since
  2026-10-12 the test Pi's ObservANT posts to the owner's Home Assistant, whose automation
  (`docs/source/camera-streaming.md`, *A phone notification with the picture*) sends
  arrivals at 0.45 or more to the phone with `/arrival.jpg`, and updates that notification
  with a tap to `/arrival.mp4?t=` once the clip's event comes. Test arrivals posted to that
  webhook reached the phone; the service's own arrival and clip POSTs are proven against
  a loopback stand-in (`test-observant-package.sh`; OxidANT's `notify.rs`), and a
  clip from the packaged service on the cat photo played (16:21, 603 kB). The visit
  statistics, the outage alert, the departure that updates the notification with the stay
  and the 21:00 summary run in the same Home Assistant; the summary's first run (21:00)
  finished without an error, and a test departure set the stay. Blocked on a cat. Done
  when one's arrival lands on the phone with its picture, a tap plays its video, and its
  departure adds the stay.
  - 2026-10-14: real cats at the feeding trough and in the living room, 58 arrivals at 0.45
    or more counted by 12:26. Home Assistant's side ran, but many pushes failed with `not
    connected to local push notifications` (the minimal app was not connected; its
    *Persistent connection* wants *Always*), and 30 events were dropped at the
    automation's `max: 10`, now 40. Whether one reached the phone needs the owner's look.
- [b] **The Windows ObservANT with a camera, at a real logon.** The MSI works
  in the image and on a real Windows 11 host (`scripts/windows/observant/`, 2026-10-06),
  and `web.yml`'s `observant-windows` job packages and tests it around every web build.
  - **In the image:** `Test-ObservANTWindows.ps1` passed all 14 checks: the MSI's LAN-only
    firewall rule, the silent install, a scrubbed-environment run loading only its own
    modules, a `webrtcsrc` viewer decoding 60 frames, the bundled model finding the cat,
    and a clean uninstall.
  - **On the dev box** (Windows 11 Pro, no camera), installed and removed through UAC:
    - the firewall rule was an inbound allow for the exe, `LocalSubnet` only, and went with
      the uninstall;
    - started from its Startup shortcut, the exe served the page and a test pattern
      (`no camera found`), loading all 128 modules from its folder or Windows;
    - the test Pi reached the page through the rule, and a browser on another device on
      the LAN played the stream.
  - **The MSIX** (`-Msix`, 2026-10-06) passed `Test-ObservANTMsix.ps1 -Install` 12 of 12
    on the dev box, with a per-build test certificate trusted. The test Pi reached the page
    through its port rules.
  - **Still unproven:**
    - a camera: Media Foundation or kernel-streaming capture on a Windows host that has
      one;
    - the start at a real sign-in, for the MSI's Startup entry and the MSIX's startup
      task; the shell ran the shortcut, no logon did, and the task stays unregistered
      until one;
    - an MSIX signed by a certificate users already trust; `-MsixPfx` takes the owner's;
    - the arrival clip: the MSIX packs `gstisomp4.dll` from `:winamd64` (run 41720025415), but no
      recorded clip has been shown on Windows.
  - **The web build as Linux ships it** (2026-10-17): `Package-ObservANT.ps1` cuts the same
    renderers and maps, and on x64 runs `--precompress`, which `Test-ObservANTWindows.ps1` checks
    (camera-streaming.md, *The Windows ObservANT*). `web.yml` has run it since (2.2.1's release
    round, 2026-10-18); open: `.gz` files for arm64, whose producer cannot run on the amd64
    packaging host.
  - **arm64 ships too** (2026-10-16): cross-built in `:winarm64`, its MSI installed and tested on
    `windows-11-arm`, its MSIX packaged and checked, in every release; the hub's CON63 it waited
    on is done since 2026-10-11.
  - Autostart is a logon task by owner decision. A boot-time service would run in
    Session 0, and on a PC with a webcam it first needs proof that LocalSystem or
    LocalService can open the camera there at all.
- [b] **ObservANT flatpak on a real Linux desktop.** `package-observant.sh` builds it
  since 2026-10-06, and `web.yml` tests it on x64 and arm64 with the .deb and the
  AppImage.
  - In `:latest` it installed, answered `/healthz` from its sandbox, and headless Chrome
    played it over the LAN address. Its first start wrote the sign-in entry.
  - **On a real desktop** (Ubuntu GNOME, amd64, 2026-10-08): CI's bundle installed as a user
    install, fetched its runtime from Flathub (24.08, end-of-life), wrote the sign-in entry,
    and the host's Chrome played 582 frames over the LAN address.
  - **On runtime 26.08 since 2026-10-11:** `web.yml` run 38158462452 (7af04e4) built the bundle on
    `org.freedesktop.Platform/26.08` for x64 and arm64, and `test-observant-package.sh` installed and
    removed it on both (`PASS flatpak installs it`); the app flatpak of Linux x64 run 38158462860 built
    on 26.08 too.
  - **Still unproven:**
    - the start at a real sign-in (the entry is in place on that desktop);
    - a USB camera through `--device=all`.
  - It has no boot service and no Pi camera by design; those stay with the .deb and the
    AppImage.

- [b] **The riscv64 `.deb` is built by hand, on the board.** mintberrycrunch built and runs it
  (2026-10-13; camera-streaming.md § *Field tests on real boards*), but no lane builds or install-tests it:
  GitHub has no riscv64 runner, `test-observant-package.sh` needs the AppImage, the flatpak and a
  Chrome for Testing that riscv64 lacks, and a Raspberry Pi 5 cannot emulate the image (16 KiB
  pages, `third_party/OxidANT/docs/ci.md` § *The riscv64 lane*). A 4 KiB-page host could run
  `package-observant.sh` in the riscv64 `:latest` under QEMU, 20 to 30 times slower than the
  board's 8 min. Blocked on a runner, or on the hub making that QEMU path a lane.
- [b] **A cheaper model, or a cheaper picture.** Measured 2026-10-14 at 01:00, one minute
  each, CPU of the service process:
  - the test Pi (Pi 5, imx219, rotate 180, dark): 3 % of a core, no model run;
  - tabblscatcam (imx708, rotate 270): 21 %, no model run: resampling the turned picture,
    not the model. Since the camera captures 480x360 when turned a quarter (OxidANT
    `capture_size`, 2026-10-14) it is 4 % at night and 10 % by day with 11 model runs a
    minute; by daylight its turned picture is upright, undistorted and bordered as before;
  - mintberrycrunch (riscv64, C270, lit): 16 % of one of 8 cores, 12 model runs a minute.

  The model stays at 640x640. Measured 2026-10-15 with ModelANT c9b81a4 (whose `--size` export
  works since) on the 11 real arrival pictures of 2026-10-14, Pi 5, 2 threads, at the
  cameras' 0.25: 640 found the cat in 6 at 273 ms a run, 480 in 4 at 171 ms, 320 in 1 at
  97 ms. 480 lost both small cats at the living-room picture's edge and two feeding-trough
  scores fell from 0.86 and 0.63 to 0.40 and 0.35; with the motion gate the boards spend 2-4 %
  of a core, so the time is not worth the cats. `fps = 15` in a board's `observant.toml`
  still halves the capture cost at once, at a less smooth stream. Blocked on the owner: 15 fps
  or not.
- [b] **A board's speed is watched only by hand** (S, ★★). `scripts/linux/observant/bench/model.sh` and
  `viewer.sh` measure a board when someone runs them, against the baseline of 2026-10-14
  (camera-streaming.md, *Measuring performance*); the one `--perf-host` baseline is a desktop's
  (`perf/baseline-amd-ryzen-9-5950x-16-core-processor.json`). The boards report `stats.model_ms`,
  `capture_fps` and `cpu_percent` in `/healthz`, and nothing keeps them over time. First step: the 21:00
  summary (camera-streaming.md, *At 21:00 a summary*) carries the day's median `model_ms` beside the
  visits. That shows a slow release after the boards took it; it is no gate. No budget is set, as none
  was measured. Blocked on the owner: the summary runs in the owner's Home Assistant. The size is this
  step's; the audit's wider finding is L and lives in the other repos. Audit 2026-11-12.

## Language AI

- [ ] **LAI-F4: microphone input in the app** (M, ★★). Hub language-AI milestone 3 (`docs/language-ai.md`).

- [ ] **The web playground's stream has not run against a real endpoint** (S, ★★). Since 2026-11-16 the request asks
  for a stream with the usage last (owner decision, replacing LAI-F2's whole answer); the reader is tested on a fake
  transport and a fake fetch, but nobody read a cross-origin body as it arrived. Next: one run in a real browser
  against a real endpoint with CORS (owner). Done when a real server's answer appears word by word and Stop ends it.
- [ ] **A thinking model's reasoning can be read** (M, ★). It is counted and hidden on web and on native builds;
  the audit puts a collapsed view last, and it needs a widget in ANThology. Native builds get the count as
  `done`'s `thinkingChars`, and a reply without words ends as the `noAnswer` failure. Done when the page shows
  the count, and the text on request.
- **llguidance accepts the hub tiny model's tokenizer** (probe 2026-11-01, GenAI 0.17.0 in
  `:latest` 7d4d4129). `set_guidance("json_schema", ...)` loaded on both the tiny model and
  SmolLM2-135M; a schema with `maxLength`, no extra properties and fixed whitespace makes the tiny
  model decode `{"a":"#$%"}` and stop at its end token, so schema tests need no SmolLM2 fallback.
  An unbounded schema lets the tiny model emit whitespace until the budget ends. At that probe
  Windows' GenAI was built without guidance (hub LAI-H2), so a schema there answered the
  unsupported error. The hub pin d66d390 builds it with llguidance (the hub's
  `windows/scripts/build/Build-OnnxGenaiFromSource.ps1:66`), and OxidANT 254b7ea and AccelerANTgine
  2fb3ab7, both newer than the pins here, expect a schema answer there. No test here runs a
  schema on Windows (`integration_test/text_generate_test.dart` is Linux-only).

## Open — browser/WebAssembly feature parity

- [ ] **Port the existing OmniAccelerANT feature set to browser/WebAssembly with local AI inference** (L, ★★★).
  Owner request 2026-11-17: a hosted browser version preserving the application's existing
  functionality and workflows, using the family's own ONNX Runtime Web builds.
  - Inventory the current desktop, mobile and web functions and record their browser equivalents:
    image/video detection, text AI, camera/stream controls, settings, storage and device integrations.
    Native-only capabilities need a tested browser implementation or compatibility bridge;
    unresolved feature gaps remain open.
  - Reuse the Flutter web UI and connect a browser inference backend to matching, version-pinned
    JS/MJS/WASM assets from ANTfrastructure. Support Asyncify and JSPI where available, detect
    capabilities, expose actual WebGPU use and make CPU fallback visible.
  - Port camera, file and persistence access to browser APIs while retaining existing WebRTC,
    remote-endpoint and device workflows. Local inference keeps user inputs on the visitor's
    device; remote modes remain explicit choices.
  - Preserve model/runtime provenance and original license texts. Provide reproducible hosting
    with HTTPS, correct asset paths/MIME types, required isolation headers and model caching.
  - Test real model inference with the shipped assets against the CPU reference, using the
    existing detector tolerances and actual GPU evidence over repeated runs. Cover supported
    browsers, fallback/refusal paths and the inventoried workflows; retain native regression tests.
  Done when the hosted application has tested browser equivalents for the inventoried functions
  and runs its local AI on the visitor's device with the family's own web builds. Browser support,
  remaining gaps and reproducible build/test/deployment commands are documented; recurring
  functionality lives in versioned scripts in its owning repository.

## Open — packaging


- [ ] **`--onnx-check` from a real NVIDIA package with the pinned CUDA probe** (S, ★★). The OxidANT (02d1d88) and
  AccelerANTgine (82597da) pins run one kernel first and name the card
  (third_party/ANTfrastructure/docs/linux-accelerator-images.md, A card without a CUDA kernel). An older NVIDIA package with
  those pins' `liboxidant.so`, `libAccelerANTgine.so`, plugin, `libapp.so` and Flutter assets swapped in names the RTX 2080
  and exits 1 where the unmodified one stops on `cudaErrorNoKernelImageForDevice` (2026-11-04, in the CI image with the
  host's CUDA libraries). `--onnx-check` does not reach AccelerANTgine's own probe. Done when a real NVIDIA package with
  those pins, from an owner-dispatched `linux-gpu-candidates.yml` run, names the card the same way.

- [ ] **The NVIDIA packages have not run on a GPU they support** (S, ★★★). The Linux and Windows packages are built and
  passed on the CPU, and hosted runners have no GPU. Done on an RTX 30xx or newer when
  `compare_detector_parity.py` passes against the CPU and the profile shows the provider; the hub's
  `docs/gpu-artifact-receipts.md` has the commands. DirectML on an NVIDIA card is unproven too.
  The owner runs this on a machine with an NVIDIA GPU. No release until this and the Linux AMD check are done.

- [ ] **The Linux AMD packages have not run with the plugin module, on a card or off it** (S, ★★★). Hub CON231 step 2
  for this app. `:latest-rocm` has no in-tree MIGraphX provider any more, so the packages carry AMD's plugin module
  `libmigraphx-ep.so` beside the CPU core, and OxidANT a8fa8d5 registers it as `MIGraphX`
  (`docs/source/camera-streaming.md`, Linux GPU build selection). **Off the card, done 2026-11-20:** the
  `linux-gpu-candidates.yml` run 44719507853 with `gpu-tuple: amd-x64` passed all four steps below; on the hosted
  runner without a card the tar, the DEB and the AppImage each refused `migraphx` by name with `ProviderUnavailable:
  MIGraphX failed to register: <the package's module>` and ran `auto` on the CPU, with no crash and no HIP wait. The
  steps, for the record:
  1. `check-gpu-image-runtime.sh migraphx`: the image's CPU core against one wheel as its stripped twin, the module and
     its texts.
  2. The native build in the rocm image, then `check-bundle-closure.sh`: the hub's census with
     `--library-path lib/glibc:lib` on the real module (OxidANT run 43314831939 stopped there without the option).
  3. `verify-gpu-candidate.sh amd x64`: module and texts against the image's in tar, DEB and AppImage.
  4. The clean-host job: `migraphx` by name must fail with `ProviderUnavailable: MIGraphX failed to register: <the
     package's module>` and `auto` must run. On a host with ROCm and no card nobody has seen what registration does
     (an error, a crash or the 30 s HIP wait).
  One thing to watch on the card: the bundle holds the chain ONNX Runtime as two real files, `libonnxruntime.so.1`
  (the native plugin needs it) and `libonnxruntime.so` (OxidANT opens it by path). With stand-in libraries of that
  shape under glibc 2.41, the process held both copies, and a module without a run path bound its
  `libonnxruntime.so.1` import to the first while the second had opened it. Read from the build files and that test,
  not seen in the app. AMD's source takes the API from the registration call, so it may not matter.
  Under WSL on the RX 9070 XT even a plain HIP copy does not return (hub CON202), so the card run takes native Linux:
  the owner runs it under Ubuntu on that machine. Done when `profile-gpu-packages.sh <dir> amd x64 migraphx` passes
  there: `compare_detector_parity.py` against the CPU, and `verify_ort_profile.py --device migraphx` with the
  plugin's operators in the profile; the hub's `docs/gpu-artifact-receipts.md` has the commands. Three stand-ins go
  when the hub owns them (hub CON256 i, j): OxidANT's `stage_amdgpu_ep_notices` and `verify_amdgpu_ep_notices`,
  called through `gpu_source_plugin_texts`; `verify_tree` on the extracted AMD AppImage instead of the hub's
  `verify-ort-appimage-payload.sh`, which asks for exact wheel bytes; and `GPU_AMD_PLUGIN_MODULE`, the module name
  repeated for the clean-host job.

- [b] **CUDA still loads through the in-tree provider** (S, ★★). Owner, 2026-11-12: only AMD moves now. The hub's
  contract says the classic CUDA append is gone on the new NVIDIA image (hub CON256 f), and the published
  `:latest-nvidia` is still the old one. Blocked on that image and on an OxidANT pin that registers the CUDA plugin.
  Then, here: the `cuda` row of `omni_linux_ort_modules` (`rust_builder/linux/ort-device.cmake`),
  `select_gpu_runtime` and `require_gpu_module_set` (`scripts/linux/lib/bundle-runtime.sh`), the module lists of
  `check-gpu-image-runtime.sh` and `verify-gpu-candidate.sh`, the ONNX Runtime row of
  `scripts/licenses/native-components.json`, and their fixtures. Done when an NVIDIA candidate builds on the new
  image and its package checks pass.

- [b] **The amd64 packages get a CPU floor that nothing here states** (S, ★★). The hub pin of 2026-11-13 carries
  the x86-64-v3 compiler default (hub CON264, `third_party/ANTfrastructure/docs/amd64-x86-64-v3-baseline.md`); no
  published image is built with it yet. From the first one, the libraries the tar, DEB and AppImage take from the
  image (ONNX Runtime, GStreamer, the compiler's libstdc++) need AVX2, FMA and BMI2, while this app's own clang and
  Rust code keeps the generic level. Blocked on that image. Then: name the floor where the docs describe the Linux
  packages, and decide whether the lane hands the level to clang and Rust
  (`CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS`, which leaves the wasm build alone). Done when the docs name
  the floor and the decision is recorded.

## Open — code audit of 2026-11-12

What the code audit of 2026-11-12 found in the Stream page, the native plugin and this repo's gates; its ObservANT and
Language AI rows are in their sections above. A second engineer checked each row against the tree, except where it
says *(not double-checked)*. All of it is read from the code: nothing was built or run, and a number marked *not
measured* is computed. Rows are in order of impact, then size, the blocked ones last. A path that starts with
`android/`, `linux/` or `windows/` is the plugin's, under `packages/kataglyphis_native_inference/`; a bare Dart file
name is under `lib/Pages/StreamPage/`.

- [ ] **Android: PLAYING as a requirement, and a faster Kotlin loop** (S, ★). The emulator check proves since
  2026-11-21 that the plugin loads, initialises GStreamer and recovers from a source's `bus error` (run 44909804182:
  `ahcsrc` missing, `autovideosrc`'s fake source fails, `videotestsrc` plays), and the Dart suite names
  `command_failed`. Left: require a `play set_state(PLAYING): SUCCESS` once the wait covers two failing sources (15 s
  each, `gstreamer_native.cpp:500-502`), and a dispatch-only workflow that compiles the Kotlin and runs its JVM test
  without the APK; its Gradle command is untested and its time not measured.

- [ ] **On Android a camera that dies still shows "Playing"** (M, ★★). Read from the code, on no device. After the
  start nothing reads the GStreamer bus: `android/src/main/cpp/gstreamer_native.cpp` reads it only inside a failing
  call (686, 706, 748), `logBusMessages` (117-150) has no caller, and "Playing" is Dart's own bool. `play()` returns
  true after a wait that timed out (752), and the wait is cut to 15 s (500-502) while the text says 20 s (702).
  Nothing under `lib/` watches the app's lifecycle, so nothing stops the pipeline in the background, and a camera
  permission granted later in the system settings needs an app restart. Closing the activity during a slow start can
  freeze it for up to 15 s: `onDetachedFromEngine` disposes on the platform thread and waits for `g_mutex`, which a
  waiting `setPipeline` holds. The first step is done (2026-11-16): `play()` answers false when its wait runs out,
  which reaches Dart as the existing play error instead of "Playing", and the texts say 15 s. Next: a
  `state` method that returns the pipeline state and drains the bus errors, asked every 2 s while the page says
  Playing; a stop on `AppLifecycleState.paused` and the last pipeline again on `resumed`; no `g_mutex` across a
  wait. Stays fixed by Dart tests on a faked `state` and by the emulator check of the first row.

- [ ] **The plugin pipeline's state machine is widget code** (L, ★★). `stream_page.dart` keeps the pipeline state and
  the fallback chain in the page's `State` with `setState` (73-125, 191-298). There is no busy guard: two source
  presses overlap, the first one's `play()` then fails with `command_failed`, and its fallback can override the second
  choice (198-244). Each test of it boots the whole app and waits 1 s of real time
  (`test/support/stream_page_app.dart:25-29`). The macOS row below comes first: it decides how much of the page is
  left to move. First step: only this pipeline moves into a pure-Dart `PluginPipelineController`, a `ChangeNotifier`
  over an `invoke` function with the phases idle, starting, playing, paused and failed, a busy guard and a typed
  problem. The web controller (`stream_controller.dart`) and `RustWebcamView` stay as they are; one status widget
  and its l10n keys for all three can follow. Stays fixed by controller tests with `fake_async` (overlapping
  requests, a stop during a start) and a source test that fails on `invokeMethod(` under `lib/Pages`; that test
  also needs the typed `create` of the MethodChannel row (`rust_webcam_view.dart:95`).

- [b] **The Pester suites still speak Pester 3.4** (M, ★). 13 suites under `scripts/windows/tests` hold
  261 dash-less `Should Be` lines, so `windows-x64.yml`, `windows-arm64.yml` and `windows-gpu-candidates.yml` pin Pester 3.4.0, the runner's inbox copy, and nothing runs
  them on Linux. The hub's next image carries Pester 6.2.0 in `pwsh` (hub CON273, CON283), which refuses that
  dialect. Blocked on that chain. Then: `Should -Be` and its kin, setup moved into `BeforeAll` or `BeforeEach`
  (Pester 5 and 6 discover a file before they run it), the `3.4.0` pins dropped, and the suites run in the image
  as well. Done when no workflow pins 3.4.0.

## Open — oxidation roadmap

The owner's decisions of 2026-11-21 on the oxidation review (D1 to D17, all as recommended): this app keeps
flutter_rust_bridge, drops its AccelerANTgine submodule, and takes new Rust API in one bundled regeneration.

- [ ] **Move the OxidANT pin to develop** (S–M, ★★★). The pin is 5caf446, OxidANT's roadmap step 3. It carries the
  native `error:` fix 2afd994 and fee17c2, which sends a failed text turn and a refused ESP32 connect into the
  stream. `integration_test/text_generate_test.dart` expects a missing model directory to end the stream with a
  `failed` event of the kind `modelLoadFailed`. Left: the `[ci windows] [ci arm64] [ci web] [ci android]` run and
  that test's first green Linux run.

## Open — native C++ gates from the BeschleunigerBallett comparison

The owner's decisions of 2026-11-21 (D3, D8, D12 and the rest, as recommended); the shared pieces are hub CON290 to
CON294.

- [ ] **The sanitizer jobs check what their names say** (S, ★★). The x64 Debug job builds an ASan+UBSan plugin gtest
  that no step runs (job 132992805094, log 9886-9907): copy the exe, `flutter_windows.dll` and the pdb out of the
  `x64_x64-ClangCL-Windows-Debug` tree the hub's sync skips (`WindowsFlutter.Common.psm1:193-195`) and run
  `Invoke-PluginGTest.ps1` with the staged ASan runtime and `UBSAN_OPTIONS=halt_on_error=1`. The arm64 "Debug/ASan"
  job instruments nothing (job 132999561812): rename it and drop its unused flag (`Build-WindowsArm64App.ps1:99-100`).
  Then an ASan+UBSan plugin gtest in the Linux Debug tree, a seeded case for random sizes, null buffers and unknown
  texture ids, `size_t` size math in `windows/kataglyphis_texture.cpp:12,16` (width*height overflows `uint32` from
  2^32), and in OxidANT a length check before `knt_push_frame`. Since a6ee053 the x64 Debug plugin and gtest take
  ASan and UBSan from the hub's `Sanitizers.cmake` through `kci_plugin_quality`; AccelerANTgine's PUBLIC options
  carried them until then.
- [ ] **Smaller native steps** (S each, ★). The hub's ELF gate on the Linux plugin once CON294 lands; `/guard:cf`
  on the Windows runner after CON290, CET only after a launch smoke on CET-capable hardware (D8); `!cancelled()` on the three uploads
  (`reusable-linux.yml:119-140`) and a googletest `URL_HASH`; `--privileged` dropped from `web.yml:56` and
  `linux-gpu-candidates.yml:119` if the lanes stay green; the Windows compiler cache fixed (0.94 % hits, save skipped,
  job 133499378065) before the hub hands its key to the other repos; D3's size change, read from the release
  artifacts before and after 9236da02, and a panic provoked in a profile build. D3 itself is in since 2026-11-21
  (`liboxidant.so` unwinds on Linux x64 and arm64, runs 44911736528 and 44911736662), and D12 too (CodeQL default
  setup for c-cpp and actions, the 96 alerts of three deleted workflows dismissed).

## Open — waiting on the owner

- [b] **False arrivals on the test Pi: nearly gone, one mark left.** On 2026-10-12 and 13 a drying rack at
  the bottom edge of the test Pi's frame made dozens of "visits" a day at 0.26 to 0.65, each
  with a clip encode, and one reached the phone. Since 2026-10-14 two fixes are in place:
  a detection starts a visit only where something moved in the last 10 s, and the Camera
  page's "Not a cat" makes ObservANT ignore a boxed spot for good
  (`docs/source/camera-streaming.md`, *Detection, visits and /healthz* and the Camera page).
  - 2026-10-14 by 09:30: one rack visit (09:09, score 0.36, 172 s, as morning light or a
    hand on the laundry moved near it), against 33 by noon on 2026-10-12. Motion alone
    narrows it; the spot needs "Not a cat" once, which the owner presses on the Camera page
    while its box shows.

  Blocked on the owner marking the rack. Done when a day counts no visit the rack made,
  while a real cat still arrives.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt overlays).
Engine, models and build driver: AGENTS.md § 2. Rules and run commands: AGENTS.md § 5.

## Quality queue

The top 5 of `logs/code-quality/queue.md` (`bash scripts/linux/quality-report.sh`), leaving out `doc-dupes-hub.allow`, which the owner keeps in every AGENTS.md; re-sync when it moves.

Owner decision 2026-11-20: only real code duplicates are merged; a pair that shares a parameter block, a test's setup
or fixture stubs stays, and a deliberate one gets a `code-dupes.allow` row with its reason. The rows below are of that kind.

- [ ] `code-dupes.allow:2` budget 103 (allow_budget_total): libjpeg-turbo's and pcre2's verbatim BSD licence texts
- [ ] `code-dupes.allow:3` budget 71 (allow_budget_total): `overview.md`'s feature tables repeat their header row
- [ ] `code-dupes.allow:4` budget 46 (allow_budget_total): the two packagers' MSI step and its three licence checks
- [ ] `scripts/linux/tests/test-check-packaged-onnx-runtime.sh:1` 48 shared shingles with scripts/linux/tests/test-check-packaged-onnx-runtime.sh:58 (duplicated_blocks)
- [ ] `scripts/windows/tests/OrtRunner.Tests.ps1:154` 41 shared shingles with scripts/windows/tests/OrtRunner.Tests.ps1:234 (duplicated_blocks)

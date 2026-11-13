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
Linux amd64/arm64 ship as a .deb and an AppImage, proven on himbeere2 (Pi 5) on
2026-10-05, and as a flatpak, proven in `:latest` on 2026-10-06. Windows x64 ships as an MSI
and an MSIX, proven on a Windows 11 host (2026-10-06); arm64 ships the same pair, its MSI
installed and tested on `windows-11-arm` and its MSIX checked (2026-10-16). These rows are
what the owner's goal still lacks.

- [b] **A USB webcam through `camera = "auto"` on amd64 or arm64.** Proven on riscv64:
  on 2026-10-13 mintberrycrunch's unit found its C270 by itself (`v4l2src /dev/video9 (C270
  HD WEBCAM)`), `/healthz` named it and headless Chrome played 767 frames. himbeere2 and
  tabblscatcam have Pi cameras only. Blocked on a UVC camera at an amd64 or arm64 board.
  Done when `/healthz` names it there and a browser plays it.
- [b] **A real cat's arrival on the owner's phone, picture first and video after.** Since
  2026-10-12 himbeere2's ObservANT posts to the owner's Home Assistant, whose automation
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
    - himbeere2 reached the page through the rule, and a browser on another device on
      the LAN played the stream.
  - **The MSIX** (`-Msix`, 2026-10-06) passed `Test-ObservANTMsix.ps1 -Install` 12 of 12
    on the dev box, with a per-build test certificate trusted. himbeere2 reached the page
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
  - himbeere2 (Pi 5, imx219, rotate 180, dark): 3 % of a core, no model run;
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
- [ ] **A board installs a new release at night with no health check and no way back** (M, ★★★)
  (not double-checked). `scripts/linux/observant/package/omni-observant-update` ends at `dpkg -i` or
  `observant --install --user` (81-87) and deletes its download on exit (70). Nothing asks `/healthz`
  afterwards, and `omni-observant.service` starts a broken build again every 5 s (`Restart=always`). Every
  push to `main` is a release, and no lane runs on a real Pi. First step: keep the running package before the
  install, then ask `/healthz` for about a minute (camera named, model loaded, frames counted); a miss exits
  non-zero. Stays fixed by two cases in `scripts/linux/observant/test-observant-update.sh`, which `web.yml`
  already runs: a fake package that never answers `/healthz`, and a healthy one that stays. Owner decision
  2026-11-13: after a miss the kept package is put back and that version is skipped, the updater's first
  downgrade (camera-streaming.md § *Updates from the releases*). Audit 2026-11-12.
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

- [ ] **The native playground still sends `top_p` and `top_k` at their defaults** (S, ★). Owner decision
  2026-11-13: both paths send each of the two only when it differs from its default. The settings page has no
  control for either, so `options()` always passes the defaults (`playground_settings.dart`) and the web body sends
  neither (`endpoint_request.dart`), which already is the decision. The native body is OxidANT's: since OxidANT
  494293f its `chat_body` leaves a default out. Done at the OxidANT pin bump that brings it, with
  `test/endpoint_chat_test.dart` holding the web body.
- [ ] **ObservANT is packaged with `--release`, not with its own profile** (S, ★★). Owner decision 2026-11-13: a
  panic in one answer costs a 502, not the camera. OxidANT 494293f adds `[profile.observant]` (release with
  `panic = "unwind"`); `scripts/linux/observant/package-observant.sh` still builds `cargo build --release` and takes
  `target/release/kataglyphis_observant`. Done at the OxidANT pin bump that brings the profile: the script builds
  `--profile observant` and takes `target/observant/`, and `test-observant-package.sh` names the profile.
- [b] **The web playground streams its answer** (S, ★★). `endpoint_chat.dart` reads an event stream when a server
  sends one (tested on a fake transport and a fake fetch), but the request still asks for one whole answer, LAI-F2's
  written choice. Blocked on the owner and on one run in a real browser against a real endpoint with CORS: nobody
  read a cross-origin body as it arrived. First step: `'stream': true` and `'stream_options': {'include_usage':
  true}` in `endpoint_request.dart`. Done when a real server's answer appears word by word and Stop ends it.
- [ ] **The web playground reads a reply of any size** (S, ★). `endpoint_chat.dart` has no bound on one stream line
  or on a whole body; OxidANT's client stops at 1 MiB per line. First step: the same bound, with the failure naming
  it. Done when a test with a line over the bound fails clearly and one under it passes.
- [ ] **A thinking model's reasoning can be read** (M, ★). It is counted and hidden on web and on native builds;
  the audit puts a collapsed view last, and it needs a widget in ANThology. On native builds an answer without a
  word is still an empty bubble, because the bridge's `done` carries no thinking count: that field needs the
  bindings regenerated with an OxidANT pin. Done when the page shows the count, and the text on request.
- [ ] **A mutation recipe holds the web client's error handling** (S, ★). Every recipe in
  `scripts/linux/tests/ort-license-mutations.json` runs a bash or python test; nobody checked that the job which
  runs them has Flutter. First step: check the mutation lane's image for `/opt/flutter`. Done when a recipe that
  makes the client ignore an error body fails `test/endpoint_chat_test.dart` in that lane.

- [b] **A failed answer is a translated frame around an English engine sentence** (M, ★★). `_onError`
  (`lib/Pages/AiPlaygroundPage/ai_playground_controller.dart:127-133`) shows `'$failure'` inside `aiError` ("Das
  Modell ist fehlgeschlagen: {detail}", `lib/l10n/app_de.arb:128`), because OxidANT's `text_generate` returns
  `Result<(), String>` (`third_party/OxidANT/src/api/text.rs:72-79`). The app cannot tell a missing model directory
  from a dead endpoint or a conversation that is too long, so it can neither translate nor say what to do. Blocked on
  OxidANT putting a fixed kind word at the front of that string, which moves no generated binding. Then each kind gets
  a sentence in both ARB files with the detail behind it, and a test that every kind has a string in both files keeps
  it. Audit 2026-11-12.

- [b] **On web an answer shows only when it is whole** (L, ★★). The playground fetches one whole answer by LAI-F2's
  choice (`docs/source/ai-playground.md:17-20`), and the Stream page's questions wait up to 310 s behind one empty
  bubble (`lib/Pages/StreamPage/observant_api_web.dart:43-54`, `visit_questions.dart:90-96`), because ObservANT's
  `/ask` is not streamed either. Blocked on the owner, one decision each: stream the playground's answer (M; it
  changes that written choice), and stream `/ask` (L; its server side is OxidANT's and comes first). Either one
  needs a pure-Dart stream reader, tested on the VM and fed by the fetch body as it arrives, with the whole answer
  as the fallback where the body cannot be read. Audit 2026-11-12.

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
  (`docs/source/camera-streaming.md`, Linux GPU build selection). All of it is proven on fixtures only: no AMD
  candidate of this layout was built, and nothing ran with AMD's module. A `linux-gpu-candidates.yml` run with
  `gpu-tuple: amd-x64` is the first real one; in the order it can stop:
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

- [ ] **The Android plugin path runs in no test, and its Dart tests use a fake that matches no plugin** (M, ★★★).
  13 of the 20 tests in `test/stream_page_native_test.dart` run as macOS, which the plugin does not have, and their
  fake fails with `pipeline_error` and `no element "x"` (51-58). The real plugin answers `command_failed`
  (`KataglyphisNativeInferencePlugin.kt:153-163`) with texts like `Missing GStreamer element: ahcsrc`
  (`gstreamer_native.cpp:406`), so the fallback in `stream_page.dart:216-223` depends on a code that no test names.
  Play, pause and stop are the same Dart code on every platform, so those tests still hold for Android; the fallback
  and the texts are unproven. `scripts/linux/check-apk-on-emulator.sh:55-59` starts the app without the camera
  permission and sleeps 20 s: create, JNI and `gst_init` never run, and an APK whose library cannot load passes.
  The android lane was the first compile of f62bcf9's Kotlin, after the push. `docs/source/testing.md` already names
  the thin Android plugin tests as a gap; the fake, the unnamed code and the emulator's missing permission are new.
  First step: install with `adb install -r -g`, require `GStreamer initialized` in logcat and fail on
  `Create failed`, `UnsatisfiedLinkError` or `bus error`, with planted-failure cases in
  `scripts/linux/tests/test-check-apk-on-emulator.sh`; and one Android-variant Dart test whose fake answers
  `command_failed` with two real messages and expects the next source. PLAYING is a later check: two failing
  sources can wait 15 s each (`gstreamer_native.cpp:500-502`). A dispatch-only workflow that only compiles the
  Kotlin and runs its JVM test is worth a try after that; its Gradle command is untested and its time is not
  measured. Done when the emulator check fails on each planted fault and the Dart test fails without the
  `command_failed` branch.

- [ ] **The desktop plugins fail hard on a call they do not expect** (S, ★★). On Windows an unknown method is a null
  dereference, not a `MissingPluginException`: `windows/kataglyphis_native_inference_plugin.cpp:203-205` moves
  `result` into `TextureMethodCall`, which takes it by value (50-52), and then calls `result->NotImplemented()`
  (not double-checked). Nothing reaches it today, since the Dart side calls only `create` and `add` on Windows; a
  `hasPushedFrame` there would. Three smaller faults, unlikely in practice: the same file reads `add` with
  `std::get<int>` (153-154), which throws on another type, and casts a negative size to `uint32_t` (177-178); Linux
  keeps `self->texture` after a failed registration (`linux/kataglyphis_native_inference_plugin.cc:95-102`), so the
  next `create` answers that texture's id (70-73). First step: Windows answers `NotImplemented` in one place, before
  any new Windows method. Stays fixed by a gtest in which `HandleMethodCall("noSuchMethod")` reaches the
  not-implemented callback, in `windows-x64.yml`'s runner job and the ASan Debug build.

- [ ] **A failed start on Android ends in a wrong text and no way to try again** (S, ★★). `_buildAndroidFallback`
  (`stream_page.dart:644-668`) promises "Falling back to WebRTC preview on Android" and builds `WebRTCView`, which on
  a native build is the stub's "only available in the web build" (`webrtc_view_stub.dart:21-34`);
  `test/stream_page_native_test.dart:422-436` pins the promise. A denied permission also shows "Error creating texture
  (null id)" (484-489) beside the right permission text; the texture future is `late final` (79), so nothing tries
  again; and a permanent denial opens the system settings on every start (159-161). First step: no WebRTC promise; one
  message per cause (permission, texture, source); the set-up as a method that a Retry button and a resume call again;
  the system settings behind a button. The three Android tests change in the same commit. Stays fixed by one widget
  test per cause: its text shows, no second text contradicts it, and Retry starts again.

- [ ] **The plugin's MethodChannel API has no owner** (M, ★★).
  `packages/kataglyphis_native_inference/lib/kataglyphis_native_inference.dart:5-19` types only `getPlatformVersion`
  and `add`; the other eight methods are called by name from app code, and the channel name is typed in 7 Dart and 3
  native files. The three plugins have drifted. Android has no `add`, so the About page's `add(3, 4)` should show
  `MissingPluginException` there (`lib/Pages/AboutMePage/about_me_page.dart:58, 67-83`; read, not run). Only Linux has
  `hasPushedFrame`. Windows wants `setPipeline` as a map where Dart sends a string, and its play, pause and stop are
  no-ops that nothing calls (`windows/kataglyphis_texture.cpp:78-88`; `windows/kataglyphis_texture.h:19` says they
  are kept for the method channel). The package's own `lib/main.dart` is still Flutter's counter template, and its
  `test/widget_test.dart` tests that. Most of the drift is in code nobody calls: a user sees only the About page's
  line on Android, and the gain is that the drift stops. First step: delete the Windows no-op handlers and the
  template with its test. Then the typed API and one table (method, arguments, result, error codes, per platform)
  as a Dart const in the package; `add` stays on desktop (AGENTS.md § 4). Stays fixed by a source test in the style
  of `test/pinned_artefacts_test.dart` that reads the method names out of the `.kt`, `.cc` and `.cpp` files and
  compares them with the table, on every push. Done when no `MethodChannel(` is left under the app's `lib/`.

- [ ] **On Android a camera that dies still shows "Playing"** (M, ★★). Read from the code, on no device. After the
  start nothing reads the GStreamer bus: `android/src/main/cpp/gstreamer_native.cpp` reads it only inside a failing
  call (686, 706, 748), `logBusMessages` (117-150) has no caller, and "Playing" is Dart's own bool. `play()` returns
  true after a wait that timed out (752), and the wait is cut to 15 s (500-502) while the text says 20 s (702).
  Nothing under `lib/` watches the app's lifecycle, so nothing stops the pipeline in the background, and a camera
  permission granted later in the system settings needs an app restart. Closing the activity during a slow start can
  freeze it for up to 15 s: `onDetachedFromEngine` disposes on the platform thread and waits for `g_mutex`, which a
  waiting `setPipeline` holds. First step: `play()` answers false on a timeout and the text says 15 s. Then a
  `state` method that returns the pipeline state and drains the bus errors, asked every 2 s while the page says
  Playing; a stop on `AppLifecycleState.paused` and the last pipeline again on `resumed`; no `g_mutex` across a
  wait. Stays fixed by Dart tests on a faked `state` and by the emulator check of the first row.

- [ ] **The `/healthz` fixture is a copy, not ObservANT's own golden** (S, ★★). One model reads `/healthz` since
  2026-11-13 (`lib/Pages/StreamPage/observant_health.dart`), and `test/observant_health_test.dart` feeds it a body
  a real ObservANT answered (`test/fixtures/observant_healthz_idle.json`, OxidANT 7abcc12 with its model, the test
  pattern as camera). That file is a copy taken once: a key ObservANT renames later leaves it, and the tests, as
  they are. Its visit fields are hand-filled in the keys `status.rs` writes, since no camera saw a cat for it, and
  `scripts/linux/tests/web-smoke-server.js` still serves its own body with a `detection.count` nothing reads.
  First step, in OxidANT: a `status.rs` test writes golden `/healthz` files (idle, a visit, a problem) and fails
  when they differ. Then the Dart test and `web-smoke-server.js` read them from `third_party/OxidANT` at the pin
  that brings them. Done when the fixture here is gone and the test parses the goldens with no shown field null.

- [ ] **No back-off when no camera answers** (M, ★★) (not double-checked). The status line asks `/healthz` every 5 s
  for ever (`detection_status.dart:261-285`), the peers' 10 s timer stops only after an own `/healthz` answered
  (`camera_peers.dart:52-60, 68-81`), and gstwebrtc-api reconnects every `reconnectionTimeoutMs`, 5000 in
  `assets/settings/webrtc_settings.json`, without a limit. The hosted site is this web build with no ObservANT behind
  it and the Stream page first: about 18 failing requests and 12 socket attempts a minute for every open tab
  (computed, not measured). `web-smoke-server.js` always answers as an idle ObservANT, so no browser test sees that
  state. First step, polling only: after a few misses the interval grows from 5 s to about 60 s and falls back on an
  answer or when the page shows again; a first answer that is no ObservANT `/healthz` stops the peers' timer. The
  signalling retry follows, in the controller, with a growing delay. Stays fixed by `fake_async` tests (ten minutes
  without an answer stay under a fixed number of fetches, and one answer restores the 5 s) and a mode of
  `scripts/linux/check-web-browser.sh` without the fixture that counts 60 s of requests against a ceiling.

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

- [ ] **Nothing times the desktop frame path or a streaming answer** (S, ★). `integration_test/performance_test.dart`
  watches the start, page switches and resizes (22-48), and `quality-report.toml`'s one perf command is
  `--detect-latency`. On Linux every frame is copied in `knt_push_frame` (`linux/my_texture.cc:344`); `copy_pixels`
  then clears the buffer, copies the frame again and rewrites each alpha byte (156-166). That is four passes of 1.2 MB
  at 640x480, about 150 MB/s at 30 fps (computed, not measured). In the playground one `AnimatedBuilder` wraps the
  page (`lib/Pages/AiPlaygroundPage/ai_playground_page.dart:71-118`), so a streaming answer parses the Markdown of
  every visible answer again on each frame (not measured). First step, measure: a timing loop in the Linux plugin
  gtest (300 pushes plus `copy_pixels` at 640x480 and 1280x720, ms per frame) under the hub's bench-history, and a
  playground section with a fake `TextClient` in `performance_test.dart` under `frontend-perf-x64`. The one change
  that needs no number: no `memset` when the sizes match. The buffers change owner only above about 1 ms a frame at
  720p, and the Markdown fix would be ANThology's.

- [ ] **macOS: the Stream page keeps a half for a platform the plugin does not have** (S, ★★). The plugin has android,
  linux and windows (`packages/kataglyphis_native_inference/pubspec.yaml:21-30`) and `docs/source/overview.md:22` says
  macOS is no target. But AGENTS.md (section 1) still gives macOS the plugin pipeline, the page keeps desktop source buttons,
  colour buttons, `setColor`, `avfvideosrc` and the appsink sink for it, and 13 of the 20 tests in
  `test/stream_page_native_test.dart` run as macOS. Owner decision 2026-11-13: macOS is no target. That UI goes,
  its tests run as Android, the AGENTS.md sentence changes, and the rows above on the Android tests, the MethodChannel
  API and the state machine get smaller.

- [ ] **Linux and Windows textures behave differently under one ABI** (S, ★). Linux keeps the texture's creation size,
  crops or pads a frame of another size and forces alpha to 255 (`linux/my_texture.cc:135-181`); Windows resizes to
  the pushed frame and copies alpha as it comes (`windows/kataglyphis_texture.cpp:34-68`), and each gtest pins its own
  side. `third_party/OxidANT/abi/texture.json` fixes names and codes, not behaviour. Nobody sees it today: Rust always
  sends RGBA at the asked size (`third_party/OxidANT/crates/media/src/capture.rs:179-195`). Owner decision 2026-11-13:
  Windows is the rule (the texture takes the pushed frame's size, alpha as sent), and Linux changes. Then one include file of cases against the C ABI beside
  the plugin, with a small adapter per platform, run by both gtests.

## Open — waiting on the owner

- [b] **False arrivals on himbeere2: nearly gone, one mark left.** On 2026-10-12 and 13 a drying rack at
  the bottom edge of himbeere2's frame made dozens of "visits" a day at 0.26 to 0.65, each
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

- [ ] `scripts/licenses/texts/native/libjpeg-turbo/LICENSE.md:137` 103 shared shingles with scripts/licenses/texts/native/pcre2/LICENCE.md:84 (duplicated_blocks)
- [ ] `docs/source/overview.md:69` 71 shared shingles with docs/source/overview.md:89 (duplicated_blocks)
- [ ] `scripts/windows/Package-OmniAccelerANT.ps1:86` 46 shared shingles with scripts/windows/observant/Package-ObservANT.ps1:190 (duplicated_blocks)
- [ ] `scripts/windows/observant/Test-ObservANTFixtureLock.ps1:31` 41 shared shingles with scripts/windows/observant/Test-ObservANTFixtureLock.ps1:44 (duplicated_blocks)
- [ ] `scripts/windows/tests/OrtRunner.Tests.ps1:154` 41 shared shingles with scripts/windows/tests/OrtRunner.Tests.ps1:234 (duplicated_blocks)

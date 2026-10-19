# Changelog

Versions follow `version:` in `pubspec.yaml`; `msix_config.msix_version` carries
the same three numbers with a fourth field of 0 (AGENTS.md § 4).

## Unreleased

### Changed

- **The README is a short overview** (2026-10-19, owner: the family's README rule). The feature
  matrix, platform summary and literature moved to `docs/source/overview.md`, the lane table and
  the by-hand API docs to `getting-started.md`, the app's Dart suite list to `testing.md`, and the
  ObservANT guide and by-hand runbook to `camera-streaming.md`, which already held most of it.
  Contributing, contact and licence are ANTfrastructure's `repository-family.md`.
- **AGENTS.md and the guides link the hub instead of restating it** (2026-10-19, hub a447ef3c).
  The family-wide procedures (branch sync, https submodule URLs, the Linux package closure with
  its glibc and GStreamer rules, the rootless engine, Rancher's per-boot binfmt and KVM, emulated
  arm64, `-v name:/path`, `dart format` and the SDK floor, the clang cfg pair, Dev Drive filters,
  raw `gst-launch` pipelines, opencode v2, the CI-round rule, Renovate's mechanics, the history
  rewrite) are links to ANTfrastructure's pages, beside this repo's own commands, numbers and
  exceptions. AGENTS.md § 2 lists topics, not facts, and its ObservANT entries point at
  `camera-streaming.md`. `doc-dupes-hub.allow` turns the hub's `doc-dupes --against-hub` gate on:
  seven restated passages before, one allowed after (the owner's docs rule). The `C:\workspace`
  mount trap is dated: images since 2026-09-26 hold no `C:\workspace` (hub CON29).
- **The API docs site has its own workflow** (2026-10-19, hub 89b098c9). `docs.yml` calls the
  hub's `build-docs.yml` with `command: bash scripts/linux/generate-docs.sh` and `site-dir:
  doc/api`: the site builds in the family image, gets the hub's `.htaccess` and 404 page, passes
  the built-site link gate and is published on a push to `develop` or `main` only, by a job no
  newer push cancels. Until now `reusable-linux.yml` uploaded `doc/api` at the end of the x64
  lane, so a red lane skipped the upload and the next push could cut it off half-way. The lane's
  `run-docs` input, its FTP step and the `SERVER`/`USERNAME`/`PW` secrets left
  `reusable-linux.yml` and `linux-x64.yml`; the lane scripts default to `--run-docs false`, and
  `Invoke-LinuxLane.ps1 -SkipDocs` became the opt-in `-Docs`. The gate in `:latest`: 909
  documents, 13 dead links, all guide links to non-Markdown repository files, which the hub's
  renderer leaves relative; `docs/site-links.allow` freezes them until it sends them to GitHub.

### Fixed

- **The ESP32 scripts pass the lint gates** that 678b3e4 turned red: `build-firmware.sh` takes the
  image ref from the hub's `ci-image-ref.sh` (`KATAGLYPHIS_IMAGE` still overrides), every comment
  in the ESP32 firmware and scripts is one line, and `build-eye-demo.sh --help` prints its header
  only, no longer three lines of code after it.
- **The Linux lane's Dart coverage floor holds again.** 678b3e4 added the Device page at 31.6 %
  and its controller at 69.6 %, which put `lib/` at 89.5 % against the floor of 96 %.
  `device_page_test.dart` drives the page over a fake bridge (ports, loading, errors, telemetry,
  LED sliders, ping, disconnect), `esp32_controller_test.dart` covers every failure path, and
  `esp32_rust_api_test.dart` checks that `RustEsp32Api` hands each call to its generated binding.
  Both files are at 100 %, `lib/` at 97.6 % (2,131 of 2,183 lines).
- **The docs site's front page links resolve.** `dart doc` renders the README as the site's
  `index.html`, where its relative links to `docs/source/`, `AGENTS.md`, `BACKLOG.md`,
  `CHANGELOG.md` and `LICENSE` and the logo were 404s. They point at `develop` on GitHub now and
  the logo at `raw.githubusercontent.com`, per the hub's README rule. `dartdoc_options.yaml` lost
  its `additional-docs` list, which lacked `esp32.md` and `testing.md` and which `dart doc` never
  read: the published guides are `generate-docs.sh`'s `DARTDOC_BUILD_GUIDES` alone.

## 2.2.1+5 — 2026-10-18

### Fixed

- **The Windows ObservANT's viewer check judges the 60 frames, not the teardown.** The release dry
  run failed once after the viewer's EOS, when the signaller lost its peer and `gst-launch` exited 1;
  that one error after the EOS passes now, any other still fails.

### Changed

- **The Pi Zero bundle copies its plugins through the hub's `gstreamer-bundle.sh` too**, so a
  missing plugin fails with the hub's one error instead of a hand-written loop's, and its list lost
  `sdp`, a plugin the image never had (it warned on every build; `webrtcsink` needs only the
  `libgstsdp` library, which the closure brings).

## 2.2.0+4 — 2026-10-17

### Added

- **The app's Windows installers** (2026-10-17, owner): every release carries an MSI and a signed MSIX of
  the main app for x64 and arm64, beside the zip. `Package-OmniAccelerANT.ps1` builds them from the
  runner on each lane's own Windows runner, with WiX 7.0.0 as the image pins it. The MSI installs into
  Program Files with a Start menu shortcut; the MSIX has `msix_config`'s identity and a test certificate,
  whose `.cer` ships beside it. `Test-OmniAccelerANTInstallers.ps1` installs both on x64 and on the arm64
  device, starts the app from each without any PATH help and removes both. `WindowsAppInstallers.Common`
  now holds the MSI and MSIX code ObservANT's packaging used alone, and the release collector expects
  the four new files.
- **Windows CI keeps sccache's cache across runs** (2026-10-17): the Release job of
  `windows-x64.yml` restores and saves `.ci-cache`, and `Build-Windows.ps1` moves it into the
  container's sccache directory and back. It switches itself on with the first `:winamd64`
  that carries the hub's sccache build, `0.18.0+1bd7432.pr2809`, which fixes clang-cl's
  module importers (mozilla/sccache#2876). On the older image it stays off and the build log
  says why.
- **sccache on the local Linux lanes has its own volume and the shared S3 level** (2026-10-17,
  owner): `Invoke-LinuxLane.ps1` keeps `/var/cache/sccache` on a named volume, so `flutter
  clean` no longer means a cold compile. It binds the host's key at `/run/secrets/sccache_s3`
  (`WindowsLaneSccache.Common`), and the lane waits for its uploads on exit. With both local
  caches deleted, the native lane hit 1,232 of 1,235 compiles from the bucket and took 5 min
  48 s, against 6 min 50 s cold. The web and android lanes pass with the level too.
- **The local Linux lanes run on a Linux host with a rootless engine** (2026-10-17): the
  driver runs them as root there, which is the host user, with `TAR_OPTIONS=--no-same-owner`.
  Before, uid 1001 could not write the checkout (`.dart_tool/package_config.json: Permission
  denied`). On such a host the driver also no longer reads Windows' `ProgramFiles`.
- **Turn the picture from the Stream page** (2026-10-16, owner): ⟲ and ⟳ beside each camera's
  name turn it a quarter each way, and the camera keeps it in its `settings.json`, so every
  board can sit at its own angle. The Camera page could do it before; now it is one click
  from the stream.
- **ObservANT without sudo** (2026-10-16): the tarball's `observant --install --user` installs
  it for the calling user, as a systemd user service with linger, its own settings in
  `~/.config/omni-observant/observant.toml` and a nightly user timer that installs a newer
  release's tarball once it matches `SHA256SUMS`. A Raspberry Pi 4 (himbeergsaelzweckle) runs
  it so. `test-observant-package.sh` and `test-observant-update.sh` cover it, the latter also
  without dpkg.
- **A Windows arm64 ObservANT** (2026-10-16): cross-built in `:winarm64`, its MSI installed and
  tested on `windows-11-arm`, and part of every release.
- **A release dry run** (2026-10-16): `gh workflow run release.yml --ref develop -f dry-run=true`
  runs every lane and the collector on `develop` and publishes nothing.
- **The Raspberry Pi 3 runs ObservANT** (2026-10-15, owner). himbeerGsaelz, a Pi 3 Model B with a
  Camera Module 3 Wide, runs the arm64 `.deb` at about 2 s per detection, 226 MB of memory;
  `docs/source/camera-streaming.md` § *Where it runs* lists every camera now.

### Fixed

- **The app flatpak starts again** (2026-10-17): it aborted at once (`No provider of
  eglGetPlatformDisplayEXT found`), because the launcher of the same day ran it under the bundled
  glibc 2.43 while org.freedesktop.Platform 26.08's Mesa needs 2.44. The hub's `bundle-loader.sh` now
  takes the bundled glibc only when the host's is older, and keeps it in `bundle/lib/glibc`;
  `runtime_paths.cc` turns GStreamer's scanner fork off wherever the bundled plugins are, since the
  bundle ships no scanner. The native lane starts the app flatpak for 20 s, and the bundle on both
  glibc paths (`KATAGLYPHIS_BUNDLED_GLIBC=1` forces the bundled one).
- **Whole-frame false visits** (2026-10-17, owner): ObservANT drops a detection covering more
  than `max_box_area` of the picture (default 0.9) before it counts. Eight of himbeere2's last
  20 visits were such boxes at scores near 0.3; `max_box_area = 1` keeps them.
- **The Linux app starts outside the build image.** The bundle carried GStreamer and ONNX
  Runtime but took `libstdc++` from the system, and the image's is GCC 16.2's
  (`GLIBCXX_3.4.36`), newer than any distro's, Ubuntu 26.04's included. It travels in
  `bundle/lib` now, and the `.deb` declares `libc6 (>= 2.43)`: the image's ORT and orc need its
  glibc, so the app runs on Ubuntu 26.04 and newer. Debian 13 and Ubuntu 24.04 need the image's
  loader as ObservANT carries it (ANTfrastructure BACKLOG CON97).
- **A clean-host job proves it** after each Linux lane: a bare `ubuntu-26.04` (`-arm`) runner
  installs the `.deb` with apt and starts it, the AppImage and the unpacked tarball for 20 s
  under Xvfb, the way the lane's launch smoke does inside the image.
- **The image's glibc travels too** (2026-10-17), so the app starts on Debian 13 and Ubuntu 24.04:
  `omni_accelerant` is a launcher that runs `omni_accelerant.bin` through the image's loader,
  kept beside it because Flutter finds `data/` from `/proc/self/exe`. The `.deb` no longer asks
  for `libc6 (>= 2.43)`. The flatpak installs the bundle whole, so its runner finds `data/` too.
- **The `.deb` declares `libegl1`, `libgles2` and `libgl1`.** That job's first run (38973418685)
  aborted the app at once with `Couldn't open libEGL.so.1`: libepoxy loads the GL libraries at
  run time, so no `NEEDED` names them, and GTK does not depend on them. Every desktop has them; a
  bare Ubuntu does not.
- **The Windows ObservANT carries ONNX Runtime's own DLLs**, the VC++ runtime included, so
  it starts on a Windows without Visual Studio's redistributable.
- **`inference = "auto"` runs the model on 1 GB boards** (OxidANT f8a2dfc). It skipped the model
  below 1024 MiB, but a 1 GB Pi 3 reports 905 MiB, so it streamed without detection; the line is
  768 MiB, above a 512 MB Pi Zero 2 W's ~430.

### Changed

- **The Linux app loads only its bundled GStreamer plugins** (2026-10-17, owner: the family's own
  GStreamer, never a distro's). `runtime_paths.cc` empties the system plugin path when the bundle
  carries its plugins, so a host's distro plugins never load beside them.
- **The app bundle and ObservANT copy their GStreamer plugins through the hub's
  `gstreamer-bundle.sh`** (CON100): one shared copy with one error for a missing plugin, instead
  of three hand-written loops; the app's element gate is the hub's `check` behind a thin wrapper.
- **The hub at `5c65bec8`, AccelerANTgine at `24de58f`.** The app's AppImage and ObservANT's take
  the image's pinned AppImage runtime instead of downloading `continuous` (`appimagetool` 1.9 never
  read the staged one), and ObservANT's packager uses the hub's `app_packaging_appimage_runtime_file`
  instead of its own copy; the bundle launcher leaves no stray child behind its `exec`; the linked
  AccelerANTgine library gives the bundle's GStreamer a registry of its own.
- **A gate proves every pipeline element loads from the bundle alone.**
  `check-bundle-gst-elements.sh` runs the image's `gst-inspect-1.0` under the app's plugin
  environment for each element the Linux pipelines name, after the closure gate; a stub suite
  plants the ways it must fail, and a Dart test ties the list to the Dart pipelines.
- **The Windows ObservANT ships the web build as Linux does** (2026-10-17): without the `wimp` and
  `webparagraph` renderers and the `*.symbols` maps (about 18 of 55 MB less), and on x64 with a zopfli
  `.gz` beside each file the server gzips, so the service no longer compresses them at run time.
  The arm64 package still gzips at run time: its producer cannot run where it is packaged.
- **One icon for the family: the ant** (2026-10-17, owner). The README logos and the plugin example
  app's Android and Windows icons are now the app's own ant (`assets/icons/kataglyphis_app_icon.png`),
  which the app already used.
- **A build report that was committed by mistake is gone** (2026-10-17):
  `android/build/reports/problems/problems-report.html` (134 KiB, Gradle's problems report)
  came in with a47525e. `/android/build/` is ignored now, so the next one stays out.
  OxidANT moves to 41845f9, whose README image is a 2.1 MiB WebP instead of a 7.5 MiB GIF.

- **A camera nobody named shows its host name** (OxidANT aa3e13e) instead of "ObservANT", so
  two new cameras differ in the Stream page's list from the start; a name from the settings or
  the Camera page still wins.
- **The Dart coverage floor is 96 %** (97.2 % measured), up from 95.
- **A release carries the app for every platform** (2026-10-16, owner): the Linux packages for
  x64 and arm64, the Android APK, and the Windows x64 and arm64 apps as zips, beside the
  ObservANT packages, which were all 2.1.0 carried. `release.yml` downloads every lane's
  uploads and `scripts/linux/collect-release-assets.sh` picks and names them (a flatpak gets its
  arch, the APK comes out of its tarball); it fails on an upload it has no rule for and on a
  missing platform. Publishing moved to the hub's `publish-github-release.sh`, which OxidANT
  shares; `scripts/linux/publish-release.sh` and its test are gone.
- **The native lane's Dart tests run once**, coverage included (hub `flutter_checks.sh
  --coverage`): about 42 s less on every push to `develop`.

## 2.1.0+3 — 2026-10-15

The first release made by a merge into `main`, and the first the ObservANT cameras update
themselves from. Most of it is the cat cam, ObservANT since 2026-10-14, whose guide is
`docs/source/camera-streaming.md` § *The ObservANT package*.

### Added

- **Branches, CI rounds and releases** (2026-10-15, owner; the family's rule in
  ANTfrastructure's `docs/branch-and-release-strategy.md`). A push to `develop` runs Linux x64
  alone; the Linux arm64, Windows x64 and arm64, Android and web lanes run when a commit message
  asks with `[ci <lane>]` (`[ci windows]`, `[ci arm64]`, `[ci all]`), read by the new
  `on-request.yml`, or by hand, since every lane has *Run workflow* now. `main` moves only
  by the owner's fast-forward to a fully green `develop` commit.
- **Releases, and cameras that update themselves** (2026-10-15, owner). Every push to `main`
  runs the new `release.yml`: every lane once more, then the tag `v<version>` and a GitHub
  release with `web.yml`'s tested ObservANT packages, a `SHA256SUMS` and the version's
  CHANGELOG section as notes, only when every lane is green. A version that is released
  already, or has no CHANGELOG section, stops it within a minute
  (`scripts/linux/publish-release.sh --check`). The `.deb` brings `omni-observant-update.timer`: every night
  it installs a newer release's package for the camera's architecture once it matches the
  release's checksum, and leaves the camera alone otherwise; `systemctl disable --now
  omni-observant-update.timer` turns it off. Both are tested: the release script against a
  stand-in `gh` in the native lane, the updater against a local stand-in for GitHub in the
  package jobs (an update, no downgrade, a bad checksum, a missing architecture).

- **Visit statistics on the Stream page** (2026-10-15, owner). A *Visits* button opens the
  last two weeks: visits today and in all, the average stay, and bars per day and per hour of the
  day, counted in the viewer's own time zone. They come from ObservANT's new `/visits` (OxidANT),
  which keeps every visit of the last 30 days in `visits.json` and is read only while the panel
  is open, every minute; `/healthz`, which the page polls, stays as small as it was.
  `test/visit_stats_test.dart` covers the counting at the window's and midnight's edges, the
  average over the visits that left, and the panel opening, closing and a camera that does not
  answer.

- **The Camera page's requests to ObservANT are tested in Chrome** (2026-10-15).
  `observant_api_web.dart`, which reads `/healthz` and `/settings` and saves settings, had no
  test, since it loads only in a browser. `test/observant_api_web_test.dart` runs in the web
  lane's Chrome (`@TestOn('browser')`, so the VM lanes skip it), swaps the page's `fetch` for a
  fake and checks each request's URL, method, `content-type`, JSON body and timeout, and that an
  error status or a failed request reads as nothing. It fails against a `PUT` and against a
  page that ignores the status.

- **Benchmarks in the projects' own tooling, tracked in CI** (2026-10-14, owner). The Flutter side
  is `integration_test/performance_test.dart` under `flutter drive --profile` with
  `test_driver/perf_driver.dart`: `watchPerformance` times the start, three rounds through every
  tab and resizes across both breakpoints. The native lane runs it on x64 under Xvfb, and
  `scripts/linux/frontend-perf-report.py` compares it in the run's summary with the median of
  the default branch's last 20 runs (2026-10-15; first against the run before, which a slow
  creep never crossed): above +25 % it warns, and an average or 90th-percentile build time at
  double the median fails the lane once 3 earlier runs exist. The Rust side is OxidANT's
  Criterion benches under `cargo bench`, judged the same way. `bench/page-perf.mjs` also times
  the signalling socket now, and `scripts/linux/flutter-trace-summary.py` names what a slow
  frame builds (how the 0.94 s start-up block below was found).

- **A test audit, and tests that can fail** (2026-10-15, the owner asked whether the tests catch
  regressions). `docs/source/testing.md` says what each kind of test proves, the rules that
  keep a green run honest, and the gaps still open. Here:
  - `test/widget_test.dart` asserted only that `App` existed after pumping it;
    `test/bootstrap_settings_test.dart` reads the shipped settings files instead (locales
    against the translations, unique blog routes, every post's markdown present).
  - `test/app_layout_test.dart` also checks each route lands on its page, not `ErrorPage`; a
    planted `/noSuchPage` now fails it.
  - The plugin's Linux gtest has six tests of the texture beside `GetPlatformVersion`: pipeline
    errors as Dart sees them, a transparent test pattern shown opaque, `knt_push_frame`'s codes
    and registry. Each was run against a planted bug in `my_texture.cc`.
  - The perf scripts have a 23-assertion suite in the native lane, and the frame timings are
    kept in `out/perf/`, which the docs step's `flutter clean` no longer deletes.
  - In the submodules: OxidANT tests its webcam engine with its real features, property-tests
    ObservANT's network and config inputs, holds every crate to its own coverage floor, and
    caught 142 of 145 planted bugs in ObservANT's network code (mutation testing);
    AccelerANTgine fails its Linux lane on a skipped test or a UBSan report and keeps
    `main()` out of its library; ANThology tests its settings readers instead of `expect(1, 1)`.

- **Performance tools and a baseline** (2026-10-14, the owner's benchmark).
  `scripts/linux/observant/bench/model.sh` times models in the installed service on a board,
  `viewer.sh` measures a board idle and with one viewer plus the page's cold load
  (`page-perf.mjs`), and camera-streaming.md § *Measuring performance* keeps the numbers: the
  model is 99 % of a detection, every viewer costs an encoder, and plain HTTP makes browsers
  load the 0.75 MB larger renderer.
- **"Too dark" on the Stream page** (2026-10-14). ObservANT's `/healthz` says `dark` while
  its picture is black, as a camera without IR is at night and the model idles; the status
  line says so instead of looking like a quiet camera.

- **"Recent detections" on the Camera page** (2026-10-14): the last five arrivals with their
  pictures, each with "Not a cat", which ignores the spot it was seen at. A false arrival is
  seldom on screen when it happens, so the live button alone rarely caught one.

- **An overview of the other cat cams, and a calmer Stream page** (2026-10-14). With
  `peers` in `catcam.toml`, the Stream page shows a card per other cat cam: its name,
  picture and cat. It also says since when a cat cam is unreachable, folds out the whole
  visit log, shows each earlier video with its arrival's picture, and closes the video of
  a tab hidden for a minute. `/healthz` names the build (`version`, also on the Camera
  page) and the tabs connected (`viewers`); more than `max_viewers` (8) get `503`.

- **"Not a cat", and a cat must move to arrive** (2026-10-14). Under the Camera page's
  preview, "Not a cat" marks the boxed spot, such as a drying rack, so the cat cam ignores
  it from then on; the marked spots show grey, and "Watch again" forgets them. And a
  detection now starts a visit only where something moved in the last 10 s, so a still
  object the model takes for a cat never counts, while a cat that sits down stays counted.

- **A Camera page for the cat cam's settings** (2026-10-13), in the bottom bar beside
  Stream. ⟲ and ⟳ turn the picture a quarter each way, for a board that gets moved about; a
  slider sets how sure detection must be before a cat counts, against false alarms; a field
  renames the camera. A live preview shows the result, the score of the last detection under
  the slider says where a false one sits, and a table shows what the camera runs.
  The cat cam applies each change at once and keeps it across restarts. It turns the
  picture itself, so detection, the arrival picture and the clips turn with the stream, and
  a quarter turn is bordered into the frame now, where it used to come out stretched.
- **An installable cat cam** (2026-10-05/06). The `cat_webrtc` producer, its GStreamer
  plugins, the chain ONNX Runtime, the model and the web build travel as one bundle:
  a .deb with a systemd service and a ufw profile, an AppImage that runs it or installs
  it as that service, and a flatpak. On Windows it is an MSI and a signed MSIX, each
  starting at logon with a firewall rule for the LAN. `web.yml` packages each one and
  install-tests it.
- **The cat cam on riscv64** (2026-10-13). `package-catcam.sh` builds its .deb and tarball
  natively on a riscv64 board, in that board's own `:latest`; no AppImage or flatpak, as
  flatpak has no riscv64 runtime. It runs on a SpacemiT board with a USB webcam, at about
  24 fps to a browser on the LAN. No CI lane builds it yet.
- **It reports the cat** (2026-10-11/12). `/healthz` says whether a cat is in view,
  when one last was, how many visits it counted, and when the latest 20 began and how
  long they lasted. `/snapshot.jpg` is the latest
  boxed frame and `/arrival.jpg` the frame each arrival was confirmed on. A cat counts
  after two detections in a row. Visits and the arrival frame outlive a restart.
- **It can notify** (2026-10-12): `notify_url` gets every arrival and departure as a
  JSON POST, which a Home Assistant webhook trigger takes as it is.
- **The Stream page shows the cat** (2026-10-12). Under the video: the cat cam's name,
  then "Cat in view", "Cat last seen: 14:32" or "No cat seen yet" in English or German,
  the latest visits with their stays, and the last arrival's picture. On a phone the video keeps its 4:3 and the line wraps.
- The web app boots without its Rust core, as Firefox and Safari need without
  cross-origin isolation; `serve.sh --http` serves the page with no certificate
  (2026-10-05).
- The integration test runs on Windows x64 and arm64, through `flutter drive` against
  the clang-cl app (2026-10-04/05).

### Fixed

- **The blog overview sorts the way its header arrow points** (2026-10-15, ANThology 1f1c56b).
  Its table, ANThology's `AnthologyTable`, sorted a header tap in the direction from before the
  tap, and since the overview sorts on load, a tap on another column only flipped the load
  column again. Two cells with the same text in one row also both took the first one's width.
  ANThology's first table tests found all three.

- **The native app's first frame no longer waits for libcamera** (2026-10-15). The Stream page
  probed the Rust core with `listCameras()`, a synchronous bridge call that starts the GStreamer
  device monitor, so the first frame's build took 963 ms of which `StreamPage` held 938 ms
  (profile build, Pi 5, `debugProfileBuildsEnabled`). The probe is now OxidANT's compile-time
  `webcamInferenceAvailable()`, and `listCameras()` is async, run only from the camera list.
  `integration_test/performance_test.dart` measured the start's worst frame at 1,895 ms before
  and 25.5 ms after; `test/stream_page_rust_test.dart` fails if the page enumerates again.

- **The app keeps its state, the Camera page recovers, and the Stream page names the animal**
  (2026-10-14, the deep review).
  - ANThology's app shell no longer rebuilds the app and its router on every resize or open
    keyboard, which closed panels and could close a phone's keyboard while typing a name.
  - The Camera page keeps a camera's last answer while it restarts, says "Camera unreachable
    since …", asks again every 3 s, and offers "Try again" when the first look fails; before,
    one failed load left it on "not reachable" until the tab was switched.
  - The Stream page says "Dog in view" for the open visit's class instead of the watch list,
    and names each visit's class once more than one is watched.

- **ObservANT is harder to misuse from the LAN** (2026-10-14, the deep review). Reads now
  need a local host name too, so a website using DNS rebinding cannot fetch the camera's
  pictures; 128 connections at most and a 10 s limit for a request head keep one device from
  exhausting the service; a model that keeps failing turns `/healthz` to `ok: false`; and
  with the privacy filter on, the classes are locked to `observant.toml`, since watching
  `person` from the page would have shown people unblurred. The Camera page then shows the
  classes without the editor. Detail: OxidANT's CHANGELOG and camera-streaming.md.

- **The app no longer calls itself "Blog von Jonas Heinle"** (2026-10-14, owner). The app
  bar showed `appNameDe`/`appNameEn` and the browser tab `appTitleDe`/`appTitleEn` from
  `assets/settings/app_settings.json`, which still held the old blog's name and slogan;
  `onGenerateTitle` even overrode `web/index.html`'s `<title>`. All four are
  `OmniAccelerANT` now, and `test/pinned_artefacts_test.dart` fails when they, the
  `<title>` and the manifest's `name` drift apart.

- **Coming back to an open cat cam tab plays again** (2026-10-14). After a sleep or a Wi-Fi
  change the page could keep a signalling socket that looked open and carried nothing, and
  stayed on "Der Videostream wird ausgehandelt" while a new tab played. The page now
  rebuilds that connection when it returns from a long absence, when a session gets no
  answer for 15 s, and when the picture stops moving for 10 s; its status requests give up
  after 8 s.

- **The cat cam review's fixes** (2026-10-13; OxidANT's changelog has the detail).
  - Each of the last five arrivals keeps its own picture (`/arrival.jpg?t=`), so a false
    visit no longer swaps the picture in the cat's phone notification.
  - A second arrival during a clip's recording gets its own clip.
  - A webhook delivery that fails is tried again for up to ten minutes, in order.
  - `/healthz` is `ok: false` with a `problem` when the camera delivers no frames or a
    test pattern stands in for it; the Stream and Camera pages show the problem.
  - Another site's page can no longer open the stream or change a setting (`403`); a
    reverse proxy's name goes into the new `allowed_hosts`.
  - `catcam.toml` is `640 root:omni-catcam`, since a `notify_url` can carry a webhook
    secret, and an upgrade takes the world's read off an older one.
  - The service comes back after any exit (`Restart=always`) and starts after
    `time-sync.target`.
  - The Camera page's slider note reads "Last detection: 34 %": it is every detection's
    score, not only an arrival's.

- **The Impressum no longer shows a commented-out phone number** (2026-10-13). The
  Markdown renderer printed `<!-- Telefon: … -->` as text, there and on two blog pages;
  ANThology strips HTML comments outside code blocks now, and a test fails any page that
  would show one.
- **Android's "Camera (ahc2src)" button opens the camera** (2026-10-13), not the
  bouncing test pattern its unknown source name fell back to. A pattern button that
  fails reports its own error rather than "No video source worked" over sources it
  never tried.
- **The footer shows all seven social icons** (2026-10-12). Icon tree shaking had kept
  GitHub's alone, because ANThology held the others in a map that was not `const`.
- **The loading screen and cookie notice fit a phone** (2026-10-12). The page had no
  viewport tag, so a phone laid both out 980 px wide, like a desktop, until Flutter
  started. The cookie notice now stacks its text above a full-width button there.
- **The About page's skills fit a phone**, a title above each list instead of words
  broken mid-word, and the footer's copyright runs to the current year (2026-10-12).
- **The video box speaks the page's language** (2026-10-12): its status lines were
  English on the German page.
- **The desktop footer shows all its page links** (2026-10-12). Held at 150 px, it cut
  off the fourth row; it now takes its content's height. A new test lays the whole app
  out at phone, tablet and desktop size with the real font, and caught it.
- **The camera stream survives a language or theme change** (2026-10-12). Either left
  the video box at "Connecting to the signalling server", because the remounted view
  waited for connection events that had fired long before. The stream now lives in one
  controller per page load: a remount keeps the playing session, and a view that
  comes back later opens one at once.

### Changed

- **The detection model is DEIM-D-FINE-N (Apache-2.0), fetched by checksum instead of
  tracked** (2026-10-14, owner). It replaces the AGPL-3.0 YOLO26n (ObservANT) and YOLOv10m
  (the Linux bundle), whose files sat in AccelerANTgine's and OxidANT's trees. The new
  repository [ModelANT](https://github.com/Kataglyphis/ModelANT) builds it from DEIM's
  pinned checkpoint and releases it; OxidANT's `resources/models/models.lock` pins its URL
  and SHA-256, and its `fetch-models.sh` / `Get-Models.ps1` put it, its license and notice
  where the native lane, the Linux bundle and the ObservANT `.deb`, AppImage, flatpak, MSI
  and MSIX expect them. The packages ship the license and notice in `share/doc`, and the
  MSI's license page names Apache-2.0 instead of AGPL-3.0. On 12 arrival pictures of the
  three boards it found the cats more often and more surely than YOLO26n, at about 260 ms a
  run instead of 190 ms on a Pi 5. Docs: camera-streaming.md § *The detection model*.
- **The cat cam is ObservANT** (2026-10-14, the owner's name): a general detector for which
  cats are the default (`classes`, the Camera page's "What it detects"). The package is
  `omni-observant` in `/opt/omni-observant`, the service and user `omni-observant`, the
  settings `/etc/omni-accelerant/observant.toml`, the state `/var/lib/omni-observant`, the
  firewall profile `OmniObservANT`, the flatpak `org.kataglyphis.omni-observant`, the Windows
  MSI and MSIX `ObservANT` (the MSI keeps its upgrade code). Scripts moved to
  `scripts/linux/observant/` (`package-observant.sh`, `test-observant-package.sh`,
  `package/`) and `scripts/windows/observant/`; `web.yml`'s jobs are `observant` and
  `observant-windows`. `/healthz`'s `cat` is `detection`; the page reads both.
  - **The upgrade is in place.** The .deb replaces and conflicts with
    `omni-accelerant-catcam`, so `dpkg -i` removes the old package, and its setup takes over
    `catcam.toml`, `/var/lib/omni-accelerant-catcam` (visits, photos, clips, page settings)
    and an allowed `OmniCatCam` firewall rule; the old copies stay. An AppImage install from
    before is stopped and removed. The package test plants such an install and checks it.
  - **The page speaks of what it watches:** "Katze / Hund im Bild", "Zuletzt gesehen",
    "Fehlalarm" instead of "Keine Katze", "Andere Kameras"; the class names in German on the
    German page.

- **The cat cam needs a fraction of the CPU** (2026-10-11/12, measured on a Pi 5).
  - ONNX Runtime runs on two threads that sleep between runs, not four that spin: 131 %
    to 70 % of a core on the live camera.
  - While nothing moves, the model runs every 5 s, and not at all on a black picture: a
    still, empty scene went from 74 % to 12 % of a core, a dark room at night to 2 %.
  - A cat in view that does not move is looked at half as often (2026-10-13): a drying
    rack counted as a cat went from 69 % to 36 % of a core.
  - Frames stay I420 from the camera to the encoder.
  - The web build goes out gzipped, and a revalidation answers 304 without reading a file.
- **92 kB less on every first visit** (2026-10-13): Roboto's Medium Italic face, which
  nothing draws, is no longer declared, so Flutter web no longer fetches it.
- **Every build is 7.6 MB lighter** (2026-10-12, ANThology 3e30917): the 404 page's
  animation is a 0.85 MB WebP instead of a 4.9 MB GIF, and the 3.6 MB GIF the landing
  page no longer shows is gone. The web, Linux, Windows and Android builds all bundle
  ANThology's images.
- **The cat cam's web build ships zopfli-compressed** (2026-10-12): a phone's first visit
  is 4.46 MB, 160 kB less, and the board compresses nothing at run time. The packages leave
  out two Flutter renderers this build never loads, and the debug maps.
- **The service runs sandboxed** (2026-10-12): `systemd-analyze security` rates the unit
  1.8, down from 8.7, and the package test holds it at 2.5 or less.
- **The web build's first load is 2.8 MB lighter** (2026-10-12). Flutter web fetches
  every font its manifest declares before the first frame, and two of the three
  families were never rendered: this repo's Noto Sans (4 faces) and ANThology's
  Montserrat (18). The cat cam page's cold load went from 7.36 MB in 71 requests to
  4.55 MB in 49, and on a 10 Mbit/s link its first video frame from 7.7 s to 5.6 s.
  Pages render pixel for pixel as before. The checkout is 48 MiB lighter too.
- **The checkout is 6.6 MiB, down from 99 MiB** (2026-10-12). Every tracked file nothing
  referenced went: `dummy_assets/` (79.7 MiB), an unlisted video (12.3 MiB),
  `assets/images/barbell.png`, gstwebrtc-api's demo page and the UMD build only it
  loaded (both published with every web build), and ANThology's `Untitled.md`.
- **The app icons are 8-bit PNGs** (2026-10-12). They were stored at 16 bits per
  channel, which no browser shows: Chrome decodes old and new to the same pixels. The
  192 px icon Chrome fetches with every cold load is 26 kB instead of 123 kB, and the
  ten web and Android icons together 0.3 MB instead of 1.7 MB.

## 2.0.0+2 — 2026-10-01

A major release over `1.1.0+1` (2026-03-09): installs of 1.x do not upgrade in
place, so the major number moves. No tag is cut with this entry.

### Breaking

- **The app is OmniAccelerANT** (2026-09-05). The package and executable are
  `omni_accelerant` (was `kataglyphis_inference_engine`), the Linux packages
  `omni-accelerant`, the Linux application id `org.kataglyphis.omniaccelerant`,
  the Android application id `org.kataglyphis.omniaccelerant`, and the MSIX
  identity `Kataglyphis.OmniAccelerANT` (was
  `Kataglyphis.KataglyphisInferenceEngine`). A 1.x install stays beside a 2.x
  one until it is removed. The web build keeps its IndexedDB name, so a
  browser's data survives.

### Added

- Rust-owned webcam inference on the Stream page — Windows first, Linux since
  2026-09-16 — with frames pushed through the plugin's `knt_push_frame` C ABI.
- A Windows arm64 app, cross-built natives plus a native Flutter build on
  `windows-11-arm`.
- The live cat-detection WebRTC stream on the web build, served by
  `scripts/linux/cat-stream/serve.sh`, with producers on a Pi 5, a Pi Zero 2 W
  and a RISC-V board.
- Relocatable Linux packages (tar, deb, AppImage, flatpak) that carry their
  GStreamer and ONNX Runtime closure and the detector model; the flatpak has
  camera access (`--device=all`).
- Only the image's chain-built ONNX Runtime ships, proved by ANTfrastructure's
  G6 census on every lane.
- Every test runs on every lane that can host it:
  AGENTS.md § *What each lane tests*.

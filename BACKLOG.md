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
2026-10-05, and as a flatpak, proven in `:latest` on 2026-10-06. Windows x64 ships as an MSI and an MSIX, proven on a Windows 11 host on
2026-10-06. These rows are what the owner's goal still lacks.

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
  a loopback stand-in (`test-observant-package.sh`, 69 checks; OxidANT's `notify.rs`), and a
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
- [ ] **The Windows ObservANT with a camera, at a real logon, then on arm64.** The MSI works
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
    - the arrival clip: `Package-ObservANT.ps1` takes `isomp4` as optional, and whether
      `:winamd64` carries it is unchecked; without it the service records no clip and says
      so at start.
  - **The web build as Linux ships it** (2026-10-17): `Package-ObservANT.ps1` cuts the same
    renderers and maps, and on x64 runs `--precompress`, which `Test-ObservANTWindows.ps1` checks
    (camera-streaming.md, *The Windows ObservANT*). Open: the first `web.yml` run of it, and `.gz`
    files for arm64, whose producer cannot run on the amd64 packaging host.
  - **Then:** arm64; the hub's CON63, which it waited on, is done since 2026-10-11.
  - Autostart is a logon task by owner decision. A boot-time service would run in
    Session 0, and on a PC with a webcam it first needs proof that LocalSystem or
    LocalService can open the camera there at all.
- [ ] **ObservANT flatpak on a real Linux desktop.** `package-observant.sh` builds it
  since 2026-10-06, and `web.yml` tests it on x64 and arm64 with the .deb and the
  AppImage.
  - In `:latest` it installed, answered `/healthz` from its sandbox, and headless Chrome
    played it over the LAN address. Its first start wrote the sign-in entry.
  - **On a real desktop** (Ubuntu GNOME, amd64, 2026-10-08): CI's bundle installed as a user
    install, fetched its runtime from Flathub (24.08, end-of-life), wrote the sign-in entry,
    and the host's Chrome played 582 frames over the LAN address.
  - **On runtime 26.08 since 2026-10-11:** `web.yml` run 38158462452 (fafa9f3) built the bundle on
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
  pages, `third_party/OxidANT/AGENTS.md` § *The riscv64 lane*). A 4 KiB-page host could run
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

## Open — CI time

- [b] **Half of every Windows lane is the image pull.** Measured on 1686eae (2026-10-12):
  *Prepare Windows container host* took 27 and 31 min of `windows-x64.yml`'s 45 and 64 min
  jobs, 25 of `windows-arm64.yml`'s 35, and 30 of `web.yml`'s 37-min Windows ObservANT job;
  the Linux lanes spend 5 to 8 of 10 to 15 min there. A round's wall time is the Windows
  Debug job's 64 min, of which 31 pull the ~54 GB `:winamd64`. The pull is the hub's
  `prepare-windows-container-host`; a smaller image for these lanes, or a cache the hosted
  runners keep, would halve the round. Blocked on the hub.

## Open — tests

- [ ] **The Linux app drawn on a desktop outside the build image.** Since a7ce99e (2026-10-17) the
  bundle starts through the image's loader and glibc (camera-streaming.md § *Relocatable Linux
  bundles*).
  - Proven: the clean-host job on bare Ubuntu 26.04, x64 and arm64, keeps the app up 20 s under
    Xvfb from the `.deb`, the AppImage and the tarball; on himbeere2 (Debian 13) all three reach
    GTK headless with `LD_BIND_NOW=1`, and `apt-get install --simulate` takes the `.deb`.
  - **Still unproven:** a window drawn on a real Debian 13 or Ubuntu 24.04 desktop, where GL comes
    from the host's Mesa under the bundled glibc; and the app flatpak since it installs the bundle
    whole under `/app/lib/omni-accelerant` (hub f0e44db7), which no lane starts.

- [b] **`webrtc_view.dart`, about 550 web-only lines, is outside coverage.** It drives
  gstwebrtc-api's JavaScript; testing it in Chrome needs a stand-in for that API. The stream's
  state is tested through `webrtc_stream_controller_test.dart`, and the Camera page's requests
  in Chrome through `observant_api_web_test.dart`. Blocked on a JS stand-in worth its upkeep.

## Open — waiting on the owner

- [b] **The legal pages carry placeholders.** ANThology's `imprintDe.md` says itself that
  it holds dummy data (Elchwinkel 42, 12345 Bärstadt), and the privacy policies name
  Elchwinkel 1 (German) and 13 (English), 10117 Bärstadt, a placeholder phone number and the e-mail `XX`. Both
  OmniAccelerANT and jotrockenmitlocken show them. Blocked on the owner's postal address
  (a c/o service address works) and the e-mail to publish. Done when both pages name them
  in German and English.
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

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

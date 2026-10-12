# Backlog

Follows the protocol ANTfrastructure's agentic loop (`shared/agentic-loop/`)
consumes, so the loop this repo adopted on 2026-09-13 (`scripts/agentic-loop/`,
§ *Agentic loop* below) reads it unchanged.

## Protocol

- `- [ ]` actionable — the planner may pick it up
- `- [b]` blocked — skipped, and excluded from the pending count, so a
  backlog containing only blocked items still lets the planner run again
- `- [x]` completed — pruned on sight; the history lives in git

## Open — the cat cam

The installable cat cam: `docs/source/camera-streaming.md` § *The cat cam package*.
Linux amd64/arm64 ship as a .deb and an AppImage, proven on himbeere2 (Pi 5) on
2026-10-05, and as a flatpak, proven in `:latest` on 2026-10-06. Windows x64 ships as an MSI and an MSIX, proven on a Windows 11 host on
2026-10-06. These rows are what the owner's goal still lacks.

- [b] **A USB webcam through `camera = "auto"`.** The UVC branch (`uvcvideo`, MJPEG when
  no raw format) has run only in unit tests: himbeere2 has no USB camera, and the C270
  sits on the riscv64 X100, which the package does not build for. Blocked on a UVC camera
  at an amd64 or arm64 board. Done when `/healthz` names it and a browser plays it.
- [b] **A real cat's arrival on the owner's phone, picture first and video after.** Since
  2026-10-12 himbeere2's cat cam posts to the owner's Home Assistant, whose automation
  (`docs/source/camera-streaming.md`, *A phone notification with the picture*) sends
  arrivals at 0.45 or more to the phone with `/arrival.jpg`, and updates that notification
  with a tap to `/arrival.mp4?t=` once the clip's event comes. Test arrivals posted to that
  webhook reached the phone; the service's own arrival and clip POSTs are proven against
  a loopback stand-in (`test-catcam-package.sh`, 49 checks; OxidANT's `notify.rs`), and a
  clip from the packaged service on the cat photo played (16:21, 603 kB). The visit
  statistics, the outage alert, the departure that updates the notification with the stay
  and the 21:00 summary run in the same Home Assistant; the summary's first run (21:00)
  finished without an error, and a test departure set the stay. Blocked on a cat. Done
  when one's arrival lands on the phone with its picture, a tap plays its video, and its
  departure adds the stay.
- [ ] **The Windows cat cam with a camera, at a real logon, then on arm64.** The MSI works
  in the image and on a real Windows 11 host (`scripts/windows/cat-stream/`, 2026-10-06),
  and `web.yml`'s `catcam-windows` job packages and tests it around every web build.
  - **In the image:** `Test-CatCamWindows.ps1` passed all 14 checks: the MSI's LAN-only
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
  - **The MSIX** (`-Msix`, 2026-10-06) passed `Test-CatCamMsix.ps1 -Install` 12 of 12
    on the dev box, with a per-build test certificate trusted. himbeere2 reached the page
    through its port rules.
  - **Still unproven:**
    - a camera: Media Foundation or kernel-streaming capture on a Windows host that has
      one;
    - the start at a real sign-in, for the MSI's Startup entry and the MSIX's startup
      task; the shell ran the shortcut, no logon did, and the task stays unregistered
      until one;
    - an MSIX signed by a certificate users already trust; `-MsixPfx` takes the owner's;
    - the arrival clip: `Package-CatCam.ps1` takes `isomp4` as optional, and whether
      `:winamd64` carries it is unchecked; without it the service records no clip and says
      so at start.
  - **The web build as Linux ships it** (2026-10-12): `package-catcam.sh` leaves out the
    `wimp` and `webparagraph` renderers and `*.symbols`, and runs the producer's
    `--precompress` over the copy, so the board sends zopfli `.gz` files. `Package-CatCam.ps1`
    copies `build\web` whole, and the Windows service still gzips at run time: the same
    steps after its `Copy-Item ... web`, and `Test-CatCamWindows.ps1` comparing a served
    file against its `.gz`, want a `:winamd64` run, which himbeere2 cannot make.
  - **Then:** arm64, after the hub's CON63.
  - Autostart is a logon task by owner decision. A boot-time service would run in
    Session 0, and on a PC with a webcam it first needs proof that LocalSystem or
    LocalService can open the camera there at all.
- [ ] **The cat cam flatpak on a real Linux desktop.** `package-catcam.sh` builds it
  since 2026-10-06, and `web.yml` tests it on x64 and arm64 with the .deb and the
  AppImage.
  - In `:latest` it installed, answered `/healthz` from its sandbox, and headless Chrome
    played it over the LAN address. Its first start wrote the sign-in entry.
  - **On a real desktop** (Ubuntu GNOME, amd64, 2026-10-08): CI's bundle installed as a user
    install, fetched its runtime from Flathub (24.08, end-of-life), wrote the sign-in entry,
    and the host's Chrome played 582 frames over the LAN address.
  - **On runtime 26.08 since 2026-10-11:** `web.yml` run 38158462452 (fafa9f3) built the bundle on
    `org.freedesktop.Platform/26.08` for x64 and arm64, and `test-catcam-package.sh` installed and
    removed it on both (`PASS flatpak installs it`); the app flatpak of Linux x64 run 38158462860 built
    on 26.08 too.
  - **Still unproven:**
    - the start at a real sign-in (the entry is in place on that desktop);
    - a USB camera through `--device=all`.
  - It has no boot service and no Pi camera by design; those stay with the .deb and the
    AppImage.

## Open — CI time

- [b] **Half of every Windows lane is the image pull.** Measured on 1686eae (2026-10-12):
  *Prepare Windows container host* took 27 and 31 min of `windows-x64.yml`'s 45 and 64 min
  jobs, 25 of `windows-arm64.yml`'s 35, and 30 of `web.yml`'s 37-min Windows cat cam job;
  the Linux lanes spend 5 to 8 of 10 to 15 min there. A round's wall time is the Windows
  Debug job's 64 min, of which 31 pull the ~54 GB `:winamd64`. The pull is the hub's
  `prepare-windows-container-host`; a smaller image for these lanes, or a cache the hosted
  runners keep, would halve the round. Blocked on the hub.

## Open — waiting on the owner

- [b] **The legal pages carry placeholders.** ANThology's `imprintDe.md` says itself that
  it holds dummy data (Elchwinkel 42, 12345 Bärstadt), and both privacy policies name
  Elchwinkel 1, 10117 Bärstadt, a placeholder phone number and the e-mail `XX`. Both
  OmniAccelerANT and jotrockenmitlocken show them. Blocked on the owner's postal address
  (a c/o service address works) and the e-mail to publish. Done when both pages name them
  in German and English.
- [b] **False arrivals: a threshold or an ignore zone.** On 2026-10-12 a drying rack at
  the bottom edge of himbeere2's frame made 39 "visits" between 0.26 and 0.44 (33 in the
  morning, 6 at 18:03 to 18:08),
  against 0.76 for a cat in the bundled photo. The Home Assistant automation kept them off
  the phone (0.45) until 21:57, when the rack scored 0.65 and a notification went out, the
  visit counted. The visit log, its statistics and the arrival picture and clip take them
  all, and each one costs a clip encode, so the threshold alone does not hold: an ignore
  zone over the frame's bottom edge, or moving the rack out of view, does. Either `score = 0.45` in
  himbeere2's `catcam.toml`, or a new setting that ignores a part of the frame. Blocked on
  the owner's choice.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

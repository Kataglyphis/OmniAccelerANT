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
    - an MSIX signed by a certificate users already trust; `-MsixPfx` takes the owner's.
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
    install, fetched its runtime from Flathub (24.08, end-of-life; the next `:latest` builds
    on 26.08, hub CON82), wrote the sign-in entry, and the host's Chrome played 582 frames
    over the LAN address.
  - **Still unproven:**
    - the start at a real sign-in (the entry is in place on that desktop);
    - the 26.08 runtime, once the published `:latest` carries it;
    - a USB camera through `--device=all`.
  - It has no boot service and no Pi camera by design; those stay with the .deb and the
    AppImage.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

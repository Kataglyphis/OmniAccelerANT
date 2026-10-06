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
2026-10-05, and Windows x64 as an MSI, proven on a Windows 11 host on 2026-10-06. These
rows are what the owner's goal still lacks.

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
  - **Still unproven:**
    - a camera: Media Foundation or kernel-streaming capture on a Windows host that has
      one;
    - the start at a real sign-in; the shell ran the Startup shortcut, no logon did.
  - **Then:** arm64, after the hub's CON63.
  - Autostart is a logon task by owner decision. A boot-time service would run in
    Session 0, and on a PC with a webcam it first needs proof that LocalSystem or
    LocalService can open the camera there at all.
- [ ] **A flatpak of the cat cam, Linux amd64 and arm64.** The owner's goal names .deb,
  flatpak and AppImage, and `package-catcam.sh` builds the first and the last.
  - A flatpak is sandboxed and runs in a user session. It cannot carry the .deb's systemd
    unit, so it would start at sign-in through the background portal, not at boot.
  - It needs `--device=all` for the camera, as the app's flatpak has, and network access.
  - Done when it installs, starts at sign-in, and a browser on the LAN plays it.
- [ ] **An MSIX of the cat cam, Windows x64.** The owner's goal names msi/msix; the MSI
  exists.
  - An MSIX would declare its logon start as a `desktop:StartupTask` and its LAN rule as
    `desktop2:FirewallRules`.
  - It installs only when signed, and nothing here signs a cat cam package yet. The hub's
    `Invoke-MsixPackage` builds the app's MSIX.
  - Done when a signed package installs, starts at sign-in, and a browser on the LAN plays
    it.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

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
2026-10-05; these rows are what the owner's goal still lacks.

- [b] **A USB webcam through `camera = "auto"`.** The UVC branch (`uvcvideo`, MJPEG when
  no raw format) has run only in unit tests: himbeere2 has no USB camera, and the C270
  sits on the riscv64 X100, which the package does not build for. Blocked on a UVC camera
  at an amd64 or arm64 board. Done when `/healthz` names it and a browser plays it.
- [ ] **The Windows cat cam on a real Windows host, then in CI and on arm64.** The MSI
  exists and works in the image (`scripts/windows/cat-stream/`, 2026-10-06).
  - `Test-CatCamWindows.ps1` passed all 13 checks there: the silent install, a
    scrubbed-environment run loading only its own modules, a `webrtcsrc` viewer decoding
    60 frames, the bundled model finding the cat, and a clean uninstall.
  - **Still unproven:**
    - an install on a Windows host with a camera, which this dev box lacks;
    - a browser on the LAN playing it;
    - the logon start after a reboot.
  - **Then:**
    - a `windows-x64.yml` job that packages and tests it, which needs `web.yml`'s web
      build;
    - arm64, after the hub's CON63.
  - **Two follow-ups for the image, the hub's to fix:**
    - WiX's firewall extension, so the MSI opens 8080/tcp and the ICE range instead of
      Windows asking once;
    - publishing the rebuilt `:winamd64`, which is the owner's decision.
  - Autostart is a logon task by owner decision; a Session 0 service waits on the
    camera-test-kit result.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

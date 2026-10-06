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
- [ ] **The Windows cat cam: a service and an MSI (x64, then arm64).** The producer's
  `mf`/`ks` sources exist, and the hub's `Invoke-MsiPackage` (CON55) is the WiX step.
  - **The producer works in a `:winamd64` built locally from hub f4c0e2be (2026-10-06).**
    - The image's smoke gate passed 229 assertions, with 1 skipped, including the WebRTC
      loopback.
    - `kataglyphis_cat_webrtc` builds in it in 79 s.
    - A `webrtcsrc` consumer decoded 60 frames from its test pattern.
    - The chain ORT found 2 cats in ANThology's photo.
    - That image is not published yet; the owner decides.
  - **Next:** a Windows bundle, with the exe, the GStreamer runtime subset, the chain ORT,
    the model and the web build, then the MSI around it. Done when an MSI installed on a
    Windows host streams to a browser on the LAN and comes back after a reboot.
  - **Still open, and the owner's to decide:** the camera-test-kit result, which settles
    a Session 0 service against a logon task.

  arm64 also waits on the hub's CON63.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

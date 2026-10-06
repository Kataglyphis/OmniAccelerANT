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
- [b] **The Windows cat cam: a service and an MSI (x64, then arm64).** The producer's
  `mf`/`ks` sources exist, and the hub's `Invoke-MsiPackage` (CON55) is the WiX step.
  Blocked on two things.
  - **A `:winamd64` carrying the hub's WebRTC fixes** (CON28, hub 7b833e31). Until then
    `webrtcsink` is missing and `create-offer` never answers.
    - Its local rebuild, owner request 2026-10-06, waits on the Stevedore repair of
      hub `docs/windows-host-setup.md` § Phase R.
    - Stevedore's 2026-09-21 update had restored the stock runhcs shim and wiped the
      buildkitd and containerd service settings.
    - The patched shim is built from fork pin 5e9df53c and needs an elevated
      `Publish-ShimPatch.ps1` + `Install-NewHost.ps1 -SkipShim`.
  - **The owner's camera-test-kit result**, which decides between a Session 0 service
    and a logon task.

  arm64 also waits on the hub's CON63.


## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

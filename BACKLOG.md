# Backlog

Follows the protocol ANTfrastructure's agentic loop (`shared/agentic-loop/`)
consumes, so the loop this repo adopted on 2026-09-13 (`scripts/agentic-loop/`,
§ *Agentic loop* below) reads it unchanged.

## Protocol

- `- [ ]` actionable — the planner may pick it up
- `- [b]` blocked — skipped, and excluded from the pending count, so a
  backlog containing only blocked items still lets the planner run again
- `- [x]` completed — pruned on sight; the history lives in git


## Open — verification gaps

- [ ] **`scripts/windows/Start-Windows.ps1` on the dev box's console session.** The
      agent's shell runs in **Session 0**, where ANGLE/DXGI surface creation fails
      (`SwapChain11 … 0x887A0022`, `EGL Error: Context Lost`). CI shows a real window on
      both architectures (launch smoke, and the integration test's `flutter drive`:
      windows-x64 run 37271415938, windows-arm64 run 37240841037), so what is left is one
      launch by hand from the console.
## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

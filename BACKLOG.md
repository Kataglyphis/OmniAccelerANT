# Backlog

Follows the protocol ANTfrastructure's agentic loop (`shared/agentic-loop/`)
consumes, so the loop this repo adopted on 2026-09-13 (`scripts/agentic-loop/`,
§ *Agentic loop* below) reads it unchanged.

## Protocol

- `- [ ]` actionable — the planner may pick it up
- `- [b]` blocked — skipped, and excluded from the pending count, so a
  backlog containing only blocked items still lets the planner run again
- `- [x]` completed — pruned on sight; the history lives in git

## Open

- [ ] **Cargokit builds `liboxidant` with a floating stable Rust, not the image's pin.**
  `rust_builder/cargokit/build_tool/lib/src/builder.dart` runs `rustup run stable cargo
  build`, and `options.dart` accepts only `stable`, `beta` or `nightly`. The image carries
  `1.98.1` and `nightly-2026-06-28`, so every native app build downloads the current
  stable into `RUSTUP_HOME`. On 2026-10-05 that was 1.99.0, with LLVM 23.1.1 behind its
  rust-lld. It is the web lane's old floating-nightly problem (AGENTS.md § 4) on the
  native lanes. A local Cargokit patch must keep that toolchain: Cargokit is vendored and
  already patched twice (AGENTS.md § 1, § 4). Done when a native lane log shows no
  `stable-*` install and `rustc -vV` inside Cargokit's build prints the image's pinned
  version.


## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

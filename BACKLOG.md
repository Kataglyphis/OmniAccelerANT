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

- [ ] **G6 over the Pi producer bundle has not run since the hub pin moved past
      e72a9a37.** `scripts/linux/cat-stream/package-producer-bundle.sh` proves
      `/bin/kataglyphis_cat_webrtc`, which carries the chain ORT's Linux source
      path as a string, with this repo's hub. Re-run it with the next Pi bundle.
      (The Windows half is done: windows-x64 run 36154744287 had the real
      `oxidant.dll` in the runner when G6 passed.)
- [ ] **`scripts/windows/Start-Windows.ps1` on the dev box's console session.** The
      agent's shell runs in **Session 0**, where ANGLE/DXGI surface creation fails
      (`SwapChain11 … 0x887A0022`, `EGL Error: Context Lost`). CI shows a real window on
      both architectures (launch smoke, and the integration test's `flutter drive`:
      windows-x64 run 37271415938, windows-arm64 run 37240841037), so what is left is one
      launch by hand from the console.
- [ ] **The scoped Windows CodeQL scan does not keep vendored C++ out of its results.** The
      first complete run (2026-10-05, 27 min, the `:winamd64` of 2026-10-04) reported 63 cpp
      and 10 rust results. 39 of the cpp ones, including all four high-severity ones, are in
      `third_party/AccelerANTgine/third_party` (SPDLOG's bundled fmt, GOOGLE_BENCHMARK), which
      `.github/codeql/codeql-config.yml` ignores. All 10 rust results are OxidANT's. Filter the
      SARIF by the config's paths after `database analyze` (the hub's `Invoke-BuildCodeQL`), or
      keep vendored targets out of the traced build. Owned code has 21 results in
      `AccelerANTgine/Src` and 3 here; its only two errors (`cpp/missing-return`,
      `onnx_inference_engine.cpp:233` and `:240`) are false positives, since both lambdas return.
- [ ] **`-CodeQL` cannot start from a fresh tree.** It forces `-SkipBootstrapFlutterBuild`, which
      also skips `-CleanBuild` and the CMake reset. So the traced build needs an earlier build's
      `windows/flutter/ephemeral`, and recompiles only what is stale: an up-to-date tree gives
      the C++ extractor nothing to see. By reading (not run), `Build-Windows-Container.ps1
      -CodeQL` cannot supply the headers either: the hub's `Remove-StaleContainerSources`
      prunes `windows`, and the inbound stream excludes `ephemeral`. The 2026-10-05 run did it
      by hand (`logs/_phase2/codeql-job2.ps1`, gitignored): a container-local copy, one plain
      build, delete `C:\kataglyphis_fast_build\build\windows`, `rust_target` and the sccache
      cache, then `-CodeQL -CodeQLDownload -CleanCodeQLDb`. Make the CodeQL path do that itself.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.

# GitHub Copilot Instructions

> Datei: `.github/copilot-instructions.md`

## Zweck
Diese Datei gibt GitHub Copilot (inkl. Copilot Chat) repository‑weite Hinweise, wie Vorschläge, Code‑Snippets und Antworten formuliert werden sollen. Sie ist auf ein Multi‑Language‑Projekt ausgelegt: **C/C++**, **Rust**, **Dart/Flutter** (plus Hinweise zu `uv`‑basierten I/O‑Bindings), sowie generelle Tools wie **ruff**. Ziel ist konsistente Code‑Qualität, starke Typisierung und sichere Vorschläge.

Hinweis: In diesem Dokument meint „**uv**“ in zwei Kontexten unterschiedliche Dinge:
- **Python `uv`** = Package Manager/Runner.
- **libuv** = native I/O‑Library (siehe Abschnitt zu libuv‑Bindings).

---

## Kurze Zusammenfassung / About
Dieses Repository enthält native Komponenten (C/C++), Rust‑Bibliotheken, und eine Flutter‑UI (Dart). Der Fokus liegt auf Performance, Cross‑Language Interop, deterministischem Verhalten und starker Typisierung.

---

## Repository‑Scope
- **Behandeln mit Vorrang:** `src/`, `lib/`, `rust/`, `flutter/`, `native/`, `include/`, `tests/`.
- **Ignorieren / nur mit Vorsicht ändern:** `third_party/`, `vendor/`, `build/`, `artifacts/`.
- **CI/Infra:** Vorschläge für CI (z. B. GitHub Actions) nur wenn klarer Nutzen erkennbar; keine ungeprüften Änderungen an Workflows ohne Review.

---

## Personality / Ton
- Sprache: Deutsch (bei technischen Kommentaren kurze englische Code‑Begriffe ok).
- Ton: Präzise, technisch, knapp. 1–3 Sätze Erklärung plus minimaler Beispielcode, wenn nötig.
- Umfang: Bei trivialen Änderungen kurz; bei Architektur/Interop ausführlicher (aber nicht ausschweifend).

---

## Starke Typisierung (allgemein)
- Priorisiere klar typisierte Lösungen:
  - **C/C++:** explizite Typen, keine zu weiten `auto`‑Verwendungen an API‑Borders.
  - **Rust:** Typinferenz nutzen, aber Signaturen und `Result`/`Option`-Fehlerpfade explizit behandeln.
  - **Dart:** Null‑Safety strikt beachten, Typannotationen für öffentliche API‑Signaturen.
- Copilot soll Typannotation vorschlagen, falls weggelassen.

### Type‑Safety‑Policy (maximal)
- Öffentliche APIs (inkl. FFI‑Grenzen) müssen vollständig typisiert sein; keine „untyped“ Escape‑Hatches (`void*`, `dynamic`, „Any“) ohne Begründung.
- Fehlerpfade müssen typisiert sein (z. B. `Result`/`Option`, `std::optional`/Fehlercode, Dart Exceptions nur wenn idiomatisch).
- Narrowing/implizite Konvertierungen vermeiden; bevorzugt explizite Casts und Wrapper‑Typen.
- Wenn Tooling/Compiler das hergeben: Warnings werden in CI als Errors behandelt.

---

## Code Style & Tooling
**C/C++**
- Target standard: **C++20**.
- Build‑System‑Policy (falls CMake): `CMAKE_CXX_STANDARD=20`, `CMAKE_CXX_STANDARD_REQUIRED=ON`, `CMAKE_CXX_EXTENSIONS=OFF`.
- Format: `clang-format` (Repo‑konfiguration verwenden). Vorschläge müssen `clang-format`-konform sein.
- Lints: `clang-tidy` Empfehlungen sind willkommen; vermeide invasive API‑Änderungen.
- Type‑Safety bevorzugen:
  - Keine Ownership über rohe Pointer: RAII (`std::unique_ptr`, `std::shared_ptr`) und klare Lifetimes.
  - Für Größen/Indizes: `std::size_t`/`ptrdiff_t` statt `int`; für ABI/FFI: feste Breiten (`std::uint32_t` etc.).
  - `enum class` statt unscoped enums; `[[nodiscard]]` für Rückgaben, die nicht ignoriert werden sollen.
  - Für Views: `std::span`, `std::string_view` (keine rohen Buffer+Len‑Paare ohne Wrapper).
  - Keine `#define` für Konstanten/Typen; `constexpr`/`consteval`/`using`.
- Compiler‑Strenge (als Vorschlag, projektabhängig):
  - Clang/GCC: `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Wnull-dereference`.
  - In CI nach Möglichkeit: `-Werror` (oder selektiv `-Werror=<warning>`).
- Windows/MSVC (falls genutzt): `/W4 /WX /permissive-` und nach Möglichkeit SDL‑Hardening (`/sdl`).
- Runtime‑Checks (Debug/CI): Sanitizer‑Builds (`ASan`, `UBSan`, optional `TSan`) für native Komponenten.
- Tests: Google Test (gtest). Vorschläge für Tests sollen kleine, deterministische Cases enthalten.

**Rust**
- Format: `rustfmt`. Linter: `clippy` — Copilot soll `clippy`-freundliche Patterns bevorzugen.
- Error Handling: Verwende `Result`/`?`-Operatoren idiomatisch; keine `unwrap()` in Produktionscode.
- Type‑Safety:
  - `unsafe` nur wenn notwendig; klein halten, kapseln, und Safety‑Invarianten in einem kurzen Kommentar festhalten.
  - In CI bevorzugt: `cargo clippy -- -D warnings` und (falls passend) `#![deny(warnings)]`/`#![deny(clippy::all)]` auf Crate‑Level.
  - Optional (wenn Crate es zulässt): `#![forbid(unsafe_code)]` in rein „safe“ Crates.
- Tests: `cargo test` mit klaren Unit‑Tests.

**Dart / Flutter**
- Format: `dart format`. Null‑safety verpflichtend.
- Architektur: Trenne UI/Business/Platform (z. B. Provider/Bloc/riverpod‑Pattern) — Copilot soll keine monolithischen Widgets vorschlagen.
- Type‑Safety:
  - `analysis_options.yaml` soll strikte Analyse aktivieren (z. B. `strict-casts`, `strict-inference`, `strict-raw-types`).
  - Keine `dynamic`‑Leaks in Public APIs; generische Typen überall vollständig ausfüllen.
  - Prefer `flutter_lints`/`lints` (projektabhängig) und behandle Analyzer‑Warnings in CI als Fehler.
- Tests: `flutter_test` für Widgets + Unit‑Tests.

**Python (uv + ruff + ty)**
- Package Manager/Runner: **`uv`** (Dependencies gehören in `pyproject.toml`; Lockfile/Sync über `uv`).
- Tools sollen über `uv run …` ausgeführt werden (kein „global pip“, kein ungepinnter Tool‑Mix).
- Lint/Style: `ruff` (und optional Formatter nach Projektpolicy).
- Typisierung: **`ty`** als Type Checker; Copilot soll Typannotationen vollständig ergänzen und `Any` vermeiden.
- Type‑Safety Regeln:
  - `from __future__ import annotations` bevorzugen (falls Projektpolicy), und öffentliche APIs vollständig annotieren.
  - Keine stillen `Any`‑Leaks: `Any`/`cast()`/`# type: ignore` nur mit Begründung und so lokal wie möglich.
  - Collections/Generics immer parametrisieren (`list[str]` statt `list`).

---

## CI / Checks (nur Kommandos, keine Workflow‑Änderungen)
Copilot soll bei „How to validate“ bevorzugt konkrete, reproduzierbare Kommandos vorschlagen (an Repo‑Tooling anpassen):
- C/C++: configure/build via CMake Presets oder `cmake -S . -B build` + `cmake --build build` + Tests (`ctest`).
- clang-format: `clang-format -i` (nur auf geänderten Dateien) oder ein Check‑Target.
- clang-tidy: nur wenn `compile_commands.json` vorhanden ist; keine massiven Auto‑Fixes ohne Review.
- Rust: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`.
- Flutter: `dart format --output=none --set-exit-if-changed .`, `dart analyze`, `flutter test`.
- Python (uv): `uv sync` (ggf. „frozen“/locked nach Projektpolicy), dann `uv run ruff check .` und `uv run ty` (bzw. `uv run ty check`, je nach Tool‑Konfiguration).

**I/O / libuv‑basierte Bindings**
- Für libuv/uvloop/uvicorn‑artige APIs: keine blockierenden Aufrufe in Event‑Loop‑Callbacks vorschlagen.
- Prefer async patterns and explicit threading/futures when interacting with native I/O.

---

## Testing & Qualität
- Neue Features sollten Unit‑Tests enthalten. Copilot soll Test‑Skeletons vorschlagen, die vorhandene Fixtures nutzen.
- Vermeide flakige Tests; prefer deterministic seeds and small inputs.
- Coverage: Mindestens smoke tests für kritische native bindings.

---

## Interop (C/C++ <-> Rust <-> Dart)
- Copilot soll sicherheitsbewusst bei FFI/Bindings handeln: null/ownership/ABI‑stability prüfen.
- Bei Vorschlägen für Bindings: automatische Free/Fallocate Regeln, `unsafe`-Blocks in Rust nur mit Kommentar.
- Keine Code‑Generierung für Bindings ohne Hinweis (z. B. `cbindgen`, `flutter_rust_bridge`) und vorgeschlagenen Tests.

### FFI‑Typregeln (konkret)
- C ABI: `extern "C"`, stabile, explizite Layouts; keine C++‑Typen über ABI (z. B. `std::string`, Exceptions) exportieren.
- Pointer/Nullability: Nullability im Typ ausdrücken (z. B. `Option<NonNull<T>>`/`*mut T` + Dokumentation); nie „silent null“.
- Ownership: Erzeuger/Zerstörer‑Paare oder klare „borrowed vs owned“ Konventionen; keine impliziten Frees.
- Fehler: über ABI entweder Fehlercodes + `out`‑Parameter oder klar definierte Ergebnis‑Structs; keine Exceptions über FFI.

---

## Sicherheit & Geheimnisse
- Niemals API‑Keys, Passwörter, private Zertifikate oder sonstige Secrets einchecken oder vorschlagen.
- Wenn Copilot möglichen Secret‑Leak erkennt, soll es auf Vault/Secret‑Manager oder `.gitignore` hinweisen.

---

## Lizenz & rechtliche Hinweise
- Repository‑Lizenz: bitte hier eintragen (z. B. MIT / Apache‑2.0). Copilot soll Lizenz‑Header nur vorschlagen, wenn klar passend.

---

## Commit‑ und PR‑Konventionen
- Commit‑Format: **Conventional Commits** (`feat:`, `fix:`, `chore:`, `docs:` etc.).
- PRs: kurze Zusammenfassung + „Changes“ + „Testing/How to validate“ und CI‑Status.
- Keine squash‑commits für sicherheitsrelevante Änderungen ohne Review.

---

## Do / Don't (kurz)
**Do**
- Kleine, überprüfbare Änderungen vorschlagen.
- Typannotationen an öffentliche APIs ergänzen.
- Tests + CI‑Checks vorschlagen.

**Don't**
- Große, invasive Refactorings ohne PR‑Diskussion vorschlagen.
- Secrets oder unsichere Defaults einfügen.
- Ungetestete native Änderungen direkt vorschlagen (z. B. ABI‑Änderungen ohne Tests).

---

## Beispiele / Snippets
> *Hinweis: konkrete Codebeispiele und Style‑Configs (z. B. `.clang-format`, `rustfmt.toml`, `analysis_options.yaml`) sollten projekt‑spezifisch ergänzt werden.*

---

## Verhalten bei Unsicherheit
- Wenn Anforderungen unklar sind, soll Copilot Rückfragen vorschlagen (z. B. "Welcher C++ Standard wird verwendet?") anstatt zu raten.
- Für kritische Bereiche (Memory/FFI/Concurrency) präferiere conservative, safe Vorschläge und verweise auf Tests.

---

## Anpassung & Pflege
- Passe die Datei an, wenn der C++ Standard wechselt oder neue CI‑Checks/Tools (z. B. OSS security scanners) hinzukommen.

---

*Ende der projekt‑spezifischen Copilot‑Anleitung.*

*Wenn du möchtest: Ich kann noch spezifische Beispiele für `.clang-format`, `rustfmt.toml` und `analysis_options.yaml` (für Dart) hinzufügen — oder die Datei auf Englisch übersetzen.*


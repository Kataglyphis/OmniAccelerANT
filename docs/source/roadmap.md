# Roadmap – Kataglyphis-Inference-Engine

Basierend auf dem Projekt und den dokumentierten Entwicklungsständen hier eine strukturierte Roadmap:

## Phase 1: Stabilität & Testing (Q1–Q2 2024)

| Feature | Beschreibung | Status |
|---------|-------------|--------|
| Unit Tests (Rust) | Kernfunktionen der Inference-Engine testen | 🟡 In Arbeit |
| Integration Tests | Frontend-Backend-Kommunikation via flutter_rust_bridge | 🔴 Geplant |
| E2E Tests (Web) | WebRTC-Streaming und UI-Flüsse testen | 🔴 Geplant |
| CI/CD Optimierung | GStreamer-Builds beschleunigen | 🟡 In Arbeit |

## Phase 2: Plattformerweiterung (Q2–Q3 2024)

| Feature | Beschreibung | Status |
|---------|-------------|--------|
| Android-Support | Flutter auf Android mit C++ FFI | 🔴 Geplant |
| iOS-Support | Cross-compile für iOS (Metal statt OpenGL) | 🔴 Geplant |
| Orange Pi Optimierung | Performance-Tuning für Orange Pi Zero | 🟡 In Arbeit |
| Docker-Compose Setup | Multi-Container für Dev/Production | 🟡 In Arbeit |

## Phase 3: KI-Modelle & Performance (Q3–Q4 2024)

| Feature | Beschreibung | Status |
|---------|-------------|--------|
| TensorFlow Lite Integration | Leichtgewichtige Modelle | 🔴 Geplant |
| ONNX Runtime Support | Modellportabilität | 🔴 Geplant |
| GPU Acceleration (Vulkan) | Desktop-Performance | 🔴 Geplant |
| Edge TPU Support | Google Coral für Embedded | 🔴 Geplant |

## Phase 4: Developer Experience (Q4 2024–Q1 2025)

| Feature | Beschreibung | Status |
|---------|-------------|--------|
| Python Bindings | Schnelle Prototypisierung | 🔴 Geplant |
| CLI Tool | Standalone Inference | 🔴 Geplant |
| Beispielmodelle | Pre-packaged YOLOv5, MobileNet | 🟡 In Arbeit |
| Dokumentation erweitern | Video-Tutorials, Best Practices | 🟡 In Arbeit |

---

**Status-Legende:**
- 🟢 Abgeschlossen
- 🟡 In Arbeit
- 🔴 Geplant

Möchtest du eine Phase spezifizieren oder weitere Details zu einer bestimmten Funktion?
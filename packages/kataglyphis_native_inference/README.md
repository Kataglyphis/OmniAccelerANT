<div align="center">
  <a href="https://jonasheinle.de">
    <img src="images/logo.png" alt="logo" width="200" />
  </a>

  <h1>kataglyphis_native_inference 🚀</h1>

  <h4> The glue 📄🧴✂️ for a cross platform inference engine to its native interface </h4>
</div>

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/paypalme/JonasHeinle)
[![Twitter](https://img.shields.io/twitter/follow/Cataglyphis_?style=social)](https://twitter.com/Cataglyphis_)

## Table of Contents
- [About The Project](#about-the-project)
  - [Key Features](#key-features)
  - [Dependencies](#dependencies)
  - [Useful tools](#useful-tools)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Tests](#tests)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)
- [Acknowledgements](#acknowledgements)
- [Literature](#literature)

## About The Project

The Flutter plugin (Android, Linux, Windows) that bridges OmniAccelerANT's native camera,
texture and inference code to Dart.

### Key Features

- The `knt_push_frame`/`knt_api_version` C ABI on Linux and Windows: OxidANT's Rust webcam engine
  pushes frames into the plugin's texture through it.
- On Windows the texture is a CPU pixel buffer fed by `knt_push_frame`; the pipeline methods are
  no-ops kept for the method channel.

### Dependencies

- AccelerANTgine, the C++ inference core (`third_party/AccelerANTgine` in OmniAccelerANT),
  linked on Linux and Windows.
- GStreamer: through pkg-config on Linux, the Android GStreamer SDK (`GSTREAMER_ROOT_ANDROID`) on
  Android.

### Useful tools

## Getting Started

### Prerequisites

### Installation

This package is not standalone. It lives inside
[OmniAccelerANT](https://github.com/Kataglyphis/OmniAccelerANT) as a path dependency at
`packages/kataglyphis_native_inference` and is built by that repo's lanes: clone OmniAccelerANT
with `--recurse-submodules` instead.

## Tests

`flutter pub get && flutter test` in this directory runs the Dart tests (`test/`); the root's
`flutter test` does not reach them. OmniAccelerANT's lanes also run the plugin's gtest, its
`knt_*` C ABI checks and, on Android, its JVM test.

## Roadmap

## Contributing

Through [OmniAccelerANT](https://github.com/Kataglyphis/OmniAccelerANT), which this package is
part of: see its README, *Contributing and contact*.

## License

## Contact

Jonas Heinle - [@Cataglyphis_](https://twitter.com/Cataglyphis_) - jonasheinle@googlemail.com

## Acknowledgements

## Literature

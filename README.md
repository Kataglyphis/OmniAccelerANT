<h1 align="center">
  <br>
  <a href="https://jonasheinle.de"><img src="images/logo.png" alt="logo" width="200"></a>
  <br>
  Kataglyphis-Inference-Engine
  <br>
</h1>

<!-- <h1 align="center">
  <br>
  <a href="https://jonasheinle.de"><img src="images/vulkan-logo.png" alt="VulkanEngine" width="200"></a>
  <a href="https://jonasheinle.de"><img src="images/Engine_logo.png" alt="VulkanEngine" width="200"></a>
  <a href="https://jonasheinle.de"><img src="images/glm_logo.png" alt="VulkanEngine" width="200"></a>
</h1> -->

<h4 align="center">An inference engine with flutter/dart frontend an rust backend. <a href="https://jonasheinle.de" target="_blank"></a>.</h4>

[![Build + run + test on Linux](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart.yml)
[![TopLang](https://img.shields.io/github/languages/top/Kataglyphis/Kataglyphis-Inference-Engine)]()
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate/?hosted_button_id=BX9AVVES2P9LN)
[![Twitter](https://img.shields.io/twitter/follow/Cataglyphis_?style=social)](https://twitter.com/Cataglyphis_)
[![YouTube](https://img.shields.io/youtube/channel/subscribers/UC3LZiH4sZzzaVBCUV8knYeg?style=social)](https://www.youtube.com/channel/UC3LZiH4sZzzaVBCUV8knYeg)

[**__Official homepage__**](https://kataglyphisinferenceengine.jonasheinle.de)

<p align="center">
  <a href="#about-the-project">About The Project</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#license">License</a> •
  <a href="#literature">Literature</a>
</p>

<!-- TABLE OF CONTENTS -->
<details open="open">
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#key-features">Key Features</a></li>
      </ul>
      <ul>
        <li><a href="#dependencies">Dependencies</a></li>
      </ul>
      <ul>
        <li><a href="#useful-tools">Useful tools</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#tests">Tests</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgements">Acknowledgements</a></li>
    <li><a href="#literature">Literature</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project
Building a high performance native inference engine with a frontend is quite challenging. This project discovers possibilities in doing it using Flutter/Dart and Rust.  
<!-- <h1 align="center">
  <br>
  <a href="https://jonasheinle.de"><img src="images/Screenshot1.png" alt="VulkanEngine" width="400"></a>
  <a href="https://jonasheinle.de"><img src="images/Screenshot2.png" alt="VulkanEngine" width="400"></a>
  <a href="https://jonasheinle.de"><img src="images/Screenshot3.png" alt="VulkanEngine" width="700"></a>
</h1> -->

<!-- [![Kataglyphis Engine][product-screenshot1]](https://jonasheinle.de)
[![Kataglyphis Engine][product-screenshot2]](https://jonasheinle.de)
[![Kataglyphis Engine][product-screenshot3]](https://jonasheinle.de) -->

This project is a template. 

### Key Features

<!-- ❌  -->
<!-- |          Feature                    |   Implement Status |
| ------------------------------------| :----------------: |
| Rasterizer                          |         ✔️         |
| Raytracing                          |         ✔️         |
| Path tracing                        |         ✔️         |
| PBR support (UE4,disney,... etc.)   |         ✔️         |
| .obj Model loading                  |         ✔️         |
| Mip Mapping                         |         ✔️         | -->

### Dependencies
This enumeration also includes submodules.
<!-- * [Vulkan 1.3](https://www.vulkan.org/) -->

### Useful tools

<!-- * [cppcheck](https://cppcheck.sourceforge.io/) -->

<!-- GETTING STARTED -->
## Getting Started

### Prerequisites

### Installation

1. Clone the repo
   ```sh
   git clone --recurse-submodules git@github.com:Kataglyphis/Kataglyphis-Inference-Engine.git
   ```
### Upgrades
Upgrading the flutter/dart bridge dependencies is as simple as this command:  
[see source](https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/upgrade/regular)
```bash
cargo install flutter_rust_bridge_codegen && flutter_rust_bridge_codegen generate
```

### Windows
For windows we absolutely do not want to be dependent on MSVC compiler.  
Therefore I use [clang-cl](https://clang.llvm.org/docs/MSVCCompatibility.html).  
Using clang-cl instead of MSVC needed adjustment. Therefore i give some instructions here.  

#### Flutter generated cmake project
Adjust the CXX-Flags in the auto-generated Cmake project. Find the folloeing line 
and adjust accordingly:

```cmake
# comment this line
# target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
# add the following:
# target_compile_options(${TARGET} PRIVATE /W3 /WX /wd4100 -Wno-cast-function-type-mismatch -Wno-unused-function)
```

Now you can build the project by running following commands:  
**__Attention:__** Adjust paths accordingly.

```powershell
cd rust
cargo build --release
cp rust\target\release\rust_lib_kataglyphis_inference_engine.dll build\windows\x64\plugins\rust_lib_kataglyphis_inference_engine
cmake C:\GitHub\Kataglyphis-Inference-Engine\windows -B C:\GitHub\Kataglyphis-Inference-Engine\build\windows\x64 -G "Ninja" -DFLUTTER_TARGET_PLATFORM=windows-x64 -DCMAKE_CXX_COMPILER="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\Llvm\bin\clang-cl.exe" -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc
cmake --build C:\GitHub\Kataglyphis-Inference-Engine\build\windows\x64 --config Release --target install --verbose
```

## Tests

<!-- ROADMAP -->
## Roadmap
Upcoming :)
<!-- See the [open issues](https://github.com/othneildrew/Best-README-Template/issues) for a list of proposed features (and known issues). -->



<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to be learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


<!-- LICENSE -->
## License

<!-- CONTACT -->
## Contact

Jonas Heinle - [@Cataglyphis_](https://twitter.com/Cataglyphis_) - jonasheinle@googlemail.com

Project Link: [https://github.com/Kataglyphis/...](https://github.com/Kataglyphis/...)


<!-- ACKNOWLEDGEMENTS -->
## Acknowledgements

<!-- Thanks for free 3D Models: 
* [Morgan McGuire, Computer Graphics Archive, July 2017 (https://casual-effects.com/data)](http://casual-effects.com/data/)
* [Viking room](https://sketchfab.com/3d-models/viking-room-a49f1b8e4f5c4ecf9e1fe7d81915ad38) -->

## Literature 

Some very helpful literature, tutorials, etc. 

CMake/C++
* [clang-cl](https://clang.llvm.org/docs/MSVCCompatibility.html)

#!/usr/bin/env bash
# Builds the ESP32-S3-EYE camera firmware: ESP-WHO/ESP-DL cat detection (C++) plus the
# Rust USB protocol layer (staticlib), in the official ESP-IDF image.
#
#   scripts/linux/esp32/build-eye-demo.sh
#   scripts/linux/esp32/build-eye-demo.sh --flash
#   scripts/linux/esp32/build-eye-demo.sh --flash --port /dev/ttyACM0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
who="${ESP_WHO_DIR:-${HOME}/.cache/esp-who}"
who_ref="${ESP_WHO_REF:-b6ac2be404f65027ff3a2bc231a946d2d475ba91}"
rust_dir="${repo_root}/firmware/esp32-s3-eye/rust_protocol"
image="${IDF_IMAGE:-espressif/idf:release-v5.5}"
engine="${KATAGLYPHIS_ENGINE:-nerdctl}"
port="${ESP32_PORT:-/dev/ttyACM0}"
flash=0

usage() {
    sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flash) flash=1; shift ;;
        --port) port="${2:?--port needs a device}"; shift 2 ;;
        --image) image="${2:?--image needs a tag}"; shift 2 ;;
        --engine) engine="${2:?--engine needs a binary}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v "$engine" >/dev/null 2>&1 || {
    echo "container engine not found: $engine" >&2
    exit 2
}
if [[ "$flash" == 1 && ! -c "$port" ]]; then
    echo "flash requested but $port is not a character device" >&2
    exit 2
fi

if [[ ! -d "$who/.git" ]]; then
    echo "cloning ESP-WHO into $who"
    git clone --recursive --depth 300 https://github.com/espressif/esp-who.git "$who"
fi
if ! git -C "$who" rev-parse --verify --quiet "$who_ref" >/dev/null; then
    git -C "$who" fetch --depth 300 origin master
fi
git -C "$who" checkout -f "$who_ref"

# The terminal app prints detections a serial monitor can check (the LCD app only shows them); idempotent.
python3 - "$who/examples/object_detect/main/app_main.cpp" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
if "    run_detect_term();" not in source:
    source = source.replace("    run_detect_lcd();", "    // run_detect_lcd();")
    source = source.replace(
        "    // run_detect_term();", "    run_detect_term();"
    )
# BSP 5.0.2 predates the led_indicator BSP helpers used by this example.
source = source.replace("#ifdef BSP_BOARD_ESP32_S3_EYE", "#if 0")
if '#include "omni_proto.h"' not in source:
    source = source.replace(
        '#include "frame_cap_pipeline.hpp"',
        '#include "frame_cap_pipeline.hpp"\n#include "omni_proto.h"',
    )
if "omni_proto_start();" not in source:
    source = source.replace(
        "    vTaskPrioritySet(xTaskGetCurrentTaskHandle(), 5);",
        "    vTaskPrioritySet(xTaskGetCurrentTaskHandle(), 5);\n    omni_proto_start();",
    )
path.write_text(source)
PY

# The callback runs on the detect task; count and best score go to the Rust task, which owns the USB frames.
python3 - "$who/components/who_app/who_detect_app/who_detect_app_term.cpp" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
if '#include "omni_proto.h"' not in source:
    source = source.replace(
        '#include "who_yield2idle.hpp"',
        '#include "who_yield2idle.hpp"\n#include "omni_proto.h"',
    )
old = """void WhoDetectAppTerm::detect_result_cb(const detect::WhoDetect::result_t &result)
{
    detect::print_detect_results(result.det_res);
}"""
new = """void WhoDetectAppTerm::detect_result_cb(const detect::WhoDetect::result_t &result)
{
    unsigned count = 0;
    unsigned best = 0;
    for (const auto &det : result.det_res) {
        ++count;
        unsigned score = static_cast<unsigned>(det.score * 1000.0f);
        if (score > best) {
            best = score;
        }
    }
    omni_proto_on_detections(count, best);
    detect::print_detect_results(result.det_res);
}"""
if old in source:
    source = source.replace(old, new)
path.write_text(source)
PY

# esp-dl 3.3.13 changed the image API (RGB565 LE/BE, img_t::bytes(), sw_decode_jpeg) after the pinned ESP-WHO.
python3 - "$who" <<'PY'
import re
import sys
from pathlib import Path

who = Path(sys.argv[1])
files = [
    "components/who_peripherals/who_cam/who_cam_define.hpp",
    "components/who_frame_cap/who_frame_cap_node.cpp",
    "components/who_app/who_app_common/who_detect_result_handle/who_detect_result_handle.cpp",
    "components/who_qrcode/who_qrcode.cpp",
    "examples/object_detect/main/frame_cap_pipeline.cpp",
]
for rel in files:
    path = who / rel
    if not path.exists():
        continue
    source = path.read_text()
    source = re.sub(
        r"dl::image::DL_IMAGE_PIX_TYPE_RGB565(?!LE|BE)",
        "dl::image::DL_IMAGE_PIX_TYPE_RGB565BE",
        source,
    )
    source = source.replace("dl::image::DL_IMAGE_CAP_RGB565_BIG_ENDIAN", "0")
    source = source.replace("dl::image::get_img_byte_size(img)", "img.bytes()")
    source = source.replace(
        "sw_decode_jpeg({fb->buf, fb->len}, m_pix_type, caps)",
        "sw_decode_jpeg({fb->buf, fb->len}, m_pix_type)",
    )
    # cvt_pix's last argument is now a pix_cvt_param_t, not the old caps word.
    source = re.sub(r",\s*caps\);", ");", source)
    if "auto img = sw_decode_jpeg(" in source and "(void)caps;" not in source:
        source = source.replace(
            "    auto img = sw_decode_jpeg(",
            "    (void)caps;\n    auto img = sw_decode_jpeg(",
        )
    path.write_text(source)
PY

# '*' resolves to BSP 6.0.0, whose Kconfig breaks these sdkconfig defaults; bsp_ext.py keeps a pinned version.
python3 - "$who/examples/object_detect/main/idf_component.yml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_text(
    "dependencies:\n"
    "  esp32_s3_eye_noglib:\n"
    "    version: '5.0.2'\n"
    "  cat_detect:\n"
    "    version: '0.3.0'\n"
)
PY

# Build the Rust staticlib on the host; the ESP-IDF container only links it.
# shellcheck source=scripts/linux/lib/espup-env.sh
source "${repo_root}/scripts/linux/lib/espup-env.sh"
omni_espup_environment
(
    cd "$rust_dir"
    cargo +esp build --release
)
cp "$rust_dir/target/xtensa-esp32s3-none-elf/release/libomni_esp32_eye_proto.a" \
    "$who/examples/object_detect/main/libomni_esp32_eye_proto.a"
cp "$rust_dir/include/omni_proto.h" "$who/examples/object_detect/main/omni_proto.h"
cp "$rust_dir/include/omni_proto.h" \
    "$who/components/who_app/who_detect_app/omni_proto.h"

python3 - "$who/examples/object_detect/main/CMakeLists.txt" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
if "libomni_esp32_eye_proto.a" not in source:
    source += (
        "\nadd_prebuilt_library(omni_proto "
        '"${CMAKE_CURRENT_SOURCE_DIR}/libomni_esp32_eye_proto.a")\n'
        "target_link_libraries(${COMPONENT_LIB} INTERFACE omni_proto)\n"
    )
if "esp_efuse_mac_get_default" not in source:
    # The Rust archive sits at the end of the link line; force the two symbols it
    # needs out of the earlier IDF archives.
    source += (
        "target_link_options(${COMPONENT_LIB} INTERFACE\n"
        '    "-Wl,--undefined=esp_efuse_mac_get_default"\n'
        '    "-Wl,--undefined=xTaskCreatePinnedToCore"\n'
        '    "-Wl,--undefined=usb_serial_jtag_driver_install")\n'
    )
path.write_text(source)
PY

run_args=(
    run --rm
    --user root
    -v "$who:/workspace"
    -w /workspace/examples/object_detect
    -e IDF_EXTRA_ACTIONS_PATH=/workspace/tools
)
if [[ "$flash" == 1 ]]; then
    run_args+=(--device "$port")
fi

"$engine" "${run_args[@]}" "$image" bash -lc "
set -euo pipefail
idf.py --version

if [ ! -f sdkconfig ]; then
  rm -rf build managed_components
  # The tested lock for this BSP+model; '*' would pick a BSP whose Kconfig breaks this sdkconfig.
  cp dependencies.lock.esp32_s3_eye_noglib.cat_detect dependencies.lock 2>/dev/null || true
  idf.py -DSDKCONFIG_DEFAULTS=sdkconfig.bsp.esp32_s3_eye_noglib \
    -DDETECT_MODEL=cat_detect set-target esp32s3
fi

# The Rust task owns USB Serial/JTAG: a console there would eat the host's HostHello, so it goes to UART0.
sed -i 's/^CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y/# CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG is not set/' sdkconfig || true
grep -q '^CONFIG_ESP_CONSOLE_UART_DEFAULT=y' sdkconfig || \
  echo 'CONFIG_ESP_CONSOLE_UART_DEFAULT=y' >> sdkconfig

idf.py build
if [ '$flash' = 1 ]; then
  idf.py -p '$port' flash
fi
"

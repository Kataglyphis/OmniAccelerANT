#!/usr/bin/env bash
# Runs the cat-detection producer (kataglyphis_cat_webrtc) from the
# :latest-cross container against a Raspberry Pi's CSI camera.
#
# Why this is not a plain `nerdctl run`: the Pi 5 kernel (6.18) renamed the
# rp1-cfe media entities to underscores (`rp1-cfe-fe_image0`) and moved to the
# libpisp 1.7 uAPI. The image's upstream libcamera 0.7.2 / libpisp 1.5 cannot
# drive that camera — no CFE match at first, then a segfault in the IPA. The
# host's Raspberry Pi OS libcamera (0.7.2+rpt) *does* match the kernel, so its
# stack and the transitive closure of its shared libraries are collected into
# build/cat-stream/hostlibs and bind-mounted ahead of the image's copy.
# Everything else (GStreamer 1.29, gst-plugins-rs/webrtcsink, ONNX Runtime,
# the Rust binary) still comes from the image.
#
# Usage:
#   scripts/linux/cat-stream/run-producer-pi.sh [--build] [--port 8443]
#       [--model FILE] [--width N] [--height N] [--fps N] [--name NAME]
#       [--libs-only]
#
# --build      build the producer in the container first (long cargo build)
# --libs-only  refresh build/cat-stream/hostlibs and exit
#
# The web frontend side: scripts/linux/cat-stream/serve.sh
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"

image="ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest-cross"
target_volume="kataglyphis-cat-target"
cargo_volume="kataglyphis-cat-cargo"
container_name="cat-producer"
build_dir="${repo_root}/build/cat-stream"
hostlibs_dir="${build_dir}/hostlibs"
producer="/cargo-target/release/kataglyphis_cat_webrtc"
port=8443
name="Trouble Tabbls Cat Cam"
model=""
width=640
height=480
fps=30
do_build=false
libs_only=false

usage() {
  cat <<'EOF'
usage: run-producer-pi.sh [--build] [--libs-only] [--port N] [--model FILE]
                          [--width N] [--height N] [--fps N] [--name NAME]

  --build      build the producer in the container first (long cargo build)
  --libs-only  refresh build/cat-stream/hostlibs and exit

Runs the cat producer from the :latest-cross container against the Pi's CSI
camera; serve.sh is the web/HTTPS half. Stop the producer with
`nerdctl rm -f cat-producer`.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build) do_build=true; shift ;;
    --libs-only) libs_only=true; shift ;;
    --port) port="${2:?--port needs a value}"; shift 2 ;;
    --model) model="${2:?--model needs a value}"; shift 2 ;;
    --width) width="${2:?--width needs a value}"; shift 2 ;;
    --height) height="${2:?--height needs a value}"; shift 2 ;;
    --fps) fps="${2:?--fps needs a value}"; shift 2 ;;
    --name) name="${2:?--name needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v nerdctl >/dev/null 2>&1 || {
  printf 'nerdctl not found - is containerd running?\n' >&2
  exit 1
}

# Collect the host libcamera stack and its library closure. Done once; delete
# build/cat-stream/hostlibs to refresh after a system upgrade.
collect_hostlibs() {
  local libcamera_real libcamera_base
  libcamera_real="$(readlink -f /usr/lib/aarch64-linux-gnu/libcamera.so.0.7 2>/dev/null || true)"
  if [ -z "${libcamera_real}" ] || [ ! -e "${libcamera_real}" ]; then
    printf 'host libcamera not found - this script expects Raspberry Pi OS with libcamera installed\n' >&2
    exit 1
  fi
  libcamera_base="$(dirname "${libcamera_real}")"
  local pisp
  pisp="$(readlink -f /lib/aarch64-linux-gnu/libpisp.so.1 2>/dev/null || true)"
  if [ -z "${pisp}" ] || [ ! -e "${pisp}" ]; then
    pisp="$(readlink -f /usr/lib/aarch64-linux-gnu/libpisp.so.1 2>/dev/null || true)"
  fi
  if [ -z "${pisp}" ] || [ ! -e "${pisp}" ]; then
    printf 'host libpisp not found\n' >&2
    exit 1
  fi
  local ipa="${libcamera_base}/libcamera/ipa/ipa_rpi_pisp.so"
  [ -e "${ipa}" ] || { printf 'host rpi/pisp IPA not found at %s\n' "${ipa}" >&2; exit 1; }

  rm -rf "${hostlibs_dir}"
  mkdir -p "${hostlibs_dir}"
  printf 'collecting host libcamera libraries into %s\n' "${hostlibs_dir}"
  # `ipa_rpi_pisp.so` is copied for name-sake only; libcamera loads the IPA
  # from its own (mounted) directory, not from here.
  local queue=(
    "$(readlink -f "${libcamera_base}/libcamera.so.0.7")"
    "$(readlink -f "${libcamera_base}/libcamera-base.so.0.7")"
    "${pisp}"
    "${ipa}"
  )
  declare -A seen=()
  while ((${#queue[@]})); do
    local f="${queue[0]}"; queue=("${queue[@]:1}")
    if [ -z "$f" ] || [ ! -e "$f" ]; then
      continue
    fi
    local base; base="$(basename "$f")"
    case "$base" in
      libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1|libgcc_s.so.1|libstdc++.so.6|ld-linux*) continue ;;
    esac
    [ -n "${seen[$base]:-}" ] && continue
    seen[$base]=1
    cp -L "$f" "${hostlibs_dir}/${base}"
    while IFS= read -r dep; do
      [ -n "$dep" ] && [ -e "$dep" ] && queue+=("$dep")
    done < <(ldd "$f" 2>/dev/null | awk '/=> \// {print $3} /^\t\/[^ ]+ \(/ {print $1}')
  done
  # NEEDED entries reference sonames; the closure names files after their real
  # paths, so link each soname the loader will ask for.
  local lib soname
  for lib in "${hostlibs_dir}"/*; do
    soname="$(readelf -d "$lib" 2>/dev/null | awk '/SONAME/ {gsub(/[][]/,""); print $NF}')"
    if [ -n "${soname}" ] && [ ! -e "${hostlibs_dir}/${soname}" ]; then
      ln -s "$(basename "$lib")" "${hostlibs_dir}/${soname}"
    fi
  done
  printf 'collected %d libraries (%s)\n' "${#seen[@]}" "$(du -sh "${hostlibs_dir}" | cut -f1)"
}

if [ "${libs_only}" = true ]; then
  collect_hostlibs
  exit 0
fi
[ -d "${hostlibs_dir}" ] || collect_hostlibs

# Rootless containers map container-root to the invoking host user, so the
# video/media/dma-heap nodes need an ACL for that user (the `video` group is
# not carried into the user namespace).
for dev in /dev/media* /dev/video* /dev/dma_heap/*; do
  [ -e "$dev" ] || continue
  [ -w "$dev" ] && continue
  printf 'granting %s ACL access to %s\n' "$dev" "$(id -un)"
  sudo setfacl -m "u:$(id -un):rw" "$dev"
done

ld_library_path="/hostlibs:/opt/gstreamer/lib/multiarch:/opt/gstreamer/lib"
ld_library_path+=":/opt/opencv5/lib:/opt/opencv5/lib64:/usr/local/lib"
ld_library_path+=":/opt/vulkan/active/lib:/opt/ffmpeg/lib:/opt/ffmpeg/lib64"
ld_library_path+=":/opt/gcc-16.2.0/lib64:/opt/gcc-16.2.0/lib"
ld_library_path+=":/usr/lib/aarch64-linux-gnu"

nerdctl_args=(
  run --rm
  --name "${container_name}"
  --user 0:0
  --network host
  # The RPi IPA proxy starts a forked worker; the default seccomp profile
  # answers that fork with ENOSYS.
  --security-opt seccomp=unconfined
  -v /sys:/sys:ro
  -v /dev:/dev
  -v /run/udev:/run/udev:ro
  -v "${hostlibs_dir}":/hostlibs:ro
  -v /usr/lib/aarch64-linux-gnu/libcamera:/usr/lib/aarch64-linux-gnu/libcamera:ro
  -v /usr/share/libcamera:/usr/share/libcamera:ro
  -v /usr/share/libpisp:/usr/share/libpisp:ro
  -v "${repo_root}":/workspace
  -v "${target_volume}":/cargo-target
  -e "LD_LIBRARY_PATH=${ld_library_path}"
  -e ORT_DYLIB_PATH=/opt/opencv5/lib/libonnxruntime.so
  -e RUST_LOG="${RUST_LOG:-info}"
  --entrypoint "${producer}"
  "${image}"
  --libcamera
  --listen-port "${port}"
  --name "${name}"
  --width "${width}"
  --height "${height}"
  --fps "${fps}"
)

if [ -n "${model}" ]; then
  nerdctl_args+=(--model "${model}")
fi

producer_present() {
  nerdctl run --rm --user 0:0 --entrypoint bash -v "${target_volume}":/cargo-target "${image}" \
    -c "test -x ${producer}" >/dev/null 2>&1
}

if [ "${do_build}" = true ] || ! producer_present; then
  [ "${do_build}" = true ] || {
    printf 'producer binary missing in volume %s - rerun with --build\n' "${target_volume}" >&2
    exit 1
  }
  printf 'building kataglyphis_cat_webrtc in the container (this takes a while)\n'
  nerdctl run --rm --user 0:0 --network host \
    -v "${repo_root}":/workspace \
    -v "${target_volume}":/cargo-target \
    -v "${cargo_volume}":/cargo-home \
    -e CARGO_TARGET_DIR=/cargo-target -e CARGO_HOME=/cargo-home \
    --entrypoint bash "${image}" \
    -lc 'cd /workspace/third_party/OxidANT && cargo build --release --locked -p kataglyphis_cat_webrtc'
fi

# A producer from an interrupted run still holds the name; replace it rather
# than fail at container creation.
nerdctl rm -f "${container_name}" >/dev/null 2>&1 || true

printf 'starting the producer: libcamerasrc -> YOLO -> webrtcsink on port %s\n' "${port}"
printf 'stop it with: nerdctl rm -f %s\n' "${container_name}"
exec nerdctl "${nerdctl_args[@]}"

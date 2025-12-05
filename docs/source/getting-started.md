# Getting Started

Follow these steps to set up the Kataglyphis Inference Engine locally.

## Prerequisites

### GStreamer

Find all available video devices on Linux:

```bash
for dev in /dev/video*; do
  echo "Testing $dev"
  gst-launch-1.0 -v v4l2src device=$dev ! fakesink
done
```

Check available resolutions and framerates:

```bash
apt update
apt install v4l-utils
v4l2-ctl --device=/dev/video0 --list-formats-ext
```

### WSL2 USB Passthrough

If running Docker on WSL2, share USB devices before use:

```bash
# List USB devices
usbipd list
# Attach device to WSL
usbipd attach --wsl --busid 1-1.2
# Verify in WSL
lsusb
# Example output for Basler USB camera: /dev/bus/usb/002/002
```

## Installation

3. Install the GStreamer WebRTC JavaScript libraries. The `public/lib` folder contains two JavaScript libraries generated from [gstwebrtc-api](https://github.com/GStreamer/gst-plugins-rs/tree/main/net/webrtc/gstwebrtc-api).

> **NOTE:** If publishing to the internet, replace `127.0.0.1` with your domain:
>
> ```bash
> sed -i 's@ws://127.0.0.1:8443@ws://customdomain:8443@g' ./public/lib/gstwebrtc-api-1.0.1.min.js
> ```
>
> To find all IP addresses and ports:
>
> ```bash
> grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}\b' yourfile.txt
> ```

## Running the Application

### Development Mode

```bash
flutter run -d web-server --profile --web-port 8080 --web-hostname 0.0.0.0
```

### Production Build

Production build automation is under construction. Use your preferred CI/CD setup or follow the platform-specific guides to create release artifacts.

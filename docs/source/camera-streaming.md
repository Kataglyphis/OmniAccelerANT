# Camera Streaming

Guides for configuring WebRTC streaming pipelines and inference demos.

## GStreamer WebRTC Setup

Follow the official [GStreamer WebRTC tutorial](https://gstreamer.freedesktop.org/documentation/rswebrtc/index.html?gi-language=c) for deeper background.

### 1. Start the Signalling Server

```bash
cd /opt/gst-plugins-rs/net/webrtc/signalling
WEBRTCSINK_SIGNALLING_SERVER_LOG=debug cargo run --bin gst-webrtc-signalling-server -- --port 8444 --host 127.0.0.1
```

### 2. Stream From a Webcam

Set the plugin path before launching pipelines:

```bash
export GST_PLUGIN_PATH=/home/user/gst-plugins-rs/target/release:$GST_PLUGIN_PATH
```

**USB webcam (inside Docker):**

```bash
gst-launch-1.0 -e webrtcsink signaller::uri="ws://ubuntu:8444" name=ws \
  meta="meta,name=kataglyphis-webfrontend-stream" \
  v4l2src device=/dev/video0 ! image/jpeg,width=640,height=360,framerate=30/1 ! \
  jpegdec ! videoconvert ! ws.
```

**Pylon camera:**

```bash
gst-launch-1.0 -e webrtcsink signaller::uri="ws://ubuntu:8444" name=ws \
  meta="meta,name=kataglyphis-webfrontend-stream" \
  pylonsrc ! videoconvert ! ws. audiotestsrc ! ws.
```

**Orange Pi RV2 RISC-V board:**

```bash
GST_DEBUG=4 gst-launch-1.0 -v -e v4l2src device=/dev/video20 ! \
  video/x-raw,format=YUY2,width=1280,height=720,framerate=5/1 ! \
  videoconvert ! video/x-raw,format=I420 ! kyh264enc ! h264parse config-interval=1 ! \
  capsfilter caps="video/x-h264,stream-format=(string)byte-stream,alignment=(string)au,profile=(string)main,level=(string)3.1,coded-picture-structure=(string)frame,chroma-format=(string)4:2:0,bit-depth-luma=(uint)8,bit-depth-chroma=(uint)8,parsed=(boolean)true" ! \
  queue ! webrtcsink congestion-control=disabled signaller::uri="ws://0.0.0.0:8443" name=ws \
  meta="meta,name=kataglyphis-webfrontend-stream"
```

**Rotating camera stream:**

```bash
gst-launch-1.0 ... \
  video/x-raw,width=1280,height=720,format=NV12,interlace-mode=progressive ! \
  videoflip method=rotate-180 ! \
  x264enc speed-preset=1 threads=1 byte-stream=true ! \
  ...
```

### 3. Launch the Web App

Once the stream is live, run the Flutter web frontend as described in the [web build guide](platforms.md#web-build).

## Python Inference Pipelines

Install system dependencies first:

```bash
sudo apt install libgirepository1.0-dev gir1.2-glib-2.0 \
  build-essential pkg-config python3-dev libgirepository-2.0-dev \
  gobject-introspection libcairo2-dev python3-gi python3-gi-cairo gir1.2-gtk-4.0
```

> **NOTE for Raspberry Pi:** Share system packages into your virtual environment:
>
> ```bash
> python3 -m venv --system-site-packages .venv
> ```

### demo_ai.py

```bash
uv venv
uv pip install loguru pygobject numpy opencv-python
GST_DEBUG=3 python3 demo_ai.py
```

### demo_yolov5.py

```bash
uv venv
uv pip install loguru pygobject numpy opencv-python
uv pip install torch==2.5.0 torchvision==0.20.0 torchaudio==2.5.0 --index-url https://download.pytorch.org/whl/cu121
uv pip install seaborn ultralytics
GST_DEBUG=3 python3 demo_yolov5.py
```

### Example Pipeline

```bash
gst-launch-1.0 -e webrtcsink signaller::uri="ws://ubuntu:8443" name=ws \
  meta="meta,name=kataglyphis-webfrontend-stream" \
  v4l2src device=/dev/video0 ! video/x-raw,width=320,height=240,framerate=10/1 ! \
  videoconvert ! ws.
```

Increase verbosity with `GST_DEBUG=2` to see FPS data in the logs.

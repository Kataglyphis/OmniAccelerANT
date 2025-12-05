#!/usr/bin/env python3
import gi
import sys
import torch
import numpy as np
import cv2

gi.require_version('Gst', '1.0')
gi.require_version('GstWebRTC', '1.0')
from gi.repository import Gst, GObject, GLib

# ---- Config ----
VIDEO_DEVICE = "/dev/video20"
WIDTH = 1280
HEIGHT = 720
FPS_NUM = 5
FPS_DEN = 1
YOLO_SIZE = 640  # inference resize (tweak for perf/accuracy)
MODEL_NAME = 'yolov5n'  # or yolov5m, etc.

# Load model once before pipeline
model = torch.hub.load('ultralytics/yolov5', MODEL_NAME, pretrained=True)
model.conf = 0.25
model.iou = 0.45


def on_new_sample(sink, appsrc):
    """
    appsink -> pull sample, convert to numpy BGR, run YOLO, draw,
    then push to appsrc (which will be converted to I420 and encoded).
    """
    sample = sink.emit("pull-sample")
    if not sample:
        return Gst.FlowReturn.ERROR

    buffer = sample.get_buffer()
    caps = sample.get_caps()
    struct = caps.get_structure(0)
    width = struct.get_value('width')
    height = struct.get_value('height')

    # Map incoming buffer for read
    success, map_info = buffer.map(Gst.MapFlags.READ)
    if not success:
        return Gst.FlowReturn.ERROR

    try:
        # Build HxWx3 uint8 numpy frame (BGR) — ensure appsink sends BGR
        frame = np.ndarray(
            (height, width, 3),
            buffer=map_info.data,
            dtype=np.uint8
        ).copy()

        # ---- YOLOv5 Inference ----
        img = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = model(img, size=YOLO_SIZE)

        # draw detections
        if len(results.xyxy) and len(results.xyxy[0]):
            for *box, conf, cls in results.xyxy[0].cpu().numpy():
                x1, y1, x2, y2 = map(int, box)
                label = results.names[int(cls)]
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                text = f"{label} {conf:.2f}"
                (w, h), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
                cv2.rectangle(frame, (x1, y1 - h - 4), (x1 + w, y1), (0, 255, 0), -1)
                cv2.putText(frame, text, (x1, y1 - 2),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1)

        # (Optional) red circle as before
        center = (width // 2, height // 2)
        cv2.circle(frame, center, 50, (255, 0, 0), thickness=5)

        # Pack into Gst.Buffer for appsrc — keep same caps as appsrc (BGR)
        data = frame.tobytes()
        out_buffer = Gst.Buffer.new_allocate(None, len(data), None)
        out_buffer.fill(0, data)

        # Preserve timestamps to keep webrtc timing reasonable
        out_buffer.pts = buffer.pts
        out_buffer.dts = buffer.dts
        out_buffer.duration = buffer.duration

    finally:
        buffer.unmap(map_info)

    # Push into appsrc pipeline
    appsrc.emit("push-buffer", out_buffer)
    return Gst.FlowReturn.OK


def on_message(bus, message, loop):
    t = message.type
    if t == Gst.MessageType.EOS:
        print("End-Of-Stream")
        loop.quit()
    elif t == Gst.MessageType.ERROR:
        err, debug = message.parse_error()
        print(f"Error from {message.src.get_name()}: {err} - {debug}")
        loop.quit()


def main():
    Gst.init(None)

    # Source pipeline: v4l2src (YUY2) -> videoconvert -> BGR -> appsink
    pipeline1_str = (
        f'v4l2src device={VIDEO_DEVICE} ! '
        f'video/x-raw,format=YUY2,width={WIDTH},height={HEIGHT},framerate={FPS_NUM}/{FPS_DEN} ! '
        'videoconvert ! '
        f'video/x-raw,format=BGR,width={WIDTH},height={HEIGHT},framerate={FPS_NUM}/{FPS_DEN} ! '
        'appsink name=ai_sink emit-signals=true max-buffers=1 drop=true'
    )

    # Sender pipeline: appsrc (BGR) -> videoconvert -> I420 -> kyh264enc -> h264parse -> capsfilter -> queue -> webrtcsink
    pipeline2_str = (
        f'appsrc name=ai_src is-live=true block=true format=time caps=video/x-raw,format=BGR,width={WIDTH},height={HEIGHT},framerate={FPS_NUM}/{FPS_DEN} ! '
        'videoconvert ! '
        'video/x-raw,format=I420 ! '
        'kyh264enc ! '
        'h264parse config-interval=1 ! '
        'capsfilter caps="video/x-h264, stream-format=(string)byte-stream,alignment=(string)au, profile=(string)main,level=(string)3.1, coded-picture-structure=(string)frame, chroma-format=(string)4:2:0, bit-depth-luma=(uint)8, bit-depth-chroma=(uint)8, parsed=(boolean)true" ! '
        'queue ! '
        'webrtcsink name=ws congestion-control=disabled signaller::uri="ws://0.0.0.0:8443" meta="meta,name=kataglyphis-webfrontend-stream"'
    )

    pipeline1 = Gst.parse_launch(pipeline1_str)
    pipeline2 = Gst.parse_launch(pipeline2_str)

    if not pipeline1 or not pipeline2:
        print("Failed to create pipelines.")
        return

    ai_sink = pipeline1.get_by_name("ai_sink")
    ai_src = pipeline2.get_by_name("ai_src")
    if not ai_sink or not ai_src:
        print("Failed to get app elements by name.")
        return

    # Connect appsink new-sample -> on_new_sample, pass ai_src as user_data
    ai_sink.connect("new-sample", on_new_sample, ai_src)

    # Message handling
    loop = GLib.MainLoop()
    bus1 = pipeline1.get_bus()
    bus2 = pipeline2.get_bus()
    bus1.add_signal_watch()
    bus2.add_signal_watch()
    bus1.connect("message", on_message, loop)
    bus2.connect("message", on_message, loop)

    # Start pipelines
    ret1 = pipeline1.set_state(Gst.State.PLAYING)
    ret2 = pipeline2.set_state(Gst.State.PLAYING)
    if ret1 == Gst.StateChangeReturn.FAILURE or ret2 == Gst.StateChangeReturn.FAILURE:
        print("Unable to set pipelines to playing state")
        pipeline1.set_state(Gst.State.NULL)
        pipeline2.set_state(Gst.State.NULL)
        return

    try:
        print("Running pipelines... (Ctrl+C to stop)")
        loop.run()
    except KeyboardInterrupt:
        print("Interrupted by user, stopping pipelines.")
    finally:
        pipeline1.set_state(Gst.State.NULL)
        pipeline2.set_state(Gst.State.NULL)


if __name__ == "__main__":
    main()

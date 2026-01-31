#!/usr/bin/env python3
import gi
import sys

import torch
import numpy as np
import cv2

gi.require_version("Gst", "1.0")
gi.require_version("GstWebRTC", "1.0")
from gi.repository import Gst, GObject, GLib

# Load the YOLOv5 model once, ideally before you start the pipeline:
# (you can choose 'yolov5s', 'yolov5m', etc. depending on your needs)
model = torch.hub.load("ultralytics/yolov5", "yolov5s", pretrained=True)
model.conf = 0.25  # confidence threshold (optional)
model.iou = 0.45  # NMS IoU threshold (optional)


def on_new_sample(sink, appsrc):
    sample = sink.emit("pull-sample")
    if not sample:
        return Gst.FlowReturn.ERROR

    buffer = sample.get_buffer()
    caps = sample.get_caps()
    struct = caps.get_structure(0)
    width = struct.get_value("width")
    height = struct.get_value("height")

    success, map_info = buffer.map(Gst.MapFlags.READ)
    if not success:
        return Gst.FlowReturn.ERROR

    try:
        # build a HxWx3 uint8 numpy frame (BGR)
        frame = np.ndarray(
            (height, width, 3), buffer=map_info.data, dtype=np.uint8
        ).copy()

        # ---- YOLOv5 Inference ----
        # convert BGR→RGB
        img = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        # run inference (will return a "Results" object)
        results = model(img, size=640)  # you can tweak size for speed/accuracy

        # parse detections
        # results.xyxy[0] is a tensor of [x1, y1, x2, y2, conf, cls]
        for *box, conf, cls in results.xyxy[0].cpu().numpy():
            x1, y1, x2, y2 = map(int, box)
            label = results.names[int(cls)]
            # draw rectangle (green) and label (white on black bg)
            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            text = f"{label} {conf:.2f}"
            # get text size
            (w, h), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
            # background
            cv2.rectangle(frame, (x1, y1 - h - 4), (x1 + w, y1), (0, 255, 0), -1)
            # text
            cv2.putText(
                frame, text, (x1, y1 - 2), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1
            )
        # ---------------------------

        # (Optional) also draw your red circle
        center = (width // 2, height // 2)
        cv2.circle(frame, center, 50, (255, 0, 0), thickness=5)

        # pack back into a Gst.Buffer
        out_buffer = Gst.Buffer.new_allocate(None, frame.nbytes, None)
        out_buffer.fill(0, frame.tobytes())
        out_buffer.pts = buffer.pts
        out_buffer.dts = buffer.dts
        out_buffer.duration = buffer.duration

    finally:
        buffer.unmap(map_info)

    appsrc.emit("push-buffer", out_buffer)
    return Gst.FlowReturn.OK


def on_message(bus, message, loop):
    msg_type = message.type

    if msg_type == Gst.MessageType.EOS:
        print("End-Of-Stream reached.")
        loop.quit()

    elif msg_type == Gst.MessageType.ERROR:
        err, debug = message.parse_error()
        print(f"Error: {err}, {debug}")
        loop.quit()


def main():
    Gst.init(None)

    # Pipeline 1: Kamera -> JPEG -> RGB -> appsink
    pipeline1_str = (
        "v4l2src device=/dev/video0 ! "
        "image/jpeg,width=640,height=360,framerate=30/1 ! "
        "jpegdec ! "
        "videoconvert ! "
        "video/x-raw,format=RGB,width=640,height=360,framerate=30/1 ! "
        "appsink name=ai_sink emit-signals=true max-buffers=1 drop=true"
    )

    # Pipeline 2: appsrc -> webrtcsink
    pipeline2_str = (
        "appsrc name=ai_src is-live=true block=true format=time caps=video/x-raw,format=RGB,width=640,height=360,framerate=30/1 ! "
        "videoconvert ! "
        'webrtcsink name=ws meta="meta,name=kataglyphiswebfrontend-webfrontend-stream"'
    )

    pipeline1 = Gst.parse_launch(pipeline1_str)
    pipeline2 = Gst.parse_launch(pipeline2_str)
    if not pipeline1 or not pipeline2:
        print("Failed to create pipelines.")
        return

    ai_sink = pipeline1.get_by_name("ai_sink")
    ai_src = pipeline2.get_by_name("ai_src")
    ai_sink.connect("new-sample", on_new_sample, ai_src)

    # Message handling für beide Pipelines
    loop = GLib.MainLoop()
    bus1 = pipeline1.get_bus()
    bus2 = pipeline2.get_bus()
    bus1.add_signal_watch()
    bus2.add_signal_watch()
    bus1.connect("message", on_message, loop)
    bus2.connect("message", on_message, loop)

    # Pipelines starten
    ret1 = pipeline1.set_state(Gst.State.PLAYING)
    ret2 = pipeline2.set_state(Gst.State.PLAYING)
    if ret1 == Gst.StateChangeReturn.FAILURE or ret2 == Gst.StateChangeReturn.FAILURE:
        print("Unable to set pipelines to playing state")
        return

    try:
        print("Running pipelines...")
        loop.run()
    except KeyboardInterrupt:
        print("Interrupted by user, stopping pipelines.")
    finally:
        pipeline1.set_state(Gst.State.NULL)
        pipeline2.set_state(Gst.State.NULL)


if __name__ == "__main__":
    main()

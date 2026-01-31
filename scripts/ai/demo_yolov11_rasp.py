#!/usr/bin/env python3
import gi
import sys
import torch
import numpy as np
import cv2

# Ultralytics YOLO11
from ultralytics import YOLO

gi.require_version('Gst', '1.0')
gi.require_version('GstWebRTC', '1.0')
from gi.repository import Gst, GObject, GLib

# ---- Config ----
# Matches the gst-launch pipeline the user provided:
WIDTH = 1280
HEIGHT = 720
FPS_NUM = 30
FPS_DEN = 1
YOLO_SIZE = 640  # inference resize (tweak for perf/accuracy)
MODEL_NAME = 'yolo11n'  # yolo11 variants: yolo11n, yolo11s, yolo11m, yolo11l, yolo11x

# Inference params
MODEL_CONF = 0.25
MODEL_IOU = 0.45

# Load model once before pipeline
model_path = MODEL_NAME if MODEL_NAME.endswith('.pt') else MODEL_NAME + '.pt'
print(f"Loading model {model_path} ...")
model = YOLO(model_path)  # downloads official weights automatically if needed

def on_new_sample(sink, appsrc):
    """
    appsink -> pull sample, convert to numpy BGR, run YOLO11, draw,
    then push to appsrc (which will be converted to I420 and encoded).
    """
    sample = sink.emit("pull-sample")
    if not sample:
        return Gst.FlowReturn.ERROR

    buffer = sample.get_buffer()
    caps = sample.get_caps()
    if not caps:
        return Gst.FlowReturn.ERROR

    struct = caps.get_structure(0)
    # Try to read width/height from caps (fallback to constants)
    try:
        width = struct.get_value('width') or WIDTH
        height = struct.get_value('height') or HEIGHT
    except Exception:
        width = WIDTH
        height = HEIGHT

    # Map incoming buffer for read
    success, map_info = buffer.map(Gst.MapFlags.READ)
    if not success:
        return Gst.FlowReturn.ERROR

    try:
        # Build HxWx3 uint8 numpy frame (BGR) — ensure appsink sends BGR
        frame = np.ndarray((height, width, 3), buffer=map_info.data, dtype=np.uint8).copy()

        # ---- YOLO11 Inference ----
        # Ultralytics expects RGB images for best compatibility
        img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # choose device automatically
        device = 'cuda' if torch.cuda.is_available() else 'cpu'

        # run prediction (returns a list-like Results object)
        results = model.predict(source=img_rgb, imgsz=YOLO_SIZE, conf=MODEL_CONF, iou=MODEL_IOU, device=device)

        if len(results) == 0:
            boxes = np.empty((0, 4))
            confs = np.empty((0,))
            cls_ids = np.empty((0,), dtype=int)
        else:
            res = results[0]
            if hasattr(res, 'boxes') and len(res.boxes) > 0:
                # move to cpu and numpy
                boxes = res.boxes.xyxy.cpu().numpy()
                confs = res.boxes.conf.cpu().numpy()
                cls_ids = res.boxes.cls.cpu().numpy().astype(int)
            else:
                boxes = np.empty((0, 4))
                confs = np.empty((0,))
                cls_ids = np.empty((0,), dtype=int)

        # draw detections if any
        if len(boxes):
            for (x1, y1, x2, y2), conf, cid in zip(boxes, confs, cls_ids):
                x1, y1, x2, y2 = map(int, (x1, y1, x2, y2))
                label = model.names[int(cid)] if hasattr(model, 'names') else str(int(cid))
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                text = f"{label} {conf:.2f}"
                (w, h), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
                cv2.rectangle(frame, (x1, y1 - h - 4), (x1 + w, y1), (0, 255, 0), -1)
                cv2.putText(frame, text, (x1, y1 - 2), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1)

        # (Optional) red circle as before
        center = (width // 2, height // 2)
        cv2.circle(frame, center, 30, (255, 0, 0), thickness=3)

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
    ret = appsrc.emit("push-buffer", out_buffer)
    if ret != Gst.FlowReturn.OK:
        print("Warning: push-buffer returned", ret)
        return ret
    return Gst.FlowReturn.OK

def on_message(bus, message, loop):
    t = message.type
    if t == Gst.MessageType.EOS:
        print("End-Of-Stream")
        loop.quit()
    elif t == Gst.MessageType.ERROR:
        err, debug = message.parse_error()
        src_name = message.src.get_name() if message.src else "unknown"
        print(f"Error from {src_name}: {err} - {debug}")
        loop.quit()

def main():
    Gst.init(None)

    # Source pipeline: libcamerasrc -> videoflip rotate-180 -> videoconvert -> BGR -> appsink
    pipeline1_str = (
        f'libcamerasrc ! '
        f'video/x-raw,format=RGB,width={WIDTH},height={HEIGHT},framerate={FPS_NUM}/{FPS_DEN} ! '
        'videoflip method=rotate-180 ! '
        'videoconvert ! '
        f'video/x-raw,format=BGR,width={WIDTH},height={HEIGHT},framerate={FPS_NUM}/{FPS_DEN} ! '
        'appsink name=ai_sink emit-signals=true max-buffers=1 drop=true'
    )

    # Sender pipeline: appsrc (BGR) -> videoconvert -> I420 -> vp8enc -> webrtcsink
    pipeline2_str = (
        f'appsrc name=ai_src is-live=true block=true format=time caps=video/x-raw,format=BGR,width={WIDTH},height={HEIGHT},framerate={FPS_NUM}/{FPS_DEN} ! '
        'videoconvert ! '
        'video/x-raw,format=I420 ! '
        'queue ! '
        'vp8enc deadline=1 threads=2 ! '
        'queue ! '
        'webrtcsink name=ws signaller::uri="ws://0.0.0.0:8444" meta="meta,name=gst-stream"'
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

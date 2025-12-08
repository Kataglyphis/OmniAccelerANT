#!/usr/bin/env python3
import gi
import sys

import numpy as np
import cv2
gi.require_version('Gst', '1.0')
gi.require_version('GstWebRTC', '1.0')
from gi.repository import Gst, GObject, GLib

def on_new_sample(sink, appsrc):
    sample = sink.emit("pull-sample")
    if not sample:
        return Gst.FlowReturn.ERROR

    buffer = sample.get_buffer()
    caps = sample.get_caps()
    structure = caps.get_structure(0)
    width = structure.get_value('width')
    height = structure.get_value('height')

    # Buffer in numpy-Array umwandeln
    success, map_info = buffer.map(Gst.MapFlags.READ)
    if not success:
        return Gst.FlowReturn.ERROR

    try:
        # Annahme: RGB, 3 Kanäle
        frame = np.ndarray(
            (height, width, 3),
            buffer=map_info.data,
            dtype=np.uint8
        ).copy()  # copy, da map_info.data readonly ist

        # Einfachen roten Kreis in die Mitte zeichnen
        center = (width // 2, height // 2)
        cv2.circle(frame, center, 50, (255, 0, 0), thickness=5)  # Rot, Dicke 5

        # Neues Gst.Buffer aus dem bearbeiteten Frame erstellen
        out_buffer = Gst.Buffer.new_allocate(None, frame.nbytes, None)
        out_buffer.fill(0, frame.tobytes())
        out_buffer.pts = buffer.pts
        out_buffer.dts = buffer.dts
        out_buffer.duration = buffer.duration

    finally:
        buffer.unmap(map_info)

    # Buffer an appsrc weitergeben
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
        'v4l2src device=/dev/video0 ! '
        'image/jpeg,width=640,height=360,framerate=30/1 ! '
        'jpegdec ! '
        'videoconvert ! '
        'video/x-raw,format=RGB,width=640,height=360,framerate=30/1 ! '
        'appsink name=ai_sink emit-signals=true max-buffers=1 drop=true'
    )

    # Pipeline 2: appsrc -> webrtcsink
    pipeline2_str = (
        'appsrc name=ai_src is-live=true block=true format=time caps=video/x-raw,format=RGB,width=640,height=360,framerate=30/1 ! '
        'videoconvert ! '
        'webrtcsink name=ws meta="meta,name=ipa364webfrontend-webfrontend-stream"'
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
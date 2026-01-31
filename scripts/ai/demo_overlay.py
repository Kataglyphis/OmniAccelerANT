#!/usr/bin/env python3
"""
Python script to run a GStreamer pipeline with a properly configured cairooverlay.
Ensures the video feed retains color and adds a simple overlay.
"""

import sys
import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstWebRTC", "1.0")
from gi.repository import GObject, Gst


def draw_overlay(overlay, context, timestamp, duration):
    """
    Callback function for cairooverlay to draw on video frames.
    """
    # Set a red color (RGBA) and draw sample text
    context.set_source_rgba(1.0, 0.0, 0.0, 1.0)  # Red color with full opacity
    context.select_font_face("Sans", 0, 0)
    context.set_font_size(36)
    context.move_to(50, 50)
    context.show_text("Sample Overlay")
    context.stroke()


def on_message(bus, message, loop):
    """
    Handles GStreamer bus messages like EOS and ERROR.
    """
    msg_type = message.type
    if msg_type == Gst.MessageType.EOS:
        print("End-Of-Stream reached.")
        loop.quit()
    elif msg_type == Gst.MessageType.ERROR:
        err, debug = message.parse_error()
        print(f"Error: {err}, {debug}")
        loop.quit()
    return True


def main():
    # Initialize GObject and GStreamer
    GObject.threads_init()
    Gst.init(None)

    # Define the pipeline using gst-launch syntax
    launch_description = (
        'webrtcsink name=ws meta="meta,name=kataglyphiswebfrontend-webfrontend-stream" '
        "pylonsrc ! video/x-raw,format=RGB  ! videoconvert ! video/x-raw,format=BGRA ! "
        "cairooverlay name=overlay ! videoconvert ! video/x-raw,format=I420 ! ws. "
        "audiotestsrc ! ws."
    )

    # Parse the launch description into a Gst.Pipeline
    try:
        pipeline = Gst.parse_launch(launch_description)
    except Exception as e:
        print(f"Failed to create pipeline: {e}")
        sys.exit(1)

    # Get the cairooverlay element and attach the drawing callback
    overlay = pipeline.get_by_name("overlay")
    if not overlay:
        print("Failed to find cairooverlay element in the pipeline.")
        sys.exit(1)
    overlay.connect("draw", draw_overlay)

    # Create a GLib MainLoop
    loop = GObject.MainLoop()

    # Watch the pipeline's bus for messages
    bus = pipeline.get_bus()
    bus.add_signal_watch()
    bus.connect("message", on_message, loop)

    # Start playing the pipeline
    ret = pipeline.set_state(Gst.State.PLAYING)
    if ret == Gst.StateChangeReturn.FAILURE:
        print("Unable to set the pipeline to the playing state.")
        sys.exit(1)

    # Run the loop until an EOS or ERROR message is received
    try:
        print("Running pipeline... Press Ctrl+C to stop.")
        loop.run()
    except KeyboardInterrupt:
        print("Interrupted by user, stopping pipeline...")
    finally:
        # Clean up
        pipeline.set_state(Gst.State.NULL)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Python script to run a GStreamer pipeline equivalent to:

    gst-launch-1.0 -e \
      webrtcsink name=ws meta="meta,name=ipa364webfrontend-webfrontend-stream" \
      pylonsrc ! videoconvert ! ws. \
      audiotestsrc ! ws.

This script initializes GStreamer, sets up the pipeline, and manages the GLib MainLoop
"""

import sys
import gi

gi.require_version('Gst', '1.0')
gi.require_version('GstWebRTC', '1.0')
from gi.repository import GObject, Gst


def on_message(bus, message, loop):
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
        'webrtcsink name=ws '
        'meta="meta,name=ipa364webfrontend-webfrontend-stream" '
        'pylonsrc ! videoconvert ! ws. '
        'audiotestsrc ! ws.'
    )

    # Parse the launch description into a Gst.Pipeline
    try:
        pipeline = Gst.parse_launch(launch_description)
    except Exception as e:
        print(f"Failed to create pipeline: {e}")
        sys.exit(1)

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


if __name__ == '__main__':
    main()
#!/bin/bash

# Create a new tmux session called 'webrtc-setup'
tmux new-session -d -s webrtc-setup

# Rename the first window
tmux rename-window -t webrtc-setup:0 'webrtc'

# In the first pane, source bashrc, navigate to the signalling directory and run the server
tmux send-keys -t webrtc-setup:0.0 'source ~/.bashrc' Enter
tmux send-keys -t webrtc-setup:0.0 'cd /home/bigjuicyjones/gst-plugins-rs/net/webrtc/signalling' Enter
tmux send-keys -t webrtc-setup:0.0 'WEBRTCSINK_SIGNALLING_SERVER_LOG=debug cargo run --bin gst-webrtc-signalling-server' Enter

# Split the window horizontally to create a second pane
tmux split-window -h -t webrtc-setup:0

# Wait a moment for the server to start, then source bashrc and run gst-launch in the second pane
tmux send-keys -t webrtc-setup:0.1 'sleep 5' Enter
tmux send-keys -t webrtc-setup:0.1 'source ~/.bashrc' Enter
tmux send-keys -t webrtc-setup:0.1 'gst-launch-1.0 \
  libcamerasrc ! video/x-raw,width=1280,height=720,format=NV12,interlace-mode=progressive ! \
  x264enc speed-preset=1 threads=1 byte-stream=true ! \
  h264parse ! \
  webrtcsink signaller::uri="ws://0.0.0.0:8443" name=ws meta="meta,name=gst-stream"' Enter

# Split the second pane vertically to create a third pane
tmux split-window -v -t webrtc-setup:0.1

# Wait a moment, then source bashrc and run the serve command in the third pane
tmux send-keys -t webrtc-setup:0.2 'sleep 6' Enter
tmux send-keys -t webrtc-setup:0.2 'source ~/.bashrc' Enter
tmux send-keys -t webrtc-setup:0.2 'serve -s dist -l 5173' Enter

# Attach to the session
tmux attach-session -t webrtc-setup

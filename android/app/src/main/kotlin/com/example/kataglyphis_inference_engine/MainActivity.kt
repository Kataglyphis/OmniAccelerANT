package com.example.kataglyphis_inference_engine

import io.flutter.embedding.android.FlutterActivity
import org.freedesktop.gstreamer.GStreamer

import android.os.Bundle
import android.util.Log

class MainActivity: FlutterActivity()

class MainActivity: FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    GStreamer.init(this);
  }
}
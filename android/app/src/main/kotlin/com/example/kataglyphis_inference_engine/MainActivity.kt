package com.example.kataglyphis_inference_engine

import io.flutter.embedding.android.FlutterActivity

import android.os.Bundle
import android.util.Log

import org.freedesktop.gstreamer.GStreamer

class MainActivity: FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    GStreamer.init(this);
  }
}

/**class MainActivity : FlutterActivity()*/

package com.example.kataglyphis_native_inference

import android.content.Context
import android.util.Log
import android.view.Surface
import io.flutter.view.TextureRegistry

internal class GStreamerController(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
) {

    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var nativeInitialized = false

    companion object {
        private const val TAG = "GStreamerController"
    }

    fun createTexture(width: Int, height: Int): Long {
        ensureNativeReady()
        releaseSurface()

        val entry = textureRegistry.createSurfaceTexture()
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        val targetSurface = Surface(entry.surfaceTexture())

        val created = GStreamerNative.create(targetSurface, width, height)
        if (!created) {
            entry.release()
            targetSurface.release()
            throw IllegalStateException("Native GStreamer create() returned false")
        }

        textureEntry = entry
        surface = targetSurface
        return entry.id()
    }

    fun setPipeline(pipeline: String) {
        ensureNativeReady()
        val success = GStreamerNative.setPipeline(pipeline)
        if (!success) throw IllegalStateException("setPipeline failed")
    }

    fun play() {
        ensureNativeReady()
        if (!GStreamerNative.play()) throw IllegalStateException("play failed")
    }

    fun pause() {
        ensureNativeReady()
        if (!GStreamerNative.pause()) throw IllegalStateException("pause failed")
    }

    fun stop() {
        if (!nativeInitialized) return
        if (!GStreamerNative.stop()) throw IllegalStateException("stop failed")
    }

    fun setColor(r: Int, g: Int, b: Int) {
        ensureNativeReady()
        if (!GStreamerNative.setColor(r, g, b)) throw IllegalStateException("setColor failed")
    }

    fun dispose() {
        runCatching {
            if (nativeInitialized) {
                GStreamerNative.stop()
                GStreamerNative.dispose()
            }
        }
        nativeInitialized = false
        releaseSurface()
    }

    private fun ensureNativeReady() {
        if (nativeInitialized) return
        GStreamerNative.ensureLoaded()
        
        // Initialize GStreamer via the Java helper class first.
        // This sets up the application context and class loader required by
        // the androidmedia plugin to access Android camera APIs.
        try {
            org.freedesktop.gstreamer.GStreamer.init(context.applicationContext)
            Log.i(TAG, "GStreamer.init() completed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "GStreamer.init() failed: ${e.message}", e)
            // Continue anyway - the native init might still work for basic functionality
        }
        
        GStreamerNative.init(context.applicationContext)
        nativeInitialized = true
    }

    private fun releaseSurface() {
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
    }
}

internal object GStreamerNative {
    private const val LIB_NAME = "kataglyphis_native_inference"
    private val loadResult = kotlin.runCatching { System.loadLibrary(LIB_NAME) }

    fun ensureLoaded() {
        loadResult.getOrThrow()
    }

    external fun init(context: Context)
    external fun create(surface: Surface, width: Int, height: Int): Boolean
    external fun setPipeline(pipeline: String): Boolean
    external fun getLastError(): String
    external fun diagnose(): String
    external fun play(): Boolean
    external fun pause(): Boolean
    external fun stop(): Boolean
    external fun setColor(r: Int, g: Int, b: Int): Boolean
    external fun dispose()
}

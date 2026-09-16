package com.example.kataglyphis_native_inference

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** KataglyphisNativeInferencePlugin */
class KataglyphisNativeInferencePlugin :
    FlutterPlugin,
    MethodCallHandler {

    private var channel: MethodChannel? = null
    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var gstreamerController: GStreamerController? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = flutterPluginBinding
        gstreamerController = GStreamerController(
            context = flutterPluginBinding.applicationContext,
            textureRegistry = flutterPluginBinding.textureRegistry,
        )

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "kataglyphis_native_inference")
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "create" -> handleCreate(call, result)
            "setPipeline" -> handleSetPipeline(call, result)
            "diagnose" -> handleDiagnose(result)
            "play" -> handleNoArgCommand(result, "play") { controller -> controller.play() }
            "pause" -> handleNoArgCommand(result, "pause") { controller -> controller.pause() }
            "stop" -> handleNoArgCommand(result, "stop") { controller -> controller.stop() }
            "setColor" -> handleSetColor(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null

        gstreamerController?.dispose()
        gstreamerController = null
        pluginBinding = null
    }

    private fun handleCreate(call: MethodCall, result: Result) {
        val controller = gstreamerController ?: run {
            result.error("no_controller", "Plugin binding is unavailable", null)
            return
        }

        val args = call.arguments as? List<*>
        val width = args?.getOrNull(0) as? Number
        val height = args?.getOrNull(1) as? Number
        if (width == null || height == null) {
            result.error("bad_args", "Expected [width, height] numeric arguments", null)
            return
        }

        runCatching {
            controller.createTexture(width.toInt(), height.toInt())
        }.onSuccess { textureId ->
            result.success(textureId)
        }.onFailure { throwable ->
            Log.e("KataglyphisGStreamer", "Create failed", throwable)
            result.error("create_failed", throwable.message, null)
        }
    }

    private fun handleSetPipeline(call: MethodCall, result: Result) {
        val pipeline = call.arguments as? String
        if (pipeline.isNullOrBlank()) {
            result.error("bad_args", "Pipeline string must not be empty", null)
            return
        }

        val controller = gstreamerController ?: run {
            result.error("no_controller", "Plugin binding is unavailable", null)
            return
        }

        runCatching { controller.setPipeline(pipeline) }
            .onSuccess { result.success(null) }
            .onFailure { throwable ->
                Log.e("KataglyphisGStreamer", "setPipeline failed for: $pipeline", throwable)

                val nativeDetails = runCatching { GStreamerNative.getLastError() }.getOrNull()
                val details = listOfNotNull(throwable.message, nativeDetails)
                    .joinToString("\n")
                    .ifBlank { "setPipeline failed" }
                result.error(
                    "command_failed",
                    details,
                    null,
                )
            }
    }

    private fun handleDiagnose(result: Result) {
        runCatching {
            GStreamerNative.diagnose()
        }.onSuccess { report ->
            result.success(report)
        }.onFailure { throwable ->
            Log.e("KataglyphisGStreamer", "diagnose failed", throwable)
            result.error("command_failed", throwable.message, null)
        }
    }

    private fun handleSetColor(call: MethodCall, result: Result) {
        val args = call.arguments as? List<*>
        val r = args?.getOrNull(0) as? Number
        val g = args?.getOrNull(1) as? Number
        val b = args?.getOrNull(2) as? Number
        if (r == null || g == null || b == null) {
            result.error("bad_args", "Expected [r, g, b] numeric arguments", null)
            return
        }

        handleNoArgCommand(result, "setColor") { controller ->
            controller.setColor(r.toInt(), g.toInt(), b.toInt())
        }
    }

    private inline fun handleNoArgCommand(
        result: Result,
        command: String,
        crossinline block: (GStreamerController) -> Unit,
    ) {
        val controller = gstreamerController ?: run {
            result.error("no_controller", "Plugin binding is unavailable", null)
            return
        }

        runCatching { block(controller) }
            .onSuccess { result.success(null) }
            .onFailure { throwable ->
                Log.e("KataglyphisGStreamer", "$command failed", throwable)

                // Same shape as handleSetPipeline above, and for the same
                // reason. The throwable's message is a constant from
                // GStreamerController ("play failed"), while the useful half —
                // the bus error the native side drained into g_last_error — is
                // only reachable through getLastError(). Reporting the
                // throwable alone put "Pipeline error: play failed" on screen
                // and left the cause in logcat. The code stays
                // "command_failed": stream_page.dart keys its source-fallback
                // chain on exactly that string.
                val nativeDetails = runCatching { GStreamerNative.getLastError() }.getOrNull()
                val details = listOfNotNull(throwable.message, nativeDetails)
                    .joinToString("\n")
                    .ifBlank { "$command failed" }
                result.error(
                    "command_failed",
                    details,
                    null,
                )
            }
    }
}

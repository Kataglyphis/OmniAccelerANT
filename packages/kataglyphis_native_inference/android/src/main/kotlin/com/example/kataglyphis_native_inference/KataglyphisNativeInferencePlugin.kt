package com.example.kataglyphis_native_inference

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** KataglyphisNativeInferencePlugin */
class KataglyphisNativeInferencePlugin :
    FlutterPlugin,
    MethodCallHandler {

    private var channel: MethodChannel? = null
    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var gstreamerController: GStreamerController? = null

    // State changes wait up to 20 s for the camera: an ANR on the platform thread. One thread keeps their order.
    private var commands: ExecutorService? = null
    private val platformThread = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = flutterPluginBinding
        commands = Executors.newSingleThreadExecutor { task -> Thread(task, "kataglyphis-gstreamer") }
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

        // What waits in the queue would run on a disposed controller; the dispose below waits for the one that runs.
        commands?.shutdownNow()
        commands = null
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

        runCommand(result, "setPipeline") { controller ->
            controller.setPipeline(pipeline)
            null
        }
    }

    private fun handleDiagnose(result: Result) {
        runCommand(result, "diagnose") { GStreamerNative.diagnose() }
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

    private fun handleNoArgCommand(
        result: Result,
        command: String,
        block: (GStreamerController) -> Unit,
    ) {
        runCommand(result, command) { controller ->
            block(controller)
            null
        }
    }

    /** Runs [block] on the command thread and answers with its value on the platform thread, where a result must be given. */
    private fun runCommand(
        result: Result,
        command: String,
        block: (GStreamerController) -> Any?,
    ) {
        val controller = gstreamerController
        val queue = commands
        if (controller == null || queue == null) {
            result.error("no_controller", "Plugin binding is unavailable", null)
            return
        }

        queue.execute {
            val outcome = runCatching { block(controller) }
            val failure = outcome.exceptionOrNull()?.let { throwable ->
                Log.e("KataglyphisGStreamer", "$command failed", throwable)

                // The bus error lives only in getLastError(); stream_page.dart's fallback keys on "command_failed".
                val nativeDetails = runCatching { GStreamerNative.getLastError() }.getOrNull()
                listOfNotNull(throwable.message, nativeDetails)
                    .joinToString("\n")
                    .ifBlank { "$command failed" }
            }
            platformThread.post {
                if (failure == null) {
                    result.success(outcome.getOrNull())
                } else {
                    result.error("command_failed", failure, null)
                }
            }
        }
    }
}

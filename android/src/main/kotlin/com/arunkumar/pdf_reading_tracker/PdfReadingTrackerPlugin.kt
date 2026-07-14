package com.arunkumar.pdf_reading_tracker

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * PdfReadingTrackerPlugin
 *
 * Registers the MethodChannel and routes calls to [DndManager]. No DND
 * business logic lives here.
 *
 * **Final Reader-integration pass:** the `disableDnd` case now reads an
 * optional integer `"filter"` argument and forwards it to
 * [DndManager.disableDnd] as the exact interruption filter to restore.
 * The method name and every other case are unchanged — this is purely an
 * additional, optional argument read via `call.argument`.
 */
class PdfReadingTrackerPlugin :
    FlutterPlugin,
    MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var dndManager: DndManager

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "pdf_reading_tracker",
        )
        channel.setMethodCallHandler(this)

        dndManager = DndManager(flutterPluginBinding.applicationContext)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "isSupported" -> result.success(dndManager.isSupported())
            "isPermissionGranted" -> result.success(dndManager.isPermissionGranted())
            "openPermissionSettings" -> {
                dndManager.openPermissionSettings()
                result.success(null)
            }
            "enableDnd" -> {
                dndManager.enableDnd()
                result.success(null)
            }

            "disableDnd" -> {
                val filter = call.argument<Int>("filter")
                dndManager.disableDnd(filter)
                result.success(null)
            }
            "getCurrentInterruptionFilter" -> {
                result.success(dndManager.getCurrentInterruptionFilter())
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
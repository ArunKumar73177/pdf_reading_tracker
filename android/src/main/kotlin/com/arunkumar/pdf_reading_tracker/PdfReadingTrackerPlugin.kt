package com.arunkumar.pdf_reading_tracker

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * PdfReadingTrackerPlugin
 *
 * Phase 1 responsibility ONLY:
 * - Register the MethodChannel.
 * - Receive method calls from Dart.
 * - Forward them to [DndManager].
 *
 * No Do Not Disturb business logic lives here. All real implementation
 * (permission checks, NotificationManager calls, interruption-filter
 * reads/writes) belongs in [DndManager] and is intentionally left as
 * TODO stubs there until Phase 2.
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
                dndManager.disableDnd()
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
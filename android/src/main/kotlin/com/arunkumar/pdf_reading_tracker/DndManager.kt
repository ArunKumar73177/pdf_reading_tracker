package com.arunkumar.pdf_reading_tracker

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/**
 * DndManager
 *
 * Owns all Android Do Not Disturb business logic, backed by
 * [NotificationManager]. [PdfReadingTrackerPlugin] only routes
 * MethodChannel calls here; no DND logic lives in the plugin class.
 *
 * [context] is the application context (see
 * [PdfReadingTrackerPlugin.onAttachedToEngine]), so it's safe to hold for
 * the plugin's lifetime without leaking an Activity. Because it's an
 * application context, launching the permission-settings screen requires
 * [Intent.FLAG_ACTIVITY_NEW_TASK].
 */
class DndManager(private val context: Context) {

    private val notificationManager: NotificationManager
        get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /**
     * Whether this Android version exposes a usable DND API.
     * The interruption-filter APIs were added in API 23 (M); the plugin's
     * minSdk is 24, so this is always true today, but the check is kept
     * explicit rather than hardcoded in case minSdk is ever lowered.
     */
    fun isSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
    }

    /**
     * Whether the user has granted Notification Policy Access.
     * Returns false (not a crash) on API levels below M, where the
     * concept doesn't exist.
     */
    fun isPermissionGranted(): Boolean {
        if (!isSupported()) return false
        return notificationManager.isNotificationPolicyAccessGranted
    }

    /**
     * Opens the system settings screen where the user grants Notification
     * Policy Access. This is the ONLY place permission is requested —
     * [enableDnd] never triggers this itself.
     */
    fun openPermissionSettings() {
        if (!isSupported()) return
        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // No matching settings screen on this device/ROM. Safe no-op —
            // the caller can re-check isPermissionGranted() afterward.
        }
    }

    /**
     * Turns Do Not Disturb on. If permission has not been granted, this
     * safely returns without doing anything and without requesting
     * permission — permission is only ever requested via
     * [openPermissionSettings].
     */
    fun enableDnd() {
        if (!isPermissionGranted()) return
        try {
            notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
        } catch (_: SecurityException) {
            // Permission was revoked between the check above and this
            // call. Fail safely rather than crashing the host app.
        }
    }

    /**
     * Turns Do Not Disturb off. Same safe-no-op behavior as [enableDnd]
     * when permission isn't granted.
     */
    fun disableDnd() {
        if (!isPermissionGranted()) return
        try {
            notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
        } catch (_: SecurityException) {
            // See enableDnd().
        }
    }

    /**
     * Returns the current system interruption filter. Reading this does
     * NOT require Notification Policy Access, so no permission guard is
     * needed here. Returns INTERRUPTION_FILTER_UNKNOWN (0) if the
     * platform can't determine it, or if this API level doesn't support
     * it at all.
     */
    fun getCurrentInterruptionFilter(): Int {
        if (!isSupported()) return NotificationManager.INTERRUPTION_FILTER_UNKNOWN
        return notificationManager.currentInterruptionFilter
    }
}
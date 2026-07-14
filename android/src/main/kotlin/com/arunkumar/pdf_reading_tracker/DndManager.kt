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
     * Turns Do Not Disturb off.
     *
     * **Final Reader-integration pass:** now accepts an optional
     * [restoreFilter] — the exact [NotificationManager] interruption
     * filter constant that was in effect before Dart's
     * `ReadingSettingsController` called [enableDnd]. When it names a
     * genuine, settable filter value ([NotificationManager.INTERRUPTION_FILTER_ALL],
     * `_PRIORITY`, `_ALARMS`, or `_NONE`), that exact value is restored —
     * this is what "restore exactly what existed before enabling DND"
     * means in practice, rather than always forcing
     * [NotificationManager.INTERRUPTION_FILTER_ALL].
     *
     * [restoreFilter] is optional and defaults to `null` so this remains
     * fully backward compatible with any existing caller that invokes
     * `disableDnd` with no arguments — that path still falls back to
     * [NotificationManager.INTERRUPTION_FILTER_ALL], exactly as before.
     * The MethodChannel method name is unchanged; this is purely an
     * additional, optional argument.
     */
    fun disableDnd(restoreFilter: Int? = null) {
        if (!isPermissionGranted()) return
        val target = when (restoreFilter) {
            NotificationManager.INTERRUPTION_FILTER_ALL,
            NotificationManager.INTERRUPTION_FILTER_PRIORITY,
            NotificationManager.INTERRUPTION_FILTER_ALARMS,
            NotificationManager.INTERRUPTION_FILTER_NONE -> restoreFilter
            // Unknown / not provided (including INTERRUPTION_FILTER_UNKNOWN,
            // which isn't a settable target) — fall back to the same safe
            // default this method always used.
            else -> NotificationManager.INTERRUPTION_FILTER_ALL
        }
        try {
            notificationManager.setInterruptionFilter(target)
        } catch (_: SecurityException) {
            // Permission was revoked between the check above and this
            // call (or while the reader was open). Fail safely rather
            // than crashing the host app.
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
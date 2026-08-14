package com.voicemailreader.voice_mail_reader

import android.app.Notification
import android.content.Context
import android.service.notification.StatusBarNotification
import notification.listener.service.NotificationListener
import org.json.JSONArray
import org.json.JSONObject

/**
 * System notification listener that persists every incoming notification to
 * app-private storage (a small JSON journal) before forwarding it to the
 * foreground Flutter engine via the plugin's event stream.
 *
 * Why this exists: the [notification_listener_service] plugin only forwards
 * notifications to the app while the Flutter engine is running. Android keeps
 * this service bound (and restarts it as needed) whenever notification access
 * is granted — even when the app UI is closed or the process was killed.
 * Writing to the journal here means no message is ever lost: when the app
 * opens again, the journal is replayed and merged into the queue.
 *
 * The journal is plaintext app-private storage by design: it only holds raw
 * events that arrived while the app was closed, it is consumed and cleared on
 * the next app launch, and the durable queue itself lives in encrypted
 * storage (see NotificationService).
 */
class NotificationPersistenceListener : NotificationListener() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        journalAppend(
            event = "posted",
            sbn = sbn,
        )
        // Keep the plugin's live behavior (broadcast -> Dart event stream).
        super.onNotificationPosted(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        journalAppend(
            event = "removed",
            sbn = sbn,
        )
        super.onNotificationRemoved(sbn)
    }

    private fun journalAppend(event: String, sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras
                .getCharSequence(Notification.EXTRA_TITLE)
                ?.toString()
                ?.take(MAX_TITLE_LENGTH)
                .orEmpty()
            val text = extras
                .getCharSequence(Notification.EXTRA_TEXT)
                ?.toString()
                ?.take(MAX_TEXT_LENGTH)
                .orEmpty()
            val isOngoing =
                (sbn.notification.flags and Notification.FLAG_ONGOING_EVENT) != 0

            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_EVENTS, null)
            val array = if (raw.isNullOrEmpty()) JSONArray() else JSONArray(raw)

            array.put(
                JSONObject()
                    .put("event", event)
                    .put("id", sbn.id)
                    .put("packageName", sbn.packageName)
                    .put("title", title)
                    .put("text", text)
                    .put("time", sbn.postTime)
                    .put("ongoing", isOngoing),
            )

            // Keep the journal bounded; entries older than the cap are dropped.
            while (array.length() > MAX_JOURNAL_EVENTS) {
                array.remove(0)
            }

            prefs.edit().putString(KEY_EVENTS, array.toString()).apply()
        } catch (e: Exception) {
            // Never let journal persistence break notification delivery.
        }
    }

    private companion object {
        const val PREFS_NAME = "pending_journal"
        const val KEY_EVENTS = "events"
        const val MAX_JOURNAL_EVENTS = 300
        const val MAX_TITLE_LENGTH = 200
        const val MAX_TEXT_LENGTH = 1000
    }
}

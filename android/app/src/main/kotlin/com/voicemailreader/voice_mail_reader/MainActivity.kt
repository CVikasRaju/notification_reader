package com.voicemailreader.voice_mail_reader

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

/**
 * Main activity. Exposes a small method channel that lets Dart consume the
 * pending-notification journal written by [NotificationPersistenceListener]
 * while the app was closed.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            when (call.method) {
                "getPendingEvents" -> {
                    val raw = prefs.getString(KEY_EVENTS, null)
                    val events: List<Any> =
                        if (raw.isNullOrEmpty()) {
                            emptyList()
                        } else {
                            val array = JSONArray(raw)
                            (0 until array.length()).map { array.get(it) as Map<*, *> }
                        }
                    result.success(events)
                }
                "clearPendingEvents" -> {
                    prefs.edit().remove(KEY_EVENTS).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val CHANNEL_NAME = "voice_mail_reader/pending"
        const val PREFS_NAME = "pending_journal"
        const val KEY_EVENTS = "events"
    }
}

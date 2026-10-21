package com.novu.HabitFlow

import android.content.Intent
import android.os.Bundle
import androidx.work.Configuration
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    // Action from a widget tap ("pro", "habit:<id>", "mood:<n>", …) waiting
    // for the Dart side to pick it up.
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            WorkManager.initialize(applicationContext, Configuration.Builder().build())
        } catch (_: Exception) {
            // Never crash the app because of WorkManager setup.
        }
        // Ignore the extra when the activity is recreated (rotation, process
        // restore) so an old widget tap is not replayed.
        if (savedInstanceState == null) {
            pendingAction = intent?.getStringExtra(WidgetUi.EXTRA_ACTION)
        }
        intent?.removeExtra(WidgetUi.EXTRA_ACTION)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = intent.getStringExtra(WidgetUi.EXTRA_ACTION) ?: return
        pendingAction = action
        // App already running: tell Dart right away.
        channel?.invokeMethod("widgetAction", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.novu.HabitFlow/widget"
        ).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        (call.argument<Boolean>("pro"))?.let { pro -> WidgetData.setAppPro(this, pro) }
                        WidgetUi.refreshAll(applicationContext)
                        result.success(null)
                    }
                    "takeAction" -> {
                        result.success(pendingAction)
                        pendingAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}

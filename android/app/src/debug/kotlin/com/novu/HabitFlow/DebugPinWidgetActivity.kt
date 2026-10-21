package com.novu.HabitFlow

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Bundle

// DEBUG BUILDS ONLY (src/debug). Lets testers pin a widget from adb:
//   adb shell am start -n com.novu.HabitFlow/.DebugPinWidgetActivity --es provider ProgressRingWidget
class DebugPinWidgetActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val name = intent.getStringExtra("provider") ?: "HabitWidgetProvider"
        val manager = AppWidgetManager.getInstance(this)
        if (manager.isRequestPinAppWidgetSupported) {
            manager.requestPinAppWidget(ComponentName(this, "$packageName.$name"), null, null)
        }
        finish()
    }
}

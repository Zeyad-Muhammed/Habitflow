package com.novu.HabitFlow

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Handles the ✔ taps from widgets and the midnight / clock-change refreshes.
class WidgetToggleReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_TOGGLE = "com.novu.HabitFlow.TOGGLE_HABIT"
        const val ACTION_MIDNIGHT = "com.novu.HabitFlow.WIDGET_MIDNIGHT"
        const val EXTRA_HABIT_ID = "habitId"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val habitId = intent.getStringExtra(EXTRA_HABIT_ID) ?: return
            if (WidgetData.toggleToday(context, habitId) == ToggleResult.NEEDS_APP) {
                // Measurable / timer habits are logged in the app.
                WidgetUi.openApp(context, "habit:$habitId").send()
            }
        }
        // Toggle, midnight, time/timezone change, boot or app update.
        WidgetUi.refreshAll(context)
    }
}

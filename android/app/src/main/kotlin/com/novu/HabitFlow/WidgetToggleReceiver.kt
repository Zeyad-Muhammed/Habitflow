package com.novu.HabitFlow

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.appwidget.AppWidgetManager

// Handles taps from widget rows: flips today's completion for the
// habit, then re-renders every HabitFlow widget.

class WidgetToggleReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WidgetData.ACTION_TOGGLE) return
        val habitId = intent.getStringExtra(WidgetData.EXTRA_HABIT_ID) ?: return
        val widgetId = intent.getIntExtra(WidgetData.EXTRA_WIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)

        val ok = WidgetData.toggleToday(context, habitId)
        if (!ok) {
            // Measurable / quit habits need the app (amount entry / relapse log).
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }

        HabitWidgetProvider.refreshAll(context)
        HabitSingleWidgetProvider.refreshAll(context)
    }
}

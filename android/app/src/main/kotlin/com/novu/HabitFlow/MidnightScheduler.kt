package com.novu.HabitFlow

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.LocalDate
import java.time.ZoneId

// Re-renders the widgets just after midnight so "today" rolls over even if
// the app is never opened. Inexact alarm: no special permission needed.
object MidnightScheduler {
    fun schedule(context: Context) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val next = LocalDate.now().plusDays(1).atStartOfDay(ZoneId.systemDefault())
                .toInstant().toEpochMilli() + 60_000L
            val pi = PendingIntent.getBroadcast(
                context, 7001,
                Intent(context, WidgetToggleReceiver::class.java)
                    .setAction(WidgetToggleReceiver.ACTION_MIDNIGHT),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.setAndAllowWhileIdle(AlarmManager.RTC, next, pi)
        } catch (_: Exception) {
        }
    }
}

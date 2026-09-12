package com.zeyad.habit_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class HabitWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.habit_widget_layout)

        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val raw = prefs.getString("flutter.habits", null)

        val openIntent = Intent(context, MainActivity::class.java)
        val openPi = PendingIntent.getActivity(
            context, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widgetRoot, openPi)

        val rowsIds = intArrayOf(
            R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4
        )
        val habitIds = intArrayOf(
            R.id.habit0, R.id.habit1, R.id.habit2, R.id.habit3, R.id.habit4
        )
        val doneIds = intArrayOf(
            R.id.done0, R.id.done1, R.id.done2, R.id.done3, R.id.done4
        )

        try {
            val arr = JSONArray(raw ?: "[]")
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                .format(Date(System.currentTimeMillis()))

            var doneToday = 0
            val shown = minOf(arr.length(), 5)
            for (i in 0 until shown) {
                val obj: JSONObject = arr.getJSONObject(i)
                val name = obj.optString("name", "Habit")
                val target = obj.optDouble("target", 0.0)
                val isMeasurable = target > 0
                val isQuit = obj.optBoolean("isQuit", false)

                val done = if (isMeasurable) {
                    val amounts = obj.optJSONObject("amounts") ?: JSONObject()
                    amounts.optDouble(today, 0.0) >= target
                } else {
                    val dates = obj.optJSONArray("dates") ?: JSONArray()
                    indexOf(dates, today)
                }

                if (done) doneToday++

                views.setViewVisibility(rowsIds[i], android.view.View.VISIBLE)
                views.setTextViewText(habitIds[i], (if (isQuit) "🚭 " else "") + name)
                views.setTextViewText(doneIds[i], if (done) "✔" else "•")
                views.setTextColor(
                    doneIds[i],
                    if (done) 0xFF4CD964.toInt() else 0xFF555B66.toInt()
                )
                views.setInt(dotIds[i], "setBackgroundResource",
                    if (done) R.drawable.widget_dot_done else R.drawable.widget_dot)
            }

            for (i in shown until 5) {
                views.setViewVisibility(rowsIds[i], android.view.View.GONE)
            }

            val percent = if (arr.length() > 0) {
                (doneToday * 100 / arr.length()).coerceIn(0, 100)
            } else 0
            views.setProgressBar(R.id.widgetProgress, 100, percent, false)
            views.setTextViewText(R.id.widgetPercent, "$percent%")
            views.setViewVisibility(
                R.id.emptyText,
                if (arr.length() == 0) android.view.View.VISIBLE else android.view.View.GONE
            )
        } catch (_: Exception) {
            views.setTextViewText(R.id.widgetPercent, "—")
        }
        return views
    }

    private val dotIds = intArrayOf(
        R.id.dot0, R.id.dot1, R.id.dot2, R.id.dot3, R.id.dot4
    )

    private fun indexOf(dates: JSONArray, value: String): Boolean {
        var i = 0
        while (i < dates.length()) {
            if (dates.optString(i) == value) return true
            i++
        }
        return false
    }
}
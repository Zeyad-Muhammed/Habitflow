package com.novu.HabitFlow

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

// Widget for a single habit. Size-adaptive:
//   small square  -> mini dot grid (4x7)
//   wide & short  -> week check circles (7 days)
//   big square    -> month heatmap grid (10x7)
// The habit is chosen in HabitConfigActivity at placement time and
// stored under key "widget_habit_<appWidgetId>".

class HabitSingleWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // Defensive: only touch widgets actually bound to THIS provider —
        // implicit APPWIDGET_UPDATE broadcasts can arrive with foreign ids.
        val mine = AppWidgetManager.getInstance(context).getAppWidgetIds(
            ComponentName(context, HabitSingleWidgetProvider::class.java)
        ).toSet()
        for (id in appWidgetIds) {
            if (mine.contains(id)) {
                appWidgetManager.updateAppWidget(id, buildViews(context, appWidgetManager, id))
            }
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        val mine = AppWidgetManager.getInstance(context).getAppWidgetIds(
            ComponentName(context, HabitSingleWidgetProvider::class.java)
        )
        if (mine.contains(appWidgetId)) {
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetManager, appWidgetId))
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = WidgetData.prefs(context)
        for (id in appWidgetIds) prefs.edit().remove("widget_habit_$id").apply()
    }

    companion object {
        fun habitIdFor(context: Context, widgetId: Int): String? {
            val prefs = WidgetData.prefs(context)
            val chosen = prefs.getString("widget_habit_$widgetId", null)
            if (chosen != null) {
                val exists = WidgetData.habits(prefs).any { it.id == chosen }
                if (exists) return chosen
            }
            return WidgetData.habits(prefs).firstOrNull()?.id
        }

        fun pickLayout(manager: AppWidgetManager, id: Int): Int {
            val opts = manager.getAppWidgetOptions(id)
            val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
            val minH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
            return when {
                minW >= 200 && minH <= 132 -> R.layout.widget_single_week
                minW >= 250 && minH >= 240 -> R.layout.widget_single_heat
                else -> R.layout.widget_single_mini
            }
        }

        fun buildViews(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
            android.util.Log.d("HFWIDGET", "SingleProvider.buildViews id=$widgetId")
            val prefs = WidgetData.prefs(context)
            val lang = WidgetData.lang(prefs)
            val layout = pickLayout(manager, widgetId)
            val views = RemoteViews(context.packageName, layout)

            val habits = WidgetData.habits(prefs)
            val chosenId = habitIdFor(context, widgetId)
            val habit = habits.firstOrNull { it.id == chosenId } ?: habits.firstOrNull()

            val openIntent = Intent(context, MainActivity::class.java)
            val openPi = PendingIntent.getActivity(
                context, widgetId, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widgetRoot, openPi)

            if (habit == null) {
                views.setTextViewText(R.id.sName, WidgetData.t(lang, "أضف عادة أولاً", "Add a habit first"))
                views.setViewVisibility(R.id.sStreak, View.GONE)
                return views
            }

            val today = today()
            val accent = WidgetData.accentFor(habit.id)
            val s = habit.streak(today)
            val doneNow = habit.done(today)

            // Tap = toggle (simple habits) or open app (measurable / quit).
            if (!habit.measurable && !habit.isQuit) {
                val intent = Intent(context, WidgetToggleReceiver::class.java)
                    .setAction(WidgetData.ACTION_TOGGLE)
                    .putExtra(WidgetData.EXTRA_HABIT_ID, habit.id)
                    .putExtra(WidgetData.EXTRA_WIDGET_ID, widgetId)
                val pi = PendingIntent.getBroadcast(
                    context, widgetId, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.sTap, pi)
            }

            when (layout) {
                R.layout.widget_single_week -> fillWeek(context, views, habit, accent, today, lang)
                R.layout.widget_single_heat -> fillHeat(context, views, habit, accent, today, lang)
                else -> fillMini(context, views, habit, accent, doneNow, s, today)
            }
            return views
        }

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val me = ComponentName(context, HabitSingleWidgetProvider::class.java)
            HabitSingleWidgetProvider().onUpdate(context, manager, manager.getAppWidgetIds(me))
        }

        private fun dp(context: Context, v: Int): Int =
            (v * context.resources.displayMetrics.density).toInt().coerceAtLeast(1)

        // ------------------------------------------------------------
        // Week circles (7 days, today highlighted)
        // ------------------------------------------------------------
        private fun fillWeek(
            context: Context,
            views: RemoteViews,
            habit: HabitInfo,
            accent: Int,
            today: String,
            lang: String
        ) {
            views.setTextViewText(R.id.sName, WidgetData.habitLabel(habit))
            views.setViewVisibility(R.id.sStreak, View.VISIBLE)
            views.setTextViewText(R.id.sStreak, "🔥 ${habit.streak(today)}")

            val freqLabel = when {
                habit.frequency == 1 && habit.weekdays.isNotEmpty() && habit.weekdays.size < 7 ->
                    habit.weekdays.sorted().joinToString(" ") { wd ->
                        // Dart weekday Mon=1..Sun=7 -> letter index: Sun=0, else wd
                        val ar = arrayOf("س", "أ", "ا", "ث", "ر", "خ", "ج")
                        val en = arrayOf("S", "M", "T", "W", "T", "F", "S")
                        val idx = if (wd == 7) 0 else wd
                        (if (lang == "en") en else ar)[idx]
                    }
                habit.frequency == 2 -> WidgetData.t(
                    lang,
                    "${habit.timesPerWeek} مرة/أسبوع",
                    "${habit.timesPerWeek}x per week"
                )
                else -> WidgetData.t(lang, "كل يوم", "Everyday")
            }
            views.setTextViewText(R.id.sFreq, freqLabel)

            val circles = intArrayOf(
                R.id.wc0, R.id.wc1, R.id.wc2, R.id.wc3, R.id.wc4, R.id.wc5, R.id.wc6
            )
            val letters = intArrayOf(
                R.id.wl0, R.id.wl1, R.id.wl2, R.id.wl3, R.id.wl4, R.id.wl5, R.id.wl6
            )
            // RTL-friendly: oldest at left … today at right end of the row.
            for (c in 0 until 7) {
                val d = daysAgo(today, 6 - c)
                views.setTextViewText(letters[c], dayLetter(d, lang))
                val isToday = d == today
                val st = when {
                    habit.done(d) -> 3 // filled + check
                    isToday -> 2       // ring on today
                    else -> 0          // dim hole
                }
                val size = dp(context, 30)
                views.setImageViewBitmap(circles[c], WidgetData.dotBitmap(size, accent, st))
            }
        }

        // ------------------------------------------------------------
        // Mini dot grid (4 rows x 7 cols = last 28 days)
        // ------------------------------------------------------------
        private fun fillMini(
            context: Context,
            views: RemoteViews,
            habit: HabitInfo,
            accent: Int,
            doneNow: Boolean,
            streak: Int,
            today: String
        ) {
            views.setTextViewText(R.id.sName, WidgetData.habitLabel(habit))
            views.setViewVisibility(R.id.sStreak, View.VISIBLE)
            views.setTextViewText(R.id.sStreak, "🔥 $streak")
            views.setImageViewBitmap(
                R.id.sCheck,
                WidgetData.dotBitmap(dp(context, 26), accent, if (doneNow) 3 else 2)
            )
            for (r in 0 until 4) {
                for (c in 0 until 7) {
                    val idx = r * 7 + c
                    val d = daysAgo(today, 27 - idx)
                    val st = if (habit.done(d)) 1 else 0
                    views.setImageViewBitmap(
                        miniDotIds[r][c], WidgetData.dotBitmap(dp(context, 12), accent, st)
                    )
                }
            }
        }

        private val miniDotIds = arrayOf(
            intArrayOf(R.id.sg0_0, R.id.sg0_1, R.id.sg0_2, R.id.sg0_3, R.id.sg0_4, R.id.sg0_5, R.id.sg0_6),
            intArrayOf(R.id.sg1_0, R.id.sg1_1, R.id.sg1_2, R.id.sg1_3, R.id.sg1_4, R.id.sg1_5, R.id.sg1_6),
            intArrayOf(R.id.sg2_0, R.id.sg2_1, R.id.sg2_2, R.id.sg2_3, R.id.sg2_4, R.id.sg2_5, R.id.sg2_6),
            intArrayOf(R.id.sg3_0, R.id.sg3_1, R.id.sg3_2, R.id.sg3_3, R.id.sg3_4, R.id.sg3_5, R.id.sg3_6)
        )

        // ------------------------------------------------------------
        // Big heatmap (7 rows x 10 cols = last 70 days)
        // ------------------------------------------------------------
        private fun fillHeat(
            context: Context,
            views: RemoteViews,
            habit: HabitInfo,
            accent: Int,
            today: String,
            lang: String
        ) {
            views.setTextViewText(R.id.sName, WidgetData.habitLabel(habit))
            views.setViewVisibility(R.id.sStreak, View.VISIBLE)
            views.setTextViewText(R.id.sStreak, "🔥 ${habit.streak(today)}")
            views.setImageViewBitmap(
                R.id.sCheck,
                WidgetData.dotBitmap(dp(context, 26), accent, if (habit.done(today)) 3 else 2)
            )
            for (r in 0 until 7) {
                for (c in 0 until 10) {
                    val idx = r * 10 + c
                    val d = daysAgo(today, 69 - idx)
                    val st = if (habit.done(d)) 1 else 0
                    views.setImageViewBitmap(
                        heatDotIds[r][c], WidgetData.dotBitmap(dp(context, 12), accent, st)
                    )
                }
            }
        }

        private val heatDotIds = arrayOf(
            intArrayOf(R.id.hm0_0, R.id.hm0_1, R.id.hm0_2, R.id.hm0_3, R.id.hm0_4, R.id.hm0_5, R.id.hm0_6, R.id.hm0_7, R.id.hm0_8, R.id.hm0_9),
            intArrayOf(R.id.hm1_0, R.id.hm1_1, R.id.hm1_2, R.id.hm1_3, R.id.hm1_4, R.id.hm1_5, R.id.hm1_6, R.id.hm1_7, R.id.hm1_8, R.id.hm1_9),
            intArrayOf(R.id.hm2_0, R.id.hm2_1, R.id.hm2_2, R.id.hm2_3, R.id.hm2_4, R.id.hm2_5, R.id.hm2_6, R.id.hm2_7, R.id.hm2_8, R.id.hm2_9),
            intArrayOf(R.id.hm3_0, R.id.hm3_1, R.id.hm3_2, R.id.hm3_3, R.id.hm3_4, R.id.hm3_5, R.id.hm3_6, R.id.hm3_7, R.id.hm3_8, R.id.hm3_9),
            intArrayOf(R.id.hm4_0, R.id.hm4_1, R.id.hm4_2, R.id.hm4_3, R.id.hm4_4, R.id.hm4_5, R.id.hm4_6, R.id.hm4_7, R.id.hm4_8, R.id.hm4_9),
            intArrayOf(R.id.hm5_0, R.id.hm5_1, R.id.hm5_2, R.id.hm5_3, R.id.hm5_4, R.id.hm5_5, R.id.hm5_6, R.id.hm5_7, R.id.hm5_8, R.id.hm5_9),
            intArrayOf(R.id.hm6_0, R.id.hm6_1, R.id.hm6_2, R.id.hm6_3, R.id.hm6_4, R.id.hm6_5, R.id.hm6_6, R.id.hm6_7, R.id.hm6_8, R.id.hm6_9)
        )
    }
}

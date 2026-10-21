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

class HabitWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val mine = AppWidgetManager.getInstance(context).getAppWidgetIds(
            ComponentName(context, HabitWidgetProvider::class.java)
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
            ComponentName(context, HabitWidgetProvider::class.java)
        )
        if (mine.contains(appWidgetId)) {
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetManager, appWidgetId))
        }
    }

    companion object {
        // ------------------------------------------------------------
        // Layout picking by current widget size (dp).
        // tiny = mini | short-wide = heatmap | short-narrow = streak
        // card | tall = today list.
        // ------------------------------------------------------------
        fun pickLayout(manager: AppWidgetManager, id: Int): Int {
            val opts = manager.getAppWidgetOptions(id)
            val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            val minH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
            return when {
                minH <= 112 || minW < 200 -> R.layout.widget_layout_mini
                minH <= 155 -> if (minW >= 300) R.layout.widget_layout_heatmap else R.layout.widget_layout_streak
                else -> R.layout.habit_widget_layout
            }
        }

        // Rows that actually fit the widget height (dp): header ≈ 93dp,
        // row ≈ 40dp including its 5dp margin.
        fun todayRows(manager: AppWidgetManager, id: Int): Int {
            val minH = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
            return (((minH - 93) / 40f).toInt()).coerceIn(1, 8)
        }

        fun buildViews(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
            android.util.Log.d("HFWIDGET", "ListProvider.buildViews id=$widgetId")
            val prefs = WidgetData.prefs(context)
            val lang = WidgetData.lang(prefs)
            val layout = pickLayout(manager, widgetId)
            val views = RemoteViews(context.packageName, layout)

            val openIntent = Intent(context, MainActivity::class.java)
            val openPi = PendingIntent.getActivity(
                context, 0, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widgetRoot, openPi)

            val today = today()
            val habits = WidgetData.habits(prefs)
            val doneToday = habits.count { it.done(today) }
            val percent = if (habits.isEmpty()) 0 else doneToday * 100 / habits.size
            val bestStreak = if (habits.isEmpty()) 0 else habits.maxOf { it.streak(today) }

            when (layout) {
                R.layout.widget_layout_mini ->
                    fillMini(context, views, habits, percent, bestStreak, today, lang)
                R.layout.widget_layout_streak -> {
                    val xp = WidgetData.readXp(prefs)
                    val level = WidgetData.levelForXp(xp)
                    val xpInLevel = xp - WidgetData.totalForLevel(level)
                    val xpToNext = WidgetData.xpForLevel(level)
                    fillStreak(views, habits, percent, bestStreak, level, xpInLevel, xpToNext, lang)
                }
                R.layout.widget_layout_heatmap ->
                    fillHeatmap(context, views, habits, percent, bestStreak, today, lang)
                else ->
                    fillToday(
                        context, views, widgetId, habits, doneToday, percent, bestStreak,
                        today, lang, todayRows(manager, widgetId)
                    )
            }
            return views
        }

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val me = ComponentName(context, HabitWidgetProvider::class.java)
            HabitWidgetProvider().onUpdate(context, manager, manager.getAppWidgetIds(me))
        }

        // ------------------------------------------------------------
        // Today list
        // ------------------------------------------------------------
        private fun fillToday(
            context: Context,
            views: RemoteViews,
            widgetId: Int,
            habits: List<HabitInfo>,
            doneToday: Int,
            percent: Int,
            bestStreak: Int,
            today: String,
            lang: String,
            maxRows: Int
        ) {
            views.setTextViewText(R.id.widgetTitle, WidgetData.t(lang, "اليوم", "Today"))
            views.setTextViewText(R.id.widgetStreak, "🔥 $bestStreak")
            views.setTextViewText(R.id.widgetPercent, "$percent%")
            views.setTextViewText(R.id.widgetDoneCount, "$doneToday/${habits.size}")
            views.setProgressBar(R.id.widgetProgress, 100, percent, false)

            for (r in 0 until 8) {
                val rowId = rowIds[r]
                if (r < habits.size && r < maxRows) {
                    val h = habits[r]
                    views.setViewVisibility(rowId, View.VISIBLE)
                    views.setTextViewText(nameIds[r], WidgetData.habitLabel(h))
                    val s = h.streak(today)
                    views.setTextViewText(flameIds[r], if (s > 0) "🔥 $s" else "")
                    views.setTextViewText(doneIds[r], if (h.done(today)) "✔" else "")
                    val accent = WidgetData.accentFor(h.id)
                    views.setImageViewBitmap(
                        dotIds[r], WidgetData.dotBitmap(dp(context, 16), accent, 1)
                    )
                    for (c in 0 until 7) {
                        val d = daysAgo(today, 6 - c)
                        val st = if (h.done(d)) 1 else 0
                        views.setImageViewBitmap(
                            stripIds[r][c], WidgetData.dotBitmap(dp(context, 10), accent, st)
                        )
                    }
                    views.setOnClickPendingIntent(rowId, togglePi(context, widgetId, h.id, r))
                } else {
                    views.setViewVisibility(rowId, View.GONE)
                }
            }
            views.setViewVisibility(
                R.id.emptyText,
                if (habits.isEmpty()) View.VISIBLE else View.GONE
            )
        }

        private fun togglePi(
            context: Context,
            widgetId: Int,
            habitId: String,
            requestCode: Int
        ): PendingIntent {
            val intent = Intent(context, WidgetToggleReceiver::class.java)
                .setAction(WidgetData.ACTION_TOGGLE)
                .putExtra(WidgetData.EXTRA_HABIT_ID, habitId)
                .putExtra(WidgetData.EXTRA_WIDGET_ID, widgetId)
            return PendingIntent.getBroadcast(
                context,
                widgetId * 100 + requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun dp(context: Context, v: Int): Int =
            (v * context.resources.displayMetrics.density).toInt().coerceAtLeast(1)

        private val rowIds = arrayOf(
            R.id.row0, R.id.row1, R.id.row2, R.id.row3,
            R.id.row4, R.id.row5, R.id.row6, R.id.row7
        )
        private val dotIds = arrayOf(
            R.id.rd0, R.id.rd1, R.id.rd2, R.id.rd3,
            R.id.rd4, R.id.rd5, R.id.rd6, R.id.rd7
        )
        private val nameIds = arrayOf(
            R.id.habit0, R.id.habit1, R.id.habit2, R.id.habit3,
            R.id.habit4, R.id.habit5, R.id.habit6, R.id.habit7
        )
        private val flameIds = arrayOf(
            R.id.flame0, R.id.flame1, R.id.flame2, R.id.flame3,
            R.id.flame4, R.id.flame5, R.id.flame6, R.id.flame7
        )
        private val doneIds = arrayOf(
            R.id.done0, R.id.done1, R.id.done2, R.id.done3,
            R.id.done4, R.id.done5, R.id.done6, R.id.done7
        )
        private val stripIds = arrayOf(
            intArrayOf(R.id.sd0_0, R.id.sd0_1, R.id.sd0_2, R.id.sd0_3, R.id.sd0_4, R.id.sd0_5, R.id.sd0_6),
            intArrayOf(R.id.sd1_0, R.id.sd1_1, R.id.sd1_2, R.id.sd1_3, R.id.sd1_4, R.id.sd1_5, R.id.sd1_6),
            intArrayOf(R.id.sd2_0, R.id.sd2_1, R.id.sd2_2, R.id.sd2_3, R.id.sd2_4, R.id.sd2_5, R.id.sd2_6),
            intArrayOf(R.id.sd3_0, R.id.sd3_1, R.id.sd3_2, R.id.sd3_3, R.id.sd3_4, R.id.sd3_5, R.id.sd3_6),
            intArrayOf(R.id.sd4_0, R.id.sd4_1, R.id.sd4_2, R.id.sd4_3, R.id.sd4_4, R.id.sd4_5, R.id.sd4_6),
            intArrayOf(R.id.sd5_0, R.id.sd5_1, R.id.sd5_2, R.id.sd5_3, R.id.sd5_4, R.id.sd5_5, R.id.sd5_6),
            intArrayOf(R.id.sd6_0, R.id.sd6_1, R.id.sd6_2, R.id.sd6_3, R.id.sd6_4, R.id.sd6_5, R.id.sd6_6),
            intArrayOf(R.id.sd7_0, R.id.sd7_1, R.id.sd7_2, R.id.sd7_3, R.id.sd7_4, R.id.sd7_5, R.id.sd7_6)
        )

        // ------------------------------------------------------------
        // Mini strip
        // ------------------------------------------------------------
        private fun fillMini(
            context: Context,
            views: RemoteViews,
            habits: List<HabitInfo>,
            percent: Int,
            bestStreak: Int,
            today: String,
            lang: String
        ) {
            views.setTextViewText(R.id.miniPercent, "$percent%")
            views.setTextViewText(R.id.miniStreak, "🔥 $bestStreak")
            views.setTextViewText(
                R.id.miniHint,
                WidgetData.t(lang, "أضف عادتك الأولى ✨", "Add your first habit ✨")
            )
            val dots = intArrayOf(
                R.id.miniDot0, R.id.miniDot1, R.id.miniDot2, R.id.miniDot3, R.id.miniDot4
            )
            for (i in dots.indices) {
                if (i < habits.size) {
                    val h = habits[i]
                    views.setViewVisibility(dots[i], View.VISIBLE)
                    val st = if (h.done(today)) 1 else 0
                    views.setImageViewBitmap(
                        dots[i], WidgetData.dotBitmap(dp(context, 12), WidgetData.accentFor(h.id), st)
                    )
                } else {
                    views.setViewVisibility(dots[i], View.GONE)
                }
            }
            views.setViewVisibility(R.id.miniHint, if (habits.isEmpty()) View.VISIBLE else View.GONE)
        }

        // ------------------------------------------------------------
        // Streak & level card
        // ------------------------------------------------------------
        private fun fillStreak(
            views: RemoteViews,
            habits: List<HabitInfo>,
            percent: Int,
            bestStreak: Int,
            level: Int,
            xpInLevel: Int,
            xpToNext: Int,
            lang: String
        ) {
            views.setTextViewText(R.id.stkValue, "$bestStreak")
            views.setTextViewText(R.id.stkLabel, WidgetData.t(lang, "أفضل سلسلة", "Best streak"))
            views.setTextViewText(R.id.stkPercent, "$percent%")
            views.setTextViewText(R.id.stkLevel, WidgetData.t(lang, "المستوى $level", "Level $level"))
            views.setTextViewText(R.id.stkXp, "$xpInLevel/$xpToNext XP")
            val prog = if (xpToNext > 0) (xpInLevel * 100 / xpToNext).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.stkProgress, 100, prog, false)
            views.setViewVisibility(
                R.id.stkEmpty,
                if (habits.isEmpty()) View.VISIBLE else View.GONE
            )
        }

        // ------------------------------------------------------------
        // Last-7-days heatmap
        // ------------------------------------------------------------
        private fun fillHeatmap(
            context: Context,
            views: RemoteViews,
            habits: List<HabitInfo>,
            percent: Int,
            bestStreak: Int,
            today: String,
            lang: String
        ) {
            views.setTextViewText(R.id.heatTitle, WidgetData.t(lang, "آخر 7 أيام", "Last 7 days"))
            views.setTextViewText(R.id.heatStreak, "🔥 $bestStreak")
            views.setTextViewText(R.id.heatPercent, "$percent%")
            views.setTextViewText(
                R.id.heatEmpty,
                WidgetData.t(lang, "لا توجد عادات بعد — افتح التطبيق لبدء رحلتك 🎯", "No habits yet - open the app to start your journey 🎯")
            )

            val dayIds = intArrayOf(
                R.id.heatDay0, R.id.heatDay1, R.id.heatDay2,
                R.id.heatDay3, R.id.heatDay4, R.id.heatDay5, R.id.heatDay6
            )
            // Rightmost column = today (RTL), oldest at the far left.
            for (c in 0 until 7) {
                views.setTextViewText(dayIds[c], dayLetter(daysAgo(today, c), lang))
            }

            val rows = intArrayOf(R.id.heatRow0, R.id.heatRow1, R.id.heatRow2, R.id.heatRow3, R.id.heatRow4)
            val names = intArrayOf(R.id.heatName0, R.id.heatName1, R.id.heatName2, R.id.heatName3, R.id.heatName4)
            for (r in rows.indices) {
                if (r < habits.size) {
                    val h = habits[r]
                    views.setViewVisibility(rows[r], View.VISIBLE)
                    views.setTextViewText(names[r], WidgetData.habitLabel(h))
                    for (c in 0 until 7) {
                        val d = daysAgo(today, c)
                        val st = if (h.done(d)) 1 else 0
                        views.setImageViewBitmap(
                            heatDotIds[r][c],
                            WidgetData.dotBitmap(dp(context, 14), WidgetData.accentFor(h.id), st)
                        )
                    }
                } else {
                    views.setViewVisibility(rows[r], View.GONE)
                }
            }
            views.setViewVisibility(
                R.id.heatEmpty,
                if (habits.isEmpty()) View.VISIBLE else View.GONE
            )
        }

        private val heatDotIds = arrayOf(
            intArrayOf(R.id.heatDot0_0, R.id.heatDot0_1, R.id.heatDot0_2, R.id.heatDot0_3, R.id.heatDot0_4, R.id.heatDot0_5, R.id.heatDot0_6),
            intArrayOf(R.id.heatDot1_0, R.id.heatDot1_1, R.id.heatDot1_2, R.id.heatDot1_3, R.id.heatDot1_4, R.id.heatDot1_5, R.id.heatDot1_6),
            intArrayOf(R.id.heatDot2_0, R.id.heatDot2_1, R.id.heatDot2_2, R.id.heatDot2_3, R.id.heatDot2_4, R.id.heatDot2_5, R.id.heatDot2_6),
            intArrayOf(R.id.heatDot3_0, R.id.heatDot3_1, R.id.heatDot3_2, R.id.heatDot3_3, R.id.heatDot3_4, R.id.heatDot3_5, R.id.heatDot3_6),
            intArrayOf(R.id.heatDot4_0, R.id.heatDot4_1, R.id.heatDot4_2, R.id.heatDot4_3, R.id.heatDot4_4, R.id.heatDot4_5, R.id.heatDot4_6)
        )
    }
}

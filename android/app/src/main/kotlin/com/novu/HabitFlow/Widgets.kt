package com.novu.HabitFlow

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import kotlin.math.roundToInt

/** Common update plumbing; a bad render never takes the launcher down. */
abstract class BaseWidget : AppWidgetProvider() {
    abstract fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews

    open val proOnly = false

    private fun render(context: Context, manager: AppWidgetManager, id: Int) {
        try {
            val views = if (proOnly && !WidgetData.isPro(context)) WidgetUi.lockedViews(context)
            else build(context, manager, id)
            manager.updateAppWidget(id, views)
        } catch (e: Exception) {
            Log.e("HabitFlowWidget", "render failed for ${javaClass.simpleName}", e)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) render(context, manager, id)
        MidnightScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context, manager, id)
    }

    protected fun base(context: Context, layout: Int, th: WidgetTheme): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        WidgetUi.direction(context, v, R.id.w_root)
        v.setInt(R.id.w_root, "setBackgroundResource", th.bgRes)
        return v
    }
}

// ---------------------------------------------------------------------------
// 1) Today list (4x2, free). Class name kept from the old widget so widgets
//    already on users' home screens keep working after the update.
// ---------------------------------------------------------------------------
class HabitWidgetProvider : BaseWidget() {
    private val rowIds = intArrayOf(R.id.w_row0, R.id.w_row1, R.id.w_row2, R.id.w_row3, R.id.w_row4, R.id.w_row5)
    private val avIds = intArrayOf(R.id.w_av0, R.id.w_av1, R.id.w_av2, R.id.w_av3, R.id.w_av4, R.id.w_av5)
    private val nameIds = intArrayOf(R.id.w_name0, R.id.w_name1, R.id.w_name2, R.id.w_name3, R.id.w_name4, R.id.w_name5)
    private val metaIds = intArrayOf(R.id.w_meta0, R.id.w_meta1, R.id.w_meta2, R.id.w_meta3, R.id.w_meta4, R.id.w_meta5)
    private val chkIds = intArrayOf(R.id.w_chk0, R.id.w_chk1, R.id.w_chk2, R.id.w_chk3, R.id.w_chk4, R.id.w_chk5)

    override fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val th = WidgetUi.theme(context)
        val v = base(context, R.layout.w_today, th)
        val (wDp, hDp) = WidgetUi.sizeDp(manager, id, 250, 110)
        val today = WidgetData.today()
        val due = WidgetData.dueToday(context)
        val done = due.count { it.isDone(today) }
        // Unfinished first, so the next thing to do is always visible.
        val ordered = due.sortedBy { if (it.isDone(today)) 1 else 0 }

        v.setTextViewText(R.id.w_title, WidgetData.t(context, "عادات اليوم", "Today"))
        v.setTextColor(R.id.w_title, th.text)
        v.setTextViewText(
            R.id.w_count,
            WidgetData.t(context, "$done من ${due.size}", "$done of ${due.size}")
        )
        v.setTextColor(R.id.w_count, th.accent)
        val frac = if (due.isEmpty()) 0f else done.toFloat() / due.size
        v.setImageViewBitmap(
            R.id.w_bar,
            WidgetUi.barBitmap(context, th, frac, (wDp - 24).toFloat(), WidgetData.isAr(context))
        )

        // Header ~44dp, each row 44dp.
        val capacity = ((hDp - 44) / 44).coerceIn(1, rowIds.size)
        val shown = ordered.take(capacity)
        for (i in rowIds.indices) {
            if (i >= shown.size) {
                v.setViewVisibility(rowIds[i], View.GONE)
                continue
            }
            val h = shown[i]
            val isDone = h.isDone(today)
            v.setViewVisibility(rowIds[i], View.VISIBLE)
            v.setInt(rowIds[i], "setBackgroundResource", th.chipRes)
            v.setImageViewBitmap(avIds[i], WidgetUi.avatarBitmap(context, th, h.name, isDone))
            v.setTextViewText(nameIds[i], h.name)
            v.setTextColor(nameIds[i], if (isDone) th.sub else th.text)
            val streak = h.currentStreak(today)
            val meta = when {
                h.measurable -> "${fmt(h.amountOn(today))}/${fmt(h.target)}"
                streak > 0 -> "🔥 $streak"
                else -> ""
            }
            v.setTextViewText(metaIds[i], meta)
            v.setTextColor(metaIds[i], th.sub)
            v.setViewVisibility(metaIds[i], if (meta.isEmpty()) View.GONE else View.VISIBLE)
            v.setImageViewBitmap(chkIds[i], WidgetUi.checkBitmap(context, th, isDone, h.needsApp && !isDone))
            v.setContentDescription(chkIds[i], h.name)
            // Measurable / timer habits open the app's log dialog or timer.
            v.setOnClickPendingIntent(
                chkIds[i],
                if (h.needsApp) WidgetUi.openApp(context, "habit:${h.id}") else WidgetUi.toggle(context, h.id)
            )
            v.setOnClickPendingIntent(rowIds[i], WidgetUi.openApp(context, "open"))
        }

        val empty = due.isEmpty()
        v.setViewVisibility(R.id.w_empty, if (empty) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.w_rows, if (empty) View.GONE else View.VISIBLE)
        v.setTextColor(R.id.w_empty, th.sub)
        v.setTextViewText(
            R.id.w_empty,
            if (WidgetData.habits(context).isEmpty())
                WidgetData.t(context, "أضف أول عادة من التطبيق", "Add your first habit in the app")
            else WidgetData.t(context, "مفيش عادات مطلوبة النهارده 🎉", "Nothing due today 🎉")
        )
        v.setOnClickPendingIntent(R.id.w_root, WidgetUi.openApp(context, "open"))
        return v
    }

    private fun fmt(d: Double) = if (d == Math.floor(d)) d.toLong().toString() else d.toString()
}

// ---------------------------------------------------------------------------
// 2) Single habit + streak (1x1 / 2x1, free). Configured via HabitConfigActivity.
// ---------------------------------------------------------------------------
class HabitSingleWidgetProvider : BaseWidget() {
    companion object {
        fun habitKey(id: Int) = "widget_habit_$id"
    }

    override fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val th = WidgetUi.theme(context)
        val (wDp, _) = WidgetUi.sizeDp(manager, id, 110, 40)
        val wide = wDp >= 100
        val v = base(context, if (wide) R.layout.w_single_wide else R.layout.w_single_small, th)
        val habitId = WidgetData.prefs(context).getString(habitKey(id), null)
        val h = WidgetData.habits(context).firstOrNull { it.id == habitId }
        val today = WidgetData.today()

        if (h == null) {
            // Habit deleted or not picked yet: tap to choose again.
            v.setTextViewText(R.id.w_name, WidgetData.t(context, "اختر عادة", "Pick a habit"))
            v.setTextColor(R.id.w_name, th.text)
            v.setTextViewText(R.id.w_streak, "")
            v.setImageViewBitmap(R.id.w_chk, WidgetUi.checkBitmap(context, th, false, true))
            if (wide) v.setImageViewBitmap(R.id.w_av, WidgetUi.avatarBitmap(context, th, "?", false))
            v.setOnClickPendingIntent(R.id.w_root, HabitConfigActivity.reconfigure(context, id))
            return v
        }

        val done = h.isDone(today)
        val streak = h.currentStreak(today)
        v.setTextViewText(R.id.w_name, h.name)
        v.setTextColor(R.id.w_name, if (wide) th.text else th.sub)
        v.setTextViewText(
            R.id.w_streak,
            if (wide) "🔥 ${WidgetData.daysLabel(context, streak)}" else "🔥 $streak"
        )
        v.setTextColor(R.id.w_streak, if (wide) th.sub else th.text)
        if (wide) v.setImageViewBitmap(R.id.w_av, WidgetUi.avatarBitmap(context, th, h.name, done))
        v.setImageViewBitmap(R.id.w_chk, WidgetUi.checkBitmap(context, th, done, h.needsApp && !done))
        v.setContentDescription(R.id.w_chk, h.name)
        v.setOnClickPendingIntent(
            R.id.w_chk,
            if (h.needsApp) WidgetUi.openApp(context, "habit:${h.id}") else WidgetUi.toggle(context, h.id)
        )
        v.setOnClickPendingIntent(R.id.w_root, WidgetUi.openApp(context, "open"))
        return v
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val e = WidgetData.prefs(context).edit()
        for (id in ids) e.remove(habitKey(id))
        e.apply()
    }
}

// ---------------------------------------------------------------------------
// 3) Today progress ring (2x2, free).
// ---------------------------------------------------------------------------
class ProgressRingWidget : BaseWidget() {
    override fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val th = WidgetUi.theme(context)
        val v = base(context, R.layout.w_ring, th)
        val today = WidgetData.today()
        val due = WidgetData.dueToday(context)
        val done = due.count { it.isDone(today) }
        val frac = if (due.isEmpty()) 0f else done.toFloat() / due.size
        val pct = (frac * 100).roundToInt()
        v.setTextViewText(R.id.w_title, WidgetData.t(context, "تقدّم اليوم", "Today"))
        v.setTextColor(R.id.w_title, th.sub)
        v.setImageViewBitmap(R.id.w_ring, WidgetUi.ringBitmap(context, th, frac, 92f))
        // "3/5" stays left-to-right in both languages.
        v.setTextViewText(R.id.w_count, "⁦$done/${due.size}⁩")
        v.setTextColor(R.id.w_count, th.text)
        v.setTextViewText(R.id.w_pct, "⁦$pct%⁩")
        v.setTextColor(R.id.w_pct, th.accent)
        val left = due.size - done
        v.setTextViewText(
            R.id.w_sub,
            when {
                due.isEmpty() -> WidgetData.t(context, "مفيش عادات النهارده", "Nothing due today")
                left == 0 -> WidgetData.t(context, "يوم مثالي! 🎉", "Perfect day! 🎉")
                else -> WidgetData.t(context, "باقي $left", "$left left")
            }
        )
        v.setTextColor(R.id.w_sub, th.sub)
        v.setOnClickPendingIntent(R.id.w_root, WidgetUi.openApp(context, "open"))
        return v
    }
}

// ---------------------------------------------------------------------------
// 4) Heatmap of the last 12 weeks across all habits (4x2, Pro).
// ---------------------------------------------------------------------------
class HeatmapWidget : BaseWidget() {
    override val proOnly = true

    override fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val th = WidgetUi.theme(context)
        val v = base(context, R.layout.w_heatmap, th)
        val (wDp, hDp) = WidgetUi.sizeDp(manager, id, 250, 110)
        val habits = WidgetData.habits(context)
        val today = WidgetData.today()
        val weeks = 12
        val start = HabitInfo.mondayOf(today).minusWeeks((weeks - 1).toLong())
        var active = 0
        var d = start
        while (!d.isAfter(today)) {
            val day = d
            if (habits.any { it.isDone(day) }) active++
            d = d.plusDays(1)
        }
        v.setTextViewText(R.id.w_title, WidgetData.t(context, "آخر 12 أسبوع", "Last 12 weeks"))
        v.setTextColor(R.id.w_title, th.text)
        v.setTextViewText(
            R.id.w_meta,
            WidgetData.t(
                context, "${WidgetData.daysLabel(context, active)} نشاط",
                if (active == 1) "1 active day" else "$active active days"
            )
        )
        v.setTextColor(R.id.w_meta, th.accent)
        val bmp = WidgetUi.heatmapBitmap(
            context, th, weeks, (wDp - 24).toFloat(), (hDp - 52).toFloat().coerceAtLeast(40f),
            WidgetData.isAr(context)
        ) { wk, dow ->
            val date = start.plusDays((wk * 7 + dow).toLong())
            if (date.isAfter(today)) return@heatmapBitmap -1f
            val due = habits.filter { it.isDue(date) }
            if (due.isEmpty()) 0f else due.count { it.isDone(date) }.toFloat() / due.size
        }
        v.setImageViewBitmap(R.id.w_grid, bmp)
        v.setOnClickPendingIntent(R.id.w_root, WidgetUi.openApp(context, "stats"))
        return v
    }
}

// ---------------------------------------------------------------------------
// 5) Level, XP and today's challenge (4x1, Pro).
// ---------------------------------------------------------------------------
class LevelWidget : BaseWidget() {
    override val proOnly = true

    override fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val th = WidgetUi.theme(context)
        val v = base(context, R.layout.w_level, th)
        val (wDp, _) = WidgetUi.sizeDp(manager, id, 250, 60)
        val xp = WidgetData.xp(context)
        val level = WidgetData.levelForXp(xp)
        val inLevel = xp - WidgetData.totalForLevel(level)
        val need = WidgetData.xpForLevel(level)
        val frac = inLevel.toFloat() / need
        v.setImageViewBitmap(R.id.w_ring, WidgetUi.ringBitmap(context, th, frac, 44f))
        v.setTextViewText(R.id.w_level, "$level")
        v.setTextColor(R.id.w_level, th.accent)
        v.setTextViewText(R.id.w_title, WidgetData.t(context, "المستوى $level", "Level $level"))
        v.setTextColor(R.id.w_title, th.text)
        v.setTextViewText(R.id.w_xp, "⁦$inLevel / $need XP⁩")
        v.setTextColor(R.id.w_xp, th.sub)
        v.setImageViewBitmap(
            R.id.w_bar,
            WidgetUi.barBitmap(context, th, frac, (wDp - 92).toFloat(), WidgetData.isAr(context))
        )
        val habits = WidgetData.habits(context)
        val ch = WidgetData.challenge(context, habits)
        val claimed = WidgetData.challengeClaimed(context)
        val target = maxOf(ch.target, 1)
        val prog = if (claimed) target else minOf(WidgetData.challengeProgress(habits, ch.id), target)
        val title = WidgetData.t(context, ch.titleAr, ch.titleEn)
        v.setTextViewText(
            R.id.w_chal,
            (if (claimed) "✅ " else "") + title + " · ⁦$prog/$target⁩"
        )
        v.setTextColor(R.id.w_chal, if (claimed) th.accent else th.sub)
        v.setOnClickPendingIntent(R.id.w_root, WidgetUi.openApp(context, "open"))
        return v
    }
}

// ---------------------------------------------------------------------------
// 6) Mood check-in + quote of the day (2x2, free).
// ---------------------------------------------------------------------------
class MoodQuoteWidget : BaseWidget() {
    private val faceIds = intArrayOf(R.id.w_m1, R.id.w_m2, R.id.w_m3, R.id.w_m4, R.id.w_m5)

    override fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val th = WidgetUi.theme(context)
        val v = base(context, R.layout.w_mood, th)
        v.setTextViewText(R.id.w_title, WidgetData.t(context, "حكمة اليوم", "Quote of the day"))
        v.setTextColor(R.id.w_title, th.accent)
        v.setTextViewText(R.id.w_quote, WidgetData.quote(context))
        v.setTextColor(R.id.w_quote, th.text)
        val mood = WidgetData.todayMood(context)
        v.setTextViewText(
            R.id.w_ask,
            if (mood == null) WidgetData.t(context, "كيف تشعر اليوم؟", "How do you feel today?")
            else WidgetData.t(context, "مزاجك النهارده", "Today's mood")
        )
        v.setTextColor(R.id.w_ask, th.sub)
        for (i in faceIds.indices) {
            val m = i + 1
            // The app saves the mood (and its XP) exactly like a tap on Home.
            v.setOnClickPendingIntent(faceIds[i], WidgetUi.openApp(context, "mood:$m"))
            if (mood == m) v.setInt(faceIds[i], "setBackgroundResource", th.chipOnRes)
            else v.setInt(faceIds[i], "setBackgroundResource", 0)
        }
        v.setOnClickPendingIntent(R.id.w_root, WidgetUi.openApp(context, "open"))
        return v
    }
}

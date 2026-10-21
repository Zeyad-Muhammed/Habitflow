package com.novu.HabitFlow

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

/** Colours matching the app's lavender/pink theme in dark and light mode. */
class WidgetTheme(val dark: Boolean) {
    val text = if (dark) 0xFFECEDF0.toInt() else 0xFF1B1B21.toInt()
    val sub = if (dark) 0xFF9AA0A6.toInt() else 0xFF6B7280.toInt()
    val track = if (dark) 0xFF2E343C.toInt() else 0xFFE6E3EE.toInt()
    val accent = if (dark) 0xFFCDBDFF.toInt() else 0xFF65558F.toInt()
    val accent2 = if (dark) 0xFFEFB8C8.toInt() else 0xFF7E5260.toInt()
    val onAccent = if (dark) 0xFF2B1F4A.toInt() else 0xFFFFFFFF.toInt()
    val bgRes = if (dark) R.drawable.w_bg_dark else R.drawable.w_bg_light
    val chipRes = if (dark) R.drawable.w_chip_dark else R.drawable.w_chip_light
    val chipOnRes = if (dark) R.drawable.w_chip_on_dark else R.drawable.w_chip_on_light
}

object WidgetUi {
    const val EXTRA_ACTION = "widget_action"

    fun theme(context: Context) = WidgetTheme(WidgetData.isDark(context))

    fun dp(context: Context, v: Float): Int =
        (v * context.resources.displayMetrics.density).toInt()

    /** Size of the widget in dp from the launcher's options (portrait). */
    fun sizeDp(manager: AppWidgetManager, id: Int, defW: Int, defH: Int): Pair<Int, Int> {
        val o: Bundle = manager.getAppWidgetOptions(id)
        val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, defW).takeIf { it > 0 } ?: defW
        val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, defH).takeIf { it > 0 } ?: defH
        return w to h
    }

    /** Applies RTL/LTR from the app language (not the device locale). */
    fun direction(context: Context, views: RemoteViews, rootId: Int) {
        views.setInt(
            rootId, "setLayoutDirection",
            if (WidgetData.isAr(context)) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        )
    }

    /** Opens the app; [action] is handled by HomePage (see _handleWidgetAction). */
    fun openApp(context: Context, action: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("habitflow://widget/$action"))
            .putExtra(EXTRA_ACTION, action)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, action.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun toggle(context: Context, habitId: String): PendingIntent {
        val intent = Intent(context, WidgetToggleReceiver::class.java)
            .setAction(WidgetToggleReceiver.ACTION_TOGGLE)
            .setData(Uri.parse("habitflow://toggle/$habitId"))
            .putExtra(WidgetToggleReceiver.EXTRA_HABIT_ID, habitId)
        return PendingIntent.getBroadcast(
            context, habitId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Re-renders every placed HabitFlow widget. */
    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (cls in PROVIDERS) {
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            val intent = Intent(context, cls)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
        }
        MidnightScheduler.schedule(context)
    }

    val PROVIDERS = listOf(
        HabitWidgetProvider::class.java,
        HabitSingleWidgetProvider::class.java,
        ProgressRingWidget::class.java,
        HeatmapWidget::class.java,
        LevelWidget::class.java,
        MoodQuoteWidget::class.java,
    )

    // ------------------------------------------------------------------
    // Bitmaps
    // ------------------------------------------------------------------

    /** Check button: outlined circle, or filled gradient circle with a tick. */
    fun checkBitmap(context: Context, th: WidgetTheme, done: Boolean, needsApp: Boolean): Bitmap {
        val s = dp(context, 30f)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = s / 2f
        if (done) {
            p.shader = LinearGradient(0f, 0f, s.toFloat(), s.toFloat(), th.accent, th.accent2, Shader.TileMode.CLAMP)
            c.drawCircle(r, r, r, p)
            p.shader = null
            p.color = th.onAccent
            p.style = Paint.Style.STROKE
            p.strokeWidth = s / 9f
            p.strokeCap = Paint.Cap.ROUND
            c.drawLine(s * 0.28f, s * 0.52f, s * 0.44f, s * 0.68f, p)
            c.drawLine(s * 0.44f, s * 0.68f, s * 0.73f, s * 0.35f, p)
        } else {
            p.style = Paint.Style.STROKE
            p.strokeWidth = s / 12f
            p.color = th.accent
            c.drawCircle(r, r, r - p.strokeWidth, p)
            if (needsApp) {
                // A "+" for habits logged in the app (amount / timer).
                p.strokeCap = Paint.Cap.ROUND
                c.drawLine(r, s * 0.32f, r, s * 0.68f, p)
                c.drawLine(s * 0.32f, r, s * 0.68f, r, p)
            }
        }
        return bmp
    }

    /** Rounded letter avatar standing in for the habit's icon. */
    fun avatarBitmap(context: Context, th: WidgetTheme, name: String, done: Boolean): Bitmap {
        val s = dp(context, 30f)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.color = if (done) th.track else (th.accent and 0x00FFFFFF) or 0x33000000
        c.drawRoundRect(RectF(0f, 0f, s.toFloat(), s.toFloat()), s * 0.3f, s * 0.3f, p)
        val trimmed = name.trim()
        val letter = if (trimmed.isEmpty()) "•" else
            trimmed.substring(0, trimmed.offsetByCodePoints(0, 1)).uppercase()
        p.color = if (done) th.sub else th.accent
        p.textSize = s * 0.5f
        p.typeface = Typeface.DEFAULT_BOLD
        p.textAlign = Paint.Align.CENTER
        val y = s / 2f - (p.descent() + p.ascent()) / 2f
        c.drawText(letter, s / 2f, y, p)
        return bmp
    }

    /** Progress ring with a gradient arc. */
    fun ringBitmap(context: Context, th: WidgetTheme, fraction: Float, sizeDp: Float): Bitmap {
        val s = dp(context, sizeDp)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val stroke = s * 0.11f
        val rect = RectF(stroke / 2 + 1, stroke / 2 + 1, s - stroke / 2 - 1, s - stroke / 2 - 1)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.style = Paint.Style.STROKE
        p.strokeWidth = stroke
        p.strokeCap = Paint.Cap.ROUND
        p.color = th.track
        c.drawArc(rect, 0f, 360f, false, p)
        val f = fraction.coerceIn(0f, 1f)
        if (f > 0f) {
            p.shader = LinearGradient(0f, 0f, s.toFloat(), s.toFloat(), th.accent, th.accent2, Shader.TileMode.CLAMP)
            c.drawArc(rect, -90f, 360f * f, false, p)
        }
        return bmp
    }

    /** Horizontal progress bar; fills from the start side for [rtl]. */
    fun barBitmap(context: Context, th: WidgetTheme, fraction: Float, widthDp: Float, rtl: Boolean): Bitmap {
        val w = dp(context, widthDp).coerceAtLeast(10)
        val h = dp(context, 8f)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = h / 2f
        p.color = th.track
        c.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), r, r, p)
        val f = fraction.coerceIn(0f, 1f)
        if (f > 0f) {
            val fw = (w * f).coerceAtLeast(h.toFloat())
            val rect = if (rtl) RectF(w - fw, 0f, w.toFloat(), h.toFloat()) else RectF(0f, 0f, fw, h.toFloat())
            p.shader = LinearGradient(rect.left, 0f, rect.right, 0f, th.accent, th.accent2, Shader.TileMode.CLAMP)
            c.drawRoundRect(rect, r, r, p)
        }
        return bmp
    }

    /**
     * Heatmap of the last [weeks] weeks: columns are weeks (newest at the
     * end side), rows Monday..Sunday. [value] returns -1 for future days,
     * otherwise 0..1 completion.
     */
    fun heatmapBitmap(
        context: Context, th: WidgetTheme, weeks: Int, widthDp: Float, heightDp: Float,
        rtl: Boolean, value: (week: Int, day: Int) -> Float,
    ): Bitmap {
        val w = dp(context, widthDp).coerceAtLeast(40)
        val h = dp(context, heightDp).coerceAtLeast(20)
        val gap = dp(context, 3f).toFloat()
        val cell = minOf((w - gap * (weeks - 1)) / weeks, (h - gap * 6) / 7)
        val gridW = cell * weeks + gap * (weeks - 1)
        val gridH = cell * 7 + gap * 6
        val ox = (w - gridW) / 2f
        val oy = (h - gridH) / 2f
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val rad = cell * 0.28f
        for (wk in 0 until weeks) {
            val col = if (rtl) weeks - 1 - wk else wk
            for (d in 0 until 7) {
                val v = value(wk, d)
                if (v < 0f) continue
                p.color = if (v <= 0f) th.track else blend(th.track, th.accent, 0.35f + 0.65f * v)
                val x = ox + col * (cell + gap)
                val y = oy + d * (cell + gap)
                c.drawRoundRect(RectF(x, y, x + cell, y + cell), rad, rad, p)
            }
        }
        return bmp
    }

    private fun blend(a: Int, b: Int, t: Float): Int {
        fun ch(x: Int, s: Int) = (x shr s) and 0xFF
        fun mix(s: Int) = (ch(a, s) + (ch(b, s) - ch(a, s)) * t).toInt().coerceIn(0, 255)
        return (0xFF shl 24) or (mix(16) shl 16) or (mix(8) shl 8) or mix(0)
    }

    /** Locked card for Pro widgets when the user is on the free plan. */
    fun lockedViews(context: Context): RemoteViews {
        val th = theme(context)
        val v = RemoteViews(context.packageName, R.layout.w_locked)
        direction(context, v, R.id.w_root)
        v.setInt(R.id.w_root, "setBackgroundResource", th.bgRes)
        v.setTextColor(R.id.w_title, th.text)
        v.setTextColor(R.id.w_sub, th.sub)
        v.setTextViewText(R.id.w_sub, WidgetData.t(context, "رقِّ إلى برو لفتح هذا الويدجت", "Upgrade to Pro to unlock this widget"))
        v.setInt(R.id.w_cta, "setBackgroundResource", th.chipOnRes)
        v.setTextColor(R.id.w_cta, th.onAccent)
        v.setTextViewText(R.id.w_cta, WidgetData.t(context, "رقِّ", "Upgrade"))
        v.setOnClickPendingIntent(R.id.w_root, openApp(context, "pro"))
        return v
    }
}

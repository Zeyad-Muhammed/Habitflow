package com.novu.HabitFlow

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

// Picker shown when a single-habit widget is placed (or reconfigured):
// lets the user choose which habit the widget tracks.
class HabitConfigActivity : Activity() {

    companion object {
        fun reconfigure(context: Context, appWidgetId: Int): PendingIntent {
            val intent = Intent(context, HabitConfigActivity::class.java)
                .setData(Uri.parse("habitflow://config/$appWidgetId"))
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(
                context, appWidgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        setResult(RESULT_CANCELED, result(appWidgetId))

        val th = WidgetUi.theme(this)
        val dark = th.dark
        val bg = if (dark) 0xFF161B22.toInt() else 0xFFF7F5FC.toInt()
        val card = if (dark) 0xFF1C2127.toInt() else 0xFFFFFFFF.toInt()
        fun d(v: Int) = WidgetUi.dp(this, v.toFloat())

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(d(20), d(48), d(20), d(20))
            setBackgroundColor(bg)
            layoutDirection = if (WidgetData.isAr(this@HabitConfigActivity))
                View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        }
        root.addView(TextView(this).apply {
            text = WidgetData.t(this@HabitConfigActivity, "اختر عادة للويدجت", "Pick a habit for this widget")
            setTextColor(th.text)
            textSize = 20f
            typeface = Typeface.DEFAULT_BOLD
            textAlignment = View.TEXT_ALIGNMENT_VIEW_START
        })

        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val scroll = ScrollView(this).apply { addView(list) }
        root.addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).apply {
            setMargins(0, d(16), 0, d(12))
        })

        val habits = WidgetData.habits(this)
        if (habits.isEmpty()) {
            list.addView(TextView(this).apply {
                text = WidgetData.t(this@HabitConfigActivity, "لا توجد عادات بعد — أضفها من التطبيق", "No habits yet — add one in the app")
                setTextColor(th.sub)
                textSize = 15f
            })
        }
        val today = WidgetData.today()
        for (h in habits) {
            val row = TextView(this).apply {
                text = h.name + "   🔥 " + h.currentStreak(today)
                setTextColor(th.text)
                textSize = 16f
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                textAlignment = View.TEXT_ALIGNMENT_VIEW_START
                setPadding(d(16), d(14), d(16), d(14))
                background = GradientDrawable().apply {
                    setColor(card)
                    cornerRadius = d(16).toFloat()
                    setStroke(d(1), (th.accent and 0x00FFFFFF) or 0x55000000)
                }
                setOnClickListener {
                    WidgetData.prefs(this@HabitConfigActivity).edit()
                        .putString(HabitSingleWidgetProvider.habitKey(appWidgetId), h.id).commit()
                    val manager = AppWidgetManager.getInstance(this@HabitConfigActivity)
                    manager.updateAppWidget(
                        appWidgetId,
                        HabitSingleWidgetProvider().build(this@HabitConfigActivity, manager, appWidgetId)
                    )
                    setResult(RESULT_OK, result(appWidgetId))
                    finish()
                }
            }
            list.addView(row, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, d(5), 0, d(5)) })
        }

        root.addView(TextView(this).apply {
            text = WidgetData.t(this@HabitConfigActivity, "إلغاء", "Cancel")
            setTextColor(th.accent)
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(0, d(12), 0, d(4))
            setOnClickListener { finish() }
        })
        setContentView(root)
    }

    private fun result(appWidgetId: Int): Intent =
        Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
}

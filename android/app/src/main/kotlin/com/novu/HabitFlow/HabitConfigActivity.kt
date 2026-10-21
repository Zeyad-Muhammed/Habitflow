package com.novu.HabitFlow

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

// Transparent configuration activity shown when a single-habit widget
// is placed. Lets the user pick which habit the widget tracks.

class HabitConfigActivity : Activity() {

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

        val dp = resources.displayMetrics.density
        fun d(v: Int) = (v * dp).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xF00D1117.toInt())
            setPadding(d(20), d(18), d(20), d(18))
            gravity = Gravity.CENTER
        }

        val title = TextView(this).apply {
            text = WidgetData.t(WidgetData.lang(WidgetData.prefs(this@HabitConfigActivity)), "اختَر عادة للويدجت", "Pick a habit for this widget")
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
        }
        root.addView(title)

        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val scroll = ScrollView(this)
        scroll.addView(list)
        val scrollParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        )
        scrollParams.setMargins(0, d(12), 0, d(12))
        root.addView(scroll, scrollParams)

        val prefs = WidgetData.prefs(this)
        val habits = WidgetData.habits(prefs)
        val lang = WidgetData.lang(prefs)

        if (habits.isEmpty()) {
            val empty = TextView(this).apply {
                text = WidgetData.t(lang, "لا توجد عادات بعد", "No habits yet")
                setTextColor(Color.parseColor("#9AA0A6"))
                textSize = 14f
            }
            list.addView(empty)
        } else {
            for (h in habits) {
                val accent = WidgetData.accentFor(h.id)
                val chip = TextView(this).apply {
                    text = WidgetData.habitLabel(h)
                    setTextColor(Color.WHITE)
                    textSize = 15f
                    setPadding(d(16), d(12), d(16), d(12))
                    background = GradientDrawable().apply {
                        setColor(Color.parseColor("#1C2128"))
                        cornerRadius = d(14).toFloat()
                        setStroke(d(1), accent)
                    }
                }
                chip.setOnClickListener {
                    prefs.edit().putString("widget_habit_$appWidgetId", h.id).apply()
                    val manager = AppWidgetManager.getInstance(this)
                    val views = HabitSingleWidgetProvider.buildViews(this@HabitConfigActivity, manager, appWidgetId)
                    manager.updateAppWidget(appWidgetId, views)
                    setResult(RESULT_OK, result(appWidgetId))
                    finish()
                }
                list.addView(
                    chip,
                    run {
                        val p = LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT
                        )
                        p.setMargins(0, d(6), 0, d(6))
                        p
                    }
                )
            }
        }

        val cancel = TextView(this).apply {
            text = WidgetData.t(lang, "إلغاء", "Cancel")
            setTextColor(Color.parseColor("#9AA0A6"))
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(0, d(12), 0, d(4))
            setOnClickListener { finish() }
        }
        root.addView(cancel)

        setContentView(root)
    }

    private fun result(appWidgetId: Int): Intent =
        Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
}

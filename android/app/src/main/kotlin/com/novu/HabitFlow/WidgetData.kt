package com.novu.HabitFlow

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// Shared data layer for every HabitFlow widget.

class HabitInfo(
    val id: String,
    val name: String,
    val isQuit: Boolean,
    val frequency: Int,
    val weekdays: Set<Int>,
    val timesPerWeek: Int,
    val target: Double,
    val unit: String,
    val dates: MutableSet<String>,
    val amounts: MutableMap<String, Double>
) {
    val measurable: Boolean get() = target > 0

    fun isDue(date: String): Boolean {
        if (frequency == 1 && weekdays.isNotEmpty() && weekdays.size < 7) {
            val cal = Calendar.getInstance()
            cal.time = parseDate(date)!!
            // Dart weekday: Mon=1..Sun=7. Calendar: Sun=1..Sat=7.
            var dow = cal.get(Calendar.DAY_OF_WEEK)
            dow = if (dow == Calendar.SUNDAY) 7 else dow - 1
            return weekdays.contains(dow)
        }
        return true
    }

    fun done(date: String): Boolean =
        if (measurable) (amounts[date] ?: 0.0) >= target else dates.contains(date)

    fun streak(today: String): Int {
        var cursor = if (done(today)) today else dayBefore(today)
        var count = 0
        while (count < 500) {
            if (!done(cursor)) break
            count++
            cursor = dayBefore(cursor)
        }
        return count
    }
}

object WidgetData {
    const val PREFS = "FlutterSharedPreferences"
    const val ACTION_TOGGLE = "com.novu.HabitFlow.TOGGLE_HABIT"
    const val EXTRA_HABIT_ID = "habitId"
    const val EXTRA_WIDGET_ID = "widgetId"

    val ACCENTS = intArrayOf(
        0xFF9B6DFF.toInt(), // violet
        0xFF4CD964.toInt(), // green
        0xFFFFB74D.toInt(), // amber
        0xFF5CA8FF.toInt(), // blue
        0xFFFF6FA5.toInt(), // pink
        0xFF4DD0C4.toInt()  // teal
    )

    fun accentFor(id: String): Int {
        var h = 0
        for (ch in id) h = h * 31 + ch.code
        val i = Math.abs(h) % ACCENTS.size
        return ACCENTS[i]
    }

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun lang(prefs: SharedPreferences): String =
        prefs.getString("flutter.app_lang", "ar") ?: "ar"

    fun habits(prefs: SharedPreferences): List<HabitInfo> {
        val out = ArrayList<HabitInfo>()
        val raw = prefs.getString("flutter.habits", "[]") ?: "[]"
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o: JSONObject = arr.getJSONObject(i)
                val amountsObj = o.optJSONObject("amounts")
                val amounts = HashMap<String, Double>()
                if (amountsObj != null) {
                    val it = amountsObj.keys()
                    while (it.hasNext()) {
                        val k = it.next()
                        amounts[k] = amountsObj.optDouble(k, 0.0)
                    }
                }
                val dates = HashSet<String>()
                val datesArr = o.optJSONArray("dates")
                if (datesArr != null) {
                    for (j in 0 until datesArr.length()) dates.add(datesArr.optString(j))
                }
                val weekdays = HashSet<Int>()
                val wdArr = o.optJSONArray("weekdays")
                if (wdArr != null) {
                    for (j in 0 until wdArr.length()) weekdays.add(wdArr.optInt(j))
                }
                out.add(
                    HabitInfo(
                        id = o.optString("id", "h$i"),
                        name = o.optString("name", "Habit"),
                        isQuit = o.optBoolean("isQuit", false),
                        frequency = o.optInt("frequency", 0),
                        weekdays = weekdays,
                        timesPerWeek = o.optInt("timesPerWeek", 3),
                        target = o.optDouble("target", 0.0),
                        unit = o.optString("unit", ""),
                        dates = dates,
                        amounts = amounts
                    )
                )
            }
        } catch (_: Exception) {
        }
        return out
    }

    fun readXp(prefs: SharedPreferences): Int {
        val email = prefs.getString("flutter.auth_email", null)
        val keys = listOfNotNull(
            email?.let { "flutter.xp_$it" },
            "flutter.xp_guest",
            "flutter.xp_null"
        )
        for (k in keys) {
            if (prefs.contains(k)) return prefs.getInt(k, 0)
        }
        return 0
    }

    // Mirrors Dart XpSystem: xpForLevel(l) = 100 + (l-1)*50.
    fun xpForLevel(level: Int) = 100 + (level - 1) * 50

    fun totalForLevel(level: Int): Int {
        var total = 0
        for (l in 1 until level) total += xpForLevel(l)
        return total
    }

    fun levelForXp(xp: Int): Int {
        var level = 1
        while (xp >= totalForLevel(level + 1)) level++
        return level
    }

    // Flips today's completion for the habit in the shared prefs JSON.
    // Returns false when the habit needs the app (measurable / quit).
    fun toggleToday(context: Context, habitId: String): Boolean {
        val prefs = prefs(context)
        val raw = prefs.getString("flutter.habits", "[]") ?: "[]"
        val today = today()
        try {
            val arr = JSONArray(raw)
            var changed = false
            for (i in 0 until arr.length()) {
                val o: JSONObject = arr.getJSONObject(i)
                if (o.optString("id") != habitId) continue
                if (o.optDouble("target", 0.0) > 0 || o.optBoolean("isQuit", false)) {
                    return false
                }
                val dates = o.optJSONArray("dates") ?: JSONArray()
                val has = (0 until dates.length()).any { dates.optString(it) == today }
                val next = JSONArray()
                for (j in 0 until dates.length()) {
                    if (dates.optString(j) != today) next.put(dates.optString(j))
                }
                if (!has) next.put(today)
                o.put("dates", next)
                arr.put(i, o)
                changed = true
                break
            }
            if (!changed) return false
            prefs.edit().putString("flutter.habits", arr.toString()).apply()
            return true
        } catch (_: Exception) {
            return false
        }
    }

    fun t(lang: String, ar: String, en: String): String =
        if (lang == "en") en else ar

    fun habitLabel(h: HabitInfo): String =
        (if (h.isQuit) "🚭 " else "") + h.name

    // ------------------------------------------------------------------
    // Bitmap dots (circles with optional white check) for ImageView cells.
    // ------------------------------------------------------------------
    fun dotBitmap(sizePx: Int, color: Int, state: Int): Bitmap {
        // state: 0 = dim hole, 1 = filled, 2 = ring (today), 3 = filled + check
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = sizePx / 2f
        when (state) {
            0 -> {
                p.color = 0x33888CA8
                c.drawCircle(r, r, r * 0.34f, p)
            }
            1 -> {
                p.color = color
                c.drawCircle(r, r, r * 0.92f, p)
            }
            2 -> {
                p.style = Paint.Style.STROKE
                p.strokeWidth = sizePx / 7f
                p.color = color
                c.drawCircle(r, r, r * 0.7f, p)
            }
            else -> {
                p.color = color
                c.drawCircle(r, r, r, p)
                p.color = -1 // white check
                p.strokeWidth = sizePx / 6.5f
                p.strokeCap = Paint.Cap.ROUND
                c.drawLine(sizePx * 0.26f, sizePx * 0.52f, sizePx * 0.44f, sizePx * 0.70f, p)
                c.drawLine(sizePx * 0.44f, sizePx * 0.70f, sizePx * 0.75f, sizePx * 0.32f, p)
            }
        }
        return bmp
    }
}

// ------------------------------------------------------------------
// Date helpers (top-level, shared by all providers).
// ------------------------------------------------------------------
private val dateFmt = ThreadLocal<SimpleDateFormat>()

fun fmt(): SimpleDateFormat {
    var f = dateFmt.get()
    if (f == null) {
        f = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        dateFmt.set(f)
    }
    return f
}

fun parseDate(date: String): Date? = try {
    fmt().parse(date)
} catch (_: Exception) {
    null
}

fun today(): String = fmt().format(Date())

fun daysAgo(from: String, days: Int): String {
    val d = Date(fmt().parse(from)!!.time - days * 86400000L)
    return fmt().format(d)
}

fun dayBefore(from: String): String = daysAgo(from, 1)

fun dayLetter(date: String, lang: String): String {
    val cal = Calendar.getInstance()
    cal.time = fmt().parse(date)!!
    val dow = cal.get(Calendar.DAY_OF_WEEK) // 1 = Sunday
    val ar = arrayOf("س", "أ", "ا", "ث", "ر", "خ", "ج")
    val en = arrayOf("S", "M", "T", "W", "T", "F", "S")
    val arr = if (lang == "en") en else ar
    return arr[dow - 1]
}

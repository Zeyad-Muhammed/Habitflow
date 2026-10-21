package com.novu.HabitFlow

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

// Shared data layer for every HabitFlow widget. Everything here mirrors the
// Dart logic in lib/main.dart (Habit, XpSystem, ChallengeSystem, MoodSystem,
// quoteFor) so the widgets and the app always agree.

private val DAY_KEY: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
private val ISO_LOCAL: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS")

fun dayKey(d: LocalDate): String = d.format(DAY_KEY)

fun parseDayKey(key: String): LocalDate? = try {
    LocalDate.parse(key, DAY_KEY)
} catch (_: Exception) {
    null
}

class HabitInfo(
    val id: String,
    val name: String,
    val isQuit: Boolean,
    val isTimer: Boolean,
    val frequency: Int, // 0 daily, 1 weekdays, 2 N times per week
    val weekdays: Set<Int>, // 1 = Mon .. 7 = Sun
    val timesPerWeek: Int,
    val target: Double,
    val unit: String,
    val dates: Set<String>,
    val amounts: Map<String, Double>,
    val doneAt: Map<String, String>,
) {
    val measurable: Boolean get() = target > 0

    /** Needs the app to complete (amount entry or countdown). */
    val needsApp: Boolean get() = measurable || isTimer

    // Habit.isDueOn: a weekly habit with no days selected counts as daily.
    fun isDue(d: LocalDate): Boolean {
        if (frequency == 1 && weekdays.isNotEmpty() && weekdays.size < 7) {
            return weekdays.contains(d.dayOfWeek.value)
        }
        return true
    }

    // Habit.isDoneOn
    fun isDone(d: LocalDate): Boolean {
        val k = dayKey(d)
        return if (measurable) (amounts[k] ?: 0.0) >= target else dates.contains(k)
    }

    fun amountOn(d: LocalDate): Double = amounts[dayKey(d)] ?: 0.0

    /** Hour the habit was completed on [d], or null (Habit.doneTimeOn). */
    fun doneHourOn(d: LocalDate): Int? {
        val iso = doneAt[dayKey(d)] ?: return null
        return try {
            iso.substring(11, 13).toInt()
        } catch (_: Exception) {
            null
        }
    }

    private fun earliest(today: LocalDate): LocalDate {
        var min: LocalDate? = null
        for (k in dates + amounts.keys) {
            val d = parseDayKey(k) ?: continue
            if (min == null || d.isBefore(min)) min = d
        }
        return min ?: today
    }

    private fun doneInRange(from: LocalDate, to: LocalDate): Int {
        var c = 0
        var d = from
        while (!d.isAfter(to)) {
            if (isDone(d)) c++
            d = d.plusDays(1)
        }
        return c
    }

    // Habit.currentStreak: an unfinished, due today does not break the run.
    fun currentStreak(today: LocalDate): Int {
        if (frequency == 2) return flexibleStreak(today)
        val earliest = earliest(today)
        var day = today
        if (isDue(day) && !isDone(day)) day = day.minusDays(1)
        var streak = 0
        while (!day.isBefore(earliest)) {
            if (!isDue(day)) {
                day = day.minusDays(1)
                continue
            }
            if (!isDone(day)) break
            streak++
            day = day.minusDays(1)
        }
        return streak
    }

    // Habit._flexibleStreak: counts weeks that met the weekly target.
    private fun flexibleStreak(today: LocalDate): Int {
        val goal = maxOf(timesPerWeek, 1)
        val monday = mondayOf(today)
        var streak = 0
        if (doneInRange(monday, today) >= goal) streak++
        var ws = monday.minusDays(7)
        while (streak < 1000 && doneInRange(ws, ws.plusDays(6)) >= goal) {
            streak++
            ws = ws.minusDays(7)
        }
        return streak
    }

    companion object {
        fun mondayOf(d: LocalDate): LocalDate = d.minusDays((d.dayOfWeek.value - 1).toLong())
    }
}

enum class ToggleResult { TOGGLED, NEEDS_APP, NOT_FOUND }

data class Challenge(
    val id: String,
    val titleAr: String,
    val titleEn: String,
    val target: Int,
)

object WidgetData {
    const val PREFS = "FlutterSharedPreferences"
    private const val NATIVE_PREFS = "HabitFlowWidgets"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun native(context: Context): SharedPreferences =
        context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

    fun today(): LocalDate = LocalDate.now()

    fun lang(context: Context): String =
        prefs(context).getString("flutter.app_lang", "ar") ?: "ar"

    fun isAr(context: Context) = lang(context) != "en"

    fun t(context: Context, ar: String, en: String) = if (isAr(context)) ar else en

    fun isDark(context: Context): Boolean =
        prefs(context).getBoolean("flutter.darkMode", true)

    // `flutter.isPro` is the stored purchase; the app also reports its
    // effective Pro state (test builds) every time it refreshes the widgets.
    fun isPro(context: Context): Boolean =
        prefs(context).getBoolean("flutter.isPro", false) ||
            native(context).getBoolean("app_pro", false)

    fun setAppPro(context: Context, pro: Boolean) {
        native(context).edit().putBoolean("app_pro", pro).apply()
    }

    // AuthService.email is interpolated as-is, so a missing email becomes "null".
    private fun email(context: Context): String =
        prefs(context).getString("flutter.auth_email", null) ?: "null"

    fun habits(context: Context): List<HabitInfo> {
        val raw = prefs(context).getString("flutter.habits", "[]") ?: "[]"
        val out = ArrayList<HabitInfo>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) out.add(parse(arr.getJSONObject(i), i))
        } catch (_: Exception) {
        }
        return out
    }

    private fun parse(o: JSONObject, index: Int): HabitInfo {
        val dates = HashSet<String>()
        o.optJSONArray("dates")?.let { a -> for (j in 0 until a.length()) dates.add(a.optString(j)) }
        val weekdays = HashSet<Int>()
        o.optJSONArray("weekdays")?.let { a -> for (j in 0 until a.length()) weekdays.add(a.optInt(j)) }
        val amounts = HashMap<String, Double>()
        o.optJSONObject("amounts")?.let { m -> m.keys().forEach { k -> amounts[k] = m.optDouble(k, 0.0) } }
        val doneAt = HashMap<String, String>()
        o.optJSONObject("doneAt")?.let { m -> m.keys().forEach { k -> doneAt[k] = m.optString(k) } }
        val tpw = if (o.isNull("timesPerWeek")) 3 else o.optInt("timesPerWeek", 3)
        return HabitInfo(
            id = o.optString("id", "h$index"),
            name = o.optString("name", "Habit"),
            isQuit = o.optBoolean("isQuit", false),
            isTimer = o.optBoolean("isTimer", false),
            frequency = o.optInt("frequency", 0),
            weekdays = weekdays,
            timesPerWeek = tpw,
            target = o.optDouble("target", 0.0),
            unit = o.optString("unit", ""),
            dates = dates,
            amounts = amounts,
            doneAt = doneAt,
        )
    }

    fun dueToday(context: Context): List<HabitInfo> {
        val d = today()
        return habits(context).filter { it.isDue(d) }
    }

    /**
     * Flips today's completion in the stored JSON exactly like the app's
     * _toggleToday: completedDates plus the doneAt timestamp. No XP is granted
     * (same as the notification "Done" action). Measurable and timer habits
     * need the app, so they are left untouched.
     */
    fun toggleToday(context: Context, habitId: String): ToggleResult {
        val p = prefs(context)
        val raw = p.getString("flutter.habits", "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw)
            val now = LocalDateTime.now()
            val key = dayKey(now.toLocalDate())
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optString("id") != habitId) continue
                if (o.optDouble("target", 0.0) > 0 || o.optBoolean("isTimer", false)) {
                    return ToggleResult.NEEDS_APP
                }
                val dates = o.optJSONArray("dates") ?: JSONArray()
                val had = (0 until dates.length()).any { dates.optString(it) == key }
                val next = JSONArray()
                for (j in 0 until dates.length()) {
                    if (dates.optString(j) != key) next.put(dates.optString(j))
                }
                val doneAt = o.optJSONObject("doneAt") ?: JSONObject()
                if (had) {
                    doneAt.remove(key)
                } else {
                    next.put(key)
                    doneAt.put(key, now.format(ISO_LOCAL))
                }
                o.put("dates", next)
                o.put("doneAt", doneAt)
                // commit(): the widget re-reads right after this returns.
                p.edit().putString("flutter.habits", arr.toString()).commit()
                return ToggleResult.TOGGLED
            }
            ToggleResult.NOT_FOUND
        } catch (_: Exception) {
            ToggleResult.NOT_FOUND
        }
    }

    // ---- XP (XpSystem) ----
    fun xp(context: Context): Int {
        val p = prefs(context)
        val k = "flutter.xp_${email(context)}"
        return try {
            p.getLong(k, 0L).toInt()
        } catch (_: ClassCastException) {
            p.getInt(k, 0)
        }
    }

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

    // ---- Daily challenge (ChallengeSystem) ----
    fun challenge(context: Context, habits: List<HabitInfo>): Challenge {
        val now = today()
        val idx = (now.year * 372 + now.monthValue * 31 + now.dayOfMonth) % 6
        val measurable = habits.any { it.measurable && it.isDue(now) }
        val due = habits.count { it.isDue(now) }
        val killIt = Challenge("kill_it", "أنهِ كل شيء اليوم ⚡", "Finish everything today ⚡", due)
        return when (idx) {
            1 -> if (measurable) Challenge("measurable", "حقّق هدفك 🎯", "Hit your goal 🎯", 1) else killIt
            2 -> Challenge("combo", "كومبو مزدوج 🔥", "Double combo 🔥", 2)
            3 -> Challenge("noon", "قبل الظهر ☀️", "Before noon ☀️", 1)
            4 -> Challenge("streak", "في انطلاق 🌀", "Keep it going 🌀", 1)
            5 -> Challenge("earlybird", "طائر مبكر 🐦", "Early bird 🐦", 1)
            else -> killIt
        }
    }

    fun challengeProgress(habits: List<HabitInfo>, id: String): Int {
        val now = today()
        return when (id) {
            "kill_it", "combo" -> habits.count { it.isDue(now) && it.isDone(now) }
            "measurable" -> if (habits.any { it.measurable && it.isDone(now) }) 1 else 0
            "noon" -> if (habits.any { it.isDone(now) && (it.doneHourOn(now) ?: 24) < 12 }) 1 else 0
            "streak" -> if (habits.any { it.isDue(now) && it.isDone(now) }) 1 else 0
            "earlybird" -> if (habits.any { it.isDone(now) && (it.doneHourOn(now) ?: 24) < 10 }) 1 else 0
            else -> 0
        }
    }

    fun challengeClaimed(context: Context): Boolean {
        val k = "flutter.challenge_${email(context)}_${dayKey(today())}"
        return (prefs(context).getString(k, "") ?: "").startsWith("done|")
    }

    // ---- Mood (MoodSystem) ----
    fun todayMood(context: Context): Int? {
        val e = prefs(context).getString("flutter.auth_email", null) ?: "guest"
        val k = "flutter.mood_${e}_${dayKey(today())}"
        val p = prefs(context)
        if (!p.contains(k)) return null
        return try {
            p.getLong(k, 0L).toInt()
        } catch (_: ClassCastException) {
            p.getInt(k, 0)
        }
    }

    // ---- Quote of the day (quoteFor) ----
    private val quotesAr = arrayOf(
        "لا تنتظر الظروف المثالية، ابدأ بما لديك وطوّرها بالاستمرار.",
        "النجاح ليس غياب الفشل، بل هو الإصرار بعد كل محاولة.",
        "العادات الصغيرة اليوم تصنع النتائج الكبيرة غداً.",
        "كل يوم هو فرصة جديدة لتصبح نسخة أفضل من نفسك.",
        "الانضباط هو الاختيار بين ما تريده الآن وما تريده أكثر.",
        "لا تقلل من قيمة الخطوات الصغيرة، فالمسافات الطويلة تبدأ بخطوة.",
        "من زرع الاستمرار حصد الإنجاز.",
        "قوة العادات تكمن في التكرار، والتكرار يصنع التميّز.",
        "ابدأ صغيراً، لكن ابدأ اليوم.",
        "كل إنجاز كبير هو سلسلة من الأيام العادية المرتبة.",
    )
    private val quotesEn = arrayOf(
        "Don't wait for perfect conditions; start with what you have and improve it.",
        "Success is not the absence of failure, it's persistence after every attempt.",
        "Small habits today create big results tomorrow.",
        "Every day is a new chance to become a better version of yourself.",
        "Discipline is choosing between what you want now and what you want most.",
        "Never underestimate small steps; long journeys begin with one step.",
        "Consistency sows, achievement reaps.",
        "The power of habits lies in repetition, and repetition creates excellence.",
        "Start small, but start today.",
        "Every big achievement is a chain of well-ordered ordinary days.",
    )

    fun quote(context: Context): String {
        val idx = (today().dayOfYear - 1) % quotesAr.size
        return if (isAr(context)) quotesAr[idx] else quotesEn[idx]
    }

    // ---- Arabic plurals (daysAr in Dart) ----
    fun daysLabel(context: Context, n: Int): String = if (isAr(context)) {
        when {
            n == 2 -> "يومين"
            n in 3..10 -> "$n أيام"
            else -> "$n يوم"
        }
    } else if (n == 1) "$n day" else "$n days"
}

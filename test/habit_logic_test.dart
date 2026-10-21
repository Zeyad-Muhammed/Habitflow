import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins "now" to [d] at 09:30 local time.
void pinToday(DateTime d) {
  clock = () => DateTime(d.year, d.month, d.day, 9, 30);
}

Habit simpleHabit(List<DateTime> done, {int frequency = 0, List<int>? weekdays}) =>
    Habit(
      name: 'Read',
      iconIndex: 1,
      id: 42,
      frequency: frequency,
      weekdays: weekdays,
      completedDates: done.map(dayKey).toList(),
    );

void main() {
  tearDown(() => clock = DateTime.now);

  group('calendar helpers', () {
    test('addDays moves by calendar days and returns midnight', () {
      expect(addDays(DateTime(2026, 1, 31, 15), 1), DateTime(2026, 2, 1));
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });

    test('addDays never repeats or skips a day across a whole year', () {
      // Run with TZ=America/New_York (or any DST zone) to exercise the
      // transitions; with Duration(days: 1) this used to repeat a day.
      var d = DateTime(2026, 1, 1);
      final seen = <String>{};
      for (var i = 0; i < 365; i++) {
        expect(seen.add(dayKey(d)), isTrue, reason: 'repeated ${dayKey(d)}');
        d = addDays(d, 1);
      }
      expect(dayKey(d), '2027-01-01');
    });
  });

  group('streaks', () {
    test('an unfinished today does not reset the current streak', () {
      pinToday(DateTime(2026, 10, 21));
      final h = simpleHabit([DateTime(2026, 10, 19), DateTime(2026, 10, 20)]);
      expect(h.currentStreak(), 2);
      h.completedDates.add(dayKey(DateTime(2026, 10, 21)));
      expect(h.currentStreak(), 3);
    });

    test('a missed day breaks the streak', () {
      pinToday(DateTime(2026, 10, 21));
      final h = simpleHabit([
        DateTime(2026, 10, 17),
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 21),
      ]);
      expect(h.currentStreak(), 2);
      expect(h.longestStreak(), 2);
    });

    test('weekly habits skip days they are not due', () {
      // 2026-10-21 is a Wednesday. Due Mon (1) and Wed (3).
      pinToday(DateTime(2026, 10, 21));
      final h = simpleHabit(
        [DateTime(2026, 10, 12), DateTime(2026, 10, 14), DateTime(2026, 10, 19)],
        frequency: 1,
        weekdays: [1, 3],
      );
      expect(h.currentStreak(), 3);
    });

    test('weekly habit with no days selected terminates (was an infinite loop)',
        () {
      pinToday(DateTime(2026, 10, 21));
      final h = simpleHabit([DateTime(2026, 10, 20)], frequency: 1, weekdays: []);
      expect(h.isDueOn(DateTime(2026, 10, 21)), isTrue);
      expect(h.currentStreak(), 1);
    });

    test('streak with no history is zero', () {
      pinToday(DateTime(2026, 10, 21));
      expect(simpleHabit([]).currentStreak(), 0);
      expect(simpleHabit([]).longestStreak(), 0);
    });

    test('longest streak counts each day once across the DST change', () {
      // US clocks fall back on 2026-11-01.
      pinToday(DateTime(2026, 11, 3));
      final days = [
        for (var d = 29; d <= 31; d++) DateTime(2026, 10, d),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 2),
      ];
      final h = simpleHabit(days);
      expect(h.longestStreak(), 5);
      expect(h.daysDoneInRange(DateTime(2026, 10, 29), DateTime(2026, 11, 2)), 5);
      expect(h.currentStreak(), 5);
    });

    test('flexible habit longest streak finds the longest run, not the first',
        () {
      // Weeks (Mondays): Sep 7, 14 done; Sep 21 missed; Sep 28, Oct 5, 12 done.
      pinToday(DateTime(2026, 10, 21));
      List<DateTime> week(DateTime monday) =>
          [monday, addDays(monday, 1), addDays(monday, 2)];
      final h = Habit(
        name: 'Gym',
        iconIndex: 0,
        id: 7,
        frequency: 2,
        timesPerWeek: 3,
        completedDates: [
          ...week(DateTime(2026, 9, 7)),
          ...week(DateTime(2026, 9, 14)),
          ...week(DateTime(2026, 9, 28)),
          ...week(DateTime(2026, 10, 5)),
          ...week(DateTime(2026, 10, 12)),
        ].map(dayKey).toList(),
      );
      expect(h.longestStreak(), 3);
      expect(h.currentStreak(), 3);
    });
  });

  group('measurable habits', () {
    test('done only when the target is reached', () {
      final day = DateTime(2026, 10, 21);
      final h = Habit(name: 'Water', iconIndex: 2, target: 8, unit: 'cups');
      h.amounts[dayKey(day)] = 5;
      expect(h.isDoneOn(day), isFalse);
      h.amounts[dayKey(day)] = 8;
      expect(h.isDoneOn(day), isTrue);
      expect(h.countCompletions(), 1);
    });
  });

  group('serialization', () {
    test('toMap/fromMap round-trips', () {
      final h = Habit(
        name: 'Pages',
        iconIndex: 1,
        id: 5,
        frequency: 1,
        weekdays: [1, 3, 5],
        target: 10,
        unit: 'pages',
        isQuit: false,
        reminderEnabled: true,
        reminderHour: 8,
        reminderMinute: 15,
        amounts: {'2026-10-21': 4},
        doneAt: {'2026-10-20': '2026-10-20T08:00:00.000'},
      );
      final copy = Habit.fromMap(h.toMap());
      expect(copy.toMap(), h.toMap());
    });

    test('an out-of-range icon index from a backup does not crash', () {
      final h = Habit.fromMap({'name': 'X', 'iconIndex': 99, 'id': 1});
      expect(h.icon, Habit.availableIcons.last);
    });
  });

  group('XP', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('level thresholds', () {
      expect(XpSystem.levelForXp(0), 1);
      expect(XpSystem.levelForXp(99), 1);
      expect(XpSystem.levelForXp(100), 2);
      expect(XpSystem.levelForXp(250), 3);
      expect(XpSystem.xpInLevel(120), 20);
      expect(XpSystem.xpToNextLevel(120), 150);
    });

    test('addOnce rewards a reason only once per day', () async {
      pinToday(DateTime(2026, 10, 21));
      final first = await XpSystem.addOnce('habit|1', 10);
      final again = await XpSystem.addOnce('habit|1', 10);
      final other = await XpSystem.addOnce('habit|2', 10);
      expect(first.awarded, isTrue);
      expect(again.awarded, isFalse);
      expect(other.awarded, isTrue);
      expect((await XpSystem.load()).xp, 20);

      pinToday(DateTime(2026, 10, 22));
      expect((await XpSystem.addOnce('habit|1', 10)).awarded, isTrue);
      expect((await XpSystem.load()).xp, 30);
    });

    test('re-picking a good mood gives XP once', () async {
      pinToday(DateTime(2026, 10, 21));
      expect(await MoodSystem.save(5), isTrue);
      expect(await MoodSystem.save(4), isFalse);
      expect(await MoodSystem.save(2), isFalse);
      expect((await XpSystem.load()).xp, 5);
      expect(await MoodSystem.todayMood(), 2);
    });
  });

  group('daily challenge', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('no habits due means the challenge is not auto-completed', () async {
      pinToday(DateTime(2026, 10, 21));
      final res = await ChallengeSystem.maybeComplete([], 'kill_it', 0, 80);
      expect(res.done, isFalse);
      expect((await XpSystem.load()).xp, 0);
    });

    test('awards the XP the challenge advertises, once', () async {
      pinToday(DateTime(2026, 10, 21));
      final today = DateTime(2026, 10, 21);
      final habits = [
        simpleHabit([today]),
        Habit(name: 'B', iconIndex: 0, id: 2, completedDates: [dayKey(today)]),
      ];
      final res = await ChallengeSystem.maybeComplete(habits, 'combo', 2, 50);
      expect(res.done, isTrue);
      expect(res.xp, 50);
      final again = await ChallengeSystem.maybeComplete(habits, 'combo', 2, 50);
      expect(again.xp, 0);
      expect((await XpSystem.load()).xp, 50);
    });
  });

  group('badges', () {
    Badge badge(String id) => BadgeSystem.all().firstWhere((b) => b.id == id);

    test('Full Focus unlocks after one perfect week on a habit', () {
      pinToday(DateTime(2026, 10, 21));
      final week = [for (var d = 14; d <= 20; d++) DateTime(2026, 10, d)];
      expect(badge('focus').earned([simpleHabit(week)], 1, 0), isTrue);
      expect(badge('focus').earned([simpleHabit(week.sublist(1))], 1, 0),
          isFalse);
    });

    test('Perfect Day ignores habits that were not due that day', () {
      pinToday(DateTime(2026, 10, 21));
      final mon = DateTime(2026, 10, 19);
      final daily = simpleHabit([mon]);
      final fridayOnly = Habit(
          name: 'F', iconIndex: 0, id: 3, frequency: 1, weekdays: [5]);
      expect(badge('perfectday').earned([daily, fridayOnly], 1, 0), isTrue);
    });
  });
}

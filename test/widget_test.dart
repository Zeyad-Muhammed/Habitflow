import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app resolves its language from the static [Language.code], which is only
/// populated by Language.load() inside main(). Widget tests never run main(),
/// so the language has to be forced here or every assertion sees Arabic.
///
/// Language.set() writes through SharedPreferences, so the mock store must be
/// installed *before* calling it, otherwise the write is discarded.
Future<void> launchApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  String lang = 'en',
}) async {
  SharedPreferences.setMockInitialValues({...prefs, 'app_lang': lang});
  await Language.set(lang);
  await tester.pumpWidget(const HabitFlowApp());
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('first launch shows onboarding', (WidgetTester tester) async {
    await launchApp(tester);
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('completing onboarding reaches the auth page',
      (WidgetTester tester) async {
    await launchApp(tester);
    expect(find.byType(OnboardingPage), findsOneWidget);

    // Drive the onboarding PageView to the last slide, then finish it.
    final skip = find.text('Skip');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip.last);
    } else {
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AuthPage), findsOneWidget);
  });

  testWidgets('auth page renders the signup form', (WidgetTester tester) async {
    await launchApp(tester, prefs: {'onboarding_done': true});
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('restored session goes straight to the main shell',
      (WidgetTester tester) async {
    await launchApp(tester, prefs: {
      'onboarding_done': true,
      'auth_logged_in': true,
      'auth_email': 'someone@example.com',
      'auth_name': 'Tester',
    });
    expect(find.byType(MainShell), findsOneWidget);
  });
}
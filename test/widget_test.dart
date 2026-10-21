import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch shows Arabic onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Language.load();
    await tester.pumpWidget(const HabitFlowApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('ابنِ أياماً أفضل'), findsOneWidget);
    expect(find.text('تخطّي'), findsOneWidget);
  });

  testWidgets('after onboarding, a new user sees sign-up (English)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lang': 'en',
      'onboarding_done': true,
    });
    await Language.load();
    await tester.pumpWidget(const HabitFlowApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('Arabic layout is right-to-left', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lang': 'ar',
      'onboarding_done': true,
    });
    await Language.load();
    await tester.pumpWidget(const HabitFlowApp());
    await tester.pump(const Duration(seconds: 1));
    final ctx = tester.element(find.text('أنشئ حسابك').first);
    expect(Directionality.of(ctx), TextDirection.rtl);
  });
}

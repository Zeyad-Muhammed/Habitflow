import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show DartPluginRegistrant;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Language.load();
  runApp(const HabitFlowApp());
  refreshWidget();
}

class Language {
  static String _code = 'ar';
  static String get code => _code;
  static bool get isAr => _code == 'ar';
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _code = p.getString('app_lang') ?? 'ar';
  }
  static Future<void> set(String code) async {
    _code = code;
    final p = await SharedPreferences.getInstance();
    await p.setString('app_lang', code);
  }
}

String t(String ar, String en) => Language.isAr ? ar : en;

/// Left-to-right isolate: keeps numbers/Latin runs like "45 / 150 XP" in
/// their natural order inside Arabic (RTL) sentences.
String ltr(String s) => '\u2066$s\u2069';

/// First-strong isolate for user text (habit names) embedded in a sentence,
/// so a Latin name inside quotes does not scramble the surrounding Arabic.
String iso(String s) => '\u2068$s\u2069';

/// Arabic day count with the right plural form: 1 يوم, 2 يومين,
/// 3–10 أيام, 11+ يوم.
String daysAr(int n) {
  if (n == 2) return 'يومين';
  if (n >= 3 && n <= 10) return '$n أيام';
  return '$n يوم';
}

/// Arabic habit count: 1 عادة, 2 عادتين, 3–10 عادات, 11+ عادة.
String habitsAr(int n) {
  if (n == 2) return 'عادتين';
  if (n >= 3 && n <= 10) return '$n عادات';
  return '$n عادة';
}

/// "N day(s)" in the current language.
String daysLabel(int n) => t(daysAr(n), n == 1 ? '$n day' : '$n days');

/// Calendar-safe day arithmetic. Adding Duration(days: n) breaks across DST
/// changes (e.g. Africa/Cairo in late October) and can repeat or skip a date.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

class AuthService {
  static const _salt = 'habitflow_salt_v1';

  static String? name;
  static String? email;
  static bool isPro = false;
  static bool proFromBilling = false;

  // TEST-ONLY: pass --dart-define=FORCE_PRO=true to build a Pro build.
  // Production builds omit the define, so this stays false.
  static const bool forceProTest = bool.fromEnvironment('FORCE_PRO');

  static const minPasswordLength = 6;

  static bool isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
  static bool get isProUser => isPro || forceProTest;

  static String _hash(String password) =>
      sha256.convert(utf8.encode('$_salt:$password')).toString();

  static Future<bool> hasAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_email') != null;
  }

  static Future<bool> register(
      String name, String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('auth_email') != null) return false;
    await prefs.setString('auth_name', name);
    await prefs.setString('auth_email', email.toLowerCase().trim());
    await prefs.setString('auth_hash', _hash(password));
    return true;
  }

  static Future<bool> login(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = email.toLowerCase().trim();
    final savedEmail = prefs.getString('auth_email');
    final savedHash = prefs.getString('auth_hash');
    if (savedEmail == null || savedHash == null) return false;
    if (savedEmail != clean) return false;
    if (savedHash != _hash(password)) return false;
    return true;
  }

  static Future<bool> socialLogin(
      {required String provider,
      required String name,
      required String email}) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = email.toLowerCase().trim();
    await prefs.setString('auth_name',
        name.trim().isEmpty ? clean.split('@').first : name.trim());
    await prefs.setString('auth_email', clean);
    await prefs.setString('auth_hash', _hash('social:$provider:$clean'));
    await prefs.setString('auth_provider', provider);
    await prefs.setBool('isPro', false);
    return true;
  }

  static Future<void> startSession() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('auth_name');
    email = prefs.getString('auth_email');
    isPro = prefs.getBool('isPro') ?? false;
    proFromBilling = prefs.getBool('proFromBilling') ?? false;
    await prefs.setBool('auth_logged_in', true);
  }

  static Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('auth_logged_in') != true) return false;
    name = prefs.getString('auth_name');
    email = prefs.getString('auth_email');
    isPro = prefs.getBool('isPro') ?? false;
    proFromBilling = prefs.getBool('proFromBilling') ?? false;
    return email != null;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auth_logged_in', false);
  }

  static Future<void> setPro(bool pro) async {
    isPro = pro;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPro', pro);
    if (!pro) { await prefs.setBool('proFromBilling', false); proFromBilling = false; }
  }

  static Future<void> setProSourceBilling(bool fromBilling) async {
    proFromBilling = fromBilling;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('proFromBilling', fromBilling);
  }

  // ---- Password reset (offline, per-device) ----
  static String? _resetCode;

  static Future<bool> canResetPassword(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('auth_email');
    if (saved == null) return false;
    return saved == email.toLowerCase().trim();
  }

  static String generateResetCode() {
    final rnd = Random.secure();
    _resetCode = List.generate(6, (_) => rnd.nextInt(10)).join();
    return _resetCode!;
  }

  static bool verifyResetCode(String code) =>
      _resetCode != null && code.trim() == _resetCode;

  static Future<bool> completePasswordReset(String newPassword) async {
    if (newPassword.length < minPasswordLength) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('auth_hash') == null) return false;
    await prefs.setString('auth_hash', _hash(newPassword));
    _resetCode = null;
    return true;
  }
}

enum BillingOutcome { granted, pending, canceled, error, unavailable, noProduct, launchFailed }

/// OAuth provider IDs. Replace the placeholders with your own values — see the
/// step-by-step guide for creating them (Google Cloud, Facebook, Microsoft Entra).
class SocialConfig {
  static const String facebookAppId = 'REPLACE_FACEBOOK_APP_ID';
  static const String facebookClientToken = 'REPLACE_FACEBOOK_CLIENT_TOKEN';
  static const String microsoftTenantId = 'common';
  static const String microsoftClientId = 'REPLACE_MICROSOFT_CLIENT_ID';
  static const String microsoftRedirectUri =
      'com.novu.HabitFlow://oauth2';

  /// OAuth client ID from Google Cloud (Web application type). Empty until
  /// google_sign_in has an authorised client for this package + signing cert.
  static const String googleClientId = '';

  /// Social providers only work once their platform credentials are filled in.
  /// Until then the buttons are hidden so the release never shows a dead
  /// "sign in" option that can only fail.
  static bool isConfigured(String provider) {
    switch (provider) {
      case 'google':
        return googleClientId.isNotEmpty;
      case 'facebook':
        return facebookAppId != 'REPLACE_FACEBOOK_APP_ID' &&
            facebookClientToken != 'REPLACE_FACEBOOK_CLIENT_TOKEN';
      case 'microsoft':
        return microsoftClientId != 'REPLACE_MICROSOFT_CLIENT_ID';
      default:
        return true;
    }
  }

  /// Keeps the "Or continue with" divider from rendering as an orphan when
  /// every provider is hidden.
  static bool get anyConfigured =>
      isConfigured('google') ||
      isConfigured('facebook') ||
      isConfigured('microsoft');
}

class SocialAuth {
  static final _google = GoogleSignIn();

  static Future<({String name, String email, String provider})?>
      signIn(String provider) async {
    switch (provider) {
      case 'google':
        return _signInGoogle();
      case 'facebook':
        return _signInFacebook();
      case 'microsoft':
        return _signInMicrosoft();
    }
    return null;
  }

  static Future<({String name, String email, String provider})?>
      _signInGoogle() async {
    final acc = await _google.signIn();
    if (acc == null) return null;
    return (
      name: acc.displayName ?? acc.email.split('@').first,
      email: acc.email,
      provider: 'google'
    );
  }

  static Future<({String name, String email, String provider})?>
      _signInFacebook() async {
    final res =
        await FacebookAuth.instance.login(permissions: ['email', 'public_profile']);
    if (res.status != LoginStatus.success) return null;
    final data = await FacebookAuth.instance.getUserData(
        fields: 'email,name');
    final email = data['email'] as String?;
    if (email == null) {
      throw Exception('Facebook did not return an email address');
    }
    return (
      name: (data['name'] as String?) ?? email.split('@').first,
      email: email,
      provider: 'facebook'
    );
  }

  static final _appauth = FlutterAppAuth();
  static const _microsoftDiscovery =
      'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration';

  static Future<({String name, String email, String provider})?>
      _signInMicrosoft() async {
    final clientId = SocialConfig.microsoftClientId;
    if (clientId.startsWith('REPLACE_')) {
      throw Exception('Microsoft client id is not configured yet');
    }
    final auth = await _appauth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        SocialConfig.microsoftRedirectUri,
        discoveryUrl: _microsoftDiscovery,
        scopes: ['openid', 'profile', 'email'],
        promptValues: ['select_account'],
      ),
    );
    final idToken = auth.idToken;
    if (idToken == null) {
      throw Exception('Microsoft did not return an id token');
    }
    final claims = _decodeIdToken(idToken);
    final email = (claims['email'] as String?) ??
        (claims['preferred_username'] as String?);
    if (email == null) throw Exception('Microsoft did not return an email');
    return (
      name: (claims['name'] as String?) ?? email.split('@').first,
      email: email,
      provider: 'microsoft'
    );
  }

  static Map<String, dynamic> _decodeIdToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw Exception('Invalid id token');
    final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])));
    return Map<String, dynamic>.from(jsonDecode(payload));
  }
}

enum ProPlan { monthly, yearly, lifetime }

/// Wraps Google Play Billing through the in_app_purchase plugin.
/// Grants Pro on active purchases; renewals are managed by Google Play.
class BillingService {
  static const String proMonthlyId = 'com.novustudio.habitflow.pro_monthly';
  static const String proYearlyId = 'com.novustudio.habitflow.pro_yearly';
  static const String proLifetimeId = 'com.novustudio.habitflow.pro_lifetime';
  static const productIds = {proMonthlyId, proYearlyId, proLifetimeId};

  static ProPlan? planFor(String productId) => switch (productId) {
        proMonthlyId => ProPlan.monthly,
        proYearlyId => ProPlan.yearly,
        proLifetimeId => ProPlan.lifetime,
        _ => null,
      };

  static BillingService? _instance;
  static BillingService get instance => _instance ??= BillingService._();

  final InAppPurchase _iap;
  final Map<ProPlan, ProductDetails> _plans = {};
  ProductDetails? _yearlyTrial;
  String? _lastError;
  Completer<BillingOutcome>? _outcome;
  bool _sawActivePro = false;

  BillingService._() : _iap = InAppPurchase.instance {
    _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      _lastError = '$e';
      final c = _outcome;
      if (c != null && !c.isCompleted) { c.complete(BillingOutcome.error); }
    });
  }

  ProductDetails? product(ProPlan plan) => _plans[plan];

  /// Set only while Play still offers this user the yearly free trial.
  bool get hasYearlyTrial => _yearlyTrial != null;
  String? get lastError => _lastError;

  // Play can leave these calls pending forever (seen on an emulator whose
  // billing service never answered), which kept the paywall on "Loading…"
  // and the buy button spinning. User-facing calls time out and treat the
  // store as unavailable; the silent startup refresh just waits.
  static const _storeTimeout = Duration(seconds: 10);

  Future<bool> available({bool timeout = false}) async {
    try {
      final f = _iap.isAvailable();
      return await (timeout ? f.timeout(_storeTimeout) : f);
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureProducts() async {
    try {
      final res =
          await _iap.queryProductDetails(productIds).timeout(_storeTimeout);
      _plans.clear();
      _yearlyTrial = null;
      // A subscription comes back once per base plan and once per offer. The
      // free-trial offer is the one whose first pricing phase costs nothing.
      for (final p in res.productDetails) {
        if (p.id == proYearlyId && p.rawPrice == 0) {
          _yearlyTrial = p;
          continue;
        }
        final plan = planFor(p.id);
        if (plan != null) _plans.putIfAbsent(plan, () => p);
      }
    } catch (e) { _lastError = '$e'; }
  }

  /// Whole-percent saving of the yearly plan over twelve monthly payments.
  int? get yearlySavingPercent {
    final m = _plans[ProPlan.monthly]?.rawPrice;
    final y = _plans[ProPlan.yearly]?.rawPrice;
    if (m == null || y == null || m <= 0) return null;
    final pct = ((1 - y / (m * 12)) * 100).round();
    return pct > 0 ? pct : null;
  }

  /// Grant pro when a monthly subscription is or was active.
  Future<void> refreshSubscription() async {
    try {
      if (!await available()) return;
      await ensureProducts();
      await _iap.restorePurchases();
    } catch (e) { _lastError = '$e'; }
  }

  Future<BillingOutcome> buy(ProPlan plan) async {
    try {
      if (!await available(timeout: true)) { return BillingOutcome.unavailable; }
      await ensureProducts();
      final details = plan == ProPlan.yearly
          ? (_yearlyTrial ?? _plans[ProPlan.yearly])
          : _plans[plan];
      if (details == null) { return BillingOutcome.noProduct; }
      final completer = Completer<BillingOutcome>();
      _outcome = completer;
      final ok = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: details,
          applicationUserName: AuthService.email,
        ),
      );
      if (!ok) {
        _outcome = null;
        return BillingOutcome.launchFailed;
      }
      return await completer.future;
    } catch (e) {
      _lastError = '$e';
      return BillingOutcome.error;
    }
  }

  Future<BillingOutcome> restore() async {
    try {
      if (!await available(timeout: true)) { return BillingOutcome.unavailable; }
      _sawActivePro = AuthService.isProUser;
      await _iap.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 6));
      final ok = _sawActivePro || AuthService.isProUser;
      if (!ok && AuthService.proFromBilling) {
        await AuthService.setProSourceBilling(false);
        await AuthService.setPro(false);
      }
      return ok ? BillingOutcome.granted : BillingOutcome.canceled;
    } catch (e) {
      _lastError = '$e';
      return BillingOutcome.error;
    }
  }

  void _onPurchases(List<PurchaseDetails> details) {
    final pending = <PurchaseDetails>[];
    for (final d in details) {
      if (d.status == PurchaseStatus.pending) {
        pending.add(d);
        continue;
      }
      if (d.status == PurchaseStatus.restored || d.status == PurchaseStatus.purchased) {
        if (productIds.contains(d.productID)) {
          _sawActivePro = true;
          _grantPro(d);
        }
        continue;
      }
      if (d.status == PurchaseStatus.canceled) { _finish(BillingOutcome.canceled); continue; }
      _lastError = '${d.error ?? 'Unknown purchase error'}';
      _finish(BillingOutcome.error);
    }
    if (pending.isNotEmpty) { _finish(BillingOutcome.pending); }
  }

  Future<void> _grantPro(PurchaseDetails d) async {
    await AuthService.setPro(true);
    await AuthService.setProSourceBilling(true);
    if (d.pendingCompletePurchase) {
      try { await _iap.completePurchase(d); } catch (e) { _lastError = '$e'; }
    }
    _finish(BillingOutcome.granted);
  }

  void _finish(BillingOutcome outcome) {
    final c = _outcome;
    if (c != null && !c.isCompleted) { c.complete(outcome); }
  }
}

/// Current time source. Tests override this to pin "today".
DateTime Function() clock = DateTime.now;

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

const palette = [
  Color(0xFF7C4DFF),
  Color(0xFF00B0FF),
  Color(0xFF00C853),
  Color(0xFFFFA000),
  Color(0xFFFF4081),
];

const quotesAr = [
  'لا تنتظر الظروف المثالية، ابدأ بما لديك وطوّرها بالاستمرار.',
  'النجاح ليس غياب الفشل، بل هو الإصرار بعد كل محاولة.',
  'العادات الصغيرة اليوم تصنع النتائج الكبيرة غداً.',
  'كل يوم هو فرصة جديدة لتصبح نسخة أفضل من نفسك.',
  'الانضباط هو الاختيار بين ما تريده الآن وما تريده أكثر.',
  'لا تقلل من قيمة الخطوات الصغيرة، فالمسافات الطويلة تبدأ بخطوة.',
  'من زرع الاستمرار حصد الإنجاز.',
  'قوة العادات تكمن في التكرار، والتكرار يصنع التميّز.',
  'ابدأ صغيراً، لكن ابدأ اليوم.',
  'كل إنجاز كبير هو سلسلة من الأيام العادية المرتبة.',
];

const quotesEn = [
  "Don't wait for perfect conditions; start with what you have and improve it.",
  "Success is not the absence of failure, it's persistence after every attempt.",
  'Small habits today create big results tomorrow.',
  'Every day is a new chance to become a better version of yourself.',
  'Discipline is choosing between what you want now and what you want most.',
  'Never underestimate small steps; long journeys begin with one step.',
  'Consistency sows, achievement reaps.',
  'The power of habits lies in repetition, and repetition creates excellence.',
  'Start small, but start today.',
  'Every big achievement is a chain of well-ordered ordinary days.',
];

({String text, String author}) quoteFor(DateTime now) {
  final idx =
      now.difference(DateTime(now.year, 1, 1)).inDays % quotesAr.length;
  return Language.isAr
      ? (text: quotesAr[idx], author: 'حكمة اليوم')
      : (text: quotesEn[idx], author: 'Quote of the day');
}

Color cardColor(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF1C2127) : Colors.white;

Color secondaryColor(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF262C33) : const Color(0xFFE8EAF0);

Color dividerColor(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF262C33) : const Color(0xFFDDE1E8);

InputDecoration softInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  Widget? prefix,
}) {
  final scheme = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: secondaryColor(Theme.of(context).brightness),
    prefixIcon: prefix,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: scheme.primary, width: 1.5),
    ),
  );
}

/// Transparent status bar with icons that contrast with the app background.
SystemUiOverlayStyle overlayStyleFor(bool isDark) =>
    (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);

ThemeData _buildTheme(Color seed, Brightness b) {
  final isDark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  return ThemeData(
    brightness: b,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: scheme,
    useMaterial3: true,
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor(b),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(
            color: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      // Transparent app bars cannot infer the status bar icon colour.
      systemOverlayStyle:
          overlayStyleFor(isDark),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 26,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardColor(b),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
            color: scheme.primary.withValues(alpha: isDark ? 0.14 : 0.07)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF272C35) : const Color(0xFF20242E),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({
    required this.scheme,
    required this.isDark,
    required this.child,
  });

  final ColorScheme scheme;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF0C0F14), Color(0xFF0E1218)]
              : const [Color(0xFFF4F2FA), Color(0xFFF7F5FC)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -140,
            top: -140,
            child: _Blob(
              size: 420,
              color: scheme.primary.withValues(alpha: isDark ? 0.16 : 0.07),
            ),
          ),
          Positioned(
            right: -120,
            top: 280,
            child: _Blob(
              size: 340,
              color: scheme.tertiary.withValues(alpha: isDark ? 0.12 : 0.05),
            ),
          ),
          Positioned(
            left: -120,
            bottom: -160,
            child: _Blob(
              size: 380,
              color: scheme.secondary.withValues(alpha: isDark ? 0.10 : 0.05),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          radius: 0.9,
          stops: const [0.0, 0.55, 1.0],
          colors: [
            color,
            color.withValues(alpha: color.a * 0.35),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class HabitFlowApp extends StatefulWidget {
  const HabitFlowApp({super.key});

  static HabitFlowAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<HabitFlowAppState>();

  @override
  State<HabitFlowApp> createState() => HabitFlowAppState();
}

class HabitFlowAppState extends State<HabitFlowApp> {
  Color _seed = palette[0];
  bool _customTheme = false;
  bool _darkMode = true;
  bool? _onboardingDone;
  String _lang = Language.code;
  int _proEpoch = 0;

  void refreshPro() => setState(() => _proEpoch++);

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initBilling();
  }

  Future<void> _initBilling() async {
    await BillingService.instance.refreshSubscription();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final i = prefs.getInt('themeColor') ?? 0;
    final custom = prefs.getInt('themeCustom');
    final dark = prefs.getBool('darkMode') ?? true;
    if (mounted) {
      setState(() {
        if (i < 0 && custom != null) {
          _customTheme = true;
          _seed = Color(custom);
        } else {
          _customTheme = false;
          _seed = palette[i.clamp(0, palette.length - 1)];
        }
        _darkMode = dark;
        _onboardingDone = prefs.getBool('onboarding_done') ?? false;
        _lang = Language.code;
      });
    }
  }

  void setTheme(int index) {
    setState(() {
      _customTheme = false;
      _seed = palette[index.clamp(0, palette.length - 1)];
    });
    SharedPreferences.getInstance().then((p) {
      p.setInt('themeColor', index);
      p.remove('themeCustom');
    });
  }

  void setCustomTheme(Color color) {
    setState(() {
      _customTheme = true;
      _seed = color;
    });
    SharedPreferences.getInstance().then((p) {
      p.setInt('themeColor', -1);
      p.setInt('themeCustom', color.toARGB32());
    });
  }

  void setDarkMode(bool dark) {
    setState(() => _darkMode = dark);
    SharedPreferences.getInstance().then((p) => p.setBool('darkMode', dark));
  }

  void setLang(String code) {
    Language.set(code);
    setState(() => _lang = code);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HabitFlow',
      debugShowCheckedModeBanner: false,
      locale: Locale(_lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _buildTheme(_seed, Brightness.light),
      darkTheme: _buildTheme(_seed, Brightness.dark),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // Screens without an AppBar (home, onboarding, sign-in) need the
        // status bar icon colour set here, or they stay white in light mode.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyleFor(isDark),
          child: _AmbientBackground(
            scheme: cs,
            isDark: isDark,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: KeyedSubtree(
        key: ValueKey('$_lang-$_proEpoch'),
        child: (_onboardingDone ?? true) ? const RootPage() : const OnboardingPage(),
      ),
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _applying = false;

  List<(IconData, String, String)> get _slides => [
    (
      Icons.track_changes,
      t('ابنِ أياماً أفضل', 'Build better days'),
      t('أنشئ عاداتك، حافظ على سلاسلك، وشاهد ثباتك ينمو يوماً بعد يوم.',
          'Create your habits, keep your streaks, and watch your consistency grow day by day.'),
    ),
    (
      Icons.workspace_premium,
      t('ارتقِ بانضباطك', 'Level up your discipline'),
      t('اكسب النقاط وافتح المستويات والإنجازات اللامعة كل مرة تلتزم بنفسك.',
          'Earn points and unlock shiny levels and achievements every time you commit.'),
    ),
    (
      Icons.self_improvement,
      t('ذكية وقابلة للقياس', 'Smart and measurable'),
      t('حدد أهدافاً أسبوعية، قس التقدم بالصفحات أو الدقائق، اضبط تذكيرات وأقلع عن العادات السيئة.',
          'Set weekly goals, track progress in pages or minutes, set reminders, and quit bad habits.'),
    ),
  ];

  Future<void> _done() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RootPage()),
    );
  }

  Future<void> _applyPack(StarterPack pack) async {
    if (_applying) return;
    setState(() => _applying = true);
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('habits') ?? '[]';
    final list = (jsonDecode(raw) as List)
        .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final room = AuthService.isProUser
        ? pack.habits.length
        : (FreePlan.maxHabits - list.length).clamp(0, pack.habits.length);
    var added = 0;
    for (final ph in pack.habits) {
      if (added >= room) break;
      list.add(ph.toHabit(
          id:
              (DateTime.now().millisecondsSinceEpoch & 0x1FFFFFFF) + added));
      added++;
    }
    await p.setString(
        'habits', jsonEncode(list.map((h) => h.toMap()).toList()));
    await p.setBool('onboarding_done', true);
    refreshWidget();
    if (!mounted) return;
    final note = added == pack.habits.length
        ? t('أضفنا ${pack.habits.length} عادات من حزمة ${t(pack.titleAr, pack.titleEn)} ✅',
            'Added ${pack.habits.length} habits from the ${t(pack.titleAr, pack.titleEn)} pack ✅')
        : t('أضفنا $added عادات — رقِّ لبرو بالتانية لأكثر.',
            'Added $added habits — upgrade to Pro for more.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(note),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ),
    );
    setState(() => _applying = false);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RootPage()),
      );
    }
  }

  Widget _buildPacks() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 12),
        Text(
          t('ابدأ بحياة 🌱', 'Start with a life 🌱'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          t('اختار حزمة عادات جاهزة لحياتك — شيل اللي مش مناسبك.',
              'Pick ready-made habit packs around the life you want — remove what does not fit.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 18),
        for (final pack in starterPacks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showPackSheet(pack),
                child: Ink(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor(Theme.of(context).brightness),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: pack.color.withAlpha(80), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: pack.color.withAlpha(32),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(pack.icon, color: pack.color, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t(pack.titleAr, pack.titleEn),
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              t('${pack.habits.length} عادات جاهزة',
                                  '${pack.habits.length} ready habits'),
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _showPackSheet(StarterPack pack) async {
    final selected = List<bool>.filled(pack.habits.length, true);
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: cardColor(Theme.of(context).brightness),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: pack.color.withAlpha(32),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(pack.icon, color: pack.color, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(t(pack.titleAr, pack.titleEn),
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('حافظ على اللي يناسبك · اضغط لإزالته',
                        'Keep what fits · tap to remove'),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < pack.habits.length; i++)
                    CheckboxListTile(
                      value: selected[i],
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: pack.color,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(t(pack.habits[i].nameAr, pack.habits[i].nameEn),
                          style: const TextStyle(fontSize: 14)),
                      onChanged: (v) =>
                          setSheetState(() => selected[i] = v ?? true),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: pack.color),
                      onPressed: _applying
                          ? null
                          : () => Navigator.pop(ctx, selected.any((s) => s)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          t('أضف العادات المختارة', 'Add selected habits'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                  if (_applying)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (added != true) return;
    final kept = <PackHabit>[
      for (var i = 0; i < pack.habits.length; i++)
        if (selected[i]) pack.habits[i],
    ];
    if (kept.isEmpty) return;
    final filtered = StarterPack(
      titleAr: pack.titleAr,
      titleEn: pack.titleEn,
      icon: pack.icon,
      color: pack.color,
      habits: kept,
    );
    await _applyPack(filtered);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _done,
                child: Text(t('تخطّي', 'Skip')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length + 1,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) {
                  if (i == _slides.length) return _buildPacks();
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: primary.withAlpha(25),
                            borderRadius: BorderRadius.circular(36),
                          ),
                          child: Icon(s.$1, size: 70, color: primary),
                        ),
                        const SizedBox(height: 32),
                        Text(s.$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text(
                          s.$3,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_page < _slides.length)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == i ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == i ? primary : Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _applying
                      ? null
                      : () {
                          if (_page < _slides.length) {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          } else {
                            _done();
                          }
                        },
                  child: Text(_page < _slides.length - 1
                      ? t('متابعة', 'Continue')
                      : t('ابدأ الآن 🚀', 'Get started 🚀')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    _check();
    try {
      MobileAds.instance.initialize();
    } catch (_) {}
  }

  Future<void> _check() async {
    final ok = await AuthService.restoreSession();
    if (mounted) setState(() => _loggedIn = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _loggedIn! ? const MainShell() : const AuthPage();
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignup = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    AuthService.hasAccount().then((has) {
      if (mounted) setState(() => _isSignup = !has);
    });
  }

  Future<void> _submit() async {
    final emailText = _email.text.trim();
    final passText = _password.text;
    // New passwords need 6+ characters; sign-in only needs one, so accounts
    // created under the old 4-character rule can still log in.
    final passTooShort = _isSignup
        ? passText.length < AuthService.minPasswordLength
        : passText.isEmpty;
    if (!AuthService.isValidEmail(emailText) || passTooShort) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('أدخل بريداً صحيحاً وكلمة مرور (6 حروف فأكثر)',
              'Enter a valid email and a password (6+ characters)'))));
      return;
    }
    setState(() => _loading = true);

    bool ok;
    if (_isSignup) {
      ok = await AuthService.register(_name.text.trim(), emailText, passText);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t('الحساب موجود مسبقاً — سجّل دخولك',
                  'Account already exists — sign in instead'))));
        }
        setState(() => _loading = false);
        return;
      }
    } else {
      ok = await AuthService.login(emailText, passText);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t('بريد أو كلمة مرور خاطئة ❌',
                  'Wrong email or password ❌'))));
        }
        setState(() => _loading = false);
        return;
      }
    }

    await AuthService.startSession();
    if (mounted) {
      Navigator.pushReplacement(
context,
          MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  Future<void> _socialSignIn(String provider) async {
    setState(() => _loading = true);
    try {
      final info = await SocialAuth.signIn(provider);
      if (info == null) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t('تم إلغاء تسجيل الدخول.',
                  'Sign-in was cancelled.'))));
        }
        return;
      }
      await AuthService.socialLogin(
          provider: info.provider, name: info.name, email: info.email);
      await AuthService.logout();
      await AuthService.startSession();
      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const MainShell()));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(
                'تعذر تسجيل الدخول بهذا الحساب — تأكد من إعدادات المزود.',
                'Could not sign in with this account — check provider settings.'))));
      }
    }
  }

  Widget _googleIcon() {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      child: const Text('G',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4285F4))),
    );
  }

  Future<void> _fakeGoogleTest() async {
    setState(() => _loading = true);
    await AuthService.socialLogin(
      provider: 'google',
      name: 'Test Google',
      email: 'testGoogle@habitflow.app',
    );
    await AuthService.logout();
    await AuthService.startSession();
    if (mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Image.asset(
                  brightness == Brightness.dark
                      ? 'assets/icon/logo_white.png'
                      : 'assets/icon/logo_black.png',
                  height: 90,
                ),
                const SizedBox(height: 24),
                Text(
                  _isSignup ? t('أنشئ حسابك', 'Create your account') : t('أهلاً بعودتك', 'Welcome back'),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignup
                      ? t('ابدأ ببناء سلسلة نجاحك اليوم',
                          'Start building your success streak today')
                      : t('سجّل دخولك لمتابعة سلاسلك',
                          'Sign in to keep your streaks going'),
                  style: TextStyle(color: Colors.grey.shade500),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor(brightness),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      if (_isSignup) ...[
                        TextField(
                          controller: _name,
                          decoration: softInputDecoration(
                            context,
                            label: t('الاسم', 'Name'),
                            prefix: const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: softInputDecoration(
                          context,
                          label: t('البريد الإلكتروني', 'Email'),
                          prefix: const Icon(Icons.alternate_email),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: softInputDecoration(
                          context,
                          label: t('كلمة المرور', 'Password'),
                          prefix: const Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(_isSignup
                                        ? t('أنشئ حسابك', 'Create account')
                                        : t('تسجيل الدخول', 'Sign in'),
                                    style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                      if (!_isSignup) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ResetPasswordPage()));
                            },
                            child: Text(t('نسيت كلمة المرور؟',
                                'Forgot password?')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (SocialConfig.anyConfigured) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(t('أو تابع بـ', 'Or continue with'),
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 13)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (SocialConfig.anyConfigured)
                  Row(
                  children: [
                    if (SocialConfig.isConfigured('google')) ...[
                      Expanded(
                        child: _SocialButton(
                          icon: _googleIcon(),
                          label: 'Google',
                          onTap: _loading ? null : () => _socialSignIn('google'),
                        ),
                      ),
                      if (SocialConfig.isConfigured('facebook'))
                        const SizedBox(width: 12),
                    ],
                    if (SocialConfig.isConfigured('facebook'))
                      Expanded(
                        child: _SocialButton(
                          icon: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF1877F2),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.facebook,
                                color: Colors.white, size: 14),
                          ),
                          label: 'Facebook',
                          onTap: _loading ? null : () => _socialSignIn('facebook'),
                        ),
                      ),
                  ],
                ),
                if (SocialConfig.isConfigured('microsoft')) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _SocialButton(
                      icon: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF0078D4),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.mail, color: Colors.white, size: 13),
                      ),
                      label: t('أوتلوك', 'Outlook'),
                      onTap: _loading ? null : () => _socialSignIn('microsoft'),
                    ),
                  ),
                ],
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _loading ? null : _fakeGoogleTest,
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: Text(t(
                        'دخول اختباري (محاكاة جوجل)',
                        'Test login (simulated Google)')),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _isSignup = !_isSignup),
                  child: Text(_isSignup
                      ? t('لديك حساب بالفعل؟ سجّل دخولك',
                          'Already have an account? Sign in')
                      : t('جديد هنا؟ أنشئ حسابك', 'New here? Create an account')),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(
                        'https://zeyad-muhammed.github.io/novu-site/habitflow/privacy-policy/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    t('سياسة الخصوصية', 'Privacy Policy'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('HabitFlow v1.0.3',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton(
      {required this.icon, required this.label, this.onTap});

  final Widget icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Material(
      color: cardColor(brightness),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.grey.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 10),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();
  int _phase = 0; // 0 = email, 1 = code, 2 = new password
  bool _loading = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _toast(t('اكتب بريدك الإلكتروني الأول', 'Enter your email first'));
      return;
    }
    setState(() => _loading = true);
    final ok = await AuthService.canResetPassword(email);
    setState(() => _loading = false);
    if (!ok) {
      _toast(t(
          'مفيش حساب بالبريد ده على الجهاز ده — اعمل حساب جديد',
          'No account with this email on this device — create one'));
      return;
    }
    final code = AuthService.generateResetCode();
    if (!mounted) return;
    setState(() => _phase = 1);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        title: Text(t('كود التغيير', 'Reset code')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('التطبيق شغال أوفلاين، فالكود بيظهر هنا مباشرة:',
                'The app works offline, so your code appears right here:')),
            const SizedBox(height: 12),
            Text(code,
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('تم', 'Got it')),
          ),
        ],
      ),
    );
  }

  void _verifyCode() {
    if (!AuthService.verifyResetCode(_code.text)) {
      _toast(t('الكود مش صح — جرب تاني', 'Wrong code — try again'));
      return;
    }
    setState(() => _phase = 2);
  }

  Future<void> _saveNewPassword() async {
    final pass = _newPass.text;
    if (pass.length < AuthService.minPasswordLength) {
      _toast(t('الباسورد لازم 6 حروف فأكثر', 'Password must be 6+ characters'));
      return;
    }
    if (pass != _confirm.text) {
      _toast(t('الباسورد والمكرر مش زي بعض', 'Passwords do not match'));
      return;
    }
    setState(() => _loading = true);
    final ok = await AuthService.completePasswordReset(pass);
    setState(() => _loading = false);
    if (!ok) {
      _toast(t('حصلت مشكلة — جرب تاني', 'Something went wrong — try again'));
      return;
    }
    if (mounted) {
      _toast(t('تم تغيير كلمة المرور — سجّل دخولك بالباسورد الجديد',
          'Password changed — sign in with your new password'));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final sub = _phase == 0
        ? t('اكتب بريدك الإلكتروني علشان نولّد كود تغيير كلمة المرور',
            'Enter your email to generate a password reset code')
        : _phase == 1
            ? t('اكتب الكود اللي ظهرلك', 'Enter the code you received')
            : t('اكتب كلمة المرور الجديدة', 'Choose your new password');

    return Scaffold(
      appBar: AppBar(
        title: Text(t('نسيت كلمة المرور', 'Forgot password')),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Image.asset(
                  brightness == Brightness.dark
                      ? 'assets/icon/logo_white.png'
                      : 'assets/icon/logo_black.png',
                  height: 72,
                ),
                const SizedBox(height: 20),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500)),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor(brightness),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      if (_phase == 0) ...[
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: softInputDecoration(
                            context,
                            label: t('البريد الإلكتروني', 'Email'),
                            prefix: const Icon(Icons.alternate_email),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _sendCode,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Text(t('توليد الكود', 'Generate code'),
                                      style:
                                          const TextStyle(fontSize: 16)),
                            ),
                          ),
                        ),
                      ],
                      if (_phase == 1) ...[
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 6),
                          decoration: softInputDecoration(
                            context,
                            label: t('كود من 6 أرقام', '6-digit code'),
                            prefix: const Icon(Icons.pin_outlined),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _verifyCode,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(t('تأكيد الكود', 'Verify code'),
                                  style:
                                      const TextStyle(fontSize: 16)),
                            ),
                          ),
                        ),
                      ],
                      if (_phase == 2) ...[
                        TextField(
                          controller: _newPass,
                          obscureText: true,
                          decoration: softInputDecoration(
                            context,
                            label: t('كلمة المرور الجديدة',
                                'New password'),
                            prefix: const Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirm,
                          obscureText: true,
                          decoration: softInputDecoration(
                            context,
                            label: t('كرر كلمة المرور', 'Confirm password'),
                            prefix: const Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _saveNewPassword,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Text(t('تغيير كلمة المرور',
                                          'Change password'),
                                      style:
                                          const TextStyle(fontSize: 16)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.handleResponse(response);
}

const MethodChannel _widgetChannel = MethodChannel('com.novu.HabitFlow/widget');

void refreshWidget() {
  // The channel only exists on Android while the activity is running (not in
  // tests, other platforms or the background notification isolate).
  _widgetChannel.invokeMethod('refresh').catchError((_) => null);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      // "Done ✔" has showsUserInterface: false, so when the app isn't in the
      // foreground Android delivers it to this background entry point only.
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundHandler,
    );
    _initialized = true;
  }

  static NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_reminder',
          t('تذكيرات العادات', 'Habit Reminders'),
          channelDescription: t('تذكير يومي لإنجاز عاداتك',
              'Daily reminder to complete your habits'),
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  static NotificationDetails _detailsWithAction(int habitId) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_reminder',
          t('تذكيرات العادات', 'Habit Reminders'),
          channelDescription: t('تذكير يومي لإنجاز عاداتك',
              'Daily reminder to complete your habits'),
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction(
              'mark_$habitId',
              t('تم ✔', 'Done ✔'),
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'dismiss_$habitId',
              t('ذكّرني لاحقاً', 'Remind later'),
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
      );

  static Future<void> _onNotificationResponse(
      NotificationResponse response) async {
    final payload = response.payload ?? '';
    final action = response.actionId ?? '';
    if (action.startsWith('mark_')) {
      final id = int.tryParse(action.split('_').last);
      if (id != null) await _completeHabitById(id);
    }
    if (payload.startsWith('mark_done|')) {
      final id = int.tryParse(payload.split('|')[1]);
      if (id != null) await _completeHabitById(id);
    }
  }

  static Future<void> handleResponse(NotificationResponse response) =>
      _onNotificationResponse(response);

  static Future<void> _completeHabitById(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('habits') ?? '[]';
      final list = (jsonDecode(raw) as List)
          .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final idx = list.indexWhere((h) => h.id == id);
      if (idx < 0) return;
      final h = list[idx];
      final now = clock();
      if (!h.isDueOn(now) || h.isDoneOn(now)) return;
      if (h.isMeasurable) {
        h.amounts[dayKey(now)] = h.target;
        h.setDoneAt(now);
      } else {
        h.completedDates.add(dayKey(now));
        h.setDoneAt(now);
      }
      await prefs.setString(
          'habits', jsonEncode(list.map((e) => e.toMap()).toList()));
      refreshWidget();
      HomePage.reload?.call();
    } catch (_) {}
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> scheduleDaily(
      {required int hour, required int minute}) async {
    await _plugin.cancel(id: 1);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: 1,
      title: t('حان وقت عاداتك! 💪', 'Time for your habits! 💪'),
      body: t('أبقِ سلسلتك حيّة — سجّل عاداتك اليوم.',
          'Keep your streak alive — log your habits today.'),
      scheduledDate: scheduled,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexact,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> scheduleHabit(Habit h) async {
    if (!h.reminderEnabled || h.reminderHour == null) return;
    await _plugin.cancel(id: h.id);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, h.reminderHour!, h.reminderMinute ?? 0);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: h.id,
      title: h.isQuit
          ? t('${h.name} — كن قوياً 💪', '${h.name} — stay strong 💪')
          : t('حان وقت "${h.name}" ⏰', 'Time for "${h.name}" ⏰'),
      body: h.isMeasurable
          ? t('الهدف: ${_fmtNum(h.target)}${h.unit.isEmpty ? '' : ' ${h.unit}'} اليوم.',
              'Goal: ${_fmtNum(h.target)}${h.unit.isEmpty ? '' : ' ${h.unit}'} today.')
          : h.isQuit
              ? t('أبقِ سلسلتك حيّة — يوماً بيوم.',
                  'Keep your streak alive — day by day.')
              : t('أبقِ سلسلتك حيّة — سجّلها اليوم.',
                  'Keep your streak alive — log it today.'),
      scheduledDate: scheduled,
      notificationDetails: _detailsWithAction(h.id),
      androidScheduleMode: AndroidScheduleMode.inexact,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: notificationPayloadForHabit(h),
    );
  }

  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  static Future<void> cancelGlobal() => _plugin.cancel(id: 1);

  static Future<void> cancelHabit(int id) => _plugin.cancel(id: id);

  static Future<void> cancelAll() => _plugin.cancelAll();

  static Future<void> showTest() async {
    await _plugin.show(
      id: 2,
      title: t('الإشعارات تعمل ✅', 'Notifications work ✅'),
      body: t('ستصلك تذكيرات يومية في الوقت الذي اخترته.',
          'You will get daily reminders at the time you chose.'),
      notificationDetails: _details,
    );
  }
}

class Habit {
  String name;
  int iconIndex;
  int id;
  List<String> completedDates;
  List<int> weekdays; // 1=Mon .. 7=Sun
  int frequency; // 0 daily, 1 specific weekdays, 2 flexible (N/week)
  int timesPerWeek;
  double target; // 0 = simple habit, >0 = measurable
  String unit;
  bool isQuit;
  bool reminderEnabled;
  int? reminderHour;
  int? reminderMinute;
  bool isTimer;
  int timerMinutes;
  Map<String, double> amounts;
  Map<String, String> doneAt;

  Habit({
    required this.name,
    required this.iconIndex,
    int? id,
    List<String>? completedDates,
    List<int>? weekdays,
    this.frequency = 0,
    this.timesPerWeek = 3,
    this.target = 0,
    this.unit = '',
    this.isQuit = false,
    this.reminderEnabled = false,
    this.reminderHour,
    this.reminderMinute,
    this.isTimer = false,
    this.timerMinutes = 5,
    Map<String, double>? amounts,
    Map<String, String>? doneAt,
  })  : id = id ?? (clock().millisecondsSinceEpoch & 0x1FFFFFFF),
        completedDates = completedDates ?? [],
        weekdays = weekdays ?? [1, 2, 3, 4, 5, 6, 7],
        amounts = amounts ?? {},
        doneAt = doneAt ?? {};

  DateTime? doneTimeOn(DateTime d) {
    final iso = doneAt[dayKey(d)];
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  void setDoneAt(DateTime d, {bool remove = false}) {
    final k = dayKey(d);
    if (remove) {
      doneAt.remove(k);
      return;
    }
    doneAt[k] = d.toIso8601String();
  }

  static const List<IconData> basicIcons = [
    Icons.fitness_center,
    Icons.menu_book,
    Icons.water_drop,
    Icons.self_improvement,
    Icons.bedtime,
    Icons.code,
    Icons.directions_run,
    Icons.local_dining,
    Icons.music_note,
    Icons.brush,
  ];

  static const List<IconData> extraIcons = [
    Icons.school_rounded,
    Icons.work_rounded,
    Icons.savings_rounded,
    Icons.attach_money_rounded,
    Icons.shopping_cart_rounded,
    Icons.shopping_bag_rounded,
    Icons.restaurant_rounded,
    Icons.local_cafe_rounded,
    Icons.cake_rounded,
    Icons.celebration_rounded,
    Icons.eco_rounded,
    Icons.park_rounded,
    Icons.forest_rounded,
    Icons.terrain_rounded,
    Icons.wb_sunny_rounded,
    Icons.nights_stay_rounded,
    Icons.bed_rounded,
    Icons.alarm_rounded,
    Icons.no_food_rounded,
    Icons.smoke_free_rounded,
    Icons.vaccines_rounded,
    Icons.medication_rounded,
    Icons.favorite_rounded,
    Icons.psychology_rounded,
    Icons.smartphone_rounded,
    Icons.laptop_mac_rounded,
    Icons.headphones_rounded,
    Icons.movie_rounded,
    Icons.videogame_asset_rounded,
    Icons.theater_comedy_rounded,
    Icons.draw_rounded,
    Icons.palette_rounded,
    Icons.camera_alt_rounded,
    Icons.language_rounded,
    Icons.translate_rounded,
    Icons.volunteer_activism_rounded,
    Icons.handshake_rounded,
    Icons.groups_rounded,
    Icons.family_restroom_rounded,
    Icons.clean_hands_rounded,
    Icons.shower_rounded,
    Icons.face_rounded,
    Icons.spa_rounded,
    Icons.accessibility_new_rounded,
    Icons.emoji_events_rounded,
    Icons.water_rounded,
    Icons.coffee_rounded,
    Icons.self_improvement_rounded,
    Icons.music_note_rounded,
    Icons.fitness_center_rounded,
    Icons.hiking_rounded,
    Icons.directions_run_rounded,
    Icons.sports_soccer_rounded,
    Icons.sports_basketball_rounded,
    Icons.directions_bike_rounded,
    Icons.pool_rounded,
    Icons.pets_rounded,
  ];

  static final List<IconData> availableIcons = [
    ...basicIcons,
    ...extraIcons,
  ];

  IconData get icon =>
      availableIcons[iconIndex.clamp(0, availableIcons.length - 1)];

  bool get isMeasurable => target > 0;
  bool get isTimerHabit => isTimer;
  bool get isWeekly => frequency == 1;
  bool get isFlexible => frequency == 2;
  bool get isDaily => frequency == 0;

  bool isDueOn(DateTime d) {
    // A weekly habit with no days selected would never be due, which made
    // currentStreak() loop forever. Treat it as daily instead.
    if (isWeekly && weekdays.isNotEmpty && weekdays.length < 7) {
      return weekdays.contains(d.weekday);
    }
    return true;
  }

  bool isDoneOn(DateTime d) {
    final key = dayKey(d);
    if (isMeasurable) return (amounts[key] ?? 0) >= target;
    return completedDates.contains(key);
  }

  double amountOn(DateTime d) => amounts[dayKey(d)] ?? 0;

  int countCompletions() {
    if (!isMeasurable) return completedDates.length;
    return amounts.keys
        .where((k) => (amounts[k] ?? 0) >= target)
        .length;
  }

  int daysDoneInRange(DateTime from, DateTime to) {
    var count = 0;
    for (var d = from; !d.isAfter(to); d = addDays(d, 1)) {
      if (isDoneOn(d)) count++;
    }
    return count;
  }

  DateTime _earliest() {
    final all = <DateTime>[];
    for (final k in completedDates) {
      all.add(parseDayKey(k));
    }
    for (final k in amounts.keys) {
      try {
        all.add(parseDayKey(k));
      } catch (_) {}
    }
    if (all.isEmpty) {
      final now = clock();
      return DateTime(now.year, now.month, now.day);
    }
    return all.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  static DateTime mondayOf(DateTime d) {
    final diff = (d.weekday - DateTime.monday) % 7;
    return addDays(DateTime(d.year, d.month, d.day), -diff);
  }

  int currentStreak() {
    if (isFlexible) return _flexibleStreak();
    int streak = 0;
    final now = clock();
    final earliest = _earliest();
    var day = DateTime(now.year, now.month, now.day);
    // Today still counts as "in progress": an unfinished today does not break
    // the streak, it just isn't added to it yet.
    if (isDueOn(day) && !isDoneOn(day)) day = addDays(day, -1);
    while (!day.isBefore(earliest)) {
      if (!isDueOn(day)) {
        day = addDays(day, -1);
        continue;
      }
      if (!isDoneOn(day)) break;
      streak++;
      day = addDays(day, -1);
    }
    return streak;
  }

  int _flexibleStreak() {
    int streak = 0;
    final today = clock();
    final self = this;
    if (self.daysDoneInRange(mondayOf(today), today) >= timesPerWeek) {
      streak++;
    }
    var weekStart = addDays(mondayOf(today), -7);
    while (self.daysDoneInRange(weekStart,
            addDays(weekStart, 6)) >= timesPerWeek) {
      streak++;
      weekStart = addDays(weekStart, -7);
    }
    return streak;
  }

  int longestStreak() {
    if (isFlexible) {
      int best = 0;
      int run = 0;
      final thisWeek = mondayOf(clock());
      for (var ws = mondayOf(_earliest());
          !ws.isAfter(thisWeek);
          ws = addDays(ws, 7)) {
        if (daysDoneInRange(ws, addDays(ws, 6)) >= timesPerWeek) {
          run++;
          if (run > best) best = run;
        } else if (ws != thisWeek) {
          // The current week can still be completed, so it never ends a run.
          run = 0;
        }
      }
      return best;
    }
    int best = 0;
    int run = 0;
    for (var d = _earliest();
        !d.isAfter(clock());
        d = addDays(d, 1)) {
      if (!isDueOn(d)) continue;
      if (isDoneOn(d)) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  /// الحلقة الهادئة: فقدت يوم مستحق قبل هذا اليوم ثم عدت اليوم.
  DateTime? _previousDueBefore(DateTime day) {
    var prev = addDays(day, -1);
    while (!prev.isBefore(addDays(_earliest(), -1))) {
      if (isDueOn(prev)) return prev;
      prev = addDays(prev, -1);
    }
    return null;
  }

  bool isComebackOn(DateTime day) {
    if (!isDoneOn(day)) return false;
    final prev = _previousDueBefore(day);
    if (prev == null) return false;
    if (isDoneOn(prev)) return false;
    var wasActiveBefore = false;
    for (var d = _earliest(); !d.isAfter(prev); d = addDays(d, 1)) {
      if (isDueOn(d) && isDoneOn(d)) {
        wasActiveBefore = true;
        break;
      }
    }
    return wasActiveBefore;
  }

  int countComebacks() {
    final doneKeys = <String>{
      if (!isMeasurable) ...completedDates,
      ...amounts.keys.where((k) => (amounts[k] ?? 0) >= target),
    };
    var count = 0;
    for (final k in doneKeys) {
      try {
        if (isComebackOn(parseDayKey(k))) count++;
      } catch (_) {}
    }
    return count;
  }

  /// إجمالي الأيام التي أُنجِز فيها شيء ما (عبر كل العادات).
  static int activeDaysOf(List<Habit> habits) {
    final days = <String>{};
    for (final h in habits) {
      if (h.isMeasurable) {
        days.addAll(h.amounts.keys.where((k) => (h.amounts[k] ?? 0) >= h.target));
      } else {
        days.addAll(h.completedDates);
      }
    }
    return days.length;
  }

  /// أقدم تاريخ لها (من أي يوم إنجاز في أي مصدر).
  DateTime? earliestEver() {
    if (!isMeasurable && completedDates.isEmpty && amounts.keys.isEmpty) {
      return null;
    }
    return _earliest();
  }

  int get numberOfStreaks {
    int weeks = 0;
    int run = 0;
    for (var d = _earliest();
        !d.isAfter(clock());
        d = addDays(d, 1)) {
      if (!isDueOn(d)) continue;
      if (isDoneOn(d)) {
        run++;
        if (run == 7) {
          weeks++;
          run = 0;
        }
      } else {
        run = 0;
      }
    }
    return weeks;
  }

  int rateLastN(int n) {
    int done = 0;
    int due = 0;
    for (int i = 0; i < n; i++) {
      final d = addDays(clock(), -i);
      if (!isDueOn(d)) continue;
      due++;
      if (isDoneOn(d)) done++;
    }
    return due == 0 ? 0 : (done / due * 100).round();
  }

  int doneInMonth(int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    var c = 0;
    for (var d = 1; d <= days; d++) {
      if (isDoneOn(DateTime(year, month, d))) c++;
    }
    return c;
  }

  int dueInMonth(int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    var c = 0;
    for (var d = 1; d <= days; d++) {
      if (isDueOn(DateTime(year, month, d))) c++;
    }
    return c;
  }

  double monthRate(int year, int month) {
    final done = doneInMonth(year, month);
    final due = dueInMonth(year, month);
    return due == 0 ? 0 : (done / due * 100).roundToDouble();
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'iconIndex': iconIndex,
        'id': id,
        'dates': completedDates,
        'weekdays': weekdays,
        'frequency': frequency,
        'timesPerWeek': timesPerWeek,
        'target': target,
        'unit': unit,
        'isQuit': isQuit,
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'isTimer': isTimer,
        'timerMinutes': timerMinutes,
        'amounts': amounts,
        'doneAt': doneAt,
      };

  factory Habit.fromMap(Map<String, dynamic> map) => Habit(
        name: map['name'],
        iconIndex: map['iconIndex'] ?? 0,
        id: map['id'],
        completedDates: List<String>.from(map['dates'] ?? []),
        weekdays: map['weekdays'] != null
            ? List<int>.from(map['weekdays'])
            : null,
        frequency: map['frequency'] ?? 0,
        timesPerWeek: map['timesPerWeek'] ?? 3,
        target: (map['target'] as num?)?.toDouble() ?? 0,
        unit: map['unit'] ?? '',
        isQuit: map['isQuit'] ?? false,
        reminderEnabled: map['reminderEnabled'] ?? false,
        reminderHour: map['reminderHour'],
        reminderMinute: map['reminderMinute'],
        isTimer: map['isTimer'] ?? false,
        timerMinutes: map['timerMinutes'] ?? 5,
        amounts: map['amounts'] != null
            ? Map<String, double>.from(
                (map['amounts'] as Map).map((k, v) =>
                    MapEntry(k as String, (v as num).toDouble())))
            : null,
        doneAt: map['doneAt'] != null
            ? Map<String, String>.from(map['doneAt'])
            : {},
      );
}

class XpSystem {
  static int xpForLevel(int level) => 100 + (level - 1) * 50;

  static int totalForLevel(int level) {
    var total = 0;
    for (var l = 1; l < level; l++) {
      total += xpForLevel(l);
    }
    return total;
  }

  static int levelForXp(int xp) {
    var level = 1;
    while (xp >= totalForLevel(level + 1)) {
      level++;
    }
    return level;
  }

  static int xpInLevel(int xp) => xp - totalForLevel(levelForXp(xp));

  static int xpToNextLevel(int xp) => xpForLevel(levelForXp(xp));

  static String _key() => 'xp_${AuthService.email}';

  static Future<({int xp, int level})> load() async {
    final p = await SharedPreferences.getInstance();
    final xp = p.getInt(_key()) ?? 0;
    return (xp: xp, level: levelForXp(xp));
  }

  static String _awardsKey() => 'xp_awards_${AuthService.email}';

  /// Adds [amount] XP only the first time [reason] is seen today, so undoing
  /// and redoing a check-in (or re-picking a mood) can't farm XP. Only
  /// today's reasons are kept: past days can no longer be toggled.
  static Future<({int xp, int level, bool leveledUp, bool awarded})> addOnce(
      String reason, int amount) async {
    final p = await SharedPreferences.getInstance();
    final today = dayKey(clock());
    final key = '$today|$reason';
    final seen = (p.getStringList(_awardsKey()) ?? [])
        .where((k) => k.startsWith('$today|'))
        .toList();
    if (seen.contains(key)) {
      final xp = p.getInt(_key()) ?? 0;
      return (xp: xp, level: levelForXp(xp), leveledUp: false, awarded: false);
    }
    await p.setStringList(_awardsKey(), [...seen, key]);
    final res = await add(amount);
    return (
      xp: res.xp,
      level: res.level,
      leveledUp: res.leveledUp,
      awarded: true,
    );
  }

  static Future<({int xp, int level, bool leveledUp})> add(int amount) async {
    final p = await SharedPreferences.getInstance();
    final oldXp = p.getInt(_key()) ?? 0;
    final newXp = oldXp + amount;
    await p.setInt(_key(), newXp);
    return (
      xp: newXp,
      level: levelForXp(newXp),
      leveledUp: levelForXp(newXp) > levelForXp(oldXp),
    );
  }
}

// ---------- Analytics helpers (local, no backend) ----------

const _monthLabelsAr = [
  'يَن', 'فِب', 'مار', 'أبري', 'ماي', 'يون',
  'يول', 'أغس', 'سِب', 'أكت', 'نوف', 'ديس'
];
const _monthLabelsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String monthLabel(int month) =>
    t(_monthLabelsAr[month - 1], _monthLabelsEn[month - 1]);

Map<int, double> weekdayConsistency(List<Habit> habits, int weeks) {
  final done = {for (var w = 1; w <= 7; w++) w: 0};
  final total = {for (var w = 1; w <= 7; w++) w: 0};
  final today = clock();
  for (int i = 0; i < weeks * 7; i++) {
    final d = addDays(today, -i);
    total[d.weekday] = total[d.weekday]! + habits.where((h) => h.isDueOn(d)).length;
    done[d.weekday] =
        done[d.weekday]! + habits.where((h) => h.isDoneOn(d)).length;
  }
  final out = <int, double>{};
  for (var w = 1; w <= 7; w++) {
    out[w] = total[w] == 0 ? 0 : done[w]! * 100.0 / total[w]!;
  }
  return out;
}

const weekdayNamesAr = [
  'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'
];
const weekdayNamesEn = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

const weekdayShortAr = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];
const weekdayShortEn = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

const _dayLabelsAr = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];
const _dayLabelsEn = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

String weekdayName(int w) =>
    t(weekdayNamesAr[w.clamp(1, 7) - 1], weekdayNamesEn[w.clamp(1, 7) - 1]);

String weekdayShortLabel(int w) =>
    t(weekdayShortAr[w.clamp(1, 7) - 1], weekdayShortEn[w.clamp(1, 7) - 1]);

String dayAxisLabel(int i) =>
    t(_dayLabelsAr[i % 7], _dayLabelsEn[i % 7]);

String get evenlySpreadLabel => t('موزّعة بالتساوي', 'Evenly spread');

String bestWeekdayLabel(List<Habit> habits) {
  final c = weekdayConsistency(habits, 4);
  var bestW = 1;
  for (var w = 2; w <= 7; w++) {
    if (c[w]! > c[bestW]!) bestW = w;
  }
  if (c[bestW]! < 30) return evenlySpreadLabel;
  return weekdayName(bestW);
}

List<({int year, int month, String label, double rate})> monthSeries(
    List<Habit> habits, int months) {
  final now = clock();
  final out = <({int year, int month, String label, double rate})>[];
  for (int i = months - 1; i >= 0; i--) {
    final dt = DateTime(now.year, now.month - i, 1);
    var done = 0, due = 0;
    for (final h in habits) {
      done += h.doneInMonth(dt.year, dt.month);
      due += h.dueInMonth(dt.year, dt.month);
    }
    final rate = due == 0 ? 0.0 : (done * 100.0 / due).roundToDouble();
    out.add((
      year: dt.year,
      month: dt.month,
      label: monthLabel(dt.month),
      rate: rate,
    ));
  }
  return out;
}

double dayRate(List<Habit> habits, DateTime d) {
  if (habits.isEmpty) return 0;
  final done = habits.where((h) => h.isDoneOn(d)).length;
  return done / habits.length * 100;
}

Color heatColor(double rate, Color primary, Color bg) {
  if (rate <= 0.0001) return bg;
  final alpha = (24 + rate * 2.2).round().clamp(24, 255);
  return primary.withAlpha(alpha);
}

bool sameDay(DateTime a, DateTime b) => dayKey(a) == dayKey(b);

List<String> buildInsights(List<Habit> habits) {
  final out = <String>[];
  final today = clock();
  if (habits.isEmpty) {
    out.add(t('أضف أول عادة لتبدأ بملاحظاتك الذكية.',
        'Add your first habit to start your smart insights.'));
    return out;
  }
  final bestDay = bestWeekdayLabel(habits);
  if (bestDay != evenlySpreadLabel) {
    out.add(t('📅 $bestDay هو أقوى يوم لديك.', '📅 $bestDay is your strongest day.'));
  }

  final totalCompletions = habits.fold<int>(
      0, (s, h) => s + h.countCompletions());
  if (totalCompletions >= 50) {
    out.add(t('🎯 إجمالي $totalCompletions تسجيلاً — الثبات يبني نتائجك.',
        '🎯 $totalCompletions total logs — consistency builds your results.'));
  }

  final hot = habits.where((h) => h.currentStreak() >= 7).toList();
  if (hot.isNotEmpty) {
    out.add(t('🔥 ${hot.length} عادة بسلسلة نشطة ${ltr('${hot.first.currentStreak()}+')} يوم.',
        '🔥 ${hot.length} habit(s) with an active ${hot.first.currentStreak()}+ day streak.'));
  }

  final measurable = habits.where((h) => h.isMeasurable);
  for (final h in measurable) {
    final r30 = h.rateLastN(30);
    final c = h.countCompletions();
    if (c >= 20 && r30 >= 85) {
      final suggested = h.target < 10
          ? (h.target * 1.5).roundToDouble()
          : (h.target + h.target * 0.25).roundToDouble();
      out.add(t(
          '📈 تتقن "${iso(h.name)}" — جرّب رفع الهدف إلى ${ltr('$suggested')} ${h.unit.trim()} للارتقاء بمستواك.',
          '📈 You master "${h.name}" — try raising the goal to $suggested ${h.unit.trim()} to level up.'));
      break;
    }
  }

  final down = habits.where((h) => h.isDueOn(today) &&
      h.rateLastN(7) < 40 && h.countCompletions() >= 10).toList();
  if (down.isNotEmpty) {
    out.add(t('⚠️ "${iso(down.first.name)}" هادئة هذا الأسبوع — اهتم بأفضل عاداتك أولاً.',
        '⚠️ "${down.first.name}" is quiet this week — focus on your best habits first.'));
  }

  if (out.length < 2 && totalCompletions > 0) {
    out.add(t('✅ سجّل مزاجك يومياً لنصائح شخصية إضافية.',
        '✅ Log your daily mood for extra personal tips.'));
  }
  return out.take(3).toList();
}

Habit? atRiskHabit(List<Habit> habits) {
  final today = clock();
  final due = habits.where((h) => h.isDueOn(today) && !h.isDoneOn(today)).toList();
  if (due.isEmpty) return null;
  due.sort((a, b) {
    final ra = a.rateLastN(7).toDouble() <= 0 ? 9999 : a.rateLastN(7);
    final rb = b.rateLastN(7).toDouble() <= 0 ? 9999 : b.rateLastN(7);
    return ra.compareTo(rb);
  });
  return due.first;
}

// ---------- Mood system ----------

class MoodSystem {
  static String _moodKey(String? email, String date) =>
      'mood_${email ?? 'guest'}_$date';

  static Future<int?> todayMood() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(
        _moodKey(AuthService.email, dayKey(clock())));
  }

  /// Saves today's mood and returns whether it earned XP.
  static Future<bool> save(int mood) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_moodKey(AuthService.email, dayKey(clock())), mood);
    if (mood < 4) return false;
    return (await XpSystem.addOnce('mood', 5)).awarded;
  }

  static Future<int> goodMoodStreak() async {
    final p = await SharedPreferences.getInstance();
    var streak = 0;
    for (var i = 0; i < 60; i++) {
      final d = addDays(clock(), -i);
      final m = p.getInt(_moodKey(AuthService.email, dayKey(d)));
      if (m == null || m < 4) break;
      streak++;
    }
    return streak;
  }

  static Future<Map<String, int>> last14() async {
    final p = await SharedPreferences.getInstance();
    final out = <String, int>{};
    for (var i = 0; i < 14; i++) {
      final d = dayKey(addDays(clock(), -i));
      final m = p.getInt(_moodKey(AuthService.email, d));
      if (m != null) out[d] = m;
    }
    return out;
  }
}

// ---------- Badges (persistent unlocks) ----------

class Badge {
  final String id;
  final IconData icon;
  final String title;
  final String desc;
  final bool Function(List<Habit> habits, int level, int xp) earned;

  Badge(this.id, this.icon, this.title, this.desc, this.earned);
}

/// What the free plan includes. Everything else is unlocked by Pro.
class FreePlan {
  static const maxHabits = 5;
  static const maxMeasurable = 1;
  static const badgeIds = {
    'first',
    'fire7',
    'perfectday',
    'first_week',
    'first_comeback',
  };
  static bool badgeAvailable(String id) =>
      AuthService.isProUser || badgeIds.contains(id);
}

class BadgeSystem {
  static List<Badge> all() => [
    Badge('first', Icons.emoji_events_outlined, t('الخطوة الأولى', 'First Step'),
        t('أنشئ أول عادة لك', 'Create your first habit'),
        (h, l, x) => h.isNotEmpty),
    Badge('fire7', Icons.local_fire_department, t('على نار', 'On Fire'),
        t('حقق سلسلة 7 أيام', 'Reach a 7-day streak'),
        (h, l, x) => h.any((hb) => hb.longestStreak() >= 7)),
    Badge('bolt30', Icons.bolt, t('لا يُوقف', 'Unstoppable'),
        t('حقق سلسلة 30 يوماً', 'Reach a 30-day streak'),
        (h, l, x) => h.any((hb) => hb.longestStreak() >= 30)),
    Badge('century', Icons.star, t('مئة إنجاز', 'Century'),
        t('أنجز 100 عادة إجمالاً', 'Complete 100 habits in total'),
        (h, l, x) => h.fold<int>(0, (s, hb) => s + hb.countCompletions()) >= 100),
    Badge('perfectday', Icons.today, t('يوم مثالي', 'Perfect Day'),
        t('أنجز كل عاداتك في يوم واحد', 'Complete every habit in one day'),
        (h, l, x) => _perfectDayEver(h)),
    Badge('perfectweek', Icons.workspace_premium, t('أسبوع مثالي', 'Perfect Week'),
        t('أنهي كل عاداتك 7 أيام متتالية', 'Complete all habits 7 days in a row'),
        (h, l, x) => _perfectWeekEver(h)),
    Badge('level5', Icons.auto_awesome, t('نجم صاعد', 'Rising Star'),
        t('صل للمستوى 5', 'Reach level 5'),
        (h, l, x) => l >= 5),
    Badge('level10', Icons.military_tech, t('سيد العادات', 'Habit Master'),
        t('صل للمستوى 10', 'Reach level 10'),
        (h, l, x) => l >= 10),
    Badge('measured', Icons.straighten, t('قابل للقياس', 'Measurable'),
        t('أنجز عادة قابلة للقياس', 'Complete a measurable habit'),
        (h, l, x) => h.any((hb) => hb.isMeasurable && hb.countCompletions() > 0)),
    Badge('consistent', Icons.rule, t('ثابت', 'Consistent'),
        t('نجاح 80%+ خلال 30 يوماً', '80%+ success over 30 days'),
        (h, l, x) => h.any((hb) => hb.countCompletions() > 0 && hb.rateLastN(30) >= 80)),
    Badge('clean7', Icons.eco, t('سلسلة نقية', 'Clean Streak'),
        t('7 أيام نقية على عادة إقلاع', '7 clean days on a quit habit'),
        (h, l, x) => h.where((hb) => hb.isQuit).fold<int>(0, (m, hb) => m > hb.longestStreak() ? m : hb.longestStreak()) >= 7),
    Badge('scholar', Icons.school, t('عالِم', 'Scholar'),
        t('أنجز 10 أهداف قابلة للقياس', 'Complete 10 measurable goals'),
        (h, l, x) => h.fold<int>(0, (s, hb) => s + (hb.isMeasurable ? hb.countCompletions() : 0)) >= 10),
    Badge('runner', Icons.flag, t('نادي 100', '100 Club'),
        t('أنجز 100 تسجيلاً هذا الأسبوع', 'Complete 100 logs this week'),
        (h, l, x) => _hundredWeek(h)),
    Badge('focus', Icons.filter_center_focus, t('تركيز كامل', 'Full Focus'),
        t('أنجز أسبوعاً مثالياً في عادة واحدة', 'Complete a perfect week on one habit'),
        (h, l, x) => _singlePerfectWeek(h)),
    Badge('pro', Icons.workspace_premium, t('داعم برو', 'Pro Supporter'),
        t('فعّل برو', 'Activate Pro'), (h, l, x) => AuthService.isProUser),
    Badge('first_week', Icons.weekend, t('أسبوع كامل 🌱', 'First week 🌱'),
        t('سبعة أيام اعتياد — أساسك اتبني', 'Seven days with your plan — the foundation is real'),
        (h, l, x) => Habit.activeDaysOf(h) >= 7),
    Badge('first_comeback', Icons.settings_backup_restore, t('أول عودة 🔥', 'First comeback 🔥'),
        t('رجعت بعد فترة هدوء — دي تحسب أكتر من أي سلسلة',
            'You returned after a quiet stretch — that counts more than any streak'),
        (h, l, x) => h.any((hb) => hb.countComebacks() >= 1)),
    Badge('new_record', Icons.star_border_purple500, t('ريكورد جديد 📈', 'New personal record 📈'),
        t('وصول لأطول سلسلة 21 يوماً', 'Reach a 21-day personal best run'),
        (h, l, x) => h.fold<int>(0, (s, hb) => s > hb.longestStreak() ? s : hb.longestStreak()) >= 21),
    Badge('active100', Icons.calendar_month, t('100 يوم نشاط 💯', '100 active days 💯'),
        t('مئة يوم ظهرت فيها لعادة واحدة على الأقل',
            'One hundred days in which you showed up for at least one habit'),
        (h, l, x) => Habit.activeDaysOf(h) >= 100),
    Badge('mastery', Icons.workspace_premium, t('إتقان عادة 🏔️', 'Habit mastery 🏔️'),
        t('ستة أشهر مع "أول عادة لك" — الالتزام بقى جزء منك',
            'Six months with a habit — it is part of you now'),
        (h, l, x) => h.any((hb) {
              final first = hb.earliestEver();
              if (first == null) return false;
              return DateTime.now().difference(first).inDays >= 180 &&
                  hb.countCompletions() >= 100;
            })),
    Badge('journey1y', Icons.route, t('رحلة سنة 🕰️', 'One-year journey 🕰️'),
        t('سنة كاملة من أول إنجاز لك — شوف اتنينت قد إيه!',
            'A full year since your first log — look how far the map goes'),
        (h, l, x) => h.any((hb) {
              final first = hb.earliestEver();
              if (first == null) return false;
              return DateTime.now().difference(first).inDays >= 365;
            })),
  ];

  static bool _perfectDayEver(List<Habit> habits) {
    if (habits.length < 2) return false;
    final allDates = <String>{};
    for (final h in habits) {
      if (h.isMeasurable) {
        allDates.addAll(h.amounts.keys);
      } else {
        allDates.addAll(h.completedDates);
      }
    }
    for (final key in allDates) {
      if (_allDueDone(habits, parseDayKey(key))) return true;
    }
    return false;
  }

  /// Every habit due on [day] was completed (and at least one was due).
  static bool _allDueDone(List<Habit> habits, DateTime day) {
    final due = habits.where((h) => h.isDueOn(day)).toList();
    return due.isNotEmpty && due.every((h) => h.isDoneOn(day));
  }

  static bool _perfectWeekEver(List<Habit> habits) {
    if (habits.length < 2) return false;
    for (var offset = 0; offset < 60; offset++) {
      final start = addDays(clock(), -(7 + offset));
      var ok = true;
      for (var i = 0; i < 7; i++) {
        if (!_allDueDone(habits, addDays(start, i))) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  static bool _hundredWeek(List<Habit> habits) =>
      habits.fold<int>(0, (s, h) => s + h.daysDoneInRange(addDays(clock(), -6), clock())) >= 100;

  static bool _singlePerfectWeek(List<Habit> habits) {
    if (habits.isEmpty) return false;
    for (final h in habits) {
      if (h.numberOfStreaks >= 1) return true;
    }
    return false;
  }

  static String _key() => 'badges_${AuthService.email}';

  static Future<Set<String>> unlocked() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_key()) ?? []).toSet();
  }

  static Future<List<Badge>> evaluate(
      List<Habit> habits, int level, int xp,
      {bool awardXp = true}) async {
    final had = await unlocked();
    final newly = <Badge>[];
    final earned = all()
        .where((b) =>
            FreePlan.badgeAvailable(b.id) && b.earned(habits, level, xp))
        .toList();
    for (final b in earned) {
      if (!had.contains(b.id)) newly.add(b);
    }
    if (newly.isNotEmpty) {
      final set = had.toSet()..addAll(newly.map((b) => b.id));
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key(), set.toList());
    }
    return newly;
  }
}

// ---------- Starter packs (onboarding templates) ----------

class PackHabit {
  final String nameAr;
  final String nameEn;
  final int iconIndex;
  final int frequency;
  final int timesPerWeek;
  final double target;
  final String unit;
  final bool isQuit;

  const PackHabit({
    required this.nameAr,
    required this.nameEn,
    required this.iconIndex,
    this.frequency = 0,
    this.timesPerWeek = 3,
    this.target = 0,
    this.unit = '',
    this.isQuit = false,
  });

  Habit toHabit({int? id}) => Habit(
        name: t(nameAr, nameEn),
        iconIndex: iconIndex,
        frequency: frequency,
        timesPerWeek: timesPerWeek,
        target: target,
        unit: unit,
        isQuit: isQuit,
        id: id,
      );
}

class StarterPack {
  final String titleAr;
  final String titleEn;
  final IconData icon;
  final Color color;
  final List<PackHabit> habits;

  const StarterPack({
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.color,
    required this.habits,
  });
}

const starterPacks = [
  StarterPack(
    titleAr: 'العافية',
    titleEn: 'Wellness',
    icon: Icons.eco,
    color: Color(0xFF2EBD85),
    habits: [
      PackHabit(nameAr: 'اشرب ماية 8 أكواب 💧', nameEn: 'Drink 8 glasses of water',
        iconIndex: 2, target: 8, unit: 'كوب'),
      PackHabit(nameAr: 'مشي يومي 🚶', nameEn: 'Daily walk', iconIndex: 6),
      PackHabit(nameAr: 'النوم قبل 11 🛌', nameEn: 'Sleep by 11', iconIndex: 4),
      PackHabit(nameAr: 'رياضة 3 مرات/أسبوع 🏋️', nameEn: 'Workout 3×/week',
        iconIndex: 0, frequency: 2, timesPerWeek: 3),
    ],
  ),
  StarterPack(
    titleAr: 'التعلّم',
    titleEn: 'Learning',
    icon: Icons.menu_book,
    color: Color(0xFF4C7CFF),
    habits: [
      PackHabit(nameAr: 'اقرأ 10 صفحات 📖', nameEn: 'Read 10 pages',
        iconIndex: 1, target: 10, unit: 'صفحة'),
      PackHabit(nameAr: '5 دقايق إنجليزي 🇬🇧', nameEn: '5 min language practice',
        iconIndex: 3, target: 5, unit: 'دقيقة'),
      PackHabit(nameAr: 'مذاكرة 25 دقيقة 🎯', nameEn: '25 min deep work',
        iconIndex: 5, target: 25, unit: 'دقيقة'),
      PackHabit(nameAr: 'مذكرات يومية ✍️', nameEn: 'Daily journal', iconIndex: 8),
    ],
  ),
  StarterPack(
    titleAr: 'الرياضة',
    titleEn: 'Sports',
    icon: Icons.fitness_center,
    color: Color(0xFFFF8A3D),
    habits: [
      PackHabit(nameAr: 'تمرين 3 مرات/أسبوع 🏋️', nameEn: 'Workout 3×/week',
        iconIndex: 0, frequency: 2, timesPerWeek: 3),
      PackHabit(nameAr: 'إطالة يومية 🤸', nameEn: 'Daily stretching', iconIndex: 3),
      PackHabit(nameAr: '10 آلاف خطوة 👟', nameEn: '10k steps',
        iconIndex: 6, target: 10000, unit: 'خطوة'),
      PackHabit(nameAr: 'أكواب ميادة 💧', nameEn: 'Drink water',
        iconIndex: 2, target: 8, unit: 'كوب'),
    ],
  ),
  StarterPack(
    titleAr: 'الإسلامية',
    titleEn: 'Islamic',
    icon: Icons.mosque,
    color: Color(0xFF7C6AE8),
    habits: [
      PackHabit(nameAr: 'صلاة الفجر في وقتها 🕌', nameEn: 'Fajr on time', iconIndex: 3),
      PackHabit(nameAr: 'ورقة قرآن 🕋', nameEn: 'One page of Quran',
        iconIndex: 1, target: 1, unit: 'صفحة'),
      PackHabit(nameAr: 'أذكار الصبح 🌅', nameEn: 'Morning dhikr', iconIndex: 3),
      PackHabit(nameAr: 'إقلاع عن السهر 📵', nameEn: 'Quit late-night scrolling',
        iconIndex: 6, isQuit: true),
    ],
  ),
];

// ---------- Daily challenge ----------

class ChallengeSystem {
  static const _names = [
    'kill_it', 'noon', 'measurable', 'streak', 'combo', 'earlybird'
  ];

  static ({String id, String title, String desc, int target, int xp}) today(
      List<Habit> habits) {
    final now = clock();
    final dayIdx =
        (now.year * 372 + now.month * 31 + now.day) % _names.length;
    final measurable =
        habits.where((h) => h.isMeasurable && h.isDueOn(now)).toList();
    final dueToday = habits.where((h) => h.isDueOn(now)).length;

    switch (dayIdx) {
      case 1:
        return measurable.isNotEmpty
            ? (id: 'measurable', title: t('حقّق هدفك 🎯', 'Hit your goal 🎯'),
                desc: t('صل لهدفك في "${iso(measurable.first.name)}" اليوم.',
                    'Hit your "${measurable.first.name}" goal today.'),
                target: 1, xp: 60)
            : (id: 'kill_it', title: t('أنهِ كل شيء اليوم ⚡', 'Finish everything today ⚡'),
                desc: t('أنجز كل عادة مطلوبة اليوم.',
                    'Complete every required habit today.'),
                target: dueToday, xp: 80);
      case 2:
        return (id: 'combo', title: t('كومبو مزدوج 🔥', 'Double combo 🔥'),
            desc: t('أنجز عادتين مختلفتين اليوم.',
                'Complete two different habits today.'),
            target: 2, xp: 50);
      case 3:
        return (id: 'noon', title: t('قبل الظهر ☀️', 'Before noon ☀️'),
            desc: t('أنجز عادة قبل الساعة 12:00.',
                'Complete a habit before 12:00.'),
            target: 1, xp: 45);
      case 4:
        return (id: 'streak', title: t('في انطلاق 🌀', 'Keep it going 🌀'),
            desc: t('أنجز اليوم لتبقي سلسلتك حيّة.',
                'Complete today to keep your streak alive.'),
            target: 1, xp: 40);
      case 5:
        return (id: 'earlybird', title: t('طائر مبكر 🐦', 'Early bird 🐦'),
            desc: t('أنجز عادة قبل الساعة 10:00.',
                'Complete a habit before 10:00.'),
            target: 1, xp: 45);
      default:
        return (id: 'kill_it', title: t('أنهِ كل شيء اليوم ⚡', 'Finish everything today ⚡'),
            desc: t('أنجز كل عادة مطلوبة اليوم.',
                'Complete every required habit today.'),
            target: dueToday, xp: 80);
    }
  }

  static String _key(String date) => 'challenge_${AuthService.email}_$date';

  static Future<bool> isClaimed(String date) async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_key(date)) ?? '').startsWith('done|');
  }

  static Future<int> progress(List<Habit> habits, String id) async {
    final now = clock();
    switch (id) {
      case 'kill_it':
        final done = habits.where((h) => h.isDueOn(now) && h.isDoneOn(now)).length;
        return done;
      case 'combo':
        return habits.where((h) => h.isDueOn(now) && h.isDoneOn(now)).length;
      case 'measurable':
        return habits.any((h) => h.isMeasurable && h.isDoneOn(now)) ? 1 : 0;
      case 'noon':
        return habits.any((h) => h.isDoneOn(now) &&
            (h.doneTimeOn(now)?.hour ?? 24) < 12)
            ? 1 : 0;
      case 'streak':
        return habits.any((h) => h.isDueOn(now) && h.isDoneOn(now)) ? 1 : 0;
      case 'earlybird':
        return habits.any((h) => h.isDoneOn(now) &&
            (h.doneTimeOn(now)?.hour ?? 24) < 10)
            ? 1 : 0;
      default:
        return 0;
    }
  }

  static Future<({bool done, int xp, bool leveled})> maybeComplete(
      List<Habit> habits, String id, int target, int xp) async {
    final date = dayKey(clock());
    if (await isClaimed(date)) return (done: true, xp: 0, leveled: false);
    // A target of 0 (no habits due today) must not count as "completed".
    if (target <= 0) return (done: false, xp: 0, leveled: false);
    final prog = await progress(habits, id);
    if (prog < target) return (done: false, xp: 0, leveled: false);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(date), 'done|$id');
    final res = await XpSystem.add(xp);
    return (done: true, xp: xp, leveled: res.leveledUp);
  }
}

// ---------- Notifications helpers ----------

String? notificationPayloadForHabit(Habit h) => 'mark_done|${h.id}';

class RatingService {
  static bool _promptedInSession = false;

  static Future<void> maybePrompt(BuildContext context,
      {required int count, required int habits}) async {
    if (_promptedInSession || count < 10 || habits == 0) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool('rating_done') ?? false) return;
    final last = p.getInt('rating_last_prompt') ?? 0;
    if (clock().millisecondsSinceEpoch - last <
        30 * 24 * 3600 * 1000) {
      return;
    }
    _promptedInSession = true;
    await p.setInt('rating_last_prompt', clock().millisecondsSinceEpoch);
    if (!context.mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(ctx).brightness),
        title: Text(t('هل تستمتع بـ HabitFlow؟ 💙', 'Enjoying HabitFlow? 💙')),
        content: Text(
            t('تقييمك السريع يساعد الآخرين على اكتشاف عادات أفضل أيضاً!',
                'Your quick rating helps others discover better habits too!')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: Text(t('لاحقاً', 'Later')),
          ),
          TextButton(
            onPressed: () {
              p.setBool('rating_done', true);
              Navigator.pop(ctx, 'never');
            },
            child: Text(t('لا شكراً', 'No thanks')),
          ),
          FilledButton(
            onPressed: () {
              p.setBool('rating_done', true);
              Navigator.pop(ctx, 'rate');
            },
            child: Text(t('قيّم الآن ⭐', 'Rate now ⭐')),
          ),
        ],
      ),
    );
    if (result == 'rate') {
      const uri =
          'https://play.google.com/store/apps/details?id=com.novu.HabitFlow';
      try {
        await launchUrl(Uri.parse(uri),
            mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onStatsChanged, this.onNavigate});

  static VoidCallback? reload;

  final ValueChanged<List<Habit>>? onStatsChanged;
  final ValueChanged<int>? onNavigate;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Habit> habits = [];
  ({String id, String title, String desc, int target, int xp})? _challenge;
  int _challengeProg = 0;
  bool _challengeClaimed = false;
  int? _moodToday;
  int _moodStreak = 0;
  List<String> _insights = const [];

  @override
  void initState() {
    super.initState();
    HomePage.reload = _loadHabits;
    // Extras (daily challenge, insights) depend on the habit list, so build
    // them only after the habits are loaded.
    _loadHabits().then((_) => _loadExtras());
    _refreshXp();
    NotificationService.init();
  }

  Future<void> _loadExtras() async {
    final chal = ChallengeSystem.today(habits);
    final prog = await ChallengeSystem.progress(habits, chal.id);
    final claimed = await ChallengeSystem.isClaimed(dayKey(clock()));
    final mood = await MoodSystem.todayMood();
    final moodStreak = await MoodSystem.goodMoodStreak();
    if (mounted) {
      setState(() {
        _challenge = chal;
        _challengeProg = prog;
        _challengeClaimed = claimed;
        _moodToday = mood;
        _moodStreak = moodStreak;
        _insights = buildInsights(habits);
      });
    }
  }

  Future<void> _loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('habits') ?? '[]';
    final list = (jsonDecode(raw) as List)
        .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    if (mounted) setState(() => habits = list);
    widget.onStatsChanged?.call(list);
    for (final h in list) {
      if (h.reminderEnabled && h.reminderHour != null) {
        NotificationService.scheduleHabit(h);
      } else {
        NotificationService.cancelHabit(h.id);
      }
    }
  }

  Future<void> _saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'habits', jsonEncode(habits.map((h) => h.toMap()).toList()));
    refreshWidget();
    widget.onStatsChanged?.call(habits);
    _loadExtras();
  }

  void _deleteHabit(int index) {
    NotificationService.cancelHabit(habits[index].id);
    setState(() => habits.removeAt(index));
    _saveHabits();
  }

  void _showAddDialog() {
    if (!AuthService.isProUser && habits.length >= FreePlan.maxHabits) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cardColor(Theme.of(context).brightness),
          title: Text(t('وصلت لحد الإصدار المجاني 🚧', 'You hit the free limit 🚧')),
          content: Text(t(
              'النسخة المجانية تسمح حتى ${FreePlan.maxHabits} عادات.\n\nرقّي إلى برو لعادات غير محدودة وبلا إعلانات والمزيد.',
              'The free version allows up to ${FreePlan.maxHabits} habits.\n\nUpgrade to Pro for unlimited habits, no ads and more.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('لاحقاً', 'Later')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProPage()));
              },
              child: Text(t('رقّي', 'Upgrade')),
            ),
          ],
        ),
      );
      return;
    }
    showHabitDialog(context,
        measurableInUse: habits.where((h) => h.isMeasurable).length,
        onSave: (habit) {
      _addHabit(habit);
    });
  }

  Future<void> _toggleToday(Habit habit) async {
    final now = clock();
    final today = dayKey(now);
    if (habit.isMeasurable) {
      await _recordAmount(habit);
      return;
    }
    if (habit.isTimerHabit) {
      await _startTimer(habit);
      return;
    }
    final completing = !habit.isDoneOn(now);
    setState(() {
      if (completing) {
        habit.completedDates.add(today);
        habit.setDoneAt(now);
      } else {
        habit.completedDates.remove(today);
        habit.setDoneAt(now, remove: true);
      }
    });
    _saveHabits();
    if (completing) await _afterComplete(habit, now);
  }

  Future<void> _afterComplete(Habit habit, DateTime now) async {
    final comeback = habit.isComebackOn(now);
    await _award(habit);
    final dueNow = habits.where((h) => h.isDueOn(now));
    final perfectDay =
        dueNow.isNotEmpty && dueNow.every((h) => h.isDoneOn(now));
    if (comeback) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t(
                '💛 عودة! رجعت لـ"${iso(habit.name)}" — ودي تُحسب كإنجاز.',
                '💛 Comeback! You came back to "${habit.name}" — counted as a win.')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1800),
          ),
        );
      }
    } else {
      _cheer();
    }
    if (perfectDay && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('🎉 يوم مثالي! أنهيت كل عاداتك!',
              '🎉 Perfect day! You completed all your habits!')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
    await _checkMilestones();
    if (mounted) {
      await RatingService.maybePrompt(context,
          count: _totalCompletions, habits: habits.length);
    }
  }

  Future<void> _startTimer(Habit habit) async {
    final now = DateTime.now();
    if (habit.isDoneOn(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('أنجزت "${iso(habit.name)}" اليوم بالفعل ✅',
                'Already completed "${habit.name}" today ✅')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final finished = await showDialog<bool>(
      context: context,
      builder: (ctx) => HabitTimerDialog(habit: habit),
    );
    if (finished != true || !mounted) return;
    setState(() {
      habit.completedDates.add(dayKey(now));
      habit.setDoneAt(now);
    });
    _saveHabits();
    await _afterComplete(habit, now);
  }

  Future<void> _recordAmount(Habit habit) async {
    final now = clock();
    final today = dayKey(now);
    final recorded = habit.amountOn(now);
    final remaining = habit.target - recorded;
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        title: Text(t('سجّل "${iso(habit.name)}"', 'Log "${habit.name}"')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(
                'اليوم: ${ltr('${_fmt(recorded)} / ${_fmt(habit.target)}')}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
                'Today: ${_fmt(recorded)} / ${_fmt(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: softInputDecoration(
                ctx,
                label: t(
                    'الكمية (${habit.unit.isEmpty ? 'وحدة' : habit.unit})',
                    'Amount (${habit.unit.isEmpty ? 'unit' : habit.unit})'),
                hint: remaining > 0
                    ? t('مثال: ${_fmt(remaining)}',
                        'Example: ${_fmt(remaining)}')
                    : t('تريد المزيد؟', 'Want more?'),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final q in [1.0, 2.0, 5.0, 10.0])
                  ActionChip(
                    label: Text(ltr('+${_fmt(q)}')),
                    onPressed: () => Navigator.pop(ctx, q),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, double.tryParse(controller.text.trim()));
            },
            child: Text(t('إضافة', 'Add')),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    final wasDone = habit.isDoneOn(now);
    setState(() {
      habit.amounts[today] = (habit.amounts[today] ?? 0) + result;
      if (habit.isDoneOn(now) && !wasDone) habit.setDoneAt(now);
    });
    _saveHabits();
    if (!wasDone && habit.isDoneOn(now)) {
      await _award(habit);
      await _checkMilestones();
    }
    if (mounted) {
      await RatingService.maybePrompt(context,
          count: _totalCompletions, habits: habits.length);
    }
  }

  static final _cheersAr = [
    'رائع! 💪',
    'تمام! ✅',
    'واصل! ⚡',
    'أنجزتها! 🔥',
    'خطوة أقرب! 🚀',
    'أسطورة! 👑',
  ];

  static final _cheersEn = [
    'Awesome! 💪',
    'Nice! ✅',
    'Keep going! ⚡',
    'Done! 🔥',
    'One step closer! 🚀',
    'Legend! 👑',
  ];

  void _cheer() {
    if (!mounted) return;
    final idx = clock().millisecondsSinceEpoch % _cheersEn.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Language.isAr ? _cheersAr[idx] : _cheersEn[idx]),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _award(Habit habit) async {
    const streakBonus = {7: 50, 30: 150, 100: 500, 365: 2000};
    final streak = habit.currentStreak();
    final bonus = streakBonus[streak] ?? 0;
    final res = await XpSystem.addOnce('habit|${habit.id}', 10 + bonus);
    await _refreshXp();
    if (!mounted || !res.awarded) return;
    if (res.leveledUp) {
      _showLevelUp(res.level);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bonus > 0
              ? t('🔥 سلسلة ${daysAr(streak)}! ${ltr('+${10 + bonus} XP')}',
                  '🔥 $streak-day streak! +${10 + bonus} XP')
              : '+10 XP ⚡'),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setMood(int mood) async {
    final earned = await MoodSystem.save(mood);
    await _loadExtras();
    await _refreshXp();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(earned
            ? t('أجواء رائعة اليوم ${ltr('+5 XP')} ✨', 'Great mood today +5 XP ✨')
            : t('شكراً لتفاعلك معنا 💛', 'Thanks for sharing 💛')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _refreshXp() async {
    final data = await XpSystem.load();
    if (mounted) {
      setState(() {
        _xp = data.xp;
        _level = data.level;
      });
    }
  }

  Future<void> _checkMilestones() async {
    final newly =
        await BadgeSystem.evaluate(habits, _level, _xp, awardXp: false);
    for (final _ in newly) {
      await XpSystem.add(25);
    }
    await _refreshXp();
    await _loadExtras();
    final challenge = ChallengeSystem.today(habits);
    final res = await ChallengeSystem.maybeComplete(
        habits,
        challenge.id,
        challenge.target,
        // Pro doubles the daily challenge reward.
        AuthService.isProUser ? challenge.xp * 2 : challenge.xp);
    if (res.done) await _loadExtras();
    if (!mounted) return;
    if (newly.isNotEmpty) _showBadgeUnlocked(newly);
    if (res.done && res.xp > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('🎯 اكتمل التحدي اليومي! ${ltr('+${res.xp} XP')}',
            '🎯 Daily challenge completed! +${res.xp} XP')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1800),
        ),
      );
    }
  }

  void _showBadgeUnlocked(List<Badge> badges) {
    final b = badges.first;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cardColor(Theme.of(context).brightness),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(b.icon, size: 52, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(t('تم فتح شارة!', 'Badge unlocked!'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(b.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(b.desc,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(t('رائع ${ltr('+25 XP')}', 'Awesome +25 XP')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLevelUp(int level) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cardColor(Theme.of(context).brightness),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(t('المستوى $level!', 'Level $level!'),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(t('الانضباط الحقيقي له مستوى جديد. استمر!',
                    'True discipline has a new level. Keep going!'),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Builder(builder: (_) {
                  final xpIn = XpSystem.xpInLevel(_xp);
                  final need = XpSystem.xpToNextLevel(_xp);
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: (xpIn / need).clamp(0, 1),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 6),
                      Text(t('${ltr('$xpIn / $need XP')} حتى المستوى التالي',
                          '$xpIn / $need XP to the next level'),
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                    ],
                  );
                }),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
child: Text(t('رائع!', 'Awesome!')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _xp = 0;
  int _level = 1;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  int get _totalCompletions {
    var t = 0;
    for (final h in habits) {
      t += h.countCompletions();
    }
    return t;
  }

  void _addHabit(Habit habit) {
    setState(() => habits.add(habit));
    _saveHabits();
    NotificationService.scheduleHabit(habit);
  }

  double get todayProgress {
    final due = habits.where((h) => h.isDueOn(clock())).toList();
    if (due.isEmpty) return 0;
    final done = due.where((h) => h.isDoneOn(clock())).length;
    return done / due.length;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    final brightness = Theme.of(context).brightness;
    final now = clock();
    final quote = quoteFor(now);

    final dueToday = habits.where((h) => h.isDueOn(now)).toList();
    final done = dueToday.where((h) => h.isDoneOn(now)).length;
    final dueCount = dueToday.length;
    String headline;
    String sub;
    if (habits.isEmpty) {
      headline = t('جاهز تبني يومك؟ 💪', 'Ready to build your day? 💪');
      sub = t('أضف أول عادة وابدأ صغيراً.', 'Add your first habit and start small.');
    } else if (dueCount == 0) {
      headline = t('يوم راحة 🌿', 'Rest day 🌿');
      sub = t('لا توجد عادات مطلوبة اليوم.', 'No habits are due today.');
    } else if (done == 0) {
      headline = t("لنُنجز اليوم 💪", "Let's get it done today 💪");
      sub = t('انتهيت من $done من $dueCount عادات حتى الآن.',
          'Finished $done of $dueCount habits so far.');
    } else if (done < dueCount) {
      headline = t("أنت على نار 🔥", "You're on fire 🔥");
      sub = t('انتهيت من $done من $dueCount عادات. استمر!',
          'Finished $done of $dueCount habits. Keep going!');
    } else {
      headline = t('يوم مثالي! 🎉', 'Perfect day! 🎉');
      sub = t('أنهيت كل الـ $dueCount عادات. لا أحد يوقفك!',
          'You completed all $dueCount habits. Nothing stops you!');
    }
    final greeting = now.hour < 12
        ? t('صباح الخير', 'Good morning')
        : now.hour < 18
            ? t('مساء الخير', 'Good afternoon')
            : t('مساء الخير', 'Good evening');

    return Scaffold(
      body: SafeArea(
        child: ListView(
          // Extra bottom space so the floating + button never covers the
          // last habit card.
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
          children: [
            Row(
              children: [
                Image.asset(
                  brightness == Brightness.dark
                      ? 'assets/icon/logo_white.png'
                      : 'assets/icon/logo_black.png',
                  height: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '$greeting${t('،', ',')} ${iso(AuthService.name ?? t('صديقي', 'friend'))} 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 14)),
                      ShaderMask(
                        shaderCallback: (rect) => LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.tertiary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(rect),
                        blendMode: BlendMode.srcIn,
                        child: Text(t('عاداتك', 'Your habits'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        final nav = widget.onNavigate;
                        if (nav != null) {
                          nav(1);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StatsPage(habits: habits),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.bar_chart, size: 26),
                      tooltip: t('الإحصائيات', 'Stats'),
                    ),
                    IconButton(
                      onPressed: () {
                        final nav = widget.onNavigate;
                        if (nav != null) {
                          nav(2);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsPage(),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.settings, size: 26),
                      tooltip: t('الإعدادات', 'Settings'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary.withAlpha(46), primary.withAlpha(16)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: primary.withAlpha(60)),
              ),
              child: Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: todayProgress),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => SizedBox(
                      width: 92,
                      height: 92,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 92,
                            height: 92,
                            child: CircularProgressIndicator(
                              value: t,
                              strokeWidth: 10,
                              strokeCap: StrokeCap.round,
                              backgroundColor: secondaryColor(brightness),
                              color: primary,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${(todayProgress * 100).round()}%',
                                  style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                      color: primary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headline,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                height: 1.3)),
                        const SizedBox(height: 5),
                        Text(sub,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                                height: 1.35)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: primary.withAlpha(28),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withAlpha(70)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: primary.withAlpha(45),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$_level',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('المستوى $_level — إجمالي ${ltr('$_xp XP')}',
        'Level $_level — $_xp total XP'),
    style: const TextStyle(
        fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (XpSystem.xpInLevel(_xp) /
                                      XpSystem.xpToNextLevel(_xp))
                                  .clamp(0.0, 1.0),
                              minHeight: 8,
                              backgroundColor: secondaryColor(brightness),
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('${ltr('${XpSystem.xpInLevel(_xp)} / ${XpSystem.xpToNextLevel(_xp)} XP')} حتى المستوى التالي',
                                '${XpSystem.xpInLevel(_xp)} / ${XpSystem.xpToNextLevel(_xp)} XP to next level'),
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor(brightness),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withAlpha(55)),
                ),
                child: _challenge == null
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.flag_circle, color: primary, size: 20),
                              const SizedBox(width: 8),
Text(t('التحدي اليومي', 'Daily challenge'),
    style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold)),
const Spacer(),
if (_challengeClaimed)
  Container(
    padding: const EdgeInsets.symmetric(
        horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.green.withAlpha(35),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(t('منجز ✓', 'Done ✓'),
        style: const TextStyle(
            fontSize: 11,
            color: Colors.green,
            fontWeight: FontWeight.bold)),
  ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(_challenge!.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(_challenge!.desc,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _challengeClaimed
                                        ? 1
                                        : _challenge!.target == 0
                                            ? 0
                                            : (_challengeProg /
                                                    _challenge!.target)
                                                .clamp(0.0, 1.0),
                                    minHeight: 8,
                                    backgroundColor: secondaryColor(brightness),
                                    color: primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Once claimed the challenge stays complete,
                              // even if a habit is unchecked later today.
                              Text(
                                  _challengeClaimed
                                      ? '${max(_challenge!.target, 1)}/${max(_challenge!.target, 1)}'
                                      : '$_challengeProg/${_challenge!.target}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor(brightness),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mood, color: primary, size: 20),
                        const SizedBox(width: 8),
                        Text(t('كيف تشعر اليوم؟', 'How do you feel today?'),
    style: const TextStyle(
        fontSize: 14, fontWeight: FontWeight.bold)),
const Spacer(),
if (_moodStreak >= 2)
  Text('🔥 ${daysLabel(_moodStreak)}',
      style: TextStyle(
          fontSize: 12, color: Colors.deepOrange)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var m = 1; m <= 5; m++)
                          GestureDetector(
                            onTap: () => _setMood(m),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _moodToday == m
                                    ? primary.withAlpha(45)
                                    : Colors.transparent,
                                border: _moodToday == m
                                    ? Border.all(color: primary, width: 2)
                                    : null,
                              ),
                              child: Text(const ['😞', '😐', '🙂', '😀', '🤩']
                                  [m - 1]),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Insights are Pro-only; skip their spacing too so Free has no
              // doubled gap before the quote card.
              if (AuthService.isProUser && _insights.isNotEmpty)
                const SizedBox(height: 12),
              if (AuthService.isProUser && _insights.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor(brightness),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: primary, size: 20),
                          const SizedBox(width: 8),
                          Text(t('رؤى ذكية', 'Smart insights'),
    style: const TextStyle(
        fontSize: 14, fontWeight: FontWeight.bold)),
const Spacer(),
Text(t('محلي · خاص', 'Local · private'),
    style: TextStyle(
        fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final s in _insights)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(s,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor(brightness),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote, color: primary, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    quote.text,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '— ${quote.author}',
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (habits.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(
                    children: [
                      Icon(Icons.emoji_events_outlined,
                          size: 80, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      Text(t('لا توجد عادات بعد', 'No habits yet'),
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text(t('الخطوات الصغيرة كل يوم تصنع نتائج كبيرة.',
                          'Small daily steps create big results.'),
                          style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _showAddDialog,
                        icon: const Icon(Icons.add),
                        label: Text(t('أنشئ أول عادة لك', 'Create your first habit')),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...habits.asMap().entries.map((entry) {
                final i = entry.key;
                final habit = entry.value;
                final done = habit.isDoneOn(clock());
                final streak = habit.currentStreak();
                final amount = habit.amountOn(clock());
                final onDone = Theme.of(context).colorScheme.onPrimary;
                final onDoneSoft = onDone.withAlpha(200);
                return Dismissible(
                  key: ValueKey(habit.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: AlignmentDirectional.centerEnd,
                    padding: const EdgeInsetsDirectional.only(end: 20),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(77),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  onDismissed: (_) => _deleteHabit(i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      gradient: done
                          ? LinearGradient(
                              colors: [primary, tertiary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight)
                          : brightness == Brightness.dark
                              ? const LinearGradient(colors: [
                                  Color(0xFF1C222B),
                                  Color(0xFF161B22)
                                ])
                              : LinearGradient(colors: [
                                  Colors.white,
                                  primary.withAlpha(10)
                                ]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: done
                            ? Colors.white.withAlpha(80)
                            : primary.withValues(
                                alpha:
                                    brightness == Brightness.dark ? 0.30 : 0.10),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(
                              alpha: brightness == Brightness.dark
                                  ? 0.16
                                  : 0.14),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HabitDetailPage(
                              habit: habit,
                              onUpdate: (h) {
                                setState(() => habits[i] = h);
                                _saveHabits();
                                NotificationService.scheduleHabit(h);
                              },
                              onDelete: () => _deleteHabit(i),
                            ),
                          ),
                        );
                      },
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: done
                                ? [Colors.white.withAlpha(100), Colors.white.withAlpha(40)]
                                : [primary, primary.withAlpha(180)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: done
                              ? null
                              : [
                                  BoxShadow(
                                    color: primary.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Icon(habit.icon,
                            color: done ? onDone : Colors.white, size: 26),
                      ),
                      title: Text(
                        habit.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                          color: done ? onDone : null,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (habit.isMeasurable)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: habit.target > 0
                                            ? (amount / habit.target)
                                                .clamp(0.0, 1.0)
                                            : 0,
                                        minHeight: 8,
                                        backgroundColor: done
                                            ? onDone.withAlpha(50)
                                            : secondaryColor(brightness),
                                        color: done
                                            ? onDone
                                            : primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${ltr('${_fmt(amount)}/${_fmt(habit.target)}')}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
                                    style: TextStyle(
                                        color: done
                                            ? onDone
                                            : primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  if (streak > 0) ...[
                                    if (done) ...[
                                      Icon(
                                          Icons.local_fire_department,
                                          color: onDoneSoft,
                                          size: 14),
                                      const SizedBox(width: 3),
                                      Text(
                                          daysLabel(streak),
                                          style: TextStyle(
                                              color: onDoneSoft,
                                              fontSize: 11)),
                                      const SizedBox(width: 8),
                                    ] else ...[
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 3),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFFFF9800),
                                                Color(0xFFFF5722)
                                              ]),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons
                                                      .local_fire_department,
                                                  color: Colors.white,
                                                  size: 14),
                                              const SizedBox(width: 4),
                                              Text(
                                                  daysLabel(streak),
                                                  style: const TextStyle(
                                                      color:
                                                          Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold)),
                                            ]),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ],
                                  if (!done &&
                                      streak == 0 &&
                                      habit.longestStreak() > 0) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFB74D)
                                            .withAlpha(40),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: const Color(0xFFFFB74D)
                                                .withAlpha(170)),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.wb_twilight,
                                                size: 13,
                                                color: Color(0xFFFFB74D)),
                                            const SizedBox(width: 4),
                                            Text(
                                                t(
                                                    'أفضل سلسلة ${habit.longestStreak()} · أعد الإشعال',
                                                    'Best run ${habit.longestStreak()} · relight today'),
                                                style: const TextStyle(
                                                    color: Color(0xFFFFB74D),
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ]),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (habit.isTimerHabit) ...[
                                    Text(
                                        '⏱ ${habit.timerMinutes} ${t('دقيقة', 'min')}',
                                        style: TextStyle(
                                            color: done
                                                ? onDoneSoft
                                                : Colors.grey.shade500,
                                            fontSize: 11)),
                                    const SizedBox(width: 8),
                                  ],
                                  if (habit.isWeekly &&
                                      habit.weekdays.length < 7)
                                    Text(_weekdayShort(habit.weekdays),
                                        style: TextStyle(
                                            color: done
                                                ? onDoneSoft
                                                : Colors.grey.shade500,
                                            fontSize: 11)),
                                  if (habit.isFlexible)
                                    Text(
                                        t(
                                            '${habit.timesPerWeek}x/أسبوع',
                                            '${habit.timesPerWeek}x/week'),
                                        style: TextStyle(
                                            color: done
                                                ? onDoneSoft
                                                : Colors.grey.shade500,
                                            fontSize: 11)),
                                  if (habit.isQuit &&
                                      !habit.isMeasurable)
                                    Text(
                                        streak > 0
                                            ? '🍃 ${t('أنظف', 'Clean')} · ${daysLabel(streak)}'
                                            : t('حافظ على نظافتها',
                                                'Keep it clean'),
                                        style: TextStyle(
                                            color: done
                                                ? onDoneSoft
                                                : Colors.grey.shade500,
                                            fontSize: 11)),
                                  if (habit.reminderEnabled) ...[
                                    const SizedBox(width: 10),
                                    Icon(
                                        Icons
                                            .notifications_active_outlined,
                                        size: 14,
                                        color: done
                                            ? onDoneSoft
                                            : Colors.grey.shade500),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                      trailing: GestureDetector(
                        onTap: () => habit.isTimerHabit
                            ? _startTimer(habit)
                            : _toggleToday(habit),
                        child: habit.isMeasurable
                            ? AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 220),
                                height: 42,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14),
                                decoration: BoxDecoration(
                                  gradient: done
                                      ? null
                                      : LinearGradient(
                                          colors: [primary, tertiary],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight),
                                  color: done ? Colors.white : null,
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  boxShadow: done
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: primary.withValues(
                                                alpha: 0.4),
                                            blurRadius: 10,
                                            offset:
                                                const Offset(0, 4),
                                          ),
                                        ],
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      done
                                          ? Icon(Icons.check_circle,
                                              color: primary,
                                              size: 26)
                                          : habit.isTimerHabit
                                              ? Icon(
                                                  Icons.play_circle_fill,
                                                  color: primary,
                                                  size: 28)
                                              : Row(children: [
                                                  Icon(Icons.add,
                                                      size: 16,
                                                      color:
                                                          Colors.white),
                                                  const SizedBox(
                                                      width: 4),
                                                  Text(t('إضافة', 'Add'),
                                                  style: const TextStyle(
                                                      color: Colors
                                                          .white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold)),
                                            ]),
                                    ]),
                              )
                            : AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 220),
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: done
                                      ? LinearGradient(
                                          colors: [
                                            Colors.white,
                                            Colors.white
                                                .withAlpha(220)
                                          ])
                                      : null,
                                  color:
                                      done ? null : Colors.transparent,
                                  border: Border.all(
                                    color: done
                                        ? Colors.white.withAlpha(180)
                                        : primary,
                                    width: 2.2,
                                  ),
                                  boxShadow: done
                                      ? [
                                          BoxShadow(
                                            color: Colors.white
                                                .withValues(
                                                    alpha: 0.35),
                                            blurRadius: 10,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: done
                                    ? Icon(Icons.check,
                                        color: primary, size: 24)
                                    : Icon(Icons.check,
                                        color: primary
                                            .withAlpha(120),
                                        size: 22),
                              ),
                      ),
                    ),
                  ),
),
            );
          }),
            const SizedBox(height: 20),
          ],
        ),
      ),
      // The gradient and shadow live on a plain circular Container; a
      // rectangular Material around an Ink clipped the shadow into a square.
      floatingActionButton: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.tertiary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.32),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _showAddDialog,
            child: Icon(Icons.add,
                color: Theme.of(context).colorScheme.onPrimary, size: 30),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  List<Habit> _statsHabits = [];
  int _refreshTick = 0;

  void _onStatsChanged(List<Habit> habits) {
    if (mounted) setState(() => _statsHabits = List.of(habits));
  }

  void _goToTab(int index) {
    if (index == 1) setState(() => _refreshTick++);
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(
            onStatsChanged: _onStatsChanged,
            onNavigate: _goToTab,
          ),
          StatsPage(habits: _statsHabits, refreshTick: _refreshTick),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _BottomNavBar(selectedIndex: _index, onSelect: _goToTab),
      ),
    );
  }
}

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      adUnitId: 'ca-app-pub-7463001555516394/3182260121',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _banner = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reserve no space until an ad has actually loaded.
    if (_banner == null || !_loaded) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C2127)
          : Colors.white,
      width: double.infinity,
      alignment: Alignment.center,
      height: 52,
      child: AdWidget(ad: _banner!),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <({IconData icon, IconData selectedIcon, String label})>[
      (
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: t('الرئيسية', 'Home'),
      ),
      (
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart_rounded,
        label: t('الإحصائيات', 'Stats'),
      ),
      (
        icon: Icons.tune_rounded,
        selectedIcon: Icons.tune_rounded,
        label: t('الإعدادات', 'Settings'),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xE6141A23) : const Color(0xEDFFFFFF),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
            color: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.12)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _NavItem(
                icon: items[i].icon,
                selectedIcon: items[i].selectedIcon,
                label: items[i].label,
                active: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          // Must not overshoot: decoration tweens are only valid for t in
          // [0, 1]. easeOutBack pushed t past 1 while a tab was being
          // deselected, scaling the shadow blur negative and throwing
          // ("Text shadow blur radius should be non-negative"), which
          // flashed a red error widget in the nav bar on every tab switch.
          curve: Curves.easeOutCubic,
          height: 58,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(24),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? selectedIcon : icon,
                color: active ? Colors.white : scheme.onSurfaceVariant,
                size: 22,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: active
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Text(
                          label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProPage extends StatefulWidget {
  const ProPage({super.key});

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> {
  ProPlan _selected = ProPlan.yearly;
  bool _loading = true;
  bool _busy = false;

  ProductDetails? get _pro => BillingService.instance.product(_selected);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await BillingService.instance.ensureProducts();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _buy() async {
    if (_busy) { return; }
    setState(() => _busy = true);
    final outcome = await BillingService.instance.buy(_selected);
    if (!mounted) { return; }
    setState(() => _busy = false);
    switch (outcome) {
      case BillingOutcome.granted:
        _welcomeDialog();
        break;
      case BillingOutcome.pending:
        _snack(t('الدفع قيد المراجعة…', 'Payment pending review…'));
        break;
      case BillingOutcome.canceled:
        _snack(t('تم إلغاء الدفع.', 'Purchase canceled.'));
        break;
      case BillingOutcome.unavailable:
        _snack(t('الدفع غير متاح على هذا الجهاز الآن.',
            'Billing is not available on this device right now.'));
        break;
      case BillingOutcome.noProduct:
        _snack(t('لم يتم إعداد المنتج في المتجر بعد.',
            'The store product is not configured yet.'));
        break;
      default:
        _snack(t('حدث خطأ في عملية الدفع، حاول مجدداً.',
            'Something went wrong. Please try again.'));
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _restore() async {
    if (_busy) { return; }
    setState(() => _busy = true);
    final outcome = await BillingService.instance.restore();
    if (!mounted) { return; }
    setState(() => _busy = false);
    if (outcome == BillingOutcome.granted) {
      _welcomeDialog();
    } else {
      _snack(t('لا يوجد اشتراك أو شراء فعّال قابل للاستعادة.',
          'No active subscription or purchase to restore.'));
    }
  }

  Future<void> _downgrade() async {
    if (_busy) { return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(ctx).brightness),
        title: Text(t('الرجوع للنسخة المجانية؟', 'Back to the free version?')),
        content: Text(t(
            'ستفقد ميزات برو وستعود الإعلانات في التطبيق. إن كان الاشتراك مفعّلاً عبر Google Play، ألغِ تفعيله من تطبيق Play أولاً حتى لا يتجدّد.',
            'You will lose Pro features and ads will come back. If your subscription is active through Google Play, cancel it in the Play app first so it does not renew.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('تأكيد الرجوع', 'Confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) { return; }
    setState(() => _busy = true);
    await AuthService.setPro(false);
    if (!mounted) { return; }
    HabitFlowApp.of(context)?.refreshPro();
    _snack(t('رجعت للنسخة المجانية ✅', 'You are back to the free version ✅'));
    Navigator.pop(context);
  }

  Future<void> _welcomeDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(ctx).brightness),
        title: const Text('HabitFlow Pro'),
        content: Text(t(
            'أهلاً بك في برو! جميع ميزات برو مفعّلة الآن.',
            'Welcome to Pro! All Pro features are now enabled.')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) { Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;

    // Keep this list in sync with FreePlan and the AuthService.isProUser checks.
    final features = [
      (Icons.all_inclusive, t('عادات غير محدودة', 'Unlimited habits'),
          t('المجاني حتى ${FreePlan.maxHabits} عادات، وبرو من غير حد',
              'Free allows ${FreePlan.maxHabits} habits, Pro has no limit')),
      (Icons.block, t('بلا إعلانات', 'No ads'),
          t('إزالة الإعلان من الإحصائيات والإعدادات',
              'Remove the banner from Stats and Settings')),
      (Icons.insights, t('تحليلات متقدمة', 'Advanced analytics'),
          t('آخر 12 شهراً، خرائط النشاط، أفضل يوم، ورؤى ذكية',
              'Last 12 months, activity heatmaps, best day and smart insights')),
      (Icons.straighten, t('قياس ومؤقت بلا حد', 'Unlimited measurable & timer habits'),
          t('المجاني عادة واحدة قابلة للقياس، وبرو بلا حد، ومعاها العدّاد التنازلي',
              'Free includes one measurable habit; Pro removes the limit and adds the countdown timer')),
      (Icons.emoji_events, t('كل الشارات و XP مضاعف', 'All badges & double challenge XP'),
          t('${FreePlan.badgeIds.length} شارات في المجاني، وكل الشارات في برو، ومكافأة التحدي اليومي مضاعفة',
              '${FreePlan.badgeIds.length} badges on Free, all of them on Pro, and double daily-challenge XP')),
      (Icons.palette, t('تخصيص كامل', 'Full customisation'),
          t('مكتبة الأيقونات الكاملة ولون مخصص للتطبيق',
              'The full icon library and a custom app colour')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('HabitFlow Pro'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              // The dark-mode primary is a light pastel; darken it so the
              // white hero text and logo stay readable.
              gradient: LinearGradient(
                colors: brightness == Brightness.dark
                    ? [
                        Color.lerp(primary, Colors.black, 0.45)!,
                        Color.lerp(primary, Colors.black, 0.25)!,
                      ]
                    : [primary, primary.withAlpha(150)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                // White text sits on the primary gradient, so the logo is
                // always the white variant.
                Image.asset(
                  'assets/icon/logo_white.png',
                  height: 70,
                ),
                const SizedBox(height: 12),
                Text(t('كن برو', 'Go Pro'),
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(t('افتح كل ما تقدمه HabitFlow',
                    'Unlock everything HabitFlow offers'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withAlpha(230))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...features.map((f) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor(brightness),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(f.$1, color: primary, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.$2,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(f.$3,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary, width: 2),
            ),
            child: Column(
              children: [
                const Text('HabitFlow Pro',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                if (!AuthService.isProUser) ...[
                  const SizedBox(height: 14),
                  for (final plan in ProPlan.values)
                    _PlanTile(
                      plan: plan,
                      selected: plan == _selected,
                      onTap: _busy
                          ? null
                          : () => setState(() => _selected = plan),
                    ),
                ],
                const SizedBox(height: 16),
                if (AuthService.isProUser)
                  Column(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green,
                          size: 40),
                      const SizedBox(height: 8),
                      Text(
                        t('أنت عضو برو ✅', 'You are a Pro member ✅'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _downgrade,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          side: BorderSide(color: Colors.red.shade400),
                        ),
                          icon: const Icon(Icons.arrow_back, size: 18),
                        label: Text(t('الرجوع للنسخة المجانية',
                            'Back to the free version')),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _buy,
                      style: FilledButton.styleFrom(backgroundColor: primary),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white))
                            : Text(
                                _pro == null
                                    ? (_loading
                                        ? t('التفاصيل عند فتح Play…',
                                            'Loading store details…')
                                        // Loading finished without this
                                        // product: don't claim to be loading.
                                        : t('المتجر غير متاح الآن',
                                            'Store unavailable right now'))
                                    : switch (_selected) {
                                        ProPlan.yearly when BillingService
                                                .instance.hasYearlyTrial =>
                                          t('ابدأ 7 أيام مجاناً',
                                              'Start 7-day free trial'),
                                        ProPlan.lifetime => t(
                                            'اشترِ مرة واحدة', 'Buy once'),
                                        _ => t('اشترك الآن', 'Subscribe now'),
                                      },
                                style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _busy ? null : _restore,
              child: Text(t('استعادة المشتريات', 'Restore purchases')),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _selected == ProPlan.lifetime
                ? t('دفعة واحدة عبر Google Play، من غير تجديد.',
                    'One payment through Google Play, no renewal.')
                : t('اشتراك يجدّد تلقائياً عبر Google Play. يمكنك الإلغاء من متجر Play في أي وقت.',
                    'Auto-renewing subscription through Google Play. Cancel anytime from the Play Store.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          if (_pro == null && !_loading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t('إن لم تظهر التفاصيل، تأكد من تهيئة المنتج في Play Console ثم أعد فتح الصفحة.',
                    'If details do not appear, ensure the product is set up in Play Console, then reopen this page.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade700, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final ProPlan plan;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final billing = BillingService.instance;
    final price = billing.product(plan)?.price ?? '—';
    final title = switch (plan) {
      ProPlan.monthly => t('شهري', 'Monthly'),
      ProPlan.yearly => t('سنوي', 'Yearly'),
      ProPlan.lifetime => t('مدى الحياة', 'Lifetime'),
    };
    final period = switch (plan) {
      // Words, not "/شهر": a leading slash lands on the wrong side in RTL.
      ProPlan.monthly => t('شهرياً', '/month'),
      ProPlan.yearly => t('سنوياً', '/year'),
      ProPlan.lifetime => t('مرة واحدة', 'one time'),
    };
    final saving = billing.yearlySavingPercent;
    final tags = <String>[
      if (plan == ProPlan.yearly) ...[
        if (saving != null)
          t('الأوفر · وفّر ${ltr('$saving%')}', 'Best value · save $saving%')
        else
          t('الأوفر', 'Best value'),
        if (billing.hasYearlyTrial) t('7 أيام مجاناً', '7 days free'),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? scheme.primary.withAlpha(30) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      if (tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final tag in tags)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(tag,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.onPrimary)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(price,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(period,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _weekdayShort(List<int> wds) {
  return wds.map((w) => weekdayShortLabel(w)).join(' · ');
}

String _weekdayName(int w) => weekdayName(w);

void showProUpgrade(
  BuildContext context, {
  String? message,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cardColor(Theme.of(ctx).brightness),
      title: Text(t('ميزة برو 🔒', 'Pro feature 🔒')),
      content: Text(message ??
          t('هذه الميزة متاحة في برو. رقِّ الآن!',
              'This feature is available in Pro. Upgrade now!')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('لاحقاً', 'Later')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProPage()));
          },
          child: Text(t('رقّي إلى برو', 'Upgrade to Pro')),
        ),
      ],
    ),
  );
}

Future<void> showHabitDialog(
  BuildContext context, {
  Habit? existing,
  // How many measurable habits the user already has. Callers that don't know
  // pass the free limit, so a free user can't convert a habit from there.
  int measurableInUse = FreePlan.maxMeasurable,
  required void Function(Habit habit) onSave,
}) {
  final canAddMeasurable = AuthService.isProUser ||
      (existing?.isMeasurable ?? false) ||
      measurableInUse < FreePlan.maxMeasurable;
  final controller = TextEditingController(text: existing?.name ?? '');
  final targetController = TextEditingController(
      text: existing != null && existing.target > 0
          ? (existing.target == existing.target.roundToDouble()
              ? existing.target.round().toString()
              : existing.target.toString())
          : '');
  final unitController = TextEditingController(text: existing?.unit ?? '');
  int selectedIndex = existing?.iconIndex ?? 0;
  int frequency = existing?.frequency ?? 0;
  List<int> weekdays =
      List.of(existing?.weekdays ?? [1, 2, 3, 4, 5, 6, 7]);
  int timesPerWeek = existing?.timesPerWeek ?? 3;
  bool measurable = (existing?.target ?? 0) > 0;
  bool timerOn = existing?.isTimer ?? false;
  int timerMinutes = existing?.timerMinutes ?? 5;
  bool isQuit = existing?.isQuit ?? false;
  bool reminderOn = existing?.reminderEnabled ?? false;
  TimeOfDay reminderTime = TimeOfDay(
    hour: existing?.reminderHour ?? 20,
    minute: existing?.reminderMinute ?? 0,
  );
  final icons = Habit.basicIcons;
  const weekDays = [1, 2, 3, 4, 5, 6, 7];
  String? formError;

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.tertiary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                  existing == null
                      ? Icons.add_task_rounded
                      : Icons.edit_rounded,
                  color: Colors.white,
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                existing == null
                    ? t('عادة جديدة', 'New habit')
                    : t('تعديل العادة', 'Edit habit'),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        // AlertDialog measures intrinsic width; a fixed width keeps it from
        // querying the horizontal icon GridView (a viewport), which throws.
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: existing == null,
                decoration: InputDecoration(
                  hintText: t('اسم العادة (مثال: اقرأ 10 صفحات)',
                      'Habit name (e.g. read 10 pages)'),
                  filled: true,
                  fillColor: secondaryColor(Theme.of(context).brightness),
                  prefixIcon: const Icon(Icons.edit_outlined),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 60,
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1, mainAxisSpacing: 8),
                  itemCount: icons.length,
                  itemBuilder: (ctx, i) => GestureDetector(
                    onTap: () => setDialogState(() => selectedIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 50,
                      decoration: BoxDecoration(
                        gradient: selectedIndex == i
                            ? LinearGradient(
                                colors: [
                                  Theme.of(ctx).colorScheme.primary,
                                  Theme.of(ctx).colorScheme.tertiary,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: selectedIndex == i
                            ? null
                            : secondaryColor(Theme.of(ctx).brightness),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: selectedIndex == i
                            ? [
                                BoxShadow(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(icons[i],
                          size: 26,
                          color: selectedIndex == i
                              ? Colors.white
                              : Theme.of(ctx).colorScheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    if (!AuthService.isProUser) {
                      showProUpgrade(ctx,
                          message: t(
                              'مكتبة الأيقونات الكاملة من مميزات برو.',
                              'The full icon library is a Pro feature.'));
                      return;
                    }
                    final picked = await showDialog<int>(
                      context: context,
                      builder: (_) =>
                          _IconLibraryDialog(selectedIndex: selectedIndex),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedIndex = picked);
                    }
                  },
                  icon: Icon(
                    selectedIndex >= Habit.basicIcons.length
                        ? Habit.availableIcons[selectedIndex]
                        : Icons.apps_rounded,
                    size: 20,
                  ),
                  label: Text(t('أيقونات أكثر', 'More icons')),
                ),
              ),
              const SizedBox(height: 16),
              Text(t('التكرار', 'Frequency'),
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                segments: [
                  ButtonSegment(
                      value: 0,
                      label: Text(t('يومي', 'Daily'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade)),
                  ButtonSegment(
                      value: 1,
                      label: Text(t('أسبوعي', 'Weekly'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade)),
                  ButtonSegment(
                      value: 2,
                      label: Text(t('مرات/أسبوع', 'Times/wk'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade)),
                ],
                selected: {frequency},
                onSelectionChanged: (s) =>
                    setDialogState(() => frequency = s.first),
                showSelectedIcon: false,
              ),
              if (frequency == 1) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final w in weekDays)
                      FilterChip(
                        label: Text(_weekdayName(w)),
                        selected: weekdays.contains(w),
                        onSelected: (sel) => setDialogState(() {
                          if (sel) {
                            if (!weekdays.contains(w)) weekdays.add(w);
                          } else {
                            weekdays.remove(w);
                          }
                          weekdays.sort();
                        }),
                      ),
                  ],
                ),
              ],
              if (frequency == 2) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(t('مرات في الأسبوع:', 'Times per week:')),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: timesPerWeek > 1
                          ? () => setDialogState(() => timesPerWeek--)
                          : null,
                    ),
                    Text('$timesPerWeek',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: timesPerWeek < 7
                          ? () => setDialogState(() => timesPerWeek++)
                          : null,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(children: [
                  Expanded(
                      child: Text(t('قابلة للقياس (هدف ووحدة)',
                          'Measurable (goal & unit)'))),
                  if (!canAddMeasurable)
                    const Icon(Icons.lock, size: 15, color: Colors.grey),
                ]),
                subtitle: Text(t('مثال: صفحات، دقائق، أكواب ماء',
                    'Example: pages, minutes, cups of water')),
                value: measurable,
                onChanged: (v) {
                  if (v && !canAddMeasurable) {
                    showProUpgrade(ctx,
                        message: t(
                            'النسخة المجانية فيها عادة واحدة قابلة للقياس. برو بيفتحها بلا حد.',
                            'The free plan includes one measurable habit. Pro unlocks unlimited ones.'));
                    return;
                  }
                  setDialogState(() => measurable = v);
                },
              ),
              if (measurable) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetController,
                        keyboardType: const TextInputType
                            .numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: t('الهدف', 'Goal'),
                          filled: true,
                          fillColor:
                              secondaryColor(Theme.of(context).brightness),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unitController,
                        decoration: InputDecoration(
                          labelText: t('الوحدة', 'Unit'),
                          hintText: t('صفحات', 'pages'),
                          filled: true,
                          fillColor:
                              secondaryColor(Theme.of(context).brightness),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(children: [
                  Expanded(
                      child: Text(t('عادة مؤقت ⏱️', 'Timer habit ⏱️'))),
                  if (!AuthService.isProUser)
                    const Icon(Icons.lock, size: 15, color: Colors.grey),
                ]),
                subtitle: Text(t(
                    'تكتمل لما المؤقت يخلص (تأمل، تركيز، جلسة صلاة…)',
                    'Completes when the countdown finishes (meditation, focus, prayer…)')),
                value: timerOn,
                onChanged: (v) {
                  if (v && !AuthService.isProUser) {
                    showProUpgrade(ctx,
                        message: t(
                            'عادات المؤقت (عدّاد تنازلي للدقائق) من مميزات برو.',
                            'Timer habits (a countdown for minutes) are a Pro feature.'));
                    return;
                  }
                  setDialogState(() {
                    timerOn = v;
                    if (v) measurable = false;
                  });
                },
              ),
              if (timerOn) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(t('المدة:', 'Duration:')),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: timerMinutes > 1
                          ? () => setDialogState(
                              () => timerMinutes = max(1, timerMinutes - 5))
                          : null,
                    ),
                    Text('$timerMinutes ${t('دقيقة', 'min')}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed:
                          () => setDialogState(() => timerMinutes += 5),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('هل تريد الإقلاع عن عادة سيئة؟',
                    'Quitting a bad habit?')),
                subtitle: Text(t(
                    'تتبّع الأيام النظيفة بدلاً منها (مثال: التدخين، السكريات)',
                    'Track clean days instead (e.g. smoking, sugar)')),
                value: isQuit,
                onChanged: (v) => setDialogState(() => isQuit = v),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(children: [
                  Expanded(child: Text(t('ذكّرني', 'Remind me'))),
                ]),
                subtitle: Text(reminderOn
                    ? t('في ${reminderTime.format(context)}',
                        'At ${reminderTime.format(context)}')
                    : t('اضبط تذكيراً يومياً لهذه العادة',
                        'Set a daily reminder for this habit')),
                value: reminderOn,
                onChanged: (v) async {
                  if (v) {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: reminderTime,
                    );
                    if (picked == null) return;
                    setDialogState(() {
                      reminderOn = true;
                      reminderTime = picked;
                    });
                  } else {
                    setDialogState(() => reminderOn = false);
                  }
                },
              ),
              if (formError != null) ...[
                const SizedBox(height: 8),
                Text(formError!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              String? error;
              if (name.isEmpty) {
                error = t('اكتب اسم العادة', 'Enter a habit name');
              } else if (frequency == 1 && weekdays.isEmpty) {
                error = t('اختر يوماً واحداً على الأقل',
                    'Pick at least one day');
              } else if (measurable &&
                  targetController.text.trim().isNotEmpty &&
                  (double.tryParse(targetController.text
                              .trim()
                              .replaceAll(',', '.')) ??
                          0) <=
                      0) {
                error = t('الهدف لازم يكون رقم أكبر من صفر',
                    'Goal must be a number greater than zero');
              }
              if (error != null) {
                setDialogState(() => formError = error);
                return;
              }
              final target = double.tryParse(
                      targetController.text.trim().replaceAll(',', '.')) ??
                  0;
              final habit = Habit(
                name: name,
                iconIndex: selectedIndex,
                id: existing?.id,
                completedDates: existing?.completedDates,
                amounts: existing?.amounts,
                doneAt: existing?.doneAt,
                frequency: frequency,
                weekdays:
                    frequency == 1 ? List.of(weekdays) : [1, 2, 3, 4, 5, 6, 7],
                timesPerWeek: frequency == 2 ? timesPerWeek : 7,
                target: measurable ? (target > 0 ? target : 1) : 0,
                unit: measurable ? unitController.text.trim() : '',
                isQuit: isQuit,
                isTimer: timerOn,
                timerMinutes: timerOn ? timerMinutes : 5,
                reminderEnabled: reminderOn,
                reminderHour: reminderOn ? reminderTime.hour : null,
                reminderMinute: reminderOn ? reminderTime.minute : null,
              );
              onSave(habit);
              Navigator.pop(ctx);
            },
            child: Text(existing == null ? t('إضافة', 'Add') : t('حفظ', 'Save')),
          ),
        ],
      ),
    ),
  );
}

class HabitTimerDialog extends StatefulWidget {
  final Habit habit;
  const HabitTimerDialog({super.key, required this.habit});

  @override
  State<HabitTimerDialog> createState() => _HabitTimerDialogState();
}

class _HabitTimerDialogState extends State<HabitTimerDialog> {
  late int _remaining;
  Timer? _ticker;
  bool _paused = false;
  bool _closed = false;

  int get _total => widget.habit.timerMinutes * 60;

  @override
  void initState() {
    super.initState();
    _remaining = _total;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _closed) return;
      setState(() {
        if (_remaining > 0) _remaining--;
      });
      if (_remaining <= 0) _done();
    });
  }

  void _done() {
    if (_closed) return;
    _closed = true;
    _ticker?.cancel();
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _stamp {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;
    final progress =
        _total == 0 ? 0.0 : ((_total - _remaining) / _total).clamp(0.0, 1.0);

    return Dialog(
      backgroundColor: cardColor(brightness),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: primary.withAlpha(34),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(habit.icon, color: primary, size: 28),
            ),
            const SizedBox(height: 10),
            Text(habit.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              width: 170,
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      backgroundColor: secondaryColor(brightness),
                      color: primary,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_stamp,
                          style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      const SizedBox(height: 2),
                      Text(
                          _remaining == 0
                              ? t('تم ✅', 'Done ✅')
                              : t('إنجاز سريع 💙', 'Stay with it 💙'),
                          style: _remaining == 0
                              ? const TextStyle(
                                  color: Colors.green,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)
                              : TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  onPressed: _paused
                      ? () => setState(() => _paused = false)
                      : () => setState(() => _paused = true),
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  tooltip: _paused ? t('استئناف', 'Resume') : t('إيقاف مؤقت', 'Pause'),
                ),
                const SizedBox(width: 16),
                IconButton.outlined(
                  onPressed: () {
                    _closed = true;
                    Navigator.pop(context, false);
                  },
                  icon: const Icon(Icons.close),
                  tooltip: t('إلغاء', 'Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HabitDetailPage extends StatefulWidget {
  final Habit habit;
  final void Function(Habit) onUpdate;
  final VoidCallback onDelete;

  const HabitDetailPage({
    super.key,
    required this.habit,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends State<HabitDetailPage> {
  int _currentStreak = 0;
  int _longestStreak = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  void _compute() {
    final habit = widget.habit;
    _currentStreak = habit.currentStreak();
    _longestStreak = habit.longestStreak();
    _total = habit.countCompletions();
  }

  Future<void> _recordNow() async {
    final habit = widget.habit;
    final now = clock();
    final wasDone = habit.isDoneOn(now);
    final controller = TextEditingController();
    final recorded = habit.amountOn(now);
    final remaining = habit.target - recorded;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        title: Text(t('سجّل "${iso(habit.name)}"', 'Log "${habit.name}"')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(
                'اليوم: ${ltr('${_fmtD(recorded)} / ${_fmtD(habit.target)}')}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
                'Today: ${_fmtD(recorded)} / ${_fmtD(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: softInputDecoration(
                ctx,
                label: t(
                    'الكمية (${habit.unit.isEmpty ? 'وحدة' : habit.unit})',
                    'Amount (${habit.unit.isEmpty ? 'unit' : habit.unit})'),
                hint: remaining > 0
                    ? t('مثال: ${_fmtD(remaining)}',
                        'Example: ${_fmtD(remaining)}')
                    : t('تريد المزيد؟', 'Want more?'),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final q in [1.0, 2.0, 5.0, 10.0])
                  ActionChip(
                    label: Text(ltr('+${_fmtD(q)}')),
                    onPressed: () => Navigator.pop(ctx, q),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: Text(t('إضافة', 'Add')),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    setState(() {
      habit.amounts[dayKey(now)] =
          (habit.amounts[dayKey(now)] ?? 0) + result;
      if (!wasDone && habit.isDoneOn(now)) habit.setDoneAt(now);
    });
    _compute();
    widget.onUpdate(habit);
    if (!wasDone && habit.isDoneOn(now)) {
      // Same reason key as the home screen, so a goal is rewarded once a day
      // no matter which screen it was logged from.
      final res = await XpSystem.addOnce('habit|${habit.id}', 10);
      if (!res.awarded) return;
      if (res.leveledUp) {
        _showLevelUp(res.level);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('+10 XP ⚡'),
            duration: Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _startDetailTimer(Habit habit) async {
    final now = DateTime.now();
    if (habit.isDoneOn(now) || !mounted) return;
    final finished = await showDialog<bool>(
      context: context,
      builder: (ctx) => HabitTimerDialog(habit: habit),
    );
    if (finished != true || !mounted) return;
    setState(() {
      habit.completedDates.add(dayKey(now));
      habit.setDoneAt(now);
    });
    _compute();
    widget.onUpdate(habit);
  }

  void _showLevelUp(int level) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(t('المستوى $level!', 'Level $level!'),
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('رائع!', 'Awesome!')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtD(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        title: Text(t('حذف العادة؟', 'Delete habit?')),
        content: Text(t(
            'حذف "${iso(widget.habit.name)}" وكل تاريخها؟ لا يمكن التراجع عن هذا.',
            'Delete "${widget.habit.name}" and all its history? This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              NotificationService.cancelHabit(widget.habit.id);
              widget.onDelete();
              Navigator.pop(context);
            },
            child: Text(t('حذف', 'Delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;
    final habit = widget.habit;
    final today = clock();

    // heatmap: 12 weeks aligned to Sunday
    final start = addDays(today, -(77 + (today.weekday % 7)));

    return Scaffold(
      appBar: AppBar(
        title: Text(t('تفاصيل العادة', 'Habit details')),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              showHabitDialog(
                context,
                existing: habit,
                onSave: (h) {
                  setState(() {
                    widget.habit
                      ..name = h.name
                      ..iconIndex = h.iconIndex
                      ..frequency = h.frequency
                      ..weekdays = h.weekdays
                      ..timesPerWeek = h.timesPerWeek
                      ..target = h.target
                      ..unit = h.unit
                      ..isQuit = h.isQuit
                      ..isTimer = h.isTimer
                      ..timerMinutes = h.timerMinutes
                      ..reminderEnabled = h.reminderEnabled
                      ..reminderHour = h.reminderHour
                      ..reminderMinute = h.reminderMinute;
                  });
                  _compute();
                  widget.onUpdate(widget.habit);
                  if (h.reminderEnabled) {
                    NotificationService.scheduleHabit(widget.habit);
                  } else {
                    NotificationService.cancelHabit(widget.habit.id);
                  }
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: primary.withAlpha(38),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(habit.icon, color: primary, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    habit.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (habit.isMeasurable) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primary.withAlpha(24),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('اليوم: ${ltr('${_fmtD(habit.amountOn(today))} / ${_fmtD(habit.target)}')}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
                        'Today: ${_fmtD(habit.amountOn(today))} / ${_fmtD(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}'),
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: habit.target > 0
                          ? (habit.amountOn(today) / habit.target).clamp(0, 1)
                          : 0,
                      minHeight: 8,
                      backgroundColor: secondaryColor(brightness),
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(habit.isDoneOn(today)
                              ? t('حققت الهدف ✅', 'Goal reached ✅')
                              : t('سجّل التقدم', 'Log progress')),
                          onPressed: habit.isDoneOn(today) ? null : _recordNow,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (habit.isTimerHabit) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primary.withAlpha(24),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('عادة مؤقت ⏱️ — ${habit.timerMinutes} ${t('دقيقة', 'min')}',
                          'Timer habit ⏱️ — ${habit.timerMinutes} min'),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(habit.isDoneOn(today)
                        ? t('تم اليوم ✅', 'Done today ✅')
                        : t('ابدأ المؤقت', 'Start timer')),
                    onPressed: habit.isDoneOn(today)
                        ? null
                        : () => _startDetailTimer(habit),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCard(
                title: t('السلسلة الحالية', 'Current streak'),
                value: daysLabel(_currentStreak),
                icon: Icons.local_fire_department,
                color: Colors.orange,
              ),
              const SizedBox(width: 12),
              _StatCard(
                title: t('أطول سلسلة', 'Longest streak'),
                value: daysLabel(_longestStreak),
                icon: Icons.emoji_events,
                color: primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                title: t('إجمالي الإنجازات', 'Total completions'),
                value: '$_total',
                icon: Icons.check_circle,
                color: Colors.green,
              ),
              const SizedBox(width: 12),
              _StatCard(
                title: t('العودات 💛', 'Comebacks 💛'),
                value:
                    '${habit.countComebacks()} ${t('عودة', 'comeback')}',
                icon: Icons.wb_twilight,
                color: const Color(0xFFFFB74D),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('آخر 12 أسبوعاً', 'Last 12 weeks'),
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(12, (col) {
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: Column(
                        children: List.generate(7, (row) {
                          final day = addDays(start, col * 7 + row);
                          final isFuture = day.isAfter(
                              DateTime(today.year, today.month, today.day));
                          final done =
                              habit.isDoneOn(day);
                          return Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: done
                                  ? primary
                                  : isFuture
                                      ? Colors.transparent
                                      : secondaryColor(brightness),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  t('كل مربع هو يوم — الملوّن يعني أنه تم إنجازه',
                      'Each square is a day — colored means completed'),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatsPage extends StatefulWidget {
  final List<Habit> habits;
  final int refreshTick;

  const StatsPage({super.key, required this.habits, this.refreshTick = 0});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _level = 1;
  int _xp = 0;
  Set<String> _unlockedBadges = {};

  List<Habit> get habits => widget.habits;

  @override
  void initState() {
    super.initState();
    _loadXp();
    _loadBadges();
  }

  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _loadXp();
      _loadBadges();
    }
  }

  Future<void> _loadBadges() async {
    final set = await BadgeSystem.unlocked();
    if (mounted) setState(() => _unlockedBadges = set);
  }

  Future<void> _loadXp() async {
    final d = await XpSystem.load();
    if (mounted) {
      setState(() {
        _level = d.level;
        _xp = d.xp;
      });
    }
  }

  /// Completion % of the habits due on each of the last 7 days, oldest first
  /// (index 6 is today).
  List<double> _last7DaysPercent() {
    final today = clock();
    return List.generate(7, (i) {
      final day = addDays(today, -(6 - i));
      final due = habits.where((h) => h.isDueOn(day)).toList();
      if (due.isEmpty) return 0.0;
      return due.where((h) => h.isDoneOn(day)).length / due.length * 100;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;
    final week = _last7DaysPercent();
    // Bars are the last 7 days ending today, so bar i is (today - (6 - i))
    // and today is always the last bar.
    const todayIndex = 6;
    String barLabel(int i) =>
        weekdayShortLabel(addDays(clock(), -(6 - i)).weekday);
    final totalCompletions = habits.fold<int>(
        0, (sum, h) => sum + h.countCompletions());

    int bestStreak = 0;
    for (final h in habits) {
      final s = h.longestStreak();
      if (s > bestStreak) bestStreak = s;
    }

    int currentStreakAny = 0;
    for (final h in habits) {
      final s = h.currentStreak();
      if (s > currentStreakAny) currentStreakAny = s;
    }

    var done30 = 0, due30 = 0;
    for (final h in habits) {
      for (int i = 0; i < 30; i++) {
        final d = addDays(clock(), -i);
        if (h.isDueOn(d)) {
          due30++;
          if (h.isDoneOn(d)) done30++;
        }
      }
    }
    final rate30 = due30 == 0 ? 0 : (done30 * 100 / due30).round();

    final monthData = monthSeries(habits, 12);
    final wd = weekdayConsistency(habits, 4);
    final bestW = wd.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final unlocked = _unlockedBadges;

    final now = DateTime.now();
    final weekStart = Habit.mondayOf(now);
    var dueWeek = 0, doneWeek = 0;
    final dayTotals = <int, int>{};
    for (final h in habits) {
      for (var i = 0; i < 7; i++) {
        final day = addDays(weekStart, i);
        if (day.isAfter(now)) continue;
        if (h.isDueOn(day)) {
          dueWeek++;
          if (h.isDoneOn(day)) {
            doneWeek++;
            dayTotals[day.weekday] = (dayTotals[day.weekday] ?? 0) + 1;
          }
        }
      }
    }
    final weekRate = dueWeek == 0 ? 0 : (doneWeek * 100 / dueWeek).round();
    int bestWeekday = 1;
    for (final e in dayTotals.entries) {
      if (e.value > (dayTotals[bestWeekday] ?? 0)) bestWeekday = e.key;
    }
    final bestDayTotal = dayTotals[bestWeekday] ?? 0;
    Habit? weekBestHabit;
    var weekBestDays = 0;
    for (final h in habits) {
      var cnt = 0;
      for (var i = 0; i < 7; i++) {
        final day = addDays(weekStart, i);
        if (!day.isAfter(now) && h.isDoneOn(day)) cnt++;
      }
      if (cnt >= weekBestDays && cnt > 0) {
        weekBestDays = cnt;
        weekBestHabit = h;
      }
    }
    final weekComebacks = <String>[];
    for (final h in habits) {
      for (var i = 0; i < 7; i++) {
        final day = addDays(weekStart, i);
        if (!day.isAfter(now) && h.isComebackOn(day)) {
          weekComebacks.add(h.name);
          break;
        }
      }
    }

    final achievements = BadgeSystem.all().map((b) {
      final earned = b.earned(habits, _level, _xp);
      final desc = FreePlan.badgeAvailable(b.id)
          ? b.desc
          : t('متاحة في برو 🔒', 'Available in Pro 🔒');
      return (b.icon, b.title, desc, earned && unlocked.contains(b.id));
    }).toList();

    return Scaffold(
      // Free plan: a small banner here and in Settings, never on Home.
      bottomNavigationBar:
          AuthService.isProUser ? null : const AdBannerWidget(),
      appBar: AppBar(
        title: Text(t('إحصائياتك', 'Your stats')),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primary.withAlpha(26),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.workspace_premium, color: primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('المستوى $_level · ${ltr('$_xp XP')}', 'Level $_level · $_xp XP'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (XpSystem.xpInLevel(_xp) /
                                  XpSystem.xpToNextLevel(_xp))
                              .clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: secondaryColor(brightness),
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCard(
                title: t('السلسلة الحالية', 'Current streak'),
                value: daysLabel(currentStreakAny),
                icon: Icons.local_fire_department,
                color: Colors.deepOrange,
              ),
              const SizedBox(width: 12),
              _StatCard(
                title: t('أفضل سلسلة', 'Best streak'),
                value: daysLabel(bestStreak),
                icon: Icons.emoji_events,
                color: Colors.amber,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                title: t('معدل 30 يوم', '30-day rate'),
                value: '$rate30%',
                icon: Icons.percent,
                color: primary,
              ),
              const SizedBox(width: 12),
              _StatCard(
                title: t('إجمالي الإنجاز', 'Total completions'),
                value: '$totalCompletions',
                icon: Icons.check_circle,
                color: Colors.green,
              ),
            ],
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: primary.withAlpha(70),
                  width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.yard, color: primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      t('ملخص أسبوعك 🎯', 'This week recap 🎯'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: primary.withAlpha(24),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '$weekRate%',
                        style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  t(
                    dueWeek == 0
                        ? 'لم تعد أي مهمة هذا الأسبوع بعد — أضف عاداتك أولاً.'
                        : 'أنجزت $doneWeek من $dueWeek مهمة مجدولة. ${weekRate == 100 ? 'أسبوع مثالي 👏' : 'كمّل وكسر رقمك بالأيام الجاية.'}',
                    dueWeek == 0
                        ? 'No tasks were due this week yet — add habits first.'
                        : 'Completed $doneWeek of $dueWeek scheduled. ${weekRate == 100 ? 'Perfect week 👏' : 'Keep going and beat it next week.'}',
                  ),
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 12),
                if (bestDayTotal > 0)
                  _RecapLine(
                    icon: Icons.star,
                    text: t(
                        'أقوى يوم: ${weekdayName(bestWeekday)} ($bestDayTotal إنجاز)',
                        'Strongest day: ${weekdayName(bestWeekday)} ($bestDayTotal done)'),
                  ),
                if (weekBestHabit != null)
                  _RecapLine(
                    icon: Icons.check_circle,
                    text: t(
                        'الثابت الكبير: "${iso(weekBestHabit.name)}" — ${daysAr(weekBestDays)}',
                        'Rock of the week: "${weekBestHabit.name}" — $weekBestDays day(s)'),
                  ),
                if (weekComebacks.isNotEmpty)
                  _RecapLine(
                    icon: Icons.wb_twilight,
                    color: const Color(0xFFFFB74D),
                    text: t(
                        'عودة تستحق التهنئة 💛 — رجعت لـ${weekComebacks.length > 1 ? '${weekComebacks.length} عادات' : weekComebacks.first}',
                        'Comebacks deserve a cheer 💛 — back at ${weekComebacks.length > 1 ? '${weekComebacks.length} habits' : weekComebacks.first}'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: BarChart(
              BarChartData(
                maxY: 100,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(
                        barLabel(value.toInt()),
                        style: TextStyle(
                          color: value.toInt() == todayIndex
                              ? primary
                              : Colors.grey,
                          fontWeight: value.toInt() == todayIndex
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
                barGroups: List.generate(7, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: week[i],
                        color: i == 6 ? primary : primary.withAlpha(120),
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t('معدل إنجازك في آخر 7 أيام', 'Your completion rate over the last 7 days'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _ProSection(
            title: t('التحليلات المتقدمة (شهري وسنوي) 📊',
                'Advanced analytics (monthly & yearly) 📊'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Text(t('آخر 12 شهراً 📈', 'Last 12 months 📈'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            height: 210,
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: BarChart(
              BarChartData(
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: secondaryColor(brightness).withAlpha(90),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= monthData.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            monthData[i].label,
                            style: TextStyle(
                              fontSize: 9,
                              color: monthData[i].month ==
                                      clock().month &&
                                  monthData[i].year == clock().year
                                  ? primary
                                  : Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(monthData.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: monthData[i].rate,
                        color: i == monthData.length - 1
                            ? primary
                            : primary.withAlpha(130),
                        width: 14,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(t('أسبوعك بنظرة واحدة 🗓️', 'Your weeks at a glance 🗓️'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WeekGrid(
                  habits: habits,
                  primary: primary,
                  bg: secondaryColor(brightness),
                ),
                const SizedBox(height: 8),
                Text(
                  t('كل نقطة يوم — أكثر لمعاناً يعني إنجاز عادات أكثر.',
                      'Every dot is a day — brighter means more habits completed.'),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(t('شهرك الحالي 📅', 'This month 📅'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: MonthHeatmap(
              habits: habits,
              primary: primary,
              bg: secondaryColor(brightness),
            ),
          ),
          const SizedBox(height: 24),
          Text(t('عامك بنظرة واحدة 🗓️', 'Your year at a glance 🗓️'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YearHeatmap(habits: habits, primary: primary),
                const SizedBox(height: 8),
                Text(
                  t('كل نقطة يوم — الأكثر لمعاناً يعني إنجاز عادات أكثر.',
                      'Each dot is a day — brighter means more habits completed.'),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(t('أفضل يوم أداءً ⭐', 'Your best day ⭐'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('${weekdayName(bestW)} هو أقوى يوم لديك '
                          '(${wd[bestW]!.round()}% ثبات)',
                      '${weekdayName(bestW)} is your strongest day '
                          '(${wd[bestW]!.round()}% consistency)'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var w = 1; w <= 7; w++) ...[
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              wd[w] == 0
                                  ? ''
                                  : '${wd[w]!.round()}',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 4 + (wd[w]! / 100 * 56),
                              decoration: BoxDecoration(
                                color: w == bestW
                                    ? primary
                                    : primary.withAlpha(120),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              weekdayShortLabel(w),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: w == bestW
                                      ? primary
                                      : Colors.grey.shade500,
                                  fontWeight: w == bestW
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            ),
                          ],
                        ),
                      ),
                      if (w != 7) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ],
            ),
          ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(t('تفصيل العادات 📊', 'Habit breakdown 📊'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (habits.isEmpty)
            Text(t('لا توجد عادات بعد — أضف واحدة من تبويب الرئيسية.',
                'No habits yet — add one from the Home tab.'),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
          else
            ...habits.map((h) {
              final hRate30 = h.rateLastN(30);
              final hStreak = h.currentStreak();
              final hTotal = h.countCompletions();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor(brightness),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: h.isMeasurable
                            ? primary.withAlpha(30)
                            : Colors.grey.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(h.icon,
                          color: h.isMeasurable
                              ? primary
                              : Colors.grey.shade500,
                          size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 3),
                          Text(
                              t('$hRate30% آخر 30 يوم · إجمالي $hTotal',
                                  '$hRate30% last 30 days · $hTotal total') +
                                  (h.isMeasurable
                                      ? ' · ${ltr(h.target.toStringAsFixed(h.target.truncateToDouble() == h.target ? 0 : 1))} ${h.unit.trim()}'
                                      : ''),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    if (hStreak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withAlpha(30),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('🔥 $hStreak',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),
          Text(t('الإنجازات 🏆', 'Achievements 🏆'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: achievements.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) {
                final a = achievements[i];
                return Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor(brightness),
                    borderRadius: BorderRadius.circular(16),
                    border: a.$4 ? Border.all(color: primary, width: 1.5) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Icon(a.$1,
                              size: 34,
                              color: a.$4
                                  ? primary
                                  : Colors.grey.shade600),
                          if (!a.$4)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Icon(Icons.lock,
                                  size: 14, color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(a.$2,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: a.$4 ? null : Colors.grey.shade600,
                          )),
                      Text(a.$3,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _RecapLine({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor(Theme.of(context).brightness),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            Text(title,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class WeekGrid extends StatelessWidget {
  final List<Habit> habits;
  final Color primary;
  final Color bg;
  final int weeks;
  const WeekGrid({
    super.key,
    required this.habits,
    required this.primary,
    required this.bg,
    this.weeks = 6,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = addDays(Habit.mondayOf(now), -(7 * (weeks - 1)));
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 42),
            for (var w = 0; w < 7; w++) ...[
              Expanded(
                child: Center(
                  child: Text(
                    weekdayShortLabel(w == 6 ? 7 : w + 1),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        for (var wi = 0; wi < weeks; wi++)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    '${addDays(start, wi * 7).day}/${addDays(start, wi * 7).month}',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
                  ),
                ),
                for (var d = 0; d < 7; d++) ...[
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: heatColor(
                            dayRate(habits,
                                addDays(start, wi * 7 + d)),
                            primary,
                            bg,
                          ),
                          borderRadius: BorderRadius.circular(5),
                          border: sameDay(addDays(start, wi * 7 + d), now)
                              ? Border.all(color: primary, width: 1.6)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class MonthHeatmap extends StatelessWidget {
  final List<Habit> habits;
  final Color primary;
  final Color bg;
  const MonthHeatmap({
    super.key,
    required this.habits,
    required this.primary,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final last = DateTime(now.year, now.month + 1, 0);
    final start = Habit.mondayOf(first);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var d = start;
        d.isBefore(addDays(last, 1));
        d = addDays(d, 7)) {
      rows.add(
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: () {
                    final date = addDays(d, i);
                    if (date.month != now.month) return const SizedBox.shrink();
                    final rate = dayRate(habits, date);
                    return Container(
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: heatColor(rate, primary, bg),
                        borderRadius: BorderRadius.circular(5),
                        border: sameDay(date, now)
                            ? Border.all(color: primary, width: 1.8)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: rate > 50
                                ? Colors.white
                                : (dark ? Colors.white70 : Colors.black54),
                            fontWeight:
                                sameDay(date, now) ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }(),
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        // No leading spacer: the day rows below have none, so headers line
        // up with their columns.
        Row(
          children: [
            for (var w = 0; w < 7; w++) ...[
              Expanded(
                child: Center(
                  child: Text(
                    weekdayShortLabel(w == 6 ? 7 : w + 1),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        for (final r in rows) r,
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              t('أقل', 'Less'),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  // Runs from the "Less" label to the "More" label in both
                  // LTR and RTL.
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [
                      bg,
                      primary.withAlpha(24 + (25 * 2.2).round()),
                      primary.withAlpha(255),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              t('أكثر', 'More'),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ],
    );
  }
}

class YearHeatmap extends StatelessWidget {
  final List<Habit> habits;
  final Color primary;
  const YearHeatmap({super.key, required this.habits, required this.primary});

  Color _colorFor(DateTime d, DateTime today) {
    if (d.isAfter(today)) return Colors.transparent;
    final due = habits.where((h) => h.isDueOn(d)).length;
    if (due == 0) return primary.withAlpha(12);
    final frac = habits.where((h) => h.isDoneOn(d)).length / due;
    if (frac < 0.34) return primary.withAlpha(60);
    if (frac < 0.67) return primary.withAlpha(120);
    return primary;
  }

  @override
  Widget build(BuildContext context) {
    final today = clock();
    final todayMid = DateTime(today.year, today.month, today.day);
    final gridStart =
        Habit.mondayOf(addDays(todayMid, -364));
    final colCount = ((todayMid.difference(gridStart).inDays + 1) / 7).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        final step = constraints.maxWidth / colCount;
        final cell = (step - 2).clamp(2.5, 9.0);

        Widget slot(DateTime d) => Container(
              width: cell,
              height: cell,
              margin: const EdgeInsets.only(right: 2, bottom: 2),
              decoration: BoxDecoration(
                color: _colorFor(d, todayMid),
                borderRadius: BorderRadius.circular(2),
              ),
            );

        String? label(int col) {
          final weekMonday = addDays(gridStart, col * 7);
          if (weekMonday.month ==
              addDays(weekMonday, -7).month) {
            return null;
          }
          return monthLabel(weekMonday.month);
        }

        return Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var c = 0; c < colCount; c++)
                    SizedBox(
                      width: step,
                      // Month labels are wider than one column; let them
                      // run into the next (empty) columns instead of
                      // wrapping letter by letter.
                      child: Text(
                        label(c) ?? '',
                        style: const TextStyle(fontSize: 8),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              for (var r = 0; r < 7; r++)
                Row(
                  children: [
                    for (var c = 0; c < colCount; c++)
                      slot(addDays(gridStart, c * 7 + r)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool reminderOn = false;
  TimeOfDay reminderTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        reminderOn = prefs.getBool('reminderEnabled') ?? false;
        reminderTime = TimeOfDay(
          hour: prefs.getInt('reminderHour') ?? 20,
          minute: prefs.getInt('reminderMinute') ?? 0,
        );
      });
    }
  }

  Future<void> _toggleReminder(bool value) async {
    if (value) {
      await NotificationService.init();
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(t('اسمح بالإشعارات لتفعيل التذكيرات',
                    'Allow notifications to enable reminders')),
            ),
          );
        }
        return;
      }
      await NotificationService.scheduleDaily(
          hour: reminderTime.hour, minute: reminderTime.minute);
    } else {
      await NotificationService.cancelGlobal();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminderEnabled', value);
    if (mounted) setState(() => reminderOn = value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: reminderTime,
    );
    if (picked != null) {
      setState(() => reminderTime = picked);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reminderHour', picked.hour);
      await prefs.setInt('reminderMinute', picked.minute);
      if (reminderOn) {
        await NotificationService.scheduleDaily(
            hour: picked.hour, minute: picked.minute);
      }
    }
  }

  Future<void> _testNotification() async {
    await NotificationService.init();
    await NotificationService.showTest();
  }

  Future<void> _exportBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = AuthService.email;

      final moodMap = <String, int>{};
      final now = DateTime.now();
      for (var i = 0; i < 730; i++) {
        final d = addDays(now, -i);
        final k = 'mood_${email ?? 'guest'}_${dayKey(d)}';
        final v = prefs.getInt(k);
        if (v != null) moodMap[dayKey(d)] = v;
      }

      final payload = <String, dynamic>{
        'app': 'HabitFlow',
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'habits': jsonDecode(prefs.getString('habits') ?? '[]'),
        'xp': prefs.getInt('xp_$email') ?? 0,
        'darkMode': prefs.getBool('darkMode') ?? true,
        'themeColor': prefs.getInt('themeColor') ?? 0,
        'themeCustom': prefs.getInt('themeCustom'),
        'reminderEnabled': prefs.getBool('reminderEnabled') ?? false,
        'reminderHour': prefs.getInt('reminderHour') ?? 20,
        'reminderMinute': prefs.getInt('reminderMinute') ?? 0,
        'mood_history': moodMap,
      };

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/habitflow_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonEncode(payload));

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'HabitFlow Backup',
          text: t(
              'نسخة احتياطية كاملة من HabitFlow 🗂️ — يمكنك استعادتها من الإعدادات.',
              'Full HabitFlow backup 🗂️ — restore it from Settings.'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('تم تجهيز النسخة الاحتياطية! 📤',
                  'Backup file ready! 📤'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('تعذر إنشاء النسخة الاحتياطية ❌',
                  'Could not create backup ❌'))),
        );
      }
    }
  }

  Future<void> _restoreBackup() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final picked = res?.files.firstOrNull;
    if (picked == null) return;

    try {
      final text = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : await File(picked.path!).readAsString();
      final decoded = jsonDecode(text);

      final prefs = await SharedPreferences.getInstance();

      if (decoded is List) {
        final habits = decoded
            .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        await prefs.setString(
            'habits', jsonEncode(habits.map((h) => h.toMap()).toList()));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    t('تمت استعادة ${habitsAr(habits.length)} بنجاح ✅',
                        'Restored ${habits.length} habits successfully ✅'))),
          );
          await _load();
        }
        HomePage.reload?.call();
        return;
      }

      if (decoded is Map && decoded['app'] == 'HabitFlow') {
        final email = AuthService.email;
        final habits = (decoded['habits'] as List)
            .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        await prefs.setString(
            'habits', jsonEncode(habits.map((h) => h.toMap()).toList()));
        if (decoded['xp'] is int) {
          await prefs.setInt(
              'xp_$email', decoded['xp'] as int);
        }
        if (decoded['darkMode'] is bool) {
          await prefs.setBool('darkMode', decoded['darkMode'] as bool);
        }
        if (decoded['themeColor'] is int) {
          await prefs.setInt('themeColor', decoded['themeColor'] as int);
        }
        if (decoded['themeCustom'] is int) {
          await prefs.setInt('themeCustom', decoded['themeCustom'] as int);
        }
        if (decoded['reminderEnabled'] is bool) {
          await prefs.setBool(
              'reminderEnabled', decoded['reminderEnabled'] as bool);
        }
        if (decoded['reminderHour'] is int) {
          await prefs.setInt('reminderHour', decoded['reminderHour'] as int);
        }
        if (decoded['reminderMinute'] is int) {
          await prefs.setInt(
              'reminderMinute', decoded['reminderMinute'] as int);
        }
        if (decoded['mood_history'] is Map) {
          (decoded['mood_history'] as Map).forEach((k, v) {
            if (v is int) {
              prefs.setInt('mood_${email ?? 'guest'}_$k', v);
            }
          });
        }
        if (mounted) {
          if (decoded['darkMode'] is bool) {
            HabitFlowApp.of(context)
                ?.setDarkMode(decoded['darkMode'] as bool);
          }
          if (decoded['themeColor'] is int) {
            final tc = decoded['themeColor'] as int;
            if (tc < 0 && decoded['themeCustom'] is int) {
              HabitFlowApp.of(context)
                  ?.setCustomTheme(Color(decoded['themeCustom'] as int));
            } else {
              HabitFlowApp.of(context)?.setTheme(tc);
            }
          }
          final xpV = decoded['xp'] is int ? decoded['xp'] as int : 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(t(
                    'تمت استعادة ${habitsAr(habits.length)} وكل بياناتك ✅ (${ltr('$xpV XP')})',
                    'Restored ${habits.length} habits and all your data ✅ ($xpV XP)'))),
          );
          await _load();
        }
        HomePage.reload?.call();
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('هذا الملف ليس نسخة احتياطية صالحة ❌',
                  'This file is not a valid backup ❌'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  t('تعذر قراءة الملف — تأكد أنه نسخة HabitFlow ❌',
                      'Could not read the file — make sure it’s a HabitFlow backup ❌'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      // Free plan: a small banner here and in Settings, never on Home.
      bottomNavigationBar:
          AuthService.isProUser ? null : const AdBannerWidget(),
      appBar: AppBar(
        title: Text(t('الإعدادات', 'Settings')),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
if (!AuthService.isProUser)
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // Darken the pastel dark-mode primary so the white text on
                // this banner stays readable (same as the Pro page hero).
                gradient: LinearGradient(
                  colors: brightness == Brightness.dark
                      ? [
                          Color.lerp(primary, Colors.black, 0.45)!,
                          Color.lerp(primary, Colors.black, 0.25)!,
                        ]
                      : [primary, primary.withAlpha(180)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.workspace_premium,
                    color: Colors.white, size: 34),
                title: Text(t('رقِّ إلى برو', 'Upgrade to Pro'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                subtitle: Text(t('بلا إعلانات • عادات غير محدودة • اشتراك شهري',
                    'No ads • Unlimited habits • Monthly subscription'),
                    style: TextStyle(color: Colors.white.withAlpha(220))),
                trailing: const Icon(Icons.arrow_forward_ios,
                    color: Colors.white, size: 14),
onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProPage())),
              ),
            ),
          )
else if (AuthService.isProUser)
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  // Darkened in dark mode so the white text stays readable.
                  colors: [
                    Colors.green.shade700,
                    brightness == Brightness.dark
                        ? Color.lerp(primary, Colors.black, 0.35)!
                        : primary,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.workspace_premium,
                    color: Colors.white, size: 34),
                title: Text(t('أنت برو', 'You are Pro'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                subtitle: Text(t('إدارة اشتراكك أو الرجوع للنسخة المجانية',
                    'Manage your subscription or go back to the free version'),
                    style: TextStyle(color: Colors.white.withAlpha(220))),
                trailing: const Icon(Icons.arrow_forward_ios,
                    color: Colors.white, size: 14),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProPage())),
              ),
            ),
          ),
          Material(
            color: cardColor(brightness),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(Icons.translate, color: primary),
              title: Text(t('اللغة', 'Language'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: Text(Language.isAr
                  ? t('التبديل إلى الإنجليزية', 'Switch to English')
                  : t('التبديل إلى العربية', 'Switch to Arabic')),
              trailing: Text(
                Language.isAr ? 'العربية' : 'English',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: primary),
              ),
              onTap: () => HabitFlowApp.of(context)?.setLang(
                  Language.isAr ? 'en' : 'ar'),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('لون التطبيق', 'App color'),
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (var i = 0; i < palette.length; i++)
                      Builder(builder: (context) {
                        final selected =
                            HabitFlowApp.of(context)?._seed == palette[i] &&
                                HabitFlowApp.of(context)?._customTheme != true;
                        return GestureDetector(
                          onTap: () => HabitFlowApp.of(context)?.setTheme(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette[i],
                              border: selected
                                  ? Border.all(
                                      color: brightness == Brightness.dark
                                          ? Colors.white
                                          : Colors.black,
                                      width: 3)
                                  : null,
                            ),
                            child: selected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 26)
                                : null,
                          ),
                        );
                      }),
                    Builder(builder: (context) {
                      final customSelected =
                          HabitFlowApp.of(context)?._customTheme == true;
                      return GestureDetector(
                        onTap: () async {
                          if (!AuthService.isProUser) {
                            showProUpgrade(
                                context,
                                message: t(
                                    'اختيار لون مخصص للتطبيق من مميزات برو.',
                                    'Picking a custom app colour is a Pro feature.'));
                            return;
                          }
                          final current =
                              HabitFlowApp.of(context)?._seed ?? palette[0];
                          final picked = await showDialog<Color>(
                            context: context,
                            builder: (ctx) =>
                                _ColorWheelDialog(initial: current),
                          );
                          if (picked != null && context.mounted) {
                            HabitFlowApp.of(context)?.setCustomTheme(picked);
                          }
                        },
                        child: Stack(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const SweepGradient(colors: [
                                  Color(0xFFFF0000),
                                  Color(0xFFFFFF00),
                                  Color(0xFF00FF00),
                                  Color(0xFF00FFFF),
                                  Color(0xFF0000FF),
                                  Color(0xFFFF00FF),
                                  Color(0xFFFF0000),
                                ]),
                                border: customSelected
                                    ? Border.all(
                                        color: brightness == Brightness.dark
                                            ? Colors.white
                                            : Colors.black,
                                        width: 3)
                                    : null,
                              ),
                              child: Icon(
                                customSelected
                                    ? Icons.check
                                    : Icons.colorize_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            if (!AuthService.isProUser)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.lock,
                                      size: 11, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: cardColor(brightness),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('تذكير يومي', 'Daily reminder'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    subtitle: Text(t('يصلك إشعار كل يوم',
                        'You get a notification every day')),
                    value: reminderOn,
                    activeThumbColor: primary,
                    onChanged: _toggleReminder,
                  ),
                  Divider(color: dividerColor(brightness)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm),
                    title: Text(t('وقت التذكير', 'Reminder time')),
                    trailing: Text(
                      reminderTime.format(context),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primary),
                    ),
                    onTap: _pickTime,
                  ),
                  Divider(color: dividerColor(brightness)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_active),
                    title: Text(t('إرسال إشعار تجريبي',
                        'Send a test notification')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: _testNotification,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: cardColor(brightness),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('الوضع الليلي', 'Dark mode'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: Text(t('التنقل بين الوضعين الليلي والنهاري',
                    'Toggle between dark and light mode')),
                value: HabitFlowApp.of(context)?._darkMode ?? true,
                activeThumbColor: primary,
                onChanged: (v) => HabitFlowApp.of(context)?.setDarkMode(v),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: cardColor(brightness),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('النسخ الاحتياطي', 'Backup & restore'),
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file),
                    title: Text(t('تصدير نسخة', 'Export backup')),
                    subtitle: Text(t('نسخة كاملة بملف JSON 🗂️',
                        'Full backup as a JSON file 🗂️')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: _exportBackup,
                  ),
                  Divider(color: dividerColor(brightness)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download),
                    title: Text(t('استعادة نسخة', 'Restore backup')),
                    subtitle: Text(t('ارفع ملف النسخة الاحتياطية 📂',
                        'Pick your backup file 📂')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: _restoreBackup,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('عن التطبيق', 'About'),
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('HabitFlow v1.0.3',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(t('تتبّع عاداتك وابنِ سلسلة نجاحك. 💪',
                    'Track your habits and build your success streak. 💪'),
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: cardColor(brightness),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('الحساب: ${AuthService.email ?? '-'}',
                      'Account: ${AuthService.email ?? '-'}'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(t('تسجيل الخروج', 'Log out'),
                      style: const TextStyle(color: Colors.red)),
                  onTap: () async {
                      await AuthService.logout();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const RootPage()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _ColorWheelDialog extends StatefulWidget {
  const _ColorWheelDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> {
  static const double _wheelSize = 232;
  late double _hue;
  late double _sat;
  late double _val;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    _hue = hsv.hue;
    _sat = hsv.saturation;
    _val = hsv.value;
  }

  Color get _color => HSVColor.fromAHSV(1, _hue, _sat, _val).toColor();

  void _updateFromLocal(Offset local) {
    final maxR = _wheelSize / 2 - 10;
    final dx = local.dx - _wheelSize / 2;
    final dy = local.dy - _wheelSize / 2;
    final r = sqrt(dx * dx + dy * dy);
    var hue = atan2(dy, dx) * 180 / pi;
    if (hue < 0) hue += 360;
    setState(() {
      _hue = hue;
      _sat = (r / maxR).clamp(0.0, 1.0).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AlertDialog(
      backgroundColor: cardColor(brightness),
      title: Row(
        children: [
          const Icon(Icons.colorize_rounded),
          const SizedBox(width: 10),
          Text(t('لون مخصص', 'Custom colour'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _wheelSize,
              height: _wheelSize,
              child: GestureDetector(
                onPanDown: (d) => _updateFromLocal(d.localPosition),
                onPanUpdate: (d) => _updateFromLocal(d.localPosition),
                child: CustomPaint(
                  painter: _ColorWheelPainter(
                    hue: _hue,
                    sat: _sat,
                    thumbColor: _color,
                    edgeColor: brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.brightness_6,
                    size: 20, color: Colors.grey.shade500),
                Expanded(
                  child: Slider(
                    value: _val,
                    activeColor: _color,
                    onChanged: (v) => setState(() => _val = v),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _color,
                    border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: Text(t('حفظ التغييرات', 'Save changes')),
        ),
      ],
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  _ColorWheelPainter({
    required this.hue,
    required this.sat,
    required this.thumbColor,
    required this.edgeColor,
  });

  final double hue;
  final double sat;
  final Color thumbColor;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const hueColors = [
      Color(0xFFFF0000),
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
      Color(0xFF00FFFF),
      Color(0xFF0000FF),
      Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ];
    canvas.drawCircle(
        center, radius, Paint()..shader = SweepGradient(colors: hueColors).createShader(rect));

    final radial = RadialGradient(colors: [
      Colors.white,
      Colors.white.withValues(alpha: 0.0),
    ]);
    canvas.drawCircle(
        center, radius, Paint()..shader = radial.createShader(rect));

    final angle = hue * pi / 180;
    final thumb = center + Offset(cos(angle), sin(angle)) * (sat * radius);
    canvas.drawCircle(thumb, 12, Paint()..color = Colors.white);
    canvas.drawCircle(
        thumb,
        12,
        Paint()
          ..color = edgeColor.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawCircle(thumb, 8.5, Paint()..color = thumbColor);
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter old) =>
      old.hue != hue || old.sat != sat || old.thumbColor != thumbColor;
}

class _ProSection extends StatelessWidget {
  const _ProSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AuthService.isProUser) return child;
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor(brightness),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withAlpha(70), width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  primary,
                  Theme.of(context).colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.lock_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(t('متاح في برو 🔒', 'Available in Pro 🔒'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProPage())),
            icon: const Icon(Icons.workspace_premium, size: 18),
            label: Text(t('رقّي إلى برو', 'Upgrade to Pro')),
          ),
        ],
      ),
    );
  }
}

class _IconLibraryDialog extends StatefulWidget {
  const _IconLibraryDialog({required this.selectedIndex});

  final int selectedIndex;

  @override
  State<_IconLibraryDialog> createState() => _IconLibraryDialogState();
}

class _IconLibraryDialogState extends State<_IconLibraryDialog> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIndex;
  }

  @override
  Widget build(BuildContext context) {
    final icons = Habit.extraIcons;
    final offset = Habit.basicIcons.length;
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;

    return AlertDialog(
      backgroundColor: cardColor(brightness),
      title: Row(
        children: [
          const Icon(Icons.apps_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(t('مكتبة الأيقونات', 'Icon library'),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        height: 400,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8),
          itemCount: icons.length,
          itemBuilder: (ctx, i) {
            final idx = offset + i;
            final sel = _selected == idx;
            return GestureDetector(
              onTap: () => setState(() => _selected = idx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: sel ? null : secondaryColor(brightness),
                  gradient: sel
                      ? LinearGradient(
                          colors: [
                            primary,
                            Theme.of(ctx).colorScheme.tertiary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  border: sel
                      ? Border.all(
                          color: brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          width: 2)
                      : null,
                ),
                child: Icon(icons[i],
                    size: 24, color: sel ? Colors.white : primary),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(t('اختيار', 'Select')),
        ),
      ],
    );
  }
}

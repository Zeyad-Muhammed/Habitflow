import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Language.load();
  runApp(const HabitFlowApp());
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

class AuthService {
  static const ownerEmail = 'zeyad@habitflow.app';
  static const Map<String, String> testAccounts = {
    'test1@habitflow.app': 'test123',
    'test2@habitflow.app': 'test123',
  };
  static const _salt = 'habitflow_salt_v1';

  static String? name;
  static String? email;
  static bool isPro = false;

  static bool get isOwner => email == ownerEmail;
  static bool get isProUser => isPro || isOwner;

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
    if (savedEmail == null && savedHash == null &&
        testAccounts[clean] == password) {
      await prefs.setString('auth_name',
          clean.startsWith('test2') ? 'صديق ٢' : 'صديق ١');
      await prefs.setString('auth_email', clean);
      await prefs.setString('auth_hash', _hash(password));
      await prefs.setBool('isPro', true);
      return true;
    }
    if (savedEmail == null || savedHash == null) return false;
    if (savedEmail != clean) return false;
    if (savedHash != _hash(password)) return false;
    return true;
  }

  static Future<void> startSession() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('auth_name');
    email = prefs.getString('auth_email');
    isPro = prefs.getBool('isPro') ?? false;
    await prefs.setBool('auth_logged_in', true);
  }

  static Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('auth_logged_in') != true) return false;
    name = prefs.getString('auth_name');
    email = prefs.getString('auth_email');
    isPro = prefs.getBool('isPro') ?? false;
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
    if (newPassword.length < 4) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('auth_hash') == null) return false;
    await prefs.setString('auth_hash', _hash(newPassword));
    _resetCode = null;
    return true;
  }
}

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

  static _HabitFlowAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_HabitFlowAppState>();

  @override
  State<HabitFlowApp> createState() => _HabitFlowAppState();
}

class _HabitFlowAppState extends State<HabitFlowApp> {
  Color _seed = palette[0];
  bool _darkMode = true;
  bool? _onboardingDone;
  String _lang = Language.code;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final i = prefs.getInt('themeColor') ?? 0;
    final dark = prefs.getBool('darkMode') ?? true;
    if (mounted) {
      setState(() {
        _seed = palette[i.clamp(0, palette.length - 1)];
        _darkMode = dark;
        _onboardingDone = prefs.getBool('onboarding_done') ?? false;
        _lang = Language.code;
      });
    }
  }

  void setTheme(int index) {
    setState(() => _seed = palette[index.clamp(0, palette.length - 1)]);
    SharedPreferences.getInstance()
        .then((p) => p.setInt('themeColor', index));
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
        return _AmbientBackground(
          scheme: cs,
          isDark: Theme.of(context).brightness == Brightness.dark,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: KeyedSubtree(
        key: ValueKey(_lang),
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

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _done,
                child: Text(t('تخطّي', 'Skip')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) {
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
                  onPressed: () {
                    if (_page < _slides.length - 1) {
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
    if (emailText.isEmpty || passText.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('أدخل بريدك وكلمة مرور (٦ حروف فأكثر)',
              'Enter your email and a password (6+ characters)'))));
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
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => setState(() => _isSignup = !_isSignup),
                  child: Text(_isSignup
                      ? t('لديك حساب بالفعل؟ سجّل دخولك',
                          'Already have an account? Sign in')
                      : t('جديد هنا؟ أنشئ حسابك', 'New here? Create an account')),
                ),
                const SizedBox(height: 12),
                Text('HabitFlow v1.2',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
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
    if (pass.length < 4) {
      _toast(t('الباسورد لازم ٤ حروف فأكثر', 'Password must be 4+ characters'));
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
                  'assets/icon/logo_white.png',
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
                            label: t('كود من ٦ أرقام', '6-digit code'),
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

const MethodChannel _widgetChannel = MethodChannel('com.zeyad.habit_tracker/widget');

void refreshWidget() {
  _widgetChannel.invokeMethod('refresh');
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
      final now = DateTime.now();
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
    Map<String, double>? amounts,
    Map<String, String>? doneAt,
  })  : id = id ?? (DateTime.now().millisecondsSinceEpoch & 0x1FFFFFFF),
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

  static const List<IconData> availableIcons = [
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

  IconData get icon => availableIcons[iconIndex];

  bool get isMeasurable => target > 0;
  bool get isWeekly => frequency == 1;
  bool get isFlexible => frequency == 2;
  bool get isDaily => frequency == 0;

  bool isDueOn(DateTime d) {
    if (isWeekly && (weekdays.isEmpty || weekdays.length < 7)) {
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
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
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
    if (all.isEmpty) return DateTime.now();
    return all.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  static DateTime mondayOf(DateTime d) {
    final diff = (d.weekday - DateTime.monday) % 7;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  int currentStreak() {
    if (isFlexible) return _flexibleStreak();
    int streak = 0;
    var day = DateTime.now();
    if (!isDueOn(day)) {
      day = day.subtract(const Duration(days: 1));
    }
    while (true) {
      if (!isDueOn(day)) {
        day = day.subtract(const Duration(days: 1));
        continue;
      }
      if (isDoneOn(day)) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  int _flexibleStreak() {
    int streak = 0;
    final today = DateTime.now();
    final self = this;
    if (self.daysDoneInRange(mondayOf(today), today) >= timesPerWeek) {
      streak++;
    }
    var weekStart = mondayOf(today).subtract(const Duration(days: 7));
    while (self.daysDoneInRange(weekStart,
            weekStart.add(const Duration(days: 6))) >= timesPerWeek) {
      streak++;
      weekStart = weekStart.subtract(const Duration(days: 7));
    }
    return streak;
  }

  int longestStreak() {
    if (isFlexible) {
      int best = 0;
      var weekStart = mondayOf(DateTime.now());
      for (var ws = mondayOf(_earliest());
          !ws.isAfter(weekStart);
          ws = ws.add(const Duration(days: 7))) {
        if (daysDoneInRange(ws, ws.add(const Duration(days: 6))) >=
            timesPerWeek) {
          best++;
        } else if (best > 0) {
          break;
        }
      }
      return best;
    }
    int best = 0;
    int run = 0;
    for (var d = _earliest();
        !d.isAfter(DateTime.now());
        d = d.add(const Duration(days: 1))) {
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

  int get numberOfStreaks {
    int weeks = 0;
    int run = 0;
    for (var d = _earliest();
        !d.isAfter(DateTime.now());
        d = d.add(const Duration(days: 1))) {
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
      final d = DateTime.now().subtract(Duration(days: i));
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
  final today = DateTime.now();
  for (int i = 0; i < weeks * 7; i++) {
    final d = today.subtract(Duration(days: i));
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
  final now = DateTime.now();
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

List<String> buildInsights(List<Habit> habits) {
  final out = <String>[];
  final today = DateTime.now();
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
    out.add(t('🔥 ${hot.length} عادة بسلسلة نشطة ${hot.first.currentStreak()}+ يوم.',
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
          '📈 تتقن "${h.name}" — جرّب رفع الهدف إلى $suggested ${h.unit.trim()} للارتقاء بمستواك.',
          '📈 You master "${h.name}" — try raising the goal to $suggested ${h.unit.trim()} to level up.'));
      break;
    }
  }

  final down = habits.where((h) => h.isDueOn(today) &&
      h.rateLastN(7) < 40 && h.countCompletions() >= 10).toList();
  if (down.isNotEmpty) {
    out.add(t('⚠️ "${down.first.name}" هادئة هذا الأسبوع — اهتم بأفضل عاداتك أولاً.',
        '⚠️ "${down.first.name}" is quiet this week — focus on your best habits first.'));
  }

  if (out.length < 2 && totalCompletions > 0) {
    out.add(t('✅ سجّل مزاجك يومياً لنصائح شخصية إضافية.',
        '✅ Log your daily mood for extra personal tips.'));
  }
  return out.take(3).toList();
}

Habit? atRiskHabit(List<Habit> habits) {
  final today = DateTime.now();
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
        _moodKey(AuthService.email, dayKey(DateTime.now())));
  }

  static Future<void> save(int mood) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_moodKey(AuthService.email, dayKey(DateTime.now())), mood);
    if (mood >= 4) await XpSystem.add(5);
  }

  static Future<int> goodMoodStreak() async {
    final p = await SharedPreferences.getInstance();
    var streak = 0;
    for (var i = 0; i < 60; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
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
      final d = dayKey(DateTime.now().subtract(Duration(days: i)));
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

class BadgeSystem {
  static List<Badge> all() => [
    Badge('first', Icons.emoji_events_outlined, t('الخطوة الأولى', 'First Step'),
        t('أنشئ أول عادة لك', 'Create your first habit'),
        (h, l, x) => h.isNotEmpty),
    Badge('fire7', Icons.local_fire_department, t('على نار', 'On Fire'),
        t('حقق سلسلة ٧ أيام', 'Reach a 7-day streak'),
        (h, l, x) => h.any((hb) => hb.longestStreak() >= 7)),
    Badge('bolt30', Icons.bolt, t('لا يُوقف', 'Unstoppable'),
        t('حقق سلسلة ٣٠ يوماً', 'Reach a 30-day streak'),
        (h, l, x) => h.any((hb) => hb.longestStreak() >= 30)),
    Badge('century', Icons.star, t('مئة إنجاز', 'Century'),
        t('أنجز ١٠٠ عادة إجمالاً', 'Complete 100 habits in total'),
        (h, l, x) => h.fold<int>(0, (s, hb) => s + hb.countCompletions()) >= 100),
    Badge('perfectday', Icons.today, t('يوم مثالي', 'Perfect Day'),
        t('أنجز كل عاداتك في يوم واحد', 'Complete every habit in one day'),
        (h, l, x) => _perfectDayEver(h)),
    Badge('perfectweek', Icons.workspace_premium, t('أسبوع مثالي', 'Perfect Week'),
        t('أنهي كل عاداتك ٧ أيام متتالية', 'Complete all habits 7 days in a row'),
        (h, l, x) => _perfectWeekEver(h)),
    Badge('level5', Icons.auto_awesome, t('نجم صاعد', 'Rising Star'),
        t('صل للمستوى ٥', 'Reach level 5'),
        (h, l, x) => l >= 5),
    Badge('level10', Icons.military_tech, t('سيد العادات', 'Habit Master'),
        t('صل للمستوى ١٠', 'Reach level 10'),
        (h, l, x) => l >= 10),
    Badge('measured', Icons.straighten, t('قابل للقياس', 'Measurable'),
        t('أنجز عادة قابلة للقياس', 'Complete a measurable habit'),
        (h, l, x) => h.any((hb) => hb.isMeasurable && hb.countCompletions() > 0)),
    Badge('consistent', Icons.rule, t('ثابت', 'Consistent'),
        t('نجاح ٨٠٪+ خلال ٣٠ يوماً', '80%+ success over 30 days'),
        (h, l, x) => h.any((hb) => hb.countCompletions() > 0 && hb.rateLastN(30) >= 80)),
    Badge('clean7', Icons.eco, t('سلسلة نقية', 'Clean Streak'),
        t('٧ أيام نقية على عادة إقلاع', '7 clean days on a quit habit'),
        (h, l, x) => h.where((hb) => hb.isQuit).fold<int>(0, (m, hb) => m > hb.longestStreak() ? m : hb.longestStreak()) >= 7),
    Badge('scholar', Icons.school, t('عالِم', 'Scholar'),
        t('أنجز ١٠ أهداف قابلة للقياس', 'Complete 10 measurable goals'),
        (h, l, x) => h.fold<int>(0, (s, hb) => s + (hb.isMeasurable ? hb.countCompletions() : 0)) >= 10),
    Badge('runner', Icons.flag, t('نادي ١٠٠', '100 Club'),
        t('أنجز ١٠٠ تسجيلاً هذا الأسبوع', 'Complete 100 logs this week'),
        (h, l, x) => _hundredWeek(h)),
    Badge('focus', Icons.filter_center_focus, t('تركيز كامل', 'Full Focus'),
        t('أنجز أسبوعاً مثالياً في عادة واحدة', 'Complete a perfect week on one habit'),
        (h, l, x) => _singlePerfectWeek(h)),
    Badge('pro', Icons.workspace_premium, t('داعم برو', 'Pro Supporter'),
        t('فعّل برو', 'Activate Pro'), (h, l, x) => AuthService.isProUser),
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
      final day = parseDayKey(key);
      final done = habits.where((h) => h.isDoneOn(day)).length;
      if (done == habits.length) return true;
    }
    return false;
  }

  static bool _perfectWeekEver(List<Habit> habits) {
    if (habits.length < 2) return false;
    for (var offset = 0; offset < 60; offset++) {
      final start = DateTime.now().subtract(Duration(days: 7 + offset));
      var ok = true;
      for (var i = 0; i < 7; i++) {
        final day = start.add(Duration(days: i));
        if (habits.where((h) => h.isDoneOn(day)).length != habits.length) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  static bool _hundredWeek(List<Habit> habits) =>
      habits.fold<int>(0, (s, h) => s + h.daysDoneInRange(DateTime.now().subtract(const Duration(days: 6)), DateTime.now())) >= 100;

  static bool _singlePerfectWeek(List<Habit> habits) {
    if (habits.isEmpty) return false;
    for (final h in habits) {
      if (h.numberOfStreaks >= 6) return true;
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
    final earned = all().where((b) => b.earned(habits, level, xp)).toList();
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

// ---------- Daily challenge ----------

class ChallengeSystem {
  static const _names = [
    'kill_it', 'noon', 'measurable', 'streak', 'combo', 'earlybird'
  ];

  static ({String id, String title, String desc, int target, int xp}) today(
      List<Habit> habits) {
    final now = DateTime.now();
    final dayIdx =
        (now.year * 372 + now.month * 31 + now.day) % _names.length;
    final measurable =
        habits.where((h) => h.isMeasurable && h.isDueOn(now)).toList();
    final dueToday = habits.where((h) => h.isDueOn(now)).length;

    switch (dayIdx) {
      case 1:
        return measurable.isNotEmpty
            ? (id: 'measurable', title: t('حقّق هدفك 🎯', 'Hit your goal 🎯'),
                desc: t('صل لهدفك في "${measurable.first.name}" اليوم.',
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
            desc: t('أنجز عادة قبل الساعة ١٢:٠٠.',
                'Complete a habit before 12:00.'),
            target: 1, xp: 45);
      case 4:
        return (id: 'streak', title: t('في انطلاق 🌀', 'Keep it going 🌀'),
            desc: t('أنجز اليوم لتبقي سلسلتك حيّة.',
                'Complete today to keep your streak alive.'),
            target: 1, xp: 40);
      case 5:
        return (id: 'earlybird', title: t('طائر مبكر 🐦', 'Early bird 🐦'),
            desc: t('أنجز عادة قبل الساعة ١٠:٠٠.',
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
    final now = DateTime.now();
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
      List<Habit> habits, String id, int target) async {
    final date = dayKey(DateTime.now());
    if (await isClaimed(date)) return (done: true, xp: 0, leveled: false);
    final prog = await progress(habits, id);
    if (prog < target) return (done: false, xp: 0, leveled: false);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(date), 'done|$id');
    final res = await XpSystem.add(40);
    return (done: true, xp: 40, leveled: res.leveledUp);
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
    if (DateTime.now().millisecondsSinceEpoch - last <
        30 * 24 * 3600 * 1000) {
      return;
    }
    _promptedInSession = true;
    await p.setInt('rating_last_prompt', DateTime.now().millisecondsSinceEpoch);
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
          'https://play.google.com/store/apps/details?id=com.zeyad.habit_tracker';
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
    _loadHabits();
    _refreshXp();
    _loadExtras();
    NotificationService.init();
  }

  Future<void> _loadExtras() async {
    if (!AuthService.isProUser) return;
    final chal = ChallengeSystem.today(habits);
    final prog = await ChallengeSystem.progress(habits, chal.id);
    final claimed = await ChallengeSystem.isClaimed(dayKey(DateTime.now()));
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
  }

  void _deleteHabit(int index) {
    NotificationService.cancelHabit(habits[index].id);
    setState(() => habits.removeAt(index));
    _saveHabits();
  }

  void _showAddDialog() {
    if (!AuthService.isProUser && habits.length >= 3) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cardColor(Theme.of(context).brightness),
          title: Text(t('وصلت لحد الإصدار المجاني 🚧', 'You hit the free limit 🚧')),
          content: Text(t(
              'النسخة المجانية تسمح حتى ٣ عادات.\n\nرقّي إلى برو لعادات غير محدودة وبلا إعلانات والمزيد.',
              'The free version allows up to 3 habits.\n\nUpgrade to Pro for unlimited habits, no ads and more.')),
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
    showHabitDialog(context, onSave: (habit) {
      _addHabit(habit);
    });
  }

  Future<void> _toggleToday(Habit habit) async {
    final now = DateTime.now();
    final today = dayKey(now);
    if (habit.isMeasurable) {
      await _recordAmount(habit);
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
    if (completing) await _award(habit);
    if (completing) _cheer();
    if (completing &&
        habits.isNotEmpty &&
        habits.every((h) => h.isDoneOn(now))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('🎉 يوم مثالي! أنهيت كل عاداتك!',
                '🎉 Perfect day! You completed all your habits!')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 2200),
          ),
        );
      }
    }
    if (completing) await _checkMilestones();
    if (mounted) {
      await RatingService.maybePrompt(context,
          count: _totalCompletions, habits: habits.length);
    }
  }

  Future<void> _recordAmount(Habit habit) async {
    if (!AuthService.isProUser) {
      showProUpgrade(context,
          message: t(
              'تسجيل التقدم في العادات القابلة للقياس من مميزات برو.',
              'Logging progress on measurable habits is a Pro feature.'));
      return;
    }
    final now = DateTime.now();
    final today = dayKey(now);
    final recorded = habit.amountOn(now);
    final remaining = habit.target - recorded;
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        title: Text(t('سجّل "${habit.name}"', 'Log "${habit.name}"')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(
                'اليوم: ${_fmt(recorded)} / ${_fmt(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
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
                    label: Text('+${_fmt(q)}'),
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
    final idx = DateTime.now().millisecondsSinceEpoch % _cheersEn.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Language.isAr ? _cheersAr[idx] : _cheersEn[idx]),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _award(Habit habit) async {
    if (!AuthService.isProUser) return;
    const streakBonus = {7: 50, 30: 150, 100: 500, 365: 2000};
    final streak = habit.currentStreak();
    final bonus = streakBonus[streak] ?? 0;
    final res = await XpSystem.add(10 + bonus);
    await _refreshXp();
    if (!mounted) return;
    if (res.leveledUp) {
      _showLevelUp(res.level);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bonus > 0
              ? t('🔥 سلسلة $streak يوم! +${10 + bonus} XP',
                  '🔥 $streak-${streak == 1 ? 'day' : 'day'} streak! +${10 + bonus} XP')
              : '+10 XP ⚡'),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setMood(int mood) async {
    await MoodSystem.save(mood);
    await _loadExtras();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mood >= 4
            ? t('أجواء رائعة اليوم +5 XP ✨', 'Great mood today +5 XP ✨')
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
    if (!AuthService.isProUser) return;
    final newly =
        await BadgeSystem.evaluate(habits, _level, _xp, awardXp: false);
    for (final _ in newly) {
      await XpSystem.add(25);
    }
    await _refreshXp();
    await _loadExtras();
    final challenge = ChallengeSystem.today(habits);
    final res = await ChallengeSystem.maybeComplete(
        habits, challenge.id, challenge.target);
    if (!mounted) return;
    if (newly.isNotEmpty) _showBadgeUnlocked(newly);
    if (res.done && res.xp > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('🎯 اكتمل التحدي اليومي! +${res.xp} XP',
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
                  child: Text(t('رائع +25 XP', 'Awesome +25 XP')),
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
                      Text(t('$xpIn / $need XP حتى المستوى التالي',
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
    final due = habits.where((h) => h.isDueOn(DateTime.now())).toList();
    if (due.isEmpty) return 0;
    final done = due.where((h) => h.isDoneOn(DateTime.now())).length;
    return done / due.length;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    final brightness = Theme.of(context).brightness;
    final now = DateTime.now();
    final quote = quoteFor(now);

    final done = habits.where((h) => h.isDoneOn(DateTime.now())).length;
    String headline;
    String sub;
    if (habits.isEmpty) {
      headline = t('جاهز تبني يومك؟ 💪', 'Ready to build your day? 💪');
      sub = t('أضف أول عادة وابدأ صغيراً.', 'Add your first habit and start small.');
    } else if (done == 0) {
      headline = t("لنُنجز اليوم 💪", "Let's get it done today 💪");
      sub = t('انتهيت من $done من ${habits.length} عادات حتى الآن.',
          'Finished $done of ${habits.length} habits so far.');
    } else if (done < habits.length) {
      headline = t("أنت على نار 🔥", "You're on fire 🔥");
      sub = t('انتهيت من $done من ${habits.length} عادات. استمر!',
          'Finished $done of ${habits.length} habits. Keep going!');
    } else {
      headline = t('يوم مثالي! 🎉', 'Perfect day! 🎉');
      sub = t('أنهيت كل الـ ${habits.length} عادات. لا أحد يوقفك!',
          'You completed all ${habits.length} habits. Nothing stops you!');
    }
    final greeting = now.hour < 12
        ? t('صباح الخير', 'Good morning')
        : now.hour < 18
            ? t('مساء الخير', 'Good evening')
            : t('مساء الخير', 'Good evening');

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$greeting, ${AuthService.name ?? t('صديقي', 'friend')} 👋',
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
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ],
                ),
                const Spacer(),
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
            if (AuthService.isProUser) ...[
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
                          Text(t('المستوى $_level — إجمالي $_xp XP',
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
                            t('${XpSystem.xpInLevel(_xp)} / ${XpSystem.xpToNextLevel(_xp)} XP حتى المستوى التالي',
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
                                    value: _challenge!.target == 0
                                        ? 0
                                        : (_challengeProg / _challenge!.target)
                                            .clamp(0.0, 1.0),
                                    minHeight: 8,
                                    backgroundColor: secondaryColor(brightness),
                                    color: primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text('$_challengeProg/${_challenge!.target}',
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
  Text(t('🔥 $_moodStreak أيام', '🔥 $_moodStreak days'),
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
              const SizedBox(height: 12),
              if (_insights.isNotEmpty)
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
                                  color: Colors.grey.shade300)),
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
                final done = habit.isDoneOn(DateTime.now());
                final streak = habit.currentStreak();
                final amount = habit.amountOn(DateTime.now());
                return Dismissible(
                  key: Key(habit.name + i.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
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
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      onTap: () {
                        if (!AuthService.isProUser) {
                          showProUpgrade(context,
                              message: t(
                                  'تفاصيل العادة والسلاسل والتاريخ من مميزات برو.',
                                  'Habit details, streaks and history are a Pro feature.'));
                          return;
                        }
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
                            color: Colors.white, size: 26),
                      ),
                      title: Text(
                        habit.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                          color: done ? Colors.white : null,
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
                                            ? Colors.white.withAlpha(50)
                                            : secondaryColor(brightness),
                                        color: done
                                            ? Colors.white
                                            : primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${_fmt(amount)}/${_fmt(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
                                    style: TextStyle(
                                        color: done
                                            ? Colors.white
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
                                  if (AuthService.isProUser &&
                                      streak > 0) ...[
                                    if (done) ...[
                                      const Icon(
                                          Icons.local_fire_department,
                                          color: Colors.white60,
                                          size: 14),
                                      const SizedBox(width: 3),
                                      Text(
                                          t('$streak يوم',
                                              streak == 1
                                                  ? '$streak day'
                                                  : '$streak days'),
                                          style: const TextStyle(
                                              color: Colors.white60,
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
                                                  t(
                                                      '$streak يوم',
                                                      streak == 1
                                                          ? '$streak day'
                                                          : '$streak days'),
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
                                  if (habit.isWeekly &&
                                      habit.weekdays.length < 7)
                                    Text(_weekdayShort(habit.weekdays),
                                        style: TextStyle(
                                            color: done
                                                ? Colors.white60
                                                : Colors.grey.shade500,
                                            fontSize: 11)),
                                  if (habit.isFlexible)
                                    Text(
                                        t(
                                            '${habit.timesPerWeek}x/أسبوع',
                                            '${habit.timesPerWeek}x/week'),
                                        style: TextStyle(
                                            color: done
                                                ? Colors.white60
                                                : Colors.grey.shade500,
                                            fontSize: 11)),
                                  if (habit.isQuit &&
                                      !habit.isMeasurable)
                                    Text(
                                        (AuthService.isProUser &&
                                                streak > 0)
                                            ? t(
                                                '🍃 أنظف · $streak يوم',
                                                '🍃 Clean · $streak ${streak == 1 ? 'day' : 'days'}')
                                            : t('حافظ على نظافتها',
                                                'Keep it clean'),
                                        style: TextStyle(
                                            color: done
                                                ? Colors.white60
                                                : Colors.grey.shade500,
                                            fontSize: 11)),
                                  if (habit.reminderEnabled) ...[
                                    const SizedBox(width: 10),
                                    Icon(
                                        Icons
                                            .notifications_active_outlined,
                                        size: 14,
                                        color: done
                                            ? Colors.white60
                                            : Colors.grey.shade500),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                      trailing: GestureDetector(
                        onTap: () => _toggleToday(habit),
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
                );
              }),
            const SizedBox(height: 20),
          ],
        ),
      ),
      floatingActionButton: Material(
        color: Colors.transparent,
        child: Ink(
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
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _showAddDialog,
            child: const Icon(Icons.add, color: Colors.white, size: 30),
          ),
        ),
      ),
      bottomNavigationBar: AuthService.isProUser
          ? null
          : const AdBannerWidget(),
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
    if (index == 1 && !AuthService.isProUser) {
      showProUpgrade(
        context,
        message: t(
            'الإحصائيات الأسبوعية والإنجازات وخريطة عاداتك من مميزات برو.',
            'Weekly stats, achievements and your habit map are Pro features.'),
      );
      return;
    }
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

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() {}),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
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
    if (_banner == null) return const SizedBox.shrink();
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
          curve: Curves.easeOutBack,
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
                        padding: const EdgeInsets.only(left: 8),
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

class ProPage extends StatelessWidget {
  const ProPage({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;

    final features = [
      (Icons.block, t('بلا إعلانات', 'No ads'),
          t('إزالة كل الإعلانات نهائياً', 'Remove all ads for good')),
      (Icons.all_inclusive, t('عادات غير محدودة', 'Unlimited habits'),
          t('أضف عدداً غير محدود من العادات', 'Add an unlimited number of habits')),
      (Icons.cloud_done, t('نسخ احتياطي واستعادة', 'Backup & restore'),
          t('احفظ واستعد بياناتك في أي وقت', 'Save and restore your data anytime')),
      (Icons.new_releases, t('مميزات جديدة أولاً', 'New features first'),
          t('احصل على كل ميزة جديدة قبل أي شخص آخر',
              'Get every new feature before anyone else')),
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
              gradient: LinearGradient(
                colors: [primary, primary.withAlpha(150)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Image.asset(
                  brightness == Brightness.dark
                      ? 'assets/icon/logo_white.png'
                      : 'assets/icon/logo_black.png',
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
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('\$2.99',
                        style: TextStyle(
                            fontSize: 40, fontWeight: FontWeight.bold)),
                    Text(t(' /شهر', '/month'),
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),
                if (AuthService.isProUser)
                  Column(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green,
                          size: 40),
                      const SizedBox(height: 8),
                      Text(
                        AuthService.isOwner
                            ? t('حساب المالك — برو مفعّل مجاناً 👑',
                                'Owner account — Pro enabled for free 👑')
                            : t('أنت عضو برو ✅', 'You are a Pro member ✅'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await AuthService.setPro(true);
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: cardColor(brightness),
                              title: Text(t('أهلاً بك في برو! 🎉',
                                  'Welcome to Pro! 🎉')),
                              content: Text(t(
                                  'جميع ميزات برو مفعّلة الآن.\n(شراء تجريبي — اربط الفوترة الحقيقية قبل الإطلاق)',
                                  'All Pro features are now enabled.\n(Trial purchase — wire real billing before launch)')),
                              actions: [
                                FilledButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    Navigator.pop(context);
                                  },
                                  child: Text(t('رائع', 'Awesome')),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(backgroundColor: primary),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(t('رقِّ الآن', 'Upgrade now'),
                            style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('فوترة تجريبية — أضف Google Play Billing للمتجر الفعلي.',
                'Demo billing — add Google Play Billing for the real store.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
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
  required void Function(Habit habit) onSave,
}) {
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
  bool isQuit = existing?.isQuit ?? false;
  bool reminderOn = existing?.reminderEnabled ?? false;
  TimeOfDay reminderTime = TimeOfDay(
    hour: existing?.reminderHour ?? 20,
    minute: existing?.reminderMinute ?? 0,
  );
  final icons = Habit.availableIcons;
  const weekDays = [1, 2, 3, 4, 5, 6, 7];

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
        content: SingleChildScrollView(
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
              const SizedBox(height: 16),
              Text(t('التكرار', 'Frequency'),
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(t('يومي', 'Daily'))),
                  ButtonSegment(value: 1, label: Text(t('أسبوعي', 'Weekly'))),
                  ButtonSegment(value: 2, label: Text(t('عدد مرات', 'Times a week'))),
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
                title: Text(t('قابلة للقياس (هدف ووحدة)', 'Measurable (goal & unit)')),
                subtitle: Text(t('مثال: صفحات، دقائق، أكواب ماء',
                    'Example: pages, minutes, cups of water')),
                value: measurable,
                onChanged: (v) {
                  if (v && !AuthService.isProUser) {
                    showProUpgrade(ctx,
                        message: t(
                            'العادات القابلة للقياس (أهداف ووحدات مثل الصفحات والدقائق…) من مميزات برو.',
                            'Measurable habits (goals and units like pages, minutes…) are a Pro feature.'));
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
                title: Text(t('ذكّرني', 'Remind me')),
                subtitle: Text(reminderOn
                    ? t('في ${reminderTime.format(context)}',
                        'At ${reminderTime.format(context)}')
                    : t('اضبط تذكيراً يومياً لهذه العادة',
                        'Set a daily reminder for this habit')),
                value: reminderOn,
                onChanged: (v) async {
                  if (v && !AuthService.isProUser) {
                    showProUpgrade(ctx,
                        message: t(
                            'التذكير اليومي للعادة من مميزات برو.',
                            'Daily habit reminders are a Pro feature.'));
                    return;
                  }
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
            ],
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
              if (name.isEmpty) return;
              final target = double.tryParse(
                      targetController.text.trim().replaceAll(',', '.')) ??
                  0;
              final habit = Habit(
                name: name,
                iconIndex: selectedIndex,
                id: existing?.id,
                completedDates: existing?.completedDates,
                amounts: existing?.amounts,
                frequency: frequency,
                weekdays:
                    frequency == 1 ? List.of(weekdays) : [1, 2, 3, 4, 5, 6, 7],
                timesPerWeek: frequency == 2 ? timesPerWeek : 7,
                target: measurable ? (target > 0 ? target : 1) : 0,
                unit: measurable ? unitController.text.trim() : '',
                isQuit: isQuit,
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
  int _rate30 = 0;

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
    _rate30 = habit.rateLastN(30);
  }

  Future<void> _recordNow() async {
    final habit = widget.habit;
    final now = DateTime.now();
    final wasDone = habit.isDoneOn(now);
    final controller = TextEditingController();
    final recorded = habit.amountOn(now);
    final remaining = habit.target - recorded;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        title: Text(t('سجّل "${habit.name}"', 'Log "${habit.name}"')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(
                'اليوم: ${_fmtD(recorded)} / ${_fmtD(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
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
                    label: Text('+${_fmtD(q)}'),
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
    });
    _compute();
    widget.onUpdate(habit);
    if (!wasDone && habit.isDoneOn(now)) {
      final res = await XpSystem.add(10);
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
            'حذف "${widget.habit.name}" وكل تاريخها؟ لا يمكن التراجع عن هذا.',
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
    final today = DateTime.now();

    // heatmap: 12 weeks aligned to Sunday
    final start = today.subtract(Duration(days: 77 + (today.weekday % 7)));

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
                    t('اليوم: ${_fmtD(habit.amountOn(today))} / ${_fmtD(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}',
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
          Row(
            children: [
              _StatCard(
                title: t('السلسلة الحالية', 'Current streak'),
                value: t('$_currentStreak يوم',
                    '$_currentStreak ${_currentStreak == 1 ? 'day' : 'days'}'),
                icon: Icons.local_fire_department,
                color: Colors.orange,
              ),
              const SizedBox(width: 12),
              _StatCard(
                title: t('أطول سلسلة', 'Longest streak'),
                value: t('$_longestStreak يوم',
                    '$_longestStreak ${_longestStreak == 1 ? 'day' : 'days'}'),
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
                title: t('آخر 30 يوم', 'Last 30 days'),
                value: '$_rate30%',
                icon: Icons.percent,
                color: Colors.blue,
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
                      padding: const EdgeInsets.only(right: 4),
                      child: Column(
                        children: List.generate(7, (row) {
                          final day = start.add(Duration(days: col * 7 + row));
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

  List<double> _last7DaysPercent() {
    final today = DateTime.now();
    return List.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      if (habits.isEmpty) return 0.0;
      final done = habits.where((h) => h.isDoneOn(day)).length;
      return done / habits.length * 100;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;
    final week = _last7DaysPercent();
    final todayIndex = DateTime.now().weekday % 7;
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
        final d = DateTime.now().subtract(Duration(days: i));
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

    final achievements = BadgeSystem.all().map((b) {
      final earned = b.earned(habits, _level, _xp);
      return (b.icon, b.title, b.desc, earned && unlocked.contains(b.id));
    }).toList();

    return Scaffold(
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
                      Text(t('المستوى $_level · $_xp XP', 'Level $_level · $_xp XP'),
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
                value: t('$currentStreakAny يوم',
                    '$currentStreakAny ${currentStreakAny == 1 ? 'day' : 'days'}'),
                icon: Icons.local_fire_department,
                color: Colors.deepOrange,
              ),
              const SizedBox(width: 12),
              _StatCard(
                title: t('أفضل سلسلة', 'Best streak'),
                value: t('$bestStreak يوم', '$bestStreak ${bestStreak == 1 ? 'day' : 'days'}'),
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
                        dayAxisLabel(value.toInt()),
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
                                      DateTime.now().month &&
                                  monthData[i].year == DateTime.now().year
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
                                      ? ' · ${h.target.toStringAsFixed(h.target.truncateToDouble() == h.target ? 0 : 1)} ${h.unit.trim()}'
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
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    final gridStart =
        Habit.mondayOf(todayMid.subtract(const Duration(days: 364)));
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
          final weekMonday = gridStart.add(Duration(days: col * 7));
          if (weekMonday.month ==
              weekMonday.subtract(const Duration(days: 7)).month) {
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
                      child: Text(
                        label(c) ?? '',
                        style: const TextStyle(fontSize: 8),
                        overflow: TextOverflow.clip,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              for (var r = 0; r < 7; r++)
                Row(
                  children: [
                    for (var c = 0; c < colCount; c++)
                      slot(gridStart.add(Duration(days: c * 7 + r))),
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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('habits') ?? '[]';
    await Clipboard.setData(ClipboardData(text: raw));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(t('تم نسخ النسخة الاحتياطية! احفظها في مكان آمن 📋',
                'Backup copied! Store it somewhere safe 📋'))),
      );
    }
  }

  Future<void> _restoreBackup() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor(Theme.of(context).brightness),
        title: Text(t('استعادة نسخة احتياطية', 'Restore backup')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('الصق نص النسخة الاحتياطية أدناه:',
                'Paste your backup text below:')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              decoration: softInputDecoration(ctx,
                  hint: '[{"name": "...", ...}]'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('استعادة', 'Restore')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final list = jsonDecode(controller.text) as List;
      final habits = list
          .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('habits', jsonEncode(habits));
      HomePage.reload?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('تمت استعادة ${habits.length} عادة بنجاح ✅',
                  'Restored ${habits.length} habits successfully ✅'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('بيانات غير صالحة ❌', 'Invalid data ❌'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('الإعدادات', 'Settings')),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!AuthService.isProUser)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, primary.withAlpha(180)],
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
                subtitle: Text(t('بلا إعلانات • عادات غير محدودة • \$2.99/شهر',
                    'No ads • Unlimited habits • \$2.99/month'),
                    style: TextStyle(color: Colors.white.withAlpha(220))),
                trailing: const Icon(Icons.arrow_forward_ios,
                    color: Colors.white, size: 14),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProPage())),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(palette.length, (i) {
                    final selected =
                        HabitFlowApp.of(context)?._seed == palette[i];
                    return GestureDetector(
                      onTap: () {
                        if (!AuthService.isProUser) {
                          showProUpgrade(context,
                              message: t('ألوان التطبيق المخصصة من مميزات برو.',
                                  'Custom app colors are a Pro feature.'));
                          return;
                        }
                        HabitFlowApp.of(context)?.setTheme(i);
                      },
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
                ),
              ],
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
                  title: Text(t('إرسال إشعار تجريبي', 'Send a test notification')),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _testNotification,
                ),
              ],
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
              children: [
                SwitchListTile(
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
              ],
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
                Text(t('النسخ الاحتياطي', 'Backup & restore'),
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_file),
                  title: Text(t('تصدير نسخة', 'Export backup')),
                  subtitle: Text(t('انسخ بياناتك إلى الحافظة',
                      'Copy your data to the clipboard')),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _exportBackup,
                ),
                Divider(color: dividerColor(brightness)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download),
                  title: Text(t('استعادة نسخة', 'Restore backup')),
                  subtitle: Text(t('الصق بيانات النسخة الاحتياطية',
                      'Paste your backup data')),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _restoreBackup,
                ),
              ],
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
                const Text('HabitFlow v1.2',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(t('تتبّع عاداتك وابنِ سلسلة نجاحك. 💪',
                    'Track your habits and build your success streak. 💪'),
                    style: const TextStyle(color: Colors.grey)),
              ],
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
                Text(
                  t('الحساب: ${AuthService.email ?? '-'}${AuthService.isOwner ? ' 👑 المالك' : ''}',
                      'Account: ${AuthService.email ?? '-'}${AuthService.isOwner ? ' 👑 Owner' : ''}'),
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
        ],
      ),
    );
  }
}

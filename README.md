# HabitFlow

![HabitFlow icon](./assets/icon/icon.png)

تطبيق فلوتر لتتبّع العادات والأذكار اليومية بدعم كامل للغة العربية والإنجليزية، مع وضع داكن/فاتح وألوان سمة متعددة.

A Flutter habit-tracking app with full Arabic/English support, dark/light themes, and multiple theme colors.

## Features

- Habit tracking with daily progress
- Adhkar (daily remembrance) with a tasbih counter
- Qibla direction helper
- Bilingual UI (Arabic / English) with RTL support
- Dark and light themes
- Multiple theme color choices
- Auto-progress levels and badges

## Languages & Technologies

All programming languages used in this project:

| Language | Where it is used |
| --- | --- |
| **Dart** | Core app — all UI, logic and state in `lib/main.dart` (plus `test/widget_test.dart`) |
| **Kotlin** | Android host — `MainActivity.kt`, home-screen `HabitWidgetProvider.kt` |
| **Swift** | iOS / macOS host — `Runner/AppDelegate.swift`, macOS `MainFlutterWindow` |
| **C++** | Windows & Linux runner — windowing / embedding (`windows/runner`, `linux/runner`) |
| **C** | Desktop runner component used alongside C++ |
| **CMake** | Build configuration for Windows/Linux desktop targets |
| **HTML / CSS / JavaScript** | Web target (`web/` — generated Flutter web shell) |
| **XML** | Android manifest, resources, layouts and widget visuals (`android/app/src/main/res`) |
| **Gradle (KTS)** | Android build scripts (`android/build.gradle.kts`, `android/app/build.gradle.kts`) |
| **Objective-C** | iOS embedder support layer (generated) |
| **PowerShell** | Dev automation — build/test/seeding scripts used during development |

The **Dart** code in `lib/main.dart` contains the entire app logic and UI; every other language is the platform shell required to run Flutter on that OS.

## App Icon

Icon assets live in:

- `assets/icon/icon.png` — main app icon
- `assets/icon/logo_black.png` / `assets/icon/logo_white.png` — logo variants
- `android/app/src/main/res/mipmap-*/ic_launcher.png` — Android launcher icons
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — iOS/macOS app icons
- `web/icons/Icon-192.png` / `Icon-512.png` — web icons
- `windows/runner/resources/app_icon.ico` — Windows icon

## Getting Started

```bash
flutter pub get
flutter run
```

## Build

```bash
flutter build apk --release
```

Requires Flutter SDK. The compiled APK is not tracked in the repository.
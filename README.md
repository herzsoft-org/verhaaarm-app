# Verhåårm App

Flutter app for Verhåårm.
- Primary: Android
- Also: Flutter Web (Safari-compatible, optionally PWA)
- No App Store submission

## Tech
- Flutter
- REST API backend

## Local Development

### Prerequisites
- Flutter SDK
- Android Studio or SDK tools (for Android builds)

### Run (Android)
- `flutter pub get`
- `flutter run`

### Run (Web)
- `flutter pub get`
- `flutter run -d chrome`
For Safari testing, build and serve:
- `flutter build web`
- serve `build/web` via a local server

## Configuration
API base URL is configured via build-time config or a simple config file (decide early and keep it consistent).

## MVP Screens
- Login
- Landing (live events later)
- Fines (view own / view all depending on role)
- Create fine (SENIOR/HOUSEKEEPING)
- Exports (role-based)
- User management (ADMIN + SENIOR)

## License

This project is proprietary and closed source.

Copyright (c) 2026 Valentin Schecklein. All rights reserved.

No permission is granted to use, copy, modify, distribute, host, deploy, or
otherwise exploit this software without prior written permission.

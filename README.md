# Verhåårm App

Flutter frontend for **Verhåårm**, a custom administration app built for one specific club.

## Project Context

This repository is mainly meant as a portfolio project. Verhåårm was developed as a custom internal tool, so the screens, roles, and workflows are intentionally specific.

The app is built for **Android** and **Flutter Web / PWA** usage.

## What I Built

This app provides the mobile and web frontend for managing fines, attendance, tasks, suggestions, live events, notifications, user sessions, and role-based administration workflows.

The focus of the project was building a real-world Flutter application with authentication, API integration, push notifications, platform-specific behavior, and a responsive UI for both mobile and web.

## Technical Highlights

* **Flutter** app for Android and web/PWA
* REST API integration using **Dio**
* JWT-based authentication with persisted login state
* Secure token storage on native platforms
* Role-based UI and permission handling
* Structured routing with **GoRouter**
* Modular feature-based project structure
* Reactive state management with custom stores
* Push notifications for Android and web/PWA clients

    * Firebase Cloud Messaging
    * Web Push / service worker integration
* Native Android integration through MethodChannels
* Camera and image upload support
* PDF and file handling for exported or uploaded documents
* Local settings and cache handling
* Material Design 3 based UI with light/dark theme support
* Makefile-based commands for testing and builds

## Platform Support

* Android APK builds
* Flutter Web builds
* Safari-compatible PWA usage

## License

This project is licensed under the **GNU Affero General Public License v3.0
only**.

Copyright (c) 2026 Valentin Schecklein.

See the `LICENSE` file for the full license text.

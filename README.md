<div align="center">

# 🔔 Notification Reader

**Hear your messages, hands-free.**

A 100% free & local Android app that captures incoming notifications (WhatsApp, Gmail, LinkedIn, Instagram, Twitter, and more) — even while it's closed — queues them on-device, and reads them aloud with Text-to-Speech when you tap **Read Now**.

</div>

---

## 📖 Table of Contents

- [Overview](#overview)
- [Features](#-features)
- [How It Works](#-how-it-works)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
- [Updating the App](#-updating-the-app)
- [Permissions](#-permissions)
- [Privacy & Security](#-privacy--security)
- [Testing](#-testing)
- [Known Limitations](#-known-limitations)
- [Roadmap](#-roadmap)
- [License](#-license)

---

## Overview

Notification Reader is an **Android-exclusive** Flutter application built for accessibility and hands-free use. Instead of opening each messaging app to check notifications, you grant the app *notification listener access* once, and it silently captures incoming messages from the apps you choose — even when the app is closed. Whenever you're ready, a single tap reads every unread message out loud, sequentially, in the language of your choice.

> **Everything runs on-device.** No cloud APIs, no servers, no accounts, no paid SDKs — and no data ever leaves your phone.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔘 **Master Service Switch** | One prominent toggle to enable/disable notification capture entirely. When off, incoming notifications are ignored and never queued. |
| 🗓 **Retention History** | Choose how long messages stay queued: **1 Day**, **3 Days**, or **1 Week**. Older notifications are purged automatically. |
| 📱 **Dynamic App Filter** | Browse every user-installed app (with icons and names), and check only the apps whose notifications you want read. |
| 🌐 **Multilingual TTS** | Built-in support for **English**, **Hindi**, and **Kannada** voice models with an in-app language dropdown. |
| ⚡ **Speech Speed Control** | Adjust playback from **0.5×** to **2.0×** (default 1.0×) with a live slider. English is tuned so **1×** is a natural, comfortable pace. |
| 🔉 **Read Now Button** | A large central button with a live unread-count badge. Tapping it speaks each unread message in sequence, formatted as: <br> *"Message from [Sender] on [App Name]: [Message Content]"* |
| 🔁 **Replay / Re-listen** | A dedicated **Replay** button re-reads *every* queued message (read or unread) so you can listen again as many times as you want. |
| 💬 **Whole Conversation Reading** | When a contact sends several quick messages, the app merges them into one queue item instead of skipping the updates — the entire conversation is read, not just the first message. |
| 📥 **Background Capture** | A native Android service keeps journaling notifications while the app is **closed**, so messages are ready to read the moment you reopen it. |
| 🧹 **Clear Queue** | Instantly dump all stored notifications with a single tap. |
| 💾 **Local Persistence** | Settings *and* the notification queue are persisted on-device — **encrypted at rest** — and survive app restarts. |

---

## 🎯 How It Works

```text
┌─────────────────────┐      ┌──────────────────────┐      ┌─────────────────────┐
│  Android System     │      │  NotificationService │      │  TtsService         │
│  posts notification │ ───► │  · master switch?    │ ───► │  · language check   │
│  (WhatsApp, Gmail…) │      │  · app whitelisted?  │      │  · read queue aloud │
└─────────────────────┘      │  · not ongoing?      │      └─────────────────────┘
                             │  · merge & queue     │
                             └──────────┬───────────┘
                                        │ persists (encrypted at rest)
                                        ▼
                              ┌─────────────────────┐
                              │  "Read Now" tap     │
                              │  → speak unread     │
                              └─────────────────────┘
```

1. **Capture** — The notification listener service receives every notification posted to the system tray. While the app is open, events stream to the app instantly; while it's **closed**, they're journaled to app-private storage by a native service.
2. **Filter** — Notifications are dropped unless the master switch is on, the posting app is whitelisted, and the notification is a real message (silent/ongoing ones like media players are skipped).
3. **Queue** — Valid messages are stored locally, newest first, with a timestamp. The queue is persisted **encrypted at rest**, so nothing is lost if the app restarts. On launch, any journaled (closed-app) events are replayed through the exact same filters and merged in, and notifications already sitting in the tray (e.g. YouTube, LinkedIn, Phone Link messages that arrived earlier) are swept into the queue too — so anything on screen when you open the app gets read.
4. **Whole conversation, not just the first message** — Messaging apps re-post the *same* notification id for each new message. Instead of skipping those updates, the app merges them into the existing queue item, so when Alice sends "hey → hello → what → why", the app reads the entire conversation.
5. **Read** — Tapping **Read Now** applies your chosen language and speed (English is automatically scaled to a natural pace — 1× sounds like normal speech, not rushed), marks the messages as read, and speaks them one by one. **Replay** re-reads everything without changing the read state.
6. **Fallback** — If your chosen language's voice data isn't installed on the device, the app gracefully falls back to English and tells you.

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| Framework | [Flutter](https://flutter.dev) (latest stable, Material 3) |
| Language | Dart (strict types, non-nullable) |
| Target OS | Android only (min SDK 24) |
| State Management | Lightweight `ChangeNotifier` + `setState` — no heavy frameworks |
| Encrypted Storage | [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) — Android Keystore-backed encryption (one-time migration from legacy plain storage) |
| TTS Engine | [`flutter_tts`](https://pub.dev/packages/flutter_tts) |
| Notification Listener | [`notification_listener_service`](https://pub.dev/packages/notification_listener_service) |
| Installed Apps | [`installed_apps`](https://pub.dev/packages/installed_apps) |

---

## 📁 Project Structure

```text
voice_mail_reader/
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml              # Permissions + notification listener service
│       └── kotlin/.../
│           ├── MainActivity.kt              # Method channel: reads/clears the pending journal
│           └── NotificationPersistenceListener.kt # Journals notifications while app is closed
├── lib/
│   ├── main.dart                            # App entry, single-screen UI (5 section cards)
│   ├── models/
│   │   └── notification_model.dart          # NotificationItem schema + text merging
│   ├── services/
│   │   ├── settings_service.dart            # ChangeNotifier: settings (encrypted)
│   │   ├── notification_service.dart        # Queue manager + live/offline capture
│   │   └── tts_service.dart                 # flutter_tts wrapper + sequential reading loop
│   └── widgets/
│       └── app_selection_sheet.dart         # Bottom sheet with installed apps & checkboxes
├── test/
│   └── widget_test.dart                     # Unit tests (model, merging, settings)
├── docs/                                    # Original spec: PRD, architecture, tasks
└── pubspec.yaml                             # Dependencies & project metadata
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, 3.41+ / Dart 3.11+)
- Android SDK with **Android toolchain** (`flutter doctor` should pass for Android)
- A physical Android device (emulator works too, though real notifications are easier to trigger on a device)

> **Note:** iOS is intentionally out of scope — Apple's sandbox does not allow apps to read other apps' notifications.

### Setup

```bash
# 1. Get the dependencies
flutter pub get

# 2. Run the analyzer to confirm everything is clean
flutter analyze

# 3. Launch on a connected device
flutter run

# 4. Build a debug APK
flutter build apk --debug

# 5. Build a release APK (requires a signing config — see Android docs)
flutter build apk --release
```

### First-Launch Flow

1. Open the app and toggle the **Master switch** on.
2. Grant **notification access** when prompted (the system settings screen opens).
3. Tap **Choose apps** to pick which apps' notifications should be read.
4. Set your language and speech speed, then wait for messages to arrive.
5. Tap **Read Now** to hear them — and **Replay** (⟳) any time you want to listen again.

---

## 🔄 Updating the App

This app is **not** on the Play Store, so it never auto-updates — you install new builds manually. Builds are signed with the project's own keystore (`android/upload-keystore.jks`), so updates install **in place** and keep your data:

```bash
# Rebuild the release APK (signed with the project keystore)
flutter build apk --release

# Install over the existing app — settings, queue & permissions are preserved
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

- The keystore and `key.properties` are **gitignored** — back them up privately; losing them means the app can no longer be updated for people who installed it.
- If you ever get a **signature mismatch** error (e.g. the old app was installed from another computer or before release signing existed), uninstall first: `adb uninstall com.voicemailreader.voice_mail_reader` (this wipes app data), then install the new APK.
- Sharing: just send `build/app/outputs/flutter-apk/app-release.apk` (≈48 MB) via WhatsApp, Drive, or a GitHub Release. Recipients install it like any APK.

---

## 🔐 Permissions

The app requires a single special permission:

| Permission | Why |
|---|---|
| **Notification access** | Allows the app to observe notifications posted by other apps so they can be queued and read aloud. Granted via *Settings → Apps → Notification Reader → Notifications → Notification access* (or prompted in-app). |

Declared in the manifest (informational / used by plugins):

- `POST_NOTIFICATIONS` — used on Android 13+ if the app ever shows its own notifications.
- `BIND_NOTIFICATION_LISTENER_SERVICE` — required to bind the `NotificationListenerService` declared in the manifest.
- `QUERY_ALL_PACKAGES` — added by the `installed_apps` plugin so the app filter can list installed apps (local only).
- `INTERNET` — **debug builds only**, added automatically by Flutter for hot-reload/breakpoint tooling. Release builds contain **no** Internet permission.

The app handles denial gracefully: the status banner shows *"Notification access is off"*, and enabling the master switch without permission walks you through the system settings.

---

## 🔒 Privacy & Security

- **No network capability** — release builds request no Internet permission and the app contains no networking code, so data physically cannot leave the device.
- **Encrypted at rest** — settings and the notification queue are stored via `flutter_secure_storage` (Android Keystore–backed AES). Legacy plain-text data is automatically migrated once and then deleted.
- **Android sandbox** — app storage is private; other apps cannot read the queue.
- **No third-party trackers** — only four open-source local packages; no accounts, no analytics, no servers.
- **User-controlled scope** — the app only sees notifications from apps you explicitly whitelist, and the permission is revocable at any time.
- **Honest caveats** — like any on-device app, data is readable on a *rooted* phone or with physical access to an unlocked device; the app is signed with the project's own release keystore.

---

## 🧪 Testing

### Automated tests

```bash
flutter analyze   # static analysis — expect "No issues found!"
flutter test      # unit tests — 16 tests, expect "All tests passed!"
```

Coverage:

- `mergeNotificationTexts` — conversation merging: appending, superset/subset deduplication, and length capping.
- `NotificationItem` — spoken-text formatting (including empty-title/content fallbacks), JSON round-tripping, and `copyWith`.
- `TtsService.effectiveRate` — language-aware speech-speed scaling (English slowed to a natural pace, Indic languages unchanged).
- `SettingsService` — sane defaults, persistence across reloads (via encrypted storage), one-time legacy migration, whitelist toggling, and TTS-rate clamping.

### Manual testing on a device

1. **Permission & master switch** — toggle the master switch on → grant notification access → the banner shows *"Listening for notifications"*. (If the master switch is off, the banner warns you instead of claiming to listen.)
2. **Filter** — Choose apps → whitelist WhatsApp → send yourself a message from WhatsApp Web → the queue badge increments.
3. **Whole conversation** — send several quick messages in one chat → **Read Now** reads them all ("hey. hello. what. why…"), not just the first.
4. **Closed-app capture** — fully close the app (swipe from recents), have someone message you, reopen → the messages are waiting to be read.
5. **Replay** — after reading, tap the replay icon (⟳) to hear everything again.
6. **Retention & clear** — switch retention to 1 Day, then **Clear Queue** empties the badge instantly.
7. **Language fallback** — pick Hindi without voice data installed → app falls back to English and tells you.

---

## ⚠️ Known Limitations

- **Force-stopping the app disables capture.** Swiping the app away from recents is fine (the native listener keeps journaling), but *force-stopping* it via Android settings disables its components until the app is opened again.
- **Conversation length is capped.** Merged message text is capped at ~2,000 characters (most recent portion kept), so very long backlogs are trimmed for practical TTS playback.
- **Language voices must be installed on the device.** Hindi and Kannada require their voice data to be downloaded via the device's TTS settings. The app detects this and falls back to English with an on-screen notice.
- **Reading happens in the app, not in the background.** While the app is closed it silently *captures* messages (native journal + tray sweep on reopen) but cannot speak them aloud — Android suspends background processes. Open the app and tap **Read Now** to hear everything that arrived.

---

## 🗺 Roadmap

- [x] Background capture while the app is closed (native journal)
- [x] Read the entire conversation, not just the first message
- [x] Replay / re-listen already-read messages
- [x] Encrypted-at-rest storage
- [ ] Per-message "mark as read" / swipe-to-dismiss in a queue preview
- [ ] Message preview list on the main screen
- [ ] More TTS languages & custom voice selection
- [ ] Auto-read option when a message arrives

---

## 📄 License

This project is **100% free and open-source** — no subscriptions, no ads, no cloud. Use it, modify it, and share it.

---

<div align="center">

Made with ❤️ for accessibility — *"Read your messages, hands-free."*

</div>

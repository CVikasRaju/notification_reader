\# Product Requirements Document (PRD)



\## Project Name

Voice Mail Reader (Notification Reader App)



\## Overview

Voice Mail Reader is an Android-exclusive Flutter application designed to catch incoming system notifications (from WhatsApp, Gmail, LinkedIn, Instagram, Twitter, etc.) in the background, store them locally in a queue, and read them aloud using a Text-to-Speech (TTS) engine when the user clicks a primary "Read Now" button.



\## Primary Objectives

1\. \*\*Accessibility \& Hands-Free Use:\*\* Allow users to hear their unread messages without opening individual apps.

2\. \*\*100% Free \& Local:\*\* Zero external cloud APIs, zero servers, zero paid subscriptions. Everything operates locally on the Android device.

3\. \*\*Single-Screen Simplicity:\*\* A clean, uncluttered interface that puts all controls on one screen.



\## Target Platform

\* \*\*Android Only\*\* (Minimum SDK: 21). iOS is explicitly out of scope due to Apple sandbox restrictions on reading external app notifications.



\## Key Features \& Functional Requirements



\### 1. Master Service Switch

\* Prominent toggle on the main screen to enable/disable notification listening.

\* When disabled, incoming notifications are ignored and not queued.



\### 2. Notification Retention History

\* Options: `1 Day`, `3 Days`, `1 Week`.

\* Purges queued notifications older than the selected retention threshold.



\### 3. Dynamic Installed App Filter

\* Queries the Android system for all user-installed applications using native APIs.

\* Displays an interactive selector dialog/bottom sheet with app names and icons.

\* Only captures and queues notifications from user-checked applications.



\### 4. Multilingual Text-to-Speech (TTS)

\* Built-in support for \*\*English\*\*, \*\*Hindi\*\*, and \*\*Kannada\*\* voice models.

\* Dynamic language selection dropdown on the main UI.



\### 5. Audio Playback Controls

\* Speech Speed slider (range: $0.5\\times$ to $2.0\\times$, default: $1.0\\times$).

\* Clear Queue button to dump stored notifications instantly.



\### 6. Central "Read Now" Trigger

\* Large primary button showing the current unread count badge.

\* Triggers sequential playback of unread notifications formatted as:  

&#x20; \*"Message from \[Sender] on \[App Name]: \[Message Content]"\*


\# Technical Architecture \& Stack Specification



\## Technology Stack

\* \*\*Framework:\*\* Flutter (Latest Stable SDK)

\* \*\*Language:\*\* Dart

\* \*\*Target OS:\*\* Android



\## Essential Dependencies (`pubspec.yaml`)

```yaml

dependencies:

&#x20; flutter:

&#x20;   sdk: flutter

&#x20; flutter\_tts: ^3.8.3                      # Local Text-to-Speech playback

&#x20; notification\_listener\_service: ^2.2.0    # Android Notification Listener

&#x20; installed\_apps: ^1.4.0                   # Fetch installed packages \& icons

&#x20; shared\_preferences: ^2.2.2               # Persist user settings locally


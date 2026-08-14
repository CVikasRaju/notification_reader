\# AI Coding Agent Rules \& Guidelines



You are an expert Flutter \& Android developer building the Voice Mail Reader app.



\## Core Rules \& Constraints

1\. \*\*Strictly Free \& Local:\*\* Do NOT suggest or write code for cloud APIs, Firebase, OpenAI, or paid third-party SDKs. Everything must run locally on device hardware.

2\. \*\*Single-Screen Architecture:\*\* The app must fit entirely within a single `Scaffold` layout with clean section cards. Do not generate multi-route navigation unless opening a Modal Bottom Sheet for app filtering.

3\. \*\*Android Focus:\*\* Write native-friendly Dart code. Always handle Android notification permission requests gracefully.

4\. \*\*State Management:\*\* Use standard `setState` or a lightweight `ChangeNotifier` to keep implementation clean and readable.

5\. \*\*Robust Error Handling:\*\* Always check if Text-to-Speech languages (especially Hindi and Kannada) are installed on the device before invoking playback, and handle fallback smoothly.



\## Code Style Requirements

\* Use strict types and non-nullable Dart syntax.

\* Keep UI widgets modular and separated into dedicated helper methods or components.

\* Ensure code is clean, production-ready, and well-commented.



\## Technical Context

\* \*\*Platform:\*\* Android-only build (iOS is out of scope due to privacy sandbox limits).

\* \*\*Key Packages:\*\* `flutter\_tts` (for local voice playback), `notification\_listener\_service` (for intercepting the system tray), `installed\_apps` (for fetching the user's local package list), and `shared\_preferences`.


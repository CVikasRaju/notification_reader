\# Implementation Checklist for AI Agent



Execute the following tasks sequentially to build the complete project:



\- \[ ] \*\*Task 1: Project Initialization \& Configuration\*\*

&#x20; - Create standard Flutter project structure.

&#x20; - Update `pubspec.yaml` with `flutter\_tts`, `notification\_listener\_service`, `installed\_apps`, and `shared\_preferences`.

&#x20; - Update `android/app/src/main/AndroidManifest.xml` with required permissions and listener service configuration.



\- \[ ] \*\*Task 2: Service \& Storage Helper Layer\*\*

&#x20; - Create `settings\_service.dart` to save and load user settings (Master switch state, selected apps whitelist, retention duration, TTS rate, chosen language).

&#x20; - Create `notification\_model.dart` for the message schema.

&#x20; - Create `notification\_service.dart` to manage notification stream listener and queue operations.



\- \[ ] \*\*Task 3: Text-to-Speech (TTS) Integration\*\*

&#x20; - Build `tts\_service.dart` using `flutter\_tts`.

&#x20; - Implement methods to set rate, volume, pitch, and language (`en-US`, `hi-IN`, `kn-IN`).

&#x20; - Implement queue reading sequential loop with status callbacks.



\- \[ ] \*\*Task 4: App Selection Bottom Sheet\*\*

&#x20; - Build a bottom sheet widget using `installed\_apps` package.

&#x20; - Display list of installed apps with icons, names, and checkboxes.

&#x20; - Connect selection state to `SettingsService`.



\- \[ ] \*\*Task 5: Main Screen UI Build\*\*

&#x20; - Build single-screen Scaffold containing:

&#x20;   1. Header \& Master Enable/Disable Switch Card.

&#x20;   2. Retention History Selector Card (1 Day, 3 Days, 1 Week).

&#x20;   3. Filter Apps Card (button opening Task 4 bottom sheet).

&#x20;   4. TTS Settings Card (Language Dropdown \& Speech Speed Slider).

&#x20;   5. Action Card ("Read Now" central button with unread count badge + "Clear Queue" icon).



\- \[ ] \*\*Task 6: System Integration \& Sanity Check\*\*

&#x20; - Verify permission request flow on app start.

&#x20; - Ensure background listener appends to queue correctly.

&#x20; - Verify TTS properly speaks and empties queue upon button press.


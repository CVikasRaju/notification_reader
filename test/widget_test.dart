import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_mail_reader/models/notification_model.dart';
import 'package:voice_mail_reader/services/settings_service.dart';

/// In-memory fake for the flutter_secure_storage Android method channel.
class FakeSecureStorage {
  final Map<String, String> store = <String, String>{};

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? <Object?, Object?>{};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          final value = args['value'];
          if (key != null && value != null) store[key] = value as String;
          return null;
        case 'delete':
          if (key != null) store.remove(key);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'containsKey':
          return key != null && store.containsKey(key);
        default:
          return null;
      }
    });
  }
}

void main() {
  group('mergeNotificationTexts', () {
    test('appends distinct messages into one conversation', () {
      expect(mergeNotificationTexts('hey', 'hello'), 'hey. hello');
      expect(
        mergeNotificationTexts('hey. hello', 'what'),
        'hey. hello. what',
      );
    });

    test('keeps the longer text when one is a superset of the other', () {
      expect(mergeNotificationTexts('hey', 'hey hello'), 'hey hello');
      expect(mergeNotificationTexts('hey hello', 'hey'), 'hey hello');
    });

    test('identical text (journal replay) changes nothing', () {
      expect(mergeNotificationTexts('hey', 'hey'), 'hey');
    });

    test('handles empty inputs', () {
      expect(mergeNotificationTexts('', 'hello'), 'hello');
      expect(mergeNotificationTexts('hey', ''), 'hey');
      expect(mergeNotificationTexts('', ''), '');
    });

    test('caps accumulated text at the maximum length, keeping the tail', () {
      final big = 'a' * 1500;
      final merged = mergeNotificationTexts(big, 'b' * 1500);
      expect(merged.length, maxNotificationContentLength);
      expect(merged.endsWith('b' * 1500), isTrue);
    });
  });

  group('NotificationItem', () {
    test('spokenText formats as "Message from Sender on App: Content"', () {
      final item = NotificationItem(
        id: 1,
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'Alice',
        content: 'See you at 5pm',
        receivedAt: _epoch,
      );

      expect(
        item.spokenText,
        'Message from Alice on WhatsApp: See you at 5pm',
      );
    });

    test('spokenText falls back for missing title or content', () {
      final item = NotificationItem(
        id: 2,
        packageName: 'com.example',
        appName: 'Example',
        title: '',
        content: '',
        receivedAt: _epoch,
      );

      expect(
        item.spokenText,
        'Message from an unknown sender on Example: No message text',
      );
    });

    test('round-trips through JSON', () {
      final item = NotificationItem(
        id: 42,
        packageName: 'com.gmail',
        appName: 'Gmail',
        title: 'Newsletter',
        content: 'Weekly digest',
        receivedAt: _epoch,
        isRead: true,
      );

      final restored = NotificationItem.fromJson(item.toJson());

      expect(restored.id, item.id);
      expect(restored.packageName, item.packageName);
      expect(restored.appName, item.appName);
      expect(restored.title, item.title);
      expect(restored.content, item.content);
      expect(
        restored.receivedAt.millisecondsSinceEpoch,
        item.receivedAt.millisecondsSinceEpoch,
      );
      expect(restored.isRead, item.isRead);
    });

    test('copyWith replaces isRead', () {
      final item = NotificationItem(
        id: 1,
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'Alice',
        content: 'Hi',
        receivedAt: _epoch,
      );

      expect(item.copyWith(isRead: true).isRead, isTrue);
      expect(item.copyWith(isRead: true).title, item.title);
    });
  });

  group('SettingsService', () {
    late FakeSecureStorage fakeStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
      fakeStorage.install();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults are sane', () async {
      final settings = SettingsService();
      await settings.load();

      expect(settings.masterEnabled, isFalse);
      expect(settings.selectedApps, isEmpty);
      expect(settings.retention, RetentionOption.oneDay);
      expect(settings.ttsRate, 1.0);
      expect(settings.language, LanguageOption.english);
    });

    test('persists changes and reloads them from secure storage', () async {
      final settings = SettingsService();
      await settings.load();

      settings.setMasterEnabled(true);
      settings.setSelectedApps({'com.whatsapp', 'com.gmail'});
      settings.setRetention(RetentionOption.oneWeek);
      settings.setTtsRate(1.5);
      settings.setLanguage(LanguageOption.hindi);

      final reloaded = SettingsService();
      await reloaded.load();

      expect(reloaded.masterEnabled, isTrue);
      expect(reloaded.selectedApps, {'com.whatsapp', 'com.gmail'});
      expect(reloaded.retention, RetentionOption.oneWeek);
      expect(reloaded.ttsRate, 1.5);
      expect(reloaded.language, LanguageOption.hindi);
    });

    test('migrates legacy plain-text settings on first load', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.master_enabled': 'true',
        'settings.selected_apps': 'com.whatsapp|com.gmail',
        'settings.retention': 'oneWeek',
        'settings.tts_rate': '1.5',
        'settings.language': 'hindi',
      });

      final settings = SettingsService();
      await settings.load();

      expect(settings.masterEnabled, isTrue);
      expect(settings.selectedApps, {'com.whatsapp', 'com.gmail'});
      expect(settings.retention, RetentionOption.oneWeek);
      expect(settings.ttsRate, 1.5);
      expect(settings.language, LanguageOption.hindi);

      // Values now live in secure storage and legacy keys are removed.
      expect(fakeStorage.store['settings.master_enabled'], 'true');
      final legacy = await SharedPreferences.getInstance();
      expect(legacy.getString('settings.master_enabled'), isNull);
    });

    test('toggleApp adds then removes a package', () async {
      final settings = SettingsService();
      await settings.load();

      settings.toggleApp('com.instagram');
      expect(settings.selectedApps, contains('com.instagram'));

      settings.toggleApp('com.instagram');
      expect(settings.selectedApps, isNot(contains('com.instagram')));
    });

    test('tts rate is clamped to the supported range', () async {
      final settings = SettingsService();
      await settings.load();

      settings.setTtsRate(99);
      expect(settings.ttsRate, SettingsService.maxTtsRate);

      settings.setTtsRate(-1);
      expect(settings.ttsRate, SettingsService.minTtsRate);
    });
  });
}

final _epoch = DateTime.utc(2026, 1, 1);

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_mail_reader/models/notification_model.dart';
import 'package:voice_mail_reader/services/notification_service.dart';
import 'package:voice_mail_reader/services/settings_service.dart';
import 'package:voice_mail_reader/services/tts_service.dart';

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

    test('short repeated message is appended, not dropped', () {
      // "ok" already appeared in the conversation, but this is a genuinely new
      // message — it must not be silently discarded.
      expect(mergeNotificationTexts('hey. ok', 'ok'), 'hey. ok. ok');
    });

    test('substring that is not a strict prefix/suffix is appended', () {
      // "world" is a substring of "hello world" but not a prefix/suffix
      // relationship that indicates a conversation superset.
      expect(
        mergeNotificationTexts('hello world', 'world'),
        'hello world. world',
      );
    });

    test('equal-length different messages are appended', () {
      expect(mergeNotificationTexts('yes', 'nah'), 'yes. nah');
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

  group('TtsService.effectiveRate', () {
    test('English speech is scaled down so 1x is a natural pace', () {
      expect(TtsService.effectiveRate(LanguageOption.english, 1.0), 0.5);
      expect(TtsService.effectiveRate(LanguageOption.english, 2.0), 1.0);
      expect(TtsService.effectiveRate(LanguageOption.english, 0.5), 0.25);
    });

    test('Indic languages keep the user rate unchanged', () {
      expect(TtsService.effectiveRate(LanguageOption.hindi, 1.0), 1.0);
      expect(TtsService.effectiveRate(LanguageOption.kannada, 1.5), 1.5);
      expect(TtsService.effectiveRate(LanguageOption.hindi, 0.75), 0.75);
      expect(TtsService.effectiveRate(LanguageOption.kannada, 0.5), 0.5);
    });
  });

  group('NotificationService', () {
    late FakeSecureStorage fakeStorage;
    late SettingsService settings;
    late StreamController<ServiceNotificationEvent> controller;

    setUp(() async {
      fakeStorage = FakeSecureStorage();
      fakeStorage.install();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      settings = SettingsService();
      await settings.load();
      settings.setMasterEnabled(true);
      controller = StreamController<ServiceNotificationEvent>();
    });

    tearDown(() async {
      await controller.close();
    });

    NotificationService buildService() => NotificationService(
          settings,
          eventStream: controller.stream,
          activeNotificationsFetcher: () async => <ServiceNotificationEvent>[],
        );

    ServiceNotificationEvent ev({
      required int id,
      String packageName = 'com.whatsapp',
      String title = '',
      String content = '',
      bool hasRemoved = false,
      bool onGoing = false,
    }) =>
        ServiceNotificationEvent(
          id: id,
          title: title,
          canReply: false,
          haveExtraPicture: false,
          hasRemoved: hasRemoved,
          packageName: packageName,
          content: content,
          onGoing: onGoing,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          appIcon: null,
          extrasPicture: null,
          largeIcon: null,
        );

    Future<void> waitFor(
      bool Function() condition, {
      Duration timeout = const Duration(seconds: 2),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Condition not met within $timeout');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('only whitelisted apps are queued', () async {
      settings.setSelectedApps({'com.whatsapp'});
      final service = buildService();
      await service.initialize();

      controller.add(ev(id: 1, packageName: 'com.instagram', content: 'nope'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.queue, isEmpty);

      controller.add(ev(id: 2, packageName: 'com.whatsapp', content: 'yes'));
      await waitFor(() => service.queue.length == 1);
      expect(service.queue.single.content, 'yes');
    });

    test('same id re-post merges the full conversation, newest on top', () async {
      final service = buildService();
      await service.initialize();

      controller.add(ev(id: 5, content: 'hey'));
      await waitFor(() => service.queue.length == 1);

      controller.add(ev(id: 5, content: 'hello'));
      await waitFor(() => service.queue.single.content == 'hey. hello');

      controller.add(ev(id: 5, content: 'what'));
      await waitFor(() => service.queue.single.content == 'hey. hello. what');

      expect(service.queue.length, 1);
      expect(service.queue.single.isRead, isFalse);
    });

    test('identical re-post (journal replay of a live event) is a no-op',
        () async {
      final service = buildService();
      await service.initialize();

      controller.add(ev(id: 9, content: 'same'));
      await waitFor(() => service.queue.length == 1);
      final receivedAt = service.queue.single.receivedAt;

      controller.add(ev(id: 9, content: 'same'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.queue.length, 1);
      expect(service.queue.single.content, 'same');
      expect(service.queue.single.receivedAt, receivedAt);
    });

    test('expired notifications are purged on load', () async {
      final now = DateTime.now();
      final stale = NotificationItem(
        id: 1,
        packageName: 'com.oldapp',
        appName: 'OldApp',
        title: '',
        content: 'too old',
        receivedAt: now.subtract(const Duration(days: 3)),
      );
      final fresh = NotificationItem(
        id: 2,
        packageName: 'com.newapp',
        appName: 'NewApp',
        title: '',
        content: 'still fresh',
        receivedAt: now,
      );
      fakeStorage.store['queue.notifications'] =
          jsonEncode([stale.toJson(), fresh.toJson()]);

      final service = buildService();
      await service.initialize();

      expect(service.queue.length, 1);
      expect(service.queue.single.content, 'still fresh');
    });

    test('replays the offline journal captured while the app was closed',
        () async {
      var cleared = false;
      const pending = MethodChannel('voice_mail_reader/pending');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pending, (call) async {
        if (call.method == 'getPendingEvents') {
          return <Map<String, Object?>>[
            <String, Object?>{
              'event': 'posted',
              'id': 7,
              'packageName': 'com.whatsapp',
              'title': 'Alice',
              'text': 'Hello while you were away',
              'time': 123456789,
              'ongoing': false,
            },
          ];
        }
        if (call.method == 'clearPendingEvents') {
          cleared = true;
          return null;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pending, null);
      });

      final service = buildService();
      await service.initialize();

      expect(cleared, isTrue);
      expect(service.queue.length, 1);
      expect(service.queue.single.packageName, 'com.whatsapp');
      expect(service.queue.single.content, 'Hello while you were away');
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

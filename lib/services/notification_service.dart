import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_model.dart';
import 'settings_service.dart';

/// Method channel exposed by [MainActivity] to consume the native
/// pending-notification journal written while the app was closed.
const MethodChannel _pendingChannel = MethodChannel('voice_mail_reader/pending');

/// Manages the local queue of captured notifications.
///
/// Notifications are captured from two sources:
///
/// 1. **Live stream** — while the app is running, the Android listener pushes
///    events over the plugin's event channel for instant queue updates.
/// 2. **Offline journal** — while the app is closed, the native
///    [NotificationPersistenceListener] journals raw events to app storage.
///    On startup the journal is replayed through the same filtering logic, so
///    nothing is lost when the app is reopened.
///
/// Messaging apps re-post the SAME notification id for each new message, so
/// updates are merged into the existing queue item (accumulating the full
/// conversation) instead of being skipped.
///
/// The queue is persisted to encrypted storage ([FlutterSecureStorage]) with a
/// one-time migration from the legacy plain-text storage.
class NotificationService extends ChangeNotifier {
  static const String _keyQueue = 'queue.notifications';

  final SettingsService settings;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _prefs;
  StreamSubscription<ServiceNotificationEvent>? _subscription;

  /// Queue of captured notifications, newest first.
  List<NotificationItem> _queue = <NotificationItem>[];

  /// Cache of package name -> human readable app name.
  final Map<String, String> _appNameCache = <String, String>{};

  /// Events waiting to be processed. Serializes handling so bursts of
  /// notifications (WhatsApp/Instagram rapid-fire messages) are never dropped.
  final List<ServiceNotificationEvent> _pendingEvents =
      <ServiceNotificationEvent>[];

  /// Whether the serialized event loop is currently running.
  bool _processingEvents = false;

  /// Live event stream to listen on. Defaults to the Android notification
  /// listener's stream; injectable for tests.
  final Stream<ServiceNotificationEvent>? _eventStream;

  /// Fetcher for notifications already in the tray. Defaults to the plugin's
  /// implementation; injectable for tests.
  final Future<List<ServiceNotificationEvent>> Function()?
      _activeNotificationsFetcher;

  NotificationService(
    this.settings, {
    Stream<ServiceNotificationEvent>? eventStream,
    Future<List<ServiceNotificationEvent>> Function()?
        activeNotificationsFetcher,
  })  : _eventStream = eventStream,
        _activeNotificationsFetcher = activeNotificationsFetcher;

  /// Queue of captured notifications (newest first).
  List<NotificationItem> get queue => List.unmodifiable(_queue);

  /// Notifications that have not been read aloud yet.
  List<NotificationItem> get unread =>
      _queue.where((item) => !item.isRead).toList();

  /// Number of unread notifications (shown on the Read Now badge).
  int get unreadCount => unread.length;

  /// Loads the persisted queue, replays any offline-captured notifications
  /// and starts listening for live notifications.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadQueue();
    purgeExpired();
    // Replay notifications captured while the app was closed.
    await _consumePendingJournal();
    _subscription =
        (_eventStream ?? NotificationListenerService.notificationsStream)
            .listen(
      _onEvent,
      onError: (Object error) {
        debugPrint('Notification stream error: $error');
      },
    );
    // Pre-warm the app-name cache so queued items display friendly names.
    unawaited(_warmAppNameCache());
    // Sweep notifications already sitting in the tray (e.g. arrived while the
    // app was closed before the journal service bound) so they get read too.
    unawaited(_consumeActiveNotifications());
  }

  /// Re-sweeps notifications currently sitting in the system tray and consumes
  /// any offline pending journal entries. Called on app launch and resume.
  Future<void> refreshFromTray() async {
    purgeExpired();
    await _consumePendingJournal();
    await _consumeActiveNotifications();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  /// Handles a raw notification event from the live stream, the offline
  /// journal or the tray sweep. Events are processed one at a time in arrival
  /// order; none are dropped while another is being handled.
  Future<void> _onEvent(ServiceNotificationEvent event) async {
    _pendingEvents.add(event);
    if (_processingEvents) return;
    _processingEvents = true;
    try {
      while (_pendingEvents.isNotEmpty) {
        await _handleEvent(_pendingEvents.removeAt(0));
      }
    } finally {
      _processingEvents = false;
    }
  }

  Future<void> _handleEvent(ServiceNotificationEvent event) async {
    if (event.hasRemoved) {
      _removeById(event.packageName, event.id);
      return;
    }
    await _enqueue(event);
  }

  /// Adds a captured notification to the queue if it passes all filters.
  ///
  /// When the same notification id is re-posted (WhatsApp/Instagram update a
  /// chat notification with each new message), the existing queue item is
  /// updated and merged instead of skipped so the whole conversation is read.
  Future<void> _enqueue(ServiceNotificationEvent event) async {
    // Ignore everything when the master switch is off.
    if (!settings.masterEnabled) return;

    // Skip silent/empty notifications and ongoing ones (media players, etc.).
    if (event.onGoing) return;
    if (event.title.trim().isEmpty && event.content.trim().isEmpty) return;

    // Respect the user's app whitelist (empty whitelist = all apps).
    if (settings.hasAppFilter &&
        !settings.selectedApps.contains(event.packageName)) {
      return;
    }

    // Android notification ids are only unique per posting app, so match on
    // both the package name and the id.
    final existingIndex = _queue.indexWhere((item) =>
        item.packageName == event.packageName && item.id == event.id);

    if (existingIndex != -1) {
      _mergeUpdate(existingIndex, event);
      return;
    }

    final appName = await _resolveAppName(event.packageName);
    final item = NotificationItem(
      id: event.id,
      packageName: event.packageName,
      appName: appName,
      title: event.title,
      content: event.content,
      receivedAt: DateTime.now(),
    );

    _queue.insert(0, item);
    purgeExpired();
    notifyListeners();
    unawaited(_persistQueue());
  }

  /// Merges an update for an already-queued notification id.
  ///
  /// If the incoming text is identical to (or a subset of) what is stored —
  /// e.g. a journal replay of an event already handled live — nothing changes.
  /// Otherwise the text is merged (superset replaces, otherwise appended),
  /// the item is marked unread again and moved to the top so it gets read.
  void _mergeUpdate(int existingIndex, ServiceNotificationEvent event) {
    final existing = _queue[existingIndex];
    final incoming = event.content.trim();

    // No genuinely new text -> exact duplicate (journal replay), keep untouched.
    if (incoming.isEmpty || existing.content == incoming) return;

    final updated = existing.copyWith(
      title: event.title.trim().isNotEmpty ? event.title.trim() : existing.title,
      content: mergeNotificationTexts(existing.content, incoming),
      isRead: false,
      receivedAt: DateTime.now(),
    );

    _queue.removeAt(existingIndex);
    _queue.insert(0, updated);
    notifyListeners();
    unawaited(_persistQueue());
  }

  void _removeById(String packageName, int id) {
    final before = _queue.length;
    _queue.removeWhere((item) =>
        item.packageName == packageName && item.id == id);
    if (_queue.length != before) {
      notifyListeners();
      unawaited(_persistQueue());
    }
  }

  /// Removes queued notifications older than the selected retention period.
  void purgeExpired() {
    final cutoff =
        DateTime.now().subtract(settings.retention.duration);
    final before = _queue.length;
    _queue.removeWhere((item) => item.receivedAt.isBefore(cutoff));
    if (_queue.length != before) {
      notifyListeners();
      unawaited(_persistQueue());
    }
  }

  /// Marks all currently unread notifications as read.
  ///
  /// Returns the items that were marked read so the caller can speak them.
  List<NotificationItem> markAllRead() {
    final items = unread;
    if (items.isEmpty) return items;
    _queue = _queue
        .map((item) => item.isRead ? item : item.copyWith(isRead: true))
        .toList();
    notifyListeners();
    unawaited(_persistQueue());
    return items;
  }

  /// Empties the entire queue instantly.
  void clearQueue() {
    if (_queue.isEmpty) return;
    _queue = <NotificationItem>[];
    notifyListeners();
    unawaited(_persistQueue());
  }

  /// Replays the native journal of events captured while the app was closed,
  /// then clears it. Runs the same filters as live events so behavior is
  /// identical whether the app was open or closed.
  Future<void> _consumePendingJournal() async {
    List<dynamic>? events;
    try {
      events =
          await _pendingChannel.invokeMethod<List<dynamic>>('getPendingEvents');
    } catch (e) {
      debugPrint('Failed to read pending journal: $e');
      return;
    }
    if (events == null || events.isEmpty) return;

    for (final raw in events) {
      if (raw is! Map) continue;
      await _onEvent(_eventFromJournal(raw));
    }

    try {
      await _pendingChannel.invokeMethod<void>('clearPendingEvents');
    } catch (e) {
      debugPrint('Failed to clear pending journal: $e');
    }
  }

  /// Pulls notifications already present in the notification tray when the
  /// app opens and merges them into the queue.
  ///
  /// The live stream only reports *new* events, and the offline journal only
  /// records events that arrived after the listener service bound, so without
  /// this sweep, messages sitting in the tray when the app opens (YouTube,
  /// LinkedIn, Phone Link, …) would never be read. Deduplication in
  /// [_enqueue] keeps already-queued items untouched.
  Future<void> _consumeActiveNotifications() async {
    // The listener service connects asynchronously after launch; retry briefly
    // so the tray is readable even on a cold start.
    for (var attempt = 0; attempt < 8; attempt++) {
      List<ServiceNotificationEvent> active;
      try {
        active =
            await (_activeNotificationsFetcher ??
                NotificationListenerService.getActiveNotifications)();
      } catch (e) {
        debugPrint('Active notification sweep failed (attempt '
            '${attempt + 1}): $e');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        continue;
      }
      for (final event in active) {
        await _onEvent(event);
      }
      return;
    }
  }

  /// Converts a native journal entry into a [ServiceNotificationEvent].
  ServiceNotificationEvent _eventFromJournal(Map<dynamic, dynamic> raw) {
    final isRemoved = raw['event'] == 'removed';
    return ServiceNotificationEvent(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      canReply: false,
      haveExtraPicture: false,
      hasRemoved: isRemoved,
      packageName: (raw['packageName'] as String?) ?? '',
      title: (raw['title'] as String?) ?? '',
      content: (raw['text'] as String?) ?? '',
      onGoing: (raw['ongoing'] as bool?) ?? false,
      timestamp: (raw['time'] as num?)?.toInt() ?? 0,
      appIcon: null,
      extrasPicture: null,
      largeIcon: null,
    );
  }

  /// Resolves a package name to a friendly app name, using a cached lookup
  /// from the installed apps list. Falls back to the last package segment.
  Future<String> _resolveAppName(String packageName) async {
    final cached = _appNameCache[packageName];
    if (cached != null) return cached;

    String? name;
    try {
      final info = await InstalledApps.getAppInfo(packageName);
      name = info?.name;
    } catch (_) {
      // Fall through to the derived name below.
    }
    final resolved = (name == null || name.trim().isEmpty)
        ? _friendlyNameFromPackage(packageName)
        : name;
    _appNameCache[packageName] = resolved;
    return resolved;
  }

  /// Warm the cache with all installed app names in one call.
  Future<void> _warmAppNameCache() async {
    try {
      final apps =
          await InstalledApps.getInstalledApps(excludeSystemApps: false);
      for (final app in apps) {
        _appNameCache[app.packageName] = app.name;
      }
    } catch (_) {
      // Cache warming is best-effort; names resolve on demand otherwise.
    }
  }

  /// Turns e.g. "com.whatsapp" into "WhatsApp".
  String _friendlyNameFromPackage(String packageName) {
    final segments = packageName.split('.');
    if (segments.isEmpty) return packageName;
    final raw = segments.last;
    if (raw.isEmpty) return packageName;
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  Future<void> _loadQueue() async {
    String? raw;
    try {
      raw = await _secureStorage.read(key: _keyQueue);
    } catch (e) {
      debugPrint('Failed to read encrypted queue: $e');
    }

    if (raw == null || raw.isEmpty) {
      // One-time migration from the legacy plain-text storage.
      final legacy = _prefs?.getString(_keyQueue);
      if (legacy != null && legacy.isNotEmpty) {
        raw = legacy;
        await _prefs?.remove(_keyQueue);
      }
    }

    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _queue = decoded
          .whereType<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList();
      // Persist migrated data into encrypted storage.
      await _persistQueue();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load notification queue: $e');
    }
  }

  Future<void> _persistQueue() async {
    final encoded = jsonEncode(_queue.map((item) => item.toJson()).toList());
    try {
      await _secureStorage.write(key: _keyQueue, value: encoded);
    } catch (e) {
      debugPrint('Failed to persist queue: $e');
    }
  }
}

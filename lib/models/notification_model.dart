/// Notification model for the Notification Reader app.
///
/// Represents a single captured system notification that is stored in the
/// local queue and later spoken aloud by the Text-to-Speech engine.
library;

/// Upper bound for a merged notification's accumulated message text.
///
/// Android updates a chat notification with each new message (same id), and we
/// accumulate those updates so the whole conversation can be read aloud.
const int maxNotificationContentLength = 2000;

/// Merges newly received notification text into previously stored text.
///
/// Messaging apps (WhatsApp, Instagram, …) re-post the SAME notification id
/// with each new message. To read the entire conversation instead of only the
/// first message, updates are accumulated while avoiding duplication:
///
/// * if one text is a subset/superset of the other, the longer one wins;
/// * otherwise the new text is appended ("hey" + "hello" -> "hey. hello").
String mergeNotificationTexts(String existing, String incoming) {
  final base = existing.trim();
  final addition = incoming.trim();
  if (addition.isEmpty) return base;
  if (base.isEmpty) return addition;
  // Exact replay (e.g. journal re-delivering the same event) — no change.
  if (base == addition) return base;
  // Messaging apps re-post the full conversation with new text appended at
  // the end, so the incoming text strictly starts with the existing base. If
  // so, the incoming is a superset — use it. Conversely, if the base already
  // starts with the incoming text, the incoming is a stale shorter version
  // (e.g. a journal replay of an earlier event) — keep the base.
  if (addition.length > base.length && addition.startsWith(base)) {
    return addition;
  }
  if (base.length > addition.length && base.startsWith(addition)) {
    return base;
  }
  final merged = '$base. $addition';
  if (merged.length <= maxNotificationContentLength) return merged;
  // Keep the most recent portion if the conversation grows too long.
  return merged.substring(merged.length - maxNotificationContentLength);
}

/// A queued notification captured from the Android notification tray.
///
/// All fields are persisted to local storage so the queue survives app
/// restarts. [isRead] tracks whether the notification has already been
/// spoken by the "Read Now" action.
class NotificationItem {
  /// Unique id of the notification as reported by Android.
  final int id;

  /// Package name of the app that posted the notification (e.g. com.whatsapp).
  final String packageName;

  /// Human readable name of the posting app (e.g. WhatsApp).
  final String appName;

  /// Notification title (usually the message sender).
  final String title;

  /// Notification body text (the message content).
  final String content;

  /// When the notification was captured.
  final DateTime receivedAt;

  /// Whether this notification has already been read aloud.
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.content,
    required this.receivedAt,
    this.isRead = false,
  });

  /// Copy of this item with selectable fields replaced.
  NotificationItem copyWith({
    String? title,
    String? content,
    DateTime? receivedAt,
    bool? isRead,
  }) {
    return NotificationItem(
      id: id,
      packageName: packageName,
      appName: appName,
      title: title ?? this.title,
      content: content ?? this.content,
      receivedAt: receivedAt ?? this.receivedAt,
      isRead: isRead ?? this.isRead,
    );
  }

  /// The spoken sentence for this notification, as specified by the PRD:
  /// "Message from [Sender] on [App Name]: [Message Content]"
  String get spokenText {
    final sender = title.trim().isEmpty ? 'an unknown sender' : title.trim();
    final message = content.trim().isEmpty ? 'No message text' : content.trim();
    return 'Message from $sender on $appName: $message';
  }

  /// Serializes this item to a JSON map for persistence.
  Map<String, dynamic> toJson() => {
        'id': id,
        'packageName': packageName,
        'appName': appName,
        'title': title,
        'content': content,
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'isRead': isRead,
      };

  /// Deserializes a [NotificationItem] from a JSON map.
  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      packageName: (json['packageName'] as String?) ?? '',
      appName: (json['appName'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      // Timestamps are persisted as epoch milliseconds; keep them UTC so the
      // stored instant is unambiguous across timezone changes.
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['receivedAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      isRead: (json['isRead'] as bool?) ?? false,
    );
  }
}

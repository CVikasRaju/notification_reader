import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retention history options for how long queued notifications are kept.
enum RetentionOption {
  oneDay('1 Day', Duration(days: 1)),
  threeDays('3 Days', Duration(days: 3)),
  oneWeek('1 Week', Duration(days: 7));

  const RetentionOption(this.label, this.duration);

  /// Human readable label shown in the UI.
  final String label;

  /// How long notifications older than this are purged from the queue.
  final Duration duration;
}

/// Text-to-Speech language options supported by the app.
enum LanguageOption {
  english('English', 'en-US'),
  hindi('Hindi', 'hi-IN'),
  kannada('Kannada', 'kn-IN');

  const LanguageOption(this.label, this.locale);

  /// Human readable label shown in the UI.
  final String label;

  /// Locale code passed to the platform Text-to-Speech engine.
  final String locale;
}

/// Persists and exposes all user-configurable app settings.
///
/// A lightweight [ChangeNotifier]. Settings are stored in **encrypted**
/// on-device storage ([FlutterSecureStorage], backed by the Android Keystore)
/// with a one-time migration from the legacy plain-text storage, so nothing
/// sensitive is readable at rest.
class SettingsService extends ChangeNotifier {
  static const String _keyMasterEnabled = 'settings.master_enabled';
  static const String _keySelectedApps = 'settings.selected_apps';
  static const String _keyRetention = 'settings.retention';
  static const String _keyTtsRate = 'settings.tts_rate';
  static const String _keyLanguage = 'settings.language';

  /// Speech speed range supported by the app (0.5x - 2.0x).
  static const double minTtsRate = 0.5;
  static const double maxTtsRate = 2.0;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  SharedPreferences? _legacyPrefs;

  bool _masterEnabled = false;
  Set<String> _selectedApps = <String>{};
  RetentionOption _retention = RetentionOption.oneDay;
  double _ttsRate = 1.0;
  LanguageOption _language = LanguageOption.english;

  /// Master service switch. When false, incoming notifications are ignored.
  bool get masterEnabled => _masterEnabled;

  /// Package names of the apps the user whitelisted for capturing.
  Set<String> get selectedApps => Set.unmodifiable(_selectedApps);

  /// How long queued notifications are retained before being purged.
  RetentionOption get retention => _retention;

  /// Text-to-Speech playback rate (0.5x to 2.0x).
  double get ttsRate => _ttsRate;

  /// Text-to-Speech language chosen by the user.
  LanguageOption get language => _language;

  /// True if any app has been whitelisted; false means "capture all apps".
  bool get hasAppFilter => _selectedApps.isNotEmpty;

  /// Loads all settings from encrypted storage. Call once on app start.
  Future<void> load() async {
    _legacyPrefs = await SharedPreferences.getInstance();

    _masterEnabled = await _readBool(_keyMasterEnabled, fallback: false);
    _selectedApps =
        (await _readStringList(_keySelectedApps, fallback: const [])).toSet();
    _retention = _parseEnum(
      await _readString(_keyRetention),
      RetentionOption.values,
      RetentionOption.oneDay,
      (option) => option.name,
    );
    _ttsRate = (await _readDouble(_keyTtsRate, fallback: 1.0))
        .clamp(minTtsRate, maxTtsRate);
    _language = _parseEnum(
      await _readString(_keyLanguage),
      LanguageOption.values,
      LanguageOption.english,
      (option) => option.name,
    );

    notifyListeners();
  }

  void setMasterEnabled(bool enabled) {
    if (_masterEnabled == enabled) return;
    _masterEnabled = enabled;
    notifyListeners();
    _writeBool(_keyMasterEnabled, enabled);
  }

  /// Replaces the whitelisted app package names.
  void setSelectedApps(Set<String> packageNames) {
    _selectedApps = Set<String>.from(packageNames);
    notifyListeners();
    _writeStringList(_keySelectedApps, _selectedApps.toList());
  }

  /// Toggles a single app in the whitelist, preserving the rest.
  void toggleApp(String packageName) {
    final updated = Set<String>.from(_selectedApps);
    if (!updated.add(packageName)) {
      updated.remove(packageName);
    }
    setSelectedApps(updated);
  }

  void setRetention(RetentionOption option) {
    if (_retention == option) return;
    _retention = option;
    notifyListeners();
    _writeString(_keyRetention, option.name);
  }

  void setTtsRate(double rate) {
    final clamped = rate.clamp(minTtsRate, maxTtsRate);
    if (_ttsRate == clamped) return;
    _ttsRate = clamped;
    notifyListeners();
    _writeDouble(_keyTtsRate, clamped);
  }

  void setLanguage(LanguageOption option) {
    if (_language == option) return;
    _language = option;
    notifyListeners();
    _writeString(_keyLanguage, option.name);
  }

  // ---- Encrypted read/write helpers (with legacy migration) ----

  Future<String?> _readString(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) return value;
    } catch (e) {
      debugPrint('Failed to read encrypted setting "$key": $e');
    }
    // One-time migration from the legacy plain-text storage.
    final legacy = _legacyPrefs?.getString(key);
    if (legacy != null) {
      await _storage.write(key: key, value: legacy);
      await _legacyPrefs?.remove(key);
      return legacy;
    }
    return null;
  }

  Future<bool> _readBool(String key, {required bool fallback}) async {
    final raw = await _readString(key);
    return raw == null ? fallback : raw == 'true';
  }

  Future<double> _readDouble(String key, {required double fallback}) async {
    final raw = await _readString(key);
    return double.tryParse(raw ?? '') ?? fallback;
  }

  Future<List<String>> _readStringList(String key,
      {required List<String> fallback}) async {
    final raw = await _readString(key);
    if (raw == null || raw.isEmpty) return fallback;
    return raw.split('|');
  }

  void _writeString(String key, String value) {
    unawaited(_storage.write(key: key, value: value));
  }

  void _writeBool(String key, bool value) {
    _writeString(key, value.toString());
  }

  void _writeDouble(String key, double value) {
    _writeString(key, value.toString());
  }

  void _writeStringList(String key, List<String> values) {
    _writeString(key, values.join('|'));
  }

  T _parseEnum<T>(
    String? name,
    List<T> values,
    T fallback,
    String Function(T value) nameOf,
  ) {
    if (name == null) return fallback;
    for (final value in values) {
      if (nameOf(value) == name) return value;
    }
    return fallback;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'settings_service.dart';

/// Lifecycle status of the Text-to-Speech engine.
enum TtsStatus {
  /// Engine is ready and not speaking.
  idle,

  /// A playback session is currently speaking.
  speaking,

  /// Playback was stopped by the user.
  stopped,
}

/// Wraps the platform Text-to-Speech engine ([FlutterTts]).
///
/// Provides language-aware playback that always verifies the requested
/// language (especially Hindi / Kannada) is installed on the device before
/// speaking, falling back to English when it is not. Exposes a sequential
/// queue-reading loop with status callbacks so the UI can react to progress.
class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _shouldStop = false;
  TtsStatus _status = TtsStatus.idle;

  /// Current engine status, observed by the UI.
  TtsStatus get status => _status;

  /// Whether the engine has been configured at least once.
  bool get isInitialized => _initialized;

  /// Configures callbacks and default engine parameters.
  Future<void> initialize() async {
    if (_initialized) return;
    _tts.setStartHandler(() => _setStatus(TtsStatus.speaking));
    _tts.setCompletionHandler(() {});
    _tts.setCancelHandler(() => _setStatus(TtsStatus.stopped));
    _tts.setErrorHandler((message) {
      debugPrint('TTS error: $message');
      _setStatus(TtsStatus.idle);
    });
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    // Resolve speak() futures only when the utterance finishes, which is what
    // powers the sequential reading loop below.
    await _tts.awaitSpeakCompletion(true);
    _initialized = true;
    _setStatus(TtsStatus.idle);
  }

  /// English voices run too fast through the Android engine's doubled-rate
  /// mapping (flutter_tts 1.0 == Android 2.0). Scale English down so "1x" is a
  /// natural pace, while Indic languages keep the user's setting unchanged.
  static const double _englishRateScale = 0.5;

  /// The engine rate to use for a language + user setting.
  static double effectiveRate(LanguageOption language, double userRate) =>
      language == LanguageOption.english ? userRate * _englishRateScale : userRate;

  /// Applies the playback rate (0.5x - 2.0x) as-is to the engine.
  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  /// Applies the chosen language (with English fallback) and the user's speed
  /// setting in one step, compensating for the platform rate mapping.
  ///
  /// Returns the language actually applied, or `null` if no language works.
  Future<LanguageOption?> configure(
    LanguageOption requested,
    double userRate,
  ) async {
    final applied = await applyLanguage(requested);
    await _tts.setSpeechRate(effectiveRate(applied ?? requested, userRate));
    return applied;
  }

  /// Applies a language if (and only if) it is installed on the device.
  ///
  /// Returns the language that was actually applied: the requested one when
  /// available, English as a fallback, or `null` when no language works.
  Future<LanguageOption?> applyLanguage(LanguageOption requested) async {
    if (await isLanguageAvailable(requested)) {
      await _tts.setLanguage(requested.locale);
      return requested;
    }
    if (await isLanguageAvailable(LanguageOption.english)) {
      await _tts.setLanguage(LanguageOption.english.locale);
      return LanguageOption.english;
    }
    return null;
  }

  /// Checks whether a language's voice data is installed (with a fallback to
  /// the platform's availability report) without throwing.
  Future<bool> isLanguageAvailable(LanguageOption option) async {
    try {
      final installed = await _tts.isLanguageInstalled(option.locale);
      if (installed == true) return true;
      final available = await _tts.isLanguageAvailable(option.locale);
      return available == true;
    } catch (error) {
      debugPrint('Language check failed for ${option.locale}: $error');
      return false;
    }
  }

  /// Speaks a queue of texts one after another, awaiting each utterance.
  ///
  /// [onItemStart] fires with the index before each utterance begins,
  /// [onDone] fires once the whole queue finished (or was stopped) and
  /// [onError] fires for individual utterance failures.
  Future<void> readQueue(
    List<String> texts, {
    ValueChanged<int>? onItemStart,
    VoidCallback? onDone,
    ValueChanged<Object>? onError,
  }) async {
    if (texts.isEmpty) {
      onDone?.call();
      return;
    }
    _shouldStop = false;
    _setStatus(TtsStatus.speaking);
    for (var i = 0; i < texts.length; i++) {
      if (_shouldStop) break;
      onItemStart?.call(i);
      try {
        await _tts.speak(texts[i]);
      } catch (error) {
        debugPrint('TTS speak error: $error');
        onError?.call(error);
      }
    }
    _setStatus(_shouldStop ? TtsStatus.stopped : TtsStatus.idle);
    onDone?.call();
  }

  /// Stops playback immediately and marks the session as stopped.
  Future<void> stop() async {
    _shouldStop = true;
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('TTS stop error: $error');
    }
    _setStatus(TtsStatus.stopped);
  }

  void _setStatus(TtsStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/tts_service.dart';
import 'widgets/app_selection_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local-only services: settings and queue persistence live on-device.
  final settings = SettingsService();
  await settings.load();

  final notificationService = NotificationService(settings);
  await notificationService.initialize();

  final ttsService = TtsService();

  runApp(
    NotificationReaderApp(
      settings: settings,
      notificationService: notificationService,
      ttsService: ttsService,
    ),
  );
}

/// Root widget wiring the three services into the single-screen UI.
class NotificationReaderApp extends StatelessWidget {
  const NotificationReaderApp({
    super.key,
    required this.settings,
    required this.notificationService,
    required this.ttsService,
  });

  final SettingsService settings;
  final NotificationService notificationService;
  final TtsService ttsService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notification Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: HomeScreen(
        settings: settings,
        notificationService: notificationService,
        ttsService: ttsService,
      ),
    );
  }
}

/// Single-screen home: everything lives inside one [Scaffold] as section
/// cards, as required by the architecture rules.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.notificationService,
    required this.ttsService,
  });

  final SettingsService settings;
  final NotificationService notificationService;
  final TtsService ttsService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool? _permissionGranted;
  bool _initializingTts = true;

  SettingsService get settings => widget.settings;
  NotificationService get notifications => widget.notificationService;
  TtsService get tts => widget.ttsService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notifications.dispose();
    tts.dispose();
    super.dispose();
  }

  /// Refreshes permission state and sweeps any incoming notifications whenever
  /// the app regains focus (e.g. returning from background or system settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
      unawaited(notifications.refreshFromTray());
    }
  }

  Future<void> _bootstrap() async {
    // Configure the TTS engine without blocking the first frame.
    unawaited(_initTts());
    await _refreshPermission();
  }

  Future<void> _initTts() async {
    await tts.initialize();
    await tts.configure(settings.language, settings.ttsRate);
    if (mounted) setState(() => _initializingTts = false);
  }

  Future<void> _refreshPermission() async {
    final granted =
        await NotificationListenerService.isPermissionGranted();
    if (!mounted) return;
    setState(() => _permissionGranted = granted);
  }

  Future<void> _requestPermission() async {
    // Opens the system "Notification access" settings screen.
    await NotificationListenerService.requestPermission();
    // Permission state is refreshed via the lifecycle observer on return.
  }

  /// Ensures notification listener access before enabling the service.
  Future<void> _onMasterToggle(bool enabled) async {
    if (enabled && _permissionGranted == false) {
      final proceed = await _confirmEnableWithoutPermission();
      if (proceed != true) {
        return; // Leave the switch off.
      }
      await _requestPermission();
    }
    settings.setMasterEnabled(enabled);
  }

  Future<bool?> _confirmEnableWithoutPermission() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification access required'),
        content: const Text(
          'Notification Reader needs notification listener access to capture '
          'your messages. You will be taken to the system settings to grant it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  /// The central "Read Now" flow: speak every unread message sequentially.
  Future<void> _readNow() async {
    if (_initializingTts) {
      _showSnack('Text-to-Speech is still starting up…');
      return;
    }
    if (notifications.unreadCount == 0) {
      _showSnack('No unread messages to read.');
      return;
    }
    if (_permissionGranted != true) {
      _showSnack('Enable notification access to capture messages.');
      return;
    }

    // Apply the user's language and speed; fall back gracefully if the
    // chosen language is not installed on the device.
    final applied = await tts.configure(settings.language, settings.ttsRate);
    if (applied != null && applied != settings.language) {
      _showSnack(
        '${settings.language.label} isn\'t installed — reading in English.',
      );
    }

    final items = notifications.markAllRead();
    final texts = items.map((item) => item.spokenText).toList();

    await tts.readQueue(
      texts,
      onDone: () {
        if (mounted) {
          _showSnack('Read ${texts.length} message'
              '${texts.length == 1 ? '' : 's'}.');
        }
      },
    );
  }

  /// Re-listen: reads every queued message again (read or unread) without
  /// changing their read state.
  Future<void> _replayAll() async {
    if (_initializingTts) {
      _showSnack('Text-to-Speech is still starting up…');
      return;
    }
    final items = notifications.queue;
    if (items.isEmpty) {
      _showSnack('Nothing to replay yet.');
      return;
    }

    final applied = await tts.configure(settings.language, settings.ttsRate);
    if (applied != null && applied != settings.language) {
      _showSnack(
        '${settings.language.label} isn\'t installed — reading in English.',
      );
    }

    final texts = items.map((item) => item.spokenText).toList();
    await tts.readQueue(
      texts,
      onDone: () {
        if (mounted) {
          _showSnack('Replayed ${texts.length} message'
              '${texts.length == 1 ? '' : 's'}.');
        }
      },
    );
  }

  Future<void> _clearQueue() async {
    await tts.stop();
    notifications.clearQueue();
    if (mounted) _showSnack('Queue cleared.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            settings,
            notifications,
            tts,
          ]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const _Header(),
              const SizedBox(height: 12),
              _StatusBanner(
                permissionGranted: _permissionGranted,
                masterEnabled: settings.masterEnabled,
                ttsStatus: tts.status,
                initializingTts: _initializingTts,
              ),
              const SizedBox(height: 12),
              _MasterSwitchCard(
                enabled: settings.masterEnabled,
                onChanged: _onMasterToggle,
              ),
              const SizedBox(height: 12),
              _RetentionCard(
                retention: settings.retention,
                onChanged: settings.setRetention,
              ),
              const SizedBox(height: 12),
              _FilterAppsCard(
                selectedCount: settings.selectedApps.length,
                onPressed: () =>
                    showAppSelectionSheet(context, settings),
              ),
              const SizedBox(height: 12),
              _TtsSettingsCard(
                language: settings.language,
                rate: settings.ttsRate,
                onLanguageChanged: (option) {
                  settings.setLanguage(option);
                  // Apply immediately so the next "Read Now" uses it.
                  unawaited(tts.configure(option, settings.ttsRate));
                },
                onRateChanged: (rate) {
                  settings.setTtsRate(rate);
                  unawaited(tts.configure(settings.language, rate));
                },
              ),
              const SizedBox(height: 12),
              _ActionCard(
                unreadCount: notifications.unreadCount,
                isSpeaking: tts.status == TtsStatus.speaking,
                onReadNow: _readNow,
                onReplay: _replayAll,
                onClearQueue: _clearQueue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable card shell giving each section a consistent look.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.record_voice_over,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notification Reader',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Hear your messages, hands-free',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thin status strip reflecting listening / reading state.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.permissionGranted,
    required this.masterEnabled,
    required this.ttsStatus,
    required this.initializingTts,
  });

  final bool? permissionGranted;
  final bool masterEnabled;
  final TtsStatus ttsStatus;
  final bool initializingTts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (IconData icon, String text, Color color) = switch ((
      permissionGranted,
      masterEnabled,
      ttsStatus,
      initializingTts,
    )) {
      (_, _, TtsStatus.speaking, _) => (
          Icons.graphic_eq,
          'Reading messages…',
          theme.colorScheme.tertiary,
        ),
      (false, _, _, _) => (
          Icons.perm_device_information,
          'Notification access is off',
          theme.colorScheme.error,
        ),
      (true, false, _, _) => (
          Icons.power_off,
          'Master switch is off — turn it on to capture notifications',
          theme.colorScheme.error,
        ),
      (true, true, _, _) => (
          Icons.volume_up,
          'Listening for notifications',
          theme.colorScheme.primary,
        ),
      _ => (
          Icons.volume_off,
          'Checking notification access…',
          theme.colorScheme.outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _MasterSwitchCard extends StatelessWidget {
  const _MasterSwitchCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Service',
      icon: Icons.power_settings_new,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Master switch'),
        subtitle: Text(
          enabled
              ? 'Capturing notifications from selected apps'
              : 'Notifications are ignored while off',
        ),
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

class _RetentionCard extends StatelessWidget {
  const _RetentionCard({required this.retention, required this.onChanged});

  final RetentionOption retention;
  final ValueChanged<RetentionOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Retention history',
      icon: Icons.history,
      child: SegmentedButton<RetentionOption>(
        segments: [
          for (final option in RetentionOption.values)
            ButtonSegment(value: option, label: Text(option.label)),
        ],
        selected: {retention},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _FilterAppsCard extends StatelessWidget {
  const _FilterAppsCard({required this.selectedCount, required this.onPressed});

  final int selectedCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Filter apps',
      icon: Icons.apps,
      child: Row(
        children: [
          Expanded(
            child: Text(
              selectedCount == 0
                  ? 'All apps allowed'
                  : '$selectedCount app${selectedCount == 1 ? '' : 's'} selected',
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: const Icon(Icons.tune),
            label: const Text('Choose apps'),
          ),
        ],
      ),
    );
  }
}

class _TtsSettingsCard extends StatelessWidget {
  const _TtsSettingsCard({
    required this.language,
    required this.rate,
    required this.onLanguageChanged,
    required this.onRateChanged,
  });

  final LanguageOption language;
  final double rate;
  final ValueChanged<LanguageOption> onLanguageChanged;
  final ValueChanged<double> onRateChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Text-to-Speech',
      icon: Icons.graphic_eq,
      child: Column(
        children: [
          DropdownButtonFormField<LanguageOption>(
            initialValue: language,
            decoration: const InputDecoration(
              labelText: 'Language',
              prefixIcon: Icon(Icons.language),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final option in LanguageOption.values)
                DropdownMenuItem(
                  value: option,
                  child: Text(option.label),
                ),
            ],
            onChanged: (option) {
              if (option != null) onLanguageChanged(option);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.speed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Speech speed  ${rate.toStringAsFixed(1)}×'),
              ),
            ],
          ),
          Slider(
            value: rate,
            min: SettingsService.minTtsRate,
            max: SettingsService.maxTtsRate,
            divisions: 15,
            label: '${rate.toStringAsFixed(1)}×',
            onChanged: onRateChanged,
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.unreadCount,
    required this.isSpeaking,
    required this.onReadNow,
    required this.onReplay,
    required this.onClearQueue,
  });

  final int unreadCount;
  final bool isSpeaking;
  final VoidCallback onReadNow;
  final VoidCallback onReplay;
  final VoidCallback onClearQueue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Playback',
      icon: Icons.play_circle_outline,
      child: Row(
        children: [
          Expanded(
            child: Badge.count(
              count: unreadCount,
              isLabelVisible: unreadCount > 0,
              child: FilledButton.icon(
                onPressed: onReadNow,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: Icon(
                  isSpeaking ? Icons.graphic_eq : Icons.play_arrow,
                ),
                label: Text(
                  isSpeaking ? 'Reading…' : 'Read Now',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Replay all messages',
            onPressed: onReplay,
            icon: const Icon(Icons.replay),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Clear queue',
            onPressed: onClearQueue,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
    );
  }
}

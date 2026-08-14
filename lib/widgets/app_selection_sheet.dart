import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../services/settings_service.dart';

/// Opens the app filter bottom sheet.
///
/// Shows every user-installed app with its icon and name; toggling a
/// checkbox immediately updates the whitelist in [SettingsService].
Future<void> showAppSelectionSheet(
  BuildContext context,
  SettingsService settings,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AppSelectionSheet(settings: settings),
  );
}

class _AppSelectionSheet extends StatefulWidget {
  const _AppSelectionSheet({required this.settings});

  final SettingsService settings;

  @override
  State<_AppSelectionSheet> createState() => _AppSelectionSheetState();
}

class _AppSelectionSheetState extends State<_AppSelectionSheet> {
  late Future<List<AppInfo>> _appsFuture;
  String _query = '';
  List<AppInfo> _apps = <AppInfo>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _appsFuture = _loadApps();
  }

  Future<List<AppInfo>> _loadApps() async {
    final apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: true,
      excludeNonLaunchableApps: true,
      withIcon: true,
    );
    if (mounted) {
      setState(() {
        _apps = apps;
        _loaded = true;
      });
    }
    return apps;
  }

  List<AppInfo> get _filteredApps {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _apps;
    return _apps
        .where((app) =>
            app.name.toLowerCase().contains(query) ||
            app.packageName.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = widget.settings.selectedApps.length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, selectedCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search apps…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<AppInfo>>(
                future: _appsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || _apps.isEmpty) {
                    return _buildEmptyState(theme);
                  }
                  return _buildAppList(theme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, int selectedCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'Apps to read aloud',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_loaded && _apps.isNotEmpty)
            TextButton(
              onPressed: selectedCount == _apps.length
                  ? () => widget.settings.setSelectedApps(<String>{})
                  : () => widget.settings.setSelectedApps(
                      _apps.map((app) => app.packageName).toSet(),
                    ),
              child: Text(
                selectedCount == _apps.length ? 'Clear all' : 'Select all',
              ),
            ),
          Text(
            '$selectedCount selected',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildAppList(ThemeData theme) {
    final filtered = _filteredApps;
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No apps match your search.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final app = filtered[index];
        final isSelected =
            widget.settings.selectedApps.contains(app.packageName);
        return CheckboxListTile(
          value: isSelected,
          onChanged: (_) {
            widget.settings.toggleApp(app.packageName);
            setState(() {});
          },
          secondary: _AppIcon(icon: app.icon, name: app.name),
          title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            app.packageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.apps_outage,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('Could not load installed apps.'),
        ],
      ),
    );
  }
}

/// Renders an app icon from raw bytes, falling back to a generic placeholder.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon, required this.name});

  final Uint8List? icon;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: const TextStyle(fontSize: 16),
      ),
    );
    if (icon == null) return fallback;
    return CircleAvatar(
      backgroundImage: MemoryImage(icon as Uint8List),
      onBackgroundImageError: (_, _) {},
      child: const SizedBox.shrink(),
    );
  }
}

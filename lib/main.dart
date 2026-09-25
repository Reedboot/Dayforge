import 'package:flutter/material.dart';

import 'app_info.dart';
import 'data/update_service.dart';
import 'pages/daily_log_page.dart';

void main() {
  runApp(const DayforgeApp());
}

class DayforgeApp extends StatefulWidget {
  const DayforgeApp({super.key});

  @override
  State<DayforgeApp> createState() => _DayforgeAppState();
}

class _DayforgeAppState extends State<DayforgeApp> {
  ThemeMode _themeMode = ThemeMode.system;

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SettingsDialog(
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF376A5A);
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        surface: const Color(0xFFF6F7F5),
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F7F5),
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: DailyLogPage(onOpenSettings: _openSettings),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _updateService = UpdateService();
  late ThemeMode _themeMode = widget.themeMode;
  bool _checking = false;
  String? _updateMessage;
  UpdateInfo? _update;

  Future<void> _checkForUpdate() async {
    setState(() {
      _checking = true;
      _updateMessage = null;
      _update = null;
    });
    try {
      final update = await _updateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = update;
        _updateMessage = update == null
            ? 'You are running the latest version.'
            : 'Version ${update.version} is available.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _updateMessage = 'Update check failed: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Color scheme',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            DropdownButtonFormField<ThemeMode>(
              initialValue: _themeMode,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System default'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _themeMode = value);
                widget.onThemeModeChanged(value);
              },
            ),
            const Divider(),
            Text('Updates', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _checking ? null : _checkForUpdate,
              icon: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_outlined),
              label: Text(_checking ? 'Checking...' : 'Check for updates'),
            ),
            if (_updateMessage != null) ...[
              const SizedBox(height: 10),
              Text(_updateMessage!),
            ],
            if (_update != null && _update!.downloadUrl != null) ...[
              const SizedBox(height: 8),
              SelectableText(_update!.downloadUrl!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

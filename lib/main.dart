import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import 'app_info.dart';
import 'data/daily_log_store.dart';
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
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _store = DailyLogStore();
  ThemeMode _themeMode = ThemeMode.system;
  int _dataRevision = 0;

  Future<void> _openSettings() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      throw StateError('Settings opened before the app navigator was mounted.');
    }
    await showDialog<void>(
      context: navigator.context,
      builder: (context) => _SettingsDialog(
        store: _store,
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
        onDataImported: () => setState(() => _dataRevision++),
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
      navigatorKey: _navigatorKey,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: DailyLogPage(
        key: ValueKey(_dataRevision),
        store: _store,
        onOpenSettings: _openSettings,
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.store,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onDataImported,
  });

  final DailyLogStore store;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onDataImported;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _updateService = UpdateService();
  late ThemeMode _themeMode = widget.themeMode;
  bool _checking = false;
  bool _backupBusy = false;
  String? _updateMessage;
  UpdateInfo? _update;
  String? _backupMessage;

  static const _backupType = XTypeGroup(
    label: 'Dayforge backup',
    extensions: ['json'],
  );

  Future<void> _exportData() async {
    setState(() {
      _backupBusy = true;
      _backupMessage = null;
    });
    try {
      final path = Platform.isAndroid
          ? await getDirectoryPath()
          : (await getSaveLocation(
              suggestedName: 'dayforge.json',
              acceptedTypeGroups: [_backupType],
            ))?.path;
      if (path == null || path.isEmpty) return;
      final destination = Platform.isAndroid
          ? File('$path${Platform.pathSeparator}dayforge.json')
          : File(path);
      await widget.store.exportTo(destination);
      if (!mounted) return;
      setState(() => _backupMessage = 'Backup exported successfully.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _backupMessage = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importData() async {
    setState(() {
      _backupBusy = true;
      _backupMessage = null;
    });
    try {
      final file = await openFile(acceptedTypeGroups: [_backupType]);
      if (file == null) return;
      await widget.store.importFrom(File(file.path));
      if (!mounted) return;
      widget.onDataImported();
      setState(() => _backupMessage = 'Backup imported successfully.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _backupMessage = 'Import failed: $error');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

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
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 48,
        maxHeight: MediaQuery.sizeOf(context).height - 48,
      ),
      insetPadding: const EdgeInsets.all(24),
      title: const Text('Settings'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Version $appVersion'),
              const SizedBox(height: 16),
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
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
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
              const Divider(),
              Text('Data', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _backupBusy ? null : _exportData,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Export dayforge'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _backupBusy ? null : _importData,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Import dayforge'),
                    ),
                  ),
                ],
              ),
              if (_backupMessage != null) ...[
                const SizedBox(height: 10),
                Text(_backupMessage!),
              ],
            ],
          ),
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

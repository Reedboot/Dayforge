import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/daily_log.dart';

class DailyLogStore {
  DailyLogStore({Directory? directory}) : _directoryOverride = directory;

  static const _storageChannel = MethodChannel('dayforge/storage');
  static const _fileName = 'daily_logs.json';
  static const _schemaVersion = 1;

  final Directory? _directoryOverride;

  Future<Map<String, DailyLog>> loadAll() async {
    final file = await _dataFile();
    if (!await file.exists()) {
      return {};
    }

    return _decodeLogs(await file.readAsString());
  }

  Future<void> exportTo(File destination, {Map<String, DailyLog>? logs}) async {
    final snapshot = logs ?? await loadAll();
    await destination.writeAsString(_encodeLogs(snapshot), flush: true);
  }

  Future<bool> exportToAndroid({Map<String, DailyLog>? logs}) async {
    final snapshot = logs ?? await loadAll();
    return await _storageChannel.invokeMethod<bool>(
          'exportBackup',
          _encodeLogs(snapshot),
        ) ??
        false;
  }

  Future<void> importFrom(File source) async {
    final logs = _decodeLogs(await source.readAsString());
    await saveAll(logs);
  }

  String _encodeLogs(Map<String, DailyLog> logs) {
    return jsonEncode({
      'schemaVersion': _schemaVersion,
      'logs': {
        for (final entry in logs.entries) entry.key: entry.value.toJson(),
      },
    });
  }

  Map<String, DailyLog> _decodeLogs(String contents) {
    final decoded = jsonDecode(contents);
    final root = _asStringMap(decoded, 'daily log storage');
    if (root['schemaVersion'] != _schemaVersion) {
      throw const FormatException('Unsupported daily log storage version.');
    }
    final storedLogs = _asStringMap(root['logs'], 'daily logs');
    final logs = <String, DailyLog>{};

    for (final entry in storedLogs.entries) {
      final log = DailyLog.fromJson(entry.value);
      if (log.dateKey != entry.key) {
        throw FormatException(
          'The stored date key "${entry.key}" does not match its daily log.',
        );
      }
      logs[entry.key] = log;
    }

    return logs;
  }

  Future<void> saveAll(Map<String, DailyLog> logs) async {
    final file = await _dataFile();
    await file.parent.create(recursive: true);
    final temporaryFile = File('${file.path}.tmp');
    final contents = _encodeLogs(logs);
    await temporaryFile.writeAsString(contents, flush: true);
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await temporaryFile.rename(file.path);
  }

  Future<File> _dataFile() async {
    final directory = _directoryOverride ?? await _resolveDataDirectory();
    return File(_joinPath(directory.path, _fileName));
  }

  Future<Directory> _resolveDataDirectory() async {
    final String root;
    if (Platform.isAndroid) {
      final appDirectory = await _storageChannel.invokeMethod<String>(
        'getDataDirectory',
      );
      if (appDirectory == null || appDirectory.isEmpty) {
        throw StateError('Android did not provide the app data directory.');
      }
      root = appDirectory;
    } else if (Platform.isWindows) {
      root =
          Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          (throw StateError('Windows did not provide an app data directory.'));
    } else if (Platform.isLinux) {
      final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
      if (xdgDataHome != null &&
          xdgDataHome.isNotEmpty &&
          _isAbsolutePath(xdgDataHome)) {
        root = xdgDataHome;
      } else {
        final home = Platform.environment['HOME'];
        if (home == null || home.isEmpty) {
          throw StateError('Linux did not provide a home directory.');
        }
        root = _joinPath(home, '.local/share');
      }
    } else {
      throw UnsupportedError(
        'Dayforge storage is not configured for ${Platform.operatingSystem}.',
      );
    }

    return Directory(_joinPath(root, 'dayforge'));
  }

  bool _isAbsolutePath(String path) {
    return Platform.isWindows
        ? path.startsWith(r'\') ||
              (path.length > 2 && path[1] == ':' && path[2] == r'\')
        : path.startsWith('/');
  }

  String _joinPath(String first, String second) {
    final separator = Platform.pathSeparator;
    final normalizedFirst = first.endsWith(separator)
        ? first.substring(0, first.length - 1)
        : first;
    return '$normalizedFirst$separator$second';
  }
}

Map<String, Object?> _asStringMap(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('The saved $label must be a JSON object.');
  }

  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('The saved $label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

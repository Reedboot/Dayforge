import 'dart:io';

import 'data/daily_log_store.dart';
import 'models/daily_log.dart';

const _usage =
    'Usage: dayforge add [--type task|email|meeting] '
    '[--date YYYY-MM-DD] <task text>\n'
    '       dayforge --help';

Future<int> runDayforgeCli(
  List<String> args, {
  DailyLogStore? store,
  DateTime? now,
  void Function(String)? printOut,
  void Function(String)? printError,
}) async {
  final output = printOut ?? stdout.writeln;
  final errorOutput = printError ?? stderr.writeln;

  if (args.length == 1 && args.single == '--help') {
    output(_usage);
    return 0;
  }
  if (args.isEmpty || args.first != 'add') {
    errorOutput(_usage);
    return 2;
  }

  var type = 'task';
  String? date;
  final textParts = <String>[];
  for (var index = 1; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--type' || argument == '--date') {
      if (index + 1 >= args.length) {
        errorOutput('Missing value for $argument.\n$_usage');
        return 2;
      }
      final value = args[++index];
      if (argument == '--type') {
        type = value;
      } else {
        date = value;
      }
    } else if (argument.startsWith('--type=')) {
      type = argument.substring('--type='.length);
    } else if (argument.startsWith('--date=')) {
      date = argument.substring('--date='.length);
    } else if (argument.startsWith('-')) {
      errorOutput('Unknown option: $argument\n$_usage');
      return 2;
    } else {
      textParts.add(argument);
    }
  }

  if (!const {'task', 'email', 'meeting'}.contains(type)) {
    errorOutput('Unknown task type: $type. Use task, email, or meeting.');
    return 2;
  }
  final text = textParts.join(' ').trim();
  if (text.isEmpty) {
    errorOutput('Task text is required.\n$_usage');
    return 2;
  }

  final currentTime = now ?? DateTime.now();
  final dateKey = _parseDateKey(date, currentTime);
  if (dateKey == null) {
    errorOutput('Invalid date: $date. Use a valid date in YYYY-MM-DD format.');
    return 2;
  }
  if (!Platform.isWindows && !Platform.isLinux) {
    errorOutput('The Dayforge command line is supported on Windows and Linux.');
    return 2;
  }

  final logStore = store ?? DailyLogStore();
  final logs = await logStore.loadAll();
  final log = logs[dateKey] ?? DailyLog.empty(dateKey);
  final task = DailyTask(id: _newTaskId(logs, currentTime), text: text);
  final updatedLog = switch (type) {
    'email' => log.copyWith(
      emailTasks: _addBeforeCompleted(log.emailTasks, task),
    ),
    'meeting' => log.copyWith(
      meetingTasks: _addBeforeCompleted(log.meetingTasks, task),
    ),
    _ => log.copyWith(tasks: _addBeforeCompleted(log.tasks, task)),
  };
  logs[dateKey] = updatedLog;
  await logStore.saveAll(logs);
  output('Added $type for $dateKey: $text');
  return 0;
}

String? _parseDateKey(String? value, DateTime today) {
  if (value == null) return dailyLogDateKey(today);
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return dailyLogDateKey(date);
}

List<DailyTask> _addBeforeCompleted(List<DailyTask> tasks, DailyTask task) => [
  ...tasks.where((existing) => !existing.isComplete),
  task,
  ...tasks.where((existing) => existing.isComplete),
];

String _newTaskId(Map<String, DailyLog> logs, DateTime now) {
  final existingIds = <String>{
    for (final log in logs.values) ...[
      ...log.previousTasks.map((task) => task.id),
      ...log.emailTasks.map((task) => task.id),
      ...log.meetingTasks.map((task) => task.id),
      ...log.tasks.map((task) => task.id),
      for (final task in [
        ...log.previousTasks,
        ...log.emailTasks,
        ...log.meetingTasks,
        ...log.tasks,
      ])
        ...task.subtasks.map((subtask) => subtask.id),
    ],
  };
  final base = now.microsecondsSinceEpoch.toString();
  var id = base;
  var suffix = 0;
  while (existingIds.contains(id)) {
    id = '$base-${++suffix}';
  }
  return id;
}

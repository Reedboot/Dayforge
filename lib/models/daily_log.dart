class DailyLog {
  const DailyLog({
    required this.dateKey,
    this.previousOutstandingTasks = '',
    this.emails = '',
    this.meetings = '',
    this.tasks = const [],
  });

  final String dateKey;
  final String previousOutstandingTasks;
  final String emails;
  final String meetings;
  final List<DailyTask> tasks;

  factory DailyLog.empty(String dateKey) => DailyLog(dateKey: dateKey);

  factory DailyLog.fromJson(Object? value) {
    final json = _jsonObject(value, 'daily log');
    final tasks = json['tasks'];
    if (tasks is! List) {
      throw const FormatException('Daily log tasks must be a list.');
    }

    return DailyLog(
      dateKey: _jsonString(json, 'dateKey'),
      previousOutstandingTasks: _jsonString(json, 'previousOutstandingTasks'),
      emails: _jsonString(json, 'emails'),
      meetings: _jsonString(json, 'meetings'),
      tasks: List<DailyTask>.unmodifiable(tasks.map(DailyTask.fromJson)),
    );
  }

  DailyLog copyWith({
    String? previousOutstandingTasks,
    String? emails,
    String? meetings,
    List<DailyTask>? tasks,
  }) {
    return DailyLog(
      dateKey: dateKey,
      previousOutstandingTasks:
          previousOutstandingTasks ?? this.previousOutstandingTasks,
      emails: emails ?? this.emails,
      meetings: meetings ?? this.meetings,
      tasks: tasks ?? this.tasks,
    );
  }

  Map<String, Object?> toJson() => {
    'dateKey': dateKey,
    'previousOutstandingTasks': previousOutstandingTasks,
    'emails': emails,
    'meetings': meetings,
    'tasks': tasks.map((task) => task.toJson()).toList(),
  };
}

class DailyTask {
  const DailyTask({
    required this.id,
    required this.text,
    this.isComplete = false,
    this.subtasks = const [],
  });

  final String id;
  final String text;
  final bool isComplete;
  final List<DailySubtask> subtasks;

  factory DailyTask.fromJson(Object? value) {
    final json = _jsonObject(value, 'task');
    final subtasks = json['subtasks'];
    if (subtasks is! List) {
      throw const FormatException('Task subtasks must be a list.');
    }

    return DailyTask(
      id: _jsonString(json, 'id'),
      text: _jsonString(json, 'text'),
      isComplete: _jsonBool(json, 'isComplete'),
      subtasks: List<DailySubtask>.unmodifiable(
        subtasks.map(DailySubtask.fromJson),
      ),
    );
  }

  DailyTask copyWith({
    String? text,
    bool? isComplete,
    List<DailySubtask>? subtasks,
  }) {
    return DailyTask(
      id: id,
      text: text ?? this.text,
      isComplete: isComplete ?? this.isComplete,
      subtasks: subtasks ?? this.subtasks,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'isComplete': isComplete,
    'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
  };
}

class DailySubtask {
  const DailySubtask({
    required this.id,
    required this.text,
    this.isComplete = false,
  });

  final String id;
  final String text;
  final bool isComplete;

  factory DailySubtask.fromJson(Object? value) {
    final json = _jsonObject(value, 'subtask');
    return DailySubtask(
      id: _jsonString(json, 'id'),
      text: _jsonString(json, 'text'),
      isComplete: _jsonBool(json, 'isComplete'),
    );
  }

  DailySubtask copyWith({String? text, bool? isComplete}) {
    return DailySubtask(
      id: id,
      text: text ?? this.text,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'isComplete': isComplete,
  };
}

Map<String, Object?> _jsonObject(Object? value, String label) {
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

String _jsonString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('The saved field "$key" must be text.');
  }
  return value;
}

bool _jsonBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('The saved field "$key" must be true or false.');
  }
  return value;
}

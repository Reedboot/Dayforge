import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/daily_log_store.dart';
import '../models/daily_log.dart';

class DailyLogPage extends StatefulWidget {
  const DailyLogPage({
    super.key,
    this.store,
    this.initialDate,
    this.onOpenSettings,
  });

  final DailyLogStore? store;
  final DateTime? initialDate;
  final VoidCallback? onOpenSettings;

  @override
  State<DailyLogPage> createState() => _DailyLogPageState();
}

class _DailyLogPageState extends State<DailyLogPage>
    with WidgetsBindingObserver {
  late final DailyLogStore _store;
  late DateTime _selectedDate;

  Map<String, DailyLog> _logs = {};
  final TextEditingController _newTaskController = TextEditingController();
  final FocusNode _newTaskFocusNode = FocusNode();
  Timer? _saveTimer;
  int _revision = 0;
  int _savedRevision = 0;
  bool _loading = true;
  bool _saving = false;
  bool _saveAgain = false;
  bool _disposing = false;
  Object? _loadError;
  Object? _saveError;
  _SaveState _saveState = _SaveState.saved;

  String get _dateKey => dailyLogDateKey(_selectedDate);
  DailyLog get _currentLog => _logs[_dateKey] ?? DailyLog.empty(_dateKey);
  bool get _isSelectedToday {
    final today = DateTime.now();
    return _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
  }

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? DailyLogStore();
    final initialDate = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadLogs());
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    if (_revision != _savedRevision) {
      unawaited(_saveNow());
    }
    _newTaskController.dispose();
    _newTaskFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveTimer?.cancel();
      unawaited(_saveNow());
    }
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final logs = await _store.loadAll();
      if (!mounted) return;
      final normalizedLogs = _addOutstandingTasks(logs);
      if (!normalizedLogs.containsKey(_dateKey)) {
        normalizedLogs[_dateKey] = DailyLog(
          dateKey: _dateKey,
          previousTasks: _outstandingForDate(normalizedLogs, _dateKey),
        );
      }
      setState(() {
        _logs = normalizedLogs;
        _loading = false;
        _savedRevision = _revision;
        _saveState = _SaveState.saved;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Map<String, DailyLog> _addOutstandingTasks(Map<String, DailyLog> logs) {
    final normalized = <String, DailyLog>{};
    final dates = logs.keys.toList()..sort();
    final completedIds = <String>{};

    for (final date in dates) {
      final log = logs[date]!;
      final previousTasks = log.previousTasks.isNotEmpty
          ? log.previousTasks
          : _legacyTasks(log.previousOutstandingTasks, 'previous');
      final meetingTasks = log.meetingTasks.isNotEmpty
          ? log.meetingTasks
          : _legacyTasks(log.meetings, 'meeting');
      final outstanding = <DailyTask>[];

      for (final priorLog in normalized.values) {
        for (final task in priorLog.tasks) {
          if (!task.isComplete &&
              !completedIds.contains(task.id) &&
              !outstanding.any((candidate) => candidate.id == task.id)) {
            outstanding.add(task);
          }
        }
      }

      final existingIds = {
        ...previousTasks.map((task) => task.id),
        ...log.tasks.map((task) => task.id),
      };
      outstanding.removeWhere((task) => existingIds.contains(task.id));
      normalized[date] = log.copyWith(
        previousTasks: [...previousTasks, ...outstanding],
        meetingTasks: meetingTasks,
      );

      for (final task in [...log.tasks, ...previousTasks, ...meetingTasks]) {
        if (task.isComplete) completedIds.add(task.id);
      }
    }
    return normalized;
  }

  List<DailyTask> _outstandingForDate(
    Map<String, DailyLog> logs,
    String dateKey,
  ) {
    final outstanding = <DailyTask>[];
    final completedIds = <String>{};
    final dates =
        logs.keys.where((date) => date.compareTo(dateKey) < 0).toList()..sort();
    for (final date in dates) {
      final log = logs[date]!;
      for (final task in log.tasks) {
        if (!task.isComplete &&
            !completedIds.contains(task.id) &&
            !outstanding.any((candidate) => candidate.id == task.id)) {
          outstanding.add(task);
        }
        if (task.isComplete) completedIds.add(task.id);
      }
    }
    return outstanding;
  }

  List<DailyTask> _legacyTasks(String value, String prefix) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((text) => DailyTask(id: '$prefix-${text.hashCode}', text: text))
        .toList();
  }

  void _updateLog(DailyLog updatedLog) {
    setState(() {
      _logs[updatedLog.dateKey] = updatedLog;
      _revision++;
      _saveState = _SaveState.pending;
      _saveError = null;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_saveNow());
    });
  }

  void _updateCollection(_TaskCollection collection, List<DailyTask> tasks) {
    _updateLog(
      collection == _TaskCollection.previous
          ? _currentLog.copyWith(previousTasks: tasks)
          : _currentLog.copyWith(meetingTasks: tasks),
    );
  }

  void _updateCollectionTaskText(
    _TaskCollection collection,
    String taskId,
    String text,
  ) {
    final tasks = _collectionTasks(collection)
        .map((task) => task.id == taskId ? task.copyWith(text: text) : task)
        .toList();
    _updateCollection(collection, tasks);
  }

  void _setCollectionTaskComplete(
    _TaskCollection collection,
    String taskId,
    bool isComplete,
  ) {
    final task = _collectionTasks(collection)
        .firstWhere((task) => task.id == taskId);
    final remaining = _collectionTasks(collection)
        .where((task) => task.id != taskId)
        .toList();
    final incomplete = remaining.where((task) => !task.isComplete);
    final complete = remaining.where((task) => task.isComplete);
    final ordered = isComplete
        ? [...incomplete, ...complete, task.copyWith(isComplete: true)]
        : [task.copyWith(isComplete: false), ...incomplete, ...complete];
    _updateCollection(collection, ordered);
  }

  Future<void> _deleteCollectionTask(
    _TaskCollection collection,
    String taskId,
  ) async {
    if (!await _confirmDelete('this task')) return;
    _updateCollection(
      collection,
      _collectionTasks(collection).where((task) => task.id != taskId).toList(),
    );
  }

  void _updateCollectionSubtaskText(
    _TaskCollection collection,
    String taskId,
    String subtaskId,
    String text,
  ) {
    final tasks = _collectionTasks(collection).map((task) {
      if (task.id != taskId) return task;
      return task.copyWith(
        subtasks: task.subtasks
            .map(
              (subtask) => subtask.id == subtaskId
                  ? subtask.copyWith(text: text)
                  : subtask,
            )
            .toList(),
      );
    }).toList();
    _updateCollection(collection, tasks);
  }

  void _setCollectionSubtaskComplete(
    _TaskCollection collection,
    String taskId,
    String subtaskId,
    bool isComplete,
  ) {
    final tasks = _collectionTasks(collection).map((task) {
      if (task.id != taskId) return task;
      final subtask = task.subtasks.firstWhere(
        (subtask) => subtask.id == subtaskId,
      );
      final remaining = task.subtasks
          .where((subtask) => subtask.id != subtaskId)
          .toList();
      final incomplete = remaining.where((subtask) => !subtask.isComplete);
      final complete = remaining.where((subtask) => subtask.isComplete);
      final ordered = isComplete
          ? [...incomplete, ...complete, subtask.copyWith(isComplete: true)]
          : [subtask.copyWith(isComplete: false), ...incomplete, ...complete];
      return task.copyWith(subtasks: ordered);
    }).toList();
    _updateCollection(collection, tasks);
  }

  Future<void> _deleteCollectionSubtask(
    _TaskCollection collection,
    String taskId,
    String subtaskId,
  ) async {
    if (!await _confirmDelete('this action')) return;
    _updateCollection(
      collection,
      _collectionTasks(collection).map((task) {
        if (task.id != taskId) return task;
        return task.copyWith(
          subtasks: task.subtasks
              .where((subtask) => subtask.id != subtaskId)
              .toList(),
        );
      }).toList(),
    );
  }

  Future<void> _addCollectionSubtask(
    DailyTask task,
    _TaskCollection collection,
  ) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _AddSubtaskDialog(),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;

    final tasks = _collectionTasks(collection).map((currentTask) {
      if (currentTask.id != task.id) return currentTask;
      return currentTask.copyWith(
        subtasks: [
          ...currentTask.subtasks.where((subtask) => !subtask.isComplete),
          DailySubtask(id: _newEntryId(), text: text.trim()),
          ...currentTask.subtasks.where((subtask) => subtask.isComplete),
        ],
      );
    }).toList();
    _updateCollection(collection, tasks);
  }

  Future<void> _addMeeting() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _AddMeetingDialog(),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    final tasks = [
      ..._currentLog.meetingTasks.where((task) => !task.isComplete),
      DailyTask(id: _newEntryId(), text: text.trim()),
      ..._currentLog.meetingTasks.where((task) => task.isComplete),
    ];
    _updateCollection(_TaskCollection.meetings, tasks);
  }

  Future<void> _addEmail() async {
    final task = await showDialog<DailyTask>(
      context: context,
      builder: (context) => const _AddTaskDialog(
        dialogTitle: 'Add an email',
        titleLabel: 'Email',
        titleHint: 'What needs a response?',
      ),
    );
    if (!mounted || task == null || task.text.trim().isEmpty) return;

    final currentTasks = _currentLog.tasks;
    final incomplete = currentTasks.where((task) => !task.isComplete).toList();
    final complete = currentTasks.where((task) => task.isComplete);
    incomplete.add(task.copyWith(id: _newEntryId()));
    _updateLog(_currentLog.copyWith(tasks: [...incomplete, ...complete]));
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_loading || _loadError != null || _revision == _savedRevision) return;
    if (_saving) {
      _saveAgain = true;
      return;
    }

    _saving = true;
    final savingRevision = _revision;
    final snapshot = Map<String, DailyLog>.of(_logs);
    var succeeded = false;
    if (mounted && !_disposing) {
      setState(() {
        _saveState = _SaveState.saving;
        _saveError = null;
      });
    }

    try {
      await _store.saveAll(snapshot);
      _savedRevision = savingRevision;
      succeeded = true;
      if (mounted && !_disposing) {
        setState(() {
          _saveState = _revision == savingRevision
              ? _SaveState.saved
              : _SaveState.pending;
        });
      }
    } catch (error, stackTrace) {
      if (mounted && !_disposing) {
        setState(() {
          _saveState = _SaveState.error;
          _saveError = error;
        });
      } else {
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      _saving = false;
      final needsAnotherSave = _saveAgain || _revision != _savedRevision;
      _saveAgain = false;
      if (succeeded && needsAnotherSave) {
        unawaited(_saveNow());
      }
    }
  }

  void _updateTaskText(String taskId, String text) {
    final tasks = _currentLog.tasks
        .map((task) => task.id == taskId ? task.copyWith(text: text) : task)
        .toList();
    _updateLog(_currentLog.copyWith(tasks: tasks));
  }

  void _setTaskComplete(String taskId, bool isComplete) {
    final task = _currentLog.tasks.firstWhere((task) => task.id == taskId);
    final updatedTask = task.copyWith(isComplete: isComplete);
    final remaining = _currentLog.tasks
        .where((task) => task.id != taskId)
        .toList();
    final incomplete = remaining.where((task) => !task.isComplete);
    final complete = remaining.where((task) => task.isComplete);
    final orderedTasks = isComplete
        ? [...incomplete, ...complete, updatedTask]
        : [updatedTask, ...incomplete, ...complete];
    _updateLog(_currentLog.copyWith(tasks: orderedTasks));
  }

  Future<void> _deleteTask(String taskId) async {
    if (!await _confirmDelete('this task')) return;
    final tasks = _currentLog.tasks.where((task) => task.id != taskId).toList();
    _updateLog(_currentLog.copyWith(tasks: tasks));
  }

  Future<bool> _confirmDelete(String description) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Are you sure you want to delete $description?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _updateSubtaskText(String taskId, String subtaskId, String text) {
    final tasks = _currentLog.tasks.map((task) {
      if (task.id != taskId) return task;
      final subtasks = task.subtasks
          .map(
            (subtask) => subtask.id == subtaskId
                ? subtask.copyWith(text: text)
                : subtask,
          )
          .toList();
      return task.copyWith(subtasks: subtasks);
    }).toList();
    _updateLog(_currentLog.copyWith(tasks: tasks));
  }

  void _setSubtaskComplete(String taskId, String subtaskId, bool isComplete) {
    final tasks = _currentLog.tasks.map((task) {
      if (task.id != taskId) return task;
      final subtask = task.subtasks.firstWhere(
        (subtask) => subtask.id == subtaskId,
      );
      final updatedSubtask = subtask.copyWith(isComplete: isComplete);
      final remaining = task.subtasks
          .where((subtask) => subtask.id != subtaskId)
          .toList();
      final incomplete = remaining.where((subtask) => !subtask.isComplete);
      final complete = remaining.where((subtask) => subtask.isComplete);
      final orderedSubtasks = isComplete
          ? [...incomplete, ...complete, updatedSubtask]
          : [updatedSubtask, ...incomplete, ...complete];
      return task.copyWith(subtasks: orderedSubtasks);
    }).toList();
    _updateLog(_currentLog.copyWith(tasks: tasks));
  }

  Future<void> _deleteSubtask(String taskId, String subtaskId) async {
    if (!await _confirmDelete('this action')) return;
    final tasks = _currentLog.tasks.map((task) {
      if (task.id != taskId) return task;
      return task.copyWith(
        subtasks: task.subtasks
            .where((subtask) => subtask.id != subtaskId)
            .toList(),
      );
    }).toList();
    _updateLog(_currentLog.copyWith(tasks: tasks));
  }

  Future<void> _addTask() async {
    final task = await showDialog<DailyTask>(
      context: context,
      builder: (context) => const _AddTaskDialog(),
    );
    if (!mounted || task == null || task.text.trim().isEmpty) return;

    final currentTasks = _currentLog.tasks;
    final incomplete = currentTasks.where((task) => !task.isComplete).toList();
    final complete = currentTasks.where((task) => task.isComplete);
    incomplete.add(task.copyWith(id: _newEntryId()));
    _updateLog(_currentLog.copyWith(tasks: [...incomplete, ...complete]));
  }

  Future<void> _addSubtask(DailyTask task) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _AddSubtaskDialog(),
    );

    if (!mounted || text == null || text.trim().isEmpty) return;
    final tasks = _currentLog.tasks.map((currentTask) {
      if (currentTask.id != task.id) return currentTask;
      return currentTask.copyWith(
        subtasks: [
          ...currentTask.subtasks.where((subtask) => !subtask.isComplete),
          DailySubtask(id: _newEntryId(), text: text.trim()),
          ...currentTask.subtasks.where((subtask) => subtask.isComplete),
        ],
      );
    }).toList();
    _updateLog(_currentLog.copyWith(tasks: tasks));
  }

  Future<void> _chooseDate() async {
    final chosenDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (chosenDate == null || !mounted) return;
    _setSelectedDate(
      DateTime(chosenDate.year, chosenDate.month, chosenDate.day),
    );
  }

  void _changeDate(int amount) {
    _setSelectedDate(_selectedDate.add(Duration(days: amount)));
  }

  void _setSelectedDate(DateTime date) {
    final dateKey = dailyLogDateKey(date);
    final log = _logs[dateKey];
    setState(() {
      _selectedDate = date;
      if (log == null) {
        _logs[dateKey] = DailyLog(
          dateKey: dateKey,
          previousTasks: _outstandingForDate(_logs, dateKey),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          appTitle,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (widget.onOpenSettings != null)
            IconButton(
              key: const ValueKey('settings-button'),
              tooltip: 'Settings',
              onPressed: widget.onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildSaveStatus(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _buildLoadError()
          : _buildDailyLog(),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              const Text(
                'Dayforge could not load your saved logs.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$_loadError',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadLogs,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyLog() {
    return SingleChildScrollView(
      key: const ValueKey('daily-log-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDateNavigation(),
              const SizedBox(height: 22),
              _buildTaskCollectionSection(_TaskCollection.previous),
              const SizedBox(height: 14),
              _buildNotesSection(
                title: "Today's emails",
                subtitle: 'Capture important messages and follow-ups.',
                fieldKey: 'emails',
                value: _currentLog.emails,
                hint: 'Write down emails, replies, or follow-ups...',
                icon: Icons.mail_outline,
                actionLabel: 'Add email',
                onAction: _addEmail,
                onChanged: (value) =>
                    _updateLog(_currentLog.copyWith(emails: value)),
              ),
              const SizedBox(height: 14),
              _buildTaskCollectionSection(_TaskCollection.meetings),
              const SizedBox(height: 14),
              _buildTasksSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateNavigation() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('previous-day'),
              tooltip: 'Previous day',
              onPressed: () => _changeDate(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton.icon(
                key: const ValueKey('choose-date'),
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  _formatDate(_selectedDate),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (!_isSelectedToday)
              TextButton.icon(
                key: const ValueKey('today-button'),
                onPressed: () => _setSelectedDate(DateTime.now()),
                icon: const Icon(Icons.today),
                label: const Text('Today'),
              ),
            IconButton(
              key: const ValueKey('next-day'),
              tooltip: 'Next day',
              onPressed: () => _changeDate(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection({
    required String title,
    required String subtitle,
    required String fieldKey,
    required String value,
    required String hint,
    required IconData icon,
    String? actionLabel,
    VoidCallback? onAction,
    required ValueChanged<String> onChanged,
  }) {
    return _LogSection(
      title: title,
      subtitle: subtitle,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ValueKey('$fieldKey-$_dateKey'),
            initialValue: value,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          if (actionLabel != null && onAction != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton.icon(
                  key: ValueKey('$fieldKey-action'),
                  onPressed: onAction,
                  icon: const Icon(Icons.add),
                  label: Text(actionLabel),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<DailyTask> _collectionTasks(_TaskCollection collection) {
    return collection == _TaskCollection.previous
        ? _currentLog.previousTasks
        : _currentLog.meetingTasks;
  }

  Widget _buildTaskCollectionSection(_TaskCollection collection) {
    final tasks = _collectionTasks(collection);
    final isPrevious = collection == _TaskCollection.previous;
    final title = isPrevious
        ? 'Previous outstanding tasks'
        : "Today's meetings";
    final subtitle = isPrevious
        ? 'Incomplete tasks from earlier days.'
        : 'Track meetings, actions, and follow-up points.';
    final emptyText = isPrevious
        ? 'No outstanding tasks from earlier days.'
        : 'Add a meeting to track its actions.';
    final allPreviousTasksComplete =
        isPrevious && (tasks.isEmpty || tasks.every((task) => task.isComplete));

    return _LogSection(
      title: title,
      subtitle: subtitle,
      icon: isPrevious ? Icons.history : Icons.groups_outlined,
      trailing: tasks.isEmpty
          ? null
          : _CountBadge(
              label:
                  '${tasks.where((task) => task.isComplete).length}/${tasks.length}',
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allPreviousTasksComplete)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                '😊',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 42),
              ),
            ),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                emptyText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            ...tasks.map((task) => _buildCollectionTask(task, collection)),
          ],
          if (allPreviousTasksComplete && tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'All outstanding tasks are complete.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (!isPrevious)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('add-meeting-button'),
                onPressed: _addMeeting,
                icon: const Icon(Icons.add),
                label: const Text('Add meeting'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollectionTask(DailyTask task, _TaskCollection collection) {
    final taskStyle = TextStyle(
      decoration: task.isComplete ? TextDecoration.lineThrough : null,
      color: task.isComplete
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : null,
    );
    return Padding(
      key: ValueKey('${collection.name}-task-${task.id}'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('${collection.name}-task-checkbox-${task.id}'),
                value: task.isComplete,
                onChanged: (value) {
                  if (value != null) {
                    _setCollectionTaskComplete(collection, task.id, value);
                  }
                },
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                    '${collection.name}-task-text-$_dateKey-${task.id}',
                  ),
                  initialValue: task.text,
                  onChanged: (value) =>
                      _updateCollectionTaskText(collection, task.id, value),
                  style: taskStyle,
                  decoration: const InputDecoration(
                    hintText: 'Meeting or task',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add action',
                onPressed: () => _addCollectionSubtask(task, collection),
                icon: const Icon(Icons.subdirectory_arrow_right),
              ),
              IconButton(
                tooltip: 'Delete task',
                onPressed: () =>
                    unawaited(_deleteCollectionTask(collection, task.id)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (task.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42, right: 48, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  task.details,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (task.subtasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Column(
                children: task.subtasks
                    .map(
                      (subtask) =>
                          _buildCollectionSubtask(task, subtask, collection),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollectionSubtask(
    DailyTask task,
    DailySubtask subtask,
    _TaskCollection collection,
  ) {
    return Row(
      key: ValueKey('${collection.name}-subtask-${subtask.id}'),
      children: [
        Checkbox(
          key: ValueKey('${collection.name}-subtask-checkbox-${subtask.id}'),
          value: subtask.isComplete,
          visualDensity: VisualDensity.compact,
          onChanged: (value) {
            if (value != null) {
              _setCollectionSubtaskComplete(
                collection,
                task.id,
                subtask.id,
                value,
              );
            }
          },
        ),
        Expanded(
          child: TextFormField(
            key: ValueKey(
              '${collection.name}-subtask-text-$_dateKey-${subtask.id}',
            ),
            initialValue: subtask.text,
            onChanged: (value) => _updateCollectionSubtaskText(
              collection,
              task.id,
              subtask.id,
              value,
            ),
            style: TextStyle(
              decoration: subtask.isComplete
                  ? TextDecoration.lineThrough
                  : null,
            ),
            decoration: const InputDecoration(
              hintText: 'Action',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Delete action',
          onPressed: () => unawaited(
            _deleteCollectionSubtask(collection, task.id, subtask.id),
          ),
          icon: const Icon(Icons.close),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildTasksSection() {
    final tasks = _currentLog.tasks;
    return _LogSection(
      title: 'To-do / tasks',
      subtitle: 'Make a plan, then check things off as you go.',
      icon: Icons.checklist,
      trailing: tasks.isEmpty
          ? null
          : _CountBadge(
              label:
                  '${tasks.where((task) => task.isComplete).length}/${tasks.length}',
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Your task list is clear. Add a task to get started.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ...tasks.map(_buildTask),
          if (tasks.isNotEmpty) const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('add-task-button'),
              onPressed: _addTask,
              icon: const Icon(Icons.add),
              label: const Text('Add task'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTask(DailyTask task) {
    final taskStyle = TextStyle(
      decoration: task.isComplete ? TextDecoration.lineThrough : null,
      color: task.isComplete
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : null,
    );

    return Padding(
      key: ValueKey('task-${task.id}'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('task-checkbox-${task.id}'),
                value: task.isComplete,
                onChanged: (value) {
                  if (value != null) _setTaskComplete(task.id, value);
                },
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('task-text-$_dateKey-${task.id}'),
                  initialValue: task.text,
                  onChanged: (value) => _updateTaskText(task.id, value),
                  style: taskStyle,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Task',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add subtask',
                onPressed: () => _addSubtask(task),
                icon: const Icon(Icons.subdirectory_arrow_right),
              ),
              IconButton(
                tooltip: 'Delete task',
                onPressed: () => unawaited(_deleteTask(task.id)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (task.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42, right: 48, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  task.details,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (task.subtasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Column(
                children: task.subtasks
                    .map((subtask) => _buildSubtask(task, subtask))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtask(DailyTask task, DailySubtask subtask) {
    return Row(
      key: ValueKey('subtask-${subtask.id}'),
      children: [
        Checkbox(
          key: ValueKey('subtask-checkbox-${subtask.id}'),
          value: subtask.isComplete,
          visualDensity: VisualDensity.compact,
          onChanged: (value) {
            if (value != null) {
              _setSubtaskComplete(task.id, subtask.id, value);
            }
          },
        ),
        Expanded(
          child: TextFormField(
            key: ValueKey('subtask-text-$_dateKey-${subtask.id}'),
            initialValue: subtask.text,
            onChanged: (value) =>
                _updateSubtaskText(task.id, subtask.id, value),
            style: TextStyle(
              decoration: subtask.isComplete
                  ? TextDecoration.lineThrough
                  : null,
              color: subtask.isComplete
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Subtask',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Delete subtask',
          onPressed: () => unawaited(_deleteSubtask(task.id, subtask.id)),
          icon: const Icon(Icons.close),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildSaveStatus() {
    final (label, icon, color) = switch (_saveState) {
      _SaveState.saved => (
        'Saved',
        Icons.cloud_done_outlined,
        Theme.of(context).colorScheme.primary,
      ),
      _SaveState.pending => (
        'Unsaved changes',
        Icons.schedule,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      _SaveState.saving => (
        'Saving...',
        Icons.sync,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      _SaveState.error => (
        'Save failed',
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
    };

    return Tooltip(
      message: _saveError?.toString() ?? label,
      child: TextButton.icon(
        onPressed: _saveState == _SaveState.error
            ? () => unawaited(_saveNow())
            : null,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
      ),
    );
  }
}

class _AddSubtaskDialog extends StatefulWidget {
  const _AddSubtaskDialog();

  @override
  State<_AddSubtaskDialog> createState() => _AddSubtaskDialogState();
}

class _AddSubtaskDialogState extends State<_AddSubtaskDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a subtask'),
      content: TextField(
        key: const ValueKey('subtask-input'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Subtask',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _AddMeetingDialog extends StatefulWidget {
  const _AddMeetingDialog();

  @override
  State<_AddMeetingDialog> createState() => _AddMeetingDialogState();
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog({
    this.dialogTitle = 'Add a task',
    this.titleLabel = 'Task',
    this.titleHint = 'What needs to be done?',
  });

  final String dialogTitle;
  final String titleLabel;
  final String titleHint;

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      DailyTask(
        id: '',
        text: _titleController.text.trim(),
        details: _detailsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('task-title-input'),
              controller: _titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: widget.titleLabel,
                hintText: widget.titleHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('task-details-input'),
              controller: _detailsController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Details',
                hintText: 'Add context or notes...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.titleLabel == 'Email' ? 'Add email' : 'Add task'),
        ),
      ],
    );
  }
}

class _AddMeetingDialogState extends State<_AddMeetingDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a meeting'),
      content: TextField(
        key: const ValueKey('meeting-input'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Meeting',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _LogSection extends StatelessWidget {
  const _LogSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

enum _SaveState { saved, pending, saving, error }

enum _TaskCollection { previous, meetings }

String dailyLogDateKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatDate(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
}

int _entryCounter = 0;

String _newEntryId() {
  return '${DateTime.now().microsecondsSinceEpoch}-${_entryCounter++}';
}

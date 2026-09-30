import 'dart:io';

import 'package:dayforge/app_info.dart';
import 'package:dayforge/data/daily_log_store.dart';
import 'package:dayforge/main.dart';
import 'package:dayforge/models/daily_log.dart';
import 'package:dayforge/pages/daily_log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late DailyLogStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('dayforge-test');
    store = DailyLogStore(directory: temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('edits and tasks autosave and reload by day', (tester) async {
    final date = DateTime(2026, 9, 25);
    const dateKey = '2026-09-25';

    await tester.pumpWidget(
      MaterialApp(
        home: DailyLogPage(store: store, initialDate: date),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isTrue);
    expect(find.byIcon(Icons.event_available), findsOneWidget);
    expect(find.text(appTitle), findsOneWidget);
    expect(find.text('Friday, September 25, 2026'), findsOneWidget);
    expect(find.text('Previous outstanding tasks'), findsOneWidget);
    expect(find.text("Today's emails"), findsOneWidget);
    expect(find.text("Today's meetings"), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('add-task-button')));
    await tester.tap(find.byKey(const ValueKey('add-task-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-input')),
      'First task',
    );
    await tester.tap(find.text('Add task').last);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-task-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-input')),
      'Second task',
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-details-input')),
      'Second task details',
    );
    expect(find.text('Second task details'), findsOneWidget);
    await tester.tap(find.text('Add task').last);
    await tester.ensureVisible(find.byKey(const ValueKey('add-task-button')));
    await tester.pump();

    await tester.ensureVisible(find.byTooltip('Add subtask').first);
    await tester.tap(find.byTooltip('Add subtask').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.byKey(const ValueKey('subtask-input')),
      'Book a room',
    );
    await tester.tap(find.text('Add').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _waitForSaved(
      tester,
      condition: () async {
        final logs = await store.loadAll();
        final saved = logs[dateKey];
        return saved != null && saved.tasks.length == 2;
      },
    );

    final savedLogs = await tester.runAsync(store.loadAll);
    expect(savedLogs, isNotNull);
    final savedLog = savedLogs![dateKey]!;
    expect(savedLog.tasks.map((task) => task.text).toList(), [
      'Second task',
      'First task',
    ]);
    expect(savedLog.tasks.last.isComplete, isTrue);
    expect(savedLog.tasks.last.subtasks.single.text, 'Book a room');

    final completedTaskField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(
          ValueKey('task-text-$dateKey-${savedLog.tasks.last.id}'),
        ),
        matching: find.byType(TextField),
      ),
    );
    expect(completedTaskField.style?.decoration, TextDecoration.lineThrough);

    await tester.ensureVisible(find.byKey(const ValueKey('next-day')));
    await tester.tap(find.byKey(const ValueKey('next-day')));
    await tester.pump();
    expect(find.text('Saturday, September 26, 2026'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('previous-day')));
    await tester.tap(find.byKey(const ValueKey('previous-day')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: DailyLogPage(store: store, initialDate: date),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.text('Second task'), findsOneWidget);
    expect(find.text('First task'), findsOneWidget);
  });

  testWidgets('autosave retries after a transient save failure', (
    tester,
  ) async {
    final date = DateTime(2026, 9, 25);
    final flakyStore = _FailOnceDailyLogStore(directory: temporaryDirectory);

    await tester.pumpWidget(
      MaterialApp(
        home: DailyLogPage(store: flakyStore, initialDate: date),
      ),
    );
    await _pumpUntilLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('add-email-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('email-input')),
      'Retry me',
    );
    await tester.tap(find.byKey(const ValueKey('add-email-dialog-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await _waitForSaved(
      tester,
      condition: () async {
        final logs = await flakyStore.loadAll();
        return logs['2026-09-25']?.emailTasks.single.text == 'Retry me';
      },
    );
    expect(flakyStore.saveAttempts, greaterThanOrEqualTo(2));
  });

  testWidgets('import prevents pending old-page autosaves from overwriting it', (
    tester,
  ) async {
    final date = DateTime(2026, 9, 25);
    final pageKey = GlobalKey<DailyLogPageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: DailyLogPage(
          key: pageKey,
          store: store,
          initialDate: date,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('add-email-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('email-input')),
      'Unsaved old-page edit',
    );
    await tester.tap(find.byKey(const ValueKey('add-email-dialog-button')));
    await tester.pump();

    final backupDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('dayforge-widget-import'),
    ))!;
    addTearDown(() => backupDirectory.delete(recursive: true));
    final backupStore = DailyLogStore(directory: backupDirectory);
    const importedLog = DailyLog(dateKey: '2026-09-26');
    final backup = File(
      '${backupDirectory.path}${Platform.pathSeparator}dayforge.json',
    );
    await tester.runAsync(() async {
      await backupStore.saveAll({importedLog.dateKey: importedLog});
      await backupStore.exportTo(backup);
    });

    await tester.runAsync(() async {
      await pageKey.currentState!.prepareForImport();
      await store.importFrom(backup);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DailyLogPage(
          key: GlobalKey<DailyLogPageState>(),
          store: store,
          initialDate: date,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    final importedLogs = await tester.runAsync(store.loadAll);
    expect(importedLogs!.keys, {importedLog.dateKey});
    expect(importedLogs[importedLog.dateKey]!.toJson(), importedLog.toJson());
  });

  testWidgets('adds an email checkpoint through its modal', (tester) async {
    final date = DateTime(2026, 9, 25);
    await tester.pumpWidget(
      MaterialApp(
        home: DailyLogPage(store: store, initialDate: date),
      ),
    );
    await _pumpUntilLoaded(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('add-email-button')));
    await tester.tap(find.byKey(const ValueKey('add-email-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('email-input')),
      'Reply to the project update',
    );
    await tester.tap(find.byKey(const ValueKey('add-email-dialog-button')));
    await tester.pumpAndSettle();

    expect(find.text('Reply to the project update'), findsOneWidget);
  });

  testWidgets('opens settings from the app bar', (tester) async {
    await tester.pumpWidget(const DayforgeApp());
    await _pumpUntilLoaded(tester);

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Version $appVersion'), findsOneWidget);
    expect(find.text('Color scheme'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Export dayforge'), findsOneWidget);
    expect(find.text('Import dayforge'), findsOneWidget);
  });
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

Future<void> _waitForSaved(
  WidgetTester tester, {
  required Future<bool> Function() condition,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final isSaved = await tester.runAsync(condition) ?? false;
    if (isSaved) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(await tester.runAsync(condition) ?? false, isTrue);
}

class _FailOnceDailyLogStore extends DailyLogStore {
  _FailOnceDailyLogStore({required super.directory});

  int saveAttempts = 0;

  @override
  Future<void> saveAll(Map<String, DailyLog> logs) async {
    saveAttempts++;
    if (saveAttempts == 1) {
      throw const FileSystemException('temporary failure');
    }
    await super.saveAll(logs);
  }
}

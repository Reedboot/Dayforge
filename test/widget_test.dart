import 'dart:io';

import 'package:dayforge/app_info.dart';
import 'package:dayforge/data/daily_log_store.dart';
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
    expect(find.text(appTitle), findsOneWidget);
    expect(find.text('Friday, September 25, 2026'), findsOneWidget);
    expect(find.text('Previous outstanding tasks'), findsOneWidget);
    expect(find.text("Today's emails"), findsOneWidget);
    expect(find.text("Today's meetings"), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('task-input')),
      'First task',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('add-task-button')));
    await tester.tap(find.byKey(const ValueKey('add-task-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('task-input')),
      'Second task',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('add-task-button')));
    await tester.tap(find.byKey(const ValueKey('add-task-button')));
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

    await tester.ensureVisible(find.byKey(const ValueKey('emails-$dateKey')));
    await tester.enterText(
      find.byKey(const ValueKey('emails-$dateKey')),
      'Reply to the project update',
    );

    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _waitForSaved(tester);

    final savedLogs = await tester.runAsync(store.loadAll);
    expect(savedLogs, isNotNull);
    final savedLog = savedLogs![dateKey]!;
    expect(savedLog.tasks.map((task) => task.text).toList(), [
      'Second task',
      'First task',
    ]);
    expect(savedLog.tasks.last.isComplete, isTrue);
    expect(savedLog.tasks.last.subtasks.single.text, 'Book a room');
    expect(savedLog.emails, 'Reply to the project update');

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
    await tester.ensureVisible(find.byKey(const ValueKey('emails-2026-09-26')));
    await tester.enterText(
      find.byKey(const ValueKey('emails-2026-09-26')),
      'Next-day note',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _waitForSaved(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('previous-day')));
    await tester.tap(find.byKey(const ValueKey('previous-day')));
    await tester.pump();
    final originalEmailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('emails-2026-09-25')),
    );
    expect(originalEmailField.initialValue, 'Reply to the project update');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: DailyLogPage(store: store, initialDate: date),
      ),
    );
    await _pumpUntilLoaded(tester);

    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('emails-2026-09-25')),
    );
    expect(emailField.initialValue, 'Reply to the project update');
    expect(find.text('Second task'), findsOneWidget);
    expect(find.text('First task'), findsOneWidget);
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

Future<void> _waitForSaved(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('Saved').evaluate().isNotEmpty) return;
  }
  expect(find.text('Saved'), findsOneWidget);
}

import 'dart:io';

import 'package:dayforge/data/daily_log_store.dart';
import 'package:dayforge/models/daily_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late DailyLogStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'dayforge-store-test',
    );
    store = DailyLogStore(directory: temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('saves and reloads logs with completed tasks and subtasks', () async {
    const log = DailyLog(
      dateKey: '2026-09-25',
      previousOutstandingTasks: 'Finish the draft',
      emails: 'Reply to Alex',
      meetings: 'Planning at 10',
      tasks: const [
        DailyTask(
          id: 'task-1',
          text: 'Prepare agenda',
          isComplete: true,
          subtasks: [
            DailySubtask(
              id: 'subtask-1',
              text: 'Collect updates',
              isComplete: true,
            ),
          ],
        ),
      ],
    );

    await store.saveAll({log.dateKey: log});
    final loaded = await store.loadAll();

    expect(loaded, hasLength(1));
    expect(loaded[log.dateKey]!.toJson(), log.toJson());
  });

  test('returns no logs before the first save', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('exports and imports a dayforge backup', () async {
    const log = DailyLog(
      dateKey: '2026-09-25',
      emailTasks: [DailyTask(id: 'email-1', text: 'Reply to Alex')],
    );
    final backup = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}dayforge.json',
    );

    await store.saveAll({log.dateKey: log});
    await store.exportTo(backup);

    final importedDirectory = await Directory.systemTemp.createTemp(
      'dayforge-import-test',
    );
    addTearDown(() => importedDirectory.delete(recursive: true));
    final importedStore = DailyLogStore(directory: importedDirectory);
    await importedStore.importFrom(backup);

    expect(
      (await importedStore.loadAll())[log.dateKey]!.toJson(),
      log.toJson(),
    );
  });

  test('reports unsupported saved data instead of replacing it', () async {
    await temporaryDirectory.create(recursive: true);
    await File(
      '${temporaryDirectory.path}${Platform.pathSeparator}daily_logs.json',
    ).writeAsString('not json');

    await expectLater(store.loadAll(), throwsFormatException);
  });
}

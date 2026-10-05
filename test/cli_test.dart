import 'dart:io';

import 'package:dayforge/cli.dart';
import 'package:dayforge/data/daily_log_store.dart';
import 'package:dayforge/models/daily_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late DailyLogStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'dayforge-cli-test',
    );
    store = DailyLogStore(directory: temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('adds a general task to today by default', () async {
    final today = DateTime(2026, 10, 5, 11);

    final result = await runDayforgeCli(
      ['add', 'Prepare', 'the', 'report'],
      store: store,
      now: today,
      printOut: (_) {},
      printError: fail,
    );

    expect(result, 0);
    final logs = await store.loadAll();
    expect(logs.keys, ['2026-10-05']);
    expect(logs['2026-10-05']!.tasks.single.text, 'Prepare the report');
  });

  test(
    'adds email and meeting entries to their selected date sections',
    () async {
      final today = DateTime(2026, 10, 5);

      expect(
        await runDayforgeCli(
          ['add', '--type=email', 'Reply to Sam'],
          store: store,
          now: today,
          printOut: (_) {},
          printError: fail,
        ),
        0,
      );
      expect(
        await runDayforgeCli(
          [
            'add',
            '--type',
            'meeting',
            '--date',
            '2026-10-06',
            'Project check-in',
          ],
          store: store,
          now: today,
          printOut: (_) {},
          printError: fail,
        ),
        0,
      );

      final logs = await store.loadAll();
      expect(logs['2026-10-05']!.emailTasks.single.text, 'Reply to Sam');
      expect(logs['2026-10-06']!.meetingTasks.single.text, 'Project check-in');
    },
  );

  test('rejects invalid dates without changing saved data', () async {
    await store.saveAll({'2026-10-05': const DailyLog(dateKey: '2026-10-05')});
    final errors = <String>[];

    final result = await runDayforgeCli(
      ['add', '--date', '2026-02-31', 'Invalid date task'],
      store: store,
      now: DateTime(2026, 10, 5),
      printOut: (_) {},
      printError: errors.add,
    );

    expect(result, 2);
    expect(errors, hasLength(1));
    expect((await store.loadAll())['2026-10-05']!.tasks, isEmpty);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

Future<void> runBd(Directory store, List<String> args) async {
  final initializesStore = args.first == 'init';
  final result = await Process.run(
    'bd',
    [
      if (!initializesStore) ...['-C', store.path],
      ...args,
    ],
    workingDirectory: initializesStore ? store.path : null,
    environment: {...Platform.environment, 'BD_NON_INTERACTIVE': '1'},
  );
  expect(
    result.exitCode,
    0,
    reason: 'bd ${args.join(' ')}\n${result.stdout}\n${result.stderr}',
  );
}

Future<Directory> filingStore() async {
  final store = Directory.systemTemp.createTempSync('filing-command-');
  addTearDown(() {
    if (store.existsSync()) store.deleteSync(recursive: true);
  });
  await runBd(store, [
    'init',
    '--prefix',
    'filing',
    '--skip-agents',
    '--skip-hooks',
    '--non-interactive',
  ]);
  return store;
}

({CommandRunner<int> runner, StringBuffer out, StringBuffer err}) harness(
  Directory store,
) {
  final out = StringBuffer();
  final err = StringBuffer();
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        FilingCommand(storeRoot: () => store.path, out: out, err: err),
      ),
    out: out,
    err: err,
  );
}

// These tests drive a REAL bd binary end to end; a fake would not prove the
// filing contract holds against bd's actual argv/exit-code surface.
final bool _bdAvailable = () {
  try {
    return Process.runSync('bd', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();
final String? _skipWithoutBd = _bdAvailable
    ? null
    : 'requires a real bd binary on PATH (absent in CI)';

void main() {
  test(
    'real bd filing passes all four requirements',
    skip: _skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-blocker',
        '--title',
        'blocker',
        '--type',
        'task',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'create',
        '--id',
        'filing-good',
        '--title',
        'good filing',
        '--type',
        'task',
        '--defer',
        '+1h',
        '--description',
        'Package: grid_assets\nBlocked by: filing-blocker',
        '--acceptance',
        '- [ ] dart test passes',
        '--metadata',
        '{"validation_plan":"dart test"}',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'dep',
        'add',
        'filing-good',
        'filing-blocker',
        '--actor',
        'test',
      ]);

      final h = harness(store);
      expect(
        await h.runner.run(['filing', '--json', 'filing-good']),
        0,
        reason: '${h.out}\n${h.err}',
      );
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      final rows = (report['requirements'] as List)
          .cast<Map<String, dynamic>>();
      expect(report['passed'], isTrue);
      expect(rows, hasLength(4));
      expect(rows.every((row) => row['passed'] == true), isTrue);
    },
  );

  test(
    'reports every failed requirement and exits non-zero',
    skip: _skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-blocker',
        '--title',
        'unwired blocker',
        '--type',
        'task',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'create',
        '--id',
        'filing-bad',
        '--title',
        'bad filing',
        '--type',
        'epic',
        '--description',
        'Depends on: filing-blocker',
        '--metadata',
        '{"validation_plan":" "}',
        '--actor',
        'test',
      ]);

      final h = harness(store);
      expect(await h.runner.run(['filing', '--json', 'filing-bad']), 1);
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      final rows = (report['requirements'] as List)
          .cast<Map<String, dynamic>>();
      expect(report['passed'], isFalse);
      expect(rows, hasLength(4));
      expect(rows.every((row) => row['passed'] == false), isTrue);
    },
  );

  test('usage and missing beads fail loudly', skip: _skipWithoutBd, () async {
    final store = await filingStore();
    expect(await harness(store).runner.run(['filing']), 64);
    expect(
      await harness(store).runner.run(['filing', 'filing-a', 'filing-b']),
      64,
    );
    final missing = harness(store);
    expect(await missing.runner.run(['filing', '--json', 'filing-missing']), 1);
    final report = jsonDecode(missing.out.toString()) as Map<String, dynamic>;
    expect(report['passed'], isFalse);
    expect(report['requirements'], isEmpty);
    expect(report['error'], 'bead not found');
  });
}

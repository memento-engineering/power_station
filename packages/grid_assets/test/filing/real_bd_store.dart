import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// The REAL `bd` harness the filing suites drive the verb against.
///
/// These tests run the actual binary end to end; a fake would not prove the
/// filing contract holds against bd's own argv, record shape and exit codes —
/// and the dependency projection exists BECAUSE two of bd's surfaces disagree
/// about `external:` rows. The helpers live here rather than in one suite so
/// the second suite composes them instead of restating them.

/// Runs one `bd` invocation against [store] and fails the test on non-zero.
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

/// Creates a throwaway `filing`-prefixed bd store, torn down with the test.
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

/// A runner carrying [FilingCommand] over [store], with [armed] as the
/// station roster the `external:` rows resolve against (null = none supplied).
({CommandRunner<int> runner, StringBuffer out, StringBuffer err}) harness(
  Directory store, {
  Set<String>? armed,
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        FilingCommand(
          storeRoot: () => store.path,
          armedSubstations: () => armed,
          out: out,
          err: err,
        ),
      ),
    out: out,
    err: err,
  );
}

/// The `dependencies` row of one `filing --json` run.
Map<String, dynamic> dependencyRow(StringBuffer out) {
  final report = jsonDecode(out.toString()) as Map<String, dynamic>;
  return (report['requirements'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere(
        (Map<String, dynamic> row) => row['requirement'] == 'dependencies',
      );
}

final bool _bdAvailable = () {
  try {
    return Process.runSync('bd', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

/// The `skip` reason when no real `bd` is on PATH (CI), or null when there is.
final String? skipWithoutBd = _bdAvailable
    ? null
    : 'requires a real bd binary on PATH (absent in CI)';

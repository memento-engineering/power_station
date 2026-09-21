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

/// Creates a throwaway [prefix]-prefixed bd store, torn down with the test.
///
/// Initialized as a PROXIED SERVER, which is the only shape the house binary
/// can open: a CGO-free `bd` refuses embedded mode outright ("embedded Dolt
/// requires a CGO build"), so a plain `bd init` reds every real-bd test on the
/// developer machine while passing nowhere. Proxied mode is also the mode the
/// live stores run, so these tests exercise the shape production reads —
/// including the one that refuses `bd export`
/// (power_station#the-per-store-bead-read-is-scoped-never-the-export-surface).
Future<Directory> bdStore({required String prefix}) async {
  final store = Directory.systemTemp.createTempSync('filing-command-');
  addTearDown(() async {
    // Order matters: the proxy and its child sql-server hold the Dolt data dir
    // the delete below removes, and they outlive the test run if left.
    await _stopStoreProcesses(store.path);
    if (store.existsSync()) store.deleteSync(recursive: true);
  });
  await runBd(store, [
    'init',
    '--prefix',
    prefix,
    '--skip-agents',
    '--skip-hooks',
    '--non-interactive',
    '--proxied-server',
  ]);
  return store;
}

/// Every store process still running out of [tempPath].
///
/// Matched on the process's own `--config` / `--root` arguments rather than on
/// bd's PID files: bd re-spawns a proxy to serve the very command that stops
/// the previous one, so a PID captured from `.beads/dolt/proxy.pid` names a
/// process that is already gone while its successor is missed entirely. The
/// process table is the only account that cannot go stale.
Future<List<({int pid, String command})>> _storeProcesses(
  String tempPath,
) async {
  final result = await Process.run('ps', ['-axo', 'pid=,command=']);
  if (result.exitCode != 0) return const [];

  final resolvedTemp = Directory(tempPath).existsSync()
      ? Directory(tempPath).resolveSymbolicLinksSync()
      : tempPath;
  final tempPrefix = '$resolvedTemp${Platform.pathSeparator}';
  final row = RegExp(r'^\s*(\d+)\s+(.*)$');

  return [
    for (final line in (result.stdout as String).split('\n'))
      if (row.firstMatch(line) case final match?)
        if (_namesTempPath(match.group(2)!, tempPrefix))
          (pid: int.parse(match.group(1)!), command: match.group(2)!),
  ];
}

/// A store process configured under [tempPrefix] — matched on the resolved
/// path arguments so a symlinked temp root still counts.
bool _namesTempPath(String command, String tempPrefix) {
  if (!command.contains('dolt sql-server') &&
      !command.contains('db-proxy-child')) {
    return false;
  }
  for (final match in _pathArgument.allMatches(command)) {
    final raw = match.group(1) ?? match.group(2) ?? match.group(3)!;
    final entry = File(raw);
    final resolved = entry.existsSync()
        ? entry.resolveSymbolicLinksSync()
        : entry.absolute.path;
    if (resolved.startsWith(tempPrefix)) return true;
  }
  return false;
}

final RegExp _pathArgument = RegExp(
  r'''(?:^|\s)--(?:config|root)(?:=|\s+)(?:"([^"]+)"|'([^']+)'|(\S+))''',
);

/// Tears the proxied store down: a SIGKILL fence driven by the process census,
/// repeated until nothing started under [tempPath] still runs.
///
/// `bd dolt stop` is NOT the instrument. It is a MODE CHANGE — it migrates the
/// workspace back to embedded storage, which a CGO-free binary cannot even
/// open — and it re-spawns a proxy to serve its own command, so the process it
/// leaves behind is never the one it reported stopping.
///
/// LOUD, because a survivor is not cosmetic: it holds a Dolt data dir that the
/// temporary-directory delete is about to remove, and it outlives the run.
Future<void> _stopStoreProcesses(String tempPath) async {
  var survivors = await _storeProcesses(tempPath);
  for (var round = 0; round < 40 && survivors.isNotEmpty; round++) {
    for (final survivor in survivors) {
      Process.killPid(survivor.pid, ProcessSignal.sigkill);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    survivors = await _storeProcesses(tempPath);
  }

  expect(
    [for (final survivor in survivors) survivor.command],
    isEmpty,
    reason: 'store processes survived under $tempPath',
  );
}

/// Creates a throwaway `filing`-prefixed bd store, torn down with the test.
Future<Directory> filingStore() => bdStore(prefix: 'filing');

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

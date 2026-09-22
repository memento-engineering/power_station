import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/proxied_bd_test_support.dart' as proxied_bd;
import 'filing_evidence_fakes.dart';

/// The REAL `bd` harness the filing suites drive the verb against.
///
/// These tests run the actual binary end to end; a fake would not prove the
/// filing contract holds against bd's own argv, record shape and exit codes —
/// and the dependency projection exists BECAUSE two of bd's surfaces disagree
/// about `external:` rows. The helpers live here rather than in one suite so
/// the second suite composes them instead of restating them.
///
/// The PROXIED-SERVER lifecycle underneath — reserving the pair's ports,
/// verifying the store bound the servers it started, and stopping them before
/// the directory goes — is not restated here either: it is
/// `../support/proxied_bd_test_support.dart`, the one such harness in this
/// workspace, shared with `github_grid_assets`' station acceptance fixture so
/// the two cannot drift.

/// Runs one `bd` invocation against [store] and fails the test on non-zero.
///
/// Every failure carries the bd version and the server identity the store is
/// bound to, so the NEXT mismatch names itself: an exit code alone cannot tell
/// a broken argv from a store answering out of a server it never started.
Future<void> runBd(Directory store, List<String> args) async {
  final result = await _spawnBd(store, args);
  expect(
    result.exitCode,
    0,
    reason:
        'bd ${args.join(' ')}\n${result.stdout}\n${result.stderr}\n'
        '${_boundServer(store)}',
  );
}

/// [runBd], with the invocation's stdout returned.
///
/// The same spawn contract, so a suite that needs to READ bd's answer never
/// hand-rolls one that resolves a different store — which is the defect
/// [_spawnBd] documents.
Future<String> bdOutput(Directory store, List<String> args) async {
  final result = await _spawnBd(store, args);
  expect(
    result.exitCode,
    0,
    reason:
        'bd ${args.join(' ')}\n${result.stdout}\n${result.stderr}\n'
        '${_boundServer(store)}',
  );
  return result.stdout as String;
}

/// Spawns `bd` INSIDE [store], and never with `-C`.
///
/// The working directory is the whole contract. MEASURED on bd 1.1.0: when the
/// spawning process sits in a git work tree whose `.beads/` is a REDIRECT stub
/// — which is exactly a per-bead grid worktree, whose `.beads/redirect` points
/// at the checkout's root store — that redirect WINS over `-C`. A
/// `bd -C <store> config get issue_prefix` then answers `(not set)` for a
/// store whose own prefix is `filing`, and the next `bd -C <store> create`
/// refuses with `create: mint top-level ID: issue_prefix config is missing`.
/// That is the whole of the six real-bd filing failures, and it is why they
/// reproduce in every station round and in no main-checkout run: the redirect
/// only exists in the worktree.
///
/// Spawning in the store resolves the store, because bd's walk up from the
/// working directory reaches `<store>/.beads` before anything else. It is also
/// what the PRODUCTION client does — `ProcessBdRunner` runs
/// `workingDirectory: workspaceRoot` and passes no `-C` — so the fixture now
/// reaches its store the same way the code under test does.
Future<ProcessResult> _spawnBd(Directory store, List<String> args) =>
    Process.run(
      'bd',
      args,
      workingDirectory: store.path,
      environment: {...Platform.environment, 'BD_NON_INTERACTIVE': '1'},
    );

/// Creates a throwaway [prefix]-prefixed bd store, torn down with the test.
///
/// Initialized as a PROXIED SERVER, which is the only shape the house binary
/// can open: a CGO-free `bd` refuses embedded mode outright ("embedded Dolt
/// requires a CGO build"), so a plain `bd init` reds every real-bd test on the
/// developer machine while passing nowhere. Proxied mode is also the mode the
/// live stores run, so these tests exercise the shape production reads —
/// including the one that refuses `bd export`
/// (power_station#the-per-store-bead-read-is-scoped-never-the-export-surface).
///
/// The server pair is the fixture's OWN: both listeners run on ports this
/// reserves, from a config this writes, under a root this names, and the live
/// processes are then checked to be serving exactly those paths and ports
/// before the store is handed back. That is what a store cannot do by
/// accepting whatever server bd finds: three abandoned proxied servers for
/// long-deleted temp stores were measured on the station host, six days old,
/// and a store that binds to one answers out of a data directory that no
/// longer exists.
///
/// [at] places the store at a CHOSEN directory (created when absent) instead
/// of a fresh temp one, for a suite whose subject is WHERE a store sits —
/// a repository root against the grid home nested under it. Every such
/// directory is still torn down here, so a caller never hand-rolls the
/// process census.
Future<Directory> bdStore({required String prefix, Directory? at}) async {
  final store = at ?? Directory.systemTemp.createTempSync('filing-command-');
  if (!store.existsSync()) store.createSync(recursive: true);
  // Registered BEFORE init, so a store whose server comes up and then fails
  // verification is still reaped rather than abandoned.
  addTearDown(() => tearDownBdStore(store));

  final storePath = store.resolveSymbolicLinksSync();
  final rootPath = p.join(storePath, '.beads', 'dolt');
  final configPath = p.join(rootPath, _fixtureConfigName);
  Directory(rootPath).createSync(recursive: true);
  final ports = await proxied_bd.reserveProxiedBdPorts();
  File(configPath).writeAsStringSync(_doltServerConfig(ports.doltPort));

  await runBd(store, [
    'init',
    '--prefix',
    prefix,
    '--skip-agents',
    '--skip-hooks',
    '--non-interactive',
    '--proxied-server',
    '--proxied-server-config-path',
    configPath,
    '--proxied-server-root-path',
    rootPath,
    '--proxied-server-port',
    '${ports.proxyPort}',
  ]);

  final identity = await proxied_bd.verifyBdStoreIdentity(
    bdVersion: _bdVersion,
    storePath: storePath,
    rootPath: rootPath,
    configPath: configPath,
    reserved: ports,
  );
  for (final key in _identityKeys(store)) {
    _identities[key] = identity;
  }
  await _refuseACapturedStore(store, prefix: prefix, identity: identity);
  return store;
}

/// Refuses unless `bd` answers for [store] itself.
///
/// The POSITIVE CONTROL the six filing failures went without. A verified
/// server pair proves the store has its own Dolt; it does not prove the `bd`
/// this fixture spawns resolves THAT store, and a bd resolving another
/// workspace answers every read with an empty store and every write with
/// `issue_prefix config is missing` — six failures whose message names neither
/// the fixture nor the workspace that captured it.
///
/// `config get issue_prefix` is the cheapest question only the right store can
/// answer: bd persists the prefix in the store's own database, so a captured
/// resolution comes back `(not set)` while this store's comes back [prefix].
Future<void> _refuseACapturedStore(
  Directory store, {
  required String prefix,
  required proxied_bd.BdStoreIdentity identity,
}) async {
  final answered = (await _spawnBd(store, const [
    'config',
    'get',
    'issue_prefix',
  ])).stdout;
  final resolved = (answered as String).trim();
  if (resolved == prefix) return;
  throw StateError(
    'the fixture bd store at ${identity.storePath} is not the store bd '
    'answers for: `bd config get issue_prefix` said "$resolved", not '
    '"$prefix". A `.beads/` above the spawn captured it — a redirect stub in '
    'an enclosing git work tree does exactly this, and it is what made six '
    'filing tests refuse with `issue_prefix config is missing`. $identity',
  );
}

/// The server pair [store] was bound to when [bdStore] initialized it.
///
/// Retained past the store's deletion on purpose: a leaked server is only
/// diagnosable — and only reapable — while something still remembers which
/// PIDs and ports belonged to the directory that is now gone.
proxied_bd.BdStoreIdentity bdStoreIdentity(Directory store) {
  final identity = _identityOrNull(store);
  if (identity != null) return identity;
  throw StateError('no bd store was initialized at ${store.path}');
}

/// Every store process still running out of [store]'s directory.
Future<List<({int pid, String command})>> bdStoreProcesses(Directory store) =>
    proxied_bd.workspaceStoreProcesses(_censusPath(store));

/// Stops [store]'s server pair, AWAITS its exit, and only then deletes it.
///
/// Order is the whole point, and the fence that enforces it is the shared
/// [proxied_bd.stopAndAwaitProxiedStateStore]: the proxy and its `dolt
/// sql-server` hold the data directory this delete removes, so nothing may be
/// left holding it when the delete runs. The census is then read on BOTH sides
/// — before the delete, where residue is a writer the stop fence did not
/// reach, and after it, where residue is a client that arrived during the
/// delete and can re-create the store.
///
/// LOUD on a survivor, because the alternative is the six-day-old orphan this
/// fixture was measured leaking. Idempotent, so the registered teardown may
/// follow a manual call.
Future<void> tearDownBdStore(Directory store) async {
  final identity = _identityOrNull(store);
  final storePath = _censusPath(store);
  final rootPath = identity?.rootPath ?? p.join(storePath, '.beads', 'dolt');

  await proxied_bd.stopAndAwaitProxiedStateStore(
    workspacePath: storePath,
    pidRootPath: rootPath,
    recordedPids: {
      if (identity != null) ...[identity.proxyPid, identity.doltPid],
    },
  );
  proxied_bd.expectEmptyWorkspaceProcessCensus(
    await proxied_bd.workspaceProcessCensus(storePath),
    workspacePath: storePath,
    phase: 'before delete (${identity ?? 'never initialized here'})',
  );

  if (store.existsSync()) store.deleteSync(recursive: true);

  proxied_bd.expectEmptyWorkspaceProcessCensus(
    await proxied_bd.workspaceProcessCensus(storePath),
    workspacePath: storePath,
    phase: 'after delete (${identity ?? 'never initialized here'})',
  );
}

/// The fixture's own Dolt config, kept under `.beads/dolt/` so bd's generated
/// `.gitignore` (`dolt/`) already covers it in a store that is also a git repo.
const _fixtureConfigName = 'fixture-server.yaml';

/// The Dolt YAML the fixture's `dolt sql-server` is started from.
///
/// [port] is RESERVED by the fixture rather than assigned by bd, which is what
/// makes "am I talking to the server I started?" a checkable question. The
/// Beads marker and the `auto_gc_behavior` key are what keep bd from printing
/// an unmanaged-config warning on every command against the store.
String _doltServerConfig(int port) =>
    '# Managed by Beads - safe to delete (will be regenerated).\n'
    'log_level: info\n'
    'behavior:\n'
    '    auto_gc_behavior:\n'
    '        archive_level: 0\n'
    'listener:\n'
    '    host: 127.0.0.1\n'
    '    port: $port\n';

/// Every identity [bdStore] has minted, under every key a caller can ask with.
final Map<String, proxied_bd.BdStoreIdentity> _identities = {};

/// The keys [store] may be looked up under: the path the caller holds, and the
/// canonical path the census matches on.
///
/// They differ under any symlinked root — every macOS temp directory — and the
/// canonical one stops resolving once the directory is deleted, so both are
/// recorded and both are tried.
List<String> _identityKeys(Directory store) =>
    {p.absolute(store.path), _canonicalPath(store)}.toList(growable: false);

proxied_bd.BdStoreIdentity? _identityOrNull(Directory store) {
  for (final key in _identityKeys(store)) {
    if (_identities[key] case final identity?) return identity;
  }
  return null;
}

/// The path the process census matches [store] on: its retained canonical path
/// when one was minted, and otherwise the best resolution available now.
String _censusPath(Directory store) =>
    _identityOrNull(store)?.storePath ?? _canonicalPath(store);

String _canonicalPath(Directory store) => store.existsSync()
    ? store.resolveSymbolicLinksSync()
    : p.absolute(store.path);

/// The server a `bd` failure was bound to, as a line the failure carries.
String _boundServer(Directory store) =>
    _identityOrNull(store)?.toString() ??
    'bd_version=$_bdVersion store_path=${p.absolute(store.path)} '
        'config_path=unavailable root_path=unavailable '
        'proxy_pid=unavailable proxy_port=unavailable '
        'dolt_pid=unavailable dolt_port=unavailable '
        '(no verified server: the store was not initialized here yet)';

/// Creates a throwaway `filing`-prefixed bd store, torn down with the test.
Future<Directory> filingStore() => bdStore(prefix: 'filing');

/// A runner carrying [FilingCommand] over [store], with [armed] as the
/// station roster the `external:` rows resolve against (null = none supplied).
///
/// The PRE-STAMP ADVISORY is a scripted Fake, and [advisory] is how a suite
/// scripts it. These suites measure the TEN MECHANICAL ROWS against a real bd
/// store; the advisory is a live inference call, and letting the verb's default
/// composition reach one here would put a model between the store and the row
/// under test.
({CommandRunner<int> runner, StringBuffer out, StringBuffer err}) harness(
  Directory store, {
  Set<String>? armed,
  FilingAdvisory? advisory,
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        FilingCommand(
          storeRoot: () => store.path,
          armedSubstations: () => armed,
          advisory: advisory ?? FakeFilingAdvisory(),
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

/// What the installed `bd` is and what its `init` accepts, resolved once.
final ({String version, Set<String> initFlags})? _installedBd = () {
  final ProcessResult version;
  try {
    version = Process.runSync('bd', ['--version']);
  } on ProcessException {
    return null;
  }
  if (version.exitCode != 0) return null;
  final help = Process.runSync('bd', ['init', '--help']);
  final text = '${help.stdout}\n${help.stderr}';
  return (
    version: (version.stdout as String).trim(),
    initFlags: {
      for (final match in RegExp(r'--[a-z0-9-]+').allMatches(text)) match[0]!,
    },
  );
}();

/// The installed `bd`, as every diagnostic here names it.
final String _bdVersion = _installedBd?.version ?? 'bd unavailable on PATH';

/// The `skip` reason when the installed `bd` cannot run this fixture, or null.
///
/// Both reasons are the shared probe's, and both are PRINTED: no binary at all
/// (CI), or a binary whose `init` is missing a flag the isolated store is
/// built from — a version skew that silently fell back to a shared server is
/// how a fixture store bound to someone else's Dolt in the first place.
final String? skipWithoutBd = proxied_bd.isolatedBdFixtureSkipReason(
  bdVersion: _installedBd?.version,
  initFlags: _installedBd?.initFlags ?? const {},
);

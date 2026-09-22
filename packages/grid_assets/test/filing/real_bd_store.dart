import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'filing_evidence_fakes.dart';

/// The REAL `bd` harness the filing suites drive the verb against.
///
/// These tests run the actual binary end to end; a fake would not prove the
/// filing contract holds against bd's own argv, record shape and exit codes —
/// and the dependency projection exists BECAUSE two of bd's surfaces disagree
/// about `external:` rows. The helpers live here rather than in one suite so
/// the second suite composes them instead of restating them.

/// The proxied server pair ONE fixture store is bound to.
///
/// A proxied store is not self-contained: `bd` talks to a `db-proxy-child`,
/// which supervises a `dolt sql-server` holding the data directory. Both
/// outlive the `bd` command that started them, and a store that binds to a
/// server it did not start answers out of a DIFFERENT (or deleted) data
/// directory — measured as `bd create` refusing with `issue_prefix config is
/// missing` against a server abandoned six days earlier. This record is what
/// makes that binding checkable, reapable, and reportable.
final class BdStoreIdentity {
  /// The identity of the server pair rooted at [rootPath].
  const BdStoreIdentity({
    required this.bdVersion,
    required this.storePath,
    required this.configPath,
    required this.rootPath,
    required this.proxyPid,
    required this.proxyPort,
    required this.doltPid,
    required this.doltPort,
  });

  /// The installed `bd` that initialized the store, as it reports itself.
  final String bdVersion;

  /// The store's own directory, canonicalized.
  ///
  /// Canonical because the process census matches on it and a macOS temp
  /// directory is reached through a symlink; canonical AND retained because
  /// resolution stops working the moment the directory is deleted, which is
  /// exactly when a leaked server most needs naming.
  final String storePath;

  /// The Dolt YAML the server pair was started from, canonicalized.
  final String configPath;

  /// The proxy's root — lockfiles, PID files, and the child `.dolt` repository
  /// — canonicalized.
  final String rootPath;

  /// The `db-proxy-child` process, and the loopback port it serves `bd` on.
  final int proxyPid;

  /// The loopback port the proxy serves `bd` on.
  final int proxyPort;

  /// The `dolt sql-server` process the proxy supervises.
  final int doltPid;

  /// The port the Dolt server listens on — RESERVED by the fixture, so a store
  /// bound to some other server is a mismatch this record can catch.
  final int doltPort;

  @override
  String toString() =>
      'bd_version=$bdVersion store_path=$storePath config_path=$configPath '
      'root_path=$rootPath proxy_pid=$proxyPid proxy_port=$proxyPort '
      'dolt_pid=$doltPid dolt_port=$doltPort';
}

/// Runs one `bd` invocation against [store] and fails the test on non-zero.
///
/// Every failure carries the bd version and the server identity the store is
/// bound to, so the NEXT mismatch names itself: an exit code alone cannot tell
/// a broken argv from a store answering out of a server it never started.
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
    reason:
        'bd ${args.join(' ')}\n${result.stdout}\n${result.stderr}\n'
        '${_boundServer(store)}',
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
///
/// The server pair is the fixture's OWN: the Dolt listener runs on a port this
/// reserves, from a config this writes, under a root this names, and the live
/// processes are then checked to be serving exactly those paths before the
/// store is handed back. That is what a store cannot do by accepting whatever
/// server bd finds — and binding to a stale one is how six filing tests came
/// to fail against a server whose store had been deleted days earlier.
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
  final doltPort = await _reserveLoopbackPort();
  File(configPath).writeAsStringSync(_doltServerConfig(doltPort));

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
  ]);

  final identity = await _verifiedIdentity(
    storePath: storePath,
    rootPath: rootPath,
    configPath: configPath,
    reservedDoltPort: doltPort,
  );
  for (final key in _identityKeys(store)) {
    _identities[key] = identity;
  }
  return store;
}

/// The server pair [store] was bound to when [bdStore] initialized it.
///
/// Retained past the store's deletion on purpose: a leaked server is only
/// diagnosable — and only reapable — while something still remembers which
/// PIDs and ports belonged to the directory that is now gone.
BdStoreIdentity bdStoreIdentity(Directory store) {
  final identity = _identityOrNull(store);
  if (identity != null) return identity;
  throw StateError('no bd store was initialized at ${store.path}');
}

/// Every store process still running out of [store]'s directory.
Future<List<({int pid, String command})>> bdStoreProcesses(
  Directory store,
) async => _storeProcessesIn(await _processTable(), _censusPath(store));

/// Stops [store]'s server pair, AWAITS its exit, and only then deletes it.
///
/// Order is the whole point. The proxy and its `dolt sql-server` hold the data
/// directory the delete removes; a delete that races them leaves a server
/// running over a path that no longer exists, and the next fixture store on
/// this host can bind to it and fail with a refusal that names neither. So
/// this signals every PID it can account for, polls until all of them are gone
/// AND nothing new is serving the store path, deletes, and then censuses once
/// more — a client that arrives during the delete re-creates the store.
///
/// LOUD on a survivor, because the alternative is the six-day-old orphan this
/// fixture was measured leaking. Idempotent, so the registered teardown may
/// follow a manual call.
Future<void> tearDownBdStore(Directory store) async {
  final identity = _identityOrNull(store);
  final storePath = _censusPath(store);
  final rootPath = identity?.rootPath ?? p.join(storePath, '.beads', 'dolt');

  // Seeded from BOTH accounts because neither is complete alone: bd records a
  // PID the moment it forks, before the child has exec'd into a command the
  // path census can recognise, and the census is the only account of the
  // successor bd spawns to serve the very command that stopped the last one.
  final recorded = <int>{
    if (identity != null) ...[identity.proxyPid, identity.doltPid],
    for (final name in _proxyPidNames)
      if (_pidArtifact(p.join(rootPath, name)) case final artifact?)
        artifact.pid,
  };

  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final table = await _processTable();
    final census = _storeProcessesIn(table, storePath);
    final survivors = <int>{
      ...recorded.where(table.containsKey),
      for (final row in census) row.pid,
    };
    if (survivors.isEmpty) break;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'the fixture bd store did not stop within 10s '
        '(${identity ?? 'store_path=$storePath, never initialized here'}); '
        'survivors: '
        '${[for (final pid in survivors) '$pid ${table[pid]}'].join('; ')}',
      );
    }
    for (final pid in survivors) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  if (store.existsSync()) store.deleteSync(recursive: true);

  final arrivals = _storeProcessesIn(await _processTable(), storePath);
  if (arrivals.isEmpty) return;
  throw StateError(
    'a bd store process arrived under $storePath after it was deleted '
    '(${identity ?? 'never initialized here'}): '
    '${[for (final row in arrivals) '${row.pid} ${row.command}'].join('; ')}',
  );
}

/// `bd dolt stop` is NOT the instrument any of this uses. It is a MODE CHANGE —
/// it migrates the workspace back to embedded storage, which a CGO-free binary
/// cannot even open — and it re-spawns a proxy to serve its own command, so the
/// process it leaves behind is never the one it reported stopping.
const _proxyPidNames = ['proxy.pid', 'proxy-child.pid'];

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

/// A loopback port the OS has just confirmed free.
///
/// Bound and released rather than guessed: bd starts the Dolt server itself,
/// so the only thing the fixture can do is hand it a port nothing else holds.
Future<int> _reserveLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Every identity [bdStore] has minted, under every key a caller can ask with.
final Map<String, BdStoreIdentity> _identities = {};

/// The keys [store] may be looked up under: the path the caller holds, and the
/// canonical path the census matches on.
///
/// They differ under any symlinked root — every macOS temp directory — and the
/// canonical one stops resolving once the directory is deleted, so both are
/// recorded and both are tried.
List<String> _identityKeys(Directory store) =>
    {p.absolute(store.path), _canonicalPath(store)}.toList(growable: false);

BdStoreIdentity? _identityOrNull(Directory store) {
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

/// Reads bd's proxy artifacts and refuses unless they, and the live processes
/// they name, all describe the store this fixture just built.
///
/// bd 1.1.0 publishes no client-info record, so the live `db-proxy-child` and
/// `dolt sql-server` argv ARE the account of what a store is bound to. Each
/// check is separately loud: a store that quietly answers out of the wrong
/// server is the defect, and a verification that only reports "something is
/// wrong" would have cost the same round the silent binding did.
Future<BdStoreIdentity> _verifiedIdentity({
  required String storePath,
  required String rootPath,
  required String configPath,
  required int reservedDoltPort,
}) async {
  final proxyPath = p.join(rootPath, 'proxy.pid');
  final doltPath = p.join(rootPath, 'proxy-child.pid');
  final proxy = _pidArtifact(proxyPath);
  final dolt = _pidArtifact(doltPath);
  final table = await _processTable();

  Never refuse(String what) => throw StateError(
    'the fixture bd store at $storePath did not bind the server it started: '
    '$what; bd_version=$_bdVersion config_path=$configPath '
    'root_path=$rootPath reserved_dolt_port=$reservedDoltPort; '
    'proxy.pid=${_artifactText(proxyPath)} '
    'proxy-child.pid=${_artifactText(doltPath)}; '
    'store processes '
    '${[for (final row in _storeProcessesIn(table, storePath)) '${row.pid} ${row.command}'].join('; ')}',
  );

  if (proxy == null) refuse('$proxyPath is absent');
  if (dolt == null) refuse('$doltPath is absent');
  if (proxy.port == null) refuse('$proxyPath records no port');
  if (dolt.port == null) refuse('$doltPath records no port');
  if (dolt.port != reservedDoltPort) {
    refuse(
      'the Dolt server answers on ${dolt.port}, not the reserved '
      '$reservedDoltPort',
    );
  }

  final proxyCommand = table[proxy.pid];
  if (proxyCommand == null) refuse('proxy ${proxy.pid} is not running');
  if (!proxyCommand.contains('db-proxy-child')) {
    refuse('${proxy.pid} is not a db-proxy-child: $proxyCommand');
  }
  if (_argument(proxyCommand, 'root') != rootPath) {
    refuse('proxy ${proxy.pid} serves another root: $proxyCommand');
  }
  if (_argument(proxyCommand, 'config') != configPath) {
    refuse('proxy ${proxy.pid} serves another config: $proxyCommand');
  }
  if (_argument(proxyCommand, 'port') != '${proxy.port}') {
    refuse('proxy ${proxy.pid} serves another port: $proxyCommand');
  }

  final doltCommand = table[dolt.pid];
  if (doltCommand == null) refuse('Dolt server ${dolt.pid} is not running');
  if (!doltCommand.contains('dolt sql-server')) {
    refuse('${dolt.pid} is not a dolt sql-server: $doltCommand');
  }
  if (_argument(doltCommand, 'config') != configPath) {
    refuse('Dolt server ${dolt.pid} serves another config: $doltCommand');
  }

  return BdStoreIdentity(
    bdVersion: _bdVersion,
    storePath: storePath,
    configPath: configPath,
    rootPath: rootPath,
    proxyPid: proxy.pid,
    proxyPort: proxy.port!,
    doltPid: dolt.pid,
    doltPort: dolt.port!,
  );
}

/// The `{pid, port}` a bd proxy artifact records, or null when it is absent —
/// a store that is already down.
///
/// bd has written a PID both ways, bare decimal and a JSON object carrying a
/// `pid`, so both are read. Anything else PRESENT is refused by name: a PID
/// file this cannot read names a process the exit fence cannot wait out, and a
/// teardown that assumes there is nothing to wait for is how this fixture left
/// a live Dolt server over a deleted temp store in the first place.
({int pid, int? port})? _pidArtifact(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final contents = file.readAsStringSync().trim();
  Never unreadable() =>
      throw StateError('unreadable bd pid artifact $path: $contents');
  if (int.tryParse(contents) case final bare?) {
    if (bare <= 0) unreadable();
    return (pid: bare, port: null);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(contents);
  } on FormatException {
    unreadable();
  }
  if (decoded is! Map) unreadable();
  final pid = decoded['pid'];
  final port = decoded['port'];
  if (pid is! int || pid <= 0) unreadable();
  return (pid: pid, port: port is int && port > 0 ? port : null);
}

/// [path]'s contents as a failure can carry them.
String _artifactText(String path) {
  final file = File(path);
  if (!file.existsSync()) return '<absent>';
  return file.readAsStringSync().trim();
}

/// Every live process by PID, as `ps` reports it.
///
/// LOUD when `ps` fails: this census is the only account of a server that
/// outlived its store, and a silently empty answer is indistinguishable from a
/// clean teardown — which is exactly the report that let an abandoned Dolt
/// server sit on this host for six days.
Future<Map<int, String>> _processTable() async {
  final result = await Process.run('ps', ['-axo', 'pid=,command=']);
  if (result.exitCode != 0) {
    throw StateError(
      'ps census failed (${result.exitCode}): ${result.stdout}${result.stderr}',
    );
  }
  final row = RegExp(r'^\s*(\d+)\s+(.*)$');
  return {
    for (final line in (result.stdout as String).split('\n'))
      if (row.firstMatch(line) case final match?)
        int.parse(match.group(1)!): match.group(2)!,
  };
}

/// The rows of [table] that are store processes running out of [storePath].
///
/// Matched on the process's own `--config` / `--root` arguments rather than on
/// bd's PID files alone: bd re-spawns a proxy to serve the very command that
/// stops the previous one, so a PID captured from `.beads/dolt/proxy.pid` names
/// a process that is already gone while its successor is missed entirely.
List<({int pid, String command})> _storeProcessesIn(
  Map<int, String> table,
  String storePath,
) {
  final storePrefix = '$storePath${Platform.pathSeparator}';
  return [
    for (final entry in table.entries)
      if (_namesStorePath(entry.value, storePrefix))
        (pid: entry.key, command: entry.value),
  ];
}

/// A store process configured under [storePrefix].
///
/// The raw argument is compared FIRST because the fixture hands bd canonical
/// paths, so a live server names them literally; resolution is the fallback for
/// a path some other writer spelled through a symlink, and it is only available
/// while the path still exists.
bool _namesStorePath(String command, String storePrefix) {
  if (!command.contains('dolt sql-server') &&
      !command.contains('db-proxy-child')) {
    return false;
  }
  for (final match in _pathArgument.allMatches(command)) {
    final raw = match.group(1) ?? match.group(2) ?? match.group(3)!;
    if (raw.startsWith(storePrefix)) return true;
    final entry = File(raw);
    final resolved = entry.existsSync()
        ? entry.resolveSymbolicLinksSync()
        : p.absolute(raw);
    if (resolved.startsWith(storePrefix)) return true;
  }
  return false;
}

final RegExp _pathArgument = RegExp(
  r'''(?:^|\s)--(?:config|root)(?:=|\s+)(?:"([^"]+)"|'([^']+)'|(\S+))''',
);

/// The value `--`[name] carries in [command], however it was quoted.
String? _argument(String command, String name) {
  final match = RegExp(
    '''(?:^|\\s)--$name(?:=|\\s+)(?:"([^"]+)"|'([^']+)'|(\\S+))''',
  ).firstMatch(command);
  if (match == null) return null;
  return match.group(1) ?? match.group(2) ?? match.group(3);
}

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

/// The `bd init` flags the isolated fixture store cannot be built without.
///
/// Named individually so an installed binary that lacks one says WHICH, rather
/// than skipping the whole suite behind "requires bd".
const _requiredInitFlags = [
  '--proxied-server',
  '--proxied-server-config-path',
  '--proxied-server-root-path',
];

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
/// Two reasons, both PRINTED: no binary at all (CI), or a binary whose `init`
/// is missing a flag the isolated store is built from. The second is the one
/// worth naming — a version skew that silently fell back to a shared server is
/// how a fixture store bound to someone else's Dolt in the first place.
final String? skipWithoutBd = () {
  final bd = _installedBd;
  if (bd == null) return 'requires a real bd binary on PATH (absent in CI)';
  final missing = [
    for (final flag in _requiredInitFlags)
      if (!bd.initFlags.contains(flag)) flag,
  ];
  if (missing.isEmpty) return null;
  return 'installed ${bd.version} cannot initialize an isolated proxied store: '
      'bd init is missing ${missing.join(', ')}';
}();

// The ONE proxied-`bd` lifecycle harness this workspace has.
//
// A proxied store is not self-contained: `bd` talks to a `db-proxy-child`,
// which supervises a `dolt sql-server` holding the data directory. Both
// outlive the `bd` command that started them, and a store that binds to a
// server it did not start answers out of a DIFFERENT (or deleted) data
// directory — measured as `bd create` refusing with `issue_prefix config is
// missing` against a server abandoned six days earlier, and separately as a
// `/tmp` workspace re-created under a teardown that reported success.
//
// Two suites in two packages met that hazard and each grew its own census,
// stop fence and PID parser. Two harnesses for one mechanism drift, and the
// drift is invisible until the leak reaches a station host — so this library
// is the single home, `grid_assets` is where it lives, and
// `github_grid_assets` reaches it by relative path (another package's `test/`
// tree carries no `package:` URI). The identity scheme is the one that was
// VERIFIED against live argv; the bare-PID scheme it replaced could not tell
// a store's own server from someone else's.
//
// Test-only. Nothing in `lib/` imports this, and it names no production
// symbol.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The proxied server pair ONE fixture store is bound to.
///
/// This record is what makes that binding checkable, reapable, and
/// reportable: it is minted only after the live processes have been read back
/// and matched against the paths and ports the fixture chose.
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

  /// The `db-proxy-child` process.
  final int proxyPid;

  /// The loopback port the proxy serves `bd` on — RESERVED by the fixture.
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

/// The two loopback ports ONE fixture store's server pair listens on.
///
/// Reserved by the fixture rather than assigned by `bd`, which is what makes
/// "am I talking to the server I started?" a checkable question at all.
typedef ProxiedBdPorts = ({int proxyPort, int doltPort});

/// One account of everything a harness can still find working under a
/// workspace: the STORE processes named by their own `--config`/`--root`, and
/// the PIDs whose working directory is inside it.
///
/// Two arms because neither alone is complete — a Dolt server names its data
/// dir and carries no useful cwd, a detached `bd` child names nothing and
/// carries only a cwd — and because a teardown that reports residue owes the
/// reader which kind it found.
typedef WorkspaceProcessCensus = ({
  List<({int pid, String command})> stores,
  List<int> residents,
});

/// The `bd init` flags an isolated fixture store cannot be built without.
///
/// Named individually so an installed binary that lacks one says WHICH, rather
/// than skipping a whole suite behind "requires bd". `--proxied-server-port`
/// is in the list because a store that lets `bd` pick the proxy's port cannot
/// prove afterwards that the proxy answering it is its own.
const requiredIsolatedBdInitFlags = [
  '--proxied-server',
  '--proxied-server-config-path',
  '--proxied-server-root-path',
  '--proxied-server-port',
];

/// The `skip` reason when the installed `bd` cannot run an isolated fixture
/// store, or null when it can.
///
/// Two reasons, both PRINTED: no binary at all ([bdVersion] null, the CI
/// case), or a binary whose `init` is missing a flag the isolated store is
/// built from. The second is the one worth naming — a version skew that
/// silently fell back to a shared server is how a fixture store bound to
/// someone else's Dolt in the first place.
///
/// Pure: [bdVersion] and [initFlags] are what a caller probed, so both
/// outcomes are provable without a binary to probe.
String? isolatedBdFixtureSkipReason({
  required String? bdVersion,
  required Set<String> initFlags,
}) {
  if (bdVersion == null) {
    return 'requires a real bd binary on PATH (absent in CI)';
  }
  final missing = [
    for (final flag in requiredIsolatedBdInitFlags)
      if (!initFlags.contains(flag)) flag,
  ];
  if (missing.isEmpty) return null;
  return 'installed $bdVersion cannot initialize an isolated proxied store: '
      'bd init is missing ${missing.join(', ')}';
}

/// Two loopback ports the OS has just confirmed free, and distinct.
///
/// Bound and released rather than guessed: `bd` starts both servers itself, so
/// the only thing a fixture can do is hand it ports nothing else holds. Both
/// sockets are held at the SAME time before either is released, which is what
/// makes the two ports different — the OS cannot hand out a port it is already
/// lending.
Future<ProxiedBdPorts> reserveProxiedBdPorts() async {
  final sockets = await Future.wait([
    ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  ]);
  final ports = (proxyPort: sockets[0].port, doltPort: sockets[1].port);
  await Future.wait([for (final socket in sockets) socket.close()]);
  if (ports.proxyPort == ports.doltPort) {
    throw StateError(
      'the loopback reservation handed the proxy and the Dolt server the same '
      'port (${ports.proxyPort}); they are held concurrently so they cannot '
      'collide, and a store built on one port cannot verify either server',
    );
  }
  return ports;
}

/// Reads `bd`'s proxy artifacts and refuses unless they, and the live
/// processes they name, all describe the store the caller just built.
///
/// bd 1.1.0 publishes no client-info record, so the live `db-proxy-child` and
/// `dolt sql-server` argv ARE the account of what a store is bound to. Each
/// check is separately loud: a store that quietly answers out of the wrong
/// server is the defect, and a verification that only reports "something is
/// wrong" would have cost the same round the silent binding did.
Future<BdStoreIdentity> verifyBdStoreIdentity({
  required String bdVersion,
  required String storePath,
  required String configPath,
  required String rootPath,
  required ProxiedBdPorts reserved,
}) async {
  final proxyPath = p.join(rootPath, 'proxy.pid');
  final doltPath = p.join(rootPath, 'proxy-child.pid');
  final proxy = proxiedBdPidArtifact(proxyPath);
  final dolt = proxiedBdPidArtifact(doltPath);
  final table = await processTable();

  Never refuse(String what) => throw StateError(
    'the fixture bd store at $storePath did not bind the server it started: '
    '$what; bd_version=$bdVersion config_path=$configPath '
    'root_path=$rootPath reserved_proxy_port=${reserved.proxyPort} '
    'reserved_dolt_port=${reserved.doltPort}; '
    'proxy.pid=${_artifactText(proxyPath)} '
    'proxy-child.pid=${_artifactText(doltPath)}; '
    'store processes '
    '${[for (final row in storeProcessesIn(table, storePath)) '${row.pid} ${row.command}'].join('; ')}',
  );

  if (proxy == null) refuse('$proxyPath is absent');
  if (dolt == null) refuse('$doltPath is absent');
  if (proxy.port == null) refuse('$proxyPath records no port');
  if (dolt.port == null) refuse('$doltPath records no port');
  if (proxy.port != reserved.proxyPort) {
    refuse(
      'the proxy answers on ${proxy.port}, not the reserved '
      '${reserved.proxyPort}',
    );
  }
  if (dolt.port != reserved.doltPort) {
    refuse(
      'the Dolt server answers on ${dolt.port}, not the reserved '
      '${reserved.doltPort}',
    );
  }

  final proxyCommand = table[proxy.pid];
  if (proxyCommand == null) refuse('proxy ${proxy.pid} is not running');
  if (!proxyCommand.contains('db-proxy-child')) {
    refuse('${proxy.pid} is not a db-proxy-child: $proxyCommand');
  }
  if (commandArgument(proxyCommand, 'root') != rootPath) {
    refuse('proxy ${proxy.pid} serves another root: $proxyCommand');
  }
  if (commandArgument(proxyCommand, 'config') != configPath) {
    refuse('proxy ${proxy.pid} serves another config: $proxyCommand');
  }
  if (commandArgument(proxyCommand, 'port') != '${reserved.proxyPort}') {
    refuse('proxy ${proxy.pid} serves another port: $proxyCommand');
  }

  final doltCommand = table[dolt.pid];
  if (doltCommand == null) refuse('Dolt server ${dolt.pid} is not running');
  if (!doltCommand.contains('dolt sql-server')) {
    refuse('${dolt.pid} is not a dolt sql-server: $doltCommand');
  }
  if (commandArgument(doltCommand, 'config') != configPath) {
    refuse('Dolt server ${dolt.pid} serves another config: $doltCommand');
  }

  return BdStoreIdentity(
    bdVersion: bdVersion,
    storePath: storePath,
    configPath: configPath,
    rootPath: rootPath,
    proxyPid: proxy.pid,
    proxyPort: proxy.port!,
    doltPid: dolt.pid,
    doltPort: dolt.port!,
  );
}

/// The PID files `bd`'s proxy pair writes while it is serving a store.
///
/// `proxy.pid` names the `db-proxy-child`; `proxy-child.pid` names the `dolt
/// sql-server` that child supervises — the process that holds the data dir a
/// delete is about to remove.
const _proxyPidNames = ['proxy.pid', 'proxy-child.pid'];

/// The flock files `bd`'s proxy pair holds open while it is serving a store.
const _proxyLockNames = ['proxy.lock', 'proxy-child.lock'];

/// The store PIDs `bd`'s own artifacts name under [pidRootPath].
///
/// The process census keys on a `--config`/`--root` argument, which a child
/// only carries once it has exec'd; `bd` records both PIDs the moment it forks.
/// These files are therefore the only account of a Dolt server that is already
/// running but not yet recognisable, and they are read BEFORE a fence signals
/// anything, because the first SIGKILL is what takes them away.
///
/// An absent file is a store that is already down, which [readPidFile] reports
/// as null. Anything else PRESENT is refused by name: a PID file this cannot
/// read names a process an exit fence cannot wait out, and a teardown that
/// assumes there is nothing to wait for is how both harnesses leaked a live
/// Dolt server in the first place.
Set<int> proxiedStateStorePids({
  required String pidRootPath,
  String? Function(String path) readPidFile = readPidFileIfPresent,
}) {
  final pids = <int>{};
  for (final name in _proxyPidNames) {
    final path = p.join(pidRootPath, name);
    final contents = readPidFile(path);
    if (contents == null) continue;
    pids.add(_parsePidArtifact(path, contents).pid);
  }
  return pids;
}

/// The `{pid, port}` a `bd` proxy artifact at [path] records, or null when it
/// is absent — a store that is already down.
({int pid, int? port})? proxiedBdPidArtifact(String path) {
  final contents = readPidFileIfPresent(path);
  if (contents == null) return null;
  return _parsePidArtifact(path, contents);
}

/// The ONE parser both the identity check and the exit fence read a PID
/// artifact through.
///
/// `bd` has written a PID both ways — bare decimal, and a JSON object carrying
/// a `pid` (and, for the proxy, the `port` it listens on) — so both are read.
/// Anything else is refused by name rather than treated as an empty store.
({int pid, int? port}) _parsePidArtifact(String path, String contents) {
  final trimmed = contents.trim();
  Never unreadable() =>
      throw StateError('unreadable proxy pid file $path: $trimmed');
  if (int.tryParse(trimmed) case final bare?) {
    if (bare <= 0) unreadable();
    return (pid: bare, port: null);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    unreadable();
  }
  if (decoded is! Map) unreadable();
  final pid = decoded['pid'];
  final port = decoded['port'];
  if (pid is! int || pid <= 0) unreadable();
  return (pid: pid, port: port is int && port > 0 ? port : null);
}

/// Reads a PID file that may not be there.
///
/// Null means ABSENT — never written, or removed by the proxy between the
/// check and the read. Every other [FileSystemException] is a filesystem this
/// teardown does not understand, and it travels rather than reading as an
/// empty process table.
String? readPidFileIfPresent(String path) {
  try {
    return File(path).readAsStringSync();
  } on PathNotFoundException {
    return null;
  }
}

/// [path]'s contents as a failure can carry them.
String _artifactText(String path) =>
    readPidFileIfPresent(path)?.trim() ?? '<absent>';

/// Every live process by PID, as `ps` reports it.
///
/// LOUD when `ps` fails: this census is the only account of a server that
/// outlived its store, and a silently empty answer is indistinguishable from a
/// clean teardown — which is exactly the report that let an abandoned Dolt
/// server sit on a station host for six days.
Future<Map<int, String>> processTable() async {
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

/// Every STORE process still running out of [workspacePath], live.
///
/// Matched on the process's own `--config` / `--root` arguments rather than on
/// `bd`'s PID files ALONE: `bd` re-spawns a proxy to serve the very command
/// that stops the previous one, so a PID captured from
/// `.beads/dolt/proxy.pid` names a process that is already gone while its
/// successor is missed entirely. The process table is the only account that
/// cannot go stale — but it is also the one a freshly forked child is not yet
/// in, which is what [proxiedStateStorePids] seeds alongside it.
Future<List<({int pid, String command})>> workspaceStoreProcesses(
  String workspacePath,
) async => storeProcessesIn(await processTable(), workspacePath);

/// The rows of [table] that are store processes running out of
/// [workspacePath].
List<({int pid, String command})> storeProcessesIn(
  Map<int, String> table,
  String workspacePath,
) {
  final prefixes = _workspacePrefixes(workspacePath);
  return [
    for (final entry in table.entries)
      if (_namesWorkspace(entry.value, prefixes))
        (pid: entry.key, command: entry.value),
  ];
}

/// The path prefixes a store process may name [workspacePath] by.
///
/// BOTH spellings, because a census is taken on both sides of a delete: the
/// absolute path as the caller holds it, and its canonical resolution while
/// the directory still exists. A macOS temp directory is reached through a
/// symlink, so a server started from one spelling is invisible to the other —
/// and the canonical spelling stops resolving the moment the directory is
/// deleted, which is exactly when a leaked server most needs finding.
Set<String> _workspacePrefixes(String workspacePath) {
  final absolute = p.absolute(workspacePath);
  final directory = Directory(absolute);
  final canonical = directory.existsSync()
      ? directory.resolveSymbolicLinksSync()
      : absolute;
  return {
    '$absolute${Platform.pathSeparator}',
    '$canonical${Platform.pathSeparator}',
  };
}

/// A store process configured under one of [prefixes].
///
/// The raw argument is compared FIRST because a fixture hands `bd` canonical
/// paths, so a live server names them literally; resolution is the fallback
/// for a path some other writer spelled through a symlink, and it is only
/// available while the path still exists.
bool _namesWorkspace(String command, Set<String> prefixes) {
  if (!command.contains('dolt sql-server') &&
      !command.contains('db-proxy-child')) {
    return false;
  }
  for (final match in _pathArgument.allMatches(command)) {
    final raw = match.group(1) ?? match.group(2) ?? match.group(3)!;
    if (prefixes.any(raw.startsWith)) return true;
    final entry = File(raw);
    final resolved = entry.existsSync()
        ? entry.resolveSymbolicLinksSync()
        : p.absolute(raw);
    if (prefixes.any(resolved.startsWith)) return true;
  }
  return false;
}

final RegExp _pathArgument = RegExp(
  r'''(?:^|\s)--(?:config|root)(?:=|\s+)(?:"([^"]+)"|'([^']+)'|(\S+))''',
);

/// The value `--`[name] carries in [command], however it was quoted.
String? commandArgument(String command, String name) {
  final match = RegExp(
    '''(?:^|\\s)--$name(?:=|\\s+)(?:"([^"]+)"|'([^']+)'|(\\S+))''',
  ).firstMatch(command);
  if (match == null) return null;
  return match.group(1) ?? match.group(2) ?? match.group(3);
}

/// Every process still WORKING somewhere under [workspacePath], by current
/// directory.
///
/// `bd` forks detached children that outlive the command that spawned them —
/// `bd send-metrics` is the one measured here, born after a test body finished
/// and alive for ~25 seconds afterwards. They carry no `--config` or `--root`,
/// so [workspaceStoreProcesses] cannot see them, and they inherit the
/// workspace as their working directory, which is the only mark they leave in
/// the process table.
///
/// They are why a SIGKILL fence can run its full bound and still find a proxy:
/// a live `bd` client re-spawns one to serve itself every time the fence kills
/// the last. Killing them is also what stops a straggler from writing the
/// store back into existence AFTER a delete that already reported success.
///
/// `lsof` is the only account of a working directory on this platform. If it
/// is absent or refuses, this degrades to the store census alone — the
/// behaviour that shipped before — and a bounded delete absorbs the
/// difference. [runProcess] and [selfPid] are injected so both that
/// degradation and the parse are provable without a store to point them at.
Future<List<int>> workspaceResidents(
  String workspacePath, {
  required int selfPid,
  required Future<ProcessResult> Function(String, List<String>) runProcess,
}) async {
  final ProcessResult result;
  try {
    result = await runProcess('lsof', [
      '-w',
      '-a',
      '-d',
      'cwd',
      '-Fp',
      '+D',
      workspacePath,
    ]);
  } on ProcessException {
    return const [];
  }
  return parseLsofPids(result.stdout as String, selfPid: selfPid);
}

/// The PIDs lsof's `-F` output names, minus [selfPid].
///
/// `-F` is a record format, not a table: one tagged field per line, and only a
/// `p` record carries a PID. Every other row — a header, a `+D` warning, a
/// permission complaint — names no process and is dropped rather than guessed
/// at.
List<int> parseLsofPids(String output, {required int selfPid}) => [
  for (final line in output.split('\n'))
    if (line.startsWith('p'))
      // `selfPid` is this process: never in the kill set, whatever lsof says.
      if (int.tryParse(line.substring(1)) case final resident?)
        if (resident != selfPid) resident,
];

/// [WorkspaceProcessCensus] against the live process table.
///
/// The ONE census both a kill fence and a pre-delete gate read, so the set a
/// teardown signals is exactly the set it then refuses to delete around.
Future<WorkspaceProcessCensus> workspaceProcessCensus(
  String workspacePath,
) async => (
  stores: await workspaceStoreProcesses(workspacePath),
  residents: await workspaceResidents(
    workspacePath,
    selfPid: pid,
    runProcess: Process.run,
  ),
);

/// Every PID [census] names, from either arm.
Set<int> censusPids(WorkspaceProcessCensus census) => {
  for (final store in census.stores) store.pid,
  ...census.residents,
};

/// [census] as a single line a failure can carry.
String describeWorkspaceProcessCensus(WorkspaceProcessCensus census) =>
    'store processes '
    '[${[for (final s in census.stores) '${s.pid} ${s.command}'].join('; ')}], '
    'workspace residents [${census.residents.join(', ')}]';

/// Refuses unless [census] is empty on BOTH arms, naming [phase] when it is
/// not.
///
/// A delete is bounded by a WINDOW, and a window only proves a tree stays gone
/// while nothing is working under it. So the same census is read on either
/// side of it — before the delete, where residue is a writer the stop fence
/// did not reach, and after it, where residue is a client that arrived while
/// the window was running and can re-create the store the moment the test
/// stops looking. Either one is the leak both fixtures are measured by, and
/// the only useful report of one names the process: a teardown that deletes
/// around a live writer is how a Dolt server was abandoned in `/tmp` in the
/// first place.
void expectEmptyWorkspaceProcessCensus(
  WorkspaceProcessCensus census, {
  required String workspacePath,
  required String phase,
}) {
  if (census.stores.isEmpty && census.residents.isEmpty) return;
  throw StateError(
    'the workspace $workspacePath was still held $phase: '
    '${describeWorkspaceProcessCensus(census)}',
  );
}

/// Stops the proxied store serving [workspacePath] and does not return until
/// it is GONE.
///
/// Order is the whole point. The proxy and its `dolt sql-server` hold the data
/// directory a delete removes; a delete that races them leaves a server
/// running over a path that no longer exists, and the next fixture store on
/// the host can bind to it and fail with a refusal that names neither.
///
/// The kill set is seeded from THREE accounts because none is complete alone:
/// [recordedPids] — what a verified identity already named — plus `bd`'s own
/// PID artifacts under [pidRootPath], which name a forked child a whole exec
/// before `ps` can recognise it, plus the live census, which is the only
/// account of the successor `bd` spawns to serve the very command that stopped
/// the last one. The census arm is wider than the store processes on purpose:
/// a store process killed while its client still runs simply comes back.
///
/// `bd dolt stop` is NOT the instrument. It is a MODE CHANGE — it migrates the
/// workspace back to embedded storage, which a CGO-free binary cannot even
/// open — and it re-spawns a proxy to serve its own command, so the process it
/// leaves behind is never the one it reported stopping.
///
/// LOUD on residue it cannot remove, via [waitForProxiedStateStoreExit].
/// Idempotent, so a registered teardown may follow a manual call.
Future<void> stopAndAwaitProxiedStateStore({
  required String workspacePath,
  required String pidRootPath,
  Set<int> recordedPids = const {},
}) async {
  final named = <int>{
    ...recordedPids,
    ...proxiedStateStorePids(pidRootPath: pidRootPath),
  };
  // bd's own record is signalled FIRST, before any census: a forked child is
  // in these files a whole exec before it is recognisable in `ps`.
  for (final target in named) {
    Process.killPid(target, ProcessSignal.sigkill);
  }
  await waitForProxiedStateStoreExit(
    survivingPids: () => _reapStoreResidue(workspacePath, named),
    heldLockPaths: () => _heldProxyLocks(pidRootPath),
    now: DateTime.now,
    delay: (duration) => Future<void>.delayed(duration),
  );
}

/// Every harness process under [workspacePath] still on the table — [named],
/// plus a fresh census — SIGKILLed again as it is named.
///
/// The poll kills because the poll is the only thing watching: `bd` re-spawns
/// a `db-proxy-child` to serve a command issued before the fence ran, and that
/// arrival holds the store open for its full 30-second idle timeout. A probe
/// that only looked would spin out its bound and fail a teardown one more
/// signal would have finished.
Future<Set<int>> _reapStoreResidue(String workspacePath, Set<int> named) async {
  final alive = <int>{
    ...await _livePids(named),
    ...censusPids(await workspaceProcessCensus(workspacePath)),
  };
  for (final target in alive) {
    Process.killPid(target, ProcessSignal.sigkill);
  }
  named.addAll(alive);
  return alive;
}

/// Which of [pids] the process table still knows about.
///
/// SIGKILL is a signal, not an event: the kernel accepts it long before the
/// process is off the table with its files closed. `ps` answers the question
/// the delete actually asks.
Future<Set<int>> _livePids(Set<int> pids) async {
  if (pids.isEmpty) return const {};
  final result = await Process.run('ps', ['-o', 'pid=', '-p', pids.join(',')]);
  return {
    for (final line in (result.stdout as String).split('\n'))
      if (int.tryParse(line.trim()) case final live?) live,
  };
}

/// The proxy locks under [pidRootPath] some process still holds.
///
/// A lock file that is absent, or present with no holder, belongs to a store
/// that is already down. A lock with a holder is a proxy that is still UP —
/// including one spawned after the census came back clean, which is the
/// arrival a delete used to race and the reason the PID census alone cannot
/// close this. Without lsof nothing can be distinguished, and the probe
/// reports nothing held rather than inventing residue.
Future<Set<String>> _heldProxyLocks(String pidRootPath) async {
  final held = <String>{};
  for (final name in _proxyLockNames) {
    final path = p.join(pidRootPath, name);
    if (!File(path).existsSync()) continue;
    final ProcessResult result;
    try {
      result = await Process.run('lsof', ['-w', '-t', path]);
    } on ProcessException {
      return const {};
    }
    final holders = [
      for (final line in (result.stdout as String).split('\n'))
        if (int.tryParse(line.trim()) case final holder?)
          if (holder != pid) holder,
    ];
    if (holders.isNotEmpty) held.add(path);
  }
  return held;
}

/// Polls [survivingPids] and [heldLockPaths] until both come back empty.
///
/// Returns only for a store that is wholly gone. Otherwise it throws a
/// [StateError] naming the residue it timed out on — surviving PIDs, held lock
/// paths, both sorted — because residue nothing can remove is a live Dolt
/// server writing into a directory a test is about to delete, and the only
/// useful report of that is the one that names it. [now] and [delay] are
/// injected so the bound can be proved without spending it.
Future<void> waitForProxiedStateStoreExit({
  required Future<Set<int>> Function() survivingPids,
  required Future<Set<String>> Function() heldLockPaths,
  required DateTime Function() now,
  required Future<void> Function(Duration) delay,
  Duration bound = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = now().add(bound);
  while (true) {
    final pids = (await survivingPids()).toList()..sort();
    final locks = (await heldLockPaths()).toList()..sort();
    if (pids.isEmpty && locks.isEmpty) return;
    if (!now().isBefore(deadline)) {
      throw StateError(
        'the proxied state store did not exit within '
        '${bound.inMilliseconds}ms: surviving pids [${pids.join(', ')}], '
        'held locks [${locks.join(', ')}]',
      );
    }
    await delay(pollInterval);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart' hide Station, Substation;
import 'package:grid_engine/testing.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Circuit _leafCircuit(Bead _) =>
    const Circuit(id: 'leaf', steps: [], terminalStepId: 'none');

final class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

final class _Tokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() async => 'token';
}

final class _ReconcileTransport implements GitHubHttpTransport {
  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    final path = request.uri.path;
    if (path.endsWith('/issues')) {
      return const GitHubHttpResponse(statusCode: 304, body: '');
    }
    if (path.endsWith('/pulls')) {
      return GitHubHttpResponse(
        statusCode: 200,
        body: jsonEncode([
          {
            'node_id': 'pr',
            'number': 8,
            'body': 'A human digest.\n\nRefs: pow-test\n',
            'user': {'login': 'nico'},
            'created_at': '2026-08-23T00:00:00Z',
            'updated_at': '2026-08-23T00:00:00Z',
            'head': {'ref': 'grid/pow-test', 'sha': 'abc'},
          },
        ]),
      );
    }
    // The FULL resource, the only place `mergeable` lives.
    if (path.contains('/pulls/')) {
      return GitHubHttpResponse(
        statusCode: 200,
        body: jsonEncode({'mergeable': true}),
      );
    }
    return GitHubHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'check_runs': [
          {
            'node_id': 'check',
            'status': 'completed',
            'conclusion': 'failure',
            'completed_at': '2026-08-23T00:00:00Z',
            'name': 'build',
            'app': {'slug': 'actions'},
          },
        ],
      }),
    );
  }
}

final class _CursorStore implements GitHubCursorStore {
  GitHubReconcilerCursor cursor = const GitHubReconcilerCursor();

  @override
  Future<GitHubReconcilerCursor> load() async => cursor;

  @override
  Future<void> save(GitHubReconcilerCursor value) async => cursor = value;
}

/// The state store's session beads.
///
/// Only the skipped `self-mints` case below reaches this: `bd export` REFUSES
/// against a proxied-server store, so whoever un-skips that test owes this
/// helper a `bd list --json` read first.
Future<List<Bead>> _sessions(ProcessBdRunner stateBd) async {
  final result = await stateBd.run(const ['export', '--all']);
  if (!result.ok) {
    throw StateError('state export failed: ${result.stderr}');
  }
  final decoded = const LineSplitter()
      .convert(result.stdout)
      .where((line) => line.trim().isNotEmpty)
      .map(jsonDecode)
      .toList(growable: false);
  return decoded
      .map((row) => Bead.fromJson((row as Map).cast<String, Object?>()))
      .where((bead) => bead.issueType == GridIssueTypes.session)
      .toList(growable: false);
}

Future<List<Bead>> _waitForMint(
  ProcessBdRunner stateBd,
  _RecordingTransport transport,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    final sessions = await _sessions(stateBd);
    final keys = _workKeys(sessions);
    if (keys.where((key) => key == 'pow-test#r1').length == 1 &&
        keys.where((key) => key == 'pow-test').length == 1) {
      return sessions;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  final sessions = await _sessions(stateBd);
  throw StateError(
    'resident reconcile did not self-mint pow-test; '
    'work keys=${_workKeys(sessions)}; flares=${transport.flares}',
  );
}

Future<void> _runBd(String root, List<String> args) async {
  final result = await Process.run('bd', args, workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('bd ${args.join(' ')} failed: ${result.stderr}');
  }
}

/// The throwaway password for the read-only `beads_dart` SQL user this harness
/// provisions in its own temporary store. Test-local, never a credential.
const _testStorePassword = 'github-grid-assets-test';

/// Boots the grid STATE store as a bd PROXIED SERVER, the only shape that
/// yields a resolvable SQL endpoint.
///
/// `assembleStationWork` refuses a LIVE station (`dryRun: false`) whose state
/// workspace resolves no endpoint, and the single built-in resolver reads bd's
/// proxied-server artifacts: an embedded-mode store has nothing to hand it, so
/// a plain `bd init` here is a `StoreRefusal` raised before the tree ever
/// mounts. Only the state half needs this — the work store stays embedded
/// because nothing reads it over SQL.
///
/// `bd dolt start` is deliberately NOT in this sequence. It swaps the
/// workspace onto a SHARED server and deletes `.beads/dolt/proxy.pid` — the
/// exact artifact the resolver reads — and leaves a `dolt sql-server` that
/// outlives the temporary directory. The read-only user is provisioned
/// offline against the stopped data dir instead, and the closing `bd list`
/// re-spawns the proxy.
Future<void> _initializeStateStore(String stateRoot) async {
  await Directory(stateRoot).create(recursive: true);
  await _runBd(stateRoot, const [
    'init',
    '--non-interactive',
    '--quiet',
    '--skip-agents',
    '--skip-hooks',
    '--prefix',
    'grid_state',
    '--proxied-server',
  ]);
  // Release the data dir that `init` left a proxy holding, so the offline
  // `dolt sql` below can open it.
  await Process.run('bd', const ['dolt', 'stop'], workingDirectory: stateRoot);
  final user = await Process.run('dolt', [
    '--data-dir=$stateRoot/.beads/dolt',
    '--use-db=grid_state',
    'sql',
    '-q',
    "CREATE USER IF NOT EXISTS 'beads_dart'@'%' IDENTIFIED BY "
        "'$_testStorePassword'; GRANT SELECT ON *.* TO 'beads_dart'@'%';",
  ]);
  if (user.exitCode != 0) {
    throw StateError('dolt user provisioning failed: ${user.stderr}');
  }
  final secret = File('$stateRoot/.beads/dolt/beads_dart.secret')
    ..writeAsStringSync(_testStorePassword);
  final chmod = await Process.run('chmod', ['600', secret.path]);
  if (chmod.exitCode != 0) {
    throw StateError('secret chmod failed: ${chmod.stderr}');
  }
  // Re-spawns the proxy, writing the `proxy.pid` the resolver reads.
  await _runBd(stateRoot, const ['list', '--json']);
}

/// Every harness-owned STORE process still running out of [tempPath].
///
/// Matched on the process's own `--config` / `--root` arguments rather than on
/// bd's PID files ALONE: bd re-spawns a proxy to serve the very command that
/// stops the previous one, so a PID captured from `.beads/dolt/proxy.pid` names
/// a process that is already gone while its successor is missed entirely. The
/// process table is the only account that cannot go stale — but it is also the
/// one a freshly forked child is not yet in, which is what
/// [proxiedStateStorePids] seeds alongside it.
///
/// This is the census the fence is LOUD about, but it is not everything the
/// harness leaves running — see [_workspaceResidents] for the clients that
/// keep re-spawning what it kills.
Future<List<({int pid, String command})>> _harnessStoreProcesses(
  String tempPath,
) async {
  final result = await Process.run('ps', ['-axo', 'pid=,command=']);
  expect(result.exitCode, 0, reason: 'ps census failed: ${result.stderr}');

  final resolvedTemp = Directory(tempPath).resolveSymbolicLinksSync();
  final tempPrefix = '$resolvedTemp${Platform.pathSeparator}';
  final row = RegExp(r'^\s*(\d+)\s+(.*)$');
  final pathArgument = RegExp(
    r'''(?:^|\s)--(?:config|root)(?:=|\s+)(?:"([^"]+)"|'([^']+)'|(\S+))''',
  );

  return [
    for (final line in (result.stdout as String).split('\n'))
      if (row.firstMatch(line) case final match?)
        if (_namesTempPath(match.group(2)!, pathArgument, tempPrefix))
          (pid: int.parse(match.group(1)!), command: match.group(2)!),
  ];
}

/// Whether [command] is a store process configured under [tempPrefix].
bool _namesTempPath(String command, RegExp pathArgument, String tempPrefix) {
  if (!command.contains('dolt sql-server') &&
      !command.contains('db-proxy-child')) {
    return false;
  }
  for (final match in pathArgument.allMatches(command)) {
    final raw = match.group(1) ?? match.group(2) ?? match.group(3)!;
    final entry = File(raw);
    final resolved = entry.existsSync()
        ? entry.resolveSymbolicLinksSync()
        : entry.absolute.path;
    if (resolved.startsWith(tempPrefix)) return true;
  }
  return false;
}

/// Every process still WORKING somewhere under [tempPath], by current
/// directory.
///
/// bd forks detached children that outlive the command that spawned them —
/// `bd send-metrics` is the one measured here, born after the test body
/// finished and alive for ~25 seconds afterwards. They carry no `--config` or
/// `--root`, so [_harnessStoreProcesses] cannot see them, and they inherit the
/// workspace as their working directory, which is the only mark they leave in
/// the process table.
///
/// They are why the SIGKILL fence below can run its full bound and still find
/// a proxy: a live bd client re-spawns one to serve itself every time the
/// fence kills the last. Killing them is also what stops a straggler from
/// writing the store back into existence AFTER a delete that already reported
/// success — measured, before this census, as a populated `.beads/dolt/`
/// skeleton left in `/tmp` by runs that reported no failure at all.
///
/// `lsof` is the only account of a working directory on this platform. If it
/// is absent or refuses, this degrades to the store census alone — the
/// behaviour that shipped before — and the bounded delete below absorbs the
/// difference. [runProcess] and [selfPid] are injected so both that
/// degradation and the parse are provable without a store to point them at.
Future<List<int>> workspaceResidents(
  String tempPath, {
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
      tempPath,
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

/// [workspaceResidents] against the live process table.
Future<List<int>> _workspaceResidents(String tempPath) =>
    workspaceResidents(tempPath, selfPid: pid, runProcess: Process.run);

/// The PID files bd's proxy pair writes while it is serving a store.
///
/// `proxy.pid` names the `db-proxy-child`; `proxy-child.pid` names the `dolt
/// sql-server` that child supervises — the process that holds the data dir the
/// delete is about to remove.
const _proxyPidNames = ['proxy.pid', 'proxy-child.pid'];

/// The store PIDs bd's own artifacts name under [tempPath].
///
/// The process census keys on a `--config`/`--root` argument, which a child
/// only carries once it has exec'd; bd records both PIDs the moment it forks.
/// These files are therefore the only account of a Dolt server that is already
/// running but not yet recognisable, and they are read BEFORE the fence signals
/// anything, because the first SIGKILL is what takes them away.
///
/// bd has written a PID both ways — bare decimal, and a JSON object carrying a
/// `pid` — so both are read. An absent file is a store that is already down,
/// which [readPidFile] reports as null. Anything else PRESENT is refused by
/// name: a PID file this cannot read names a process the exit fence cannot
/// wait out, and a teardown that assumes there is nothing to wait for is how
/// this fixture leaked a live Dolt server into `/tmp` in the first place.
Set<int> proxiedStateStorePids(
  String tempPath, {
  required String? Function(String path) readPidFile,
}) {
  final pids = <int>{};
  for (final name in _proxyPidNames) {
    final path = '$tempPath/grid/.grid/.beads/dolt/$name';
    final contents = readPidFile(path);
    if (contents == null) continue;
    final recorded = _recordedPid(contents);
    if (recorded == null) {
      throw StateError('unreadable proxy pid file $path: ${contents.trim()}');
    }
    pids.add(recorded);
  }
  return pids;
}

/// The positive PID [contents] records, or null if it records none.
int? _recordedPid(String contents) {
  final trimmed = contents.trim();
  if (int.tryParse(trimmed) case final bare?) return bare > 0 ? bare : null;
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded case {'pid': final int recorded} when recorded > 0) {
    return recorded;
  }
  return null;
}

/// Reads a PID file that may not be there.
///
/// Null means ABSENT — never written, or removed by the proxy between the
/// check and the read. Every other [FileSystemException] is a filesystem this
/// teardown does not understand, and it travels rather than reading as an
/// empty process table.
String? _readPidFileIfPresent(String path) {
  try {
    return File(path).readAsStringSync();
  } on PathNotFoundException {
    return null;
  }
}

/// Tears the proxied state store down: a SIGKILL fence driven by the process
/// census, repeated until nothing the harness started still runs out of
/// [tempPath], and returning every PID it named on the way.
///
/// `bd dolt stop` is NOT the instrument. It is a MODE CHANGE — it migrates the
/// workspace back to embedded storage — which rewrites a store that is about to
/// be deleted anyway, and it re-spawns a proxy to serve its own command, so the
/// process it leaves behind is never the one it reported stopping.
///
/// The kill set is wider than the census: it takes the workspace's cwd-rooted
/// residents too, because a store process killed while its client still runs
/// simply comes back, and it is SEEDED from [proxiedStateStorePids] so the Dolt
/// server bd recorded is named directly rather than only once it looks like
/// one. The LOUD assertion stays on the store census, which names the invariant
/// that matters — no process is left holding the Dolt data dir the delete is
/// about to remove. A transient bd client that outlives its SIGKILL is not
/// that, and the awaited exit below already answers it.
///
/// Signalling is all this does. The returned set is the account
/// [_stopAndAwaitProxiedStateStore] then waits out: a fence that reports a
/// clean census has proved the kernel accepted its signals, not that the
/// processes are off the table with their files closed.
Future<Set<int>> _stopProxiedStateStore(String tempPath) async {
  final named = proxiedStateStorePids(
    tempPath,
    readPidFile: _readPidFileIfPresent,
  );
  var survivors = await _harnessStoreProcesses(tempPath);
  for (var round = 0; round < 40; round++) {
    final residents = await _workspaceResidents(tempPath);
    if (survivors.isEmpty && residents.isEmpty) break;
    for (final target in {
      ...named,
      for (final survivor in survivors) survivor.pid,
      ...residents,
    }) {
      named.add(target);
      Process.killPid(target, ProcessSignal.sigkill);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    survivors = await _harnessStoreProcesses(tempPath);
  }

  expect(
    [for (final survivor in survivors) survivor.command],
    isEmpty,
    reason: 'harness-owned store processes survived under $tempPath',
  );
  return named;
}

/// The flock files bd's proxy pair holds open while it is serving a store.
const _proxyLockNames = ['proxy.lock', 'proxy-child.lock'];

/// The proxy locks under [tempPath] some process still holds.
///
/// A lock file that is absent, or present with no holder, belongs to a store
/// that is already down. A lock with a holder is a proxy that is still UP —
/// including one spawned after the census came back clean, which is the
/// arrival the delete used to race and the reason the PID census alone cannot
/// close this. Without lsof nothing can be distinguished, and the probe
/// reports nothing held rather than inventing residue.
Future<Set<String>> _heldProxyLocks(String tempPath) async {
  final held = <String>{};
  for (final name in _proxyLockNames) {
    final path = '$tempPath/grid/.grid/.beads/dolt/$name';
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

/// Every harness process under [tempPath] still on the table — [named], plus a
/// fresh census — SIGKILLed again as it is named.
///
/// The poll kills because the poll is the only thing watching: bd re-spawns a
/// `db-proxy-child` to serve a command issued before the fence ran, and that
/// arrival holds the store open for its full 30-second idle timeout. A probe
/// that only looked would spin out its bound and fail a teardown one more
/// signal would have finished.
Future<Set<int>> _reapStoreResidue(String tempPath, Set<int> named) async {
  final alive = <int>{
    ...await _livePids(named),
    for (final survivor in await _harnessStoreProcesses(tempPath)) survivor.pid,
    ...await _workspaceResidents(tempPath),
  };
  for (final target in alive) {
    Process.killPid(target, ProcessSignal.sigkill);
  }
  return alive;
}

/// Stops the proxied state store and does not return until it is GONE.
///
/// [_stopProxiedStateStore] signals; this awaits the consequence — every PID
/// the fence named off the process table, and both proxy locks unheld. That is
/// the one state in which a recursive delete cannot race a write, and reaching
/// it deterministically is what makes this teardown a fence rather than a bet
/// on a retry loop.
Future<void> _stopAndAwaitProxiedStateStore(String tempPath) async {
  final named = await _stopProxiedStateStore(tempPath);
  await waitForProxiedStateStoreExit(
    survivingPids: () => _reapStoreResidue(tempPath, named),
    heldLockPaths: () => _heldProxyLocks(tempPath),
    now: DateTime.now,
    delay: (duration) => Future<void>.delayed(duration),
  );
}

/// Polls [survivingPids] and [heldLockPaths] until both come back empty.
///
/// Returns only for a store that is wholly gone. Otherwise it throws a
/// [StateError] naming the residue it timed out on — surviving PIDs, held lock
/// paths — because residue nothing can remove is a live Dolt server writing
/// into a directory the test is about to delete, and the only useful report of
/// that is the one that names it. [now] and [delay] are injected so the bound
/// can be proved without spending it.
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

/// Removes [temporary] once the store inside it is gone.
///
/// The awaited stop above is the mechanism; everything behind it is a counted
/// fallback, not the fence. macOS answers an unlink that races a write with
/// `ENOTEMPTY` — Linux tolerates it, which is why CI stayed green while this
/// teardown failed here, abandoning the tree AND its store processes on disk —
/// so a delete that fails, or a workspace that comes BACK, once the store is
/// proven gone means the fence missed something, and [onDeleteFallback] counts
/// every such miss for the case that asserts there are none.
Future<void> _deleteTemporaryWorkspace(
  Directory temporary, {
  required void Function() onDeleteFallback,
}) async {
  if (!temporary.existsSync()) return;
  await _stopAndAwaitProxiedStateStore(temporary.path);
  await deleteTemporaryWorkspaceWithRetry(
    delete: () async {
      await temporary.delete(recursive: true);
    },
    stillPresent: temporary.existsSync,
    delay: (duration) => Future<void>.delayed(duration),
    onDeleteFallback: onDeleteFallback,
    workspacePath: temporary.path,
  );
}

/// Deletes the workspace at [workspacePath] and does not return until it has
/// STAYED deleted.
///
/// A delete that reports success is not an empty `/tmp`: the leak measured here
/// was a workspace whose every file the recursive delete removed, and whose
/// `grid/.grid/.beads/dolt` chain a store process re-created on its way out —
/// a directory nothing then owned, reported by a teardown that raised nothing.
/// So a delete is only believed once [stillPresent] has come back false
/// [absenceChecks] times in a row, one [between] apart. A workspace that
/// reappears inside that window is a miss: [onDeleteFallback] counts it and the
/// next attempt deletes it again.
///
/// A [FileSystemException] that leaves the directory gone is a delete another
/// hand completed, and goes on to the same absence window. One that leaves it
/// present spends an attempt: [onDeleteFallback] once, a [delay] of [between],
/// and another try. The final attempt rethrows, so the error the teardown
/// reports is the original object and stack — never a summary of it; a
/// workspace still coming back on the final attempt raises a [StateError]
/// naming it, because a directory that survives [attempts] deletions is a live
/// writer no retry count is going to outlast.
Future<void> deleteTemporaryWorkspaceWithRetry({
  required Future<void> Function() delete,
  required bool Function() stillPresent,
  required Future<void> Function(Duration) delay,
  required void Function() onDeleteFallback,
  required String workspacePath,
  int attempts = 5,
  int absenceChecks = 5,
  Duration between = const Duration(milliseconds: 50),
}) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      await delete();
    } on FileSystemException {
      if (stillPresent()) {
        if (attempt == attempts) rethrow;
        onDeleteFallback();
        await delay(between);
        continue;
      }
    }
    var stayedGone = true;
    for (var check = 0; check < absenceChecks; check++) {
      await delay(between);
      if (stillPresent()) {
        stayedGone = false;
        break;
      }
    }
    if (stayedGone) return;
    onDeleteFallback();
    if (attempt == attempts) {
      throw StateError(
        'the temporary workspace $workspacePath was re-created after '
        '$attempts deletions',
      );
    }
  }
}

/// The `ci-rework-mint-` workspaces on disk right now.
///
/// The leak this fixture is measured by: a teardown that reported success
/// while a proxy re-created the store under it left one of these behind, and
/// nothing in the test noticed. Counted before the workspace is made and again
/// after it is removed, it does.
int _temporaryWorkspaceCount() => Directory.systemTemp
    .listSync(followLinks: false)
    .where((entry) => p.basename(entry.path).startsWith('ci-rework-mint-'))
    .length;

Future<void> _seedStore({
  required String gridRoot,
  required String workRoot,
}) async {
  final stateRoot = GridStateStore.forGridRoot(gridRoot).runtimeDir;
  await _initializeStateStore(stateRoot);
  await Directory(workRoot).create(recursive: true);
  await _runBd(workRoot, const ['init', '--prefix', 'pow']);
  await _runBd(stateRoot, const [
    'config',
    'set',
    'types.custom',
    'session,molecule,step,link,mount-attempt',
  ]);
  await _runBd(workRoot, const [
    'create',
    '--id',
    'pow-test',
    '--title',
    'test work',
    '--type',
    'task',
    '--label',
    'grid.approved',
    '--metadata',
    '{"rig":"power_station","validation_plan":"dart test"}',
  ]);
  await _runBd(stateRoot, const [
    'create',
    '--id',
    'grid_state-session-1',
    '--title',
    'parked session',
    '--type',
    'session',
    '--metadata',
    '{"rig":"grid_state","work_bead":"pow-test"}',
  ]);
  await _runBd(stateRoot, const [
    'create',
    '--id',
    'grid_state-gate-1',
    '--title',
    'fixture gate',
    '--type',
    'gate',
    '--metadata',
    '{"rig":"grid_state","blocks":"grid_state-session-1",'
        '"node":"pow-test/root","reason":"fixture parked for rework"}',
  ]);
}

Future<void> _writeStationLock(
  String gridRoot,
  String controlUrl,
  String token,
) async {
  final file = File(StationLockService.lockPath(gridRoot));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode(
      StationLockRecord(
        pid: pid,
        pgid: pid,
        startedAt: DateTime.utc(2026, 8, 10),
        controlUrl: controlUrl,
        token: token,
      ).toJson(),
    ),
  );
  await Process.run('chmod', ['0600', file.path]);
}

StationStatus _stationStatus() => StationStatus(
  substation: 'power_station',
  stateStore: 'grid_state',
  workRoot: null,
  dryRun: false,
  pid: pid,
  startedAt: DateTime.utc(2026, 8, 10),
  version: Platform.version,
  ready: 0,
  mounted: 0,
  liveSessions: 0,
  lastSyncAt: null,
);

List<String?> _workKeys(List<Bead> sessions) => sessions
    .map((bead) => bead.metadata[SessionBeadKeys.workBead] as String?)
    .toList(growable: false);

void main() {
  test(
    'resident rework supersedes before gate auto-close',
    () async {
      final leakedBefore = _temporaryWorkspaceCount();
      final temporary = await Directory.systemTemp.createTemp(
        'ci-rework-mint-',
      );
      final gridRoot = '${temporary.path}/grid';
      final workRoot = '${temporary.path}/work';
      var fallbacks = 0;
      void onRetry() => fallbacks++;
      // Registered the moment the directory exists — and therefore run LAST,
      // after the station teardown below — so a failure anywhere in the boot
      // still fences the proxied store before the tree is removed. The two
      // closing assertions are the teardown's own gate: a workspace left on
      // disk is the leak, and a delete that needed a retry is a write the
      // fence should have stopped before it started deleting.
      addTearDown(() async {
        await _deleteTemporaryWorkspace(temporary, onDeleteFallback: onRetry);
        expect(_temporaryWorkspaceCount(), lessThanOrEqualTo(leakedBefore));
        expect(fallbacks, 0, reason: 'the delete fell back to a retry');
      });
      await _seedStore(gridRoot: gridRoot, workRoot: workRoot);
      final stateStore = GridStateStore.forGridRoot(gridRoot);
      final stateBd = ProcessBdRunner(workspaceRoot: stateStore.runtimeDir);
      final transport = _RecordingTransport();
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final runtime = await assembleStationWork(
        stateStore: stateStore,
        substations: [
          SubstationWorkSpec(
            name: 'power_station',
            prefix: 'pow',
            root: workRoot,
            head: 'main',
          ),
        ],
        resolver: CircuitResolver(_leafCircuit),
        dryRun: false,
        preferSql: false,
        providerOverride: DryRunProvider(),
        gitOverride: buildDryStationGitService(),
        syncFloorInterval: const Duration(milliseconds: 20),
        registry: registry,
        transport: transport,
      );
      await runtime.start();
      final owner = TreeOwner();
      var flushScheduled = false;
      owner.onNeedsFlush = () {
        if (flushScheduled) return;
        flushScheduled = true;
        scheduleMicrotask(() {
          flushScheduled = false;
          owner.flush();
          runtime.afterFlush();
        });
      };
      owner.mountRoot(
        ProviderScope(
          child: RawAssetGrid(
            root: gridRoot,
            assets: [
              Station(
                name: 'station',
                assets: [
                  Nest(
                    children: [StationWork(wiring: runtime.wiring)],
                    child: Substations(
                      substations: [
                        Substation(
                          'power_station',
                          workRoot,
                          prefix: 'pow',
                          assets: [const SubstationWork()],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      owner.flush();
      runtime.afterFlush();
      final control = await StationControl.start(
        port: 0,
        token: 'feedback-token',
        view: _stationStatus,
        commandHandler: runtime.commands,
      );
      addTearDown(() async {
        // Snapshotted while the runtime is LIVE: `shutdown` takes the sources
        // down but leaves the sockets the assembly opened established, and
        // only an awaited close keeps this isolate off a proxy the delete
        // registered above is about to remove.
        final stores = List<StoreConnection>.of(runtime.openStores);
        await control.dispose();
        owner.unmountRoot();
        await runtime.shutdown();
        for (final store in stores) {
          await store.close();
        }
      });
      await _writeStationLock(gridRoot, control.url, 'feedback-token');
      final projection = CiFeedbackProjection(
        bd: stateBd,
        // The REAL work store this seat mints `pow-…` beads in — the same one
        // the substation is mounted over, never the state store beside it.
        workBd: ProcessBdRunner(workspaceRoot: workRoot),
        scope: sdk.SubstationScope(
          name: 'power_station',
          root: workRoot,
          prefix: 'pow',
        ),
        commandSender: ResidentFeedbackCommandSender(),
        gridRoot: gridRoot,
      );
      final reconcilerRuntime = GitHubReconcilerRuntime(
        installationId: 'installation',
        reconciler: GitHubReconciler(
          owner: 'memento',
          repository: 'power_station',
          substation: 'power_station',
          client: GitHubAppClient(
            config: GitHubAppConfig(
              appId: 'app',
              installationId: 1,
              apiBaseUri: Uri.parse('https://api.github.test'),
            ),
            tokens: _Tokens(),
            transport: _ReconcileTransport(),
          ),
          cursors: _CursorStore(),
          emit: (event) async {
            // The POLLED observation drives the projection, not a stand-in: the
            // feedback leg attributes this pull through its body's
            // `Refs: pow-test` trailer — the `grid/` head it happens to carry
            // takes no part — and the failing check aggregate is what the
            // rework decision below reads.
            expect(event, isA<PullRequestFeedback>());
            await projection(event);
          },
        ),
        coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      );

      await reconcilerRuntime.reconciler.reconcileOnce();
      expect(
        transport.flares.where(
          (flare) =>
              flare.name == 'rework.specPreserved' &&
              flare.data['beadId'] == 'pow-test',
        ),
        hasLength(1),
      );
      expect(
        transport.flares.where(
          (flare) =>
              flare.name == 'gate.autoCloseFailed' &&
              flare.data['sessionId'] == 'grid_state-session-1',
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'resident rework self-mints and replay stays at one retired round',
    () async {
      final leakedBefore = _temporaryWorkspaceCount();
      final temporary = await Directory.systemTemp.createTemp(
        'ci-rework-mint-',
      );
      final gridRoot = '${temporary.path}/grid';
      final workRoot = '${temporary.path}/work';
      var fallbacks = 0;
      void onRetry() => fallbacks++;
      // Registered the moment the directory exists — and therefore run LAST,
      // after the station teardown below — so a failure anywhere in the boot
      // still fences the proxied store before the tree is removed. A workspace
      // left on disk is the leak; the retry count rides the failure so whoever
      // un-skips this case reads why the delete had to race.
      addTearDown(() async {
        await _deleteTemporaryWorkspace(temporary, onDeleteFallback: onRetry);
        expect(
          _temporaryWorkspaceCount(),
          lessThanOrEqualTo(leakedBefore),
          reason: 'the delete fell back to a retry $fallbacks times',
        );
      });
      await _seedStore(gridRoot: gridRoot, workRoot: workRoot);
      final stateStore = GridStateStore.forGridRoot(gridRoot);
      final stateBd = ProcessBdRunner(workspaceRoot: stateStore.runtimeDir);
      final transport = _RecordingTransport();
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final runtime = await assembleStationWork(
        stateStore: stateStore,
        substations: [
          SubstationWorkSpec(
            name: 'power_station',
            prefix: 'pow',
            root: workRoot,
            head: 'main',
          ),
        ],
        resolver: CircuitResolver(_leafCircuit),
        dryRun: false,
        preferSql: false,
        providerOverride: DryRunProvider(),
        gitOverride: buildDryStationGitService(),
        syncFloorInterval: const Duration(milliseconds: 20),
        registry: registry,
        transport: transport,
      );
      await runtime.start();
      final owner = TreeOwner();
      var flushScheduled = false;
      owner.onNeedsFlush = () {
        if (flushScheduled) return;
        flushScheduled = true;
        scheduleMicrotask(() {
          flushScheduled = false;
          owner.flush();
          runtime.afterFlush();
        });
      };
      owner.mountRoot(
        ProviderScope(
          child: RawAssetGrid(
            root: gridRoot,
            assets: [
              Station(
                name: 'station',
                assets: [
                  Nest(
                    children: [StationWork(wiring: runtime.wiring)],
                    child: Substations(
                      substations: [
                        Substation(
                          'power_station',
                          workRoot,
                          prefix: 'pow',
                          assets: [const SubstationWork()],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      owner.flush();
      runtime.afterFlush();
      final control = await StationControl.start(
        port: 0,
        token: 'feedback-token',
        view: _stationStatus,
        commandHandler: runtime.commands,
      );
      addTearDown(() async {
        // Snapshotted while the runtime is LIVE: `shutdown` takes the sources
        // down but leaves the sockets the assembly opened established, and
        // only an awaited close keeps this isolate off a proxy the delete
        // registered above is about to remove.
        final stores = List<StoreConnection>.of(runtime.openStores);
        await control.dispose();
        owner.unmountRoot();
        await runtime.shutdown();
        for (final store in stores) {
          await store.close();
        }
      });
      await _writeStationLock(gridRoot, control.url, 'feedback-token');
      final projection = CiFeedbackProjection(
        bd: stateBd,
        // The REAL work store this seat mints `pow-…` beads in — the same one
        // the substation is mounted over, never the state store beside it.
        workBd: ProcessBdRunner(workspaceRoot: workRoot),
        scope: sdk.SubstationScope(
          name: 'power_station',
          root: workRoot,
          prefix: 'pow',
        ),
        commandSender: ResidentFeedbackCommandSender(),
        gridRoot: gridRoot,
      );
      final reconcilerRuntime = GitHubReconcilerRuntime(
        installationId: 'installation',
        reconciler: GitHubReconciler(
          owner: 'memento',
          repository: 'power_station',
          substation: 'power_station',
          client: GitHubAppClient(
            config: GitHubAppConfig(
              appId: 'app',
              installationId: 1,
              apiBaseUri: Uri.parse('https://api.github.test'),
            ),
            tokens: _Tokens(),
            transport: _ReconcileTransport(),
          ),
          cursors: _CursorStore(),
          emit: (event) async {
            // The POLLED observation drives the projection, not a stand-in: the
            // feedback leg attributes this pull through its body's
            // `Refs: pow-test` trailer — the `grid/` head it happens to carry
            // takes no part — and the failing check aggregate is what the
            // rework decision below reads.
            expect(event, isA<PullRequestFeedback>());
            await projection(event);
          },
        ),
        coordinator: GitHubPollCoordinator(minimumSpacing: Duration.zero),
      );

      await reconcilerRuntime.reconciler.reconcileOnce();
      expect(
        transport.flares.where(
          (flare) =>
              flare.name == 'rework.specPreserved' &&
              flare.data['beadId'] == 'pow-test',
        ),
        hasLength(1),
      );
      expect(
        transport.flares.where(
          (flare) =>
              flare.name == 'gate.autoCloseFailed' &&
              flare.data['sessionId'] == 'grid_state-session-1',
        ),
        isEmpty,
      );
      final afterFirst = await _waitForMint(stateBd, transport);
      expect(
        _workKeys(afterFirst).where((key) => key == 'pow-test#r1'),
        hasLength(1),
      );
      expect(
        _workKeys(afterFirst).where((key) => key == 'pow-test'),
        hasLength(1),
      );

      await reconcilerRuntime.reconciler.reconcileOnce();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final afterReplay = await _sessions(stateBd);
      expect(
        _workKeys(afterReplay).where((key) => key == 'pow-test#r1'),
        hasLength(1),
      );
      expect(
        _workKeys(afterReplay).where((key) => key == 'pow-test'),
        hasLength(1),
      );
      expect(
        transport.flares.where(
          (flare) => const {
            'session.mintFailed',
            'session.moleculePourFailed',
            'session.mintExhausted',
            'session.mintRefused',
          }.contains(flare.name),
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip:
        'blocked by tg-u4ml: resident-command rework does not self-mint replacement',
  );
}

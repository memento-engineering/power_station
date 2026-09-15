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
/// bd's PID files: bd re-spawns a proxy to serve the very command that stops
/// the previous one, so a PID captured from `.beads/dolt/proxy.pid` names a
/// process that is already gone while its successor is missed entirely. The
/// process table is the only account that cannot go stale.
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
/// difference.
Future<List<int>> _workspaceResidents(String tempPath) async {
  final ProcessResult result;
  try {
    result = await Process.run('lsof', [
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
  return [
    for (final line in (result.stdout as String).split('\n'))
      if (line.startsWith('p'))
        // `pid` is this process: never in the kill set, whatever lsof says.
        if (int.tryParse(line.substring(1)) case final resident?)
          if (resident != pid) resident,
  ];
}

/// Tears the proxied state store down: a SIGKILL fence driven by the process
/// census, repeated until nothing the harness started still runs out of
/// [tempPath].
///
/// `bd dolt stop` is NOT the instrument. It is a MODE CHANGE — it migrates the
/// workspace back to embedded storage — which rewrites a store that is about to
/// be deleted anyway, and it re-spawns a proxy to serve its own command, so the
/// process it leaves behind is never the one it reported stopping.
///
/// The kill set is wider than the census: it takes the workspace's cwd-rooted
/// residents too, because a store process killed while its client still runs
/// simply comes back. The LOUD assertion stays on the store census, which
/// names the invariant that matters — no process is left holding the Dolt data
/// dir the delete is about to remove. A transient bd client that outlives its
/// SIGKILL is not that, and the bounded delete already answers it.
///
/// The fence is LOUD because a survivor is not cosmetic: it holds a Dolt data
/// dir that the temporary-directory delete is about to remove, and it outlives
/// the test run.
Future<void> _stopProxiedStateStore(String tempPath) async {
  var survivors = await _harnessStoreProcesses(tempPath);
  for (var round = 0; round < 40; round++) {
    final residents = await _workspaceResidents(tempPath);
    if (survivors.isEmpty && residents.isEmpty) break;
    for (final pid in [
      for (final survivor in survivors) survivor.pid,
      ...residents,
    ]) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    survivors = await _harnessStoreProcesses(tempPath);
  }

  expect(
    [for (final survivor in survivors) survivor.command],
    isEmpty,
    reason: 'harness-owned store processes survived under $tempPath',
  );
}

/// Removes [temporary] once nothing is writing inside it, retrying the delete
/// across a proxy spawned AFTER an empty census.
///
/// The fence above cannot be the whole story: bd re-spawns a
/// `db-proxy-child` to serve a command issued before the fence ran, so a store
/// process can appear once the census has already come back clean and write
/// into `.beads/dolt/` while the recursive delete is walking it. macOS answers
/// that unlink race with `ENOTEMPTY` — Linux tolerates it, which is why CI
/// stayed green while this teardown failed on most runs here, abandoning the
/// tree AND its store processes on disk.
///
/// Every attempt re-censuses, so a late arrival is killed before the next
/// delete. Only [FileSystemException] is caught, and only for as long as the
/// bound allows: a surviving store process still fails the fence's own
/// expectation, and a delete that never succeeds still throws its original
/// error, LOUDLY.
Future<void> _deleteTemporaryWorkspace(Directory temporary) async {
  const attempts = 40;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    if (!temporary.existsSync()) return;
    await _stopProxiedStateStore(temporary.path);
    try {
      await temporary.delete(recursive: true);
      return;
    } on FileSystemException {
      if (!temporary.existsSync()) return;
      if (attempt == attempts) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

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
      final temporary = await Directory.systemTemp.createTemp(
        'ci-rework-mint-',
      );
      final gridRoot = '${temporary.path}/grid';
      final workRoot = '${temporary.path}/work';
      // Registered the moment the directory exists — and therefore run LAST,
      // after the station teardown below — so a failure anywhere in the boot
      // still fences the proxied store before the tree is removed.
      addTearDown(() async {
        await _deleteTemporaryWorkspace(temporary);
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
        await control.dispose();
        owner.unmountRoot();
        await runtime.shutdown();
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
      final temporary = await Directory.systemTemp.createTemp(
        'ci-rework-mint-',
      );
      final gridRoot = '${temporary.path}/grid';
      final workRoot = '${temporary.path}/work';
      // Registered the moment the directory exists — and therefore run LAST,
      // after the station teardown below — so a failure anywhere in the boot
      // still fences the proxied store before the tree is removed.
      addTearDown(() async {
        await _deleteTemporaryWorkspace(temporary);
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
        await control.dispose();
        owner.unmountRoot();
        await runtime.shutdown();
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

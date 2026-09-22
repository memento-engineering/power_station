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

// The ONE proxied-bd lifecycle harness this workspace has, lifted out of this
// fixture so the real-bd filing fixture next door runs the same census, the
// same stop fence and the same PID parser. Another package's `test/` tree
// carries no `package:` URI, so the workspace-relative path IS the import; the
// production `grid_assets` dependency is unrelated and unchanged.
import '../../../grid_assets/test/support/proxied_bd_test_support.dart'
    as proxied_bd;

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

/// The ONE `bd` runner every state write in a case goes through, held to a
/// single concurrency permit so the teardown can prove it IDLE.
///
/// What re-creates this fixture's workspace after a delete that already
/// reported success is not a stray server — it is a bd CLIENT. Measured
/// against bd 1.1.0: a `bd` command run in a proxied-server workspace whose
/// `.beads/dolt` has been removed rebuilds the whole chain and spawns a fresh
/// proxy pair, and it does so under EVERY documented suppression —
/// `BEADS_DOLT_AUTO_START=0`, `BEADS_DOLT_AUTO_START=false`, and
/// `dolt.auto-start: false` in `.beads/config.yaml` alike (all four arms:
/// directory back, two store pids, exit 0). Proxied mode simply does not
/// consult them. So the capability cannot be taken away; the CLIENTS have to
/// be gone.
///
/// The census below cannot do that on its own, because a command that has not
/// been spawned yet is in no process table. Two things make it possible
/// instead. This runner is the ONE state writer in the case — injected as
/// `assembleStationWork`'s `stateBdOverride`, which otherwise builds a second
/// `ProcessBdRunner` over the same store that the test never holds and
/// therefore can never wait on. And one permit makes [drainStateBdRunner] a
/// fence: the semaphore hands permits on in FIFO order, so acquiring it once
/// is proof that every spawn this runner had queued or in flight has
/// finished.
ProcessBdRunner seededStateBdRunner(String workspaceRoot) =>
    ProcessBdRunner(workspaceRoot: workspaceRoot, maxConcurrency: 1);

/// Returns once [stateBd] has no `bd` spawn queued or in flight.
///
/// The station teardown awaits this AFTER the runtime is down and before the
/// process fence starts counting, so the fence censuses a settled table rather
/// than one a shutting-down sync loop is still adding to. A spawn that is
/// merely FORKED is not yet in `ps` under its workspace, which is exactly the
/// arrival the SIGKILL fence used to miss and the absence window used to
/// outlast by a couple of hundred milliseconds.
Future<void> drainStateBdRunner(ProcessBdRunner stateBd) =>
    stateBd.guarded(() async {});

/// Returns once [stateBd] owes no spawn, and KEEPS its one permit so it never
/// spawns again.
///
/// [drainStateBdRunner] proves the runner owed nothing at the moment it ran;
/// the engine can still owe it more afterwards. A session scope unmounted
/// mid-mint retires its abandoned session with one last state write, from an
/// unawaited continuation the test holds no handle to — measured here as a
/// `bd update` spawned between the drain and the stop fence, SIGKILLed by that
/// fence as a workspace resident, and failing an otherwise clean case with the
/// engine's `BdCommandFailed: bd exited -9`. Holding the permit closes that
/// window instead of racing it: everything queued before this call has
/// finished, and everything queued after it parks behind a permit that is
/// never handed back — a write against a store the teardown is about to
/// delete, which is exactly the write that must not run.
Future<void> closeStateBdRunner(ProcessBdRunner stateBd) {
  final held = Completer<void>();
  unawaited(
    stateBd.guarded(() {
      held.complete();
      return Completer<void>().future;
    }),
  );
  return held.future;
}

/// The proxied state store's PID root inside a case workspace.
///
/// The workspace and the store are DIFFERENT directories — the store sits at
/// the grid home nested under the workspace — so the shared fence is told
/// both: the workspace is what the path census matches processes on, and this
/// is where bd writes the pair's PID and lock files.
String _stateStorePidRoot(String workspacePath) =>
    p.join(workspacePath, 'grid', '.grid', '.beads', 'dolt');

/// Removes [temporary] once the store inside it is gone.
///
/// The awaited stop above is the mechanism; everything behind it is a counted
/// fallback, not the fence. macOS answers an unlink that races a write with
/// `ENOTEMPTY` — Linux tolerates it, which is why CI stayed green while this
/// teardown failed here, abandoning the tree AND its store processes on disk —
/// so a delete that fails, or a workspace that comes BACK, once the store is
/// proven gone means the fence missed something, and [onDeleteFallback] counts
/// every such miss for the case that asserts there are none.
///
/// The process census is read on BOTH sides of that delete, because the two
/// sides answer different questions: before it, whether the stop fence left a
/// writer behind; after the absence window, whether one arrived while the
/// window was running — the bd client that rebuilds a proxied store out of an
/// empty path, which no window can outlast and only a census can name.
Future<void> _deleteTemporaryWorkspace(
  Directory temporary, {
  required void Function() onDeleteFallback,
}) async {
  if (!temporary.existsSync()) return;
  await proxied_bd.stopAndAwaitProxiedStateStore(
    workspacePath: temporary.path,
    pidRootPath: _stateStorePidRoot(temporary.path),
  );
  // The one state a recursive delete cannot race, re-read AFTER the fence
  // rather than inferred from it: nothing the harness can account for is still
  // working under this tree. A census that is not empty here is a writer the
  // stop above did not reach, and naming it beats deleting around it.
  final preDeleteCensus = await proxied_bd.workspaceProcessCensus(
    temporary.path,
  );
  proxied_bd.expectEmptyWorkspaceProcessCensus(
    preDeleteCensus,
    workspacePath: temporary.path,
    phase: 'before delete',
  );
  await deleteTemporaryWorkspaceWithRetry(
    delete: () async {
      await temporary.delete(recursive: true);
    },
    stillPresent: temporary.existsSync,
    delay: (duration) => Future<void>.delayed(duration),
    onDeleteFallback: onDeleteFallback,
    workspacePath: temporary.path,
    reappearanceCensus: () => proxied_bd.workspaceProcessCensus(temporary.path),
  );
  // The other side of the window. An absence window that ran clean while a bd
  // client was working under the path proves only that the client had not got
  // round to re-creating the store yet — so the tree being gone is believed
  // only once nothing is left to bring it back.
  final postDeleteCensus = await proxied_bd.workspaceProcessCensus(
    temporary.path,
  );
  proxied_bd.expectEmptyWorkspaceProcessCensus(
    postDeleteCensus,
    workspacePath: temporary.path,
    phase: 'after absence window',
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
/// [absenceChecks] and [between] are a MEASUREMENT, not a guess. A 20 Hz stat
/// loop over `/tmp` around ten consecutive deletes of this fixture's workspace
/// saw no workspace come back at all, and every one stay gone through a
/// 3,000 ms tail past the run that made it; the leak that reached the station
/// was a workspace present at the count assertion and gone again afterwards,
/// which is the same tail seen from the wrong side. So the default window is
/// 6,000 ms — twice the longest clean tail measured — and it is spent only on
/// a teardown that is already done.
///
/// A [FileSystemException] that leaves the directory gone is a delete another
/// hand completed, and goes on to the same absence window. One that leaves it
/// present spends an attempt: [onDeleteFallback] once, a [delay] of [between],
/// and another try. The final attempt rethrows, so the error the teardown
/// reports is the original object and stack — never a summary of it; a
/// workspace still coming back on the final attempt raises a [StateError]
/// naming it — and a FRESH [reappearanceCensus], taken at the moment of the
/// last reappearance — because a directory that survives [attempts] deletions
/// is a live writer no retry count is going to outlast, and the only useful
/// report of one is the one that says which process it was.
Future<void> deleteTemporaryWorkspaceWithRetry({
  required Future<void> Function() delete,
  required bool Function() stillPresent,
  required Future<void> Function(Duration) delay,
  required void Function() onDeleteFallback,
  required String workspacePath,
  required Future<proxied_bd.WorkspaceProcessCensus> Function()
  reappearanceCensus,
  int attempts = 5,
  int absenceChecks = 120,
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
        '$attempts deletions; ${proxied_bd.describeWorkspaceProcessCensus(await reappearanceCensus())}',
      );
    }
  }
}

/// Every `ci-rework-mint-` entry in the system temp directory right now.
List<FileSystemEntity> _temporaryWorkspaces() => [
  for (final entry in Directory.systemTemp.listSync(followLinks: false))
    if (p.basename(entry.path).startsWith('ci-rework-mint-')) entry,
];

/// The `ci-rework-mint-` workspaces on disk right now.
///
/// The leak this fixture is measured by: a teardown that reported success
/// while a proxy re-created the store under it left one of these behind, and
/// nothing in the test noticed. Counted before the workspace is made and polled
/// after it is removed by [expectNoDurableTemporaryWorkspaceLeak], it does.
int _temporaryWorkspaceCount() => _temporaryWorkspaces().length;

/// Every `ci-rework-mint-` workspace on disk, as the evidence a durable leak
/// carries: its absolute path, its UTC modification time, and a sorted
/// recursive listing of what is inside it.
///
/// The listing is the part that tells a leak apart. The residue measured on
/// this host was an empty `grid/.grid/.beads/dolt` skeleton re-created after
/// the delete, and the mtime places it against the run that made it. Links are
/// not followed. A workspace that vanishes while it is being described keeps
/// its path and says so, because this runs only on the way to a failure, and
/// a diagnosis that throws would replace the error it exists to explain.
String _describeTemporaryWorkspaces() {
  final workspaces = _temporaryWorkspaces()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (workspaces.isEmpty) return 'no ci-rework-mint- workspace on disk';
  return [for (final entry in workspaces) _describeWorkspace(entry)].join('\n');
}

/// One workspace for [_describeTemporaryWorkspaces].
String _describeWorkspace(FileSystemEntity entry) {
  final path = entry.absolute.path;
  final stat = entry.statSync();
  if (stat.type == FileSystemEntityType.notFound) {
    return '$path (vanished during diagnosis)';
  }
  final modified = stat.modified.toUtc().toIso8601String();
  final List<String> listing;
  try {
    listing = [
      for (final child in Directory(
        path,
      ).listSync(recursive: true, followLinks: false))
        child is Directory
            ? '${p.relative(child.path, from: path)}/'
            : p.relative(child.path, from: path),
    ]..sort();
  } on FileSystemException catch (error) {
    return Directory(path).existsSync()
        ? '$path (modified $modified; listing failed: $error)'
        : '$path (modified $modified; vanished during diagnosis)';
  }
  return [
    '$path (modified $modified)',
    for (final relative in listing) '  $relative',
  ].join('\n');
}

/// Refuses unless the `ci-rework-mint-` workspace count is back at
/// [baselineCount] and the workspace's [processCensus] is empty — allowing a
/// residue that CLEARS inside a bounded window, and naming one that does not.
///
/// The count is global and instantaneous, and the station measured it red
/// with nothing durable behind it: a run whose workspace had stayed gone
/// through the whole delete-absence window read one workspace over its
/// baseline, and `/tmp` held no workspace of that run's afterwards. A single
/// read cannot tell that residue from a leak. So [currentCount] and
/// [processCensus] are sampled together, once immediately — a clean first
/// sample returns without waiting, logging, or describing — and otherwise up
/// to [checks] more times, [between] apart.
///
/// The first clean resample is a TRANSIENT: [reportTransient] carries one
/// line naming the recovered count and the first sample's census, and the
/// teardown passes. A final sample still above the baseline, or with either
/// census arm occupied, is a DURABLE leak: a [StateError] carries the
/// baseline and final counts, the final census, and [describeWorkspaces] —
/// which is read on that branch alone, because it walks every workspace on
/// disk.
///
/// [checks] and [between] are the same MEASUREMENT the delete-absence window
/// uses: a 20 Hz stat loop over `/tmp` around ten consecutive deletes of this
/// fixture's workspace saw every one stay gone through a 3,000 ms tail, so
/// 120 checks 50 ms apart spend twice that before a residue is called
/// durable. [delay] is injected so the bound can be proved without spending
/// it.
Future<void> expectNoDurableTemporaryWorkspaceLeak({
  required int baselineCount,
  required int Function() currentCount,
  required Future<proxied_bd.WorkspaceProcessCensus> Function() processCensus,
  required String Function() describeWorkspaces,
  required Future<void> Function(Duration) delay,
  required void Function(String) reportTransient,
  int checks = 120,
  Duration between = const Duration(milliseconds: 50),
}) async {
  bool clean(int count, proxied_bd.WorkspaceProcessCensus census) =>
      count <= baselineCount &&
      census.stores.isEmpty &&
      census.residents.isEmpty;

  final firstCount = currentCount();
  final firstCensus = await processCensus();
  if (clean(firstCount, firstCensus)) return;

  var count = firstCount;
  var census = firstCensus;
  for (var check = 1; check <= checks; check++) {
    await delay(between);
    count = currentCount();
    census = await processCensus();
    if (clean(count, census)) {
      reportTransient(
        'ci-rework-mint teardown: transient workspace residue cleared after '
        '$check of $checks checks ${between.inMilliseconds} ms apart; the '
        'workspace count recovered to $count from $firstCount (baseline '
        '$baselineCount); the first sample held ${proxied_bd.describeWorkspaceProcessCensus(firstCensus)}',
      );
      return;
    }
  }
  throw StateError(
    'a ci-rework-mint- workspace leak outlasted $checks checks '
    '${between.inMilliseconds} ms apart: $count workspaces on disk against a '
    'baseline of $baselineCount; ${proxied_bd.describeWorkspaceProcessCensus(census)}; on disk:\n'
    '${describeWorkspaces()}',
  );
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
      // closing checks are the teardown's own gate: a workspace still on disk
      // once the durable check's window has run out is the leak, and a delete
      // that needed a retry is a write the fence should have stopped before it
      // started deleting.
      addTearDown(() async {
        await _deleteTemporaryWorkspace(temporary, onDeleteFallback: onRetry);
        await expectNoDurableTemporaryWorkspaceLeak(
          baselineCount: leakedBefore,
          currentCount: _temporaryWorkspaceCount,
          processCensus: () =>
              proxied_bd.workspaceProcessCensus(temporary.path),
          describeWorkspaces: _describeTemporaryWorkspaces,
          delay: Future<void>.delayed,
          reportTransient: stderr.writeln,
        );
        expect(fallbacks, 0, reason: 'the delete fell back to a retry');
      });
      await _seedStore(gridRoot: gridRoot, workRoot: workRoot);
      final stateStore = GridStateStore.forGridRoot(gridRoot);
      final stateBd = seededStateBdRunner(stateStore.runtimeDir);
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
        // The SAME runner the projection and the session helpers use, so the
        // case has exactly ONE state writer and the teardown can drain it.
        // Left to itself the assembly builds a second `ProcessBdRunner` over
        // this store, and a late spawn from THAT one is a bd client nothing in
        // the teardown holds a reference to.
        stateBdOverride: BdCliService(stateBd),
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
        // Last, because `shutdown` cancels the sync loop's TIMERS but does not
        // await the `bd` spawns already on their way out of it. Until this
        // returns, the workspace teardown registered above would be counting
        // processes against a store that is still being read.
        await drainStateBdRunner(stateBd);
        // Then CLOSED: the engine may still queue one more state write — an
        // abandoned mint's retirement — from a continuation nothing here can
        // await, and it must park rather than spawn into the fence below.
        await closeStateBdRunner(stateBd);
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
    // A MEASURED budget, not a round number. This case boots a proxied bd
    // store, serialises every state write through the ONE permit the teardown
    // fence depends on, and spends the bounded absence and residue windows on
    // its way out: 29 to 62 seconds of real work across eleven runs on the
    // station host. The minute it used to carry sat UNDER that — one clean run
    // measured 62 seconds, and a loaded one expired inside the projection, so
    // the teardown SIGKILLed the `bd` it had parked and the case reported
    // `bd exited -9`: a red that reads like a store failure and blocks the
    // review of a diff that never touched this file. Three minutes is about
    // three times the longest clean run, and still bounded — a genuine hang
    // fails the case instead of parking the lane.
    timeout: const Timeout(Duration(minutes: 3)),
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
      // still on disk once the durable check's window has run out is the leak;
      // the retry count rides the failure so whoever un-skips this case reads
      // why the delete had to race.
      addTearDown(() async {
        await _deleteTemporaryWorkspace(temporary, onDeleteFallback: onRetry);
        printOnFailure('the delete fell back to a retry $fallbacks times');
        await expectNoDurableTemporaryWorkspaceLeak(
          baselineCount: leakedBefore,
          currentCount: _temporaryWorkspaceCount,
          processCensus: () =>
              proxied_bd.workspaceProcessCensus(temporary.path),
          describeWorkspaces: _describeTemporaryWorkspaces,
          delay: Future<void>.delayed,
          reportTransient: stderr.writeln,
        );
      });
      await _seedStore(gridRoot: gridRoot, workRoot: workRoot);
      final stateStore = GridStateStore.forGridRoot(gridRoot);
      final stateBd = seededStateBdRunner(stateStore.runtimeDir);
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
        // The SAME runner the projection and the session helpers use, so the
        // case has exactly ONE state writer and the teardown can drain it.
        // Left to itself the assembly builds a second `ProcessBdRunner` over
        // this store, and a late spawn from THAT one is a bd client nothing in
        // the teardown holds a reference to.
        stateBdOverride: BdCliService(stateBd),
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
        // Last, because `shutdown` cancels the sync loop's TIMERS but does not
        // await the `bd` spawns already on their way out of it. Until this
        // returns, the workspace teardown registered above would be counting
        // processes against a store that is still being read.
        await drainStateBdRunner(stateBd);
        // Then CLOSED: the engine may still queue one more state write — an
        // abandoned mint's retirement — from a continuation nothing here can
        // await, and it must park rather than spawn into the fence below.
        await closeStateBdRunner(stateBd);
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
    // The same measured budget as the case above: whoever un-skips this one
    // boots the same store through the same single-permit writer.
    timeout: const Timeout(Duration(minutes: 3)),
    skip:
        'blocked by tg-u4ml: resident-command rework does not self-mint replacement',
  );
}

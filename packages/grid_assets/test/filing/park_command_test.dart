import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_fakes.dart' show callMetadata;
import '../support/package_root.dart';

const String _workRoot = '/work/power_station';
const String _workBead = 'pow-child';
const String _session = 'tgdog-s1';

/// Creates a REAL grid home — `<home>/.grid/.beads` — because the resolver
/// probes the filesystem to tell a grid home from its own state store.
String _gridHome() {
  final home = Directory.systemTemp.createTempSync('grid-home-');
  Directory(p.join(home.path, '.grid', '.beads')).createSync(recursive: true);
  addTearDown(() => home.deleteSync(recursive: true));
  return home.path;
}

/// One store's worth of fake bd state: the beads it holds, plus every argv it
/// was ever handed. Stateful — a mutation lands in [beads] so a later read in
/// the SAME run observes it (the round trip needs that).
final class _Store {
  _Store(this.root);

  final String root;
  final Map<String, Map<String, Object?>> beads = {};
  final List<List<String>> argvs = [];
  int failAt = -1;
  String failWith = '';

  List<List<String>> callsTo(String subcommand) =>
      argvs.where((argv) => argv.first == subcommand).toList();
}

/// A stateful `bd` fake covering exactly the calls the two verbs make:
/// `query id=<id>`, `dep list`, `list -t <type> --metadata-field k=v`,
/// `update`, `defer`, `undefer` and `close`. Fakes, not mocks.
final class _FakeBd implements BdRunner {
  _FakeBd(this.store);

  final _Store store;
  int _mutations = 0;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    store.argvs.add(args);
    return switch (args.first) {
      'query' => _envelope(_query(args)),
      'dep' => _envelope(const []),
      'list' => _envelope(_list(args)),
      'update' => _mutate(args, _update),
      'defer' => _mutate(args, _defer),
      'undefer' => _mutate(args, _undefer),
      'close' => _mutate(args, _close),
      _ => _envelope(const []),
    };
  }

  BdResult _envelope(List<Map<String, Object?>> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );

  BdResult _mutate(List<String> args, void Function(List<String>) apply) {
    if (_mutations++ == store.failAt) {
      return BdResult(exitCode: 1, stdout: '', stderr: store.failWith);
    }
    apply(args);
    return _envelope(const []);
  }

  List<Map<String, Object?>> _query(List<String> args) {
    final id = args[1].replaceFirst('id=', '');
    final bead = store.beads[id];
    return bead == null ? const [] : [bead];
  }

  List<Map<String, Object?>> _list(List<String> args) {
    final type = args[args.indexOf('-t') + 1];
    final filters = <String, String>{};
    for (var i = 0; i + 1 < args.length; i++) {
      if (args[i] != '--metadata-field') continue;
      final pair = args[i + 1];
      final eq = pair.indexOf('=');
      filters[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return [
      for (final bead in store.beads.values)
        if (bead['issue_type'] == type &&
            filters.entries.every(
              (f) =>
                  (bead['metadata']! as Map<String, Object?>)[f.key] == f.value,
            ))
          bead,
    ];
  }

  void _update(List<String> args) {
    final bead = store.beads[args[1]]!;
    final metadata = bead['metadata']! as Map<String, Object?>;
    for (var i = 0; i + 1 < args.length; i++) {
      switch (args[i]) {
        case '--set-metadata':
          final pair = args[i + 1];
          final eq = pair.indexOf('=');
          metadata[pair.substring(0, eq)] = pair.substring(eq + 1);
        case '--unset-metadata':
          metadata.remove(args[i + 1]);
        case '--append-notes':
          bead['notes'] = '${bead['notes'] ?? ''}\n${args[i + 1]}'.trim();
      }
    }
  }

  void _defer(List<String> args) {
    final bead = store.beads[args[1]]!;
    bead['status'] = 'deferred';
    bead['defer_until'] = '${args[args.indexOf('--until') + 1]}T00:00:00.000Z';
  }

  void _undefer(List<String> args) {
    final bead = store.beads[args[1]]!;
    bead['status'] = 'open';
    bead['defer_until'] = null;
  }

  void _close(List<String> args) {
    final bead = store.beads[args[1]]!;
    bead['status'] = 'closed';
    bead['close_reason'] = args[args.indexOf('--reason') + 1];
  }
}

/// A recording [ProcessGroupController] with programmed liveness. Only the two
/// probe verbs are reachable from the park verb; the signalling half must NOT
/// be — park never kills anything.
final class _FakeProcesses implements ProcessGroupController {
  _FakeProcesses({this.alivePids = const {}, this.membersByPgid = const {}});

  final Set<int> alivePids;
  final Map<int, List<int>> membersByPgid;
  final List<String> probes = [];

  @override
  bool processAlive(int pid) {
    probes.add('alive:$pid');
    return alivePids.contains(pid);
  }

  @override
  Future<List<int>> groupMembers(int pgid) async {
    probes.add('members:$pgid');
    return membersByPgid[pgid] ?? const <int>[];
  }

  @override
  Future<int?> resolvePgid(int pid) async =>
      throw StateError('park never resolves a pgid');

  @override
  bool signalGroup(int pgid, ProcessSignal signal) =>
      throw StateError('park never signals a group');

  @override
  int currentGroupId() => throw StateError('park never reads its own group');
}

/// A [WorktreeActivityProbe] fake — the corroboration the verb reports but
/// never decides on.
final class _FakeWorktrees implements WorktreeActivityProbe {
  _FakeWorktrees(this.activity);

  final WorktreeActivity activity;
  final List<String> calls = [];

  @override
  Future<WorktreeActivity> probe({
    required String stateStoreRoot,
    required String workBeadId,
  }) async {
    calls.add('$stateStoreRoot:$workBeadId');
    return activity;
  }
}

WorktreeActivity _stale() => WorktreeActivity(
  path: '/grid/.grid/worktrees/power_station/$_workBead',
  lastWrite: DateTime.utc(2026, 9, 7, 4),
  age: const Duration(hours: 54),
);

Map<String, Object?> _workBeadJson({
  bool approved = true,
  String status = 'open',
}) => {
  'id': _workBead,
  'title': 'child',
  'issue_type': 'task',
  'description': 'No local ordering.',
  'acceptance_criteria': '- [ ] checked',
  'status': status,
  'metadata': <String, Object?>{
    'validation_plan': 'dart test',
    if (approved) ...{
      kApprovedByKey: 'nico',
      kApprovedAtKey: '2026-09-01T00:00:00.000Z',
      kApprovedRevKey: '$kFilingApprovalRevisionPrefix${'a' * 64}',
    },
  },
};

Map<String, Object?> _sessionJson({
  String pauseState = '',
  int? pgid,
  int? pid,
  String workBead = _workBead,
}) => {
  'id': _session,
  'title': 'session for $workBead',
  'issue_type': 'session',
  'status': 'open',
  'metadata': <String, Object?>{
    SessionBeadKeys.workBead: workBead,
    if (pauseState.isNotEmpty) SessionBeadKeys.pauseState: pauseState,
    if (pgid != null) SessionBeadKeys.pgid: '$pgid',
    if (pid != null) SessionBeadKeys.pid: '$pid',
  },
};

Map<String, Object?> _gateJson({String status = 'open'}) => {
  'id': 'tgdog-g1',
  'title': 'gate',
  'issue_type': 'gate',
  'status': status,
  'metadata': <String, Object?>{kGateBlocksKey: _session, 'node': 'build'},
};

typedef _Harness = ({
  CommandRunner<int> runner,
  StringBuffer out,
  StringBuffer err,
  _Store work,
  _Store state,
  _FakeProcesses processes,
  _FakeWorktrees worktrees,
  List<String> resolvedFor,
});

_Harness _harness({
  required String home,
  Map<String, Object?>? workBead,
  List<Map<String, Object?>> stateBeads = const [],
  _FakeProcesses? processes,
  WorktreeActivity? activity,
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final work = _Store(_workRoot);
  final state = _Store(p.join(home, '.grid'));
  final resolvedFor = <String>[];
  work.beads[_workBead] = workBead ?? _workBeadJson();
  for (final bead in stateBeads) {
    state.beads[bead['id']! as String] = bead;
  }
  final stores = {work.root: _FakeBd(work), state.root: _FakeBd(state)};
  BdRunner runnerFor(String root) =>
      stores[root] ?? (throw StateError('unexpected store root "$root"'));
  final probes = processes ?? _FakeProcesses();
  final worktrees = _FakeWorktrees(activity ?? _stale());
  String workStoreRoot(String beadId) {
    resolvedFor.add(beadId);
    return _workRoot;
  }

  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        ParkCommand(
          service: ParkService(
            runnerFor: runnerFor,
            processes: probes,
            worktrees: worktrees,
          ),
          workStoreRoot: workStoreRoot,
          stateRoot: () => home,
          out: out,
          err: err,
        ),
      )
      ..addCommand(
        UnparkCommand(
          service: UnparkService(
            approve: ApproveService(
              runnerFor: runnerFor,
              now: () => DateTime.utc(2026, 9, 9, 12),
            ),
            runnerFor: runnerFor,
          ),
          workStoreRoot: workStoreRoot,
          stateRoot: () => home,
          out: out,
          err: err,
        ),
      ),
    out: out,
    err: err,
    work: work,
    state: state,
    processes: probes,
    worktrees: worktrees,
    resolvedFor: resolvedFor,
  );
}

List<String> _park({
  bool json = true,
  bool overrideLive = false,
  String actor = 'nico',
  String reason = 'operator bounce window needed',
  String until = '2026-09-16',
}) => [
  'park',
  if (json) '--json',
  if (overrideLive) '--override-live',
  '--actor',
  actor,
  '--reason',
  reason,
  '--until',
  until,
  _workBead,
];

Map<String, dynamic> _json(StringBuffer out) =>
    jsonDecode(out.toString().trim()) as Map<String, dynamic>;

void main() {
  test(
    'park performs the five mutations in order across the two stores',
    () async {
      final home = _gridHome();
      final h = _harness(home: home, stateBeads: [_sessionJson(), _gateJson()]);

      expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');

      // AC-1: five calls, in the ONE order, and nothing else mutates.
      final workMutations = [
        ...h.work.argvs.where(
          (argv) => argv.first != 'query' && argv.first != 'dep',
        ),
      ];
      expect(workMutations.map((argv) => argv.first).toList(), [
        'update',
        'update',
        'defer',
      ]);
      expect(
        h.state.argvs
            .where((argv) => argv.first != 'list')
            .map((argv) => argv.first)
            .toList(),
        ['close', 'update'],
      );
      expect(workMutations[0], containsAllInOrder(['--append-notes']));
      expect(
        workMutations[1].where((arg) => arg == '--unset-metadata').length,
        3,
      );
      expect(
        workMutations[1],
        allOf(
          contains(kApprovedAtKey),
          contains(kApprovedByKey),
          contains(kApprovedRevKey),
        ),
      );
      expect(workMutations[2], containsAllInOrder(['--until', '2026-09-16']));

      // The work bead really lost its stamp and really got deferred.
      final metadata =
          h.work.beads[_workBead]!['metadata']! as Map<String, Object?>;
      expect(metadata.keys, isNot(contains(kApprovedAtKey)));
      expect(metadata.keys, isNot(contains(kApprovedByKey)));
      expect(metadata.keys, isNot(contains(kApprovedRevKey)));
      expect(h.work.beads[_workBead]!['status'], 'deferred');
      expect(h.state.beads[_session]!['status'], 'closed');

      // The receipt says WHO, WHY, WHEN, and HOW TO UNDO — on both beads.
      final receipt = h.state.beads[_session]!['close_reason']! as String;
      expect(
        receipt,
        allOf(
          contains('nico'),
          contains(_workBead),
          contains(_session),
          contains('operator bounce window needed'),
          contains('2026-09-16'),
          contains(
            'unpark --actor nico --state-root ${p.join(home, '.grid')} '
            '$_workBead',
          ),
        ),
      );
      expect(h.work.beads[_workBead]!['notes'], receipt);
      expect(_json(h.out)['parked'], isTrue);
    },
  );

  test('void retire writes only voidRetireMetadata output', () async {
    final home = _gridHome();
    final h = _harness(home: home, stateBeads: [_sessionJson(), _gateJson()]);

    expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');

    // AC-2: the payload is the ENGINE's, key shape and receipt alike.
    final retire = h.state.argvs.lastWhere((argv) => argv.first == 'update');
    final expected = voidRetireMetadata(
      workBeadId: _workBead,
      deadSessionId: _session,
      reason: h.state.beads[_session]!['close_reason']! as String,
    );
    expect(callMetadata(retire), expected);
    expect(expected[SessionBeadKeys.workBead], voidKeyFor(_workBead, _session));
    final retired =
        h.state.beads[_session]!['metadata']! as Map<String, Object?>;
    expect(retired[SessionBeadKeys.workBead], voidKeyFor(_workBead, _session));
    expect(retired[SessionBeadKeys.voidedReason], isNotNull);
    expect(_json(h.out)['void_metadata'], expected);

    // AC-2: and grid_assets authors NO key formatter of its own.
    final source = File(
      p.join(packageRoot(), 'lib', 'src', 'filing', 'park_command.dart'),
    ).readAsStringSync();
    expect(source, contains('voidRetireMetadata'));
    expect(source, isNot(contains('#void-')));
    expect(source, isNot(contains('voidKeyFor')));
  });

  group('durable park marker', () {
    test('an open gate admits the park', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [_sessionJson(), _gateJson()],
      );

      expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');
      expect(_json(h.out)['marker'], 'open_gate');
    });

    test('a paused session admits the park with no gate at all', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [_sessionJson(pauseState: 'paused')],
      );

      expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');
      expect(_json(h.out)['marker'], 'pause_state');
    });

    test('a CLOSED gate is no marker, and neither is resumed', () async {
      for (final beads in [
        [_sessionJson(), _gateJson(status: 'closed')],
        [_sessionJson(pauseState: 'resumed')],
        [_sessionJson()],
      ]) {
        final h = _harness(home: _gridHome(), stateBeads: beads);

        expect(await h.runner.run(_park()), 1, reason: '${h.out}${h.err}');
        final report = _json(h.out);
        expect(report['parked'], isFalse);
        expect(
          report['reason'],
          allOf(
            contains('no durable park marker'),
            contains(kGateBlocksKey),
            contains(SessionBeadKeys.pauseState),
          ),
        );
        // Refused BEFORE any write: the work store saw only the exact READ,
        // the state store only its two scoped list reads.
        expect(
          h.work.argvs.map((argv) => argv.first),
          everyElement(anyOf('query', 'dep')),
        );
        expect(h.state.argvs.map((argv) => argv.first), everyElement('list'));
      }
    });

    test('a session for another work bead is not this bead\'s slot', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [
          _sessionJson(workBead: 'pow-other'),
          _gateJson(),
        ],
      );

      expect(await h.runner.run(_park()), 1);
      expect(_json(h.out)['reason'], contains('no open session'));
      expect(h.state.callsTo('close'), isEmpty);
    });
  });

  test('stale worktree without a durable marker is refused', () async {
    final h = _harness(home: _gridHome(), stateBeads: [_sessionJson()]);

    // AC-4: two days of silence is corroboration, never an accept arm.
    expect(await h.runner.run(_park()), 1);
    final report = _json(h.out);
    expect(report['parked'], isFalse);
    expect((report['worktree']! as Map)['age_hours'], 54);
    expect(report['reason'], contains('corroborates but never admits'));
    expect(h.work.callsTo('defer'), isEmpty);
    expect(h.state.callsTo('close'), isEmpty);
    expect(h.worktrees.calls, isNotEmpty);
  });

  test('a successful park reports the worktree corroboration', () async {
    final h = _harness(
      home: _gridHome(),
      stateBeads: [_sessionJson(), _gateJson()],
      activity: const WorktreeActivity.unavailable('no worktree for pow-child'),
    );

    expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');
    final worktree = _json(h.out)['worktree']! as Map<String, dynamic>;
    expect(worktree['available'], isFalse);
    expect(worktree['detail'], 'no worktree for pow-child');
    expect(
      h.state.beads[_session]!['close_reason'],
      contains('worktree activity unavailable'),
    );
  });

  group('live fence', () {
    test('a live leader refuses before any write', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [_sessionJson(pgid: 4242, pid: 4243), _gateJson()],
        processes: _FakeProcesses(
          alivePids: const {4243},
          membersByPgid: const {
            4242: [4243],
          },
        ),
      );

      expect(await h.runner.run(_park()), 1);
      final report = _json(h.out);
      expect(report['reason'], allOf(contains('LIVE'), contains('4242')));
      expect((report['live_fences']! as List).single, {
        'pgid': 4242,
        'pid': 4243,
        'leader_alive': true,
        'members': 1,
      });
      // AC-5: BOTH probes ran, leader first.
      expect(h.processes.probes, ['alive:4243', 'members:4242']);
      expect(h.work.callsTo('defer'), isEmpty);
      expect(h.state.callsTo('close'), isEmpty);
    });

    test('a dead leader over live members is still LIVE', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [_sessionJson(pgid: 77, pid: 78), _gateJson()],
        processes: _FakeProcesses(
          membersByPgid: const {
            77: [910, 911],
          },
        ),
      );

      expect(await h.runner.run(_park()), 1);
      final report = _json(h.out);
      expect(report['reason'], contains('2 group members'));
      expect((report['live_fences']! as List).single, {
        'pgid': 77,
        'pid': 78,
        'leader_alive': false,
        'members': 2,
      });
      expect(h.processes.probes, ['alive:78', 'members:77']);
      expect(h.state.callsTo('update'), isEmpty);
    });

    test('an empty group over a dead leader parks', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [_sessionJson(pgid: 77, pid: 78), _gateJson()],
      );

      expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');
      expect(h.processes.probes, ['alive:78', 'members:77']);
      expect(_json(h.out)['overrode_live'], isEmpty);
    });
  });

  group('override-live', () {
    test('waives the liveness refusal and prints what it overrode', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [_sessionJson(pgid: 4242, pid: 4243), _gateJson()],
        processes: _FakeProcesses(
          alivePids: const {4243},
          membersByPgid: const {
            4242: [4243, 4244],
          },
        ),
      );

      expect(
        await h.runner.run(_park(overrideLive: true)),
        0,
        reason: '${h.out}${h.err}',
      );
      final report = _json(h.out);
      expect(report['parked'], isTrue);
      expect((report['overrode_live']! as List).single, {
        'pgid': 4242,
        'pid': 4243,
        'leader_alive': true,
        'members': 2,
      });
      expect(
        h.state.beads[_session]!['close_reason'],
        allOf(
          contains('OVERRODE LIVE'),
          contains('pgid 4242'),
          contains('2 group members'),
        ),
      );
    });

    test('cannot waive a missing durable marker', () async {
      final h = _harness(
        home: _gridHome(),
        stateBeads: [_sessionJson(pgid: 4242, pid: 4243)],
        processes: _FakeProcesses(alivePids: const {4243}),
      );

      expect(await h.runner.run(_park(overrideLive: true)), 1);
      expect(_json(h.out)['reason'], contains('no durable park marker'));
      expect(h.work.callsTo('update'), isEmpty);
      expect(h.state.callsTo('close'), isEmpty);
    });
  });

  test('park writes only work fields to work store and session fields to '
      'state store', () async {
    final home = _gridHome();
    final h = _harness(
      home: home,
      stateBeads: [
        _sessionJson(pauseState: 'paused'),
        _gateJson(),
      ],
    );

    expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');

    // AC-7: the A37 split, argv by argv.
    for (final argv in h.work.argvs.where(
      (argv) => const {'update', 'defer'}.contains(argv.first),
    )) {
      expect(argv, isNot(contains(_session)), reason: '$argv');
      expect(argv[1], _workBead, reason: '$argv');
    }
    for (final argv in h.state.argvs.where((argv) => argv.first != 'list')) {
      expect(argv[1], _session, reason: '$argv');
    }
    // The pause marker is the resident command handler's to write. Park READS
    // it and never touches it, in either store.
    for (final argv in [...h.work.argvs, ...h.state.argvs]) {
      expect(
        argv.any((arg) => arg.contains(SessionBeadKeys.pauseState)),
        isFalse,
        reason: '$argv',
      );
    }
    expect(
      (h.state.beads[_session]!['metadata']!
          as Map)[SessionBeadKeys.pauseState],
      'paused',
    );
  });

  test('a refused mutation stops the ritual and is never a park', () async {
    final home = _gridHome();
    final h = _harness(home: home, stateBeads: [_sessionJson(), _gateJson()]);
    // The state store's FIRST mutation is the session close.
    h.state.failAt = 0;
    h.state.failWith = 'bd: close refused';

    expect(await h.runner.run(_park()), 1);
    final report = _json(h.out);
    expect(report['parked'], isFalse);
    expect(report['failed_step'], 'close_session');
    expect(report['failed_store'], 'state');
    expect(report['completed'], ['note', 'unstamp', 'defer']);
    expect(report['reason'], contains('bd: close refused'));
    // The void retire never ran, so nothing claims a retired join key.
    expect(h.state.callsTo('update'), isEmpty);
  });

  test('unpark clears defer date then delegates to ApproveService', () async {
    final home = _gridHome();
    final h = _harness(
      home: home,
      workBead: _workBeadJson(approved: false, status: 'deferred'),
    );
    h.work.beads[_workBead]!['defer_until'] = '2026-09-16T00:00:00.000Z';

    expect(
      await h.runner.run(['unpark', '--json', '--actor', 'nico', _workBead]),
      0,
      reason: '${h.out}${h.err}',
    );

    // AC-8: undefer FIRST, then exactly one stamped update.
    expect(h.work.argvs.map((argv) => argv.first), [
      'query',
      'dep',
      'undefer',
      'query',
      'dep',
      'update',
    ]);
    expect(h.work.callsTo('undefer').single, [
      'undefer',
      _workBead,
      '--json',
      '--actor',
      'nico',
    ]);
    expect(h.work.beads[_workBead]!['status'], 'open');
    expect(h.work.beads[_workBead]!['defer_until'], isNull);
    expect(callMetadata(h.work.callsTo('update').single).keys, {
      kApprovedByKey,
      kApprovedAtKey,
      kApprovedRevKey,
    });
    final report = _json(h.out);
    expect(report['unparked'], isTrue);
    expect(report['undeferred'], isTrue);
    expect(report['by'], 'nico');
  });

  test('a refused approval leaves unpark honest about the stamp', () async {
    final home = _gridHome();
    final h = _harness(
      home: home,
      // No validation plan ⇒ the preflight fails a row and refuses.
      workBead: {
        ..._workBeadJson(approved: false, status: 'deferred'),
        'metadata': <String, Object?>{},
      },
    );

    expect(
      await h.runner.run(['unpark', '--json', '--actor', 'nico', _workBead]),
      1,
    );
    final report = _json(h.out);
    expect(report['unparked'], isFalse);
    expect(report['undeferred'], isTrue);
    expect(report['reason'], contains('remains UNSTAMPED'));
    expect(h.work.callsTo('undefer'), hasLength(1));
    expect(h.work.callsTo('update'), isEmpty);
  });

  test('an unknown bead is refused before bd undefer runs', () async {
    final h = _harness(home: _gridHome());
    h.work.beads.clear();

    expect(await h.runner.run(['unpark', '--actor', 'nico', _workBead]), 1);
    expect(h.out.toString(), contains('not found'));
    expect(h.work.callsTo('undefer'), isEmpty);
  });

  test(
    'commands resolve work store callback and state-root grid home',
    () async {
      final home = _gridHome();
      final h = _harness(home: home, stateBeads: [_sessionJson(), _gateJson()]);

      // AC-9: usage refusals spawn nothing AND never resolve a work store.
      expect(await h.runner.run(['park', '--actor', 'nico', _workBead]), 64);
      expect(h.err.toString(), contains('--reason'));
      expect(
        await h.runner.run([
          'park',
          '--actor',
          'nico',
          '--reason',
          'why',
          _workBead,
        ]),
        64,
      );
      expect(h.err.toString(), contains('--until'));
      expect(
        await h.runner.run([
          'park',
          '--reason',
          'why',
          '--until',
          'x',
          _workBead,
        ]),
        64,
      );
      expect(h.err.toString(), contains('--actor'));
      expect(await h.runner.run(['unpark', _workBead]), 64);
      expect(await h.runner.run(['park', ..._park().skip(1).take(0)]), 64);
      expect(h.work.argvs, isEmpty);
      expect(h.state.argvs, isEmpty);
      expect(h.resolvedFor, isEmpty);

      // The prefix-aware callback is handed the PARSED work id, once per run.
      expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');
      expect(h.resolvedFor, [_workBead]);
      // And the grid HOME resolved to its own `.grid` state store.
      expect(h.worktrees.calls.single, '${p.join(home, '.grid')}:$_workBead');
    },
  );

  test('an unrelated state root refuses park before any read', () async {
    final unrelated = Directory.systemTemp.createTempSync('not-a-grid-home-');
    addTearDown(() => unrelated.deleteSync(recursive: true));
    final h = _harness(home: _gridHome(), stateBeads: [_sessionJson()]);

    expect(
      await h.runner.run([..._park(), '--state-root', unrelated.path]),
      64,
    );
    expect(h.err.toString(), allOf(contains('.grid'), contains('.beads')));
    expect(h.work.argvs, isEmpty);
    expect(h.state.argvs, isEmpty);
  });

  test('a park with no grid home at all refuses loudly', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(ParkCommand(out: out, err: err));

    expect(await runner.run(_park()), 64);
    expect(err.toString(), contains('--state-root'));
  });

  test('both new verbs register the ONE shared state-root seam', () {
    final park = ParkCommand(out: StringBuffer(), err: StringBuffer());
    final unpark = UnparkCommand(out: StringBuffer(), err: StringBuffer());
    final reference = ArgParser();
    addStateRootOption(reference);

    for (final parser in [park.argParser, unpark.argParser]) {
      expect(parser.options[kStateRootOption]?.help, kStateRootHelp);
    }
    expect(
      kStateRootHelp,
      'The grid home whose .grid/.beads holds the cross-store link and '
      'session-lifecycle state beads.',
    );
    expect(reference.options[kStateRootOption]?.help, kStateRootHelp);
    expect(
      park.invocation,
      'park --actor <name> --reason <text> --until <date> [--override-live] '
      '[--json] [--state-root <grid-home>] <work-bead-id>',
    );
    expect(
      unpark.invocation,
      'unpark --actor <name> [--json] [--state-root <grid-home>] '
      '<work-bead-id>',
    );
  });

  test('park then unpark restores mount eligibility', () async {
    final home = _gridHome();
    final h = _harness(home: home, stateBeads: [_sessionJson(), _gateJson()]);

    expect(await h.runner.run(_park()), 0, reason: '${h.out}${h.err}');
    expect(
      await h.runner.run(['unpark', '--actor', 'nico', _workBead]),
      0,
      reason: '${h.out}${h.err}',
    );

    // AC-10: the round trip ends mountable again.
    final bead = Bead.fromJson(h.work.beads[_workBead]!);
    expect(bead.status, BeadStatus.open);
    expect(bead.deferUntil, isNull);
    final stamp = ApprovalStamp.tryParse(bead);
    expect(stamp, isNotNull);
    expect(stamp!.by, 'nico');
    expect(stamp.at, '2026-09-09T12:00:00.000Z');
    expect(mountEligibilityDecision(bead), isA<MountEligible>());
    // And the retired session keeps ONLY the engine-authored join key.
    final session = Bead.fromJson(h.state.beads[_session]!);
    expect(session.isClosed, isTrue);
    expect(projectSession(session).workBeadId, voidKeyFor(_workBead, _session));
  });

  group('FileSystemWorktreeActivityProbe', () {
    test('reads the newest non-.git descendant write', () async {
      final home = Directory.systemTemp.createTempSync('probe-home-');
      addTearDown(() => home.deleteSync(recursive: true));
      final store = p.join(home.path, '.grid');
      final tree = Directory(
        p.join(store, 'worktrees', 'power_station', _workBead),
      )..createSync(recursive: true);
      final work = File(p.join(tree.path, 'lib', 'a.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// work');
      work.setLastModifiedSync(DateTime.utc(2026, 9, 7, 4));
      final git = File(p.join(tree.path, '.git', 'HEAD'))
        ..createSync(recursive: true)
        ..writeAsStringSync('ref: refs/heads/x');
      git.setLastModifiedSync(DateTime.utc(2026, 9, 9, 3));
      final activity = await FileSystemWorktreeActivityProbe(
        now: () => DateTime.utc(2026, 9, 9, 10),
      ).probe(stateStoreRoot: store, workBeadId: _workBead);

      expect(activity.available, isTrue);
      expect(activity.lastWrite, DateTime.utc(2026, 9, 7, 4));
      expect(activity.age, const Duration(hours: 54));
      expect(activity.describe(), contains('54h ago'));
    });

    test('an absent worktree is unavailable, never quiet', () async {
      final home = Directory.systemTemp.createTempSync('probe-home-');
      addTearDown(() => home.deleteSync(recursive: true));
      final store = p.join(home.path, '.grid');
      Directory(p.join(store, 'worktrees')).createSync(recursive: true);

      final activity = await const FileSystemWorktreeActivityProbe().probe(
        stateStoreRoot: store,
        workBeadId: _workBead,
      );

      expect(activity.available, isFalse);
      expect(activity.toJson()['detail'], contains('no worktree'));
    });
  });
}

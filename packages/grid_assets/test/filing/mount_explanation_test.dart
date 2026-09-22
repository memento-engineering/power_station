// The MOUNT EXPLAINER — the ten offline preconditions, their remedies, and the
// seams it shares with `filing`.
//
// THE CAP BOUNDARY this bead had to settle first, stated once, here, so the
// answer is not re-derived:
//
//   Cap boundary: verdict cap is STORE state, derived from durable
//   session/step beads and supersedes edges; mount-attempt cap is STORE state,
//   carried by type=mount-attempt grid.attempt.* metadata. Neither named cap is
//   engine-only. Engine-only session-mint and step-successor retry counters are
//   outside the named caps and remain covered by live_admission=UNCHECKED. The
//   current resident remedy for an exhausted mount-attempt record is
//   bead rearm.
//
// Scripted rather than real-bd for everything but AC-5 and AC-8: what is
// asserted here is the ROW SET, the classifications and the exact argv the verb
// spawns, and a Fake is the only way to hold a twin mint, an anomalous open
// tombstone and an exhausted verdict budget still enough to read them.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';
import 'filing_evidence_fakes.dart';
import 'real_bd_store.dart';

const String _beadId = 'pow-child';
const String _workRoot = '/work/power_station';
const String _emptyEnvelope = '{"schema_version":1,"data":[]}';

/// A UTC instant every clock-reading row is evaluated against.
final DateTime _now = DateTime.utc(2026, 9, 14, 12);

String _envelope(List<Map<String, Object?>> data) =>
    jsonEncode({'schema_version': 1, 'data': data});

/// One recorded bd spawn: WHICH store root, and the exact argv.
final class _Call {
  const _Call(this.root, this.argv);

  final String root;
  final List<String> argv;
}

/// Replies per store root and records every spawn, so a run can prove the verb
/// wrote nothing and reached no store it was not given.
///
/// A null reply is a REFUSING bd (exit 1) — how the fail-closed arms are
/// reached without a real broken store.
final class _Bd {
  final List<_Call> calls = [];
  final Map<String, String? Function(List<String> argv)> replies = {};

  BdRunner Function(String storeRoot) get runnerFor =>
      (root) => _Runner(root, this);

  List<List<String>> argvFor(String root) => [
    for (final call in calls)
      if (call.root == root) call.argv,
  ];
}

final class _Runner implements BdRunner {
  _Runner(this._root, this._bd);

  final String _root;
  final _Bd _bd;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    _bd.calls.add(_Call(_root, args));
    final reply = _bd.replies[_root];
    final body = reply == null ? _emptyEnvelope : reply(args);
    if (body == null) {
      return BdResult(
        exitCode: 1,
        stdout: '',
        stderr: 'store $_root refused the read',
      );
    }
    return BdResult(exitCode: 0, stdout: body, stderr: '');
  }
}

/// A [ShellRunner] answering every `decisions index` ask with one canned
/// envelope — the roster the DEFAULT mount composition executes through.
final class _CannedIndexShell implements ShellRunner {
  _CannedIndexShell(this.body);

  final String body;

  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
  }) async => ShellRunResult(exitCode: 0, output: body);
}

// ── fixtures ────────────────────────────────────────────────────────────────

/// A git-sha-shaped approval revision — the legacy arm `ApprovalStamp` still
/// accepts, so a fixture need not recompute a filing digest to be stamped.
const Map<String, Object?> _stamped = {
  kApprovedByKey: 'nico',
  kApprovedAtKey: '2026-09-13T00:00:00.000Z',
  kApprovedRevKey: 'abc1234',
};

/// A RETIRED filing receipt — complete and well-formed in every part, minted
/// under a basis scheme version nothing re-derives.
const String _retiredRev =
    'filing:v1:sha256:e6635f6c8a3307a33271500460a95c176baa'
    'adaf11f3a479663ae534aa33d52c';

/// That receipt on an otherwise mountable bead.
Map<String, Object?> _retiredStampBead() => _workBead(
  metadata: <String, Object?>{
    'validation_plan': 'dart test',
    ..._stamped,
    kApprovedRevKey: _retiredRev,
  },
);

Map<String, Object?> _workBead({
  String id = _beadId,
  String type = 'task',
  String status = 'open',
  String acceptance = '- [ ] the outcome',
  Map<String, Object?> metadata = const {
    'validation_plan': 'dart test',
    ..._stamped,
  },
  List<String> blockers = const [],
  String? deferUntil,
}) => {
  'id': id,
  'title': 'a bead',
  'issue_type': type,
  'status': status,
  'acceptance_criteria': acceptance,
  'metadata': metadata,
  if (deferUntil != null) 'defer_until': deferUntil,
  'dependencies': [
    for (final blocker in blockers)
      {'issue_id': id, 'depends_on_id': blocker, 'type': 'blocks'},
  ],
};

Map<String, Object?> _target(String id, {String status = 'closed'}) => {
  'id': id,
  'title': 'a blocker',
  'issue_type': 'task',
  'status': status,
};

Map<String, Object?> _session(
  String id, {
  required String workBead,
  bool closed = false,
  Map<String, Object?> metadata = const {},
}) => {
  'id': id,
  'title': 'session $id',
  'issue_type': 'session',
  'status': closed ? 'closed' : 'open',
  'metadata': {SessionBeadKeys.workBead: workBead, ...metadata},
};

Map<String, Object?> _step(
  String id, {
  required String session,
  required String path,
  bool graded = true,
  String? supersedes,
}) => {
  'id': id,
  'title': 'step $id',
  'issue_type': 'step',
  'status': 'closed',
  'metadata': {
    MoleculeStepKeys.session: session,
    MoleculeStepKeys.path: path,
    if (graded) '${ResultKeys.prefix}$path.${ResultKeys.grade}': 'A',
  },
  'dependencies': [
    if (supersedes != null)
      {'issue_id': id, 'depends_on_id': supersedes, 'type': 'supersedes'},
  ],
};

Map<String, Object?> _attempt(
  String id, {
  required String workBead,
  required int count,
}) => {
  'id': id,
  'title': 'attempts for $workBead',
  'issue_type': 'mount-attempt',
  'status': 'open',
  'metadata': {
    MountAttemptKeys.workBead: workBead,
    MountAttemptKeys.count: '$count',
  },
};

/// The rows of one `bd --json` body, whichever shape the binary emitted: the
/// `{schema_version, data}` envelope under `BD_JSON_ENVELOPE=1`, or the bare
/// list without it.
List<Map<String, dynamic>> _rowsOf(String body) {
  final decoded = jsonDecode(body);
  final rows = decoded is Map<String, dynamic> ? decoded['data'] : decoded;
  return (rows as List).cast<Map<String, dynamic>>();
}

/// A REAL grid home — `<home>/.grid/.beads` — because `resolveStateRoot` probes
/// the filesystem to tell a home from its own state store.
String _gridHome() {
  final home = Directory.systemTemp.createTempSync('mount-grid-home-');
  Directory(p.join(home.path, '.grid', '.beads')).createSync(recursive: true);
  addTearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });
  return home.path;
}

/// A directory holding NEITHER `.grid` nor `.beads`.
String _unrelatedRoot() {
  final root = Directory.systemTemp.createTempSync('mount-not-a-home-');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  return root.path;
}

/// The scripted harness: `mount` AND `filing` over ONE store pair, so a probe
/// can compare the two verbs' answers about the same rows.
final class _Harness {
  _Harness({
    Map<String, Object?>? bead,
    List<Map<String, Object?>> targets = const [],
    List<Map<String, Object?>> sessions = const [],
    Map<String, List<Map<String, Object?>>> steps =
        const <String, List<Map<String, Object?>>>{},
    List<Map<String, Object?>> attempts = const [],
    Set<String>? armed,
    bool stateStore = true,
    bool stateRefuses = false,
    bool targetQueryRefuses = false,
    DateTime? now,
  }) {
    final record = bead ?? _workBead();
    home = stateStore ? _gridHome() : null;
    stateRoot = home == null ? null : p.join(home!, '.grid');
    bd.replies[_workRoot] = (argv) {
      if (argv.first != 'query') return _emptyEnvelope;
      if (argv[1] == 'id=${record['id']}') return _envelope([record]);
      if (targetQueryRefuses) return null;
      return _envelope(targets);
    };
    if (stateRoot case final root?) {
      bd.replies[root] = (argv) {
        if (stateRefuses) return null;
        if (argv.first != 'list') return _emptyEnvelope;
        final type = argv[argv.indexOf('-t') + 1];
        switch (type) {
          case 'session':
            return _envelope(sessions);
          case 'step':
            final field = argv[argv.indexOf('--metadata-field') + 1];
            final sessionId = field.split('=').last;
            return _envelope(steps[sessionId] ?? const []);
          case 'mount-attempt':
            return _envelope(attempts);
          default:
            return _emptyEnvelope;
        }
      };
    }
    // These tests isolate MOUNT STATE, over fake stores at paths no shell can
    // chdir into. ONE prepared gather is shared by both verbs, so the embedded
    // report stays byte-identical to `filing --json` while the six viability
    // rows stay out of this suite's way; their refusals are pinned in
    // `filing_viability_test.dart`, and the LIVE default composition has its
    // own test below.
    final evidence = FakeFilingEvidenceSource(completeEmptyEvidence);
    final service = MountExplanationService(
      runnerFor: bd.runnerFor,
      now: () => now ?? _now,
      evidence: evidence,
    );
    runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        MountCommand(
          service: service,
          storeRoot: () => _workRoot,
          stateRoot: () => home,
          armedSubstations: () => armed,
          out: out,
          err: err,
        ),
      )
      ..addCommand(
        FilingCommand(
          service: FilingService(
            source: ExactSubstationBeadSource(runnerFor: bd.runnerFor),
            evidence: evidence,
            advisory: FakeFilingAdvisory(),
          ),
          storeRoot: () => _workRoot,
          armedSubstations: () => armed,
          out: filingOut,
          err: err,
        ),
      );
  }

  final _Bd bd = _Bd();
  final StringBuffer out = StringBuffer();
  final StringBuffer filingOut = StringBuffer();
  final StringBuffer err = StringBuffer();
  late final CommandRunner<int> runner;
  late final String? home;
  late final String? stateRoot;

  Future<int> mount({List<String> extra = const []}) =>
      runner.run(['mount', '--json', ...extra, _beadId]).then((c) => c ?? 0);

  Future<int> mountPlain() =>
      runner.run(['mount', _beadId]).then((code) => code ?? 0);

  Future<int> filing() =>
      runner.run(['filing', '--json', _beadId]).then((code) => code ?? 0);

  Map<String, dynamic> get report =>
      jsonDecode(out.toString()) as Map<String, dynamic>;

  List<Map<String, dynamic>> get rows => (report['preconditions'] as List)
      .cast<Map<String, dynamic>>()
      .toList(growable: false);

  Map<String, dynamic> row(MountPrecondition precondition) =>
      rows.singleWhere((row) => row['precondition'] == precondition.wire);

  String outcomeOf(MountPrecondition precondition) =>
      row(precondition)['outcome'] as String;
}

void main() {
  group('AC-1 — the row set is the answer', () {
    test('ten bounded rows in one order, each with a detail and — only when '
        'it does not pass — a remedy', () async {
      final h = _Harness();

      expect(await h.mount(), 2, reason: '${h.out}${h.err}');

      expect(h.rows.map((row) => row['precondition']), [
        for (final precondition in MountPrecondition.values) precondition.wire,
      ]);
      expect(h.rows, hasLength(10));
      expect(
        h.rows.map((row) => row['precondition']),
        isNot(contains('local_blockers')),
      );
      expect(
        h.rows.map((row) => row['precondition']),
        isNot(contains('cross_store_blockers')),
      );
      for (final row in h.rows) {
        expect(row['outcome'], isIn(const ['PASS', 'BLOCKED', 'UNCHECKED']));
        expect((row['detail'] as String).trim(), isNotEmpty);
        if (row['outcome'] == 'PASS') {
          expect(
            row.containsKey('remedy'),
            isFalse,
            reason: '${row['precondition']} passes and has nothing to remedy',
          );
        } else {
          expect((row['remedy'] as String).trim(), isNotEmpty);
        }
      }
      // The aggregate is the fail-closed one: `live_admission` is never asked,
      // so a bead with nine green rows is UNCHECKED, never PASS.
      expect(h.report['verdict'], 'UNCHECKED');
      expect(h.outcomeOf(MountPrecondition.liveAdmission), 'UNCHECKED');
      expect(
        jsonEncode(h.report).length,
        lessThan(kBoundedOutputCapBytes),
        reason: 'the structured rendering is bounded',
      );
    });

    test('the row constructor REFUSES a row that would leave the dance in '
        "the operator's head", () {
      expect(
        () => MountPreconditionRow(
          precondition: MountPrecondition.deferState,
          outcome: MountOutcome.pass,
          detail: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => MountPreconditionRow(
          precondition: MountPrecondition.deferState,
          outcome: MountOutcome.blocked,
          detail: 'deferred',
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'a BLOCKED row without a remedy is the whole defect',
      );
      expect(
        () => MountPreconditionRow(
          precondition: MountPrecondition.deferState,
          outcome: MountOutcome.unchecked,
          detail: 'not asked',
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'an UNCHECKED row names where to ask',
      );
      expect(
        () => MountPreconditionRow(
          precondition: MountPrecondition.deferState,
          outcome: MountOutcome.pass,
          detail: 'not deferred',
          remedy: 'unpark',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => MountPreconditionRow(
          precondition: MountPrecondition.dependencies,
          outcome: MountOutcome.pass,
          detail: 'rows',
          evidence: const ['pow-x'],
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'evidence that can be withheld names the read that returns it',
      );
    });

    test('an unknown bead REFUSES with no green rows', () async {
      final h = _Harness(bead: _workBead(id: 'pow-other'));

      expect(await h.mount(), 1);
      expect(h.rows, isEmpty);
      expect(h.report['error'], 'bead not found');
      expect(h.report['verdict'], 'BLOCKED');
      expect(
        (h.report['filing'] as Map<String, dynamic>)['error'],
        'bead not found',
      );
    });

    test(
      'the plain rendering carries the same rows, then the remedies',
      () async {
        final h = _Harness(bead: _workBead(type: 'epic'));

        expect(await h.mountPlain(), 1);
        final plain = h.out.toString();
        expect(plain, startsWith('MOUNT $_beadId: BLOCKED'));
        for (final precondition in MountPrecondition.values) {
          expect(plain, contains('${precondition.wire}:'));
        }
        expect(
          plain,
          contains('BLOCKED driveable_type: epic is not driveable'),
        );
        expect(plain, contains('REMEDY driveable_type: '));
        expect(
          plain.indexOf('REMEDY driveable_type'),
          greaterThan(plain.indexOf('UNCHECKED live_admission')),
          reason: 'ordered rows FIRST, then the remedy lines',
        );
      },
    );
  });

  group('AC-2 — the filing report rides out whole', () {
    test('the embedded report is byte-identical to `filing --json`', () async {
      final h = _Harness(bead: _workBead(blockers: const ['pow-blocker']));

      expect(await h.mount(), 2, reason: '${h.out}${h.err}');
      expect(await h.filing(), 0, reason: '${h.filingOut}${h.err}');

      final embedded = h.report['filing'] as Map<String, dynamic>;
      final direct = jsonDecode(h.filingOut.toString()) as Map<String, dynamic>;
      // The mount explainer is an EXPLAINER, not a stamp moment: it answers
      // the TEN MECHANICAL ROWS and spends no inference, so its embedded
      // report carries no advisory member at all. Strip the one member the
      // `filing` VERB adds and the two reports are byte-identical.
      expect(embedded.containsKey('advisory'), isFalse);
      expect(direct.remove('advisory'), isNotNull);
      expect(jsonEncode(embedded), jsonEncode(direct));
      // WHOLE means all ELEVEN: mount renders the four clauses it owns, and
      // carries the six VIABILITY rows and the CONTENT row out untouched
      // rather than dropping the half of the contract it has no precondition
      // for.
      expect(
        (embedded['requirements'] as List).map((row) => row['requirement']),
        [for (final value in FilingRequirement.values) value.wire],
      );
      expect((embedded['requirements'] as List), hasLength(11));
      // And the first three mount rows RENDER those very details.
      for (final requirement in const [
        'driveable_type',
        'validation_plan',
        'acceptance_criteria',
      ]) {
        final filingRow = (embedded['requirements'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((row) => row['requirement'] == requirement);
        final mountRow = h.rows.singleWhere(
          (row) => row['precondition'] == requirement,
        );
        expect(
          mountRow['detail'],
          startsWith(filingRow['detail'] as String),
          reason: '$requirement renders the filing detail, never a paraphrase',
        );
      }
    });

    test('the field rows are the SOLE eligibility predicate, called once', () {
      final source = File(
        p.join(packageRoot(), 'lib', 'src', 'filing', 'mount_explanation.dart'),
      ).readAsStringSync();
      final predicate = File(
        p.join(packageRoot(), 'lib', 'src', 'code', 'mount_eligibility.dart'),
      ).readAsStringSync();

      expect(
        'List<String> mountEligibilityFindings('.allMatches(predicate).length,
        1,
        reason: 'ONE definition of the predicate, and it is not in this verb',
      );
      expect(
        source,
        isNot(contains('List<String> mountEligibilityFindings(')),
        reason: 'the explainer mints no second completeness predicate',
      );
      expect(
        'mountEligibilityFindings('.allMatches(source).length,
        1,
        reason: 'the explainer CALLS it exactly once per evaluation',
      );
      // It never re-runs filing either: the report it renders is handed in.
      expect(source, isNot(contains('FilingContract()')));
      expect(source, isNot(contains('.evaluate(bead,')));
    });

    test(
      'a bead refused by the predicate is BLOCKED on the named clause',
      () async {
        final h = _Harness(
          bead: _workBead(
            type: 'epic',
            acceptance: '   ',
            metadata: const <String, Object?>{},
          ),
        );

        expect(await h.mount(), 1);
        expect(h.outcomeOf(MountPrecondition.driveableType), 'BLOCKED');
        expect(h.outcomeOf(MountPrecondition.validationPlan), 'BLOCKED');
        expect(h.outcomeOf(MountPrecondition.acceptanceCriteria), 'BLOCKED');
        expect(h.outcomeOf(MountPrecondition.approvalStamp), 'BLOCKED');
        expect(
          h.row(MountPrecondition.approvalStamp)['detail'],
          contains(kApprovedRevKey),
        );
        expect(
          h.row(MountPrecondition.approvalStamp)['remedy'],
          contains('approve --actor <actor> --json $_beadId'),
        );
        expect(
          h.row(MountPrecondition.acceptanceCriteria)['remedy'],
          contains('--acceptance'),
        );
      },
    );

    test('AC-2: a RETIRED approval receipt is BLOCKED as STALE, named and '
        'remedied in both renderings', () async {
      final json = _Harness(bead: _retiredStampBead());

      expect(await json.mount(), 1, reason: '${json.out}${json.err}');
      expect(json.outcomeOf(MountPrecondition.approvalStamp), 'BLOCKED');
      final row = json.row(MountPrecondition.approvalStamp);
      // STALE, not "not approved": a governor DID approve this bead, and the
      // retired revision it was approved against is named in full so the
      // operator can see which receipt the sweep is replacing.
      expect(row['detail'], startsWith('approval: stale'));
      expect(row['detail'], contains(_retiredRev));
      expect(
        row['remedy'],
        contains('approve --actor <actor> --json $_beadId'),
      );

      // The plain rendering carries the same three facts — an operator who
      // never passes --json is not told less.
      final plain = _Harness(bead: _retiredStampBead());
      expect(await plain.mountPlain(), 1, reason: '${plain.out}${plain.err}');
      final text = plain.out.toString();
      expect(text, contains('BLOCKED approval_stamp: approval: stale'));
      expect(text, contains(_retiredRev));
      expect(
        text,
        contains(
          'REMEDY approval_stamp: approve --actor <actor> --json '
          '$_beadId',
        ),
      );
    });
  });

  group('AC-3 — the rows over durable state', () {
    test('dependencies names every row, and blocks on an OPEN local '
        'target', () async {
      final h = _Harness(
        bead: _workBead(
          blockers: const ['pow-open', 'pow-done', 'external:the_grid:tg-1'],
        ),
        targets: [
          _target('pow-open', status: 'open'),
          _target('pow-done'),
        ],
        armed: const {'the_grid'},
      );

      expect(await h.mount(), 1, reason: '${h.out}${h.err}');
      final row = h.row(MountPrecondition.dependencies);
      expect(row['outcome'], 'BLOCKED');
      expect(
        row['detail'],
        startsWith(
          'bd dependency rows: pow-done, pow-open, '
          'external:the_grid:tg-1 (armed)',
        ),
        reason: 'the retained projection detail comes FIRST, verbatim',
      );
      expect(row['detail'], contains('still OPEN locally: pow-open'));
      expect(row['evidence'], const ['pow-open']);
      expect(row['remedy'], contains('dep remove $_beadId <target>'));
    });

    test('dependencies PASSES only when every local target is closed and '
        'every external row is armed', () async {
      final h = _Harness(
        bead: _workBead(blockers: const ['pow-done', 'external:the_grid:tg-1']),
        targets: [_target('pow-done')],
        armed: const {'the_grid'},
      );

      expect(await h.mount(), 2, reason: '${h.out}${h.err}');
      final row = h.row(MountPrecondition.dependencies);
      expect(row['outcome'], 'PASS');
      expect(row['detail'], contains('every local target is closed: pow-done'));
      expect(row.containsKey('remedy'), isFalse);
    });

    test(
      'dependencies BLOCKS on an external row the roster cannot arm',
      () async {
        final h = _Harness(
          bead: _workBead(blockers: const ['external:nowhere:tg-1']),
          armed: const {'the_grid'},
        );

        expect(await h.mount(), 1);
        final row = h.row(MountPrecondition.dependencies);
        expect(row['outcome'], 'BLOCKED');
        expect(row['detail'], contains('which this station does not arm'));
        expect(row['remedy'], contains('arm the substation "nowhere"'));
      },
    );

    test(
      'no linked session PASSES, and one open bare-key session ADOPTS',
      () async {
        final none = _Harness();
        expect(await none.mount(), 2);
        expect(none.outcomeOf(MountPrecondition.sessionOccupancy), 'PASS');
        expect(
          none.row(MountPrecondition.sessionOccupancy)['detail'],
          contains('no session row links $_beadId'),
        );

        final adopt = _Harness(sessions: [_session('s1', workBead: _beadId)]);
        expect(await adopt.mount(), 2);
        expect(adopt.outcomeOf(MountPrecondition.sessionOccupancy), 'PASS');
        expect(
          adopt.row(MountPrecondition.sessionOccupancy)['detail'],
          contains('one open session (s1)'),
        );
      },
    );

    test('TWIN OPENS block and name every rival', () async {
      final h = _Harness(
        sessions: [
          _session('s1', workBead: _beadId),
          _session('s2', workBead: _beadId),
        ],
      );

      expect(await h.mount(), 1);
      final row = h.row(MountPrecondition.sessionOccupancy);
      expect(row['outcome'], 'BLOCKED');
      expect(row['detail'], contains('TWIN MINT: 2 open rows'));
      expect(row['detail'], allOf(contains('s1'), contains('s2')));
      expect(row['remedy'], contains('the GOVERNOR resolves it'));
      expect(row['remedy'], contains('park --actor'));
    });

    test('an ANOMALOUS OPEN TOMBSTONE blocks with its literal key — the state '
        'that blocks re-mount indefinitely', () async {
      final h = _Harness(
        sessions: [_session('s9', workBead: '$_beadId#void-s8')],
      );

      expect(await h.mount(), 1);
      final row = h.row(MountPrecondition.sessionOccupancy);
      expect(row['outcome'], 'BLOCKED');
      expect(row['detail'], contains('"$_beadId#void-s8"'));
      expect(row['remedy'], contains('park --actor'));
    });

    test('each BLOCKING terminal disposition is told apart, with its own '
        'remedy', () async {
      final done = _Harness(
        sessions: [
          _session(
            's1',
            workBead: _beadId,
            closed: true,
            metadata: const {SessionBeadKeys.outcome: kSessionOutcomeComplete},
          ),
        ],
      );
      expect(await done.mount(), 1);
      expect(done.outcomeOf(MountPrecondition.sessionOccupancy), 'BLOCKED');
      expect(
        done.row(MountPrecondition.sessionOccupancy)['detail'],
        contains('DELIVERED positive terminal'),
      );
      expect(
        done.row(MountPrecondition.sessionOccupancy)['remedy'],
        contains('close $_beadId'),
      );

      final held = _Harness(
        sessions: [
          _session(
            's1',
            workBead: _beadId,
            closed: true,
            metadata: const {SessionBeadKeys.escalation: 'breaker'},
          ),
        ],
      );
      expect(await held.mount(), 1);
      expect(
        held.row(MountPrecondition.sessionOccupancy)['detail'],
        contains('HELD for a human'),
      );
      expect(
        held.row(MountPrecondition.sessionOccupancy)['remedy'],
        contains('rework --note'),
      );

      final paused = _Harness(
        sessions: [
          _session(
            's1',
            workBead: _beadId,
            metadata: const {SessionBeadKeys.pauseState: 'paused'},
          ),
        ],
      );
      expect(await paused.mount(), 1);
      expect(
        paused.row(MountPrecondition.sessionOccupancy)['detail'],
        contains('operator-PAUSED'),
      );
      expect(
        paused.row(MountPrecondition.sessionOccupancy)['remedy'],
        contains('resume $_beadId'),
      );
    });

    test('terminal dead-key surplus PASSES and reads as history', () async {
      final h = _Harness(
        sessions: [
          // Closed mid-flight with an empty cursor: a DEAD KEY, never blocking.
          _session('s1', workBead: _beadId, closed: true),
          _session('s0', workBead: _beadId, closed: true),
          // A retired round keys to itself and is literal history.
          _session('sr', workBead: '$_beadId#r1', closed: true),
        ],
      );

      expect(await h.mount(), 2, reason: '${h.out}${h.err}');
      final row = h.row(MountPrecondition.sessionOccupancy);
      expect(row['outcome'], 'PASS');
      expect(row['detail'], contains('terminal, non-blocking DEAD KEY'));
      expect(
        row['detail'],
        contains('1 terminal dead-key row(s) remain history'),
      );
      expect(
        row['evidence'],
        contains('sr work_bead=$_beadId#r1 closed voided'),
      );
    });

    test('a DEFERRED bead blocks, and unpark is the remedy', () async {
      final h = _Harness(
        bead: _workBead(
          status: 'deferred',
          deferUntil: '2026-09-15T00:00:00.000Z',
        ),
      );

      expect(await h.mount(), 1);
      final row = h.row(MountPrecondition.deferState);
      expect(row['outcome'], 'BLOCKED');
      expect(row['detail'], contains('status=deferred'));
      expect(row['detail'], contains('2026-09-15T00:00:00.000Z'));
      expect(row['remedy'], contains('unpark --actor <actor> $_beadId'));
    });

    test('a PAST defer date on an open bead is not a hold', () async {
      final h = _Harness(
        bead: _workBead(deferUntil: '2026-09-13T00:00:00.000Z'),
      );

      expect(await h.mount(), 2);
      expect(h.outcomeOf(MountPrecondition.deferState), 'PASS');
    });

    test('RETIRED-ROUND verdict exhaustion blocks, and the remedy needs '
        '--beyond-cap', () async {
      Map<String, Object?> spent(String round) => _session(
        'r$round',
        workBead: '$_beadId#r$round',
        closed: true,
        metadata: {'${ResultKeys.prefix}review.${ResultKeys.grade}': 'F'},
      );
      final h = _Harness(sessions: [spent('1'), spent('2'), spent('3')]);

      expect(await h.mount(), 1, reason: '${h.out}${h.err}');
      final row = h.row(MountPrecondition.verdictCap);
      expect(row['outcome'], 'BLOCKED');
      expect(row['detail'], contains('3/$kMaxReworkRounds retired rounds'));
      expect(row['remedy'], contains('rework --note'));
      expect(row['remedy'], contains('--beyond-cap --actor <actor>'));
      expect(row['evidence'], contains('retired $_beadId#r1 spent a verdict'));
    });

    test('PER-STEP exhaustion on the published round blocks WITHOUT crossing '
        'the round cap', () async {
      final h = _Harness(
        sessions: [_session('s1', workBead: _beadId)],
        steps: {
          's1': [
            _step('st1', session: 's1', path: 'review'),
            _step('st2', session: 's1', path: 'review', supersedes: 'st1'),
            _step('st3', session: 's1', path: 'review', supersedes: 'st2'),
          ],
        },
      );

      expect(await h.mount(), 1, reason: '${h.out}${h.err}');
      final row = h.row(MountPrecondition.verdictCap);
      expect(row['outcome'], 'BLOCKED');
      expect(row['detail'], contains('review=3/$kMaxReworkRounds'));
      expect(row['remedy'], contains('rework --note'));
      expect(
        row['remedy'],
        isNot(contains('--beyond-cap')),
        reason: 'no retired round spent budget, so the cap is not crossed',
      );
    });

    test(
      'a historical per-step exhaustion does NOT block a later round',
      () async {
        final h = _Harness(
          sessions: [
            _session('s1', workBead: _beadId),
            _session('sr', workBead: '$_beadId#r1', closed: true),
          ],
          steps: {
            'sr': [
              _step('st1', session: 'sr', path: 'review'),
              _step('st2', session: 'sr', path: 'review', supersedes: 'st1'),
              _step('st3', session: 'sr', path: 'review', supersedes: 'st2'),
            ],
          },
        );

        expect(await h.mount(), 2, reason: '${h.out}${h.err}');
        expect(h.outcomeOf(MountPrecondition.verdictCap), 'PASS');
      },
    );

    test('a mount-attempt record AT the cap blocks, and bead rearm is the '
        'remedy', () async {
      final h = _Harness(
        attempts: [_attempt('a1', workBead: _beadId, count: kMaxMountAttempts)],
      );

      expect(await h.mount(), 1);
      final row = h.row(MountPrecondition.mountAttemptCap);
      expect(row['outcome'], 'BLOCKED');
      expect(row['detail'], contains('durable remount budget is SPENT'));
      expect(row['remedy'], contains('bead rearm --grid-root ${h.home}'));
      expect(row['remedy'], contains('--actor <actor>'));
      expect(row['evidence'], [
        'a1 count=$kMaxMountAttempts/$kMaxMountAttempts',
      ]);
    });

    test('a mount-attempt record BELOW the cap passes', () async {
      final h = _Harness(
        attempts: [_attempt('a1', workBead: _beadId, count: 1)],
      );

      expect(await h.mount(), 2);
      expect(h.outcomeOf(MountPrecondition.mountAttemptCap), 'PASS');
    });
  });

  group('AC-4 — fail closed: an unasked condition is never a pass', () {
    test(
      'no state root leaves the three state-backed rows UNCHECKED',
      () async {
        final h = _Harness(stateStore: false);

        expect(await h.mount(), 2, reason: '${h.out}${h.err}');
        for (final precondition in const [
          MountPrecondition.sessionOccupancy,
          MountPrecondition.verdictCap,
          MountPrecondition.mountAttemptCap,
        ]) {
          final row = h.row(precondition);
          expect(row['outcome'], 'UNCHECKED');
          expect(row['detail'], contains('no --state-root was supplied'));
          expect(row['detail'], contains('not a pass'));
          expect(row['remedy'], contains('--state-root <grid-home>'));
        }
        expect(h.report['verdict'], 'UNCHECKED');
      },
    );

    test(
      'a REFUSING state store is unavailable, never an empty answer',
      () async {
        final h = _Harness(
          stateRefuses: true,
          sessions: [_session('s1', workBead: _beadId)],
        );

        expect(await h.mount(), 2, reason: '${h.out}${h.err}');
        for (final precondition in const [
          MountPrecondition.sessionOccupancy,
          MountPrecondition.verdictCap,
          MountPrecondition.mountAttemptCap,
        ]) {
          expect(h.outcomeOf(precondition), 'UNCHECKED');
          expect(
            h.row(precondition)['detail'],
            contains('reading the state store at ${h.stateRoot} failed'),
          );
        }
      },
    );

    test('an unreadable local dependency target makes dependencies '
        'UNCHECKED', () async {
      final absent = _Harness(bead: _workBead(blockers: const ['pow-ghost']));
      expect(await absent.mount(), 2, reason: '${absent.out}${absent.err}');
      final row = absent.row(MountPrecondition.dependencies);
      expect(row['outcome'], 'UNCHECKED');
      expect(row['detail'], contains('NOT READ BACK'));
      expect(row['evidence'], const ['pow-ghost']);

      final refused = _Harness(
        bead: _workBead(blockers: const ['pow-a', 'pow-b']),
        targetQueryRefuses: true,
      );
      expect(await refused.mount(), 2, reason: '${refused.out}${refused.err}');
      expect(
        refused.row(MountPrecondition.dependencies)['evidence'],
        const ['pow-a', 'pow-b'],
        reason: 'a refused read says nothing about ANY target',
      );
    });

    test('an unconsulted roster refuses the external row and names the '
        'COMPOSITION seam', () async {
      final h = _Harness(
        bead: _workBead(blockers: const ['external:the_grid:tg-1']),
      );

      expect(await h.mount(), 1);
      final row = h.row(MountPrecondition.dependencies);
      expect(row['outcome'], 'BLOCKED');
      expect(row['detail'], contains('no station roster was supplied'));
      expect(row['remedy'], contains('armedSubstations'));
      expect(row['remedy'], contains('COMPOSITION gap, not a bead defect'));
    });

    test(
      'live_admission is ALWAYS unchecked and points at the resident',
      () async {
        for (final h in [_Harness(), _Harness(stateStore: false)]) {
          expect(await h.mount(), 2);
          final row = h.row(MountPrecondition.liveAdmission);
          expect(row['outcome'], 'UNCHECKED');
          expect(row['detail'], contains('NOT asked'));
          expect(row['remedy'], contains('StationAdmissionStatus'));
          expect(row['remedy'], contains('relay inference'));
        }
      },
    );
  });

  group('AC-5 — station-down, over a REAL bd store', () {
    test(
      'every offline row comes back with no resident in the path',
      () async {
        final store = await filingStore();
        await runBd(store, [
          'create',
          '--title',
          'a real bead',
          '--type',
          'task',
          '--json',
          '--actor',
          'test',
          '--acceptance',
          '- [ ] the outcome',
        ]);
        // Read through the fixture's own spawn: a hand-rolled `bd -C <store>`
        // resolves whatever workspace the test process sits in, not this
        // store.
        final created = await bdOutput(store, const [
          'list',
          '-t',
          'task',
          '--json',
          '--limit',
          '0',
        ]);
        final beadId = _rowsOf(created).single['id'] as String;
        await runBd(store, [
          'update',
          beadId,
          '--set-metadata',
          'validation_plan=dart test',
          '--json',
          '--actor',
          'test',
        ]);

        final out = StringBuffer();
        final err = StringBuffer();
        final runner = CommandRunner<int>('space', 'test station')
          ..addCommand(
            MountCommand(storeRoot: () => store.path, out: out, err: err),
          );

        // No station process, no control socket, no VM service.
        final code = await runner.run(['mount', '--json', beadId]);
        final report = jsonDecode(out.toString()) as Map<String, dynamic>;
        final rows = (report['preconditions'] as List)
            .cast<Map<String, dynamic>>();
        expect(rows.map((row) => row['precondition']), [
          for (final value in MountPrecondition.values) value.wire,
        ], reason: '$out$err');
        expect(report['id'], beadId);
        expect((report['filing'] as Map<String, dynamic>)['error'], isNull);
        // The bead files cleanly and is UNSTAMPED, so a real store answers the
        // two questions differently — which is the whole reason this verb
        // exists beside `filing`.
        expect((report['filing'] as Map<String, dynamic>)['passed'], isTrue);
        expect(
          rows.singleWhere(
            (row) => row['precondition'] == 'approval_stamp',
          )['outcome'],
          'BLOCKED',
        );
        expect(report['verdict'], 'BLOCKED');
        expect(code, 1);
        for (final precondition in const [
          'session_occupancy',
          'verdict_cap',
          'mount_attempt_cap',
          'live_admission',
        ]) {
          expect(
            rows.singleWhere(
              (row) => row['precondition'] == precondition,
            )['outcome'],
            'UNCHECKED',
          );
        }
      },
      skip: skipWithoutBd,
    );
  });

  group('AC-6 — the shared seams', () {
    test('--readiness is REACHABLE on all three stamping verbs, and on none '
        'of the explainers', () {
      // A vended option is done when a real runner carries it, so these are
      // DEFAULT constructions driven through a real CommandRunner.
      final runner = CommandRunner<int>('space', 'test station')
        ..addCommand(FilingCommand(out: StringBuffer(), err: StringBuffer()))
        ..addCommand(ApproveCommand(out: StringBuffer(), err: StringBuffer()))
        ..addCommand(UnparkCommand(out: StringBuffer(), err: StringBuffer()))
        ..addCommand(MountCommand(out: StringBuffer(), err: StringBuffer()))
        ..addCommand(ShowCommand(out: StringBuffer(), err: StringBuffer()));

      for (final verb in const ['filing', 'approve', 'unpark']) {
        final option =
            runner.commands[verb]!.argParser.options[kReadinessOption];
        expect(option, isNotNull, reason: '$verb carries --$kReadinessOption');
        expect(option!.defaultsTo, kReadinessRun);
        expect(option.allowed, [kReadinessRun, kReadinessSkip]);
        // A human can actually type it: the parser accepts both values and
        // refuses anything else.
        for (final value in const [kReadinessRun, kReadinessSkip]) {
          expect(
            runner.commands[verb]!.argParser
                .parse(['--$kReadinessOption=$value'])
                .option(kReadinessOption),
            value,
          );
        }
        expect(
          runner.commands[verb]!.invocation,
          contains('[--$kReadinessOption=$kReadinessRun|$kReadinessSkip]'),
        );
      }
      // The EXPLAINERS are not stamp moments and spend nothing.
      for (final verb in const ['mount', 'show']) {
        expect(
          runner.commands[verb]!.argParser.options.keys,
          isNot(contains(kReadinessOption)),
        );
      }
    });

    test('mount is the THIRD state-root consumer, and the option stayed '
        'retired on the other three', () {
      final mount = MountCommand(out: StringBuffer(), err: StringBuffer());
      final park = ParkCommand(out: StringBuffer(), err: StringBuffer());
      final show = ShowCommand(out: StringBuffer(), err: StringBuffer());

      for (final parser in [mount.argParser, park.argParser, show.argParser]) {
        final option = parser.options[kStateRootOption];
        expect(option, isNotNull);
        expect(option!.help, kStateRootHelp);
        expect(option.defaultsTo, isNull);
      }
      for (final parser in [
        FilingCommand(out: StringBuffer(), err: StringBuffer()).argParser,
        ApproveCommand(out: StringBuffer(), err: StringBuffer()).argParser,
        UnparkCommand(out: StringBuffer(), err: StringBuffer()).argParser,
      ]) {
        expect(parser.options.keys, isNot(contains(kStateRootOption)));
      }
      expect(
        mount.invocation,
        'mount [--json] [--state-root <grid-home>] <bead-id>',
      );
      // The resolution is the module's, not a copy: a grid home resolves to
      // its `.grid` child exactly as `park` and `show` resolve it.
      final parser = ArgParser();
      addStateRootOption(parser);
      final home = _gridHome();
      expect(
        resolveStateRoot(parser.parse(['--state-root', home]), noStateRoot),
        p.join(home, '.grid'),
      );
    });

    test('an unrelated --state-root is REFUSED loudly, not quietly '
        'accepted', () async {
      final h = _Harness();
      final unrelated = _unrelatedRoot();

      expect(
        await h.runner.run([
          'mount',
          '--json',
          '--state-root',
          unrelated,
          _beadId,
        ]),
        1,
      );
      expect(h.err.toString(), contains(unrelated));
      expect(h.err.toString(), contains('.grid'));
      expect(h.out.toString(), isEmpty);
    });

    test('one inspect, one roster seam, one work store', () async {
      final h = _Harness(
        bead: _workBead(blockers: const ['external:the_grid:tg-1']),
        armed: const {'the_grid'},
      );

      expect(await h.mount(), 2, reason: '${h.out}${h.err}');
      // The dependencies PRECONDITION reuses the very projection the filing
      // REQUIREMENT was rendered from — it adds local target state and nothing
      // else.
      expect(await h.filing(), 0);
      final filingDetail =
          ((jsonDecode(h.filingOut.toString())
                          as Map<String, dynamic>)['requirements']
                      as List)
                  .cast<Map<String, dynamic>>()
                  .singleWhere(
                    (row) => row['requirement'] == 'dependencies',
                  )['detail']
              as String;
      expect(
        (h.report['filing'] as Map<String, dynamic>)['requirements'],
        isNotNull,
      );
      expect(
        h.row(MountPrecondition.dependencies)['detail'],
        startsWith(filingDetail),
      );
      // The work store root is the injected callback's, and the state store is
      // the resolved grid home's — never a third root.
      expect(h.bd.calls.map((call) => call.root).toSet(), {
        _workRoot,
        h.stateRoot,
      });
      expect(noArmedSubstations(), isNull);
      expect(
        MountCommand(
          out: StringBuffer(),
          err: StringBuffer(),
        ).argParser.options.keys,
        isNot(contains('armed-substations')),
      );
    });
  });

  group('AC-7 — READ-ONLY by construction', () {
    test('the COMPLETE argv set is scoped reads and nothing else', () async {
      final h = _Harness(
        bead: _workBead(blockers: const ['pow-done']),
        targets: [_target('pow-done')],
        sessions: [_session('s1', workBead: _beadId)],
        steps: {
          's1': [_step('st1', session: 's1', path: 'review')],
        },
        attempts: [_attempt('a1', workBead: _beadId, count: 1)],
        armed: const {'the_grid'},
      );

      expect(await h.mount(), 2, reason: '${h.out}${h.err}');
      expect(h.bd.calls, isNotEmpty);

      const mutations = [
        'create',
        'update',
        'close',
        'defer',
        'undefer',
        'dep',
        'batch',
        'import',
        'ship',
        'rearm',
      ];
      for (final call in h.bd.calls) {
        expect(
          call.argv.first,
          isNot('show'),
          reason:
              '`bd show` writes .beads/last-touched and self-triggers the '
              "store's watcher",
        );
        expect(call.argv, isNot(contains('link')));
        switch (call.argv.first) {
          case 'query':
            // Every query is scoped to EXACT ids — never an open predicate.
            expect(call.argv[1].split(' OR '), everyElement(startsWith('id=')));
            expect(call.argv.sublist(2), const [
              '--all',
              '--json',
              '--limit',
              '0',
            ]);
          case 'list':
            expect(call.argv[1], '-t');
            expect(
              call.argv[2],
              isIn(const ['session', 'step', 'mount-attempt']),
              reason: 'the retired type=link read is never issued',
            );
            expect(call.argv.last, '0');
            expect(
              call.argv,
              containsAllInOrder(const ['--json', '--limit', '0']),
            );
          case 'dep':
            // beads_dart's OWN external-row control, and only there: it spawns
            // a `dep list` exactly when the record surface returned no rows.
            expect(call.argv.take(2), const ['dep', 'list']);
          default:
            fail('unexpected bd subcommand `${call.argv.first}`');
        }
        expect(
          call.argv.first == 'dep' || !mutations.contains(call.argv.first),
          isTrue,
        );
      }
      // The state store is only ever list-scoped; the work store only ever
      // record-read.
      expect(h.argvFirsts(h.stateRoot!).toSet(), {'list'});
      expect(h.argvFirsts(_workRoot).toSet(), {'query'});
    });
  });

  // THE RECEIPT, captured 2026-09-14 against this worktree's own power_station
  // work store with no station in the path and no `--state-root` named:
  //
  //   argv:    space mount --json pow-1pfs
  //   exit:    2
  //   verdict: UNCHECKED
  //   PASS driveable_type          PASS validation_plan
  //   PASS acceptance_criteria     PASS dependencies
  //   PASS approval_stamp          UNCHECKED session_occupancy
  //   PASS defer_state             UNCHECKED verdict_cap
  //   UNCHECKED mount_attempt_cap  UNCHECKED live_admission
  //
  // The three UNCHECKED state rows are the honest offline answer to a run that
  // named no grid home; `live_admission` is unchecked by construction. The test
  // below re-derives that receipt rather than pinning it, because a real bead's
  // state moves and a pinned outcome would be a fixture pretending to be a
  // probe.
  group('AC-8 — reachability and the real-bead receipt', () {
    test('a real CommandRunner exposes `mount`, and it explains this round\'s '
        'own bead end to end', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      // The power_station work store this round runs against: the repo root
      // that holds `.beads`, resolved off the source-located package root.
      final repoRoot = p.normalize(p.join(packageRoot(), '..', '..'));
      final runner = CommandRunner<int>('space', 'test station')
        ..addCommand(FilingCommand(out: StringBuffer(), err: err))
        ..addCommand(
          MountCommand(storeRoot: () => repoRoot, out: out, err: err),
        );

      expect(
        runner.commands['mount'],
        isNotNull,
        reason: 'a verb a real runner does not carry has not shipped',
      );
      expect(runner.commands['filing'], isNotNull);

      const argv = ['mount', '--json', 'pow-1pfs'];
      final code = await runner.run(argv);
      final report = jsonDecode(out.toString()) as Map<String, dynamic>;

      expect(report['id'], 'pow-1pfs');
      expect(report['error'], isNull, reason: '$out$err');
      expect(
        (report['preconditions'] as List).map((row) => row['precondition']),
        [for (final value in MountPrecondition.values) value.wire],
        reason: 'ten rows, in order, for a real bead read out of a real store',
      );
      // The RECEIPT: the exit code is the aggregate verdict's own mapping, and
      // the three state-backed rows are honestly unchecked because no
      // --state-root was named.
      expect(code, isIn(const [0, 1, 2]));
      expect(code, switch (report['verdict']) {
        'PASS' => 0,
        'BLOCKED' => 1,
        _ => 2,
      });
      for (final precondition in const [
        MountPrecondition.sessionOccupancy,
        MountPrecondition.verdictCap,
        MountPrecondition.mountAttemptCap,
      ]) {
        expect(
          (report['preconditions'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere(
                (row) => row['precondition'] == precondition.wire,
              )['outcome'],
          'UNCHECKED',
        );
      }
    }, skip: skipWithoutBd);
  });

  group('AC-9 — the DEFAULT composition binds live filing evidence', () {
    test('default mount composition binds owning decision evidence', () async {
      // NO `filing` and NO `FilingEvidenceSource` override: this is the wiring
      // a resident actually gets. Before it was threaded, `mount` composed an
      // evidence-free `FilingService`, so the embedded report refused every
      // decision-citing bead with "restore complete evidence and rerun" — an
      // explanation about the explainer's own wiring, not about the bead.
      const slug = 'the-dependencies-row-is-a-projection-of-bd-dependency-rows';
      final register = Directory.systemTemp.createTempSync('mount-register-');
      addTearDown(() => register.deleteSync(recursive: true));
      File(p.join(register.path, 'a.md')).writeAsStringSync(
        '---\nslug: $slug\nstatus: accepted\n---\n\nA projection.\n',
      );

      Future<({Map<String, dynamic> report, FakeValidationPlanProbe probe})>
      explain(String description) async {
        final bd = _Bd();
        final record = {
          ..._workBead(blockers: const ['pow-blocker']),
          'description': description,
        };
        bd.replies[_workRoot] = (argv) {
          if (argv.first != 'query') return _emptyEnvelope;
          if (argv[1] == 'id=$_beadId') return _envelope([record]);
          return _envelope([_target('pow-blocker')]);
        };
        final probe = FakeValidationPlanProbe();
        final out = StringBuffer();
        final runner = CommandRunner<int>('space', 'test station')
          ..addCommand(
            MountCommand(
              storeRoot: () => _workRoot,
              stateRoot: () => null,
              runnerFor: bd.runnerFor,
              owningScope: sdk.SubstationScope(
                name: 'power_station',
                root: _workRoot,
                prefix: 'pow',
              ),
              validationPlanProbe: probe,
              decisionShell: _CannedIndexShell(
                jsonEncode({
                  'spec': 2,
                  'decisions': [
                    {
                      'slug': slug,
                      'originRegister': 'power_station',
                      'originPath': register.path,
                      'status': 'accepted',
                      'surfaces': <String>['packages/grid_assets/**'],
                    },
                  ],
                }),
              ),
              decisionInvocation: 'space',
              decisionGridHome: _gridHome(),
              out: out,
              err: StringBuffer(),
            ),
          );
        await runner.run(['mount', '--json', _beadId]);
        return (
          report: jsonDecode(out.toString()) as Map<String, dynamic>,
          probe: probe,
        );
      }

      final cited = await explain('Follows power_station#$slug.');
      final embedded = cited.report['filing']! as Map<String, dynamic>;
      final rows = (embedded['requirements']! as List)
          .cast<Map<String, dynamic>>();
      expect(
        rows.where((row) => row['passed'] == false),
        isEmpty,
        reason: '$embedded',
      );
      expect(rows, hasLength(11));
      expect(embedded['passed'], isTrue);

      // ONE gather, not one per row: the two plan shells are asked exactly
      // once each, and the plan is PARSED rather than run.
      expect(cited.probe.calls.map((call) => call.shell), [
        kFilingLaneShell,
        kFilingPortabilityShell,
      ]);
      expect(
        cited.probe.calls.map((call) => call.plan),
        everyElement('dart test'),
      );

      // The retained projection still rides through: the mount row reports the
      // very rows the filing requirement was rendered from.
      final dependencies = (cited.report['preconditions']! as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (row) => row['precondition'] == MountPrecondition.dependencies.wire,
          );
      expect(dependencies['detail'], contains('pow-blocker'));
      expect(
        rows.singleWhere(
          (row) => row['requirement'] == 'dependencies',
        )['detail'],
        contains('pow-blocker'),
      );

      // Change ONLY the cited slug to one this round would have to create: the
      // same wiring refuses on the named row, with the exact correction.
      final invented = await explain(
        'Follows power_station#a-rule-this-round-creates.',
      );
      final refused =
          ((invented.report['filing']! as Map<String, dynamic>)['requirements']!
                  as List)
              .cast<Map<String, dynamic>>()
              .singleWhere(
                (row) => row['requirement'] == 'decision_references',
              );
      expect(refused['passed'], isFalse);
      expect(refused['detail'], contains('a-rule-this-round-creates'));
      expect(
        refused['detail'],
        contains(
          'a round may not cite a decision it creates; cite an existing entry '
          'or describe the proposed entry without a citation',
        ),
      );
    });
  });
}

extension on _Harness {
  Iterable<String> argvFirsts(String root) =>
      bd.argvFor(root).map((argv) => argv.first);
}

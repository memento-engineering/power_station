import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart'
    show ApproveService, kFilingApprovalRevisionPrefix;
import 'package:test/test.dart';

class FakeBdRunner implements BdRunner {
  FakeBdRunner(this.results);

  final List<BdResult> results;
  final List<List<String>> argvs = [];
  final List<String?> stdins = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    stdins.add(stdin);
    return results.removeAt(0);
  }
}

const record = GitHubIntakeRecord(
  nodeId: 'I_1',
  kind: 'issue',
  repository: 'memento/power_station',
  number: 42,
  actor: 'nico',
  title: 'Fix the flux capacitor',
  body: 'Details.',
);

const expectedTitle =
    '[GitHub issue memento/power_station#42] Fix the flux capacitor';

const expectedBody =
    'GitHub issue opened by @nico in memento/power_station#42.\n'
    'GitHub node_id: I_1\n'
    '\n'
    'Details.';

/// The per-key metadata channel: one flag pair per key, never one whole object.
const expectedSetMetadata = <String>[
  '--set-metadata',
  'github.node_id=I_1',
  '--set-metadata',
  'github.kind=issue',
  '--set-metadata',
  'github.repository=memento/power_station',
  '--set-metadata',
  'github.actor=nico',
];

BdResult ok(Object? data, {int schemaVersion = 1}) => BdResult(
  exitCode: 0,
  stdout: jsonEncode({'schema_version': schemaVersion, 'data': data}),
  stderr: '',
);

/// The seat's WORK store, scripted by argv SHAPE rather than a fixed queue, so
/// the approval leg's reads can be answered wherever they land in the order.
final class RecordingBdRunner implements BdRunner {
  RecordingBdRunner({
    this.correlated = const <Map<String, Object?>>[],
    this.openBugs = const <Map<String, Object?>>[],
    this.filed,
    this.createdId = 'pow-run',
  });

  /// Answers the external-ref correlation read.
  List<Map<String, Object?>> correlated;

  /// Answers the OPEN same-subject `bug` read.
  List<Map<String, Object?>> openBugs;

  /// Answers the approval preflight's exact-id read; null means "not found".
  Map<String, Object?>? filed;

  /// The id `bd create` reports back.
  String createdId;

  final argvs = <List<String>>[];
  final stdins = <String?>[];

  List<List<String>> verb(String name) =>
      argvs.where((argv) => argv.first == name).toList();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    stdins.add(stdin);
    return switch (args) {
      ['list', ...] when args.contains('--external-ref') => ok(correlated),
      ['list', ...] when args.contains('link') => ok(const <Object?>[]),
      ['list', ...] => ok(openBugs),
      ['create', ...] => ok({'id': createdId}),
      ['query', ...] => ok(filed == null ? const <Object?>[] : [filed]),
      ['dep', ...] => ok(const <Object?>[]),
      _ => ok({'id': args.length > 1 ? args[1] : createdId}),
    };
  }
}

/// The bead the approval preflight reads back for a well-formed filing.
Map<String, Object?> filedBug({
  String id = 'pow-run',
  String validationPlan = 'dart test',
  String acceptance = '- [ ] AC-1 — CI is green; falsifier: `dart test`',
}) => <String, Object?>{
  'id': id,
  'title': 'a red nightly',
  'description': 'The nightly failed.',
  'acceptance_criteria': acceptance,
  'issue_type': 'bug',
  'priority': 1,
  'metadata': <String, Object?>{'validation_plan': validationPlan},
};

GitHubIntakeRecord workflowRecord({
  String nodeId = 'WFR_1',
  String validationPlan = 'dart test',
  int priority = 1,
  bool approve = true,
  List<WorkflowRunFailedJob> failedJobs = const [
    WorkflowRunFailedJob(jobName: 'test', failedStepName: 'dart test'),
  ],
}) => GitHubIntakeRecord.workflowRun(
  nodeId: nodeId,
  repository: 'memento/power_station',
  runId: 9001,
  runNumber: 128,
  workflowPath: '.github/workflows/ci.yaml',
  workflowName: 'CI',
  event: 'schedule',
  headBranch: 'main',
  headSha: 'abcdef0',
  conclusion: 'failure',
  htmlUrl: 'https://github.test/memento/power_station/actions/runs/9001',
  failedJobs: failedJobs,
  validationPlan: validationPlan,
  priority: priority,
  approve: approve,
);

/// A store wired exactly as the seat binding wires it: one runner for the work
/// root and one for the grid state root, and the approve VERB over both.
BdGitHubIntakeStore seatStore(
  RecordingBdRunner runner, {
  String? stateRoot = '/grid/.grid',
}) => BdGitHubIntakeStore(
  runner,
  approvals: ApproveService(
    runnerFor: (_) => runner,
    now: () => DateTime.utc(2026, 9, 8, 12),
  ),
  workRoot: '/work/seat',
  stateRoot: stateRoot,
);

const workflowMetadata = <String>[
  '--set-metadata',
  'github.node_id=WFR_1',
  '--set-metadata',
  'github.kind=workflow run',
  '--set-metadata',
  'github.repository=memento/power_station',
  '--set-metadata',
  'github.actor=github-workflow',
  '--set-metadata',
  'github.run_id=9001',
  '--set-metadata',
  'github.workflow_path=.github/workflows/ci.yaml',
  '--set-metadata',
  'github.head_branch=main',
  '--set-metadata',
  'github.head_sha=abcdef0',
  '--set-metadata',
  'github.conclusion=failure',
  '--set-metadata',
  'validation_plan=dart test',
];

void main() {
  group('BdGitHubIntakeStore', () {
    test('creates a durable OPEN core bead for a new node id', () async {
      final runner = FakeBdRunner([
        ok([]),
        ok({'id': 'pow-new'}),
        ok({'id': 'pow-new'}),
      ]);

      await BdGitHubIntakeStore(runner).upsert(record);

      expect(runner.argvs, hasLength(3));
      expect(runner.argvs[0], [
        'list',
        '--all',
        '--external-ref',
        'github:I_1',
        '--json',
        '--limit',
        '0',
      ]);
      expect(runner.argvs[1], [
        'create',
        '--json',
        '--actor',
        'grid-controller',
        '--title',
        expectedTitle,
        '--type',
        'chore',
        '--priority',
        '2',
        '--description',
        expectedBody,
        '--external-ref',
        'github:I_1',
      ]);
      expect(runner.argvs[2], [
        'update',
        'pow-new',
        '--json',
        '--actor',
        'grid-controller',
        ...expectedSetMetadata,
      ]);
      final flattened = runner.argvs.expand((argv) => argv).toList();
      expect(flattened, isNot(contains('--metadata')));
      expect(flattened, isNot(contains('--ephemeral')));
      expect(flattened, isNot(contains('--status')));
    });

    test(
      'the create argv carries no parking date and no approval marker',
      () async {
        final runner = FakeBdRunner([
          ok([]),
          ok({'id': 'pow-new'}),
          ok({'id': 'pow-new'}),
        ]);

        await BdGitHubIntakeStore(runner).upsert(record);

        final flattened = runner.argvs.expand((argv) => argv).toList();
        expect(flattened, isNot(contains('--defer')));
        expect(flattened.where((arg) => arg.contains('9999')), isEmpty);
        expect(
          flattened.where((arg) => arg.contains('grid.approved')),
          isEmpty,
          reason: 'the approve verb is the only writer of the approval stamp',
        );
        expect(flattened, isNot(contains('--label')));
        expect(flattened, isNot(contains('--add-label')));
      },
    );

    test(
      'updates the sole correlated bead without readiness mutation',
      () async {
        final runner = FakeBdRunner([
          ok([
            {'id': 'pow-existing'},
          ]),
          ok({'id': 'pow-existing'}),
        ]);

        await BdGitHubIntakeStore(runner).upsert(record);

        expect(runner.argvs, hasLength(2));
        expect(runner.argvs[1], [
          'update',
          'pow-existing',
          '--json',
          '--actor',
          'grid-controller',
          '--title',
          expectedTitle,
          '--body-file',
          '-',
          ...expectedSetMetadata,
        ]);
        expect(runner.stdins[1], expectedBody);
        expect(runner.argvs[1], isNot(contains('--metadata')));
        expect(runner.argvs[1], isNot(contains('--defer')));
        expect(runner.argvs[1], isNot(contains('--status')));
        expect(runner.argvs[1], isNot(contains('create')));
      },
    );

    test('fails loudly for multiple correlations or malformed ids', () async {
      final multiple = FakeBdRunner([
        ok([
          {'id': 'a'},
          {'id': 'b'},
        ]),
      ]);
      await expectLater(
        BdGitHubIntakeStore(multiple).upsert(record),
        throwsStateError,
      );

      final empty = FakeBdRunner([
        ok([
          {'id': ''},
        ]),
      ]);
      await expectLater(
        BdGitHubIntakeStore(empty).upsert(record),
        throwsA(isA<BdParseException>()),
      );

      for (final id in <Object?>[null, 3]) {
        final malformed = FakeBdRunner([
          ok([
            {'id': id},
          ]),
        ]);
        await expectLater(
          BdGitHubIntakeStore(malformed).upsert(record),
          throwsA(isA<TypeError>()),
        );
      }
    });

    test('fails loudly for command failure and schema drift', () async {
      final failed = FakeBdRunner([
        const BdResult(exitCode: 1, stdout: '', stderr: 'nope'),
      ]);
      await expectLater(
        BdGitHubIntakeStore(failed).upsert(record),
        throwsA(isA<BdCommandFailed>()),
      );
      final drifted = FakeBdRunner([ok([], schemaVersion: 2)]);
      await expectLater(
        BdGitHubIntakeStore(drifted).upsert(record),
        throwsA(isA<BdSchemaDriftException>()),
      );
      final malformed = FakeBdRunner([
        ok({'id': 'not-a-list'}),
      ]);
      await expectLater(
        BdGitHubIntakeStore(malformed).upsert(record),
        throwsA(isA<BdParseException>()),
      );
    });
  });

  group('BdGitHubIntakeStore workflow run', () {
    test('mints one approved bug through the filing verb', () async {
      final runner = RecordingBdRunner(filed: filedBug());

      await seatStore(runner).upsert(workflowRecord());

      expect(runner.verb('list').first, [
        'list',
        '--all',
        '--external-ref',
        'github:WFR_1',
        '--json',
        '--limit',
        '0',
      ]);
      expect(runner.verb('list')[1], [
        'list',
        '-t',
        'bug',
        '--status',
        'open',
        '--metadata-field',
        'github.head_branch=main',
        '--metadata-field',
        'github.workflow_path=.github/workflows/ci.yaml',
        '--json',
        '--limit',
        '0',
      ]);
      expect(runner.verb('create').single, [
        'create',
        '--json',
        '--actor',
        'grid-controller',
        '--title',
        '[GitHub workflow memento/power_station ci.yaml#128] '
            'CI failed on main (schedule)',
        '--type',
        'bug',
        '--priority',
        '1',
        '--description',
        contains('/actions/runs/9001'),
        '--external-ref',
        'github:WFR_1',
      ]);

      final updates = runner.verb('update');
      expect(updates, hasLength(2));
      expect(updates.first, [
        'update',
        'pow-run',
        '--json',
        '--actor',
        'grid-controller',
        '--acceptance',
        contains('`dart test`'),
        ...workflowMetadata,
      ]);
      expect(
        updates.last,
        containsAllInOrder([
          'update',
          'pow-run',
          '--json',
          '--actor',
          'github-workflow',
          '--set-metadata',
          'grid.approved_by=github-workflow',
          '--set-metadata',
          'grid.approved_at=2026-09-08T12:00:00.000Z',
        ]),
        reason: 'the approve verb writes the stamp, this store never does',
      );
      expect(
        updates.last.last,
        startsWith('grid.approved_rev=$kFilingApprovalRevisionPrefix'),
      );
      expect(
        runner.argvs.expand((argv) => argv),
        isNot(contains('show')),
        reason: 'no bd show on the reconciler poll path',
      );
    });

    test('this store never hand-writes an approval key', () async {
      final runner = RecordingBdRunner(filed: filedBug());

      await seatStore(runner).upsert(workflowRecord());

      final byController = runner.argvs
          .where((argv) => argv.contains('grid-controller'))
          .expand((argv) => argv)
          .where((arg) => arg.contains('grid.approved'));
      expect(byController, isEmpty);
    });

    test('a repeat observation updates its correlated bead', () async {
      final runner = RecordingBdRunner(
        correlated: [
          {'id': 'pow-existing'},
        ],
        filed: filedBug(id: 'pow-existing'),
      );

      await seatStore(runner).upsert(workflowRecord());

      expect(runner.verb('create'), isEmpty);
      expect(
        runner.verb('list'),
        hasLength(2),
        reason: 'a correlated bead skips the open-subject guard entirely',
      );
      expect(runner.verb('update').first, [
        'update',
        'pow-existing',
        '--json',
        '--actor',
        'grid-controller',
        '--title',
        contains('#128'),
        '--body-file',
        '-',
        '--acceptance',
        contains('`dart test`'),
        ...workflowMetadata,
      ]);
      expect(runner.stdins[1], contains('/actions/runs/9001'));
    });

    test('a fresh run for an OPEN same-workflow bead writes nothing', () async {
      final runner = RecordingBdRunner(
        openBugs: [
          {'id': 'pow-yesterday'},
        ],
      );

      await seatStore(runner).upsert(workflowRecord(nodeId: 'WFR_TONIGHT'));

      expect(runner.verb('create'), isEmpty);
      expect(runner.verb('update'), isEmpty);
      expect(
        runner.verb('list'),
        hasLength(2),
        reason: 'exactly the correlation read and the open-subject read',
      );
    });

    test('approve false files the bug and stamps nothing', () async {
      final runner = RecordingBdRunner(filed: filedBug());

      await seatStore(runner).upsert(workflowRecord(approve: false));

      expect(runner.verb('create'), hasLength(1));
      expect(runner.verb('update'), hasLength(1));
      expect(runner.verb('query'), isEmpty);
      expect(
        runner.argvs
            .expand((argv) => argv)
            .where((arg) => arg.contains('grid.approved')),
        isEmpty,
      );
    });

    test(
      'workflow run refused preflight leaves it open and unstamped',
      () async {
        final runner = RecordingBdRunner(filed: filedBug(validationPlan: ''));

        await seatStore(runner).upsert(workflowRecord(validationPlan: ''));

        expect(runner.verb('create'), hasLength(1));
        final updates = runner.verb('update');
        expect(updates, hasLength(2));
        expect(
          updates.last,
          containsAllInOrder(['update', 'pow-run', '--json', '--append-notes']),
        );
        expect(updates.last.last, contains('validation_plan is blank'));
        expect(
          runner.argvs
              .expand((argv) => argv)
              .where((arg) => arg.contains('grid.approved')),
          isEmpty,
          reason: 'a refused preflight writes NO approval key',
        );
        expect(
          [...runner.verb('create'), ...updates].expand((argv) => argv),
          isNot(contains('--status')),
          reason: 'the bead stays OPEN — no write touches its status',
        );
      },
    );

    test('a store with no approve verb refuses an approving record', () async {
      final runner = RecordingBdRunner(filed: filedBug());

      await expectLater(
        BdGitHubIntakeStore(runner).upsert(workflowRecord()),
        throwsStateError,
      );
    });

    test('no state root still approves, with links unconsulted', () async {
      final runner = RecordingBdRunner(filed: filedBug());

      await seatStore(runner, stateRoot: null).upsert(workflowRecord());

      expect(
        runner.verb('list').where((argv) => argv.contains('link')),
        isEmpty,
      );
      expect(
        runner.verb('update').last,
        contains('grid.approved_by=github-workflow'),
      );
    });
  });

  group('outbound issue watch', () {
    GitHubIssueWatchUpdate update({
      String? state = 'closed',
      String? stateReason = 'not_planned',
      String? actor = 'ricardoboss',
      String? url = 'https://github.com/ricardoboss/radioactive_dart/issues/1',
      String change = 'closed_not_planned',
    }) => GitHubIssueWatchUpdate(
      beadId: 'lunar_station-6p9',
      repository: 'ricardoboss/radioactive_dart',
      issueNumber: 1,
      issueNodeId: 'I_kwDO',
      observationId: 'poll:issue-state:CE_closed:closed_not_planned',
      actor: actor,
      change: change,
      state: state,
      stateReason: stateReason,
      updatedAt: DateTime.utc(2026, 9, 9, 13),
      url: url,
      headline: 'closed as not planned',
      detail: 'The issue is now closed (not_planned).',
    );

    test('one update targets the ORIGINATING bead with exact argv', () async {
      final runner = FakeBdRunner(<BdResult>[ok(<String, Object?>{})]);
      await BdGitHubIntakeStore(runner).appendIssueWatch(update());

      expect(runner.argvs, hasLength(1), reason: 'ONE bd call, one store');
      final argv = runner.argvs.single;
      expect(argv.take(3), <String>['update', 'lunar_station-6p9', '--json']);
      expect(argv, containsAllInOrder(<String>['--status', 'open']));
      expect(
        argv,
        containsAllInOrder(<String>[
          '--set-metadata',
          'github.watch.repository=ricardoboss/radioactive_dart',
          '--set-metadata',
          'github.watch.issue_number=1',
          '--set-metadata',
          'github.watch.issue_node_id=I_kwDO',
          '--set-metadata',
          'github.watch.last_observation='
              'poll:issue-state:CE_closed:closed_not_planned',
          '--set-metadata',
          'github.watch.change=closed_not_planned',
          '--set-metadata',
          'github.watch.updated_at=2026-09-09T13:00:00.000Z',
          '--set-metadata',
          'github.watch.state=closed',
          '--set-metadata',
          'github.watch.state_reason=not_planned',
        ]),
        reason: 'PER KEY, never one whole metadata object',
      );
      expect(
        argv,
        containsAllInOrder(<String>[
          '--unset-metadata',
          'grid.approved_by',
          '--unset-metadata',
          'grid.approved_at',
          '--unset-metadata',
          'grid.approved_rev',
        ]),
      );
      final note = argv[argv.indexOf('--append-notes') + 1];
      expect(note, contains('GitHub watch ricardoboss/radioactive_dart#1'));
      expect(note, contains('By: @ricardoboss'));
      expect(note, contains('State: closed (not_planned)'));
      expect(argv, isNot(contains('--body-file')));
      expect(argv, isNot(contains('--acceptance')));
      expect(argv, isNot(contains('--defer-until')));
    });

    test('a comment neither asserts nor erases the issue state', () async {
      final runner = FakeBdRunner(<BdResult>[ok(<String, Object?>{})]);
      await BdGitHubIntakeStore(runner).appendIssueWatch(
        update(state: null, stateReason: null, change: 'commented'),
      );

      final argv = runner.argvs.single;
      expect(argv.join(' '), isNot(contains('github.watch.state=')));
      expect(argv.join(' '), isNot(contains('github.watch.state_reason')));
      expect(
        argv,
        containsAllInOrder(<String>[
          '--set-metadata',
          'github.watch.change=commented',
        ]),
      );
    });

    test('a reopen UNSETS the reason it was closed with', () async {
      final runner = FakeBdRunner(<BdResult>[ok(<String, Object?>{})]);
      await BdGitHubIntakeStore(
        runner,
      ).appendIssueWatch(update(state: 'open', stateReason: null));

      expect(
        runner.argvs.single,
        containsAllInOrder(<String>[
          '--unset-metadata',
          'github.watch.state_reason',
        ]),
      );
    });

    test('the note omits an actor GitHub named nobody for', () async {
      final runner = FakeBdRunner(<BdResult>[ok(<String, Object?>{})]);
      await BdGitHubIntakeStore(
        runner,
      ).appendIssueWatch(update(actor: kIssueWatchResourceActor, url: null));

      final argv = runner.argvs.single;
      final note = argv[argv.indexOf('--append-notes') + 1];
      expect(note, isNot(contains('By: @')));
      expect(note, isNot(contains('URL:')));
    });

    test('this path never reaches the approve verb', () async {
      final runner = FakeBdRunner(<BdResult>[ok(<String, Object?>{})]);
      await BdGitHubIntakeStore(
        runner,
        approvals: ApproveService(
          runnerFor: (_) => throw StateError('an external reply is never SELF'),
        ),
        workRoot: '/unused',
      ).appendIssueWatch(update());

      expect(runner.argvs, hasLength(1));
      expect(
        runner.argvs.single,
        isNot(contains(kFilingApprovalRevisionPrefix)),
      );
    });
  });
}

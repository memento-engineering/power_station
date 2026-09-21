import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_fakes.dart' show callMetadata;
import 'filing_evidence_fakes.dart';

/// Creates a REAL grid home — `<home>/.grid/.beads` — because the resolver
/// probes the filesystem to tell a grid home from its own state store.
String _gridHome() {
  final home = Directory.systemTemp.createTempSync('grid-home-');
  Directory(p.join(home.path, '.grid', '.beads')).createSync(recursive: true);
  addTearDown(() => home.deleteSync(recursive: true));
  return home.path;
}

/// Replies by bd subcommand, recording every argv so a refusal can prove it
/// wrote nothing.
final class _ScriptedBdRunner implements BdRunner {
  _ScriptedBdRunner(this.replies, {this.updateExitCode = 0});

  final Map<String, String> replies;
  final int updateExitCode;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    return BdResult(
      exitCode: args.first == 'update' ? updateExitCode : 0,
      stdout: replies[args.first] ?? '{"schema_version":1,"data":[]}',
      stderr: args.first == 'update' && updateExitCode != 0
          ? 'bd: refused'
          : '',
    );
  }

  List<List<String>> get updates =>
      argvs.where((argv) => argv.first == 'update').toList();
}

/// bd's RECORD surface for `pow-child`, carrying the dependency ROWS bd holds
/// — the one surface an `external:` target survives on.
String _beadReply({
  required String description,
  List<String> blockers = const [],
}) => jsonEncode({
  'schema_version': 1,
  'data': [
    {
      'id': 'pow-child',
      'title': 'child',
      'issue_type': 'task',
      'description': description,
      'acceptance_criteria': '- [ ] checked',
      'metadata': {'validation_plan': 'dart test'},
      'dependencies': [
        for (final blocker in blockers)
          {'issue_id': 'pow-child', 'depends_on_id': blocker, 'type': 'blocks'},
      ],
    },
  ],
});

({
  CommandRunner<int> runner,
  StringBuffer out,
  StringBuffer err,
  _ScriptedBdRunner bd,
  List<String> roots,
})
_harness(_ScriptedBdRunner bd, {Set<String>? armed, FilingAdvisory? advisory}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final roots = <String>[];
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        ApproveCommand(
          service: ApproveService(
            runnerFor: (root) {
              roots.add(root);
              return bd;
            },
            now: () => DateTime.utc(2026, 9, 2, 14, 30),
            // COMPLETE fake evidence, not absent evidence: the `pow` store
            // ANSWERED with the ids these fixtures cite, so a passing
            // `bead_references` row here is a resolution and not a vacuum.
            // The stores are fakes at a path no shell can enter, so the plan
            // probes are prepared too.
            evidence: FakeFilingEvidenceSource(
              parsedPlanEvidence(
                beadCatalogs: const {
                  'pow': {'pow-child', 'pow-n6n', 'pow-n6n.1'},
                },
                decisionRegisters: const {},
              ),
            ),
            // The PRE-STAMP ADVISORY is a scripted Fake for the same reason
            // the evidence is: these probes measure the STAMP, and an
            // inference call between the rows and the receipt would put a
            // model inside an argv assertion. Its own arms are pinned in
            // `pre_stamp_advisory_test.dart`.
            advisory: advisory ?? FakeFilingAdvisory(),
          ),
          storeRoot: () => '/work/power_station',
          armedSubstations: () => armed,
          out: out,
          err: err,
        ),
      ),
    out: out,
    err: err,
    bd: bd,
    roots: roots,
  );
}

void main() {
  test('a prose blocker is PROSE — the preflight stamps', () async {
    // The sentence that used to refuse this bead. bd holds no row, so there is
    // no blocker: `Blocked-by:` and `Depends on` are English either way.
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(
          description:
              'Child 2 of epic pow-n6n. Depends on child pow-n6n.1. '
              'Blocked-by: pow-n6n.1.',
        ),
      }),
    );

    expect(
      await h.runner.run(['approve', '--json', '--actor', 'nico', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    final filing = report['filing'] as Map<String, dynamic>;
    final rows = (filing['requirements'] as List).cast<Map<String, dynamic>>();
    final dependencies = rows.singleWhere(
      (row) => row['requirement'] == 'dependencies',
    );
    expect(dependencies['passed'], isTrue);
    expect(dependencies['detail'], 'bd holds no blocking dependency rows');
    expect(h.bd.updates, hasLength(1));
  });

  test('stamps the deterministic filing revision in one update', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(
          description: 'Child 2 of epic pow-n6n.',
          blockers: const ['pow-n6n.1'],
        ),
      }),
    );

    expect(
      await h.runner.run(['approve', '--json', '--actor', 'nico', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(h.bd.updates, hasLength(1));
    final argv = h.bd.updates.single;
    expect(argv.take(2), ['update', 'pow-child']);
    expect(argv, containsAllInOrder(['--actor', 'nico']));
    expect(argv, isNot(contains('--add-label')));
    // THREE receipt keys plus the advisory's grade — one update, because a
    // receipt and the account of what was judged to earn it land together.
    expect(argv.where((arg) => arg == '--set-metadata'), hasLength(4));

    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    final filing = report['filing'] as Map<String, dynamic>;
    final revision = filing['approval_revision'] as String;
    // The stamp is the revision the PASSING preflight evaluated — the receipt
    // names WHAT was approved, not which commit the store sat on.
    expect(revision, startsWith(kFilingApprovalRevisionPrefix));
    expect(callMetadata(argv), {
      'grid.approved_by': 'nico',
      'grid.approved_at': '2026-09-02T14:30:00.000Z',
      'grid.approved_rev': revision,
      kReadinessGradeKey: 'B',
    });
    expect(report['approved'], isTrue);
    expect(report['by'], 'nico');
    expect(DateTime.parse(report['at'] as String).isUtc, isTrue);
    expect(report['rev'], revision);

    // The verb reached NO git: `/work/power_station` is a fiction, and only
    // the injected bd runner was ever spawned against it. ONE store, too —
    // the dependency rows are the work store's own.
    expect(Directory('/work/power_station').existsSync(), isFalse);
    expect(h.roots, everyElement(isNot(endsWith('.git'))));
    expect(h.roots.toSet(), {'/work/power_station'});
  });

  test('an external row is resolved through the station roster', () async {
    _ScriptedBdRunner bd() => _ScriptedBdRunner({
      'query': _beadReply(
        description: 'Needs the native external reader.',
        blockers: const ['external:the_grid:tg-xh5d'],
      ),
    });

    // NOT ARMED: the Q4 hard refusal — nothing is written.
    final unarmed = _harness(bd(), armed: const {'space'});
    expect(
      await unarmed.runner.run(['approve', '--actor', 'nico', 'pow-child']),
      1,
    );
    expect(
      unarmed.out.toString(),
      contains('external:the_grid:tg-xh5d names "the_grid"'),
    );
    expect(unarmed.bd.updates, isEmpty);

    // ARMED: an ordinary prerequisite, and the stamp lands.
    final armed = _harness(bd(), armed: const {'the_grid', 'space'});
    expect(
      await armed.runner.run(['approve', '--actor', 'nico', 'pow-child']),
      0,
      reason: '${armed.out}${armed.err}',
    );
    expect(armed.bd.updates, hasLength(1));
  });

  test('AC-3: the receipt is stable across runs and moves with the '
      'external row', () async {
    _ScriptedBdRunner armedRow(String capability) => _ScriptedBdRunner({
      'query': _beadReply(
        description: 'Needs the native external reader.',
        blockers: ['external:the_grid:$capability'],
      ),
    });

    Future<String> approvedRev(_ScriptedBdRunner bd) async {
      final h = _harness(bd, armed: const {'the_grid'});
      expect(
        await h.runner.run(['approve', '--actor', 'nico', 'pow-child']),
        0,
        reason: '${h.out}${h.err}',
      );
      expect(h.bd.updates, hasLength(1));
      return callMetadata(h.bd.updates.single)[kApprovedRevKey] as String;
    }

    // Two runs of the verb over the SAME bead and the SAME armed row write
    // ONE receipt value: re-approving an unedited bead is a no-op, so the
    // governor's one-time re-approval sweep can be re-run without churning
    // the beads it already swept.
    final revision = await approvedRev(armedRow('tg-xh5d'));
    expect(revision, startsWith('filing:v2:sha256:'));
    expect(await approvedRev(armedRow('tg-xh5d')), revision);

    // The ROW is basis. Re-pointing it at another capability of the same
    // armed project is a different thing to have approved, so it is a
    // different receipt — the cross-store shape the retired link-proof member
    // used to claim to cover.
    expect(await approvedRev(armedRow('tg-other')), isNot(revision));
  });

  test('no roster refuses the external row fail-closed', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(
          description: 'Needs the native external reader.',
          blockers: const ['external:the_grid:tg-xh5d'],
        ),
      }),
    );

    expect(await h.runner.run(['approve', '--actor', 'nico', 'pow-child']), 1);
    expect(
      h.out.toString(),
      contains('FAIL dependencies: unresolvable external dependency rows:'),
    );
    expect(h.out.toString(), contains('no station roster was supplied'));
    expect(h.bd.updates, isEmpty);
  });

  test('the verb takes no state root at all', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'No local ordering.'),
      }),
    );

    // The option is GONE, not accepted-and-ignored: a root the verb never
    // reads teaches an operator that the root matters to its answer.
    await expectLater(
      h.runner.run([
        'approve',
        '--actor',
        'nico',
        '--state-root',
        _gridHome(),
        'pow-child',
      ]),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('state-root'),
        ),
      ),
    );
    expect(h.bd.updates, isEmpty);

    // Without it, ONE store answers the whole verb.
    final plain = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'No local ordering.'),
      }),
    );
    expect(
      await plain.runner.run([
        'approve',
        '--actor',
        'nico',
        '--json',
        'pow-child',
      ]),
      0,
      reason: '${plain.out}${plain.err}',
    );
    expect(plain.roots.toSet(), {'/work/power_station'});
    expect(plain.err.toString(), isEmpty);
  });

  test('a missing actor is a usage refusal that spawns nothing', () async {
    final h = _harness(_ScriptedBdRunner(const {}));

    expect(await h.runner.run(['approve', 'pow-child']), 64);
    expect(h.err.toString(), contains('--actor'));
    expect(h.bd.argvs, isEmpty);
  });

  test('a refused bd update is reported, never claimed as approval', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'No local ordering.'),
      }, updateExitCode: 1),
    );

    expect(
      await h.runner.run(['approve', '--json', '--actor', 'nico', 'pow-child']),
      1,
    );
    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(report['approved'], isFalse);
    expect(report['reason'], contains('bd update refused'));
  });

  group('the pre-stamp advisory decides whether the stamp lands', () {
    _ScriptedBdRunner ready() => _ScriptedBdRunner({
      'query': _beadReply(description: 'A real brief with no ordering.'),
    });

    test('AC-1 — a D verdict refuses with the lens\'s exact FIX text and '
        'issues NO bd update', () async {
      final hold = renderRefinementAsk(
        grade: 'D',
        rationale: 'names no surface and no decision',
      );
      final h = _harness(
        ready(),
        advisory: FakeFilingAdvisory(
          FilingAdvisoryRefused(rule: 'readiness', reason: hold),
        ),
      );

      expect(
        await h.runner.run(['approve', '--actor', 'nico', 'pow-child']),
        1,
      );
      // VERBATIM: the refiner reads the identical hold a spec_review gate
      // would have parked with, at the moment the bead text is open.
      expect(h.out.toString(), contains(hold));
      expect(h.out.toString(), contains('FAIL advisory (readiness)'));
      expect(h.bd.updates, isEmpty);
    });

    test('AC-1 — an A-C verdict stamps once and records the grade', () async {
      for (final grade in const ['A', 'B', 'C']) {
        final h = _harness(
          ready(),
          advisory: FakeFilingAdvisory(
            FilingAdvisoryPassed(readinessGrade: grade),
          ),
        );
        expect(
          await h.runner.run([
            'approve',
            '--json',
            '--actor',
            'nico',
            'pow-child',
          ]),
          0,
          reason: '${h.out}${h.err}',
        );
        expect(h.bd.updates, hasLength(1));
        final written = callMetadata(h.bd.updates.single);
        expect(written[kReadinessGradeKey], grade);
        expect(written.containsKey(kReadinessSkippedKey), isFalse);
        expect(written.containsKey(kApprovedAdvisoryKey), isFalse);
        // The three-key receipt tuple is untouched — it is still the whole of
        // what makes a stamp readable.
        expect(
          written.keys,
          containsAll([kApprovedByKey, kApprovedAtKey, kApprovedRevKey]),
        );
        final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
        expect(report['readiness_grade'], grade);
        expect((report['filing'] as Map<String, dynamic>)['advisory'], {
          'outcome': 'passed',
          'readiness_grade': grade,
        });
      }
    });

    test('AC-4 — --readiness=skip stamps anyway, records the waiver and no '
        'grade, and asks the advisory NOTHING', () async {
      final advisory = FakeFilingAdvisory();
      final h = _harness(ready(), advisory: advisory);

      expect(
        await h.runner.run([
          'approve',
          '--json',
          '--readiness=skip',
          '--actor',
          'nico',
          'pow-child',
        ]),
        0,
        reason: '${h.out}${h.err}',
      );
      expect(advisory.calls, isEmpty, reason: 'a waiver spends no inference');
      expect(h.bd.updates, hasLength(1));
      final written = callMetadata(h.bd.updates.single);
      expect(written[kReadinessSkippedKey], 'true');
      expect(written[kApprovedAdvisoryKey], kApprovedAdvisorySkipped);
      expect(written.containsKey(kReadinessGradeKey), isFalse);
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      expect(report['readiness_skipped'], isTrue);
      expect(report.containsKey('readiness_grade'), isFalse);
    });

    test(
      'a MECHANICAL failure refuses before the advisory is ever asked',
      () async {
        final advisory = FakeFilingAdvisory();
        final h = _harness(
          _ScriptedBdRunner({
            'query': _beadReply(
              description: 'Needs the native external reader.',
              blockers: const ['external:the_grid:tg-xh5d'],
            ),
          }),
          advisory: advisory,
        );

        expect(
          await h.runner.run(['approve', '--actor', 'nico', 'pow-child']),
          1,
        );
        expect(h.out.toString(), contains('FAIL dependencies:'));
        expect(h.out.toString(), isNot(contains('FAIL advisory')));
        expect(advisory.calls, isEmpty);
        expect(h.bd.updates, isEmpty);
      },
    );

    test('the advisory provenance is NOT part of the receipt tuple — a stamp '
        'carrying none of it still parses', () {
      // `ApprovalStamp.tryParse` reads exactly three keys, so every receipt
      // minted before the advisory existed is exactly as valid as one minted
      // with it. Widening the tuple would strand them all.
      Bead stamped(Map<String, Object?> extra) =>
          const Bead(
            id: 'pow-x',
            title: 'x',
            issueType: IssueType.task,
          ).copyWith(
            metadata: {
              kApprovedByKey: 'nico',
              kApprovedAtKey: '2026-09-02T14:30:00.000Z',
              kApprovedRevKey: '$kFilingApprovalRevisionPrefix${'a' * 64}',
              ...extra,
            },
          );

      expect(isApprovalStamped(stamped(const {})), isTrue);
      expect(
        isApprovalStamped(stamped(const {kReadinessGradeKey: 'A'})),
        isTrue,
      );
      expect(
        isApprovalStamped(
          stamped(const {
            kReadinessSkippedKey: 'true',
            kApprovedAdvisoryKey: kApprovedAdvisorySkipped,
          }),
        ),
        isTrue,
      );
      // And the writer never emits both halves at once.
      const graded = ApprovalStamp(
        by: 'nico',
        at: '2026-09-02T14:30:00.000Z',
        rev: 'abcdef1',
        readinessGrade: 'B',
      );
      const waived = ApprovalStamp(
        by: 'nico',
        at: '2026-09-02T14:30:00.000Z',
        rev: 'abcdef1',
        advisorySkipped: true,
      );
      expect(graded.metadata.keys, [
        kApprovedByKey,
        kApprovedAtKey,
        kApprovedRevKey,
        kReadinessGradeKey,
      ]);
      expect(waived.metadata.keys, [
        kApprovedByKey,
        kApprovedAtKey,
        kApprovedRevKey,
        kReadinessSkippedKey,
        kApprovedAdvisoryKey,
      ]);
    });
  });
}

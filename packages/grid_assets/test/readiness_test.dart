// The spec-readiness INTAKE lens (bead `pow-q7n`) — the pure matrix + the three
// capability seams.
//
// Proves: the deterministic intake contract is LOUD, pure and DELIBERATELY
// NARROW (a non-driveable type or an EMPTY description holds; a terse or
// placeholder-MENTIONING human description does NOT — a structural fence on a
// human's prose is a false-HOLD machine); driveability is CONSUMED from
// grid_engine, never re-declared; the readiness matrix is total and FAIL-CLOSED
// (a missing verdict holds, never advances); and the lens is CHEAP — exactly ONE
// agent-backed step runs upstream of `specify`.
//
// Offline only: no live claude/git/network; the critique-dir clearer is a
// recording no-op (Fakes, not mocks).
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A REFINED bead — a driveable type carrying a substantive human brief (modelled
/// on the live `pow-kzx`, which the wide run's spec committee PASSED).
Bead _refined() => bead('pow-kzx').copyWith(
  issueType: IssueType.feature,
  title: 'grid_assets: station_overlay skill-file delivery',
  description:
      'DECIDED (Nico): approach = SKILL-FILE INSTALL. SCOPE (grid_assets, '
      'in-store): the format, the materialization lib, AND the in-store '
      'provision hook. Wire it at per-bead worktree PROVISION via '
      'AgentCapability._linkWorkspace (the sanctioned hook, ADR-0000 A1). '
      'ACCEPTANCE (dart test): the format round-trips; the materializer is '
      'non-destructive; the lib has NO CLI dependency.',
);

void _noop(String dir) {}

/// Every step [stepId] transitively `dependsOn` — the mirror of the engine's own
/// `transitiveDependents` (which the rewind-set fence uses), walked the other way.
/// The engine exports no ancestors helper, so this test computes it.
Set<String> _ancestorsOf(Circuit circuit, String stepId) {
  final byId = {for (final s in circuit.steps) s.stepId: s};
  final seen = <String>{};
  final stack = [...byId[stepId]!.dependsOn];
  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    if (!seen.add(id)) continue;
    stack.addAll(byId[id]!.dependsOn);
  }
  return seen;
}

Future<RouteVerdict> _runIntake(Bead b, {DirectoryClearer clearer = _noop}) =>
    IntakeCapability(clearer: clearer).route(
      FakeTreeContext(
        values: {
          Bead: b,
          Workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1'),
        },
      ),
      stepArgs('tg-1/$kIntakeNode'),
    );

Future<RouteVerdict> _runRoute({String? grade, String rationale = ''}) {
  const parent = 'tg-1/spec_review';
  return const ReadinessRouteCapability().route(
    FakeTreeContext(
      values: {
        SiblingView: SiblingView(
          cursor: {
            '$parent/$kReadinessStep': const NodeCursor(
              state: StepState.complete,
            ),
          },
          results: {
            '$parent/$kReadinessStep': {
              if (grade != null) 'grade': grade,
              if (rationale.isNotEmpty) 'rationale': rationale,
            },
          },
        ),
      },
    ),
    stepArgs(
      '$parent/$kReadinessRouteStep',
      params: const {'lane': kReadinessStep},
    ),
  );
}

void main() {
  group('intakeFindings — the deterministic contract (tier 1)', () {
    test('a REFINED bead has NO findings — it reaches the lens', () {
      expect(intakeFindings(_refined()), isEmpty);
    });

    test('a NON-DRIVEABLE type is held and NAMED (the live `pow-p94` is a '
        '`decision` bead, and a NON-resident station DOES mount it)', () {
      final findings = intakeFindings(
        _refined().copyWith(issueType: IssueType.decision),
      );
      expect(findings, hasLength(1));
      expect(findings.single, contains('decision'));
      expect(findings.single, contains('not a driveable type'));
    });

    test('an EPIC is held (decompose first, never drive)', () {
      expect(
        intakeFindings(_refined().copyWith(issueType: IssueType.epic)),
        isNotEmpty,
      );
    });

    test('an EMPTY description is held — nobody can specify a bead with no '
        'brief', () {
      final findings = intakeFindings(_refined().copyWith(description: '  '));
      expect(findings, hasLength(1));
      expect(findings.single, contains('EMPTY'));
    });

    // The false-HOLD correction: tier 1 NEVER reads the human description
    // structurally. ADR-0000 A13(10)'s placeholder fence is for the fields the
    // specify AGENT writes to a known contract, not for a human's prose.
    test(
      'a TERSE chore bead PASSES — there is no length floor on human prose',
      () {
        final terse = _refined().copyWith(
          issueType: IssueType.chore,
          description: 'Delete the dead flag.',
        );
        expect(intakeFindings(terse), isEmpty);
      },
    );

    test('an UNBACKTICKED placeholder token in the human description does NOT '
        'hold the bead — that is the LENS\'s judgement, not a machine\'s', () {
      for (final prose in <String>[
        'Remove the TODO markers the old parser left behind.',
        'The rollout date is TBD but the code change is decided: drop the shim.',
      ]) {
        expect(
          intakeFindings(_refined().copyWith(description: prose)),
          isEmpty,
          reason: 'a human brief must never be parked by a token match',
        );
      }
    });

    test('BOTH violations are named at once — guards LOUD', () {
      final findings = intakeFindings(
        _refined().copyWith(issueType: IssueType.epic, description: ''),
      );
      expect(findings, hasLength(2));
    });
  });

  group('intakeFindings — the single source of truth for driveability', () {
    test('it accepts exactly grid_engine\'s driveableTypes, and holds every '
        'other core type', () {
      for (final t in driveableTypes) {
        expect(
          intakeFindings(_refined().copyWith(issueType: t)),
          isEmpty,
          reason: '${t.wire} is driveable per grid_engine',
        );
      }
      for (final t in IssueType.coreTypes.where((t) => !t.isDriveable)) {
        expect(
          intakeFindings(_refined().copyWith(issueType: t)),
          isNotEmpty,
          reason: '${t.wire} is NOT driveable per grid_engine',
        );
      }
    });

    test(
      'grid_assets declares NO second driveable-type list — the engine\'s is '
      'CONSUMED (two definitions would drift and park work nobody meant to)',
      () {
        final src = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .map((f) => f.readAsStringSync())
            .join('\n');
        expect(
          src,
          isNot(contains('kDriveableTypes')),
          reason: 'consume IssueTypeDriveability.isDriveable / driveableTypes',
        );
      },
    );
  });

  group('decideReadiness — the pure matrix (tier 3)', () {
    for (final grade in ['A', 'B', 'C', 'a', ' b ']) {
      test('grade "$grade" DRIVES', () {
        final verdict = decideReadiness(grade: grade, rationale: '');
        expect(verdict, isA<ReadinessDrive>());
        expect((verdict as ReadinessDrive).grade, grade.trim().toUpperCase());
      });
    }

    for (final grade in ['D', 'E', 'F']) {
      test('grade "$grade" HOLDS, carrying the rationale VERBATIM as the '
          'refinement ask', () {
        final verdict = decideReadiness(
          grade: grade,
          rationale: 'the bead never decides the layering',
        );
        expect(verdict, isA<ReadinessHold>());
        final hold = verdict as ReadinessHold;
        expect(hold.rule, 'not-ready');
        expect(hold.reason, contains('the bead never decides the layering'));
        expect(hold.reason, contains('HELD for refinement'));
        expect(
          hold.reason,
          contains('NO specify agent'),
          reason: 'the hold says plainly what was NOT spent',
        );
      });
    }

    test('an OFF-LADDER letter holds (fail-closed, never a silent drive)', () {
      expect(decideReadiness(grade: 'Z', rationale: ''), isA<ReadinessHold>());
    });

    test('a MISSING grade FAIL-CLOSES to a hold — a transport miss must never '
        'buy a free pass to the expensive fan-out', () {
      for (final missing in <String?>[null, '', '   ']) {
        final verdict = decideReadiness(grade: missing, rationale: '');
        expect(verdict, isA<ReadinessHold>());
        expect((verdict as ReadinessHold).rule, 'no-verdict');
      }
    });

    test(
      'a D with NO rationale still holds, and says how to refine anyway',
      () {
        final verdict = decideReadiness(grade: 'D', rationale: '');
        expect(verdict, isA<ReadinessHold>());
        expect((verdict as ReadinessHold).reason, contains('rubric bands'));
      },
    );
  });

  group('IntakeCapability — gates BEFORE any agent (tier 1)', () {
    test('a driveable bead advances with provenance', () async {
      final out = await _runIntake(_refined());
      expect(out, isA<Advance>());
      expect((out as Advance).payload, {
        'verdict': 'driveable',
        'type': 'feature',
      });
    });

    test('a `decision` bead GATES — the hold NAMES the finding', () async {
      final out = await _runIntake(
        _refined().copyWith(issueType: IssueType.decision),
      );
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('INTAKE HOLD'));
      expect(out.reason, contains('not a driveable type'));
      expect(
        out.reason,
        contains('NO agent ran at all'),
        reason: 'the whole saving is the un-spawned agent',
      );
    });

    test('a missing ambient bead GATES (fail-closed)', () async {
      final out = await const IntakeCapability(
        clearer: _noop,
      ).route(FakeTreeContext(values: const {}), stepArgs('tg-1/$kIntakeNode'));
      expect(out, isA<Escalate>());
    });

    test(
      'it WIPES the critique dir — the readiness lane\'s round-freshness '
      '(clear-critique only wipes DOWNSTREAM of specify, so it cannot)',
      () async {
        final wiped = <String>[];
        await _runIntake(_refined(), clearer: wiped.add);
        expect(wiped.single, endsWith('.grid/critique'));
      },
    );

    test('it RESETS the respec-round ledger — the counter is SESSION-scoped '
        '(bead pow-96s): a fresh session over a reused worktree starts at '
        'round zero instead of inheriting a prior session\'s rounds', () async {
      final dir = Directory.systemTemp.createTempSync('intake-ledger-');
      addTearDown(() => dir.deleteSync(recursive: true));
      // The prior session's spent counter, left behind in the worktree.
      writeRespecLedger(
        dir.path,
        const RespecLedger(
          round: kMaxRespecRounds,
          lanes: [
            RespecLane(
              rubric: 'coherence',
              grade: 'D',
              rationale: 'a prior session\'s correction',
            ),
          ],
        ),
      );
      final out = await const IntakeCapability(clearer: _noop).route(
        FakeTreeContext(
          values: {
            Bead: _refined(),
            Workspace: testWorkspace('tg-1', workspaceDir: dir.path),
          },
        ),
        stepArgs('tg-1/$kIntakeNode'),
      );
      expect(out, isA<Advance>());
      expect(
        readRespecLedger(dir.path),
        isNull,
        reason:
            'every lane\'s verdict-round stamp (`roundOf`) and the spec '
            'route\'s cap now start this session at round 0',
      );
    });
  });

  group('ReadinessRouteCapability — the decision point (tier 3)', () {
    test('grade A ⇒ Ok(drive) with route provenance', () async {
      final out = await _runRoute(grade: 'A');
      expect(out, isA<Advance>());
      expect((out as Advance).payload!['verdict'], 'drive');
      expect(out.payload!['grade'], 'A');
      expect(out.payload!['lane'], kReadinessStep);
      expect(out.payload!['rule'], 'ready');
    });

    test('grade D ⇒ Gate carrying the lens rationale VERBATIM', () async {
      final out = await _runRoute(
        grade: 'D',
        rationale: 'no acceptance shape; name the surfaces it touches',
      );
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('no acceptance shape'));
      expect(out.reason, contains('SPEC-READINESS HOLD'));
    });

    test('NO verdict ⇒ Gate (fail-closed)', () async {
      expect(await _runRoute(grade: null), isA<Escalate>());
    });
  });

  group('the lens is CHEAP — at most ONE agent upstream of specify', () {
    // A `RouteCapability` runs IN-PROCESS and NEVER spawns (the engine's own
    // contract — spawning is a `ProcessCapability`). So the two facts below —
    // (1) which of the ladder's capabilities can spawn at all, and (2) which
    // steps of the circuit sit upstream of `specify` — together bound the
    // ladder's agent cost at ONE. (That the REGISTRY wires these classes at
    // these ids is proven end-to-end, through the real kernel, in
    // `acceptance/readiness_acceptance_test.dart`: nothing spawns until intake
    // completes, and then exactly one process starts before specify.)
    test('intake + readiness-route CANNOT spawn (RouteCapability); readiness '
        'is the single agent-backed tier', () {
      expect(const IntakeCapability(), isA<RouteCapability>());
      expect(const IntakeCapability(), isNot(isA<ProcessCapability>()));
      expect(const ReadinessRouteCapability(), isA<RouteCapability>());
      expect(const ReadinessRouteCapability(), isNot(isA<ProcessCapability>()));
      expect(const ReadinessCriticCapability(), isA<ProcessCapability>());
    });

    test('the LADDER contributes exactly ONE agent lane upstream of `specify` — '
        'it replaces an ~18-agent round (specify + committee + up to 2 respecs) '
        'with one', () {
      // Everything upstream of the architect: the ladder's three steps, plus the
      // DISCOVERY sub-circuit spliced in behind them (`discovery.dart`).
      final upstream = _ancestorsOf(kSpecReviewCircuit, kSpecifyStep);
      expect(upstream, {
        kIntakeStep,
        kReadinessStep,
        kReadinessRouteStep,
        kDiscoveryCircuitId,
      });
      final byId = {for (final s in kSpecReviewCircuit.steps) s.stepId: s};
      // The LADDER's own steps carry exactly ONE agent lane; its other two are
      // deterministic (zero agents). Discovery's cost is its own circuit's, and
      // its three explorers ride the CHEAP tier (`discovery_test.dart`).
      final ladder = [
        for (final id in upstream)
          if (byId[id] case final CapabilityStep step) step,
      ];
      expect(
        ladder.map((s) => s.stepId),
        {kIntakeStep, kReadinessStep, kReadinessRouteStep},
        reason:
            'the ladder is the only CapabilityStep run upstream of specify; '
            'discovery is a SubCircuitStep',
      );
      expect(
        [
          for (final step in ladder)
            if (step.capabilityId == kReadinessStep) step.stepId,
        ],
        [kReadinessStep],
      );
    });
  });

  group('buildReadinessPrompt — the lens brief', () {
    test('malformed verdict gets one structured re-ask', () {
      final dir = Directory.systemTemp.createTempSync('readiness-reask-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'pow-kzx/spec_review/readiness';
      File('${dir.path}/.grid/critique/$kReadinessRubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      final context = FakeTreeContext(
        values: {
          Bead: _refined(),
          Workspace: testWorkspace(
            'pow-kzx',
            workspaceDir: dir.path,
            branch: 'grid/pow-kzx',
          ),
        },
      );
      final cfg = const ReadinessCriticCapability().spawn(
        context,
        stepArgs(
          nodePath,
          params: {'rubric': kReadinessRubric, 'grid.round': '0'},
        ),
      );
      final prompt = cfg.args.join(' ');
      expect(prompt, contains('## Verdict contract repair'));
      expect(prompt.split('## Verdict contract repair').length - 1, 1);
    });

    test('grades the BEAD (no spec, no diff), stamps the nodePath + round, and '
        'names the ABSOLUTE verdict path LAST (tg-291 recency + '
        'gate-integrity #4)', () {
      final prompt = const ReadinessCriticCapability().buildReadinessPrompt(
        _refined(),
        kReadinessRubric,
        'pow-kzx/spec_review/readiness',
        '/w/pow-kzx',
        round: 0,
      );
      expect(prompt, contains('grading the WORK BEAD ITSELF'));
      expect(prompt, contains('has NOT been specified'));
      expect(prompt, contains('has NOT been built'));
      // The bead itself rides the prompt (a title-only brief starves the lens).
      expect(prompt, contains('pow-kzx'));
      expect(prompt, contains('SKILL-FILE INSTALL'));
      expect(prompt, contains('type: `feature`'));
      // The freshness stamps + the cheapness budget. The lens sits upstream of
      // every rewind set, so 0 is its permanent round — it stamps because it
      // shares ONE reader with the lanes that DO rewind (A15(5) alt-A).
      expect(
        prompt,
        contains('"nodePath":"pow-kzx/spec_review/readiness","round":0}'),
      );
      expect(prompt, contains('Stay cheap'));
      expect(
        prompt.trimRight(),
        endsWith(
          'Write the file at `/w/pow-kzx/.grid/critique/$kReadinessRubric.json`.',
        ),
      );
    });

    test('anti-anchoring: it names ONLY its own rubric, never a spec-committee '
        'lane', () {
      final prompt = const ReadinessCriticCapability().buildReadinessPrompt(
        _refined(),
        kReadinessRubric,
        'pow-kzx/spec_review/readiness',
        '/w/pow-kzx',
        round: 0,
      );
      for (final other in kSpecLlmRubrics) {
        expect(prompt, isNot(contains(other)));
      }
    });
  });
}

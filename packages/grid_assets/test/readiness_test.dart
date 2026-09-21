// The spec-readiness INTAKE lens (bead `pow-q7n`) — the pure matrix + the three
// capability seams.
//
// Proves: the deterministic intake contract is LOUD, pure and DELIBERATELY
// NARROW (a non-driveable type or an EMPTY description holds; a terse or
// placeholder-MENTIONING human description does NOT — a structural fence on a
// human's prose is a false-HOLD machine); driveability is CONSUMED from
// grid_engine, never re-declared; the readiness matrix is total and no arm ever
// buys a free pass to the fan-out (a missing verdict never advances); and the
// lens is CHEAP — exactly ONE agent-backed step runs upstream of `specify`.
//
// Also proves the route JOINS rather than routes over absence: a lane result
// that has not been published yet is WAITED for (never a hold), a lane that
// finished without publishing FAILS loudly naming the missing invocation, and a
// lane still silent at its budget fails loudly too.
//
// Offline only: no live claude/git/network; the critique-dir clearer is a
// recording no-op (Fakes, not mocks). The join probes write real verdict JSON
// into a `Directory.systemTemp` workspace — the only filesystem this suite
// touches, torn down per test, and never the process working directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';
import 'support/package_root.dart';

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

/// The spec_review parent every route probe hangs its lane off.
const _parent = 'tg-1/spec_review';

/// The readiness LANE's node path — the freshness stamp every verdict below
/// carries (ADR-0000 A4's foreign-node fence).
const _lanePath = '$_parent/$kReadinessStep';

/// The route's own node path.
const _routePath = '$_parent/$kReadinessRouteStep';

/// The OFFLINE route drive: no [Workspace], so the lane's recorded step result
/// is the join candidate (the synthetic posture the rest of this suite runs in).
Future<RouteVerdict> _runRoute({String? grade, String rationale = ''}) =>
    const ReadinessRouteCapability().route(
      FakeTreeContext(
        values: {
          SiblingView: SiblingView(
            cursor: {_lanePath: const NodeCursor(state: StepState.complete)},
            results: {
              _lanePath: {
                if (grade != null) 'grade': grade,
                if (rationale.isNotEmpty) 'rationale': rationale,
              },
            },
          ),
        },
      ),
      stepArgs(
        _routePath,
        params: const {'lane': kReadinessStep, 'grid.round': '0'},
      ),
    );

/// A live temp WORKSPACE, torn down with the test. Never the process working
/// directory — every path below is absolute and derived from this root.
Directory _liveWorkspace() {
  final dir = Directory.systemTemp.createTempSync('readiness-join-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Writes the `bead-readiness` lens's verdict to its CANONICAL path under
/// [workspaceDir], exactly as the lane writes it: both freshness stamps, a
/// non-empty rationale, flushed so the route's next read sees a complete file.
void _publishVerdict(
  String workspaceDir, {
  required String grade,
  String rationale = 'the bead decides its approach and names its surfaces',
  String nodePath = _lanePath,
  int round = 0,
}) {
  final dir = Directory(critiqueDirPath(workspaceDir))
    ..createSync(recursive: true);
  File(p.join(dir.path, '$kReadinessRubric.json')).writeAsStringSync(
    jsonEncode({
      'rubric': kReadinessRubric,
      'version': 1,
      'grade': grade,
      'rationale': rationale,
      'nodePath': nodePath,
      kVerdictRoundKey: round,
    }),
    flush: true,
  );
}

/// The canonical verdict path the route NAMES in its provenance and its
/// failures.
String _verdictPath(String workspaceDir) =>
    p.join(critiqueDirPath(workspaceDir), '$kReadinessRubric.json');

/// A LIVE route drive over [dir], with the lane's cursor [state] and the join
/// tuning under test.
Future<RouteVerdict> _runLiveRoute(
  Directory dir, {
  StepState state = StepState.pending,
  Duration lanePoll = const Duration(milliseconds: 2),
  Duration laneWaitBudget = const Duration(seconds: 30),
  FakeTreeContext? context,
}) =>
    ReadinessRouteCapability(
      lanePoll: lanePoll,
      laneWaitBudget: laneWaitBudget,
    ).route(
      context ?? _liveContext(dir, state: state),
      stepArgs(
        _routePath,
        params: const {'lane': kReadinessStep, 'grid.round': '0'},
      ),
    );

/// The ambient values a LIVE route drive reads: the temp workspace plus the
/// lane's cursor.
FakeTreeContext _liveContext(
  Directory dir, {
  StepState state = StepState.pending,
}) => FakeTreeContext(
  values: {
    Workspace: testWorkspace('tg-1', workspaceDir: dir.path),
    SiblingView: SiblingView(cursor: {_lanePath: NodeCursor(state: state)}),
  },
);

void main() {
  test('ReadinessCriticCapability inherits artifact durability', () {
    expect(
      const ReadinessCriticCapability().completionContract,
      CompletionContract.artifactDurability,
    );
  });

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
        final src = Directory(p.join(packageRoot(), 'lib'))
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

    test('a MISSING grade is ABSENT, not a hold — nothing was published, so '
        'there is nothing to route over (it still never DRIVES)', () {
      for (final missing in <String?>[null, '', '   ']) {
        final verdict = decideReadiness(grade: missing, rationale: '');
        expect(verdict, isA<ReadinessAbsent>());
        expect(
          verdict,
          isNot(isA<ReadinessDrive>()),
          reason: 'absence must never buy a free pass to the expensive fan-out',
        );
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
          sessionRoot: 'tg-1',
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
        readRespecLedger(dir.path, expectedSessionRoot: 'tg-1'),
        isNull,
        reason:
            'every lane\'s verdict-round stamp (`roundOf`) and the spec '
            'route\'s cap now start this session at round 0',
      );
    });

    test('the session head also clears the prior session\'s FIX-IN-FLIGHT '
        'carry and REFINEMENT flag (bead pow-bhm)', () async {
      final dir = Directory.systemTemp.createTempSync('intake-carry-');
      addTearDown(() => dir.deleteSync(recursive: true));
      // The prior session's two worktree channels. Both are SIBLINGS of
      // `.grid/critique/` (they live under `.grid/spec/`), so the per-round
      // critique sweep never touches them — only this session-head clear does.
      writeFixInFlight(
        dir.path,
        const FixInFlight(
          sessionRoot: 'tg-1',
          round: 2,
          lane: RespecLane(
            rubric: 'coherence',
            grade: 'D',
            rationale: 'a prior session\'s carried finding',
          ),
        ),
      );
      writeRefinementFlag(
        dir.path,
        const RefinementFlag(
          sessionRoot: 'tg-1',
          round: 2,
          notes: [
            RefinementNote(
              rubric: 'coherence',
              finding: 'a prior session\'s tracker note',
            ),
          ],
        ),
      );
      expect(File(fixInFlightPath(dir.path)).existsSync(), isTrue);
      expect(File(refinementFlagPath(dir.path)).existsSync(), isTrue);

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
      expect(readFixInFlight(dir.path), isNull);
      expect(readRefinementFlag(dir.path), isNull);
      // DELETED, not merely unreadable: both decoders degrade a corrupt
      // document to null, so only the file-level check pins the clear — a
      // reused worktree inherits nothing.
      expect(File(fixInFlightPath(dir.path)).existsSync(), isFalse);
      expect(File(refinementFlagPath(dir.path)).existsSync(), isFalse);
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
      expect(out.payload!['source-state'], 'PRESENT');
      expect(
        out.payload!['transport'],
        'sibling-view',
        reason: 'the offline posture joins on the lane\'s recorded result',
      );
    });

    test('grade D ⇒ Gate carrying the lens rationale VERBATIM', () async {
      final out = await _runRoute(
        grade: 'D',
        rationale: 'no acceptance shape; name the surfaces it touches',
      );
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('no acceptance shape'));
      expect(out.reason, contains('SPEC-READINESS HOLD'));
      expect(out.reason, contains('VERDICT SOURCE: PRESENT'));
    });

    test('NO verdict on a COMPLETED lane FAILS — it never mints a hold on an '
        'absence', () async {
      await expectLater(
        _runRoute(grade: null),
        throwsA(
          isA<RouteFailure>().having(
            (f) => f.reason,
            'reason',
            allOf(contains('ABSENT'), contains('missing invocation')),
          ),
        ),
      );
    });
  });

  // THE JOIN (the 2026-09-14 incident, twelve rounds across four substations):
  // the route read the lane's result BEFORE it was visible and escalated on
  // "no verdict" while the lens's grade sat on disk. Absence is now a join
  // state — waited for, and LOUD when the lane really did not publish.
  group('ReadinessRouteCapability — the lane JOIN (live workspace)', () {
    test('a late readiness verdict is waited for and advances after its '
        'current-round JSON lands', () async {
      final dir = _liveWorkspace();
      final context = _liveContext(dir);
      var settled = false;
      final routed = _runLiveRoute(dir, context: context).whenComplete(() {
        settled = true;
      });

      // The lane is mid-flight: nothing on disk, nothing in the view. The
      // route must still be WAITING, not holding.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        settled,
        isFalse,
        reason: 'an ABSENT lane result is waited for, never escalated on',
      );

      // The lens publishes: its verdict lands first, its result becomes
      // visible second — the real ordering the incident raced against.
      _publishVerdict(dir.path, grade: 'B');
      context.provide<SiblingView>(
        SiblingView(
          cursor: {_lanePath: const NodeCursor(state: StepState.complete)},
          results: {
            _lanePath: const {'grade': 'B', 'rationale': 'specifiable'},
          },
        ),
      );

      final out = await routed;
      expect(out, isA<Advance>());
      expect((out as Advance).payload!['grade'], 'B');
      expect(out.payload!['source-state'], 'PRESENT');
      expect(out.payload!['source-path'], _verdictPath(dir.path));
      expect(out.payload!['transport'], 'file');
      expect(
        out,
        isNot(isA<Escalate>()),
        reason: 'a late verdict must never mint a gate',
      );
    });

    test('a completed readiness lane without current-round JSON fails loudly '
        'instead of holding', () async {
      final dir = _liveWorkspace();
      await expectLater(
        _runLiveRoute(dir, state: StepState.complete),
        throwsA(
          isA<RouteFailure>().having(
            (f) => f.reason,
            'reason',
            allOf(
              contains('ABSENT'),
              contains('missing invocation'),
              contains(_lanePath),
              contains(_verdictPath(dir.path)),
            ),
          ),
        ),
      );
    });

    test('present readiness JSON preserves passing and failing routes with '
        'source provenance', () async {
      for (final grade in ['A', 'B', 'C']) {
        final dir = _liveWorkspace();
        _publishVerdict(dir.path, grade: grade);
        final out = await _runLiveRoute(dir, state: StepState.complete);
        expect(out, isA<Advance>());
        expect((out as Advance).payload, {
          'verdict': 'drive',
          'grade': grade,
          'lane': kReadinessStep,
          'rule': 'ready',
          'source-state': 'PRESENT',
          'source-path': _verdictPath(dir.path),
          'transport': 'file',
        });
      }

      for (final grade in ['D', 'E', 'F']) {
        final dir = _liveWorkspace();
        _publishVerdict(
          dir.path,
          grade: grade,
          rationale: 'no acceptance shape; name the surfaces it touches',
        );
        final out = await _runLiveRoute(dir, state: StepState.complete);
        expect(out, isA<Escalate>());
        expect((out as Escalate).reason, contains('SPEC-READINESS HOLD'));
        expect(out.reason, contains('no acceptance shape'));
        expect(
          out.reason,
          contains(
            'VERDICT SOURCE: PRESENT — ${_verdictPath(dir.path)} via file.',
          ),
        );
      }

      // The NEGATIVE controls — the fences are the committee reader's own, so
      // a foreign node's verdict and a prior round's verdict are ABSENT here,
      // never a grade this route could act on.
      for (final stale in [
        (nodePath: '$_parent/some-other-lane', round: 0),
        (nodePath: _lanePath, round: 7),
      ]) {
        final dir = _liveWorkspace();
        _publishVerdict(
          dir.path,
          grade: 'A',
          nodePath: stale.nodePath,
          round: stale.round,
        );
        await expectLater(
          _runLiveRoute(dir, state: StepState.complete),
          throwsA(
            isA<RouteFailure>().having(
              (f) => f.reason,
              'reason',
              contains('ABSENT'),
            ),
          ),
          reason: 'a verdict failing a freshness fence never joins',
        );
      }
    });

    test('a readiness lane still silent past its wait budget fails loudly '
        'naming the budget', () async {
      final dir = _liveWorkspace();
      await expectLater(
        _runLiveRoute(
          dir,
          lanePoll: const Duration(milliseconds: 2),
          laneWaitBudget: const Duration(milliseconds: 30),
        ),
        throwsA(
          isA<RouteFailure>().having(
            (f) => f.reason,
            'reason',
            allOf(
              contains('0s'),
              contains('30ms'),
              contains(_lanePath),
              contains(_verdictPath(dir.path)),
            ),
          ),
        ),
      );
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
      final args = stepArgs(
        nodePath,
        params: {'rubric': kReadinessRubric, 'grid.round': '0'},
      );
      final firstPrompt = const ReadinessCriticCapability()
          .spawn(context, args)
          .args
          .join(' ');
      expect(firstPrompt, isNot(contains('## Verdict contract repair')));
      File('${dir.path}/.grid/critique/$kReadinessRubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      final cfg = const ReadinessCriticCapability().spawn(context, args);
      final prompt = cfg.args.join(' ');
      expect(prompt, contains('## Verdict contract repair'));
      expect(prompt.split('## Verdict contract repair').length - 1, 1);
    });

    test('spawn records THIS incarnation for the readiness lens — one proof, '
        'three critic families', () {
      final dir = Directory.systemTemp.createTempSync('readiness-mark-');
      addTearDown(() => dir.deleteSync(recursive: true));
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
      final args = stepArgs(
        'pow-kzx/spec_review/readiness',
        params: {'rubric': kReadinessRubric, 'grid.round': '0'},
      );
      const ReadinessCriticCapability().spawn(context, args);
      expect(
        File(criticIncarnationPath(dir.path, kReadinessRubric)).existsSync(),
        isTrue,
      );
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
      // This lens composes NO grid home, so it names no invocation at all.
      expect(prompt, contains('composing grid home is bound'));
      expect(prompt, contains('EVERY mounted register'));
      expect(prompt, isNot(contains('space decisions index')));
      for (final token in kLocalOnlyTokens) {
        expect(prompt, isNot(contains(token)));
      }
      expect(
        prompt.trimRight(),
        endsWith('never reuse one writer\'s temporary path in another writer.'),
      );
      expect(prompt, contains('mktemp "/w/pow-kzx/.grid/critique/'));
      expect(prompt, contains('mv -f -- "\$verdict_tmp"'));
    });

    test('a BOUND station composes a lens lookup it can RUN — its own verb, '
        'from the grid home that verb resolves in', () {
      final prompt =
          const ReadinessCriticCapability(
            decisionRunner: 'dart run lunar:lunar',
            decisionGridHome: '/grid/lunar',
          ).buildReadinessPrompt(
            _refined(),
            kReadinessRubric,
            'pow-kzx/spec_review/readiness',
            '/w/pow-kzx',
            round: 0,
          );
      expect(
        prompt,
        contains("cd '/grid/lunar' && dart run lunar:lunar decisions index"),
      );
      expect(prompt, contains('mounted-substation roster'));
      expect(prompt, contains('ONCE'));
      // The whole-union form: no `--surface`, and no register directory.
      expect(prompt, isNot(contains('decisions index --surface')));
      expect(prompt, isNot(contains('space decisions index')));
      for (final token in kLocalOnlyTokens) {
        expect(prompt, isNot(contains(token)));
      }
    });

    test('ONE builder serves both call sites — the capability method IS the '
        'shared artifact-arm prompt', () {
      // The pin behind the pre-stamp advisory: the in-pipeline lane and the
      // filing verbs reach the same text through the same function, so a
      // hardening landed for one is landed for both.
      expect(
        const ReadinessCriticCapability().buildReadinessPrompt(
          _refined(),
          kReadinessRubric,
          'pow-kzx/spec_review/readiness',
          '/w/pow-kzx',
          round: 0,
        ),
        readinessLensPrompt(
          bead: _refined(),
          rubric: kReadinessRubric,
          nodePath: 'pow-kzx/spec_review/readiness',
          workspaceDir: '/w/pow-kzx',
          round: 0,
          transport: const LensArtifactTransport(),
        ),
      );
    });

    test('the FILELESS arm shares the whole body and swaps ONLY the closing '
        'destination paragraph', () {
      const args = (
        rubric: kReadinessRubric,
        nodePath: 'pow-kzx/spec_review/readiness',
        workspaceDir: '/w/pow-kzx',
      );
      final body = readinessLensPromptBody(
        bead: _refined(),
        rubric: args.rubric,
        nodePath: args.nodePath,
        round: 0,
      );
      String promptFor(LensResultTransport transport) => readinessLensPrompt(
        bead: _refined(),
        rubric: args.rubric,
        nodePath: args.nodePath,
        workspaceDir: args.workspaceDir,
        round: 0,
        transport: transport,
      );
      final artifact = promptFor(const LensArtifactTransport());
      final inProcess = promptFor(const LensInProcessTransport());

      // Same judgement, same rubric, same verdict schema — byte-for-byte.
      expect(artifact, startsWith(body));
      expect(inProcess, startsWith(body));
      expect(body, contains('"nodePath":"${args.nodePath}","round":0}'));

      // The ONE difference: the fileless arm names NO path and forbids a write,
      // so an advisory run can never leave an artifact a route would read.
      expect(
        inProcess.substring(body.length).trim(),
        kInProcessResultInstruction,
      );
      expect(inProcess, isNot(contains('mktemp')));
      expect(inProcess, isNot(contains('.grid/critique')));
      expect(inProcess, contains('write NO file'));
      expect(artifact, contains('mktemp "/w/pow-kzx/.grid/critique/'));
    });

    test('verdictFromResultText recovers the grade a FILELESS lens replies '
        'with — last answer wins', () {
      final recovered = verdictFromResultText(
        'Thinking: this might be {"grade":"B","rationale":"draft"} …\n'
        'Final: {"grade":"D","rationale":"names no surface"}',
      );
      expect(recovered?['grade'], 'D');
      expect(recovered?['rationale'], startsWith('names no surface'));
      expect(verdictFromResultText('no verdict here'), isNull);
      expect(verdictFromResultText(null), isNull);
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

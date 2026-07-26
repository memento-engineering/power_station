// The spec-route AUTO-RESPEC arm (bead `pow-7nm`) — the three-way matrix
// (advance | RESPEC | escalate), the worktree guidance ledger that survives the
// session re-mint, the bound, and the LOUD write failure.
//
// The layering: the engine owns the loop edge, and backward motion there is a
// pure DERIVATION — it refuses a rewind a route REPORTS. What is proven here is
// what power_station owns: the DECISION, the GUIDANCE ledger, the BOUND counted
// off that ledger's own `round`, and the ACTUATION (a declared `validates` edge
// onto the folded `specify` sibling plus the invalidating `grade: 'F'` stamp
// the derivation consumes).
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _gating = kSpecGatingRubric;
const _critics =
    'spec-validation,coherence,adr-alignment,acceptance-testability,'
    'plan-completeness';

/// The five spec lanes at [grades], with [rationales] where a critic gave one;
/// an omitted lane has NO grade (the fail-closed-missing case).
List<SpecLane> _lanes(
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
}) => [
  for (final id in kSpecCommitteeRubrics)
    (id: id, grade: grades[id], rationale: rationales[id] ?? ''),
];

Map<String, String> _allA() => {
  for (final id in kSpecCommitteeRubrics) id: 'A',
};

/// Plants a canonical verdict ARTIFACT for each NON-gating lane in [grades] —
/// the LIVE route's join requirement (bead `pow-96s`): a judgement lane joins
/// only through a `.grid/critique/<lane>.json` stamped with THIS node path and
/// THIS round. [round] defaults to the ledger's own `round` (the same
/// derivation `roundOf` and the route use), so successive rounds stay fresh by
/// re-calling this after the previous route moved the ledger; pass it
/// explicitly to plant a STALE artifact. The gating lane (`spec-validation`)
/// is never planted: it is a deterministic structural check with no artifact —
/// its grade rides the SiblingView (`_route`'s grades param), like the other
/// lanes' USED to.
void _plantVerdicts(
  String workspaceDir,
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
  int? round,
}) {
  final r = round ?? 0;
  for (final entry in grades.entries) {
    if (entry.key == _gating) continue;
    File(p.join(workspaceDir, '.grid', 'critique', '${entry.key}.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'rubric': entry.key,
          'version': 1,
          'grade': entry.value,
          if (rationales[entry.key] case final why?) 'rationale': why,
          'nodePath': 'tg-1/spec_review/${entry.key}',
          'round': r,
        }),
      );
  }
}

/// Runs the SPEC route over the fabricated [grades]/[rationales] with the
/// ambient [Workspace] pointed at [workspaceDir] (null ⇒ the offline posture: no
/// ambient workspace, so no ledger I/O at all — every lane then joins off the
/// SiblingView). LIVE, only the GATING lane's grade rides the SiblingView: the
/// judgement lanes join through their on-disk artifacts ([_plantVerdicts]).
/// The ROUND COUNTER is the LEDGER's own `round`, so successive rounds are
/// driven by re-running this over the SAME [workspaceDir] — there is no cursor
/// counter to seed.
Future<RouteVerdict> _route(
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
  String? workspaceDir,
  Map<String, Map<String, String>> resultExtras = const {},
  SpecRouteCapability capability = const SpecRouteCapability(),
  int round = 0,
}) {
  const parent = 'tg-1/spec_review';
  final context = FakeTreeContext(
    values: {
      SiblingView: SiblingView(
        cursor: {
          for (final id in grades.keys)
            '$parent/$id': const NodeCursor(state: StepState.complete),
          '$parent/route': const NodeCursor(state: StepState.running),
        },
        results: {
          for (final entry in grades.entries)
            '$parent/${entry.key}': {
              'grade': entry.value,
              'round': '$round',
              if (rationales[entry.key] case final r?) 'rationale': r,
              ...?resultExtras[entry.key],
            },
        },
      ),
      if (workspaceDir != null)
        Workspace: testWorkspace(
          'tg-1',
          workspaceDir: workspaceDir,
          branch: 'grid/tg-1',
        ),
    },
  );
  return capability.route(
    context,
    stepArgs(
      '$parent/route',
      params: {'critics': _critics, 'gating': _gating, 'grid.round': '$round'},
    ),
  );
}

/// A route tuned for tests that exercise the mid-wave WAIT: millisecond poll,
/// sub-second budget — the refusal path fires fast instead of holding the
/// suite for the production-scale wait.
const SpecRouteCapability _impatientRoute = SpecRouteCapability(
  lanePoll: Duration(milliseconds: 10),
  laneWaitBudget: Duration(milliseconds: 150),
);

void main() {
  group('decideSpecRoute — the three-way spec matrix', () {
    test('all A–C ⇒ SpecAdvance, with the route provenance (FT-2)', () {
      final v = decideSpecRoute(
        lanes: _lanes({..._allA(), 'coherence': 'C'}),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecAdvance>());
      expect(
        (v as SpecAdvance).gradesCsv,
        'spec-validation=A,coherence=C,adr-alignment=A,'
        'acceptance-testability=A,plan-completeness=A',
      );
      expect(v.spread, 2);
    });

    test('a FIXABLE fail (a critic D WITH a rationale) ⇒ SpecRespec — never an '
        'escalation — and the ledger carries the rationale VERBATIM', () {
      final v = decideSpecRoute(
        lanes: _lanes(
          {..._allA(), 'plan-completeness': 'D'},
          rationales: const {'plan-completeness': 'step 3 has no test command'},
        ),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecRespec>());
      final ledger = (v as SpecRespec).ledger;
      expect(ledger.round, 0);
      expect(ledger.lanes.single.rubric, 'plan-completeness');
      expect(ledger.lanes.single.grade, 'D');
      expect(ledger.lanes.single.rationale, 'step 3 has no test command');
    });

    test('a grade E is fixable too (an actionable grade, not a hard F)', () {
      final v = decideSpecRoute(
        lanes: _lanes(
          {..._allA(), 'coherence': 'E'},
          rationales: const {
            'coherence': 'the plan contradicts the acceptance',
          },
        ),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecRespec>());
      expect((v as SpecRespec).ledger.lanes.single.grade, 'E');
    });

    test('the pow-kzx shape (A/A/B/D, spread 3) auto-respecs — the old "human '
        'ultimatum" spread rule no longer parks it', () {
      final v = decideSpecRoute(
        lanes: _lanes(
          {
            _gating: 'A',
            'coherence': 'A',
            'adr-alignment': 'A',
            'acceptance-testability': 'B',
            'plan-completeness': 'D',
          },
          rationales: const {
            'plan-completeness': 'the ADR citation is not real',
          },
        ),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecRespec>());
    });

    test(
      'ESCALATION — the structural gating lane at F is a hard block, never a '
      'respec (and NAMES its lane — ADR-0000 A13(5))',
      () {
        final v = decideSpecRoute(
          lanes: _lanes({..._allA(), _gating: 'F'}),
          gating: _gating,
          priorRound: 0,
        );
        expect(v, isA<SpecEscalate>());
        expect((v as SpecEscalate).rule, 'gating-hard-block');
        expect(v.reason, contains('spec-validation'));
        expect(v.reason, contains('hard block'));
      },
    );

    test(
      'ESCALATION — a critic F (the scope/decompose-class ruling) is never a '
      'respec',
      () {
        final v = decideSpecRoute(
          lanes: _lanes(
            {..._allA(), 'coherence': 'F'},
            rationales: const {
              'coherence': 'this bead needs decomposing first',
            },
          ),
          gating: _gating,
          priorRound: 0,
        );
        expect(v, isA<SpecEscalate>());
        expect((v as SpecEscalate).rule, 'critic-F');
      },
    );

    test(
      'ESCALATION — a MISSING critic grade fail-closes to F (never advances, '
      'never respecs)',
      () {
        final grades = _allA()..remove('adr-alignment');
        final v = decideSpecRoute(
          lanes: _lanes(grades),
          gating: _gating,
          priorRound: 0,
        );
        expect(v, isA<SpecEscalate>());
        expect((v as SpecEscalate).rule, 'critic-F');
      },
    );

    test('ESCALATION — a fixable grade with NO rationale has nothing to respec '
        'against', () {
      final v = decideSpecRoute(
        lanes: _lanes({..._allA(), 'coherence': 'D'}),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecEscalate>());
      expect((v as SpecEscalate).rule, 'no-rationale');
    });

    test('BOUNDED — a fixable fail at the round cap escalates instead of '
        'looping forever', () {
      SpecRouteVerdict at(int priorRound) => decideSpecRoute(
        lanes: _lanes(
          {..._allA(), 'coherence': 'D'},
          rationales: const {'coherence': 'still incoherent'},
        ),
        gating: _gating,
        priorRound: priorRound,
      );
      expect(at(0), isA<SpecRespec>());
      expect((at(1) as SpecRespec).ledger.round, 1);
      expect(kMaxRespecRounds, 2);
      final capped = at(kMaxRespecRounds);
      expect(capped, isA<SpecEscalate>());
      expect((capped as SpecEscalate).rule, 'respec-cap');
    });

    test(
      'CONVERGED AT THE CAP — a clean vector with every round consumed '
      'ADVANCES; the cap bounds the LOOP, never the spec (bead `pow-p8w`)',
      () {
        final v = decideSpecRoute(
          lanes: _lanes(_allA()),
          gating: _gating,
          priorRound: kMaxRespecRounds,
        );
        expect(v, isA<SpecAdvance>());
        expect((v as SpecAdvance).spread, 0);
      },
    );
  });

  group('the guidance ledger — the channel that survives the critique wipe', () {
    late Directory ws;
    setUp(() => ws = Directory.systemTemp.createTempSync('pow7nm'));
    tearDown(() => ws.deleteSync(recursive: true));

    test('write → read round-trips the round + every lane verbatim', () {
      const ledger = RespecLedger(
        round: 2,
        lanes: [
          RespecLane(
            rubric: 'coherence',
            grade: 'D',
            rationale: 'plan ≠ acceptance',
          ),
        ],
      );
      writeRespecLedger(ws.path, ledger);
      final read = readRespecLedger(ws.path)!;
      expect(read.round, 2);
      expect(read.lanes.single.rationale, 'plan ≠ acceptance');
      // It is a SIBLING of `.grid/critique/`, which clear-critique wipes each
      // round — never a member of it.
      expect(respecLedgerPath(ws.path), endsWith('.grid/spec/respec.json'));
    });

    test(
      'a stale ledger cannot disturb a clean round-2 committee join',
      () async {
        writeRespecLedger(
          ws.path,
          const RespecLedger(
            round: 1,
            lanes: [
              RespecLane(
                rubric: 'coherence',
                grade: 'D',
                rationale: 'stale guidance',
              ),
            ],
          ),
        );
        final grades = _allA();
        _plantVerdicts(ws.path, grades, round: 2);

        final out = await _route(grades, workspaceDir: ws.path, round: 2);

        expect(out, isA<Advance>());
        final payload = (out as Advance).payload!;
        expect(payload['verdict'], 'advance');
        expect(payload[kVerdictRoundKey], '2');
        expect(payload['grades'], contains('spec-validation=A'));
        expect(readRespecLedger(ws.path), isNull);
      },
    );

    test('a stale structural payload does not join round 2', () async {
      final grades = _allA();
      _plantVerdicts(ws.path, grades, round: 2);

      await expectLater(
        _route(
          grades,
          workspaceDir: ws.path,
          round: 2,
          capability: _impatientRoute,
          resultExtras: const {
            _gating: {'round': '1'},
          },
        ),
        throwsA(
          isA<RouteFailure>().having(
            (error) => error.reason,
            'reason',
            allOf(contains(_gating), contains('round 2')),
          ),
        ),
      );
    });

    test('a corrupt / absent ledger degrades to "no prior round" — never a '
        'throw', () {
      expect(readRespecLedger(ws.path), isNull);
      File(respecLedgerPath(ws.path))
        ..createSync(recursive: true)
        ..writeAsStringSync('{ not json');
      expect(readRespecLedger(ws.path), isNull);
    });

    test(
      'a fixable fail WRITES the ledger and stamps the INVALIDATING F on the '
      'route\'s OWN result — the engine derives the wave off the declared '
      '`validates` edge, with no gate, no human, no session re-mint',
      () async {
        final grades = {..._allA(), 'plan-completeness': 'D'};
        const why = {'plan-completeness': 'step 3 names no test command'};
        _plantVerdicts(ws.path, grades, rationales: why);
        final out = await _route(
          grades,
          rationales: why,
          workspaceDir: ws.path,
        );
        // The route COMPLETES (an Advance on a sub-circuit terminal is a plain
        // `state=complete` + result write) carrying the structured stamp the
        // derivation reads. It reports NO rewind — the engine routes a reported
        // one to a supervised failure.
        expect(out, isA<Advance>());
        final payload = (out as Advance).payload!;
        expect(payload['grade'], 'F');
        expect(payload['verdict'], 'respec');
        expect(payload['round'], '0');
        expect(payload['rationale'], contains('RESPEC round 0/2'));
        expect(payload['rationale'], contains('plan-completeness=D'));
        // The edge the derivation walks is DECLARED on the route step, and its
        // target is a real sibling of the SAME circuit — a dangling name mints no
        // edge at all, so a drift here would silently disarm the loop.
        expect(
          (kSpecReviewCircuit.stepById('route')! as CapabilityStep)
              .params[kValidatesParamKey],
          kSpecifyStep,
        );
        expect(kValidatesParamKey, 'validates');
        expect(
          kSpecReviewCircuit.steps.map((s) => s.stepId),
          contains(kSpecifyStep),
        );
        // The RATIONALES ride the LEDGER (the stamp's prose is telemetry; the
        // ledger is what the next specify brief reads).
        final ledger = readRespecLedger(ws.path)!;
        expect(ledger.round, 0);
        expect(ledger.lanes.single.rationale, 'step 3 names no test command');
      },
    );

    test('the round counter is the LEDGER\'s own `round`, and at the cap the '
        'route flares to a HUMAN gate — the asset escalates on its OWN policy '
        'before the engine\'s derived belt', () async {
      final grades = {..._allA(), 'coherence': 'D'};
      const why = {'coherence': 'the plan still contradicts the acceptance'};

      _plantVerdicts(ws.path, grades, rationales: why); // round 0's artifacts.
      final first = await _route(
        grades,
        rationales: why,
        workspaceDir: ws.path,
      );
      expect((first as Advance).payload!['grade'], 'F');
      expect(readRespecLedger(ws.path)!.round, 0);

      // Round 2 reads back the ledger the previous round wrote — no cursor, no
      // engine-side counter (the engine no longer produces one a re-run node
      // can read). The re-planted artifacts stamp the ledger's OWN round (1) —
      // exactly what the re-run critics stamp via `roundOf`.
      _plantVerdicts(ws.path, grades, rationales: why, round: 1);
      final second = await _route(
        grades,
        rationales: why,
        workspaceDir: ws.path,
        round: 1,
      );
      expect((second as Advance).payload!['grade'], 'F');
      expect(readRespecLedger(ws.path)!.round, 1);

      // At the cap: a human rules — an Escalate, never another F stamp.
      _plantVerdicts(ws.path, grades, rationales: why, round: kMaxRespecRounds);
      final capped = await _route(
        grades,
        rationales: why,
        workspaceDir: ws.path,
        round: kMaxRespecRounds,
      );
      expect(capped, isA<Escalate>());
      expect((capped as Escalate).reason, startsWith('respec-cap'));
      expect(kMaxRespecRounds, lessThan(kMaxReworkRounds));
    });

    test('a CONSUMED ledger + an ALL-CLEAN current join ADVANCES — the cap is '
        '(rounds spent AND the join STILL fails), never rounds alone '
        '(bead `pow-p8w`)', () async {
      writeRespecLedger(
        ws.path,
        const RespecLedger(
          round: kMaxRespecRounds,
          lanes: [
            RespecLane(
              rubric: 'adr-alignment',
              grade: 'D',
              rationale: 'the ADR citation is not real',
            ),
          ],
        ),
      );
      _plantVerdicts(ws.path, _allA()); // round-2 (the ledger's) artifacts.
      final out = await _route(_allA(), workspaceDir: ws.path);
      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['verdict'], 'advance');
      // NO `grade` key: a converged round invalidates nothing.
      expect(payload.containsKey('grade'), isFalse);
      expect(readRespecLedger(ws.path), isNull);
    });

    test('the CAP flare quotes the FRESH vector it decided on, never the '
        'ledger\'s recorded last failure (bead `pow-p8w`)', () async {
      // A SPENT ledger whose recorded last failure names `adr-alignment` …
      writeRespecLedger(
        ws.path,
        const RespecLedger(
          round: kMaxRespecRounds,
          lanes: [
            RespecLane(
              rubric: 'adr-alignment',
              grade: 'D',
              rationale: 'the ADR citation is not real',
            ),
          ],
        ),
      );
      // … while the CURRENT join fails on a DIFFERENT lane.
      final grades = {..._allA(), 'coherence': 'D'};
      const why = {'coherence': 'the plan contradicts the acceptance'};
      _plantVerdicts(ws.path, grades, rationales: why, round: kMaxRespecRounds);
      final capped = await _route(
        grades,
        rationales: why,
        workspaceDir: ws.path,
        round: kMaxRespecRounds,
      );
      expect(capped, isA<Escalate>());
      final reason = (capped as Escalate).reason;
      expect(reason, startsWith('respec-cap'));
      expect(reason, contains('coherence=D'));
      expect(reason, contains('adr-alignment=A'));
      expect(reason, isNot(contains('adr-alignment=D')));
    });

    test(
      'the CAP flare SPENDS the ledger — a governor gate-resolve re-arms this '
      'route and it decides on the CURRENT join instead of re-flaring off the '
      'consumed round forever (bead `pow-p8w`)',
      () async {
        final grades = {..._allA(), 'coherence': 'D'};
        const why = {'coherence': 'the plan still contradicts the acceptance'};

        _plantVerdicts(ws.path, grades, rationales: why);
        await _route(grades, rationales: why, workspaceDir: ws.path);
        _plantVerdicts(ws.path, grades, rationales: why, round: 1);
        await _route(grades, rationales: why, workspaceDir: ws.path, round: 1);
        _plantVerdicts(
          ws.path,
          grades,
          rationales: why,
          round: kMaxRespecRounds,
        );
        final capped = await _route(
          grades,
          rationales: why,
          workspaceDir: ws.path,
          round: kMaxRespecRounds,
        );
        expect(capped, isA<Escalate>());
        expect(readRespecLedger(ws.path), isNull);

        // The re-arm after the human ruling: a CONVERGED join advances. The
        // ledger is spent, so the re-run lanes stamp round 0 again.
        _plantVerdicts(ws.path, _allA());
        final reArmed = await _route(_allA(), workspaceDir: ws.path);
        expect(reArmed, isA<Advance>());
        expect((reArmed as Advance).payload!['verdict'], 'advance');
      },
    );

    test(
      'a NON-cap escalate arm spends the ledger too — no stale correction '
      'survives into a `grid rework` specify brief (bead `pow-p8w`)',
      () async {
        writeRespecLedger(
          ws.path,
          const RespecLedger(
            round: 1,
            lanes: [
              RespecLane(rubric: 'coherence', grade: 'D', rationale: 'spent'),
            ],
          ),
        );
        final grades = {..._allA(), 'coherence': 'F'};
        const why = {'coherence': 'this bead needs decomposing first'};
        _plantVerdicts(
          ws.path,
          grades,
          rationales: why,
        ); // the ledger's round 1.
        final out = await _route(
          grades,
          rationales: why,
          workspaceDir: ws.path,
        );
        expect(out, isA<Escalate>());
        expect(readRespecLedger(ws.path), isNull);
      },
    );

    test(
      'an ADVANCE deletes the ledger — a later rework never re-injects stale '
      'guidance',
      () async {
        writeRespecLedger(
          ws.path,
          const RespecLedger(
            round: 1,
            lanes: [
              RespecLane(rubric: 'coherence', grade: 'D', rationale: 'stale'),
            ],
          ),
        );
        _plantVerdicts(ws.path, _allA()); // the ledger's round 1.
        final out = await _route(_allA(), workspaceDir: ws.path);
        expect(out, isA<Advance>());
        expect((out as Advance).payload!['verdict'], 'advance');
        expect(readRespecLedger(ws.path), isNull);
      },
    );

    test('a ledger write that cannot land is LOUD (a thrown RouteFailure) — '
        'never a respec whose guidance silently never arrives', () async {
      // `.grid/spec` occupied by a FILE ⇒ createSync(recursive: true) throws.
      File(p.join(ws.path, '.grid', 'spec'))
        ..createSync(recursive: true)
        ..writeAsStringSync('not a directory');
      _plantVerdicts(
        ws.path,
        {..._allA(), 'coherence': 'D'},
        rationales: const {'coherence': 'incoherent'},
      );
      // A route has NO failure arm: a throwing body is what RouteAllocation
      // sinks to supervision.
      await expectLater(
        _route(
          {..._allA(), 'coherence': 'D'},
          rationales: const {'coherence': 'incoherent'},
          workspaceDir: ws.path,
        ),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            contains('respec guidance ledger'),
          ),
        ),
      );
    });

    test('offline/dry-run (a workspace dir that does not exist) skips the ledger '
        'I/O but still stamps the invalidating F — the BOUND is then the '
        'ENGINE\'s, derived from the successor-chain depth', () async {
      final out = await _route(
        {..._allA(), 'coherence': 'D'},
        rationales: const {'coherence': 'the plan contradicts the acceptance'},
        workspaceDir: '/grid/worktrees/tg-1',
      );
      expect((out as Advance).payload!['grade'], 'F');
      expect(out.payload!['round'], '0');
      // No ledger was written anywhere, so the ASSET's counter cannot advance
      // offline. That is not an unbounded loop: the engine's derived generation
      // reaches `kMaxReworkRounds` off the successor chain and gates the node.
      expect(readRespecLedger('/grid/worktrees/tg-1'), isNull);
      expect(kMaxRespecRounds, lessThan(kMaxReworkRounds));
    });

    test('THE JOIN RULE (bead `pow-96s`, hardened by the 2026-07-24 bridge '
        'fix) — a lane joins the LIVE route only through a CURRENT-ROUND '
        'artifact, and a lane WITHOUT one is never silently dropped: the '
        'route WAITS for it and then refuses LOUDLY, citing no grade for the '
        'un-joined lanes and leaving the round counter unspent', () async {
      // The counter is SPENT: a full fixable join would be the cap flare.
      writeRespecLedger(
        ws.path,
        const RespecLedger(
          round: kMaxRespecRounds,
          lanes: [
            RespecLane(rubric: 'coherence', grade: 'D', rationale: 'still off'),
          ],
        ),
      );
      // CURRENT-round (2) artifacts for TWO judgement lanes only…
      _plantVerdicts(
        ws.path,
        const {'coherence': 'D', 'adr-alignment': 'A'},
        rationales: const {'coherence': 'the plan contradicts the acceptance'},
        round: kMaxRespecRounds,
      );
      // …a STALE (round-1) artifact for a third…
      _plantVerdicts(
        ws.path,
        const {'plan-completeness': 'D'},
        rationales: const {'plan-completeness': 'left over from round 1'},
        round: kMaxRespecRounds - 1,
      );
      // …and NO artifact at all for `acceptance-testability`. The SiblingView
      // still carries a full five-lane D-heavy vector (the replay shape — no
      // this-round result stamps): the route may neither decide over the
      // partial join (the tg-60t false advance) nor fabricate the missing
      // grades into a flare (the pow-96s incident). It WAITS, then refuses.
      await expectLater(
        _route(
          {
            ..._allA(),
            'coherence': 'D',
            'plan-completeness': 'D',
            'acceptance-testability': 'D',
          },
          rationales: const {
            'coherence': 'the plan contradicts the acceptance',
            'plan-completeness': 'left over from round 1',
            'acceptance-testability': 'never graded this round',
          },
          workspaceDir: ws.path,
          capability: _impatientRoute,
          round: kMaxRespecRounds,
          resultExtras: const {
            'plan-completeness': {'round': '1'},
            'acceptance-testability': {'round': '1'},
          },
        ),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            allOf(
              contains('plan-completeness'),
              contains('acceptance-testability'),
              contains('round $kMaxRespecRounds'),
              // The refusal cites NO grade — fabricating one was the incident.
              isNot(contains('plan-completeness=D')),
              isNot(contains('acceptance-testability=D')),
            ),
          ),
        ),
      );
      // The refusal never spends the counter: the round is still open for the
      // re-keyed lanes to finish (supervision re-runs this route bounded).
      expect(readRespecLedger(ws.path)?.round, kMaxRespecRounds);
    });

    test(
      'A FRESH session over a worktree littered with a PRIOR session\'s '
      'round-stamped verdicts does NOT replay them (bead `pow-96s`) — the '
      'lanes\' own results fail-closed THIS round (their reader rejected '
      'the stale files), so the route flares the transport miss LOUDLY '
      'instead of deciding over grades no current-round artifact backs',
      () async {
        // The prior session ended at round 2; its verdicts survive on disk. The
        // fresh session's intake CLEARED the ledger, so THIS round is 0.
        _plantVerdicts(
          ws.path,
          {..._allA(), 'coherence': 'D', 'plan-completeness': 'D'},
          rationales: const {
            'coherence': 'a prior session said so',
            'plan-completeness': 'a prior session said so',
          },
          round: kMaxRespecRounds,
        );
        expect(readRespecLedger(ws.path), isNull);
        // THIS round's lanes ran and their `result()` REJECTED the stale files
        // (the ledger-round fence): every judgement lane recorded a fail-closed
        // F stamped round 0 — finished this round, no artifact behind it.
        final out = await _route(
          {..._allA(), 'coherence': 'F', 'plan-completeness': 'F'},
          rationales: const {
            'coherence': 'no parseable verdict — fail-closed',
            'plan-completeness': 'no parseable verdict — fail-closed',
          },
          workspaceDir: ws.path,
          resultExtras: {
            for (final id in kSpecLlmRubrics)
              id: const {'round': '0', 'transport': 'fail-closed-default'},
          },
          capability: _impatientRoute,
        );
        // The judgement lanes finished round 0 with NO round-0 artifact on disk
        // ⇒ the loud, once, no-grades-cited flare (never a silent advance over
        // a gating-only join, never a fabricated five-lane vector).
        expect(out, isA<Escalate>());
        final reason = (out as Escalate).reason;
        expect(reason, contains('no current-round (round 0) verdict artifact'));
        expect(reason, contains('coherence'));
        expect(reason, contains('plan-completeness'));
        expect(reason, isNot(contains('coherence=')));
        expect(reason, isNot(contains('plan-completeness=')));
      },
    );
  });

  group('renderRespecGuidance — the recommendations reach the agent', () {
    test('names the round, the bound, every rubric + grade, and the rationale '
        'VERBATIM', () {
      const ledger = RespecLedger(
        round: 1,
        lanes: [
          RespecLane(
            rubric: 'adr-alignment',
            grade: 'D',
            rationale: 'ADR-0008 D3 is cited but says the opposite',
          ),
          RespecLane(
            rubric: 'plan-completeness',
            grade: 'D',
            rationale: 'step 4 has no commit message',
          ),
        ],
      );
      final g = renderRespecGuidance(ledger);
      expect(g, contains('RESPEC round 1 of 2'));
      expect(g, contains('READ THIS FIRST'));
      expect(g, contains('`adr-alignment` — grade D'));
      expect(g, contains('ADR-0008 D3 is cited but says the opposite'));
      expect(g, contains('`plan-completeness` — grade D'));
      expect(g, contains('step 4 has no commit message'));
    });
  });
}

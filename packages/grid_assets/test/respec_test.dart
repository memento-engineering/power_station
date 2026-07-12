// The spec-route AUTO-RESPEC arm (bead `pow-7nm`) — the three-way matrix
// (advance | RESPEC | escalate), the worktree guidance ledger that survives the
// session re-mint, the bound, and the LOUD write failure.
//
// The layering (the bead's SCOPE question): the loop EDGE is grid_engine's
// (`StepOutcome` is sealed over Ok/Failed/Gate; a CapabilityHost writes only its
// OWN node's cursor) — split bead `tg-b3k`. What is proven here is everything
// power_station owns: the DECISION, the GUIDANCE, and the BOUND.
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

Map<String, String> _allA() => {for (final id in kSpecCommitteeRubrics) id: 'A'};

/// Runs the SPEC route over the fabricated [grades]/[rationales], with the
/// ambient [Workspace] pointed at [workspaceDir] (null ⇒ the offline posture: no
/// ambient workspace, so no ledger I/O at all).
Future<StepOutcome> _route(
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
  String? workspaceDir,
}) {
  const parent = 'tg-1/spec_review';
  final context = FakeTreeContext(
    values: {
      SiblingView: SiblingView(
        cursor: {
          for (final id in grades.keys)
            '$parent/$id': const NodeCursor(state: StepState.complete),
        },
        results: {
          for (final entry in grades.entries)
            '$parent/${entry.key}': {
              'grade': entry.value,
              if (rationales[entry.key] case final r?) 'rationale': r,
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
  return const SpecRouteCapability().run(
    context,
    stepArgs(
      '$parent/route',
      params: const {'critics': _critics, 'gating': _gating},
    ),
  );
}

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
      expect(ledger.round, 1);
      expect(ledger.lanes.single.rubric, 'plan-completeness');
      expect(ledger.lanes.single.grade, 'D');
      expect(ledger.lanes.single.rationale, 'step 3 has no test command');
    });

    test('a grade E is fixable too (an actionable grade, not a hard F)', () {
      final v = decideSpecRoute(
        lanes: _lanes(
          {..._allA(), 'coherence': 'E'},
          rationales: const {'coherence': 'the plan contradicts the acceptance'},
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
          rationales: const {'plan-completeness': 'the ADR citation is not real'},
        ),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecRespec>());
    });

    test('ESCALATION — the structural gating lane at F is a hard block, never a '
        'respec (and NAMES its lane — ADR-0000 A13(5))', () {
      final v = decideSpecRoute(
        lanes: _lanes({..._allA(), _gating: 'F'}),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecEscalate>());
      expect((v as SpecEscalate).rule, 'gating-hard-block');
      expect(v.reason, contains('spec-validation'));
      expect(v.reason, contains('hard block'));
    });

    test('ESCALATION — a critic F (the scope/decompose-class ruling) is never a '
        'respec', () {
      final v = decideSpecRoute(
        lanes: _lanes(
          {..._allA(), 'coherence': 'F'},
          rationales: const {'coherence': 'this bead needs decomposing first'},
        ),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecEscalate>());
      expect((v as SpecEscalate).rule, 'critic-F');
    });

    test('ESCALATION — a MISSING critic grade fail-closes to F (never advances, '
        'never respecs)', () {
      final grades = _allA()..remove('adr-alignment');
      final v = decideSpecRoute(
        lanes: _lanes(grades),
        gating: _gating,
        priorRound: 0,
      );
      expect(v, isA<SpecEscalate>());
      expect((v as SpecEscalate).rule, 'critic-F');
    });

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
      expect((at(1) as SpecRespec).ledger.round, 2);
      expect(kMaxRespecRounds, 2);
      final capped = at(kMaxRespecRounds);
      expect(capped, isA<SpecEscalate>());
      expect((capped as SpecEscalate).rule, 'respec-cap');
    });
  });

  group('the guidance ledger — the channel that survives the session re-mint', () {
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

    test('a corrupt / absent ledger degrades to "no prior round" — never a '
        'throw', () {
      expect(readRespecLedger(ws.path), isNull);
      File(respecLedgerPath(ws.path))
        ..createSync(recursive: true)
        ..writeAsStringSync('{ not json');
      expect(readRespecLedger(ws.path), isNull);
    });

    test('a fixable fail WRITES the ledger and parks with a MACHINE-ACTIONABLE '
        'gate — not a human ultimatum', () async {
      final out = await _route(
        {..._allA(), 'plan-completeness': 'D'},
        rationales: const {'plan-completeness': 'step 3 names no test command'},
        workspaceDir: ws.path,
      );
      expect(out, isA<Gate>());
      expect((out as Gate).reason, startsWith(kRespecGatePrefix));
      expect(out.reason, contains('round 1/2'));
      expect(out.reason, contains('step 3 names no test command'));
      final ledger = readRespecLedger(ws.path)!;
      expect(ledger.round, 1);
      expect(ledger.lanes.single.rationale, 'step 3 names no test command');
    });

    test('the round COUNTS UP across rounds, then the cap flares to a HUMAN '
        'gate (no `respec:` prefix)', () async {
      final grades = {..._allA(), 'coherence': 'D'};
      const why = {'coherence': 'the plan still contradicts the acceptance'};
      await _route(grades, rationales: why, workspaceDir: ws.path);
      expect(readRespecLedger(ws.path)!.round, 1);
      await _route(grades, rationales: why, workspaceDir: ws.path);
      expect(readRespecLedger(ws.path)!.round, 2);
      final capped = await _route(
        grades,
        rationales: why,
        workspaceDir: ws.path,
      );
      expect(capped, isA<Gate>());
      expect((capped as Gate).reason, isNot(startsWith(kRespecGatePrefix)));
      expect(capped.reason, startsWith('respec-cap'));
    });

    test('an ADVANCE deletes the ledger — a later rework never re-injects stale '
        'guidance', () async {
      writeRespecLedger(
        ws.path,
        const RespecLedger(
          round: 1,
          lanes: [
            RespecLane(rubric: 'coherence', grade: 'D', rationale: 'stale'),
          ],
        ),
      );
      final out = await _route(_allA(), workspaceDir: ws.path);
      expect(out, isA<Ok>());
      expect((out as Ok).payload!['verdict'], 'advance');
      expect(readRespecLedger(ws.path), isNull);
    });

    test('a ledger write that cannot land is LOUD (Failed) — never a respec '
        'whose guidance silently never arrives', () async {
      // `.grid/spec` occupied by a FILE ⇒ createSync(recursive: true) throws.
      File(p.join(ws.path, '.grid', 'spec'))
        ..createSync(recursive: true)
        ..writeAsStringSync('not a directory');
      final out = await _route(
        {..._allA(), 'coherence': 'D'},
        rationales: const {'coherence': 'incoherent'},
        workspaceDir: ws.path,
      );
      expect(out, isA<Failed>());
      expect((out as Failed).reason, contains('respec guidance ledger'));
    });

    test('offline/dry-run (a workspace dir that does not exist) skips the '
        'ledger I/O but still names the rationales on the gate', () async {
      final out = await _route(
        {..._allA(), 'coherence': 'D'},
        rationales: const {'coherence': 'the plan contradicts the acceptance'},
        workspaceDir: '/grid/worktrees/tg-1',
      );
      expect(out, isA<Gate>());
      expect((out as Gate).reason, startsWith(kRespecGatePrefix));
      expect(out.reason, contains('the plan contradicts the acceptance'));
    });
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

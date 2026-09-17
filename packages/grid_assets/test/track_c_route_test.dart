// Track C3 — the route/aggregate capability + the deterministic matrix.
//
// `route` reads its sibling critics' grades through the AMBIENT SiblingView
// (D-5; read with the effect verb — never a subscription/re-query) and decides:
//   gating-F → Escalate · any non-gating F → Escalate · two-plus action grades
//   (D/E) → Escalate · a single E → Escalate · a single rationale-less D →
//   Escalate · a single D WITH a rationale → Advance carrying the finding ·
//   else → Advance (bead `pow-bhm`; policy Nico-ratified 2026-07-18).
// Fail-closed: a missing/forged grade is F, so it can NEVER advance.
//
// The LIVE join is the second group: in a real workspace a JUDGEMENT lane's
// grade comes from the artifact the lane itself persisted
// (`.grid/critique/<lane>.json`), never from a second channel — the fix for a
// lane that wrote grade B and routed as `a critic returned F` seven seconds
// later. Only the gating lanes (which persist no verdict JSON) and the offline
// posture (no worktree, so no artifacts) read the recorded step result.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const String _parent = 'tg-1/review';

final String _critics = kCommitteeRubrics.join(',');

/// A route (ambient tree, per-step args) pair whose ambient [SiblingView]
/// carries the fabricated [grades] (criticId → letter); an omitted critic has
/// NO recorded grade (the fail-closed-missing case). The node path is
/// realistic: `tg-1/review/route`, so the siblings live at
/// `tg-1/review/<criticId>`.
({FakeTreeContext context, StepArgs args}) _routeCtx(
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
  Map<String, String> diagnosticHeads = const {},
}) {
  const parent = _parent;
  final effectiveGrades = {kDeclaredTestsRubric: 'A', ...grades};
  return (
    context: FakeTreeContext(
      values: {
        SiblingView: SiblingView(
          cursor: {
            for (final id in effectiveGrades.keys)
              '$parent/$id': const NodeCursor(state: StepState.complete),
          },
          results: {
            for (final entry in effectiveGrades.entries)
              '$parent/${entry.key}': {
                'grade': entry.value,
                if (rationales[entry.key] case final rationale?)
                  'rationale': rationale,
                if (diagnosticHeads[entry.key] case final head?)
                  'diagnostic_head': head,
              },
          },
        ),
      },
    ),
    args: stepArgs(
      '$parent/route',
      params: {'critics': _critics, 'gating': kCodeGatingRubrics.join(',')},
    ),
  );
}

/// Runs the route over the fabricated [grades].
Future<RouteVerdict> _route(
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
  Map<String, String> diagnosticHeads = const {},
}) {
  final c = _routeCtx(
    grades,
    rationales: rationales,
    diagnosticHeads: diagnosticHeads,
  );
  return const CodeRouteCapability().route(c.context, c.args);
}

void main() {
  group('Track C3 — the route matrix', () {
    test('all A–C ⇒ Advance — with route provenance (FT-2)', () async {
      final out = await _route(const {
        'code-validation': 'A',
        'spec-adherence': 'B',
        'regression-risk': 'A',
        'test-coverage': 'C',
      });
      expect(out, isA<Advance>());
      // FT-2: the advance payload is now self-contained — it carries the grade
      // vector it consumed (CSV in kCommitteeRubrics order), the computed spread
      // (A..C ⇒ index 0..2 ⇒ 2), and the matrix arm that fired.
      expect((out as Advance).payload, {
        'verdict': 'advance',
        'grades':
            'code-validation=A,declared-tests-present=A,spec-adherence=B,'
            'regression-risk=A,'
            'test-coverage=C',
        'spread': '2',
        'rule': 'all-approve',
      });
    });

    test('the gating critic at F ⇒ Gate (hard block)', () async {
      final out = await _route(const {
        'code-validation': 'F',
        'spec-adherence': 'A',
        'regression-risk': 'A',
        'test-coverage': 'A',
      });
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, 'code-validation failed: hard block');
    });

    test('declared test failures hard-block with every missing path', () async {
      final c = _routeCtx(
        const {
          kDeclaredTestsRubric: 'F',
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
        rationales: const {
          kDeclaredTestsRubric:
              'missing test/one_test.dart, test/two_test.dart',
        },
      );
      final out = await const CodeRouteCapability().route(c.context, c.args);
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains(kDeclaredTestsRubric));
      expect(out.reason, contains('test/one_test.dart'));
      expect(out.reason, contains('test/two_test.dart'));
    });

    test('the gating critic appends an exit-127 candidate rationale', () async {
      final c = _routeCtx(
        const {
          'code-validation': 'F',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
        rationales: const {
          'code-validation': 'exit 127 — candidate missing commands: rg',
        },
      );
      final out = await const CodeRouteCapability().route(c.context, c.args);
      expect(out, isA<Escalate>());
      expect(
        (out as Escalate).reason,
        'code-validation failed: hard block: '
        'exit 127 — candidate missing commands: rg',
      );
    });

    test('diagnostic head precedes the code-validation hard block', () async {
      final out = await _route(
        const {
          'code-validation': 'F',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
        rationales: const {
          'code-validation':
              'validation plan failed (exit 1); full log: '
              '.grid/critique/code-validation.log: Some tests failed.',
        },
        diagnosticHeads: const {
          'code-validation':
              'Failed to load "test/a_test.dart":\n'
              'lib/a.dart:4:2: Error: Missing member.\n'
              '[E] analyzer failed',
        },
      );

      expect(out, isA<Escalate>());
      final reason = (out as Escalate).reason;
      expect(
        reason,
        startsWith(
          'Failed to load "test/a_test.dart":\n'
          'lib/a.dart:4:2: Error: Missing member.\n'
          '[E] analyzer failed\n'
          'code-validation failed: hard block: ',
        ),
      );
      expect(reason, contains('.grid/critique/code-validation.log'));
      expect(reason, endsWith('Some tests failed.'));
    });

    test('deadline rationale remains explicit in the hard block', () async {
      final out = await _route(
        const {
          'code-validation': 'F',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
        rationales: const {
          'code-validation':
              'validation plan exceeded the 10-minute kGatingDeadline; '
              'full log: .grid/critique/code-validation.log: partial output',
        },
      );

      expect(out, isA<Escalate>());
      expect(
        (out as Escalate).reason,
        allOf(
          startsWith('code-validation failed: hard block: '),
          contains('exceeded the 10-minute kGatingDeadline'),
          contains('.grid/critique/code-validation.log'),
        ),
      );
    });

    test('a single D (A + D, spread 3) ⇒ Advance carrying the finding — the '
        'spread rule is GONE', () async {
      final out = await _route(
        const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'D',
        },
        rationales: const {'test-coverage': 'the new arm has no test'},
      );
      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['rule'], 'single-finding-advance');
      expect(payload['fix_in_flight'], 'test-coverage=D');
      expect(payload['fix_in_flight_finding'], 'the new arm has no test');
      // The spread still rides the payload as FT-2 provenance — it just no
      // longer DECIDES anything.
      expect(payload['spread'], '3');
    });

    test('a single E ⇒ Gate — the code committee has no respec arm', () async {
      final out = await _route(
        const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'E',
          'test-coverage': 'A',
        },
        rationales: const {'regression-risk': 'the retry loop is unbounded'},
      );
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('returned E'));
    });

    test('a single D with NO rationale ⇒ Gate — nothing to carry', () async {
      final out = await _route(const {
        'code-validation': 'A',
        'spec-adherence': 'A',
        'regression-risk': 'A',
        'test-coverage': 'D',
      });
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('NO rationale'));
    });

    test('a non-gating critic at F (spread < 3) ⇒ Gate (rework rule, the F '
        'branch)', () async {
      // Isolates rule 3's `== F` branch: a synthetic gating=D keeps rule 1 from
      // firing, and all grades sit in D..F so the spread (2) stays < 3 — only the
      // non-gating F can trip the gate (review finding C-2).
      final out = await _route(const {
        'code-validation': 'D',
        kDeclaredTestsRubric: 'D',
        'spec-adherence': 'F',
        'regression-risk': 'E',
        'test-coverage': 'D',
      });
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('rework'));
    });

    test('TWO non-gating critics at an action grade ⇒ Gate (rework)', () async {
      // The round did not converge on a SINGLE carriable finding, so it
      // gates — even though each lane says WHY (bead `pow-bhm`).
      final out = await _route(
        const {
          'code-validation': 'B',
          kDeclaredTestsRubric: 'B',
          'spec-adherence': 'C',
          'regression-risk': 'D',
          'test-coverage': 'D',
        },
        rationales: const {
          'regression-risk': 'the retry loop is unbounded',
          'test-coverage': 'the new arm has no test',
        },
      );
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('two or more critics'));
      expect(out.reason, contains('rework'));
    });

    test(
      'a MISSING sibling grade ⇒ Gate (fail-closed — can never advance)',
      () async {
        // test-coverage has no recorded grade ⇒ treated as F ⇒ cannot advance.
        final out = await _route(const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'A',
        });
        expect(
          out,
          isA<Escalate>(),
          reason: 'an unread/forged-missing grade is F',
        );
        // A missing non-gating grade is F → the D/F rework rule (review C-1).
        expect((out as Escalate).reason, contains('rework'));
      },
    );

    test('the gating critic MISSING ⇒ Gate (fail-closed)', () async {
      final out = await _route(const {
        'spec-adherence': 'A',
        'regression-risk': 'A',
        'test-coverage': 'A',
      });
      expect(out, isA<Escalate>());
      // A missing gating grade is F → the hard-block rule, not spread (review C-1).
      expect((out as Escalate).reason, contains('hard block'));
    });
  });

  group('the gating param is a lane SET', () {
    /// The SAME route over the DOCS committee's param set — three deterministic
    /// gating lanes instead of one.
    Future<RouteVerdict> docsRoute(Map<String, String> grades) {
      final c = _routeCtx(grades);
      return const CodeRouteCapability().route(
        c.context,
        stepArgs(
          'tg-1/review/route',
          params: {
            'critics': kDocsCommitteeRubrics.join(','),
            'gating': kDocsGatingRubrics.join(','),
          },
        ),
      );
    }

    test('ANY mechanical lane at F is a hard block', () async {
      final out = await docsRoute(const {
        'citation-paths-resolve': 'A',
        'terminology-ban': 'F',
        'section-structure': 'A',
        'spec-adherence': 'A',
      });
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('terminology-ban'));
    });

    test('all lanes clean ⇒ Advance', () async {
      expect(
        await docsRoute(const {
          'citation-paths-resolve': 'A',
          'terminology-ban': 'A',
          'section-structure': 'A',
          'spec-adherence': 'B',
        }),
        isA<Advance>(),
      );
    });
  });

  group('the LIVE join reads the lane\'s OWN persisted verdict', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('route_verdict_');
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('a persisted B overrides a conflicting recorded F — the false-F '
        'incident', () async {
      // The live shape, exactly: the lane WROTE grade B, and the recorded step
      // result the route used to read says F. One source, one value — the
      // artifact wins, and the round advances instead of being reworked.
      _persistVerdict(workspace, 'spec-adherence', grade: 'A');
      _persistVerdict(workspace, 'test-coverage', grade: 'A');
      _persistVerdict(
        workspace,
        'regression-risk',
        grade: 'B',
        rationale:
            'shared review-base path touched, contracts preserved, 65 tests '
            'pass',
      );

      final out = await _liveRoute(
        workspace,
        recorded: const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'F',
          'test-coverage': 'A',
        },
      );

      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['grades'], contains('regression-risk=B'));
      expect(payload['rule'], 'all-approve');
    });

    test('a PRIOR-round artifact HOLDS, naming the round fence and the '
        'path', () async {
      _persistVerdict(workspace, 'spec-adherence', grade: 'A');
      _persistVerdict(workspace, 'test-coverage', grade: 'A');
      // The file the previous round left on the reused worktree. A4's nodePath
      // fence cannot see it (a rework does not move the node path), so the
      // round pin is the one that fires.
      _persistVerdict(workspace, 'regression-risk', grade: 'A', round: 78);

      final out = await _liveRoute(
        workspace,
        recorded: const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
      );

      expect(out, isA<Escalate>());
      final reason = (out as Escalate).reason;
      expect(reason, contains('regression-risk'));
      expect(reason, contains(kVerdictRoundPinMismatch));
      expect(reason, contains(_verdictPath(workspace, 'regression-risk')));
      expect(
        reason,
        isNot(contains('a critic returned F')),
        reason: 'a refused artifact is a HOLD, never a critic ruling',
      );
    });

    test('an INVALID-shape artifact HOLDS, naming the shape check and the '
        'path', () async {
      _persistVerdict(workspace, 'spec-adherence', grade: 'A');
      _persistVerdict(workspace, 'test-coverage', grade: 'A');
      _writeVerdictJson(workspace, 'regression-risk', {
        'grade': 'B',
        // no rationale — the strict decoder's shape check refuses it.
        'nodePath': '$_parent/regression-risk',
        kVerdictRoundKey: _liveRound,
      });

      final out = await _liveRoute(
        workspace,
        recorded: const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
      );

      expect(out, isA<Escalate>());
      final reason = (out as Escalate).reason;
      expect(reason, contains(kVerdictShapeCheckFailed));
      expect(reason, contains('rationale must be a non-empty string'));
      expect(reason, contains(_verdictPath(workspace, 'regression-risk')));
      expect(reason, isNot(contains('a critic returned F')));
    });

    test('an ABSENT artifact HOLDS on the canonical path, not on F', () async {
      _persistVerdict(workspace, 'spec-adherence', grade: 'A');
      _persistVerdict(workspace, 'test-coverage', grade: 'A');

      final out = await _liveRoute(
        workspace,
        recorded: const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
      );

      expect(out, isA<Escalate>());
      final reason = (out as Escalate).reason;
      expect(reason, contains(kVerdictArtifactAbsent));
      expect(reason, contains(_verdictPath(workspace, 'regression-risk')));
      expect(reason, isNot(contains('a critic returned F')));
    });

    test(
      'only a WRITTEN F routes as a critic F — and names its source',
      () async {
        _persistVerdict(workspace, 'spec-adherence', grade: 'A');
        _persistVerdict(workspace, 'test-coverage', grade: 'A');
        _persistVerdict(
          workspace,
          'regression-risk',
          grade: 'F',
          rationale: 'the migration drops rows on the null branch',
        );

        final out = await _liveRoute(
          workspace,
          recorded: const {
            'code-validation': 'A',
            'spec-adherence': 'A',
            // The recorded channel says B; the ARTIFACT says F, and the artifact
            // is the one that rules.
            'regression-risk': 'B',
            'test-coverage': 'A',
          },
        );

        expect(out, isA<Escalate>());
        final reason = (out as Escalate).reason;
        expect(reason, contains('a critic returned F (regression-risk)'));
        expect(reason, contains(_verdictPath(workspace, 'regression-risk')));
      },
    );

    test('a single persisted D carries the ARTIFACT\'s rationale', () async {
      _persistVerdict(workspace, 'spec-adherence', grade: 'A');
      _persistVerdict(workspace, 'regression-risk', grade: 'A');
      _persistVerdict(
        workspace,
        'test-coverage',
        grade: 'D',
        rationale: 'the new escalation arm has no test',
      );

      final out = await _liveRoute(
        workspace,
        recorded: const {
          'code-validation': 'A',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
      );

      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['rule'], 'single-finding-advance');
      expect(payload['fix_in_flight'], 'test-coverage=D');
      expect(
        payload['fix_in_flight_finding'],
        'the new escalation arm has no test',
      );
    });

    test('a GATING lane still joins off its own step result — it writes no '
        'verdict JSON', () async {
      _persistVerdict(workspace, 'spec-adherence', grade: 'A');
      _persistVerdict(workspace, 'regression-risk', grade: 'A');
      _persistVerdict(workspace, 'test-coverage', grade: 'A');

      final out = await _liveRoute(
        workspace,
        recorded: const {
          'code-validation': 'F',
          'spec-adherence': 'A',
          'regression-risk': 'A',
          'test-coverage': 'A',
        },
        rationales: const {
          'code-validation': 'validation plan failed (exit 1)',
        },
      );

      expect(out, isA<Escalate>());
      expect(
        (out as Escalate).reason,
        'code-validation failed: hard block: validation plan failed (exit 1)',
      );
    });
  });
}

/// The circuit round the live probes pin every artifact to.
const int _liveRound = 79;

/// [lane]'s canonical verdict path under [workspace].
String _verdictPath(Directory workspace, String lane) =>
    p.join(workspace.path, '.grid', 'critique', '$lane.json');

/// Writes [lane]'s verdict JSON verbatim — the shape-violation probe's writer.
void _writeVerdictJson(
  Directory workspace,
  String lane,
  Map<String, Object?> json,
) => File(_verdictPath(workspace, lane))
  ..createSync(recursive: true)
  ..writeAsStringSync(jsonEncode(json));

/// Persists [lane]'s verdict exactly as a critic does — both freshness stamps,
/// pinned to [round] (defaulting to the live probes' current round).
void _persistVerdict(
  Directory workspace,
  String lane, {
  required String grade,
  String rationale = 'the lane said so',
  int round = _liveRound,
}) => _writeVerdictJson(workspace, lane, {
  'grade': grade,
  'rationale': rationale,
  'nodePath': '$_parent/$lane',
  kVerdictRoundKey: round,
});

/// Runs the route in the LIVE posture: a REAL [workspace] directory mounted as
/// the ambient [Workspace], so every non-gating lane joins through its own
/// artifact while [recorded] supplies only the step-result channel the gating
/// lanes (and the old, conflicting read) use.
Future<RouteVerdict> _liveRoute(
  Directory workspace, {
  required Map<String, String> recorded,
  Map<String, String> rationales = const {},
}) {
  final grades = {kDeclaredTestsRubric: 'A', ...recorded};
  final context = FakeTreeContext(
    values: {
      Workspace: Workspace(
        workspaceDir: workspace.path,
        branch: 'grid/tg-1',
        baseBranch: 'main',
      ),
      SiblingView: SiblingView(
        cursor: {
          for (final id in grades.keys)
            '$_parent/$id': const NodeCursor(state: StepState.complete),
        },
        results: {
          for (final entry in grades.entries)
            '$_parent/${entry.key}': {
              'grade': entry.value,
              if (rationales[entry.key] case final rationale?)
                'rationale': rationale,
            },
        },
      ),
    },
  );
  return const CodeRouteCapability().route(
    context,
    stepArgs(
      '$_parent/route',
      params: {
        'critics': _critics,
        'gating': kCodeGatingRubrics.join(','),
        'grid.round': '$_liveRound',
      },
    ),
  );
}

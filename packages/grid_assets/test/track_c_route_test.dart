// Track C3 — the route/aggregate capability + the deterministic matrix.
//
// `route` reads its sibling critics' grades through the AMBIENT SiblingView
// (D-5; read with the effect verb — never a subscription/re-query) and decides:
//   gating-F → Escalate · any non-gating F → Escalate · two-plus action grades
//   (D/E) → Escalate · a single E → Escalate · a single rationale-less D →
//   Escalate · a single D WITH a rationale → Advance carrying the finding ·
//   else → Advance (bead `pow-bhm`; policy Nico-ratified 2026-07-18).
// Fail-closed: a missing/forged grade is F, so it can NEVER advance. Zero I/O.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

final String _critics = kCommitteeRubrics.join(',');

/// A route (ambient tree, per-step args) pair whose ambient [SiblingView]
/// carries the fabricated [grades] (criticId → letter); an omitted critic has
/// NO recorded grade (the fail-closed-missing case). The node path is
/// realistic: `tg-1/review/route`, so the siblings live at
/// `tg-1/review/<criticId>`.
({FakeTreeContext context, StepArgs args}) _routeCtx(
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
}) {
  const parent = 'tg-1/review';
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
}) {
  final c = _routeCtx(grades, rationales: rationales);
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

    test(
      'TWO non-gating critics at an action grade ⇒ Gate (rework)',
      () async {
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
      },
    );

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
}

// Track C3 — the route/aggregate capability + the deterministic matrix.
//
// `route` reads its sibling critics' grades through the AMBIENT SiblingView
// (D-5; read with the effect verb — never a subscription/re-query) and decides:
//   gating-F → Escalate · spread ≥ 3 → Escalate · any non-gating D/F →
//   Escalate · all A–C → Advance.
// Fail-closed: a missing/forged grade is F, so it can NEVER advance. Zero I/O.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _critics = 'code-validation,spec-adherence,regression-risk,test-coverage';

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
  return (
    context: FakeTreeContext(
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
                if (rationales[entry.key] case final rationale?)
                  'rationale': rationale,
              },
          },
        ),
      },
    ),
    args: stepArgs(
      '$parent/route',
      params: const {'critics': _critics, 'gating': 'code-validation'},
    ),
  );
}

/// Runs the route over the fabricated [grades].
Future<RouteVerdict> _route(Map<String, String> grades) {
  final c = _routeCtx(grades);
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
            'code-validation=A,spec-adherence=B,regression-risk=A,'
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

    test('a grade spread ≥ 3 (A + D) ⇒ Gate', () async {
      final out = await _route(const {
        'code-validation': 'A',
        'spec-adherence': 'A',
        'regression-risk': 'A',
        'test-coverage': 'D',
      });
      expect(out, isA<Escalate>());
      // The spread rule (rule 2) fires before the D/F rule — assert the REASON
      // so a gate firing for the WRONG rule is caught (review finding C-1).
      expect((out as Escalate).reason, contains('spread'));
    });

    test('a non-gating critic at F (spread < 3) ⇒ Gate (rework rule, the F '
        'branch)', () async {
      // Isolates rule 3's `== F` branch: a synthetic gating=D keeps rule 1 from
      // firing, and all grades sit in D..F so the spread (2) stays < 3 — only the
      // non-gating F can trip the gate (review finding C-2).
      final out = await _route(const {
        'code-validation': 'D',
        'spec-adherence': 'F',
        'regression-risk': 'E',
        'test-coverage': 'D',
      });
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('rework'));
    });

    test(
      'a non-gating critic at D (spread < 3) ⇒ Gate (rework, deferred)',
      () async {
        // B..D is a spread of 2 (< 3) so the spread rule does NOT fire — the D/F
        // rework rule does.
        final out = await _route(const {
          'code-validation': 'B',
          'spec-adherence': 'C',
          'regression-risk': 'C',
          'test-coverage': 'D',
        });
        expect(out, isA<Escalate>());
        expect((out as Escalate).reason, contains('rework'));
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

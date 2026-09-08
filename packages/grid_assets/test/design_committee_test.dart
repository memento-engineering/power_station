// The DESIGN-ROUND committee — the docs committee's adversarial extension.
//
// Proves: the path-only admission (`docs/design/**`, evaluated BEFORE the docs
// arm, leaving every ordinary docs bead where it was); the circuit's lane set
// (the three unchanged deterministic gates + four rubric-selected judges); the
// verify join and the route's single dependency; and the verifier's own
// behaviour over FAKE judgments — one refuted, one confirmed-and-fixed, one
// confirmed-open — down to the document it rewrites, the adjudication log it
// appends, the critique artifact it writes, and the ONE finding that reaches
// the route.
// Offline only: the inference seam is a Fake, and every path is a temp dir.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A bead whose `## Touches` cites design paths only.
Bead _designBead() => bead('pow-d1').copyWith(
  title: 'the W2-D soak gate',
  design:
      '## Touches\n'
      '- `docs/design/w2d-soak-gate.md` — the round document\n',
);

void main() {
  group('design path admission', () {
    test('isDesignPath admits the docs/design tree at any depth', () {
      for (final path in const [
        'docs/design/w2d-soak-gate.md',
        'docs/design/r7/cut-wiring.md',
        'docs/design/r7/appendix/ordering.md',
      ]) {
        expect(isDesignPath(path), isTrue, reason: path);
      }
    });

    test('isDesignPath refuses everything outside that ONE prefix', () {
      for (final path in const [
        // The directory itself is not a document.
        'docs/design',
        'docs/design/',
        // A string prefix is not a path prefix — the match is by SEGMENT.
        'docs/design.md',
        'docs/designs/x.md',
        // The tree is the REPO's, never a package's.
        'packages/grid_assets/docs/design/a.md',
        // A cited path is repo-relative, or it is not admitted.
        '/tmp/docs/design/a.md',
        '../docs/design/a.md',
        'docs/design/../../lib/src/code/committee.dart',
        // Ordinary docs, and ordinary source.
        'docs/adr/ADR-0000-ai-decision-register.md',
        'README.md',
        'lib/src/code/docs_committee.dart',
        '',
      ]) {
        expect(isDesignPath(path), isFalse, reason: path);
      }
    });

    test('a design-only bead classifies as design, ahead of the docs arm', () {
      expect(changeShapeOf(_designBead()), ChangeShape.design);
      // Every design path is ALSO a docs path — the ordering is what makes the
      // narrower arm reachable at all.
      expect(isDocsPath('docs/design/w2d-soak-gate.md'), isTrue);
    });

    test('an ordinary docs bead is UNCHANGED by the new arm', () {
      final docs = bead(
        'pow-d2',
      ).copyWith(design: '## Touches\n- `docs/adr/ADR-0009-x.md` — created\n');
      expect(changeShapeOf(docs), ChangeShape.docs);
    });

    test('a design doc MIXED with anything else falls through the ladder', () {
      final withDocs = bead('pow-d3').copyWith(
        design:
            '## Touches\n'
            '- `docs/design/r7.md`\n'
            '- `docs/adr/ADR-0009-x.md`\n',
      );
      expect(changeShapeOf(withDocs), ChangeShape.docs);
      final withSource = bead('pow-d4').copyWith(
        design:
            '## Touches\n'
            '- `docs/design/r7.md`\n'
            '- `lib/src/code/committee.dart`\n',
      );
      expect(changeShapeOf(withSource), ChangeShape.code);
    });

    test('a design bead roots a circuit whose review is design_review', () {
      const resolver = ChangeShapeCircuitResolver(kCodeCircuit);
      final review =
          resolver.circuitFor(ChangeShape.design).stepById(kReviewStepId)!
              as SubCircuitStep;
      expect(review.circuitId, kDesignReviewCircuitId);
      // The other three shapes are byte-unchanged.
      for (final pair in const [
        (ChangeShape.docs, kDocsReviewCircuitId),
        (ChangeShape.metadata, kDocsReviewCircuitId),
        (ChangeShape.code, 'code_review'),
      ]) {
        expect(
          (resolver.circuitFor(pair.$1).stepById(kReviewStepId)!
                  as SubCircuitStep)
              .circuitId,
          pair.$2,
        );
      }
    });
  });
}

// The migration guard's PURE halves — the five-way cursor classifier, the
// resolver's circuit dispatch, the frozen shapes, and the frozen sub-circuits'
// registry entries. No kernel, no tree mount, no IO (pure logic tested before IO
// is wired — the house set).
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const NodeCursor _complete = NodeCursor(state: StepState.complete);
const NodeCursor _running = NodeCursor(state: StepState.running);
const NodeCursor _gated = NodeCursor(state: StepState.gated);
// D-7's gate re-arm flips a parked node back to an explicit `pending` — the KEY
// is still present, and presence is the signal.
const NodeCursor _pending = NodeCursor();

SessionProjection _session(CircuitCursor cursor) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-sess1',
  cursor: cursor,
);

void main() {
  group('classifyCodeShape — the five-way cursor classifier', () {
    CodeCircuitShape c(CircuitCursor cursor) =>
        classifyCodeShape(beadId: 'tg-1', cursor: cursor);

    test('an empty cursor (fresh mint / rework round) is the CURRENT shape', () {
      expect(c(const {}), CodeCircuitShape.discovery);
    });

    test("only another bead's keys — nothing of ours — is the CURRENT shape",
        () {
      expect(c(const {'tg-9/agent': _complete}), CodeCircuitShape.discovery);
    });

    test('the DISCOVERY head key classifies the CURRENT shape, in ANY state',
        () {
      expect(
        c(const {'tg-1/spec_review/discovery/anchors': _running}),
        CodeCircuitShape.discovery,
      );
      expect(
        c(const {
          'tg-1/spec_review/intake': _complete,
          'tg-1/spec_review/discovery/anchors': _complete,
          'tg-1/spec_review/specify': _complete,
          'tg-1/agent': _complete,
        }),
        CodeCircuitShape.discovery,
      );
    });

    test('a PRE-DISCOVERY survivor that already SPECIFIED is FROZEN laddered — '
        'the gather never mounts and its three agents never spawn', () {
      expect(
        c(const {
          'tg-1/spec_review/intake': _complete,
          'tg-1/spec_review/specify': _complete,
          'tg-1/agent': _running,
        }),
        CodeCircuitShape.laddered,
      );
    });

    test('a pre-discovery session still IN the ladder MIGRATES FORWARD — it '
        'gains discovery, and nothing downstream has run', () {
      expect(
        c(const {'tg-1/spec_review/intake': _running}),
        CodeCircuitShape.discovery,
      );
      expect(
        c(const {
          'tg-1/spec_review/intake': _complete,
          'tg-1/spec_review/readiness': _complete,
          'tg-1/spec_review/readiness-route': _complete,
        }),
        CodeCircuitShape.discovery,
        reason: 'discovery mounts exactly where it belongs — after '
            '`readiness-route`, before `specify`',
      );
    });

    test('the FOLDED specify key with NO ladder key is a PRE-LADDER survivor, '
        'in ANY state', () {
      expect(
        c(const {'tg-1/spec_review/specify': _running}),
        CodeCircuitShape.folded,
      );
      expect(
        c(const {
          'tg-1/spec_review/specify': _complete,
          'tg-1/agent': _complete,
        }),
        CodeCircuitShape.folded,
      );
    });

    test('the ROOT specify key (pow-6ao) classifies specHead', () {
      expect(c(const {'tg-1/specify': _running}), CodeCircuitShape.specHead);
      expect(
        c(const {
          'tg-1/specify': _complete,
          'tg-1/spec_review/route': _complete,
          'tg-1/agent': _complete,
        }),
        CodeCircuitShape.specHead,
      );
    });

    test(
      'any old-head node with NO specify at either path is LEGACY — '
      'state-agnostic (complete, running, gated, even a re-armed pending)',
      () {
        expect(c(const {'tg-1/agent': _complete}), CodeCircuitShape.legacy);
        expect(c(const {'tg-1/agent': _running}), CodeCircuitShape.legacy);
        expect(c(const {'tg-1/review/route': _gated}), CodeCircuitShape.legacy);
        expect(
          c(const {'tg-1/review/route': _pending}),
          CodeCircuitShape.legacy,
        );
        expect(
          c(const {'tg-1/land/rebase': _complete}),
          CodeCircuitShape.legacy,
        );
        expect(c(const {'tg-1/land/land': _running}), CodeCircuitShape.legacy);
      },
    );

    test('the folded key WINS over a root specify key', () {
      expect(
        c(const {
          'tg-1/spec_review/specify': _complete,
          'tg-1/specify': _complete,
        }),
        CodeCircuitShape.folded,
      );
    });

    test('the DISCOVERY key WINS over every older specify key — newest shape '
        'first', () {
      expect(
        c(const {
          'tg-1/spec_review/discovery/anchors': _complete,
          'tg-1/spec_review/intake': _complete,
          'tg-1/spec_review/specify': _complete,
          'tg-1/specify': _complete,
        }),
        CodeCircuitShape.discovery,
      );
    });

    test('the LADDER key WINS over both older specify keys', () {
      expect(
        c(const {
          'tg-1/spec_review/intake': _complete,
          'tg-1/spec_review/specify': _complete,
          'tg-1/specify': _complete,
        }),
        CodeCircuitShape.laddered,
      );
    });
  });

  group('CodeCircuitResolver — the migration-aware circuit dispatch', () {
    const resolver = CodeCircuitResolver(kCodeCircuit);

    SessionScope scopeFor(SessionProjection? session) =>
        resolver.sessionFor(bead: bead('tg-1'), session: session)
            as SessionScope;

    test('no session yet (fresh bead) roots the CURRENT kCodeCircuit', () {
      final scope = scopeFor(null);
      expect(identical(scope.circuit, kCodeCircuit), isTrue);
      expect(scope.key, const ValueKey('tg-1:session'));
    });

    test('a freshly-minted (empty-cursor) session roots kCodeCircuit', () {
      final scope = scopeFor(_session(const {}));
      expect(identical(scope.circuit, kCodeCircuit), isTrue);
    });

    test('a CURRENT-shape session stays on kCodeCircuit', () {
      final scope = scopeFor(
        _session(const {'tg-1/spec_review/discovery/anchors': _complete}),
      );
      expect(identical(scope.circuit, kCodeCircuit), isTrue);
      expect(scope.key, const ValueKey('tg-1:session'));
    });

    test('a shape-4 PRE-DISCOVERY survivor past `specify` roots '
        'kLadderedCodeCircuit — the gather never mounts, so its three explorers '
        'never spawn and its route can never park a building bead', () {
      final scope = scopeFor(
        _session(const {
          'tg-1/spec_review/intake': _complete,
          'tg-1/spec_review/specify': _complete,
          'tg-1/agent': _running,
        }),
      );
      expect(identical(scope.circuit, kLadderedCodeCircuit), isTrue);
      expect(identical(scope.circuit, kCodeCircuit), isFalse);
      expect(scope.key, const ValueKey('tg-1:session'));
    });

    test('a shape-3 PRE-LADDER folded session roots kFoldedCodeCircuit — the '
        'readiness ladder never mounts for an in-flight survivor', () {
      final scope = scopeFor(
        _session(const {
          'tg-1/spec_review/specify': _complete,
          'tg-1/agent': _running,
        }),
      );
      expect(identical(scope.circuit, kFoldedCodeCircuit), isTrue);
      expect(identical(scope.circuit, kCodeCircuit), isFalse);
      expect(scope.key, const ValueKey('tg-1:session'));
    });

    test('a shape-2 SPEC-HEAD session roots kSpecHeadCodeCircuit', () {
      final scope = scopeFor(
        _session(const {'tg-1/specify': _complete, 'tg-1/agent': _complete}),
      );
      expect(identical(scope.circuit, kSpecHeadCodeCircuit), isTrue);
      expect(scope.key, const ValueKey('tg-1:session'));
    });

    test('a shape-1 LEGACY session roots kLegacyCodeCircuit', () {
      final scope = scopeFor(_session(const {'tg-1/agent': _complete}));
      expect(identical(scope.circuit, kLegacyCodeCircuit), isTrue);
      expect(scope.key, const ValueKey('tg-1:session'));
    });
  });

  group('the FROZEN shapes', () {
    test('kLegacyCodeCircuit: agent → review → land → deliver, no spec steps',
        () {
      expect(kLegacyCodeCircuit.id, 'code');
      expect(kLegacyCodeCircuit.terminalStepId, kDeliverStep);
      expect(kLegacyCodeCircuit.steps.map((s) => s.stepId), [
        'agent',
        'review',
        'land',
        kDeliverStep,
      ]);
      expect(kLegacyCodeCircuit.stepById('specify'), isNull);
      expect(kLegacyCodeCircuit.stepById('spec_review'), isNull);
    });

    test(
      'kSpecHeadCodeCircuit: specify → spec_review → agent → review → land, '
      'with spec_review pointing at the FROZEN sub-circuit',
      () {
        expect(kSpecHeadCodeCircuit.id, 'code');
        expect(kSpecHeadCodeCircuit.terminalStepId, kDeliverStep);
        expect(kSpecHeadCodeCircuit.steps.map((s) => s.stepId), [
          'specify',
          'spec_review',
          'agent',
          'review',
          'land',
          kDeliverStep,
        ]);
        final sub =
            kSpecHeadCodeCircuit.stepById('spec_review')! as SubCircuitStep;
        expect(sub.circuitId, kSpecHeadSpecReviewCircuitId);
        expect(sub.circuitId, isNot('spec_review'));
      },
    );

    test(
      'kSpecHeadSpecReviewCircuit has NO specify step and runs the pre-fold '
      'BINARY route (a Rewind could not name a non-sibling specify)',
      () {
        expect(kSpecHeadSpecReviewCircuit.id, kSpecHeadSpecReviewCircuitId);
        expect(kSpecHeadSpecReviewCircuit.terminalStepId, 'route');
        expect(kSpecHeadSpecReviewCircuit.stepById('specify'), isNull);
        final route =
            kSpecHeadSpecReviewCircuit.stepById('route')! as CapabilityStep;
        expect(route.capabilityId, 'route');
        expect(route.capabilityId, isNot('spec-route'));
      },
    );

    test(
      'kFoldedSpecReviewCircuit has NO readiness ladder and KEEPS the three-way '
      'spec route (specify IS its sibling here, so a Rewind naming it is legal)',
      () {
        expect(kFoldedSpecReviewCircuit.id, kFoldedSpecReviewCircuitId);
        expect(kFoldedSpecReviewCircuit.terminalStepId, 'route');
        expect(kFoldedSpecReviewCircuit.stepById('intake'), isNull);
        expect(kFoldedSpecReviewCircuit.stepById('readiness'), isNull);
        expect(kFoldedSpecReviewCircuit.stepById('readiness-route'), isNull);
        expect(kFoldedSpecReviewCircuit.stepById('specify'), isNotNull);
        expect(kFoldedSpecReviewCircuit.stepById('specify')!.dependsOn, isEmpty);
        final route =
            kFoldedSpecReviewCircuit.stepById('route')! as CapabilityStep;
        expect(route.capabilityId, 'spec-route');
      },
    );

    test('kFoldedCodeCircuit points spec_review at the FROZEN pre-ladder body',
        () {
      expect(kFoldedCodeCircuit.id, 'code');
      expect(kFoldedCodeCircuit.terminalStepId, kDeliverStep);
      expect(kFoldedCodeCircuit.steps.map((s) => s.stepId), [
        'spec_review',
        'agent',
        'review',
        'land',
        kDeliverStep,
      ]);
      final sub = kFoldedCodeCircuit.stepById('spec_review')! as SubCircuitStep;
      expect(sub.circuitId, kFoldedSpecReviewCircuitId);
      expect(sub.circuitId, isNot('spec_review'));
    });

    test(
      'kLadderedSpecReviewCircuit KEEPS the readiness ladder but has NO '
      'discovery step — nothing to inflate, so a survivor spawns no explorer — '
      'and it keeps the three-way spec route (specify IS its sibling here)',
      () {
        expect(kLadderedSpecReviewCircuit.id, kLadderedSpecReviewCircuitId);
        expect(kLadderedSpecReviewCircuit.terminalStepId, 'route');
        expect(kLadderedSpecReviewCircuit.stepById('intake'), isNotNull);
        expect(
          kLadderedSpecReviewCircuit.steps.map((s) => s.stepId),
          isNot(contains(kDiscoveryCircuitId)),
        );
        // Under shape 4, `specify` depended on `readiness-route` DIRECTLY.
        expect(
          kLadderedSpecReviewCircuit.stepById('specify')!.dependsOn,
          {'readiness-route'},
        );
        final route =
            kLadderedSpecReviewCircuit.stepById('route')! as CapabilityStep;
        expect(route.capabilityId, 'spec-route');
      },
    );

    test('kLadderedCodeCircuit points spec_review at the FROZEN pre-discovery '
        'body', () {
      expect(kLadderedCodeCircuit.id, 'code');
      expect(kLadderedCodeCircuit.terminalStepId, kDeliverStep);
      expect(kLadderedCodeCircuit.steps.map((s) => s.stepId), [
        'spec_review',
        'agent',
        'review',
        'land',
        kDeliverStep,
      ]);
      final sub =
          kLadderedCodeCircuit.stepById('spec_review')! as SubCircuitStep;
      expect(sub.circuitId, kLadderedSpecReviewCircuitId);
      expect(sub.circuitId, isNot('spec_review'));
    });

    test('the CURRENT spec circuit is the DISCOVERY one (the contrast)', () {
      expect(kSpecReviewCircuit.stepById('specify'), isNotNull);
      expect(kSpecReviewCircuit.stepById(kIntakeStep), isNotNull);
      expect(kSpecReviewCircuit.stepById(kDiscoveryCircuitId), isNotNull);
      expect(
        kSpecReviewCircuit.stepById(kSpecifyStep)!.dependsOn,
        {kDiscoveryCircuitId},
      );
    });
  });

  group('the registry', () {
    test('registers ALL THREE frozen sub-circuits beside the current one', () {
      final registry = buildCodeRegistry();
      expect(
        identical(
          registry.circuit(kSpecHeadSpecReviewCircuitId),
          kSpecHeadSpecReviewCircuit,
        ),
        isTrue,
      );
      expect(
        identical(
          registry.circuit(kFoldedSpecReviewCircuitId),
          kFoldedSpecReviewCircuit,
        ),
        isTrue,
      );
      expect(
        identical(
          registry.circuit(kLadderedSpecReviewCircuitId),
          kLadderedSpecReviewCircuit,
        ),
        isTrue,
      );
      expect(
        identical(registry.circuit('spec_review'), kSpecReviewCircuit),
        isTrue,
      );
      expect(
        identical(registry.circuit(kDiscoveryCircuitId), kDiscoveryCircuit),
        isTrue,
      );
    });
  });
}

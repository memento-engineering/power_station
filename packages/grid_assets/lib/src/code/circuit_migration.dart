/// The `code`-circuit MIGRATION GUARD (bead `pow-3p4`) — the edge ADR-0000
/// A15(6) carved out of the fold rather than absorbing.
///
/// [kCodeCircuit]'s spec head has been reshaped FOUR times, and each reshape
/// moved (or added) a persisted cursor key:
///
///  1. **legacy** (pre-`pow-6ao`) — `agent → review → land`. No spec phase.
///  2. **spec-head** (`pow-6ao`, A13(1)) — `specify → spec_review → agent →
///     review → land`. `specify` is a step of the ROOT circuit, so its cursor
///     key is `<bead>/specify`.
///  3. **folded** (`pow-ui8`, A15(1)) — `spec_review → agent → review → land`,
///     with `specify` folded INSIDE the spec circuit so the spec route's
///     `Rewind` may name it as a sibling. The key MOVED to
///     `<bead>/spec_review/specify`.
///  4. **laddered** (`pow-q7n`, A17) — the SPEC-READINESS INTAKE LENS re-heads
///     the spec circuit (`intake` → `readiness` → `readiness-route` → `specify`
///     → …), so the spec circuit's only dep-free step is now `intake` and the
///     head key MOVED again, to `<bead>/spec_review/intake`.
///  5. **discovery** (`discovery.dart`; CURRENT) — the DISCOVERY circuit is
///     spliced BETWEEN the ladder and `specify` (`readiness-route` → `discovery`
///     → `specify`), so `specify` gains a new dependency and the discovery
///     circuit's own dep-free step appears at
///     `<bead>/spec_review/discovery/anchors`. This is the FIRST reshape that did
///     NOT move the circuit's head — `intake` is still the spec circuit's only
///     dep-free step — which is why [classifyCodeShape] discriminates on
///     `specify`, not on the head (see its doc).
///
/// The frontier reads a MISSING cursor key as `pending` (`cursorNodeAt`), so a
/// session minted under an OLDER shape and still in flight across a station
/// BOUNCE has no key where the current circuit expects one: the current circuit
/// would mount a step for a bead already mid-review or mid-land. Under shapes 1–2
/// that spawns a spurious `specify` architect which MUTATES the work bead's
/// acceptance and design via bd; under shape 3 it mounts the readiness ladder,
/// whose `readiness` tier SPAWNS A REAL AGENT and whose `readiness-route` can
/// PARK (`Gate`) a bead whose build is already running; under shape 4 it mounts
/// the DISCOVERY circuit, which SPAWNS THREE READ-ONLY AGENTS and whose route can
/// likewise PARK a bead whose build is already running.
///
/// The NAMED invariant this file protects: **a session that already advanced
/// past its own circuit's head never re-enters the spec phase.** The guard is
/// pure bead→circuit ROUTING at the engine's existing [SessionResolver] seam —
/// zero engine change, holding A13(1)'s wiring-only posture:
/// [CodeCircuitResolver] classifies the ADOPTED cursor with [classifyCodeShape]
/// and roots the FROZEN shape the session was MINTED under, so an old-shape
/// survivor's frontier has no new head step to mount. Fresh beads, and
/// freshly-minted or reworked (empty-cursor) sessions, root the CURRENT shape.
///
/// **RETIREMENT.** This is a MIGRATION, not a permanent seam: it exists only
/// while old-shape sessions are in flight. Once no OPEN session carries a
/// shape-1, shape-2, shape-3 **or shape-4** cursor (every survivor landed,
/// closed, or was reworked into a fresh round), DELETE this file, drop
/// `...kMigrationCircuits` from `buildCodeRegistry`, and put the production
/// composition back to `CircuitResolver((_) => kCodeCircuit)`.
///
/// **Layering note (do not "fix" into a cycle).** This library imports NOTHING
/// from `code_capabilities.dart`: the CURRENT circuit arrives as a constructor
/// VALUE ([CodeCircuitResolver.current] — config = values, ADR-0008 D-H), and
/// `code_capabilities.dart` imports THIS library for [kMigrationCircuits]. That
/// one-way edge is deliberate.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';

/// The FROZEN **legacy** root shape — `agent → review → land`, the shape of
/// `kCodeCircuit` before `pow-6ao` (git `a67feb8~1`). The migration target for
/// a shape-1 survivor.
///
/// Its sub-circuits (`code_review`, `landing`) are the SAME registry entries the
/// current circuit uses — the fold did not touch them — so an adopted legacy
/// session continues exactly as it would have: the review lanes fan out, land
/// completes, the session closes. Every step id is a LITERAL, never a shared
/// const: a frozen shape must not follow a future rename. Never hand this to
/// NEW work.
const Circuit kLegacyCodeCircuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    SubCircuitStep(
      stepId: 'review',
      circuitId: 'code_review',
      dependsOn: {'agent'},
    ),
    SubCircuitStep(stepId: 'land', circuitId: 'landing', dependsOn: {'review'}),
  ],
);

/// The registry id of [kSpecHeadSpecReviewCircuit] — the FROZEN pre-fold spec
/// circuit. Deliberately NOT `spec_review` (that id now resolves to the CURRENT
/// circuit, which CONTAINS `specify`).
const String kSpecHeadSpecReviewCircuitId = 'spec_review_v1';

/// The FROZEN **pre-fold spec circuit** (git `a67feb8`) — `clear-critique` →
/// the gating lane + four LLM critics in parallel → `route`. `specify` is NOT
/// in it: under shape 2 the architect ran at the ROOT circuit's `<bead>/specify`.
///
/// Registered under [kSpecHeadSpecReviewCircuitId] and reachable ONLY from
/// [kSpecHeadCodeCircuit]. It is the whole reason shape 2 needs its own frozen
/// sub-circuit: pointing shape 2's `spec_review` step at the CURRENT
/// `spec_review` would inflate a circuit whose head IS `specify`, re-mounting
/// it at `<bead>/spec_review/specify` — precisely the spawn this guard exists
/// to prevent.
///
/// Its `route` runs `capabilityId: 'route'` — the pre-fold BINARY matrix
/// (`RouteCapability`: advance | gate), NOT the current `spec-route`. That is
/// load-bearing, not incidental: `SpecRouteCapability` actuates a
/// `StepOutcome.Rewind` naming `specify`, and a `Rewind` may only name steps of
/// the rewinding node's OWN circuit — `specify` is not a sibling here. A
/// shape-2 session minted between `pow-7nm` and the fold (same node paths, a
/// three-way route) therefore degrades to the binary matrix: a fixable spec
/// PARKS at a gate instead of auto-respec-ing. That is the deliberate
/// fail-SAFE call for a migration path — these sessions are already past
/// `specify`, and a park is a human unwind, never a spurious mutation.
const Circuit kSpecHeadSpecReviewCircuit = Circuit(
  id: kSpecHeadSpecReviewCircuitId,
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'clear-critique', capabilityId: 'clear-critique'),
    CapabilityStep(
      stepId: 'spec-validation',
      capabilityId: 'spec-validation',
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'coherence',
      capabilityId: 'spec-critic',
      params: {'rubric': 'coherence'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'adr-alignment',
      capabilityId: 'spec-critic',
      params: {'rubric': 'adr-alignment'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'acceptance-testability',
      capabilityId: 'spec-critic',
      params: {'rubric': 'acceptance-testability'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'plan-completeness',
      capabilityId: 'spec-critic',
      params: {'rubric': 'plan-completeness'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {
        'spec-validation',
        'coherence',
        'adr-alignment',
        'acceptance-testability',
        'plan-completeness',
      },
      params: {
        'critics': 'spec-validation,coherence,adr-alignment,'
            'acceptance-testability,plan-completeness',
        'gating': 'spec-validation',
      },
    ),
  ],
);

/// The FROZEN **spec-head** root shape (`pow-6ao`, git `a67feb8`) — `specify →
/// spec_review → agent → review → land`, with `specify` a step of the ROOT
/// circuit (cursor key `<bead>/specify`). The migration target for a shape-2
/// survivor.
///
/// Its `spec_review` step keeps `stepId: 'spec_review'` but points its
/// `circuitId` at [kSpecHeadSpecReviewCircuitId]. That split is what makes the
/// freeze work: the inflater derives the NODE PATH from `stepId`
/// (`circuit_scope.dart` — `stepPath(nodePath, step.stepId)`) and resolves the
/// SHAPE from `circuitId` (`reg.circuit(circuitId)`), so the sub-circuit's
/// children still land at `<bead>/spec_review/<lane>` and an adopted shape-2
/// cursor lines up key-for-key, while the body inflated is the pre-fold one
/// that has no `specify` in it.
const Circuit kSpecHeadCodeCircuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'specify', capabilityId: 'specify'),
    SubCircuitStep(
      stepId: 'spec_review',
      circuitId: kSpecHeadSpecReviewCircuitId,
      dependsOn: {'specify'},
    ),
    CapabilityStep(
      stepId: 'agent',
      capabilityId: 'agent',
      dependsOn: {'spec_review'},
    ),
    SubCircuitStep(
      stepId: 'review',
      circuitId: 'code_review',
      dependsOn: {'agent'},
    ),
    SubCircuitStep(stepId: 'land', circuitId: 'landing', dependsOn: {'review'}),
  ],
);

/// The registry id of [kFoldedSpecReviewCircuit] — the FROZEN pre-LADDER spec
/// circuit. Deliberately NOT `spec_review` (that id now resolves to the CURRENT
/// circuit, whose head is the readiness LADDER).
const String kFoldedSpecReviewCircuitId = 'spec_review_v2';

/// The FROZEN **pre-ladder folded** spec circuit (`pow-ui8`, git `996d020`) —
/// `specify → clear-critique → the gating lane + four LLM critics → route`. The
/// readiness LADDER (bead `pow-q7n`) is NOT in it: under shape 3 the spec
/// circuit's head was `specify` itself.
///
/// Registered under [kFoldedSpecReviewCircuitId] and reachable ONLY from
/// [kFoldedCodeCircuit]. Pointing shape 3's `spec_review` step at the CURRENT
/// `spec_review` would inflate a circuit whose head is `intake` → `readiness`,
/// mounting a lens — and SPAWNING its agent — for a session already past the
/// spec phase: precisely the spawn this guard exists to prevent.
///
/// Unlike the shape-2 freeze, its `route` KEEPS `capabilityId: 'spec-route'`
/// (the three-way advance | RESPEC | escalate matrix): `specify` IS a sibling in
/// this circuit, so a `StepOutcome.Rewind` naming it is legal here. A shape-3
/// survivor therefore keeps its auto-respec — no capability degrades.
const Circuit kFoldedSpecReviewCircuit = Circuit(
  id: kFoldedSpecReviewCircuitId,
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'specify', capabilityId: 'specify'),
    CapabilityStep(
      stepId: 'clear-critique',
      capabilityId: 'clear-critique',
      dependsOn: {'specify'},
    ),
    CapabilityStep(
      stepId: 'spec-validation',
      capabilityId: 'spec-validation',
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'coherence',
      capabilityId: 'spec-critic',
      params: {'rubric': 'coherence'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'adr-alignment',
      capabilityId: 'spec-critic',
      params: {'rubric': 'adr-alignment'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'acceptance-testability',
      capabilityId: 'spec-critic',
      params: {'rubric': 'acceptance-testability'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'plan-completeness',
      capabilityId: 'spec-critic',
      params: {'rubric': 'plan-completeness'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'spec-route',
      dependsOn: {
        'spec-validation',
        'coherence',
        'adr-alignment',
        'acceptance-testability',
        'plan-completeness',
      },
      params: {
        'critics': 'spec-validation,coherence,adr-alignment,'
            'acceptance-testability,plan-completeness',
        'gating': 'spec-validation',
      },
    ),
  ],
);

/// The FROZEN **pre-ladder folded** root shape (`pow-ui8`, git `996d020`) —
/// `spec_review → agent → review → land`, whose `spec_review` step keeps
/// `stepId: 'spec_review'` (so every child node path lines up key-for-key with
/// the adopted cursor) but points its `circuitId` at
/// [kFoldedSpecReviewCircuitId], so the body inflated is the pre-ladder one.
/// The migration target for a shape-3 survivor.
const Circuit kFoldedCodeCircuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    SubCircuitStep(
      stepId: 'spec_review',
      circuitId: kFoldedSpecReviewCircuitId,
    ),
    CapabilityStep(
      stepId: 'agent',
      capabilityId: 'agent',
      dependsOn: {'spec_review'},
    ),
    SubCircuitStep(
      stepId: 'review',
      circuitId: 'code_review',
      dependsOn: {'agent'},
    ),
    SubCircuitStep(stepId: 'land', circuitId: 'landing', dependsOn: {'review'}),
  ],
);

/// The registry id of [kLadderedSpecReviewCircuit] — the FROZEN pre-DISCOVERY
/// spec circuit. Deliberately NOT `spec_review` (that id now resolves to the
/// CURRENT circuit, whose `specify` dependsOn the discovery circuit).
const String kLadderedSpecReviewCircuitId = 'spec_review_v3';

/// The FROZEN **pre-discovery laddered** spec circuit (`pow-q7n`, git `4f9d5c1`)
/// — `intake` → `readiness` → `readiness-route` → `specify` → `clear-critique` →
/// the gating lane + four LLM critics → `route`. The DISCOVERY circuit is NOT in
/// it: under shape 4 `specify` depended directly on `readiness-route`.
///
/// Registered under [kLadderedSpecReviewCircuitId] and reachable ONLY from
/// [kLadderedCodeCircuit]. Pointing shape 4's `spec_review` step at the CURRENT
/// `spec_review` would inflate a circuit whose `specify` dependsOn a `discovery`
/// sub-circuit the survivor's cursor has never seen — the frontier reads those
/// missing keys as `pending`, mounts the gather, SPAWNS THREE REAL AGENTS, and
/// its route could PARK a bead whose build is already running. That is precisely
/// the spawn this guard exists to prevent.
///
/// Its `route` keeps `capabilityId: 'spec-route'` (the three-way matrix):
/// `specify` IS a sibling here, so a `Rewind` naming it is legal and a shape-4
/// survivor keeps its auto-respec — no capability degrades.
const Circuit kLadderedSpecReviewCircuit = Circuit(
  id: kLadderedSpecReviewCircuitId,
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'intake', capabilityId: 'intake'),
    CapabilityStep(
      stepId: 'readiness',
      capabilityId: 'readiness',
      params: {'rubric': 'bead-readiness'},
      dependsOn: {'intake'},
    ),
    CapabilityStep(
      stepId: 'readiness-route',
      capabilityId: 'readiness-route',
      params: {'lane': 'readiness'},
      dependsOn: {'readiness'},
    ),
    CapabilityStep(
      stepId: 'specify',
      capabilityId: 'specify',
      dependsOn: {'readiness-route'},
    ),
    CapabilityStep(
      stepId: 'clear-critique',
      capabilityId: 'clear-critique',
      dependsOn: {'specify'},
    ),
    CapabilityStep(
      stepId: 'spec-validation',
      capabilityId: 'spec-validation',
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'coherence',
      capabilityId: 'spec-critic',
      params: {'rubric': 'coherence'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'adr-alignment',
      capabilityId: 'spec-critic',
      params: {'rubric': 'adr-alignment'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'acceptance-testability',
      capabilityId: 'spec-critic',
      params: {'rubric': 'acceptance-testability'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'plan-completeness',
      capabilityId: 'spec-critic',
      params: {'rubric': 'plan-completeness'},
      dependsOn: {'clear-critique'},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'spec-route',
      dependsOn: {
        'spec-validation',
        'coherence',
        'adr-alignment',
        'acceptance-testability',
        'plan-completeness',
      },
      params: {
        'critics': 'spec-validation,coherence,adr-alignment,'
            'acceptance-testability,plan-completeness',
        'gating': 'spec-validation',
      },
    ),
  ],
);

/// The FROZEN **pre-discovery laddered** root shape (`pow-q7n`, git `4f9d5c1`) —
/// `spec_review → agent → review → land`, whose `spec_review` step keeps
/// `stepId: 'spec_review'` (so every child node path lines up key-for-key with
/// the adopted cursor) but points its `circuitId` at
/// [kLadderedSpecReviewCircuitId]. The migration target for a shape-4 survivor.
const Circuit kLadderedCodeCircuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    SubCircuitStep(
      stepId: 'spec_review',
      circuitId: kLadderedSpecReviewCircuitId,
    ),
    CapabilityStep(
      stepId: 'agent',
      capabilityId: 'agent',
      dependsOn: {'spec_review'},
    ),
    SubCircuitStep(
      stepId: 'review',
      circuitId: 'code_review',
      dependsOn: {'agent'},
    ),
    SubCircuitStep(stepId: 'land', circuitId: 'landing', dependsOn: {'review'}),
  ],
);

/// The registry entries the frozen shapes need, spread into `buildCodeRegistry`.
/// Only the frozen SPEC circuits need registering — the legacy shape's
/// `code_review`/`landing` sub-circuits are the CURRENT ones, unchanged by any
/// reshape, and a ROOT circuit is passed to `SessionScope` directly rather than
/// looked up by id.
const Map<String, Circuit> kMigrationCircuits = {
  kSpecHeadSpecReviewCircuitId: kSpecHeadSpecReviewCircuit,
  kFoldedSpecReviewCircuitId: kFoldedSpecReviewCircuit,
  kLadderedSpecReviewCircuitId: kLadderedSpecReviewCircuit,
};

/// Which shape of the `code` circuit a session's cursor was MINTED under.
enum CodeCircuitShape {
  /// The CURRENT circuit: the DISCOVERY circuit sits between the readiness ladder
  /// and `specify`, so a session that reached `specify` has written
  /// `<bead>/spec_review/discovery/anchors`. Also the shape for a fresh bead and
  /// for a freshly-minted / reworked (empty-cursor) session.
  discovery,

  /// The `pow-q7n` circuit: the readiness ladder heads the spec circuit and
  /// `specify` dependsOn `readiness-route` DIRECTLY — no discovery circuit.
  laddered,

  /// The `pow-ui8` circuit: `specify` is the spec circuit's head, at
  /// `<bead>/spec_review/specify`, with NO readiness ladder before it.
  folded,

  /// The `pow-6ao` circuit: `specify` lives at `<bead>/specify`.
  specHead,

  /// The pre-`pow-6ao` circuit: no spec phase at all.
  legacy,
}

/// Classifies the shape [cursor] was minted under, for the session of [beadId].
///
/// PRESENCE, not state, is the signal (A16) — every persisted cursor key was
/// written by a host that actually MOUNTED (running or terminal; D-7's gate
/// re-arm flips a parked node back to an explicit `pending`, key still present),
/// so reading the STATE instead would misclassify a re-armed head.
///
/// But the DISCOVERY reshape is the first that did NOT move the circuit's head:
/// `intake` is still the spec circuit's only dep-free step, so `intake`-presence
/// no longer separates shape 4 from shape 5. The discriminator is therefore the
/// step DOWNSTREAM of the insertion point:
///
///  - a cursor holding `spec_review/discovery/anchors` is shape 5 (the discovery
///    circuit's only dep-free step — any session that reached `specify` under
///    this shape necessarily wrote it, so presence stays TOTAL);
///  - a cursor holding the LADDER but ALSO `spec_review/specify`, with NO
///    discovery key, is a shape-4 SURVIVOR that already specified: it is FROZEN
///    on [kLadderedCodeCircuit], so the gather never mounts, its three agents
///    never spawn, and its route can never PARK a bead whose build is running;
///  - a cursor holding the LADDER and NOT `specify` is still IN the ladder. It
///    adopts the CURRENT shape and MIGRATES FORWARD — it gains the discovery
///    circuit, which mounts exactly where it belongs (after `readiness-route`,
///    before `specify`). Nothing downstream has run, so there is no spurious
///    spawn and nothing to re-do: the ONLY safe direction, and the reason the
///    discriminator is `specify` rather than `intake`.
///
/// Keys rooted at another bead's id are IGNORED (they say nothing about this
/// session), so a cursor with no keys of our own is [CodeCircuitShape.discovery]
/// — a fresh mint, or a bead that never started, both of which correctly get the
/// current spec stage. A rework round also lands here: `grid rework` re-keys the
/// prior session's `work_bead` to `<bead>#rN`, so the tree finds no session at
/// `bead.id` and MINTS one with an empty cursor.
///
/// The final fall-through to [CodeCircuitShape.legacy] is FAIL-CLOSED: given keys
/// of our own and no `specify`/`intake` node at ANY path, the one thing we must
/// never do is root a circuit that can mount `specify`. The legacy shape has no
/// spec phase at all, so the named invariant holds even for a cursor state that
/// should not be reachable.
CodeCircuitShape classifyCodeShape({
  required String beadId,
  required CircuitCursor cursor,
}) {
  final prefix = '$beadId/';
  final ours = cursor.keys.where((k) => k.startsWith(prefix));
  if (ours.isEmpty) return CodeCircuitShape.discovery;

  final specReview = stepPath(beadId, 'spec_review');
  final specify = stepPath(specReview, 'specify');

  // Shape 5 (CURRENT) — the discovery circuit's own head. Literal ids: a
  // persisted cursor key is a WIRE fact and must not follow a source rename.
  if (cursor.containsKey(
    stepPath(stepPath(specReview, 'discovery'), 'anchors'),
  )) {
    return CodeCircuitShape.discovery;
  }

  // Shapes 4/5 both carry the ladder. Only a session that already SPECIFIED under
  // the pre-discovery shape must be frozen; one still in the ladder migrates
  // forward.
  if (cursor.containsKey(stepPath(specReview, 'intake'))) {
    return cursor.containsKey(specify)
        ? CodeCircuitShape.laddered
        : CodeCircuitShape.discovery;
  }

  // Shape 3 — folded, PRE-ladder: `specify` inside spec_review, no ladder keys.
  if (cursor.containsKey(specify)) return CodeCircuitShape.folded;

  // Shape 2 — spec-head: `specify` at the ROOT circuit.
  if (cursor.containsKey(stepPath(beadId, 'specify'))) {
    return CodeCircuitShape.specHead;
  }

  return CodeCircuitShape.legacy;
}

/// The migration-aware bead→circuit resolver for the `code` circuit — the
/// production replacement for `CircuitResolver((_) => kCodeCircuit)`.
///
/// [current] is the CURRENT (folded) root circuit — production passes
/// `kCodeCircuit`. It arrives as a VALUE rather than an import so this library
/// stays free of `code_capabilities.dart` (see the library doc), and so a test
/// can inject a shape of its own (config = values in the tree; impls = DI —
/// ADR-0008 D-H).
///
/// It delegates to the engine's [CircuitResolver] so the engine stays the single
/// owner of the [SessionResolver] key contract (`ValueKey('<bead.id>:session')`)
/// — this class picks only the ROOT SHAPE. The classification is recomputed on
/// every `WorkBead.build` from the injected (bead, session): `WorkBead` reads the
/// resolver with the SUBSCRIBING `dependOnInheritedSeedOfExactType`, and this is
/// a const, stateless policy object that caches NOTHING (D-H: always watch deps;
/// never snapshot-and-cache reactive state).
///
/// ARMING NOTE (out of this repo's diff): the live station composes the resolver
/// in space_station `lib/src/up_command.dart`
/// (`resolver: CircuitResolver((_) => kCodeCircuit)`). The guard is armed only
/// when that line becomes `resolver: const CodeCircuitResolver(kCodeCircuit)` —
/// the one-line follow-up that must ride the same space_station grid_assets bump
/// that first bounces onto the folded circuit. THIS BEAD GATES THAT BOUNCE.
class CodeCircuitResolver implements SessionResolver {
  /// Creates the migration-aware `code` resolver over the [current] root shape.
  const CodeCircuitResolver(this.current);

  /// The CURRENT (discovery) root circuit — `kCodeCircuit` in production.
  final Circuit current;

  /// The root circuit for [shape] — [current] for the current shape, else the
  /// frozen shape the session was minted under.
  Circuit circuitFor(CodeCircuitShape shape) => switch (shape) {
    CodeCircuitShape.discovery => current,
    CodeCircuitShape.laddered => kLadderedCodeCircuit,
    CodeCircuitShape.folded => kFoldedCodeCircuit,
    CodeCircuitShape.specHead => kSpecHeadCodeCircuit,
    CodeCircuitShape.legacy => kLegacyCodeCircuit,
  };

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) {
    final circuit = circuitFor(
      classifyCodeShape(
        beadId: bead.id,
        cursor: session?.cursor ?? const <String, NodeCursor>{},
      ),
    );
    return CircuitResolver(
      (_) => circuit,
    ).sessionFor(bead: bead, session: session);
  }
}

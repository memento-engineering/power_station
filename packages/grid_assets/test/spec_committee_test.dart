// The spec-readiness committee (bead `pow-6ao`) — the pluggable committee
// machine (`committee.dart`) reused for the SPEC gate upstream of the build.
//
// Proves: the `spec_review` circuit's shape (hygiene → the deterministic
// gating lane + four isolated LLM spec critics → the shared route matrix);
// the structural gate's LOUD findings (a placeholder / section-less / absent
// spec grades F — a spec-less bead can never silently reach the build); the
// spec critic's prompt (its own rubric only, the spec as review subject —
// never a pinned diff — the live-tree verification instruction, and the SAME
// verdict hardening as the code critics: nodePath freshness stamp + absolute
// canonical path); the inherited verdict transports; and the route matrix
// over the spec param set (a gating F names `spec-validation` in the parked
// gate). Zero I/O — no real claude/bd/git.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _specCritics =
    'spec-validation,coherence,decision-alignment,acceptance-testability,'
    'plan-completeness';

/// A bead carrying a structurally WHOLE spec — the SHIPPED exemplar itself, so
/// this suite's "conforming" fixture cannot drift from the one the brief
/// teaches and the round-trip fence proves.
Bead _specced() => bead('tg-1').copyWith(
  title: 'Wire the federation bus',
  acceptanceCriteria: kSpecExemplarAcceptance,
  design: kSpecExemplarDesign,
);

({FakeTreeContext context, StepArgs args}) _laneCtx({
  required String rubric,
  Bead? beadOverride,
  String workspaceDir = '/w/tg-1',
  String? nodePath,
  int round = 0,
  Map<String, String>? specifyResult,
}) {
  final path = nodePath ?? 'tg-1/spec_review/$rubric';
  // The ROUND is the respec LEDGER's own `round` (A27(3), re-sourced here by
  // A27(7)(a)'s follow-up, bead `pow-96s`) — the counter the critic stamps and
  return (
    context: FakeTreeContext(
      values: {
        Bead: beadOverride ?? _specced(),
        Workspace: testWorkspace(
          'tg-1',
          workspaceDir: workspaceDir,
          branch: 'grid/tg-1',
        ),
        if (specifyResult != null)
          SiblingView: SiblingView(
            results: {'${parentPath(path)}/$kSpecifyStep': specifyResult},
          ),
      },
    ),
    args: stepArgs(path, params: {'rubric': rubric, 'grid.round': '$round'}),
  );
}

/// Runs the SPEC route (bead `pow-7nm` — the three-way matrix) over the
/// fabricated [grades], with [rationales] where a critic returned one. No
/// ambient `Workspace` ⇒ the offline posture (no ledger I/O; the round counter
/// reads 0).
Future<RouteVerdict> _specRoute(
  Map<String, String> grades, {
  Map<String, String> rationales = const {},
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
    },
  );
  return const SpecRouteCapability().route(
    context,
    stepArgs(
      '$parent/route',
      params: const {'critics': _specCritics, 'gating': kSpecGatingRubric},
    ),
  );
}

void main() {
  test('SpecCriticCapability inherits artifact durability', () {
    expect(
      const SpecCriticCapability().completionContract,
      CompletionContract.artifactDurability,
    );
  });

  group('specForStructuralValidation', () {
    final ambient = bead(
      'tg-1',
    ).copyWith(title: 'preserved title', metadata: const {'rig': 'tgdog'});
    final carried = {
      kCarriedSpecAcceptanceKey: kSpecExemplarAcceptance,
      kCarriedSpecDesignKey: kSpecExemplarDesign,
    };

    test('replaces only the spec fields on the fallback', () {
      final selected = specForStructuralValidation(
        fallback: ambient,
        specifyResult: carried,
      )!;
      expect(selected.id, ambient.id);
      expect(selected.title, ambient.title);
      expect(selected.metadata, ambient.metadata);
      expect(selected.acceptanceCriteria, kSpecExemplarAcceptance);
      expect(selected.design, kSpecExemplarDesign);
    });

    for (final entry in <String, Map<String, String>>{
      'absent': const {},
      'empty': {kCarriedSpecAcceptanceKey: '', kCarriedSpecDesignKey: ''},
      'blank': {kCarriedSpecAcceptanceKey: ' ', kCarriedSpecDesignKey: '\n'},
      'acceptance only': {kCarriedSpecAcceptanceKey: kSpecExemplarAcceptance},
      'design only': {kCarriedSpecDesignKey: kSpecExemplarDesign},
    }.entries) {
      test('${entry.key} carried fields return the identical fallback', () {
        expect(
          identical(
            specForStructuralValidation(
              fallback: ambient,
              specifyResult: entry.value,
            ),
            ambient,
          ),
          isTrue,
        );
      });
    }

    test('a complete pair without a fallback returns null', () {
      expect(
        specForStructuralValidation(fallback: null, specifyResult: carried),
        isNull,
      );
    });
  });

  group('kSpecReviewCircuit — the shape', () {
    test('readiness ladder → specify → hygiene → gating lane + four isolated '
        'spec critics → route; the route is the terminal', () {
      expect(kSpecReviewCircuit.id, 'spec_review');
      expect(kSpecReviewCircuit.terminalStepId, 'route');
      expect(kSpecReviewCircuit.maxRestarts, 3);
      final byId = {for (final s in kSpecReviewCircuit.steps) s.stepId: s};
      expect(byId.keys, {
        kIntakeStep,
        kReadinessStep,
        kReadinessRouteStep,
        kDiscoveryCircuitId,
        kSpecifyStep,
        kClearCritiqueStep,
        kSpecGatingRubric,
        ...kSpecLlmRubrics,
        'route',
      });
      // The READINESS LADDER is the head (bead `pow-q7n`) — cheapest first, and
      // `specify` only mounts behind it, so a not-ready bead HOLDS before any
      // architect or committee agent is ever spawned.
      expect(byId[kIntakeStep]!.dependsOn, isEmpty);
      expect(byId[kReadinessStep]!.dependsOn, {kIntakeStep});
      expect((byId[kReadinessStep]! as CapabilityStep).params, {
        'rubric': kReadinessRubric,
      });
      expect(byId[kReadinessRouteStep]!.dependsOn, {kReadinessStep});
      // `specify` is still the route's SIBLING (bead `pow-ui8`), so the RESPEC
      // arm can name it in a `validates` edge — it just no longer heads the
      // circuit, and it now sits behind the DISCOVERY gate as well.
      expect(
        (byId[kSpecifyStep]! as CapabilityStep).capabilityId,
        kSpecifyStep,
      );
      expect(byId[kSpecifyStep]!.dependsOn, {kDiscoveryCircuitId});
      // The hygiene wipe waits on specify, which is what puts EVERY lane
      // downstream of it (see the invalidated-closure test below).
      expect(byId[kClearCritiqueStep]!.dependsOn, {kSpecifyStep});
      // Every lane waits on the hygiene wipe (round-fresh verdict files).
      for (final rubric in kSpecCommitteeRubrics) {
        expect(
          (byId[rubric]! as CapabilityStep).dependsOn,
          {kClearCritiqueStep},
          reason: '$rubric depends on clear-critique',
        );
      }
      // The gating lane is the deterministic structural capability; the LLM
      // lanes share the one `spec-critic` capability, each with ONLY its own
      // rubric param (anti-anchoring).
      expect(
        (byId[kSpecGatingRubric]! as CapabilityStep).capabilityId,
        kSpecGatingRubric,
      );
      for (final rubric in kSpecLlmRubrics) {
        final step = byId[rubric]! as CapabilityStep;
        expect(step.capabilityId, 'spec-critic');
        expect(step.params, {'rubric': rubric});
      }
      // The route joins on ALL five lanes, names the gating lane, and DECLARES
      // the backward-motion edge the engine's derivation walks: a `grade: 'F'`
      // stamped by THIS step invalidates `specify` ∪ its transitive dependents
      // ∪ this route.
      final route = byId['route']! as CapabilityStep;
      expect(route.dependsOn, {kSpecGatingRubric, ...kSpecLlmRubrics});
      expect(route.params['gating'], kSpecGatingRubric);
      expect(route.params['critics'], _specCritics);
      expect(route.params[kValidatesParamKey], kSpecifyStep);
      // NO critic or gate step declares one: the derivation invalidates on a
      // SOURCE grade of `F`, and a critic `F` is a HUMAN ruling in this
      // committee's matrix, never an auto-respec. Edges there would INVERT the
      // matrix.
      for (final rubric in kSpecCommitteeRubrics) {
        expect(
          (byId[rubric]! as CapabilityStep).params[kValidatesParamKey],
          isNull,
        );
      }
    });

    test('INVALIDATING `specify` re-runs the WHOLE committee virgin — every '
        'other step is transitively DOWNSTREAM of it (bead `pow-ui8`)', () {
      // The engine's OWN closure predicate (grid_engine `sdk/rewind.dart`) —
      // the same one the `validates` derivation expands its edge through.
      final rewound = transitiveDependents(kSpecReviewCircuit, {kSpecifyStep});
      expect(rewound, {
        kClearCritiqueStep,
        kSpecGatingRubric,
        ...kSpecLlmRubrics,
        'route',
      });
      // TWO invariants ride this, not one.
      expect(
        rewound,
        containsAll(<String>[kSpecGatingRubric, ...kSpecLlmRubrics]),
        reason:
            'every lane re-runs, so the route can NEVER re-decide over a '
            'previous round\'s grades',
      );
      expect(
        rewound,
        contains(kClearCritiqueStep),
        reason:
            'ROUND-FRESHNESS: a critic\'s nodePath stamp is byte-identical '
            'across rounds and cannot by itself fence a stale verdict file — '
            'the successor re-key is what makes a round virgin. The critique '
            'WIPE is the BELT behind it: it stays in the closure so a round '
            'still starts '
            'with a clean workspace (and it remains the gating lane\'s only '
            'freshness fence — the `.rc` carries no stamp), which is exactly '
            'what `clear-critique dependsOn specify` buys.',
      );
      // The readiness ladder is UPSTREAM of `specify`, so it is outside the
      // invalidated closure and an auto-respec never re-runs it: a respec
      // rewrites the SPEC, not the BEAD (bead `pow-q7n`).
      expect(
        rewound,
        isNot(
          anyOf(
            contains(kIntakeStep),
            contains(kReadinessStep),
            contains(kReadinessRouteStep),
          ),
        ),
        reason:
            'a respec round must not burn an agent re-grading an unchanged '
            'bead',
      );
      // DISCOVERY is upstream of `specify` for exactly the same reason.
      expect(
        rewound,
        isNot(contains(kDiscoveryCircuitId)),
        reason:
            'a respec re-runs `specify` and its dependents; re-running three '
            'explorers per round would burn the very agents the discovery '
            'circuit exists to save',
      );
    });

    test('the DISCOVERY circuit heads the spec circuit and `specify` dependsOn '
        'it — a HELD bead spawns NO architect', () {
      final byId = {for (final s in kSpecReviewCircuit.steps) s.stepId: s};
      final discovery = byId[kDiscoveryCircuitId]! as SubCircuitStep;
      expect(discovery.circuitId, kDiscoveryCircuitId);
      expect(
        discovery.dependsOn,
        {kReadinessRouteStep},
        reason: 'the gather runs only once the ladder released the bead',
      );
      expect(
        (byId[kSpecifyStep]! as CapabilityStep).dependsOn,
        {kDiscoveryCircuitId},
        reason: 'the architect is withheld behind the violation gate',
      );
      // The engine's one-hop terminal resolution: the dep is satisfied by the
      // discovery circuit's TERMINAL, so a Gate there withholds `specify`.
      expect(kDiscoveryCircuit.terminalStepId, kDiscoveryRouteStep);
    });

    test('the discovery circuit is gather → 3 read-only lenses in parallel → '
        'the route: the lenses join on the gather, the route on all three', () {
      final byId = {for (final s in kDiscoveryCircuit.steps) s.stepId: s};
      expect(byId.keys.toList(), [
        kAnchorsStep,
        ...kDiscoveryLenses,
        kDiscoveryRouteStep,
      ]);
      // The gather is the circuit's ONLY dep-free step — its wipe + its gather
      // always land before any lens can read or write.
      expect((byId[kAnchorsStep]! as CapabilityStep).dependsOn, isEmpty);
      for (final lens in kDiscoveryLenses) {
        final step = byId[lens]! as CapabilityStep;
        expect(
          step.capabilityId,
          kDiscoveryCircuitId,
          reason: 'ONE capability, three lanes (the `params[rubric]` idiom)',
        );
        expect(step.params, {'lens': lens});
        expect(step.dependsOn, {kAnchorsStep});
      }
      final route = byId[kDiscoveryRouteStep]! as CapabilityStep;
      expect(route.dependsOn, kDiscoveryLenses.toSet());
      expect(route.params['lenses'], kDiscoveryLenses.join(','));
    });

    test('no pin-diff lane: the review subject is the bead\'s spec, not a '
        'code delta', () {
      expect(
        kSpecReviewCircuit.steps.map((s) => s.stepId),
        isNot(contains(kPinDiffStep)),
      );
    });

    test('the code circuit is spec_review → agent → review → land → deliver: '
        'the spec circuit is the HEAD (specify folded inside it) and only a '
        'passing spec proceeds to build', () {
      final byId = {for (final s in kCodeCircuit.steps) s.stepId: s};
      expect(byId.keys.toList(), [
        'spec_review',
        'agent',
        'review',
        'land',
        kDeliverStep,
      ]);
      expect(byId['spec_review']!.dependsOn, isEmpty);
      expect(byId['agent']!.dependsOn, {'spec_review'});
      expect((byId['spec_review']! as SubCircuitStep).circuitId, 'spec_review');
      // `specify` is no longer a step of THIS circuit — it lives in the spec
      // circuit as the route's rewindable sibling.
      expect(byId.keys, isNot(contains(kSpecifyStep)));
    });
  });

  group('SpecValidationCapability — the deterministic structural gate', () {
    test(
      'one committee stamps every lane with the same circuit round',
      () async {
        final dir = Directory.systemTemp.createTempSync('spec-round-stamps-');
        addTearDown(() => dir.deleteSync(recursive: true));

        final gating = _laneCtx(
          rubric: kSpecGatingRubric,
          workspaceDir: dir.path,
          round: 2,
        );
        final structural = await const SpecValidationCapability().run(
          gating.context,
          gating.args,
        );
        expect((structural as Ok).payload![kVerdictRoundKey], '2');

        for (final rubric in kSpecLlmRubrics) {
          final lane = _laneCtx(
            rubric: rubric,
            workspaceDir: dir.path,
            round: 2,
          );
          File('${dir.path}/.grid/critique/$rubric.json')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              jsonEncode({
                'rubric': rubric,
                'version': 1,
                'grade': 'A',
                'rationale': 'the specification is complete',
                'nodePath': lane.args.nodePath,
                kVerdictRoundKey: 2,
              }),
            );
          final result = await const SpecCriticCapability().result(
            lane.context,
            lane.args,
          );
          expect(result![kVerdictRoundKey], '2', reason: rubric);
          final artifact =
              jsonDecode(
                    File(
                      '${dir.path}/.grid/critique/$rubric.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>;
          expect(artifact[kVerdictRoundKey], 2, reason: rubric);
        }
      },
    );

    test('a whole spec grades A', () async {
      final c = _laneCtx(rubric: kSpecGatingRubric);
      final out = await const SpecValidationCapability().run(c.context, c.args);
      expect(out, isA<Ok>());
      expect((out as Ok).payload, {
        'grade': 'A',
        'transport': 'structural',
        'round': '0',
      });
    });

    test(
      'a fresh carried spec grades A over a stale incomplete ambient bead',
      () async {
        final ambient = bead('tg-1');
        final c = _laneCtx(
          rubric: kSpecGatingRubric,
          beadOverride: ambient,
          specifyResult: const {
            kCarriedSpecAcceptanceKey: kSpecExemplarAcceptance,
            kCarriedSpecDesignKey: kSpecExemplarDesign,
          },
        );
        final out = await const SpecValidationCapability().run(
          c.context,
          c.args,
        );
        expect((out as Ok).payload, {
          'grade': 'A',
          'transport': 'structural',
          kVerdictRoundKey: '0',
        });
        expect(specStructuralFindings(ambient), isNotEmpty);
      },
    );

    for (final specifyResult in <Map<String, String>?>[null, const {}]) {
      test(
        'an absent/empty carried result validates the whole ambient bead',
        () async {
          final c = _laneCtx(
            rubric: kSpecGatingRubric,
            specifyResult: specifyResult,
          );
          final out = await const SpecValidationCapability().run(
            c.context,
            c.args,
          );
          expect((out as Ok).payload!['grade'], 'A');
        },
      );

      test(
        'an absent/empty carried result fails an incomplete ambient bead',
        () async {
          final c = _laneCtx(
            rubric: kSpecGatingRubric,
            beadOverride: bead('tg-1'),
            specifyResult: specifyResult,
          );
          final out = await const SpecValidationCapability().run(
            c.context,
            c.args,
          );
          expect((out as Ok).payload!['grade'], 'F');
          expect(out.payload!['transport'], 'structural');
          expect(out.payload!['rationale'], isNotEmpty);
          expect(out.payload![kVerdictRoundKey], '0');
        },
      );
    }

    test('the pre-specify state (no spec at all) grades F with EVERY missing '
        'element named — specify can never be silently skipped', () async {
      final c = _laneCtx(rubric: kSpecGatingRubric, beadOverride: bead('tg-1'));
      final out = await const SpecValidationCapability().run(c.context, c.args);
      expect(out, isA<Ok>());
      final payload = (out as Ok).payload!;
      expect(payload['grade'], 'F');
      expect(payload['rationale'], contains('checkbox'));
      expect(payload['rationale'], contains('## Implementation Plan'));
      expect(payload['rationale'], contains('## Touches'));
      expect(payload['rationale'], contains('## ADR Alignment'));
      expect(payload['rationale'], contains('## Validation Plan'));
    });

    test('a missing ambient bead grades F (fail-closed)', () async {
      final out = await const SpecValidationCapability().run(
        FakeTreeContext(values: const {}),
        stepArgs(
          'tg-1/spec_review/spec-validation',
          params: const {'grid.round': '2'},
        ),
      );
      expect(((out as Ok).payload)!['grade'], 'F');
      expect(out.payload!['round'], '2');
    });

    group('specStructuralFindings — each defect is a named, LOUD finding', () {
      test('names blank and whitespace-only authored artifacts', () {
        final blank = _specced().copyWith(acceptanceCriteria: '', design: ' ');
        expect(specStructuralFindings(blank).take(2), [
          'acceptance: empty',
          'design: empty',
        ]);
      });

      test('empty on the whole spec', () {
        expect(specStructuralFindings(_specced()), isEmpty);
      });

      test('acceptance without checkboxes', () {
        final b = _specced().copyWith(
          acceptanceCriteria: 'works well and is fast',
        );
        expect(
          specStructuralFindings(b).single,
          contains('no testable `- [ ]` checkbox criteria'),
        );
      });

      test('a plan without numbered steps', () {
        final b = _specced().copyWith(
          design: _specced().design.replaceFirst('### Step 1 — Add', 'Add'),
        );
        expect(specStructuralFindings(b).single, contains('no numbered steps'));
      });

      test('a validation plan without items', () {
        final design = _specced().design;
        final b = _specced().copyWith(
          design:
              '${design.substring(0, design.indexOf('## Validation Plan'))}'
              '## Validation Plan\n',
        );
        expect(
          specStructuralFindings(b).single,
          contains('`## Validation Plan` has no items'),
        );
      });

      test('a prose MENTION is not a section — the REAL section further down '
          'is the one the gate reads (bead `pow-o3ti`)', () {
        final mentioning = _specced().copyWith(
          design:
              'The machine gate for this bead is the fast subset rather than '
              'the full house gate (see ## Validation Plan), and every step is '
              'ordinal-led (see ## Implementation Plan).\n'
              '\n'
              '${_specced().design}',
        );
        expect(specStructuralFindings(mentioning), isEmpty);
      });

      test(
        'a MENTION with no real `## Validation Plan` section blocks — the '
        'finding is unchanged, and today the mention SATISFIES the check',
        () {
          final mentionOnly = _specced().copyWith(
            design: _specced().design.replaceFirst(
              '\n## Validation Plan\n',
              '\nEvery criterion is mapped (see ## Validation Plan).\n',
            ),
          );
          expect(
            specStructuralFindings(mentionOnly).single,
            contains('no `## Validation Plan` section'),
          );
        },
      );

      test('a MENTION with no real `## Implementation Plan` section blocks — '
          'the finding is unchanged', () {
        final mentionOnly = _specced().copyWith(
          design: _specced().design.replaceFirst(
            '## Implementation Plan\n',
            'Every step is ordinal-led (see ## Implementation Plan).\n',
          ),
        );
        expect(
          specStructuralFindings(mentionOnly).single,
          contains('no `## Implementation Plan` section'),
        );
      });

      test('a MENTION of `## Touches` no longer satisfies the PRESENCE check '
          '— the two `contains` lookups move to the same resolver', () {
        final mentionOnly = _specced().copyWith(
          design: _specced().design.replaceFirst(
            '\n## Touches\n',
            '\nThe surfaces are enumerated under ## Touches in the epic.\n',
          ),
        );
        expect(
          specStructuralFindings(mentionOnly).single,
          contains('no `## Touches` section'),
        );
      });

      test('an UNTERMINATED fence quoting a heading ABOVE the real section '
          'does not displace it — the LAST line-anchored match wins', () {
        const ticks = '\x60\x60\x60';
        final quoting = _specced().copyWith(
          design: _specced().design.replaceFirst(
            'Commit: `feat(bus): add the peer heartbeat frame`\n',
            'Commit: `feat(bus): add the peer heartbeat frame`\n'
                '\n'
                'The exemplar this brief ships, quoted:\n'
                '${ticks}markdown\n'
                '## Validation Plan\n'
                'carrying no items\n'
                '\n',
          ),
        );
        expect(specStructuralFindings(quoting), isEmpty);
      });

      test('placeholder tokens anchor F — on word boundaries, so an '
          'identifier merely containing the letters never trips', () {
        final withTodo = _specced().copyWith(
          design: _specced().design.replaceFirst(
            'No recorded decision governs',
            'TODO: check the register. No recorded decision governs',
          ),
        );
        expect(
          specStructuralFindings(withTodo).single,
          contains('placeholder: "TODO"'),
        );

        // The exemplar's ids are KEPT: the mutation under test is the banned
        // PHRASE, not the record form, and a fixture that broke both would
        // prove neither.
        final withPhrase = _specced().copyWith(
          acceptanceCriteria: kSpecExemplarAcceptance.replaceFirst(
            'AC-1 — ',
            'AC-1 — add appropriate error handling to the wire; ',
          ),
        );
        expect(
          specStructuralFindings(withPhrase).single,
          contains('appropriate error handling'),
        );

        // "mastodon"/"autodial" must NOT trip the tbd/todo word tokens —
        // in the DESIGN field, which the fence actually scans (a notes-only
        // control would be vacuous: the fence never reads notes).
        final safe = _specced().copyWith(
          design:
              '${_specced().design}\n'
              'The mastodon bridge autodials the relay.\n',
        );
        expect(specStructuralFindings(safe), isEmpty);
      });

      test('quotation contexts never trip the fence — quoted code and cited '
          'clauses are evidence, not deferral (negative control)', () {
        // A fenced block carrying the very comment the plan deletes, inline
        // spans naming the token, and a blockquote citing a gate note that
        // uses the banned phrases verbatim.
        final quoting = _specced().copyWith(
          design:
              '${_specced().design}\n'
              'Delete the stale comment:\n'
              '```dart\n'
              '// TODO(tg-32r): migrate to the positional form — TBD.\n'
              '```\n'
              'Sweep the residue with `grep -rn TODO lib/` and remove every '
              'surviving `// TODO` hit.\n'
              '> Gate note, cited verbatim: rework the fence "as needed" and\n'
              '> add appropriate error handling around the loader.\n',
        );
        expect(specStructuralFindings(quoting), isEmpty);

        // Stripping must never SPLICE a phrase across the seam: the span in
        // as`retryPolicy`needed is replaced two-spaces-wide, so the banned
        // single-space "as needed" cannot be manufactured by the strip.
        final seam = _specced().copyWith(
          design:
              '${_specced().design}\n'
              'Frames retry as`retryPolicy`needed dictates.\n',
        );
        expect(specStructuralFindings(seam), isEmpty);

        // The SAME token in plain prose still parks — stripping quotation
        // never widens what the fence forgives.
        final deferring = quoting.copyWith(
          design: '${quoting.design}\nHandle malformed frames as needed.\n',
        );
        expect(
          specStructuralFindings(deferring).single,
          contains('placeholder: "as needed"'),
        );
      });

      // The three FENCE fixtures below vary ONE thing against the shipped
      // exemplar — the fence spliced beside a step's `Change:` — so a failure
      // can only ever be about the fence, never about the record grammar.
      Bead fenced(String id, String evidence) => bead(id).copyWith(
        acceptanceCriteria: kSpecExemplarAcceptance,
        design: kSpecExemplarDesign.replaceFirst(
          'Test: `cd packages/grid_assets',
          '$evidence\nTest: `cd packages/grid_assets',
        ),
      );

      test('a longer outer fence ignores shorter fenced blocks', () {
        const ticks = '\x60\x60\x60';
        expect(
          specStructuralFindings(
            fenced(
              'tg-long-fence',
              'Quoted whole, inner fence and all:\n'
                  '$ticks`markdown\n'
                  '${ticks}dart\n'
                  'final pulse = true;\n'
                  '$ticks`',
            ),
          ),
          isEmpty,
        );
      });

      test('an unterminated line fence leaves the document tail scannable', () {
        const ticks = '\x60\x60\x60';
        expect(
          specStructuralFindings(
            fenced(
              'tg-open-fence',
              'The diagnostic transcript, preserved:\n'
                  '${ticks}dart\n'
                  'final pulse = true;',
            ),
          ),
          isEmpty,
        );
      });

      test('inline triple backticks are not fence delimiters', () {
        const ticks = '\x60\x60\x60';
        expect(
          specStructuralFindings(
            fenced(
              'tg-inline-fence',
              'Validate with ruby -e \'s.include?("${ticks}dart")\'.',
            ),
          ),
          isEmpty,
        );
      });
    });

    group('the brief ↔ gate ROUND TRIP (`pow-77g`)', () {
      test('the exemplar the brief SHIPS passes the gate that grades it — the '
          'contract is one string, not two', () {
        final exemplar = bead('tg-1').copyWith(
          acceptanceCriteria: kSpecExemplarAcceptance,
          design: kSpecExemplarDesign,
        );
        expect(specStructuralFindings(exemplar), isEmpty);
      });

      test('an ORDERED-LIST plan still grades A — the record grammar lands on '
          'what a step CONTAINS, never on which openers count', () {
        // The exemplar now SHIPS the ordinal-HEADING shape (a step carrying a
        // fenced block has to take it), so this fence runs the other way: the
        // `1. …` list item stays a step, fields and all.
        final listed = _specced().copyWith(
          design: _specced().design.replaceFirst(
            '### Step 1 — Add the `Heartbeat` frame',
            '1. Add the `Heartbeat` frame',
          ),
        );
        expect(specStructuralFindings(listed), isEmpty);

        final bold = _specced().copyWith(
          design: _specced().design.replaceFirst(
            '### Step 1 — Add the `Heartbeat` frame',
            '**Step 1:** Add the `Heartbeat` frame',
          ),
        );
        expect(specStructuralFindings(bold), isEmpty);
      });

      test('a BULLETED plan still F\'s — the ordinal stays MANDATORY', () {
        final bulleted = _specced().copyWith(
          design: _specced().design.replaceFirst('### Step 1 — Add', '- Add'),
        );
        expect(
          specStructuralFindings(bulleted).single,
          contains('has no numbered steps'),
        );
      });

      test('an ordinal OUTSIDE the plan section no longer rescues a step-less '
          'plan — the check reads the `## Implementation Plan` body', () {
        final elsewhere = _specced().copyWith(
          design: _specced().design
              .replaceFirst('### Step 1 — Add', '- Add')
              .replaceFirst(
                '## Validation Plan\n',
                '## Validation Plan\n1. run the suite\n',
              ),
        );
        expect(
          specStructuralFindings(elsewhere).single,
          contains('has no numbered steps'),
        );
      });

      test(
        'a heading quoted inside a fenced block is evidence, not a section',
        () {
          final quotedOnly = _specced().copyWith(
            design: _specced().design.replaceFirst(
              '## Touches\n',
              '```markdown\n## Touches\n```\n',
            ),
          );
          expect(
            specStructuralFindings(quotedOnly).single,
            contains('no `## Touches` section'),
          );
        },
      );

      test('every banned token is DERIVED from one list: each trips the fence '
          'in prose, and the brief names all seven', () {
        final rendered = buildSpecifyBrief(
          _specced(),
          testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1'),
        ).render();
        for (final token in kSpecPlaceholderTokens) {
          final tripped = _specced().copyWith(
            design: '${_specced().design}\nThe loader handles $token.\n',
          );
          expect(
            specStructuralFindings(tripped).single,
            contains('placeholder:'),
            reason: '$token must trip the fence in prose',
          );
          expect(
            rendered,
            contains('`$token`'),
            reason:
                'the brief must NAME $token — a token the fence bans and '
                'the brief omits is a silent F',
          );
        }
      });
    });

    group('headingOffset — a heading is STRUCTURE, read at a line start', () {
      test('a mid-sentence mention is not a heading', () {
        expect(
          headingOffset(
            'see ## Validation Plan for the map\n',
            '## Validation Plan',
          ),
          -1,
        );
      });

      test('the LAST line-anchored heading wins', () {
        const doc = '## Touches\nfirst\n\n## Touches\nsecond\n';
        expect(headingOffset(doc, '## Touches'), doc.lastIndexOf('## Touches'));
      });

      test('a deeper level and trailing text still read as the heading — no '
          'stricter than the substring search it replaces', () {
        expect(
          headingOffset(
            '### Validation Plan (1:1)\n- [ ] x\n',
            '## Validation Plan',
          ),
          0,
        );
      });

      test('an absent heading answers -1 — the `indexOf` contract every call '
          'site keeps', () {
        expect(headingOffset('## Touches\nx\n', '## Validation Plan'), -1);
      });

      test('0-3 spaces still indent a heading; 4+ is an indented code block, '
          'i.e. quotation', () {
        expect(headingOffset('   ## Touches\n- x\n', '## Touches'), 0);
        expect(headingOffset('    ## Touches\n- x\n', '## Touches'), -1);
      });
    });
  });

  group('SpecCriticCapability — one spec rubric, in isolation', () {
    test('malformed verdict gets one structured re-ask', () {
      final dir = Directory.systemTemp.createTempSync('spec-critic-reask-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'coherence';
      final c = _laneCtx(rubric: rubric, workspaceDir: dir.path);
      final firstPrompt = const SpecCriticCapability()
          .spawn(c.context, c.args)
          .args
          .join(' ');
      expect(firstPrompt, isNot(contains('## Verdict contract repair')));
      File('${dir.path}/.grid/critique/$rubric.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      final prompt = const SpecCriticCapability()
          .spawn(c.context, c.args)
          .args
          .join(' ');
      expect(prompt, contains('## Verdict contract repair'));
      expect(prompt.split('## Verdict contract repair').length - 1, 1);
    });

    test('a D verdict naming NO owner is REFUSED (LOUD) — the spec family is '
        'held to the owner column (bead `pow-hxme`)', () async {
      final dir = Directory.systemTemp.createTempSync('spec-owner-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = SpecCriticCapability();
      final c = _laneCtx(rubric: 'coherence', workspaceDir: dir.path);
      final verdict = File('${dir.path}/.grid/critique/coherence.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'rubric': 'coherence',
            'version': 1,
            'grade': 'D',
            'rationale': 'the names collide with a sibling',
            'nodePath': 'tg-1/spec_review/coherence',
            'round': 0,
          }),
        );
      await expectLater(
        cap.result(c.context, c.args),
        throwsA(
          isA<RouteFailure>().having(
            (e) => e.reason,
            'reason',
            allOf(contains(kVerdictOwnerKey), contains('WHO can fix this')),
          ),
        ),
      );

      verdict.writeAsStringSync(
        jsonEncode({
          'rubric': 'coherence',
          'version': 1,
          'grade': 'B',
          'rationale': 'fine',
          kVerdictOwnerKey: 'nobody',
          'nodePath': 'tg-1/spec_review/coherence',
          'round': 0,
        }),
      );
      await expectLater(
        cap.result(c.context, c.args),
        throwsA(isA<RouteFailure>()),
      );

      verdict.writeAsStringSync(
        jsonEncode({
          'rubric': 'coherence',
          'version': 1,
          'grade': 'D',
          'rationale': 'whose names win?',
          kVerdictOwnerKey: kOwnerAuthor,
          'nodePath': 'tg-1/spec_review/coherence',
          'round': 0,
        }),
      );
      expect(
        (await cap.result(c.context, c.args))![kVerdictOwnerKey],
        kOwnerAuthor,
      );

      verdict.writeAsStringSync(
        jsonEncode({
          'rubric': 'coherence',
          'version': 1,
          'grade': 'D',
          'rationale': 'the names collide with a sibling',
          'nodePath': 'tg-1/spec_review/coherence',
          'round': 0,
        }),
      );
      expect(
        currentVerdictFromFile(
          workspaceDir: dir.path,
          rubric: 'coherence',
          nodePath: 'tg-1/spec_review/coherence',
          round: 0,
        ),
        isNotNull,
      );
    });

    test('spawn records THIS incarnation for the spec critic too — the '
        're-stamp proof spans all three critic families', () {
      final dir = Directory.systemTemp.createTempSync('spec-critic-mark-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const rubric = 'coherence';
      final c = _laneCtx(rubric: rubric, workspaceDir: dir.path);
      const SpecCriticCapability().spawn(c.context, c.args);
      expect(
        File(criticIncarnationPath(dir.path, rubric)).existsSync(),
        isTrue,
      );
    });

    test('spawns claude WRAPPED for usage capture, carrying only its own '
        'rubric (FT-2)', () {
      final c = _laneCtx(rubric: 'coherence');
      final cfg = const SpecCriticCapability().spawn(c.context, c.args);
      expect(cfg.command, 'sh');
      expect(cfg.args[0], '-c');
      expect(
        cfg.args[1],
        contains('.grid/telemetry/tg-1_spec_review_coherence.usage.json'),
      );
      expect(cfg.args, contains('claude'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
    });

    test('the prompt grades the SPEC (never a diff): spec framing, live-tree '
        'verification, no pinned-diff scope', () {
      final prompt = const SpecCriticCapability().buildSpecCriticPrompt(
        _specced(),
        'coherence',
        'tg-1/spec_review/coherence',
        '/w/tg-1',
        round: 0,
      );
      expect(prompt, contains('# Spec review — rubric: `coherence`'));
      expect(prompt, contains('NOT been built'));
      expect(prompt, contains('Verify against the live tree'));
      expect(prompt, contains(kDecisionLookupRule));
      for (final token in kLocalOnlyTokens) {
        expect(prompt, isNot(contains(token)));
      }
      expect(prompt, contains('the_grid#admission-authority-boundary'));
      expect(prompt, contains(kDecisionWriteRule));
      expect(
        prompt,
        contains(
          'appends an `A<n>` amendment to ADR-0000 has DEPARTED from that '
          'rule — say so under `decision-alignment`',
        ),
      );
      // The spec IS the bead's acceptance + design — both render.
      expect(prompt, contains(kSpecExemplarAcceptance));
      expect(prompt, contains('## Implementation Plan'));
      // NO pinned-diff scope — that is the CODE committee's instrument.
      expect(prompt, isNot(contains('pinned')));
      expect(prompt, isNot(contains(pinnedDiffPath('/w/tg-1'))));
    });

    test('the prompt carries the SAME verdict hardening as the code critics: '
        'nodePath + round freshness stamps, the ABSOLUTE canonical path, '
        'write-file last (tg-291 / gate-integrity #3+#4 / A15(5) alt-A)', () {
      final prompt = const SpecCriticCapability().buildSpecCriticPrompt(
        _specced(),
        'plan-completeness',
        'tg-1#r2/spec_review/plan-completeness',
        '/w/tg-1',
        round: 2,
      );
      expect(
        prompt,
        contains(
          '"nodePath":"tg-1#r2/spec_review/plan-completeness","round":2}',
        ),
      );
      expect(prompt, contains('byte-for-byte'));
      expect(prompt, contains('REQUIRED freshness stamps'));
      expect(prompt, contains('the lane fails and re-runs'));
      expect(prompt, contains('the unstamped grade is never recorded'));
      expect(prompt, contains('/w/tg-1/.grid/critique/plan-completeness.json'));
      expect(
        prompt.trim(),
        endsWith('never reuse one writer\'s temporary path in another writer.'),
      );
      expect(prompt, contains('mktemp "/w/tg-1/.grid/critique/'));
      expect(prompt, contains('mv -f -- "\$verdict_tmp"'));
    });

    test('anti-anchoring: the prompt names ONLY its own rubric, never the '
        'other lanes\'', () {
      final prompt = const SpecCriticCapability().buildSpecCriticPrompt(
        _specced(),
        'decision-alignment',
        'tg-1/spec_review/decision-alignment',
        '/w/tg-1',
        round: 0,
      );
      for (final other in kSpecCommitteeRubrics) {
        if (other == 'decision-alignment') continue;
        expect(
          prompt,
          isNot(contains('`$other`')),
          reason: 'the $other lane must not leak into this prompt',
        );
      }
    });

    test('result() inherits the code committee\'s transport stack: a fresh '
        'canonical verdict parses; a STALE nodePath stamp fail-closes to F '
        '(gate-integrity #3)', () async {
      final dir = Directory.systemTemp.createTempSync('spec-critic-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = SpecCriticCapability();
      final c = _laneCtx(rubric: 'coherence', workspaceDir: dir.path);

      // Fresh verdict (stamp matches this round's nodePath) ⇒ the file wins.
      final verdict = File('${dir.path}/.grid/critique/coherence.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'rubric': 'coherence',
            'version': 1,
            'grade': 'B',
            'rationale': 'scope carved cleanly',
            'nodePath': 'tg-1/spec_review/coherence',
            'round': 0,
          }),
        );
      expect(await cap.result(c.context, c.args), {
        'grade': 'B',
        'transport': 'file',
        'round': '0',
        'rationale': 'scope carved cleanly',
      });

      // A STALE stamp (a prior round's file) is rejected ⇒ fail-closed F.
      verdict.writeAsStringSync(
        jsonEncode({
          'rubric': 'coherence',
          'version': 1,
          'grade': 'A',
          'rationale': 'the prior result is stale',
          'nodePath': 'tg-1#r1/spec_review/coherence',
          'round': 0,
        }),
      );
      expect(
        await cap.probeCompletionArtifact(c.context, c.args),
        GateOutcome.present,
      );
    });

    test('an unstamped parseable spec-critic verdict fails the lane, while a '
        'fresh stamped verdict still parses', () async {
      final dir = Directory.systemTemp.createTempSync('spec-critic-unstamped-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/spec_review/coherence';
      final verdict = File('${dir.path}/.grid/critique/coherence.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'rubric': 'coherence',
            'version': 1,
            'grade': 'C',
            'rationale': 'scope is close but the sibling carve-out is thin',
          }),
        );
      final c = _laneCtx(
        rubric: 'coherence',
        workspaceDir: dir.path,
        nodePath: nodePath,
      );
      await expectLater(
        const SpecCriticCapability().result(c.context, c.args),
        throwsA(
          isA<RouteFailure>()
              .having(
                (e) => e.reason,
                'reason',
                'invalid critic verdict at ${verdict.path}: nodePath must be '
                    'a non-empty string',
              )
              .having(
                (e) => e.toString(),
                'toString',
                'invalid critic verdict at ${verdict.path}: nodePath must be '
                    'a non-empty string',
              ),
        ),
      );

      verdict.writeAsStringSync(
        jsonEncode({
          'rubric': 'coherence',
          'version': 1,
          'grade': 'B',
          'rationale': 'scope carved cleanly',
          'nodePath': nodePath,
          'round': 0,
        }),
      );
      expect(await const SpecCriticCapability().result(c.context, c.args), {
        'grade': 'B',
        'transport': 'file',
        'round': '0',
        'rationale': 'scope carved cleanly',
      });
    });

    test('A15(5) alt-A: a stale round-0 verdict surviving into round 1 is '
        'REJECTED even though the critique wipe NEVER RAN — the wipe is a '
        'BELT, the round stamp is the guarantee', () async {
      final dir = Directory.systemTemp.createTempSync('spec-critic-round-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/spec_review/coherence';
      // Round 0's verdict, left on disk: ClearCritiqueCapability is NEVER
      // invoked in this test. Under a Rewind the nodePath is BYTE-IDENTICAL, so
      // A4's stamp still MATCHES — only the round stamp can tell them apart.
      File('${dir.path}/.grid/critique/coherence.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'rubric': 'coherence',
            'version': 1,
            'grade': 'A',
            'rationale': 'round 0 said the spec was clean',
            'nodePath': nodePath,
            'round': 0,
          }),
        );
      final c = _laneCtx(
        rubric: 'coherence',
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1, // the route moved the LEDGER: this is the RESPEC round.
      );
      expect(
        await const SpecCriticCapability().probeCompletionArtifact(
          c.context,
          c.args,
        ),
        GateOutcome.present,
      );
    });

    test('the SAME file stamped with the CURRENT round parses (the fence is '
        'positive verification, not blanket rejection)', () async {
      final dir = Directory.systemTemp.createTempSync('spec-critic-round-ok-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/spec_review/coherence';
      File('${dir.path}/.grid/critique/coherence.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'grade': 'B',
            'rationale': 'the respec landed',
            'nodePath': nodePath,
            'round': 1,
          }),
        );
      final c = _laneCtx(
        rubric: 'coherence',
        workspaceDir: dir.path,
        nodePath: nodePath,
        round: 1,
      );
      expect(await const SpecCriticCapability().result(c.context, c.args), {
        'grade': 'B',
        'transport': 'file',
        'round': '1',
        'rationale': 'the respec landed',
      });
    });
  });

  group('the route matrix over the spec param set', () {
    Map<String, String> allA() => {
      for (final id in _specCritics.split(',')) id: 'A',
    };

    test('all pass ⇒ Ok(advance) with the spec grade vector (FT-2)', () async {
      final out = await _specRoute(allA());
      expect(out, isA<Advance>());
      expect((out as Advance).payload!['verdict'], 'advance');
      expect(
        out.payload!['grades'],
        'spec-validation=A,coherence=A,decision-alignment=A,'
        'acceptance-testability=A,plan-completeness=A',
      );
    });

    test('the gating spec-validation at F ⇒ Gate, and the reason NAMES the '
        'gating lane (this route serves both committees)', () async {
      final out = await _specRoute({...allA(), kSpecGatingRubric: 'F'});
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('spec-validation'));
      expect(out.reason, contains('hard block'));
    });

    test('an LLM spec lane at E WITH a rationale ⇒ an ADVANCE carrying the '
        'invalidating `grade: F` stamp — the loop actuates through the declared '
        '`validates` edge, with no human and no reported rewind', () async {
      final out = await _specRoute(
        {...allA(), 'plan-completeness': 'E'},
        rationales: const {'plan-completeness': 'step 3 names no test command'},
      );
      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['grade'], 'F');
      expect(payload['verdict'], 'respec');
      expect(payload['rationale'], contains('plan-completeness=E'));
    });

    test('an LLM spec lane at D with NO rationale ⇒ a HUMAN gate — nothing to '
        'respec against, so never a respec stamp', () async {
      final out = await _specRoute({...allA(), 'plan-completeness': 'D'});
      expect(out, isA<Escalate>());
      expect((out as Escalate).reason, contains('NO rationale'));
    });

    test('a missing spec grade fail-closes (never advances)', () async {
      final grades = allA()..remove('decision-alignment');
      final out = await _specRoute(grades);
      expect(out, isA<Escalate>());
    });
  });
}

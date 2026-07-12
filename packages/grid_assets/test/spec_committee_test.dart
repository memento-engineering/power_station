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
    'spec-validation,coherence,adr-alignment,acceptance-testability,'
    'plan-completeness';

/// A bead carrying a structurally WHOLE spec (every section, no placeholders).
Bead _specced() => bead('tg-1').copyWith(
  title: 'Wire the federation bus',
  acceptanceCriteria:
      '- [ ] A peer heartbeat surfaces within 1s\n'
      '- [ ] A malformed frame is refused loudly',
  design: '''
## Implementation Plan
1. Add `Heartbeat` — `lib/src/heartbeat.dart`
   ```dart
   class Heartbeat {
     const Heartbeat(this.peerId);
     final String peerId;
   }
   ```
   Test: `dart test test/heartbeat_test.dart` → expect PASS
   Commit: `feat(bus): add the peer heartbeat`

## Touches
**Files:**
- `lib/src/heartbeat.dart` — created

## ADR Alignment
No ADR applies — verified via grep on `heartbeat`, `bus`.

## Validation Plan
- [ ] A peer heartbeat surfaces within 1s → `dart test test/heartbeat_test.dart` → PASS
- [ ] A malformed frame is refused loudly → `dart test test/wire_test.dart` → PASS
''',
);

({FakeTreeContext context, StepArgs args}) _laneCtx({
  required String rubric,
  Bead? beadOverride,
  String workspaceDir = '/w/tg-1',
  String? nodePath,
}) => (
  context: FakeTreeContext(
    values: {
      Bead: beadOverride ?? _specced(),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
    },
  ),
  args: stepArgs(
    nodePath ?? 'tg-1/spec_review/$rubric',
    params: {'rubric': rubric},
  ),
);

/// Runs the SPEC route (bead `pow-7nm` — the three-way matrix) over the
/// fabricated [grades], with [rationales] where a critic returned one. No
/// ambient `Workspace` ⇒ the offline posture (no ledger I/O; the round counter
/// reads 0).
Future<StepOutcome> _specRoute(
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
  return const SpecRouteCapability().run(
    context,
    stepArgs(
      '$parent/route',
      params: const {'critics': _specCritics, 'gating': kSpecGatingRubric},
    ),
  );
}

void main() {
  group('kSpecReviewCircuit — the shape', () {
    test('hygiene → gating lane + four isolated spec critics → route; the '
        'route is the terminal', () {
      expect(kSpecReviewCircuit.id, 'spec_review');
      expect(kSpecReviewCircuit.terminalStepId, 'route');
      final byId = {
        for (final s in kSpecReviewCircuit.steps) s.stepId: s,
      };
      expect(byId.keys, {
        kClearCritiqueStep,
        kSpecGatingRubric,
        ...kSpecLlmRubrics,
        'route',
      });
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
      // The route joins on ALL five lanes and names the gating lane.
      final route = byId['route']! as CapabilityStep;
      expect(route.dependsOn, {kSpecGatingRubric, ...kSpecLlmRubrics});
      expect(route.params['gating'], kSpecGatingRubric);
      expect(route.params['critics'], _specCritics);
    });

    test('no pin-diff lane: the review subject is the bead\'s spec, not a '
        'code delta', () {
      expect(
        kSpecReviewCircuit.steps.map((s) => s.stepId),
        isNot(contains(kPinDiffStep)),
      );
    });

    test('the code circuit sequences specify → spec_review → agent: only a '
        'passing spec proceeds to build', () {
      final byId = {for (final s in kCodeCircuit.steps) s.stepId: s};
      expect(
        byId.keys.toList(),
        ['specify', 'spec_review', 'agent', 'review', 'land'],
      );
      expect(byId['spec_review']!.dependsOn, {'specify'});
      expect(byId['agent']!.dependsOn, {'spec_review'});
      expect((byId['spec_review']! as SubCircuitStep).circuitId, 'spec_review');
    });
  });

  group('SpecValidationCapability — the deterministic structural gate', () {
    test('a whole spec grades A', () async {
      final c = _laneCtx(rubric: kSpecGatingRubric);
      final out = await const SpecValidationCapability().run(c.context, c.args);
      expect(out, isA<Ok>());
      expect((out as Ok).payload, {'grade': 'A', 'transport': 'structural'});
    });

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
        stepArgs('tg-1/spec_review/spec-validation'),
      );
      expect(((out as Ok).payload)!['grade'], 'F');
    });

    group('specStructuralFindings — each defect is a named, LOUD finding', () {
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
          design: _specced().design.replaceFirst('1. Add', 'Add'),
        );
        expect(
          specStructuralFindings(b).single,
          contains('no numbered steps'),
        );
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

      test('placeholder tokens anchor F — on word boundaries, so an '
          'identifier merely containing the letters never trips', () {
        final withTodo = _specced().copyWith(
          design: _specced().design.replaceFirst(
            'No ADR applies',
            'TODO: check ADRs. No ADR applies',
          ),
        );
        expect(
          specStructuralFindings(withTodo).single,
          contains('placeholder: "TODO"'),
        );

        final withPhrase = _specced().copyWith(
          acceptanceCriteria:
              '- [ ] add appropriate error handling to the wire',
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

      test(
          'quotation contexts never trip the fence — quoted code and cited '
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
    });
  });

  group('SpecCriticCapability — one spec rubric, in isolation', () {
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
      );
      expect(prompt, contains('# Spec review — rubric: `coherence`'));
      expect(prompt, contains('NOT been built'));
      expect(prompt, contains('Verify against the live tree'));
      expect(prompt, contains('docs/adr/'));
      // The spec IS the bead's acceptance + design — both render.
      expect(prompt, contains('- [ ] A peer heartbeat surfaces within 1s'));
      expect(prompt, contains('## Implementation Plan'));
      // NO pinned-diff scope — that is the CODE committee's instrument.
      expect(prompt, isNot(contains('pinned')));
      expect(prompt, isNot(contains(pinnedDiffPath('/w/tg-1'))));
    });

    test('the prompt carries the SAME verdict hardening as the code critics: '
        'nodePath freshness stamp + the ABSOLUTE canonical path, write-file '
        'last (tg-291 / gate-integrity #3+#4)', () {
      final prompt = const SpecCriticCapability().buildSpecCriticPrompt(
        _specced(),
        'plan-completeness',
        'tg-1#r2/spec_review/plan-completeness',
        '/w/tg-1',
      );
      expect(prompt, contains('"nodePath":"tg-1#r2/spec_review/plan-completeness"'));
      expect(prompt, contains('byte-for-byte'));
      expect(
        prompt,
        contains('/w/tg-1/.grid/critique/plan-completeness.json'),
      );
      expect(prompt.trim(), endsWith('.grid/critique/plan-completeness.json`.'));
    });

    test('anti-anchoring: the prompt names ONLY its own rubric, never the '
        'other lanes\'', () {
      final prompt = const SpecCriticCapability().buildSpecCriticPrompt(
        _specced(),
        'adr-alignment',
        'tg-1/spec_review/adr-alignment',
        '/w/tg-1',
      );
      for (final other in kSpecCommitteeRubrics) {
        if (other == 'adr-alignment') continue;
        expect(prompt, isNot(contains('`$other`')),
            reason: 'the $other lane must not leak into this prompt');
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
        ..writeAsStringSync(jsonEncode({
          'rubric': 'coherence',
          'version': 1,
          'grade': 'B',
          'rationale': 'scope carved cleanly',
          'nodePath': 'tg-1/spec_review/coherence',
        }));
      expect(await cap.result(c.context, c.args), {
        'grade': 'B',
        'transport': 'file',
        'rationale': 'scope carved cleanly',
      });

      // A STALE stamp (a prior round's file) is rejected ⇒ fail-closed F.
      verdict.writeAsStringSync(jsonEncode({
        'rubric': 'coherence',
        'version': 1,
        'grade': 'A',
        'nodePath': 'tg-1#r1/spec_review/coherence',
      }));
      final graded = await cap.result(c.context, c.args);
      expect(graded!['grade'], 'F');
      expect(graded['transport'], 'fail-closed-default');
    });
  });

  group('the route matrix over the spec param set', () {
    Map<String, String> allA() => {
      for (final id in _specCritics.split(',')) id: 'A',
    };

    test('all pass ⇒ Ok(advance) with the spec grade vector (FT-2)', () async {
      final out = await _specRoute(allA());
      expect(out, isA<Ok>());
      expect((out as Ok).payload!['verdict'], 'advance');
      expect(
        out.payload!['grades'],
        'spec-validation=A,coherence=A,adr-alignment=A,'
        'acceptance-testability=A,plan-completeness=A',
      );
    });

    test('the gating spec-validation at F ⇒ Gate, and the reason NAMES the '
        'gating lane (this route serves both committees)', () async {
      final out = await _specRoute({...allA(), kSpecGatingRubric: 'F'});
      expect(out, isA<Gate>());
      expect((out as Gate).reason, contains('spec-validation'));
      expect(out.reason, contains('hard block'));
    });

    test('an LLM spec lane at D WITH a rationale ⇒ an AUTO-RESPEC gate (bead '
        '`pow-7nm`) — machine-actionable, never a human ultimatum', () async {
      final out = await _specRoute(
        {...allA(), 'plan-completeness': 'D'},
        rationales: const {'plan-completeness': 'step 3 names no test command'},
      );
      expect(out, isA<Gate>());
      expect((out as Gate).reason, startsWith(kRespecGatePrefix));
      expect(out.reason, contains('step 3 names no test command'));
    });

    test('an LLM spec lane at D with NO rationale ⇒ a HUMAN gate — nothing to '
        'respec against', () async {
      final out = await _specRoute({...allA(), 'plan-completeness': 'D'});
      expect(out, isA<Gate>());
      expect((out as Gate).reason, isNot(startsWith(kRespecGatePrefix)));
      expect(out.reason, contains('NO rationale'));
    });

    test('a missing spec grade fail-closes (never advances)', () async {
      final grades = allA()..remove('adr-alignment');
      final out = await _specRoute(grades);
      expect(out, isA<Gate>());
    });
  });
}

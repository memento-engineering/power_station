// The CROSS-REPO decision lane.
//
// The failure this fences: a bead carried a file-watcher approach through a
// PASSING decision grade while contradicting the_grid's recorded `a50` ("The
// trigger is explicit only … an in-process filesystem watcher … [was]
// rejected"), because the lane only ever read the LOCAL register.
// Offline only — renders prompts, runs no station and no index.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// The space-my4 shape: a spec that adds a file-system watcher under
/// `packages/grid/`, the surface the fixture roster's
/// `policy_repo#no-file-watching` governs.
const String kContradictingDesign = '''
## Implementation Plan

### Step 1 — Watch the source tree

Add a `Directory.watch` loop that reloads the station on every save.

## Touches
- `packages/grid/lib/src/watcher.dart` — created;
  `packages/grid/lib/src/watcher.dart:StationWatcher`
- `packages/grid/lib/src/watcher.dart` — the duplicate collapses

## ADR Alignment
No ADR applies.

## Validation Plan
- [ ] the watcher reloads on save
''';

/// The no-precedent companion: one ungoverned surface, no `/` in the token.
const String kUngovernedDesign = '''
## Implementation Plan

### Step 1 — Document the pack

Rewrite the pack table.

## Touches
- `README.md` — rewritten; `Heartbeat` is untouched

## ADR Alignment
No recorded decision governs these surfaces.

## Validation Plan
- [ ] the table lists every pack
''';

/// Built from `bead()` (`package:grid_engine/testing.dart`, the helper every
/// sibling suite uses) so the fixture stays one `copyWith` from the real shape.
Bead _fixture(String design) => bead('pow-fixture').copyWith(
  title: 'reload the station on save',
  design: design,
  acceptanceCriteria: '- [ ] the station reloads on save',
  metadata: const <String, dynamic>{'rig': 'power_station'},
);

/// The lane prompt as the STATION composes it — the packaged loader is the
/// injected [RubricSource] (D-9), so the prompt carries the vendored rubric's
/// own prose, not the no-assets placeholder.
String _lanePrompt(Bead bead) =>
    SpecCriticCapability(rubrics: PackagedAssetLoader().rubricSource)
        .buildSpecCriticPrompt(
          bead,
          'decision-alignment',
          'pow-fixture/spec_review/decision-alignment',
          '/w/pow-fixture',
          round: 0,
        );

void main() {
  group('rosterQualifiedSurfaces reads the spec\'s OWN Touches section', () {
    test('strips a trailing symbol, skips non-paths, dedupes, prefixes the '
        'substation', () {
      expect(
        rosterQualifiedSurfaces(
          design: kContradictingDesign,
          substation: 'power_station',
        ),
        ['power_station/packages/grid/lib/src/watcher.dart'],
      );
    });

    test('a bare filename with no slash still qualifies', () {
      expect(
        rosterQualifiedSurfaces(
          design: kUngovernedDesign,
          substation: 'power_station',
        ),
        ['power_station/README.md'],
      );
    });

    test('an unknown substation falls back to the literal placeholder', () {
      expect(
        rosterQualifiedSurfaces(design: kUngovernedDesign, substation: '  '),
        ['$kUnknownSubstationPrefix/README.md'],
      );
    });

    test('a spec with no Touches section yields nothing, and the block still '
        'names the verb', () {
      expect(
        rosterQualifiedSurfaces(
          design: '## Implementation Plan',
          substation: 'x',
        ),
        isEmpty,
      );
      expect(
        rosterDecisionLookupBlock(const []),
        'space decisions index --surface <repo>/<path>',
      );
    });
  });

  group('the lookup is ROSTER MODE', () {
    test('no register-directory argument is ever rendered', () {
      expect(rosterDecisionIndexCommand(), 'space decisions index');
      expect(
        rosterDecisionIndexCommand(surface: 'the_grid/lib/a.dart'),
        'space decisions index --surface the_grid/lib/a.dart',
      );
      expect(rosterDecisionIndexCommand(), isNot(contains('docs/')));
    });

    test('the rule names the union, the sibling force, the citation identity, '
        'the empty union and the CRASHED lookup', () {
      expect(kDecisionLookupRule, contains('UNION'));
      expect(kDecisionLookupRule, contains('LOAD-BEARING'));
      expect(kDecisionLookupRule, contains('originRegister'));
      expect(kDecisionLookupRule, contains('<repo>#<slug>'));
      expect(kDecisionLookupRule, contains('register.legacy-id'));
      expect(kDecisionLookupRule, contains('real result, not an error'));
      expect(
        kDecisionLookupRule,
        contains('never grade a crashed index clean'),
      );
      for (final token in kLocalOnlyTokens) {
        expect(kDecisionLookupRule, isNot(contains(token)));
      }
    });
  });

  group('THE FIXTURE — a spec contradicting a SIBLING register', () {
    test('the lane prompt renders the roster-qualified query for the touched '
        'surface', () {
      final prompt = _lanePrompt(_fixture(kContradictingDesign));
      expect(
        prompt,
        contains(
          'space decisions index --surface '
          'power_station/packages/grid/lib/src/watcher.dart',
        ),
      );
      expect(prompt, contains('# Spec review — rubric: `decision-alignment`'));
    });

    test('the lane prompt carries NO local-only register read (this fails if '
        'the lane is reverted)', () {
      final prompt = _lanePrompt(_fixture(kContradictingDesign));
      for (final token in kLocalOnlyTokens) {
        expect(prompt, isNot(contains(token)), reason: token);
      }
    });

    test('the rubric it carries gives a SIBLING register equal force and '
        'calibrates on the cross-register file-watcher contradiction', () {
      final prompt = _lanePrompt(_fixture(kContradictingDesign));
      expect(
        prompt,
        contains('a sibling register has exactly the same force as the'),
      );
      expect(prompt, contains('policy_repo#no-file-watching'));
    });

    test('the ungoverned companion still gets its surface queried — an empty '
        'union is not an error', () {
      final prompt = _lanePrompt(_fixture(kUngovernedDesign));
      expect(
        prompt,
        contains('space decisions index --surface power_station/README.md'),
      );
      expect(prompt, contains('real result, not an error'));
    });
  });

  group('the composed lane is the roster-aware one', () {
    test('the circuit and the rubric list name decision-alignment', () {
      expect(kSpecLlmRubrics, contains('decision-alignment'));
      expect(kSpecLlmRubrics, isNot(contains('adr-alignment')));
      expect(kSpecCommitteeRubrics, contains('decision-alignment'));
      final lane = kSpecReviewCircuit.steps
          .whereType<CapabilityStep>()
          .firstWhere((step) => step.stepId == 'decision-alignment');
      expect(lane.params['rubric'], 'decision-alignment');
      final route = kSpecReviewCircuit.steps
          .whereType<CapabilityStep>()
          .firstWhere((step) => step.stepId == 'route');
      expect(route.params['critics'], contains('decision-alignment'));
      expect(route.params['critics'], isNot(contains('adr-alignment')));
      expect(route.dependsOn, contains('decision-alignment'));
    });

    test('PackagedAssetLoader resolves the vendored rubric', () {
      expect(
        PackagedAssetLoader().loadRubric('decision-alignment'),
        contains('# decision-alignment'),
      );
    });
  });
}

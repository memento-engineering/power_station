// The CROSS-REPO decision lane.
//
// The failure this fences: a bead carried a file-watcher approach through a
// PASSING decision grade while contradicting the_grid's recorded `a50` ("The
// trigger is explicit only … an in-process filesystem watcher … [was]
// rejected"), because the lane only ever read the LOCAL register.
// Offline only — renders prompts, runs no station and no index.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:genesis_tree/genesis_tree.dart';
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

/// The lane's own step, as the spec circuit declares it.
const CapabilityStep _laneStep = CapabilityStep(
  stepId: 'decision-alignment',
  capabilityId: 'spec-critic',
  params: {'rubric': 'decision-alignment'},
);

const Circuit _laneCircuit = Circuit(
  id: 'spec_review',
  terminalStepId: 'decision-alignment',
  steps: [_laneStep],
);

StepMount _laneMount() => StepMount(
  step: _laneStep,
  nodePath: 'pow-fixture/spec_review/decision-alignment',
  circuit: _laneCircuit,
  circuitPath: 'pow-fixture/spec_review',
  session: const SessionHandle('pow-fixture-session'),
  node: const NodeCursor(),
  key: const ValueKey('pow-fixture/spec_review/decision-alignment#0.0'),
);

/// The lane capability as the STATION composes it — resolved out of the REAL
/// `code` registry, so the prompt carries the vendored rubric's own prose (the
/// registry's bound [RubricSource], D-9) and the station verb the registry
/// derived from [overlayArgs], never a hand-wired pair the wire never uses.
SpecCriticCapability _composedLane({
  Map<String, String> overlayArgs = const {},
}) {
  final host =
      buildCodeRegistry(
            overlayArgs: overlayArgs,
            overlaySourceRef: 'test',
          ).host(_laneMount())
          as CapabilityHost;
  return host.capability as SpecCriticCapability;
}

/// The composing station's grid home — the cwd its verb resolves from, and
/// NOT the lane's worktree (`/w/pow-fixture`).
const String _lunarHome = '/grid/lunar';

/// The bound composition every "the lookup is runnable" probe uses: a
/// downstream station's own verb, plus the home that verb resolves from.
const Map<String, String> _lunarArgs = {
  'runner': 'dart run lunar:lunar',
  'gridHome': _lunarHome,
};

String _lanePrompt(Bead bead, {Map<String, String> overlayArgs = const {}}) =>
    _composedLane(overlayArgs: overlayArgs).buildSpecCriticPrompt(
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
        rosterDecisionLookupBlock(const [], gridHome: _lunarHome),
        "cd '$_lunarHome' && space decisions index --surface <repo>/<path>",
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
      expect(
        rosterDecisionIndexCommand(
          surface: 'the_grid/lib/a.dart',
          gridHome: _lunarHome,
        ),
        isNot(contains('docs/')),
      );
    });

    test('the BOUND rule names the union, the sibling force, the citation '
        'identity, the empty union and the CRASHED lookup', () {
      final rule = decisionLookupRule(gridHome: _lunarHome);
      expect(rule, contains('UNION'));
      expect(rule, contains('LOAD-BEARING'));
      expect(rule, contains('originRegister'));
      expect(rule, contains('<repo>#<slug>'));
      expect(rule, contains('register.legacy-id'));
      expect(rule, contains('real result, not an error'));
      expect(rule, contains('never grade a crashed index clean'));
      for (final token in kLocalOnlyTokens) {
        expect(rule, isNot(contains(token)));
      }
    });

    test('the UNBOUND rule — the exported default — keeps every FORCE clause '
        'while naming no command', () {
      expect(kDecisionLookupRule, contains('UNION'));
      expect(kDecisionLookupRule, contains('LOAD-BEARING'));
      expect(kDecisionLookupRule, contains('<repo>#<slug>'));
      expect(kDecisionLookupRule, contains('register.legacy-id'));
      expect(kDecisionLookupRule, contains('real result, not an error'));
      expect(kDecisionLookupRule, contains('EVERY mounted register'));
      expect(kDecisionLookupRule, isNot(contains('decisions index --surface')));
      for (final token in kLocalOnlyTokens) {
        expect(kDecisionLookupRule, isNot(contains(token)));
      }
    });
  });

  group('THE FIXTURE — a spec contradicting a SIBLING register', () {
    test('the lane prompt renders the roster-qualified query for the touched '
        'surface', () {
      final prompt = _lanePrompt(
        _fixture(kContradictingDesign),
        overlayArgs: _lunarArgs,
      );
      expect(
        prompt,
        contains(
          "cd '$_lunarHome' && dart run lunar:lunar decisions index --surface "
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
      final prompt = _lanePrompt(
        _fixture(kUngovernedDesign),
        overlayArgs: _lunarArgs,
      );
      expect(
        prompt,
        contains(
          "cd '$_lunarHome' && dart run lunar:lunar decisions index "
          '--surface power_station/README.md',
        ),
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

  // The DEAD-COMMAND defect: every rendered decision surface named `space`,
  // the FIRST-PARTY station's verb, on every station. A downstream station
  // (lunar, whose verb is `dart run lunar:lunar`) was handed a lookup that
  // exits 127, so its critics hand-read whole registers instead.
  //
  // Its second half (this bead): even the RIGHT verb dies from the wrong cwd.
  // `dart run lunar:lunar decisions index …`, run from the lane's own
  // worktree, exits 255 `Could not find package lunar` — the live receipt from
  // three decision-alignment rounds — so the lane fell back to a local
  // register grep and never read a sibling substation's register at all.
  group('the station\'s own verb reaches every rendered decision surface', () {
    test('a multi-token runner and its GRID HOME bind the generated lookup', () {
      final prompt = _lanePrompt(
        _fixture(kContradictingDesign),
        overlayArgs: _lunarArgs,
      );
      final qualified =
          "cd '$_lunarHome' && dart run lunar:lunar decisions index --surface";
      expect(
        RegExp(RegExp.escape(qualified)).allMatches(prompt).length,
        2,
        reason:
            'the read rule\'s template line AND the generated lookup '
            'block, both cwd-qualified',
      );
      expect(prompt, isNot(contains('space ')));
      expect(prompt, isNot(contains('{{runner}}')));
      // EVERY lunar invocation is part of that qualified command — a bare one
      // is the defect, and it survives a `contains` assertion.
      expect(
        prompt.replaceAll(qualified, '').contains('lunar:lunar decisions'),
        isFalse,
      );
    });

    test('the rubric bands defer to the prompt rather than minting a second '
        'command', () {
      final bands = PackagedAssetLoader().loadRubric('decision-alignment');
      expect(bands, isNot(contains('{{runner}}')));
      expect(bands, isNot(contains('decisions index --surface')));
      expect(bands, isNot(contains('space decisions index')));
      expect(bands, contains('Run those lines EXACTLY as written'));
      expect(bands, contains('EVERY mounted register'));
    });

    test('unbound grid home renders manual roster guidance without a '
        'command', () {
      for (final home in [null, '', '   ']) {
        final overlayArgs = <String, String>{
          'runner': 'dart run lunar:lunar',
          if (home != null) 'gridHome': home,
        };
        final texts = <String, String>{
          'architect': buildSpecifyBrief(
            _fixture(kContradictingDesign),
            testWorkspace(
              'pow-fixture',
              workspaceDir: '/w/pow-fixture',
              branch: 'grid/pow-fixture',
            ),
            runner: 'dart run lunar:lunar',
            gridHome: home,
          ).render(),
          'decision-alignment': _lanePrompt(
            _fixture(kContradictingDesign),
            overlayArgs: overlayArgs,
          ),
          'readiness':
              ReadinessCriticCapability(
                decisionRunner: 'dart run lunar:lunar',
                decisionGridHome: home,
              ).buildReadinessPrompt(
                _fixture(kContradictingDesign),
                kReadinessRubric,
                'pow-fixture/spec_review/readiness',
                '/w/pow-fixture',
                round: 0,
              ),
        };
        for (final entry in texts.entries) {
          final why = '${entry.key} @ home=${home ?? 'null'}';
          // It SAYS the index is unavailable, and why.
          expect(
            entry.value,
            contains('composing grid home is bound'),
            reason: why,
          );
          // It names the fallback: every mounted register, on disk.
          expect(entry.value, contains('docs/decisions/'), reason: why);
          expect(entry.value, contains('EVERY mounted register'), reason: why);
          // And it names NO invocation — not the station's, not the
          // first-party default, not an empty shell fence.
          expect(
            entry.value,
            isNot(contains('decisions index --surface')),
            reason: why,
          );
          expect(
            entry.value,
            isNot(contains('lunar:lunar decisions index')),
            reason: why,
          );
          expect(
            entry.value,
            isNot(contains('space decisions index')),
            reason: why,
          );
          expect(entry.value, isNot(contains('```sh\n```')), reason: why);
        }
      }
    });
  });
}

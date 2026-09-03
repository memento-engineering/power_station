// The spec-readiness rubric pack (bead `pow-6ao`) — the ported pack's prose,
// homed in the Packaged-AI-Asset loader (D-9), CONTENT-REWRITTEN for the
// station/memento context.
//
// Proves: every spec rubric loads through the SAME RubricSource loader the
// code committee uses (non-empty, self-naming); the spec-critic prompt
// template renders with no leftover mustache holes; the manifest declares the
// five spec resources + the spec-critic prompt; and — the acceptance's
// grep-clean fence — the ported prose carries NO residue of its deprecated
// source context (no Go tooling, no gas-city/factory vocabulary, no foreign
// CLI or ADR paths): the rewrite is for Dart tooling, the substation's local
// decision registers, this committee's own machinery, and the station status
// model.
// Offline only — reads bundled files; no live anything.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// Resolves this package's `extension/` dir by walking up from the cwd (the
/// same walk the loader + track_d use).
String _extensionDir() {
  final candidates = <String>[
    'extension',
    p.join('packages', 'grid_assets', 'extension'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          Directory(p.join(probe.path, 'rubrics')).existsSync()) {
        return probe.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate packages/grid_assets/extension from '
    '${Directory.current.path}',
  );
}

/// This package's `lib/` — the sibling of [_extensionDir]'s result. The
/// positive-control fence greps BOTH source trees: the brief that teaches the
/// write rule is Dart, its portable mirrors are Markdown.
Directory _libDir() =>
    Directory(p.join(Directory(_extensionDir()).parent.path, 'lib'));

/// The residue fence: tokens from the pack's DEPRECATED source context that
/// must NOT survive the content rewrite. Each pattern names its concern.
final Map<String, RegExp> _forbiddenResidue = {
  'the source factory by name': RegExp('factoryskills', caseSensitive: false),
  'the gas-city runtime': RegExp('gascity|gas city', caseSensitive: false),
  'gc CLI vocabulary': RegExp(r'\bgc\b'),
  'the foreign fs CLI': RegExp(r'\bfs\b'),
  'factory worker nouns': RegExp('polecat|bitsmith', caseSensitive: false),
  'the Go language': RegExp(r'\bGo\b'),
  'Go source files': RegExp(r'\.go\b'),
  'Go tooling': RegExp(r'\bgo (test|build|vet)\b'),
  'Go package layout': RegExp('internal/'),
  'the foreign ADR home': RegExp('docs/adrs'),
  'the foreign rubric ADR': RegExp('ADR 0012'),
};

void main() {
  final root = _extensionDir();
  final loader = PackagedAssetLoader(root: root);

  group('the spec-readiness rubrics load through the SAME RubricSource', () {
    for (final rubricId in kSpecCommitteeRubrics) {
      test(
        'loadRubric("$rubricId") returns non-empty prose that names itself',
        () {
          final text = loader.loadRubric(rubricId);
          expect(text, isNotEmpty);
          expect(text, contains(rubricId));
        },
      );
    }

    test('the gating rubric names its hard-block contract', () {
      final text = loader.loadRubric(kSpecGatingRubric);
      expect(text, contains('GATING'));
      expect(text, contains('hard block'));
    });
  });

  group('the grep-clean fence — no residual source-context references', () {
    final files = <String, String>{
      for (final rubricId in kSpecCommitteeRubrics)
        'rubrics/$rubricId.md': loader.loadRubric(rubricId),
      'prompts/spec-critic.md': loader.loadPromptTemplate('spec-critic'),
      // The spec-readiness INTAKE lens (bead `pow-q7n`) — same pack, same fence.
      'rubrics/bead-readiness.md': loader.loadRubric(kReadinessRubric),
      'prompts/readiness.md': loader.loadPromptTemplate('readiness'),
      // The DISCOVERY explorer (`discovery.dart`) — same pack, same fence. It
      // carries NO rubric: a lens gathers and cites, it does not grade.
      'prompts/discovery.md': loader.loadPromptTemplate('discovery'),
    };

    for (final entry in files.entries) {
      test('${entry.key} is clean', () {
        for (final residue in _forbiddenResidue.entries) {
          final match = residue.value.firstMatch(entry.value);
          expect(
            match,
            isNull,
            reason:
                '${entry.key} carries ${residue.key} '
                '("${match?.group(0)}") — the port must be rewritten for the '
                'station context, never copied verbatim',
          );
        }
      });
    }

    test(
      'the fence is non-vacuous: it WOULD catch the verbatim source prose',
      () {
        const verbatim =
            'run go test ./internal/lint/ before fs convene '
            '(see factoryskills ADR 0012 in docs/adrs)';
        final tripped = _forbiddenResidue.values
            .where((pattern) => pattern.hasMatch(verbatim))
            .length;
        expect(tripped, greaterThanOrEqualTo(4));
      },
    );
  });

  group('the station-context rewrite is PRESENT (not just residue-free)', () {
    test('the judgement rubrics ground in Dart tooling + the house set', () {
      final all = kSpecLlmRubrics.map(loader.loadRubric).join('\n');
      expect(all, contains('dart test'));
      expect(all, contains('freezed'));
      expect(all, contains('Fakes'));
    });

    test('every judgement rubric DEFINES D/E ownership — the column the '
        'decoder enforces is stated to the critic it judges (A19)', () {
      for (final rubricId in kSpecLlmRubrics) {
        final text = loader.loadRubric(rubricId);
        expect(text, contains('## Ownership'), reason: rubricId);
        expect(text, contains('`$kOwnerArchitect`'), reason: rubricId);
        expect(text, contains('`$kOwnerAuthor`'), reason: rubricId);
      }
      expect(
        loader.loadRubric(kSpecGatingRubric),
        isNot(contains('## Ownership')),
        reason: 'the deterministic gate grades A or F and owns no fixable D',
      );
    });

    test('decision-alignment names the ROSTER union, not a local register', () {
      final text = loader.loadRubric('decision-alignment');
      expect(text, contains('decisions index'));
      expect(text, contains('originRegister'));
      expect(text, contains('<repo>#<slug>'));
      expect(text, isNot(contains('docs/adr')));
    });

    test('coherence speaks memento terminology (the seam word is extension) '
        'and names THIS committee\'s own machinery as its duplication '
        'examples', () {
      final text = loader.loadRubric('coherence');
      expect(text, contains('**extension**'));
      expect(
        text.contains(RegExp(r'never\s+"plugin"')),
        isTrue,
        reason:
            'the terminology rule rides the rubric (naming the banned '
            'word to ban it)',
      );
      expect(text, contains('PackagedAssetLoader'));
      expect(text, contains('bd dep list'));
    });

    test(
      'spec-validation names the station status model\'s gate (`gated`)',
      () {
        expect(loader.loadRubric(kSpecGatingRubric), contains('gated'));
      },
    );
  });

  group('renderSpecCriticPrompt — the portable mirror', () {
    test('substitutes every hole (no `{{` survives) and embeds the bead + the '
        'rubric bands', () {
      final review = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        acceptanceCriteria: '- [ ] A peer heartbeat surfaces within 1s',
        design:
            '## Implementation Plan\n1. step\n## Touches\nnone\n'
            '## ADR Alignment\nnone\n## Validation Plan\n- check',
      );
      final prompt = loader.renderSpecCriticPrompt('coherence', review);
      expect(prompt, isNot(contains('{{')));
      expect(prompt, contains('coherence'));
      expect(prompt, contains('tg-1'));
      expect(prompt, contains('Wire the federation bus'));
      expect(prompt, contains(loader.loadRubric('coherence')));
      // The spec framing — this mirror grades a SPEC, never a diff.
      expect(prompt, contains('NOT been built'));
    });
  });

  group('the INTAKE lens rubric (bead `pow-q7n`) — it grades the BEAD', () {
    test('bead-readiness loads, names itself, and states the ONE question it '
        'asks (not "is there a spec" — that is the committee, downstream)', () {
      final text = loader.loadRubric(kReadinessRubric);
      expect(text, isNotEmpty);
      expect(text, contains(kReadinessRubric));
      expect(text, contains('WORK BEAD'));
      expect(text, contains('HELD for refinement'));
      // The four axes ARE the bar the bead's brief must clear.
      expect(text, contains('Scope'));
      expect(text, contains('Acceptance shape'));
      expect(text, contains('Cited constraints'));
      expect(text, contains('Decided approach'));
    });

    test('it bands A-C as DRIVE and D-F as HOLD — the matrix decideReadiness '
        'actually applies', () {
      final text = loader.loadRubric(kReadinessRubric);
      expect(text, contains('**D**'));
      expect(text, contains('**F**'));
      expect(text, contains('HOLD'));
    });

    test('it is generous about STYLE — a terse brief is not a finding (the '
        'false-HOLD correction the deterministic tier also honors)', () {
      final text = loader.loadRubric(kReadinessRubric);
      expect(text, contains('strict about SUBSTANCE'));
      expect(
        text,
        contains('Do not hold a bead for being short'),
        reason: 'length is NOT an axis — a terse chore bead is real work',
      );
    });
  });

  group('renderReadinessPrompt — the portable mirror (bead `pow-q7n`)', () {
    test('substitutes every hole (no `{{` survives), embeds the bead + the '
        'rubric bands, and carries the INTAKE framing (no spec, no diff)', () {
      final review = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'DECIDED: extend the existing bus; no new transport.',
      );
      final prompt = loader.renderReadinessPrompt(kReadinessRubric, review);
      expect(prompt, isNot(contains('{{')));
      expect(prompt, contains(kReadinessRubric));
      expect(prompt, contains('tg-1'));
      expect(prompt, contains('Wire the federation bus'));
      expect(prompt, contains(loader.loadRubric(kReadinessRubric)));
      // This mirror grades the BEAD — never a spec (spec-critic) and never a
      // diff (critic). Three prompt SHAPES, three mirrors.
      expect(prompt, contains('NOT been specified'));
      expect(prompt, contains('WORK BEAD ITSELF'));
      // It is a LENS, not a committee — the budget instruction is load-bearing.
      expect(prompt, contains('Stay cheap'));
    });
  });

  group('renderDiscoveryPrompt — the portable mirror of the explorer lens', () {
    test(
      'substitutes every hole (no `{{` survives), embeds the bead + the lens '
      'brief, and carries the CITE-THE-OFFENCE contract — it GRADES nothing',
      () {
        final review = bead('tg-1').copyWith(
          title: 'Wire the federation bus',
          description: 'DECIDED: extend the existing bus; no new transport.',
        );
        final prompt = loader.renderDiscoveryPrompt(
          kDecisionLens,
          lensBrief(kDecisionLens),
          review,
        );
        expect(prompt, isNot(contains('{{')));
        expect(prompt, contains(kDecisionLens));
        expect(prompt, contains('tg-1'));
        expect(prompt, contains('Wire the federation bus'));
        expect(prompt, contains('DECISION CONTEXT'));
        // The gate's three rules, as the lens reads them.
        expect(prompt, contains('CITE-THE-OFFENCE'));
        expect(prompt, contains('The departure clause'));
        expect(prompt, contains('NAME the precedent'));
        // A lens REPORTS; it does not grade — no letter anywhere in the mirror.
        expect(prompt, contains('You DECIDE nothing'));
        expect(prompt, isNot(contains('A (best) through F')));
        // READ-ONLY (A37), and CHEAP.
        expect(prompt, contains('You are READ-ONLY'));
        expect(prompt, contains('no `bd update`'));
        expect(prompt, contains('Stay CHEAP'));
      },
    );
  });

  group('extension/mcp/config.yaml declares the spec pack', () {
    test('the five spec rubrics + the INTAKE rubric ride as resources; the '
        'spec-critic, readiness and discovery prompts are declared', () {
      final manifest = File(
        p.join(root, 'mcp', 'config.yaml'),
      ).readAsStringSync();
      for (final rubricId in kSpecCommitteeRubrics) {
        expect(
          manifest,
          contains('rubrics/$rubricId.md'),
          reason: 'the $rubricId resource must be declared',
        );
      }
      expect(manifest, contains('prompts/spec-critic.md'));
      // The spec-readiness INTAKE lens (bead `pow-q7n`).
      expect(manifest, contains('rubrics/bead-readiness.md'));
      expect(manifest, contains('prompts/readiness.md'));
      // The DISCOVERY explorer — no rubric, so a prompt entry only.
      expect(manifest, contains('prompts/discovery.md'));
    });
  });

  test('all decision assets name the roster-mode lookup', () {
    final assets = <String, String>{
      'rubrics/decision-alignment.md': loader.loadRubric('decision-alignment'),
      'prompts/readiness.md': loader.loadPromptTemplate('readiness'),
      'prompts/spec-critic.md': loader.loadPromptTemplate('spec-critic'),
      'prompts/discovery.md': loader.loadPromptTemplate('discovery'),
    };

    for (final entry in assets.entries) {
      expect(entry.value, contains('space decisions index'), reason: entry.key);
      expect(
        entry.value,
        contains('mounted-substation roster'),
        reason: entry.key,
      );
      for (final token in kLocalOnlyTokens) {
        expect(entry.value, isNot(contains(token)), reason: entry.key);
      }
    }
  });

  test('searching assets pass NO register-directory argument', () {
    final searchingAssets = [
      loader.loadRubric('decision-alignment'),
      loader.loadPromptTemplate('readiness'),
      loader.loadPromptTemplate('spec-critic'),
      loader.loadPromptTemplate('discovery'),
    ];

    for (final text in searchingAssets) {
      expect(text, isNot(contains(r'[ ! -d "$register" ]')));
    }
    for (final text in [
      loader.loadRubric('decision-alignment'),
      loader.loadPromptTemplate('discovery'),
    ]) {
      expect(text, contains('the_grid#admission-authority-boundary'));
    }
  });

  test('discovery prompts require structured FOREIGN bead citations', () {
    final runtime = const DiscoveryLensCapability().buildLensPrompt(
      bead: bead('tg-1'),
      lens: kPriorArtLens,
      nodePath: 'tg-1/spec_review/discovery/$kPriorArtLens',
      workspaceDir: '/w/tg-1',
    );
    final packaged = loader.loadPromptTemplate('discovery');
    for (final prompt in [runtime, packaged]) {
      for (final token in [
        'beadCitation',
        'VERBATIM',
        'FOREIGN',
        'beadId',
        'field',
        'excerpt',
      ]) {
        expect(prompt, contains(token));
      }
    }
  });

  group('the register WRITE rule replaced the legacy-register vocabulary', () {
    /// Every Markdown asset under `extension/` plus every Dart source under
    /// `lib/` — the two trees the positive control covers.
    List<File> sourceFiles() => [
      ...Directory(_extensionDir())
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.md')),
      ..._libDir()
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    test('POSITIVE CONTROL: the legacy-register strings are GONE from lib/ '
        'and extension/', () {
      final dead = <String, RegExp>{
        'the living-register framing': RegExp(
          'living AI-decision register',
          caseSensitive: false,
        ),
        'the pending amendment status': RegExp(
          r'status:\s*pending',
          caseSensitive: false,
        ),
      };
      final files = sourceFiles();
      expect(files, isNotEmpty, reason: 'the fence must scan something');
      for (final file in files) {
        final text = file.readAsStringSync();
        for (final entry in dead.entries) {
          expect(
            entry.value.hasMatch(text),
            isFalse,
            reason: '${file.path} still carries ${entry.key}',
          );
        }
      }
    });

    test('no RENDERED register instruction carries the `pending` tier', () {
      final rendered = <String, String>{
        'rubrics/decision-alignment.md': loader.loadRubric(
          'decision-alignment',
        ),
        'rubrics/bead-readiness.md': loader.loadRubric(kReadinessRubric),
        'prompts/spec-critic.md': loader.loadPromptTemplate('spec-critic'),
        'prompts/readiness.md': loader.loadPromptTemplate('readiness'),
        'prompts/discovery.md': loader.loadPromptTemplate('discovery'),
        'discovery.dart:buildLensPrompt': const DiscoveryLensCapability()
            .buildLensPrompt(
              bead: bead('tg-1'),
              lens: kDecisionLens,
              nodePath: 'tg-1/spec_review/discovery/$kDecisionLens',
              workspaceDir: '/w/tg-1',
            ),
        'discovery.dart:lensBrief': lensBrief(kDecisionLens),
      };
      final tier = RegExp(r'\bpending\b', caseSensitive: false);
      for (final entry in rendered.entries) {
        expect(
          tier.hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} still teaches the `pending` tier',
        );
      }
    });

    test('the write rule NAMES its four load-bearing tokens', () {
      for (final token in [
        'docs/decisions/',
        '.claude/skills/decide/SKILL.md',
        'BINDS ON WRITE',
        'READ-ONLY LEGACY',
      ]) {
        expect(kDecisionWriteRule, contains(token));
      }
    });

    test('every searching asset mirrors the lens command VERBATIM', () {
      final surfaceLookup = rosterDecisionIndexCommand(
        surface: '$kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
      );

      for (final text in [
        loader.loadRubric('decision-alignment'),
        loader.loadPromptTemplate('spec-critic'),
        loader.loadPromptTemplate('discovery'),
      ]) {
        expect(text, contains(surfaceLookup));
      }
      expect(
        loader.loadPromptTemplate('readiness'),
        contains(rosterDecisionIndexCommand()),
      );
    });
  });

  group('the pow-bhm re-tune — the vended docs (ratified 2026-07-18)', () {
    test('coherence grades the CODEBASE axis only — the bead graph is '
        'reported, never graded', () {
      final text = File(
        p.join(_extensionDir(), 'rubrics', 'coherence.md'),
      ).readAsStringSync();
      expect(text, contains(kVerdictRefinementKey));
      expect(text, contains('never graded'));
      expect(
        text,
        isNot(contains('the WORSE axis sets the floor')),
        reason: 'the two-axis floor rule is what pow-bhm retired',
      );
    });

    test('adr-alignment bands a MISATTRIBUTED citation as C', () {
      final text = File(
        p.join(_extensionDir(), 'rubrics', 'adr-alignment.md'),
      ).readAsStringSync();
      final cBand = text.split('- **D**').first;
      expect(cBand, contains('MISATTRIBUTED'));
      expect(text, contains('MISSING or MISAPPLIED'));
    });

    test('the vended spec-critic prompt teaches the refinement column', () {
      final text = File(
        p.join(_extensionDir(), 'prompts', 'spec-critic.md'),
      ).readAsStringSync();
      expect(text, contains(kVerdictRefinementKey));
      expect(text, contains('NEVER grades'));
    });
  });
}

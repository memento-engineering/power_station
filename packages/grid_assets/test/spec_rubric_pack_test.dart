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
// CLI or ADR paths): the rewrite is for Dart tooling, the substation docs/adr
// register, this committee's own machinery, and the station status model.
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
  fail('could not locate packages/grid_assets/extension from '
      '${Directory.current.path}');
}

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
      test('loadRubric("$rubricId") returns non-empty prose that names itself',
          () {
        final text = loader.loadRubric(rubricId);
        expect(text, isNotEmpty);
        expect(text, contains(rubricId));
      });
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
    };

    for (final entry in files.entries) {
      test('${entry.key} is clean', () {
        for (final residue in _forbiddenResidue.entries) {
          final match = residue.value.firstMatch(entry.value);
          expect(
            match,
            isNull,
            reason: '${entry.key} carries ${residue.key} '
                '("${match?.group(0)}") — the port must be rewritten for the '
                'station context, never copied verbatim',
          );
        }
      });
    }

    test('the fence is non-vacuous: it WOULD catch the verbatim source prose',
        () {
      const verbatim = 'run go test ./internal/lint/ before fs convene '
          '(see factoryskills ADR 0012 in docs/adrs)';
      final tripped = _forbiddenResidue.values
          .where((pattern) => pattern.hasMatch(verbatim))
          .length;
      expect(tripped, greaterThanOrEqualTo(4));
    });
  });

  group('the station-context rewrite is PRESENT (not just residue-free)', () {
    test('the judgement rubrics ground in Dart tooling + the house set', () {
      final all = kSpecLlmRubrics.map(loader.loadRubric).join('\n');
      expect(all, contains('dart test'));
      expect(all, contains('freezed'));
      expect(all, contains('Fakes'));
    });

    test('adr-alignment names the SUBSTATION register (docs/adr + the '
        'ADR-0000 amendment register), never a foreign home', () {
      final text = loader.loadRubric('adr-alignment');
      expect(text, contains('docs/adr/'));
      expect(text, contains('ADR-0000'));
      expect(text, contains('A<n>'));
    });

    test('coherence speaks memento terminology (the seam word is extension) '
        'and names THIS committee\'s own machinery as its duplication '
        'examples', () {
      final text = loader.loadRubric('coherence');
      expect(text, contains('**extension**'));
      expect(
        text.contains(RegExp(r'never\s+"plugin"')),
        isTrue,
        reason: 'the terminology rule rides the rubric (naming the banned '
            'word to ban it)',
      );
      expect(text, contains('PackagedAssetLoader'));
      expect(text, contains('bd dep list'));
    });

    test('spec-validation names the station status model\'s gate (`gated`)',
        () {
      expect(loader.loadRubric(kSpecGatingRubric), contains('gated'));
    });
  });

  group('renderSpecCriticPrompt — the portable mirror', () {
    test('substitutes every hole (no `{{` survives) and embeds the bead + the '
        'rubric bands', () {
      final review = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        acceptanceCriteria: '- [ ] A peer heartbeat surfaces within 1s',
        design: '## Implementation Plan\n1. step\n## Touches\nnone\n'
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

  group('extension/mcp/config.yaml declares the spec pack', () {
    test('the five spec rubrics ride as resources; the spec-critic prompt is '
        'declared', () {
      final manifest =
          File(p.join(root, 'mcp', 'config.yaml')).readAsStringSync();
      for (final rubricId in kSpecCommitteeRubrics) {
        expect(
          manifest,
          contains('rubrics/$rubricId.md'),
          reason: 'the $rubricId resource must be declared',
        );
      }
      expect(manifest, contains('prompts/spec-critic.md'));
    });
  });
}

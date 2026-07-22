// The DOCS-CHANGE rubric pack — the third pack in the loader.
//
// Proves: the three docs rubrics load through the SAME RubricSource, each names
// itself and its hard-block contract; the manifest declares all three; the
// ported-prose residue fence holds here too (the sibling fence in
// `test/spec_rubric_pack_test.dart` guards the spec pack); and — the
// self-consistency check — the `terminology-ban` lane grades the pack's OWN
// rubric prose A, so a rubric that states the ban can never trip it.
// Offline only — reads bundled files; no live anything.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves this package's `extension/` dir by walking up from the cwd (the
/// same walk the loader + the sibling pack tests use).
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

/// The residue fence: tokens from the deprecated source context the whole pack
/// was rewritten out of. The docs rubrics are new prose, so this is a fence
/// against DRIFT rather than against a port.
final Map<String, RegExp> _forbiddenResidue = {
  'the source factory by name': RegExp('factoryskills', caseSensitive: false),
  'the gas-city runtime': RegExp('gascity|gas city', caseSensitive: false),
  'gc CLI vocabulary': RegExp(r'\bgc\b'),
  'the foreign fs CLI': RegExp(r'\bfs\b'),
  'factory worker nouns': RegExp('polecat|bitsmith', caseSensitive: false),
  'the Go language': RegExp(r'\bGo\b'),
  'Go source files': RegExp(r'\.go\b'),
  'Go package layout': RegExp('internal/'),
  'the foreign ADR home': RegExp('docs/adrs'),
};

void main() {
  final root = _extensionDir();
  final loader = PackagedAssetLoader(root: root);

  group('the docs rubrics load through the SAME RubricSource', () {
    for (final rubricId in kDocsGatingRubrics) {
      test('loadRubric("$rubricId") returns prose that names itself', () {
        final text = loader.loadRubric(rubricId);
        expect(text, isNotEmpty);
        expect(text, contains(rubricId));
        expect(text, contains('GATING'));
        expect(text, contains('hard block'));
      });
    }

    test("the LLM lane is the code committee's own spec-adherence rubric", () {
      expect(kDocsLlmRubrics, ['spec-adherence']);
      expect(loader.loadRubric('spec-adherence'), isNotEmpty);
    });
  });

  group('extension/mcp/config.yaml declares the docs pack', () {
    test('all three docs rubrics ride as resources', () {
      final manifest = File(
        p.join(root, 'mcp', 'config.yaml'),
      ).readAsStringSync();
      for (final rubricId in kDocsGatingRubrics) {
        expect(manifest, contains('rubrics/$rubricId.md'));
      }
    });
  });

  group('the grep-clean fence — no foreign source-context references', () {
    for (final rubricId in kDocsGatingRubrics) {
      test('rubrics/$rubricId.md is clean', () {
        final text = loader.loadRubric(rubricId);
        for (final residue in _forbiddenResidue.entries) {
          final match = residue.value.firstMatch(text);
          expect(
            match,
            isNull,
            reason:
                'rubrics/$rubricId.md carries ${residue.key} '
                '("${match?.group(0)}") — this pack speaks the station context',
          );
        }
      });
    }
  });

  group('self-consistency: the pack passes its own terminology lane', () {
    test('every shipped rubric states the ban without tripping it', () {
      final addedLines = <String, List<String>>{
        for (final rubricId in [
          ...kDocsGatingRubrics,
          'adr-alignment',
          'coherence',
        ])
          'rubrics/$rubricId.md': loader.loadRubric(rubricId).split('\n'),
      };
      expect(terminologyFindings(addedLines), isEmpty);
    });

    test('the lane is NON-VACUOUS: a bare use IS caught', () {
      expect(
        terminologyFindings(const {
          'docs/x.md': ['Each capability ships as a plugin.'],
        }),
        hasLength(1),
      );
    });
  });
}

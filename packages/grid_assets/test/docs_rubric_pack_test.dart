// The DOCS-CHANGE rubric pack — the third pack in the loader — and the DESIGN
// judge pack that extends it.
//
// Proves: the three docs rubrics load through the SAME RubricSource, each names
// itself and its hard-block contract; the four DESIGN judge rubrics load the
// same way, each teaching the shared finding grammar, the severity vocabulary
// and its OWN distinct lens; the manifest declares all seven; the
// ported-prose residue fence holds here too (the sibling fence in
// `test/spec_rubric_pack_test.dart` guards the spec pack); and — the
// self-consistency check — the `terminology-ban` lane grades the pack's OWN
// rubric prose A, so a rubric that states the ban can never trip it.
// Offline only — reads bundled files; no live anything.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_root.dart';

/// This package's `extension/` dir, off the shared cwd-independent package
/// root. Never a walk up from the process working
/// directory: that is a process property and `dart test` runs the suites
/// concurrently, so a walk from here could read a directory another file had
/// pointed somewhere else.
String _extensionDir() => p.join(packageRoot(), 'extension');

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

  group('the DESIGN judges load through that SAME RubricSource', () {
    for (final rubricId in kDesignJudgeRubrics) {
      test('loadRubric("$rubricId") teaches the shared finding contract', () {
        final text = loader.loadRubric(rubricId);
        expect(text, isNotEmpty);
        expect(text, contains(rubricId));
        expect(text, contains('DESIGN JUDGE'));
        // Adversarial by instruction, not by hope.
        expect(text, contains('REFUTE'));
        // The exact line grammar `parseDesignFindings` enforces.
        expect(
          text,
          contains(
            '- [BLOCKER|MAJOR|MINOR] <finding-id> — <claim>; receipt: '
            '<path:line or quoted ruling entry sentence>',
          ),
        );
        for (final severity in kDesignSeverities) {
          expect(text, contains('**$severity**'));
        }
        expect(text, contains('UNIQUE within this'));
        expect(text, contains('receipt'));
        // The severity → letter map the lane is HELD to.
        expect(text, contains('worst finding is MINOR'));
        expect(text, contains('worst finding is MAJOR'));
        expect(text, contains('worst finding is BLOCKER'));
        expect(text, contains('no finding. Your rationale is EMPTY'));
      });
    }

    test('each judge names its OWN lens and disclaims the other three', () {
      const lenses = {
        'ruling-adherence': ['ruling', 'entry sentence'],
        'ordering-and-rollback': [
          'Causal ordering',
          'Interlocks',
          'Restore order',
          'Breaker semantics',
          'rollback',
        ],
        'fold-fidelity-and-ops': [
          'carrier',
          'Migration',
          'Rollout',
          'Observation',
          'Operator recovery',
        ],
        'cite-verification': [
          'BASE COMMIT',
          'branch-only',
          'current tree',
          'invented citation',
        ],
      };
      expect(lenses.keys, kDesignJudgeRubrics);
      lenses.forEach((rubricId, terms) {
        final text = loader.loadRubric(rubricId);
        for (final term in terms) {
          expect(text, contains(term), reason: '$rubricId lost "$term"');
        }
        expect(
          text,
          contains('blind to the other lanes'),
          reason: '$rubricId must weigh ONE lens (anti-anchoring)',
        );
      });
    });

    test('the committee is the docs gates plus exactly those judges', () {
      expect(kDesignCommitteeRubrics, [
        ...kDocsGatingRubrics,
        ...kDesignJudgeRubrics,
      ]);
    });
  });

  group('extension/mcp/config.yaml declares the docs pack', () {
    test('all three docs rubrics and all four judges ride as resources', () {
      final manifest = File(
        p.join(root, 'mcp', 'config.yaml'),
      ).readAsStringSync();
      for (final rubricId in kDesignCommitteeRubrics) {
        expect(manifest, contains('rubrics/$rubricId.md'));
      }
    });
  });

  group('the grep-clean fence — no foreign source-context references', () {
    for (final rubricId in kDesignCommitteeRubrics) {
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
          ...kDesignCommitteeRubrics,
          'decision-alignment',
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

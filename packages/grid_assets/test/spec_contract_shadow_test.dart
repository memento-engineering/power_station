// The SHADOW measurement of the spec record grammar — the evidence phase.
//
// Proves: the retained corpus is on disk and whole; every DECLARED overlap and
// residue clause is quoted VERBATIM from the packaged rubric it names (so the
// claim "this lane already asks for it" can never be invented); the report is
// pinned to its own regeneration; this measurement rides the recorded-artifact
// writer the pack's other retained-corpus measurement uses rather than forking
// it; and this bead changes NO routing — the committee's lane set is
// byte-unchanged and no critic is removed, skipped or made conditional.
import 'dart:io';

import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// The package root, resolved through the loader's OWN resolution (package
/// config first, cwd walk-up fallback) rather than read off
/// [Directory.current].
///
/// Two suites in this pack legitimately chdir that process-global, so a
/// relative read here would fail depending on which suite ran alongside it.
/// This suite never writes [Directory.current] either.
final String _root = p.dirname(PackagedAssetLoader().root);

/// Whether [rubric] carries [clause], ignoring how the rubric HARD-WRAPS its
/// prose: a clause quoted across a line break is still quoted verbatim.
bool _quotesVerbatim(String rubric, String clause) => rubric
    .replaceAll(RegExp(r'\s+'), ' ')
    .contains(clause.replaceAll(RegExp(r'\s+'), ' '));

void main() {
  final corpus = readSpecCorpus(_root);
  final loader = PackagedAssetLoader();

  group('the retained corpus', () {
    test('is the 10 shipped specs, each whole', () {
      expect(corpus, hasLength(10));
      for (final entry in corpus) {
        expect(entry.acceptance.trim(), isNotEmpty, reason: entry.bead);
        expect(entry.design, contains('## Implementation Plan'), reason: entry.bead);
        expect(entry.outcome, 'shipped', reason: entry.bead);
        expect(entry.closedAt, isNotEmpty, reason: entry.bead);
      }
    });

    test('every entry PREDATES the grammar — which is what makes a finding on '
        'one of them migration cost rather than critic redundancy', () {
      for (final entry in corpus) {
        expect(
          DateTime.parse(entry.closedAt).isBefore(DateTime.utc(2026, 9, 4)),
          isTrue,
          reason: '${entry.bead} closed ${entry.closedAt}',
        );
      }
    });

    test('the parser is TOTAL over every retained spec — no throw on real, '
        'messy, 80KB input', () {
      for (final entry in corpus) {
        expect(
          () => parseSpecContract(
            acceptance: entry.acceptance,
            design: entry.design,
          ),
          returnsNormally,
          reason: entry.bead,
        );
      }
    });
  });

  group('the declared tables are QUOTED from the lanes, never asserted', () {
    test('every overlap clause is verbatim in its rubric', () {
      for (final overlap in kSpecContractLaneOverlap) {
        if (overlap.rubric.isEmpty) {
          expect(
            overlap.clause,
            isEmpty,
            reason: '${overlap.rule.name} names no lane but quotes one',
          );
          continue;
        }
        expect(
          _quotesVerbatim(loader.loadRubric(overlap.rubric), overlap.clause),
          isTrue,
          reason:
              '${overlap.rule.name} claims `${overlap.rubric}` already says '
              '"${overlap.clause}"',
        );
      }
    });

    test('every residue clause is verbatim in its rubric', () {
      for (final residue in kSpecContractSemanticResidue) {
        expect(
          _quotesVerbatim(loader.loadRubric(residue.rubric), residue.clause),
          isTrue,
          reason: '${residue.rubric}: "${residue.clause}"',
        );
      }
    });

    test('every rule appears in the overlap table exactly once', () {
      expect(
        kSpecContractLaneOverlap.map((overlap) => overlap.rule).toList(),
        unorderedEquals(SpecContractRule.values),
      );
    });

    test('the residue names every LLM lane — the four that keep judging', () {
      expect(
        kSpecContractSemanticResidue.map((r) => r.rubric).toSet(),
        kSpecLlmRubrics.toSet(),
      );
    });
  });

  test('the checked-in report EQUALS the regenerated one — '
      '`dart run tool/spec_contract_shadow.dart --record` is the only writer',
      () {
    expect(
      File(p.join(_root, kSpecContractShadowReport)).readAsStringSync(),
      renderSpecContractShadowReport(corpus),
    );
  });

  test('a read-only run over the checked-in report exits 0', () async {
    expect(await runSpecContractShadow(root: _root, record: false), 0);
  });

  group('this measurement rides the pack\'s existing shape', () {
    test('`recordArtifact` is the ONE writer of a recorded artifact — no '
        'second temp-file-plus-rename site anywhere in lib/', () {
      final renamers = [
        for (final file in Directory(p.join(_root, 'lib'))
            .listSync(recursive: true)
            .whereType<File>())
          if (file.path.endsWith('.dart') &&
              file.readAsStringSync().contains('.rename('))
            p.relative(file.path, from: _root),
      ];
      expect(
        renamers,
        ['lib/src/io/recorded_artifact.dart'],
        reason:
            'a second atomic-write site means this measurement forked the '
            'discipline instead of riding the one search_recall.dart uses',
      );
    });

    test('that writer creates parents, replaces in place, and leaves no '
        'temporary behind', () async {
      final directory = await Directory.systemTemp.createTemp('recorded');
      addTearDown(() => directory.delete(recursive: true));
      // The parent is created, so a first record run needs no mkdir of its own.
      final file = File(p.join(directory.path, 'nested', 'report.md'));
      await recordArtifact(file, 'body');
      expect(file.readAsStringSync(), 'body');
      // The rename consumes the temporary rather than leaving it behind.
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      await recordArtifact(file, 'replaced');
      expect(file.readAsStringSync(), 'replaced');
    });
  });

  test('this bead changes NO routing: the lane set is unchanged and no critic '
      'is conditional', () {
    expect(kSpecCommitteeRubrics, [
      'spec-validation',
      'coherence',
      'decision-alignment',
      'acceptance-testability',
      'plan-completeness',
    ]);
    expect(kSpecLlmRubrics, hasLength(4));
    expect(kSpecGatingRubric, 'spec-validation');
    final lanes = [
      for (final step in kSpecReviewCircuit.steps)
        if (step case CapabilityStep(:final stepId)) stepId,
    ];
    for (final rubric in kSpecCommitteeRubrics) {
      expect(lanes, contains(rubric));
    }
  });
}

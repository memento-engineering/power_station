// The SHADOW committee-selection policy (beads `pow-1nl.1.1`, `pow-1d2x`) — the
// PURE half.
//
// Five named tables, each addressable with `--plain-name`:
//
//  - `change-shape classifier tables` every policy-2 lane rule, the code
//                           diff-shape table, the first-round spec table, the
//                           unconditional gates, the uncertain-evidence full
//                           fallback and the shared path vocabulary;
//  - `stage evidence`       the two stages' independent evidence, their digests
//                           and every lane's input digest;
//  - `shadow receipt`       the strict codecs over trajectory's own value types,
//                           null-versus-zero, the counterfactual accounting and
//                           the store's previous-round read;
//  - `replay`               re-classification as a pure function of the receipt,
//                           and the retained version-1 shape;
//  - `source shape`         the architecture fences.
//
// Fakes, not mocks. Zero inference; the only I/O is a temp dir for the evidence
// source's and the store's own read paths and the source-shape test's reads.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart' show bead;
import 'package:grid_trajectory/grid_trajectory.dart'
    show GateDisposition, LaneReport, UsageSample;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_root.dart';

const _policy = kCommitteeSelectionPolicy;

CommitteeSelectionEvidence _spec({
  List<String> intent = const [],
  List<String> acceptance = const [],
  List<String> paths = const [],
  List<String> decisions = const [],
  List<String> priorArt = const [],
  List<String> context = const [],
  List<String> flags = const [],
  List<String> missing = const [],
  bool truncated = false,
  int round = 3,
}) => CommitteeSelectionEvidence(
  stage: CommitteeStage.specReview,
  workBeadId: 'pow-1',
  round: round,
  intent: intent,
  acceptance: acceptance,
  paths: paths,
  decisions: decisions,
  priorArt: priorArt,
  context: context,
  flags: flags,
  missingEvidenceIds: missing,
  truncated: truncated,
);

CommitteeSelectionEvidence _code({
  List<String> changedPaths = const [],
  String pinnedDiffDigest = 'sha-of-the-pinned-diff',
  List<String> intent = const [],
  List<String> acceptance = const [],
  List<String> paths = const [],
  List<String> decisions = const [],
  List<String> priorArt = const [],
  List<String> missing = const [],
  bool truncated = false,
  int round = 3,
}) => CommitteeSelectionEvidence(
  stage: CommitteeStage.codeReview,
  workBeadId: 'pow-1',
  round: round,
  intent: intent,
  acceptance: acceptance,
  paths: paths,
  decisions: decisions,
  priorArt: priorArt,
  changedPaths: changedPaths,
  pinnedDiffDigest: pinnedDiffDigest,
  missingEvidenceIds: missing,
  truncated: truncated,
);

CommitteeSelection _selectSpec(
  CommitteeSelectionEvidence evidence, {
  CommitteePreviousRound? previous,
}) => _policy.classify(
  evidence: evidence,
  fullRubricIds: kSpecCommitteeRubrics,
  gatingRubricIds: const [kSpecGatingRubric],
  previous: previous,
);

CommitteeSelection _selectCode(CommitteeSelectionEvidence evidence) =>
    _policy.classify(
      evidence: evidence,
      fullRubricIds: kCommitteeRubrics,
      gatingRubricIds: kCodeGatingRubrics,
    );

/// `rubric id -> rule id` over every lane decision — the table's cell.
Map<String, String> _rules(CommitteeSelection selection) => {
  for (final decision in selection.laneDecisions)
    decision.rubricId: decision.rule.id,
};

/// A complete decision lookup that found NOTHING — a real empty result.
const _emptyLookup = 'surface:power_station/lib|complete|decision-surface:x';

/// A resolved decision citation.
const _cited = 'decision:decision-entry:power_station#a21@sha256:fake';

/// The source of `grid_assets/lib/<relative>`, off the shared cwd-independent
/// package root — never a cwd-relative read, which a concurrently scheduled
/// suite could resolve against a working directory it does not own.
String _libSource(String relative) =>
    File(p.join(packageRoot(), 'lib', relative)).readAsStringSync();

void main() {
  group('change-shape classifier tables', () {
    test('every lane rule id is stable, fixes its disposition and '
        'round-trips', () {
      expect(CommitteeLaneRule.values.map((r) => r.id), [
        'gate-always',
        'full-fallback',
        'unrecognized-lane',
        'runtime-change',
        'metadata-change',
        'test-change',
        'no-runtime-change',
        'no-test-change',
        'test-only-change',
        'first-round',
        'cited-decision',
        'no-cited-decision',
        'facts-changed',
        'no-prior-verdict',
        'facts-unchanged',
        'acceptance-unchanged',
        'targeted-respec-action',
        'targeted-respec-preserved',
      ]);
      for (final rule in CommitteeLaneRule.values) {
        expect(CommitteeLaneRule.fromId(rule.id), rule);
        final decision = CommitteeLaneDecision(rubricId: 'lane', rule: rule);
        expect(decision.disposition, rule.disposition);
        expect(
          CommitteeLaneDecision.fromJson(
            jsonDecode(jsonEncode(decision.toJson())),
          )!.toJson(),
          decision.toJson(),
        );
      }
      expect(CommitteeLaneRule.fromId('no-such-rule'), isNull);
      // A disposition that disagrees with its rule is refused, never coerced.
      expect(
        CommitteeLaneDecision.fromJson({
          'rubricId': 'regression-risk',
          'disposition': 'elected',
          'rule': 'no-runtime-change',
        }),
        isNull,
      );
      expect(
        CommitteeLaneDecision.fromJson({
          'rubricId': ' ',
          'disposition': 'elected',
          'rule': 'gate-always',
        }),
        isNull,
      );
      expect(
        {
          for (final rule in CommitteeLaneRule.values)
            if (rule.preservesPriorVerdict) rule.id,
        },
        {
          'facts-unchanged',
          'acceptance-unchanged',
          'targeted-respec-preserved',
        },
      );
    });

    test('the code diff-shape table elects only the lanes a change can '
        'exercise', () {
      const docs = {
        'spec-adherence': 'metadata-change',
        'regression-risk': 'no-runtime-change',
        'test-coverage': 'no-test-change',
      };
      const testOnly = {
        'spec-adherence': 'test-only-change',
        'regression-risk': 'no-runtime-change',
        'test-coverage': 'test-change',
      };
      const runtime = {
        'spec-adherence': 'runtime-change',
        'regression-risk': 'runtime-change',
        'test-coverage': 'runtime-change',
      };
      final table = <({List<String> paths, Map<String, String> lanes})>[
        (paths: const ['docs/a.md', 'README.md'], lanes: docs),
        (paths: const ['pubspec.yaml', 'CHANGELOG.md', 'LICENSE'], lanes: docs),
        (
          paths: const ['test/a_test.dart', 'packages/x/test/b.dart'],
          lanes: testOnly,
        ),
        (paths: const ['test/fixtures/corpus.json'], lanes: testOnly),
        (
          paths: const ['README.md', 'test/a_test.dart'],
          lanes: const {
            'spec-adherence': 'metadata-change',
            'regression-risk': 'no-runtime-change',
            'test-coverage': 'test-change',
          },
        ),
        (paths: const ['lib/src/code/committee.dart'], lanes: runtime),
        (
          paths: const ['README.md', 'lib/a.dart', 'test/a_test.dart'],
          lanes: runtime,
        ),
        // An UNLISTED surface fails to code: it elects everything.
        (paths: const ['tool/release.sh'], lanes: runtime),
      ];
      for (final row in table) {
        final selection = _selectCode(_code(changedPaths: row.paths));
        expect(_rules(selection), {
          for (final gate in kCodeGatingRubrics) gate: 'gate-always',
          ...row.lanes,
        }, reason: '${row.paths}');
        expect(selection.source, CommitteeSelectionSource.deterministic);
        expect(
          selection.selectedRubricIds,
          [
            for (final id in kCommitteeRubrics)
              if (selection.decisionFor(id)!.elected) id,
          ],
          reason: 'elected lanes return in ROSTER order',
        );
        expect(
          selection.matchedRuleIds,
          {for (final rule in _rules(selection).values) rule}.toList(),
          reason: 'the per-rule fold key is the distinct rule ids',
        );
      }
      // The DOCS committee runs one semantic lane, and a docs diff elects it.
      final docsCommittee = _policy.classify(
        evidence: _code(changedPaths: const ['docs/guide.md']),
        fullRubricIds: kDocsCommitteeRubrics,
        gatingRubricIds: kDocsGatingRubrics,
      );
      expect(docsCommittee.selectedRubricIds, kDocsCommitteeRubrics);
      expect(
        docsCommittee.decisionFor('spec-adherence')!.rule,
        CommitteeLaneRule.metadataChange,
      );
    });

    test('the first-round spec table elects decision-alignment only on a '
        'cited decision', () {
      const firstRound = {
        kSpecGatingRubric: 'gate-always',
        'coherence': 'first-round',
        'acceptance-testability': 'first-round',
        'plan-completeness': 'first-round',
      };
      final table = <({List<String> decisions, String rule})>[
        (decisions: const [], rule: 'no-cited-decision'),
        (decisions: const [_emptyLookup], rule: 'no-cited-decision'),
        (decisions: const [_emptyLookup, _cited], rule: 'cited-decision'),
        (decisions: const ['departure:abc'], rule: 'cited-decision'),
      ];
      for (final row in table) {
        final selection = _selectSpec(
          _spec(
            intent: const ['title:i'],
            acceptance: const ['acceptance_criteria:a'],
            decisions: row.decisions,
          ),
        );
        expect(_rules(selection), {
          ...firstRound,
          'decision-alignment': row.rule,
        }, reason: '${row.decisions}');
      }
    });

    test('later spec rounds re-run only the lanes whose facts moved', () {
      final base = _spec(
        intent: const ['title:i'],
        acceptance: const ['acceptance_criteria:a'],
        decisions: const [_cited],
      );
      expect(_rules(_selectSpec(base, previous: _previous(base))), {
        kSpecGatingRubric: 'gate-always',
        'coherence': 'facts-unchanged',
        'decision-alignment': 'facts-unchanged',
        'acceptance-testability': 'acceptance-unchanged',
        'plan-completeness': 'facts-unchanged',
      });
      final redesigned = _spec(
        intent: const ['title:i', 'design:d2'],
        acceptance: const ['acceptance_criteria:a'],
        decisions: const [_cited],
      );
      expect(_rules(_selectSpec(redesigned, previous: _previous(base))), {
        kSpecGatingRubric: 'gate-always',
        'coherence': 'facts-changed',
        'decision-alignment': 'facts-changed',
        'acceptance-testability': 'acceptance-unchanged',
        'plan-completeness': 'facts-changed',
      });
      // An unchanged lane the previous round never GRADED has no verdict to
      // carry forward, so it runs.
      expect(
        _rules(
          _selectSpec(
            base,
            previous: _previous(base, grades: {'coherence': null}),
          ),
        )['coherence'],
        'no-prior-verdict',
      );
    });

    test('a respec round re-runs only its action lanes', () {
      final base = _spec(
        intent: const ['title:i'],
        acceptance: const ['acceptance_criteria:a'],
        decisions: const [_emptyLookup],
      );
      final respecced = _previous(
        base,
        grades: {'plan-completeness': 'D', 'coherence': null},
        respec: true,
      );
      expect(_rules(_selectSpec(base, previous: respecced)), {
        kSpecGatingRubric: 'gate-always',
        'coherence': 'no-prior-verdict',
        'decision-alignment': 'targeted-respec-preserved',
        'acceptance-testability': 'targeted-respec-preserved',
        'plan-completeness': 'targeted-respec-action',
      });
      // A respec whose only action lane was the GATE targets no semantic lane,
      // so the round falls back to the fact comparison.
      final gateOnly = _previous(
        base,
        grades: {kSpecGatingRubric: 'F'},
        respec: true,
      );
      expect(
        _rules(_selectSpec(base, previous: gateOnly))['plan-completeness'],
        'facts-unchanged',
      );
      // An unknown semantic lane is elected, never silently dropped.
      final unknown = _policy.classify(
        evidence: base,
        fullRubricIds: const [kSpecGatingRubric, 'coherence', 'a-new-lane'],
        gatingRubricIds: const [kSpecGatingRubric],
        previous: respecced,
      );
      expect(
        unknown.decisionFor('a-new-lane')!.rule,
        CommitteeLaneRule.unrecognizedLane,
      );
    });

    test('uncertain evidence elects the FULL committee, loudly', () {
      final uncertainCode = <CommitteeSelectionEvidence>[
        _code(changedPaths: const [], missing: const ['pinned-diff']),
        _code(
          changedPaths: const [],
          missing: const ['pinned-diff:no-targets'],
        ),
        _code(
          changedPaths: const ['docs/a.md'],
          missing: const ['pinned-diff:clipped'],
        ),
        _code(changedPaths: const ['docs/a.md'], pinnedDiffDigest: ''),
        _code(changedPaths: const ['docs/a.md'], missing: const ['workspace']),
        CommitteeSelectionEvidence(
          stage: CommitteeStage.codeReview,
          workBeadId: 'pow-1',
          round: 1,
          missingEvidenceIds: const ['evidence-source'],
        ),
      ];
      for (final evidence in uncertainCode) {
        expect(committeeEvidenceIsUncertain(evidence), isTrue);
        final selection = _selectCode(evidence);
        expect(selection.source, CommitteeSelectionSource.fullFallback);
        expect(selection.selectedRubricIds, kCommitteeRubrics);
        expect(_rules(selection), {
          for (final gate in kCodeGatingRubrics) gate: 'gate-always',
          'spec-adherence': 'full-fallback',
          'regression-risk': 'full-fallback',
          'test-coverage': 'full-fallback',
        });
      }
      final uncertainSpec = <CommitteeSelectionEvidence>[
        _spec(
          intent: const ['title:i'],
          missing: const ['decisions:power_station/lib'],
        ),
        _spec(missing: const ['anchors', 'round']),
        _spec(
          intent: const ['title:i'],
          missing: const ['anchors:work-bead-mismatch'],
        ),
        _spec(),
      ];
      for (final evidence in uncertainSpec) {
        final selection = _selectSpec(evidence);
        expect(selection.source, CommitteeSelectionSource.fullFallback);
        expect(selection.selectedRubricIds, kSpecCommitteeRubrics);
      }
      // A gap the code classification never reads is NOT uncertainty: the
      // diff alone decides a code round.
      final noDossier = _code(
        changedPaths: const ['docs/a.md'],
        missing: const ['anchors', 'dossier'],
      );
      expect(committeeEvidenceIsUncertain(noDossier), isFalse);
      expect(
        _selectCode(noDossier).source,
        CommitteeSelectionSource.deterministic,
      );
    });

    test('EVERY gate set is unconditional, in all three committees', () {
      for (final row in <({List<String> full, List<String> gating})>[
        (full: kSpecCommitteeRubrics, gating: const [kSpecGatingRubric]),
        (full: kCommitteeRubrics, gating: kCodeGatingRubrics),
        (full: kDocsCommitteeRubrics, gating: kDocsGatingRubrics),
      ]) {
        final stage = row.full == kSpecCommitteeRubrics
            ? CommitteeStage.specReview
            : CommitteeStage.codeReview;
        for (final evidence in <CommitteeSelectionEvidence>[
          CommitteeSelectionEvidence(
            stage: stage,
            workBeadId: 'pow-1',
            round: 1,
          ),
          CommitteeSelectionEvidence(
            stage: stage,
            workBeadId: 'pow-1',
            round: 1,
            intent: const ['title:i'],
            changedPaths: const ['docs/a.md'],
            pinnedDiffDigest: 'sha',
          ),
          CommitteeSelectionEvidence(
            stage: stage,
            workBeadId: 'pow-1',
            round: 1,
            intent: const ['title:i'],
            changedPaths: const ['lib/a.dart'],
            pinnedDiffDigest: 'sha',
          ),
        ]) {
          final selection = _policy.classify(
            evidence: evidence,
            fullRubricIds: row.full,
            gatingRubricIds: row.gating,
          );
          for (final gate in row.gating) {
            expect(selection.selectedRubricIds, contains(gate));
            expect(
              selection.decisionFor(gate)!.rule,
              CommitteeLaneRule.gateAlways,
            );
          }
          expect(
            selection.laneDecisions.map((d) => d.rubricId),
            row.full,
            reason: 'ONE decision per active lane, in roster order',
          );
        }
        // The FULL FALLBACK is the whole roster, in declaration order.
        expect(
          _policy
              .selectFullFallback(
                evidence: CommitteeSelectionEvidence(
                  stage: stage,
                  workBeadId: 'pow-1',
                  round: 1,
                ),
                fullRubricIds: row.full,
                gatingRubricIds: row.gating,
              )
              .selectedRubricIds,
          row.full,
        );
      }
    });

    test('every lane rule is reachable from a real classification', () {
      final base = _spec(
        intent: const ['title:i'],
        acceptance: const ['acceptance_criteria:a'],
        decisions: const [_cited],
      );
      final selections = [
        for (final paths in const [
          ['docs/a.md'],
          ['test/a_test.dart'],
          ['lib/a.dart'],
        ])
          _selectCode(_code(changedPaths: paths)),
        _selectCode(
          _code(changedPaths: const [], missing: const ['pinned-diff']),
        ),
        _selectSpec(_spec(intent: const ['title:i'])),
        _selectSpec(base),
        _selectSpec(base, previous: _previous(base)),
        _selectSpec(
          _spec(
            intent: const ['title:i2'],
            acceptance: const ['acceptance_criteria:a'],
            decisions: const [_cited],
          ),
          previous: _previous(base, grades: {'coherence': null}),
        ),
        _selectSpec(
          base,
          previous: _previous(
            base,
            grades: {'coherence': 'E', 'plan-completeness': null},
            respec: true,
          ),
        ),
        _policy.classify(
          evidence: base,
          fullRubricIds: const ['a-new-lane'],
          gatingRubricIds: const [],
        ),
      ];
      expect({
        for (final selection in selections)
          for (final decision in selection.laneDecisions) decision.rule,
      }, CommitteeLaneRule.values.toSet());
    });

    test('the semantic set is the roster minus the gates, in roster order', () {
      expect(
        _policy.semanticRubricIds(
          fullRubricIds: kCommitteeRubrics,
          gatingRubricIds: kCodeGatingRubrics,
        ),
        ['spec-adherence', 'regression-risk', 'test-coverage'],
      );
      expect(
        _policy.semanticRubricIds(
          fullRubricIds: kDocsCommitteeRubrics,
          gatingRubricIds: kDocsGatingRubrics,
        ),
        ['spec-adherence'],
      );
    });

    test('the shared path vocabulary has ONE owner', () {
      expect(isCommitteeTestPath('test/a_test.dart'), isTrue);
      expect(isCommitteeTestPath('packages/x/test/a.dart'), isTrue);
      expect(isCommitteeTestPath('lib/src/a_test.dart'), isTrue);
      expect(isCommitteeTestPath('lib/src/a.dart'), isFalse);
      for (final row in <(String, CommitteeDiffPathKind)>[
        ('LICENSE', CommitteeDiffPathKind.metadata),
        ('packages/x/CHANGELOG.md', CommitteeDiffPathKind.metadata),
        ('packages/x/pubspec.yaml', CommitteeDiffPathKind.metadata),
        ('tool/config.toml', CommitteeDiffPathKind.metadata),
        ('test/README.md', CommitteeDiffPathKind.metadata),
        ('test/fixtures/x.json', CommitteeDiffPathKind.test),
        ('test/a_test.dart', CommitteeDiffPathKind.test),
        ('lib/a.dart', CommitteeDiffPathKind.runtime),
        ('tool/release.sh', CommitteeDiffPathKind.runtime),
      ]) {
        expect(committeeDiffPathKindOf(row.$1), row.$2, reason: row.$1);
      }
      // The predicates the classifier reads ARE the docs committee's: one
      // neutral library owns them, the docs library re-exports them.
      final owner = _libSource(p.join('src', 'code', 'review_path.dart'));
      final docs = _libSource(p.join('src', 'code', 'docs_committee.dart'));
      final policy = _libSource(
        p.join('src', 'code', 'committee_selection.dart'),
      );
      for (final declaration in const [
        'bool isDocsPath(',
        'bool isMetadataPath(',
        'const Set<String> kMetadataPathExtensions',
        'const Set<String> kMetadataPathFilenames',
      ]) {
        expect(owner, contains(declaration), reason: declaration);
        expect(docs, isNot(contains(declaration)), reason: declaration);
        expect(policy, isNot(contains(declaration)), reason: declaration);
      }
      expect(docs, contains("export 'review_path.dart'"));
      expect(policy, contains("import 'review_path.dart';"));
      for (final retired in const [
        'kCommitteeProseExtensions',
        'kCommitteeMetadataExtensions',
        'kCommitteeMetadataBasenames',
        'isCommitteeProseOrMetadataPath',
      ]) {
        expect(policy, isNot(contains(retired)), reason: retired);
      }
    });
  });

  group('stage evidence', () {
    test('spec evidence reads the round-stamped artifacts and NO diff', () {
      final evidence = buildSpecReviewSelectionEvidence(
        workBeadId: 'pow-x',
        anchors: _anchors(),
        dossier: _dossier(),
      );
      expect(evidence.stage, CommitteeStage.specReview);
      expect(evidence.round, 7);
      expect(evidence.intent, hasLength(3));
      expect(evidence.acceptance, hasLength(1));
      expect(evidence.paths, hasLength(1));
      expect(evidence.decisions, isNotEmpty);
      expect(evidence.priorArt, isNotEmpty);
      expect(evidence.context, isNotEmpty);
      expect(evidence.flags, isNotEmpty);
      expect(
        evidence.changedPaths,
        isEmpty,
        reason: 'there is no diff at spec time, by construction',
      );
      expect(evidence.pinnedDiffDigest, isEmpty);
      expect(evidence.missingEvidenceIds, isEmpty);
    });

    test('code evidence adds the pinned diff digest and its target paths', () {
      const diff = '''
diff --git a/lib/src/code/committee.dart b/lib/src/code/committee.dart
index 1..2 100644
--- a/lib/src/code/committee.dart
+++ b/lib/src/code/committee.dart
@@ -1 +1 @@
-old
+new
diff --git a/test/committee_test.dart b/test/committee_test.dart
@@ -1 +1 @@
+a test
''';
      final evidence = buildCodeReviewSelectionEvidence(
        workBeadId: 'pow-x',
        anchors: _anchors(),
        dossier: _dossier(),
        pinnedDiff: diff,
      );
      expect(evidence.stage, CommitteeStage.codeReview);
      expect(evidence.changedPaths, [
        'lib/src/code/committee.dart',
        'test/committee_test.dart',
      ]);
      expect(evidence.pinnedDiffDigest, hasLength(64));
      expect(evidence.missingEvidenceIds, isEmpty);

      // ONLY the `diff --git` targets are read — never a hunk body.
      expect(committeeChangedPathsIn('+++ b/not-a-header.dart\n'), isEmpty);
      expect(
        committeeChangedPathsIn(
          'diff --git a/b.dart b/b.dart\ndiff --git a/a.dart b/a.dart\n'
          'diff --git a/b.dart b/b.dart\n',
        ),
        ['a.dart', 'b.dart'],
        reason: 'normalized, deduplicated and sorted',
      );
    });

    test('a missing or mismatched artifact is a FACT, never clean evidence', () {
      final none = buildCodeReviewSelectionEvidence(
        workBeadId: 'pow-x',
        anchors: null,
        dossier: null,
        pinnedDiff: null,
      );
      expect(
        none.missingEvidenceIds,
        containsAll(<String>['anchors', 'dossier', 'pinned-diff', 'round']),
      );
      expect(none.isEmpty, isTrue);

      // A gather for ANOTHER bead contributes nothing at all.
      final foreign = buildSpecReviewSelectionEvidence(
        workBeadId: 'pow-other',
        anchors: _anchors(),
        dossier: _dossier(),
      );
      expect(
        foreign.missingEvidenceIds,
        containsAll(<String>[
          'anchors:work-bead-mismatch',
          'dossier:work-bead-mismatch',
        ]),
      );
      expect(foreign.intent, isEmpty);
      expect(foreign.context, isEmpty);

      // A dossier whose embedded gather is a DIFFERENT round is refused whole.
      final skewed = buildSpecReviewSelectionEvidence(
        workBeadId: 'pow-x',
        anchors: _anchors(),
        dossier: DiscoveryDossier(
          anchors: _anchors(round: 8),
          workBeadId: 'pow-x',
          context: const [ContextNote(note: 'n')],
        ),
      );
      expect(skewed.missingEvidenceIds, contains('dossier:anchors-mismatch'));
      expect(skewed.context, isEmpty);
      expect(skewed.intent, isNotEmpty, reason: 'the GATHER is still usable');

      // A dossier citing evidence the gather does not carry is refused whole.
      final unciteable = buildSpecReviewSelectionEvidence(
        workBeadId: 'pow-x',
        anchors: _anchors(),
        dossier: DiscoveryDossier(
          anchors: _anchors(),
          workBeadId: 'pow-x',
          evidenceIds: const ['bead-field:invented@sha256:nope'],
          context: const [ContextNote(note: 'n')],
        ),
      );
      expect(
        unciteable.missingEvidenceIds,
        contains('dossier:evidence-id-mismatch'),
      );
    });

    test('an unwired or clipped lookup is recorded, and truncation rides', () {
      final gather = _anchors(
        priorArtState: EvidenceState.unavailable,
        clipped: true,
      );
      final evidence = buildSpecReviewSelectionEvidence(
        workBeadId: 'pow-x',
        anchors: gather,
        dossier: DiscoveryDossier(
          anchors: gather,
          workBeadId: 'pow-x',
          missingLenses: const ['explore-code'],
        ),
      );
      expect(
        evidence.missingEvidenceIds,
        containsAll(<String>[
          'prior-art:AnchorsCapability',
          'anchors:clipped',
          'lens:explore-code',
        ]),
      );
      expect(evidence.truncated, isTrue);
    });

    test('digests are stable, input-sensitive and stage-separated', () {
      final a = _code(changedPaths: const ['lib/a.dart']);
      final b = _code(changedPaths: const ['lib/a.dart']);
      expect(
        _policy.evidenceDigestOf(a),
        _policy.evidenceDigestOf(b),
        reason: 'identical inputs reproduce the digest',
      );

      // The DIFF alone changes the code digest.
      expect(
        _policy.evidenceDigestOf(
          _code(
            changedPaths: const ['lib/a.dart'],
            pinnedDiffDigest: 'another-sha',
          ),
        ),
        isNot(_policy.evidenceDigestOf(a)),
      );

      // Two stages carrying IDENTICAL facts still digest apart.
      final specFacts = CommitteeSelectionEvidence(
        stage: CommitteeStage.specReview,
        workBeadId: 'pow-1',
        round: 3,
        intent: const ['i'],
      );
      final codeFacts = CommitteeSelectionEvidence(
        stage: CommitteeStage.codeReview,
        workBeadId: 'pow-1',
        round: 3,
        intent: const ['i'],
      );
      expect(
        _policy.evidenceDigestOf(specFacts),
        isNot(_policy.evidenceDigestOf(codeFacts)),
      );

      // Facts are normalized: order and duplication do not move the digest.
      expect(
        _policy.evidenceDigestOf(
          _code(changedPaths: const ['b.dart', 'a.dart', 'a.dart']),
        ),
        _policy.evidenceDigestOf(
          _code(changedPaths: const ['a.dart', 'b.dart']),
        ),
      );
    });

    test('EVERY active lane gets an input digest over its OWN facts', () {
      final base = _code(
        changedPaths: const ['lib/a.dart'],
        intent: const ['i'],
        acceptance: const ['a'],
        paths: const ['lib/a.dart|true|d'],
        decisions: const ['d'],
        priorArt: const ['pa'],
      );
      final digests = _policy.laneInputDigests(
        evidence: base,
        fullRubricIds: kCommitteeRubrics,
        gatingRubricIds: kCodeGatingRubrics,
      );
      expect(
        digests.keys,
        kCommitteeRubrics,
        reason: 'selected AND omitted lanes both get one',
      );
      // The rubric id is hashed in, so two lanes over the same facts differ.
      final gates = _policy.laneInputDigests(
        evidence: base,
        fullRubricIds: kCodeGatingRubrics,
        gatingRubricIds: kCodeGatingRubrics,
      );
      expect(gates[kGatingRubric], isNot(gates[kDeclaredTestsRubric]));

      // Each fact set is exactly the one the lane reads. Perturb ONE family and
      // assert which lanes moved.
      Map<String, String> digestsOf(CommitteeSelectionEvidence evidence) =>
          _policy.laneInputDigests(
            evidence: evidence,
            fullRubricIds: const [
              ...kCommitteeRubrics,
              ...kSpecCommitteeRubrics,
            ],
            gatingRubricIds: kCodeGatingRubrics,
          );
      final baseline = digestsOf(base);

      List<String> moved(CommitteeSelectionEvidence changed) {
        final next = digestsOf(changed);
        return [
          for (final entry in baseline.entries)
            if (next[entry.key] != entry.value) entry.key,
        ]..sort();
      }

      expect(
        moved(
          _code(
            changedPaths: const ['lib/a.dart'],
            intent: const ['i2'],
            acceptance: const ['a'],
            paths: const ['lib/a.dart|true|d'],
            decisions: const ['d'],
            priorArt: const ['pa'],
          ),
        ),
        [
          'coherence',
          'decision-alignment',
          'plan-completeness',
          'spec-adherence',
          'spec-validation',
        ],
        reason:
            'acceptance-testability reads the criteria ALONE; '
            'decision-alignment reads the design beside the decisions',
      );
      expect(
        moved(
          _code(
            changedPaths: const ['lib/a.dart'],
            intent: const ['i'],
            acceptance: const ['a'],
            paths: const ['lib/a.dart|true|d'],
            decisions: const ['d2'],
            priorArt: const ['pa'],
          ),
        ),
        ['decision-alignment', 'regression-risk'],
      );
      expect(
        moved(
          _code(
            changedPaths: const ['lib/b.dart'],
            intent: const ['i'],
            acceptance: const ['a'],
            paths: const ['lib/a.dart|true|d'],
            decisions: const ['d'],
            priorArt: const ['pa'],
          ),
        ),
        [kDeclaredTestsRubric, kGatingRubric, 'test-coverage']..sort(),
      );
      // An UNRECOGNISED active lane hashes the COMPLETE stage evidence, so it
      // is explicit rather than silently digested over nothing.
      final invented = _policy.laneInputDigests(
        evidence: base,
        fullRubricIds: const ['a-new-lane'],
        gatingRubricIds: const [],
      );
      final inventedElsewhere = _policy.laneInputDigests(
        evidence: _code(changedPaths: const ['lib/b.dart']),
        fullRubricIds: const ['a-new-lane'],
        gatingRubricIds: const [],
      );
      expect(invented['a-new-lane'], isNot(inventedElsewhere['a-new-lane']));
    });

    test('the discovery source reads a live worktree, best-effort', () {
      final dir = Directory.systemTemp.createTempSync('committee-selection-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pinned = File(p.join(dir.path, '.grid/critique/pinned.diff'))
        ..createSync(recursive: true)
        ..writeAsStringSync('diff --git a/lib/a.dart b/lib/a.dart\n');
      final source = DiscoveryCommitteeSelectionEvidenceSource(
        pinnedDiffPathFor: (_) => pinned.path,
        readAnchors: (_) => _anchors(),
        readDossier: (_) => _dossier(),
      );
      final evidence = source.read(
        stage: CommitteeStage.codeReview,
        workBeadId: 'pow-x',
        workspaceDir: dir.path,
      );
      expect(evidence.changedPaths, ['lib/a.dart']);
      expect(evidence.pinnedDiffDigest, isNotEmpty);

      // A THROWING reader degrades to a named gap, never an exception.
      final broken = DiscoveryCommitteeSelectionEvidenceSource(
        pinnedDiffPathFor: (_) => pinned.path,
        readAnchors: (_) => throw StateError('boom'),
        readDossier: (_) => throw StateError('boom'),
      );
      expect(
        broken
            .read(
              stage: CommitteeStage.specReview,
              workBeadId: 'pow-x',
              workspaceDir: dir.path,
            )
            .missingEvidenceIds,
        containsAll(<String>['anchors', 'dossier']),
      );

      // A workspace that is not on disk is a named gap too — no I/O attempted.
      expect(
        source
            .read(
              stage: CommitteeStage.codeReview,
              workBeadId: 'pow-x',
              workspaceDir: '/grid/worktrees/does-not-exist/pow-x',
            )
            .missingEvidenceIds,
        ['workspace'],
      );
    });
  });

  group('shadow receipt', () {
    test('the run codec round-trips and REFUSES version/enum drift', () {
      final run = _run();
      final decoded = CommitteeSelectionRun.fromJson(
        jsonDecode(jsonEncode(run.toJson())),
      );
      expect(decoded, isNotNull);
      expect(decoded!.toJson(), run.toJson());

      for (final mutate in <void Function(Map<String, Object?>)>[
        (json) => json['version'] = 3,
        (json) => json['stage'] = 'design_review',
        (json) => json['round'] = -1,
        (json) => (json['selection']! as Map)['source'] = 'guessing',
        (json) => (json['evidence']! as Map)['stage'] = 'nope',
        (json) => json['attempts'] = [
          {'attempt': 1},
        ],
        (json) => json['policyVersion'] = '',
        // A version-2 run decides EVERY roster lane exactly once.
        (json) => (json['selection']! as Map)['laneDecisions'] = <Object?>[],
        (json) => ((json['selection']! as Map)['laneDecisions']! as List)[0] = {
          'rubricId': kGatingRubric,
          'disposition': 'omitted',
          'rule': 'gate-always',
        },
        (json) => json['previous'] = {'round': -1},
      ]) {
        final json =
            jsonDecode(jsonEncode(run.toJson())) as Map<String, Object?>;
        mutate(json);
        expect(CommitteeSelectionRun.fromJson(json), isNull);
      }
    });

    test('a lane receipt carries trajectory values by COMPOSITION', () {
      final lane = CommitteeLaneReceipt.derive(
        rubricId: 'regression-risk',
        nodePath: 'pow-1/review/regression-risk',
        workBeadId: 'pow-1',
        routeType: 'escalate',
        gating: false,
        grade: 'd',
        transport: 'file',
        rationale: 'the blast radius is wider than the diff',
        model: 'sonnet',
        tokensIn: 120,
        tokensOut: 30,
        costUsd: 0.42,
        numTurns: 4,
        durationMs: 9000,
      );
      expect(lane.report, isA<LaneReport>());
      expect(lane.usage, isA<UsageSample>());
      expect(lane.report.lane, 'regression-risk');
      expect(lane.grade, 'D', reason: 'normalized to the upper-case letter');
      expect(lane.report.gradeCounts, {'D': 1});
      expect(lane.report.adverseVerdicts, 1);
      expect(lane.gateDisposition, GateDisposition.upheld);
      expect(lane.report.upheld, 1);
      expect(lane.report.respecNoFollowUp, 1);
      expect(lane.report.meanCostUsd, 0.42);
      expect(lane.usage.costUsd, 0.42);
      expect(lane.usage.fromFallback, isFalse);
      expect(lane.missingFields, isEmpty);

      // An ADVANCE past an adverse verdict is an OVERRIDE; an operator ruling
      // is one however the route ruled.
      expect(
        committeeGateDispositionFor(adverse: true, routeType: 'advance'),
        GateDisposition.overridden,
      );
      expect(
        committeeGateDispositionFor(adverse: true, routeType: 'rewind'),
        GateDisposition.unresolved,
      );
      expect(
        committeeGateDispositionFor(
          adverse: true,
          routeType: 'escalate',
          transport: kCommitteeOperatorTransport,
        ),
        GateDisposition.overridden,
      );
      expect(
        committeeGateDispositionFor(adverse: false, routeType: 'escalate'),
        isNull,
        reason: 'an unearned disposition is worse than a blank',
      );
    });

    test('NULL and ZERO stay distinct across lanes and totals', () {
      // A DETERMINISTIC gate contributes KNOWN ZERO inference cost.
      final gate = CommitteeLaneReceipt.derive(
        rubricId: kGatingRubric,
        nodePath: 'pow-1/review/$kGatingRubric',
        workBeadId: 'pow-1',
        routeType: 'advance',
        gating: true,
        grade: 'A',
        transport: 'file',
        durationMs: 1000,
      );
      expect(gate.costUsd, 0);
      expect(gate.tokensIn, 0);
      expect(gate.missingFields, isEmpty);

      // A SEMANTIC lane that reported nothing leaves nulls AND names them.
      final blank = CommitteeLaneReceipt.derive(
        rubricId: 'test-coverage',
        nodePath: 'pow-1/review/test-coverage',
        workBeadId: 'pow-1',
        routeType: 'advance',
        gating: false,
      );
      expect(blank.costUsd, isNull);
      expect(blank.tokensIn, isNull);
      expect(blank.grade, isNull);
      expect(
        blank.missingFields,
        containsAll(<String>['grade', 'transport', 'costUsd', 'model']),
      );

      final accounting = committeeUsageAccounting(lanes: [gate, blank]);
      expect(
        accounting.costUsd,
        isNull,
        reason: 'one blank contributor nulls the total instead of coercing it',
      );
      expect(accounting.missingLaneIds, ['test-coverage']);
      expect(accounting.samples, hasLength(2));

      // With the blank lane OMITTED, the counterfactual total is earned.
      final earned = committeeUsageAccounting(lanes: [gate]);
      expect(earned.costUsd, 0);
      expect(earned.tokensIn, 0);
      expect(earned.missingLaneIds, isEmpty);
    });

    test(
      'the receipt records omissions, provenance and the counterfactual',
      () {
        final receipt = _receipt();
        expect(receipt.selectedRubricIds, [
          ...kCodeGatingRubrics,
          'test-coverage',
        ]);
        expect(
          receipt.omittedRubricIds,
          ['spec-adherence', 'regression-risk'],
          reason: 'the hypothetical omission is the whole point of the sample',
        );
        expect(receipt.actionLaneIds, ['regression-risk']);
        expect(
          receipt.run.selection.decisionFor('regression-risk')!.rule,
          CommitteeLaneRule.noRuntimeChange,
        );
        expect(
          receipt.preservedLanes,
          isEmpty,
          reason:
              'a code omission declares the lane irrelevant; it carries '
              'no prior verdict',
        );
        expect(receipt.route.type, 'advance');
        expect(receipt.gateDisposition, GateDisposition.overridden);
        expect(receipt.lanes, hasLength(kCommitteeRubrics.length));
        expect(receipt.run.selection.laneInputDigests.keys, kCommitteeRubrics);
        expect(receipt.downstreamJoinKeys['workBeadId'], 'pow-1');
        expect(receipt.downstreamJoinKeys['siblingScope'], 'pow-1/review/');
        expect(receipt.sampleId, hasLength(64));
        expect(receipt.joinId, hasLength(64));

        // The counterfactual EXCLUDES the omitted lanes; policy 2 spends
        // nothing on selection, so the classifier block is empty.
        expect(receipt.actual.contributingRunIds, kCommitteeRubrics);
        expect(
          receipt.counterfactual.contributingRunIds,
          receipt.selectedRubricIds,
        );
        expect(receipt.classifier.contributingRunIds, isEmpty);
        expect(receipt.classifier.costUsd, 0);
        expect(receipt.actual.costUsd, closeTo(1.5, 1e-9));
        expect(receipt.counterfactual.costUsd, closeTo(0.51, 1e-9));
        expect(
          receipt.counterfactual.costUsd! < receipt.actual.costUsd!,
          isTrue,
          reason: 'omitting a priced lane is the saving being measured',
        );
        expect(receipt.truncated, isTrue);

        final decoded = CommitteeShadowReceipt.fromJson(
          jsonDecode(jsonEncode(receipt.toJson())),
        );
        expect(decoded, isNotNull);
        expect(decoded!.toJson(), receipt.toJson());

        for (final mutate in <void Function(Map<String, Object?>)>[
          (json) => json['version'] = 9,
          (json) => json['gateDisposition'] = 'ignored',
          (json) => (json['lanes']! as List)[0] = {'rubricId': 'x'},
          (json) => (json['actual']! as Map)['samples'] = [
            {'lane': 1},
          ],
          (json) => json['sampleId'] = '',
          (json) => (json['route']! as Map)['type'] = '',
          (json) => json['version'] = 1,
          (json) => json['preservedLanes'] = [
            {'rubricId': 'x'},
          ],
        ]) {
          final json =
              jsonDecode(jsonEncode(receipt.toJson())) as Map<String, Object?>;
          mutate(json);
          expect(CommitteeShadowReceipt.fromJson(json), isNull);
        }
      },
    );

    test('a route verdict is encoded by an EXHAUSTIVE switch', () {
      expect(committeeRouteTypeOf(const Advance()), 'advance');
      expect(committeeRouteTypeOf(const Rewind({'specify'}, 'why')), 'rewind');
      expect(committeeRouteTypeOf(const Escalate('hard block')), 'escalate');
      final rewind = committeeRouteObservationOf(
        const Rewind({'b', 'a'}, 'respec'),
        nodePath: 'pow-1/spec_review/route',
      );
      expect(rewind.payload['stepIds'], 'a,b');
      expect(rewind.reason, 'respec');
      expect(rewind.parentPath, 'pow-1/spec_review');
    });

    test('the file store round-trips a run and refuses a stale one', () {
      final dir = Directory.systemTemp.createTempSync('committee-store-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const store = FileCommitteeSelectionStore();
      final run = _run();
      store.writeRun(dir.path, run);
      expect(
        File(
          committeeSelectionRunPath(dir.path, CommitteeStage.codeReview),
        ).existsSync(),
        isTrue,
      );
      expect(
        store.readRun(dir.path, CommitteeStage.codeReview)!.toJson(),
        run.toJson(),
      );
      expect(store.readRun(dir.path, CommitteeStage.specReview), isNull);
      expect(
        run.isFreshFor(
          stage: CommitteeStage.codeReview,
          workBeadId: 'pow-1',
          round: 3,
        ),
        isTrue,
      );
      expect(
        run.isFreshFor(
          stage: CommitteeStage.codeReview,
          workBeadId: 'pow-1',
          round: 4,
        ),
        isFalse,
      );

      // NOTHING is written under `.grid/critique`, which verdict freshness owns.
      expect(
        Directory(p.join(dir.path, '.grid', 'critique')).existsSync(),
        isFalse,
      );

      store.writeReceipt(dir.path, _receipt());
      expect(
        File(
          committeeShadowReceiptPath(dir.path, _receipt().sampleId),
        ).existsSync(),
        isTrue,
      );

      // A corrupt artifact reads as "no run", never as a throw.
      File(
        committeeSelectionRunPath(dir.path, CommitteeStage.codeReview),
      ).writeAsStringSync('{');
      expect(store.readRun(dir.path, CommitteeStage.codeReview), isNull);
    });

    test('the file store reads the PREVIOUS round, strictly and read-only', () {
      final dir = Directory.systemTemp.createTempSync('committee-previous-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const store = FileCommitteeSelectionStore();
      CommitteeShadowReceipt? previous(int round, {String bead = 'pow-1'}) =>
          store.readPreviousReceipt(
            dir.path,
            stage: CommitteeStage.codeReview,
            workBeadId: bead,
            round: round,
          );

      expect(previous(3), isNull, reason: 'no receipt directory yet');
      for (final round in const [1, 2, 4]) {
        store.writeReceipt(dir.path, _receipt(round: round));
      }
      store.writeReceipt(dir.path, _receipt(round: 3, bead: 'pow-other'));
      // An unreadable and a version-skewed artifact are skipped, not half-read.
      final receipts = p.dirname(committeeShadowReceiptPath(dir.path, 'x'));
      File(p.join(receipts, 'corrupt.json')).writeAsStringSync('{');
      File(p.join(receipts, 'skewed.json')).writeAsStringSync(
        jsonEncode({..._receipt(round: 2).toJson(), 'version': 9}),
      );
      final before = Directory(receipts).listSync().length;

      expect(previous(3)!.run.round, 2, reason: 'greatest round BELOW 3');
      expect(previous(5)!.run.round, 4);
      expect(previous(1), isNull, reason: 'nothing precedes the first round');
      expect(previous(4, bead: 'pow-other')!.run.workBeadId, 'pow-other');
      expect(
        store.readPreviousReceipt(
          dir.path,
          stage: CommitteeStage.specReview,
          workBeadId: 'pow-1',
          round: 5,
        ),
        isNull,
        reason: 'another stage is another chain',
      );
      expect(
        Directory(receipts).listSync(),
        hasLength(before),
        reason: 'the read writes nothing',
      );
    });
  });

  group('replay', () {
    test('a version-2 receipt reclassifies to ITSELF, source-free', () {
      final base = _spec(
        intent: const ['title:i'],
        acceptance: const ['acceptance_criteria:a'],
        decisions: const [_emptyLookup],
      );
      final previous = _previous(
        base,
        grades: {'coherence': 'D'},
        respec: true,
      );
      final run = CommitteeSelectionRun(
        policyVersion: kCommitteeSelectionPolicyVersion,
        stage: CommitteeStage.specReview,
        workBeadId: 'pow-1',
        round: 3,
        nodePath: 'pow-1/spec_review/committee-selection',
        selection: _selectSpec(base, previous: previous),
        evidence: base,
        fullRubricIds: kSpecCommitteeRubrics,
        gatingRubricIds: const [kSpecGatingRubric],
        previous: previous,
      );
      final recorded = buildCommitteeShadowReceipt(
        run: run,
        route: CommitteeRouteObservation(
          nodePath: 'pow-1/spec_review/route',
          type: 'advance',
          payload: const {'verdict': 'advance'},
        ),
        lanes: [
          for (final id in kSpecCommitteeRubrics)
            CommitteeLaneReceipt.derive(
              rubricId: id,
              nodePath: 'pow-1/spec_review/$id',
              workBeadId: 'pow-1',
              routeType: 'advance',
              gating: id == kSpecGatingRubric,
              grade: 'B',
              transport: 'file',
            ),
        ],
      );
      expect(recorded.preservedLanes.map((lane) => lane.rubricId), [
        'decision-alignment',
        'acceptance-testability',
        'plan-completeness',
      ]);
      final decoded = CommitteeShadowReceipt.fromJson(
        jsonDecode(jsonEncode(recorded.toJson())),
      )!;
      expect(decoded.toJson(), recorded.toJson());
      expect(
        reclassifyCommitteeShadowReceipt(decoded).toJson(),
        recorded.toJson(),
      );
    });

    test(
      'reclassification re-derives the selection rather than trusting it',
      () {
        // A run whose recorded selection DISAGREES with its own evidence is
        // corrected — that is what makes drift visible.
        final honest = _receipt();
        final lying = buildCommitteeShadowReceipt(
          run: CommitteeSelectionRun(
            policyVersion: honest.run.policyVersion,
            stage: honest.run.stage,
            workBeadId: honest.run.workBeadId,
            round: honest.run.round,
            nodePath: honest.run.nodePath,
            evidence: honest.run.evidence,
            selection: kCommitteeSelectionPolicy.selectFullFallback(
              evidence: honest.run.evidence,
              fullRubricIds: honest.run.fullRubricIds,
              gatingRubricIds: honest.run.gatingRubricIds,
            ),
            fullRubricIds: honest.run.fullRubricIds,
            gatingRubricIds: honest.run.gatingRubricIds,
          ),
          route: honest.route,
          lanes: honest.lanes,
        );
        final corrected = reclassifyCommitteeShadowReceipt(lying);
        expect(corrected.selectedRubricIds, honest.selectedRubricIds);
        expect(
          corrected.run.selection.source,
          CommitteeSelectionSource.deterministic,
        );
        // The route observation is carried, never re-ruled.
        expect(corrected.route.toJson(), honest.route.toJson());
      },
    );

    test('a version-1 receipt still decodes and keeps its version-1 shape', () {
      final rows =
          jsonDecode(
                File(
                  p.join(
                    packageRoot(),
                    'test',
                    'fixtures',
                    'committee_selection_corpus.json',
                  ),
                ).readAsStringSync(),
              )
              as List<Object?>;
      final v1 = [
        for (final row in rows)
          if ((row! as Map)['version'] == 1) row,
      ];
      expect(v1, isNotEmpty);
      for (final row in v1) {
        final decoded = CommitteeShadowReceipt.fromJson(row);
        expect(decoded, isNotNull, reason: 'the corpus decodes STRICTLY');
        expect(decoded!.run.wireVersion, 1);
        expect(decoded.run.previous, isNull);
        expect(decoded.preservedLanes, isEmpty);
        expect(decoded.toJson(), row, reason: 'no version-2 field is invented');
        // Re-classification lifts it to policy 2 at the CURRENT wire version.
        final lifted = reclassifyCommitteeShadowReceipt(decoded);
        expect(lifted.run.wireVersion, kCommitteeSelectionWireVersion);
        expect(lifted.run.policyVersion, kCommitteeSelectionPolicyVersion);
        expect(
          lifted.run.selection.laneDecisions.map((d) => d.rubricId),
          decoded.run.fullRubricIds,
        );
      }
    });
  });

  group('source shape', () {
    final policySource = _libSource(
      p.join('src', 'code', 'committee_selection.dart'),
    );
    final evidenceSource = _libSource(
      p.join('src', 'code', 'committee_selection_evidence.dart'),
    );
    final barrel = _libSource('grid_assets.dart');

    test('the ONLY trajectory surface is the public barrel, value types', () {
      expect(
        policySource,
        contains("import 'package:grid_trajectory/grid_trajectory.dart'"),
      );
      expect(
        policySource,
        contains('show GateDisposition, LaneReport, UsageSample'),
      );
      for (final source in [policySource, evidenceSource]) {
        for (final forbidden in const [
          'grid_trajectory/src/connect',
          'grid_trajectory/src/ddl',
          'grid_trajectory/src/append',
          'grid_trajectory/src/fold',
          'TrajectoryDb',
          'TrajectoryAppender',
          'TrajectoryConnection',
          'mysql_client',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason:
                'D2: the second consumer takes the VALUE types only, so a '
                'later promotion never drags the store into grid_assets',
          );
        }
      }
      // No parallel vocabulary was minted beside the imported one.
      for (final minted in const [
        'CommitteeGateDisposition',
        'CommitteeLaneObservation',
        'CommitteeMetricTotals',
        'enum GateDisposition',
        'class LaneReport',
        'class UsageSample',
      ]) {
        expect(policySource, isNot(contains(minted)), reason: minted);
      }
      // The composition is real: the receipt types HOLD trajectory's values.
      expect(policySource, contains('final LaneReport report;'));
      expect(policySource, contains('final UsageSample usage;'));
      expect(policySource, contains('final GateDisposition? gateDisposition;'));
      expect(policySource, contains('final List<UsageSample> samples;'));
    });

    test(
      'the policy is typed Dart — no document, runner, watcher or reload',
      () {
        for (final forbidden in const [
          'Process.start',
          'Process.run',
          'Directory.watch',
          'runGrid',
          'loadYaml',
          'print(',
          'reloadPolicy',
          'package:yaml',
        ]) {
          expect(policySource, isNot(contains(forbidden)), reason: forbidden);
          expect(evidenceSource, isNot(contains(forbidden)), reason: forbidden);
        }
        // NO policy document exists on disk beside the library.
        for (final artifact in const [
          'lib/src/code/committee_selection.yaml',
          'lib/src/code/committee_selection.yml',
          'lib/src/code/committee_selection.md',
          'lib/src/code/committee_selection',
        ]) {
          expect(
            FileSystemEntity.typeSync(artifact),
            FileSystemEntityType.notFound,
            reason: 'the policy source of truth is the Dart library alone',
          );
        }
        // The rules live in the POLICY library, not elsewhere.
        for (final rule in CommitteeLaneRule.values) {
          expect(policySource, contains("'${rule.id}'"), reason: rule.id);
        }
        expect(
          evidenceSource,
          isNot(contains('CommitteeLaneRule')),
          reason: 'the adapter adapts facts; it never carries policy',
        );
        // Selection is DETERMINISTIC: no inference seam survives in it.
        for (final inference in const [
          'InferenceRunner',
          'RuntimeConfig',
          'spawnFor(',
          'resolveAgentConfig(',
          'AgentBrief(',
          'kCommitteeClassifierAllowlist',
          'parseCommitteeClassifierResult',
          'buildCommitteeClassifierPrompt',
        ]) {
          expect(policySource, isNot(contains(inference)), reason: inference);
        }
        // The policy library knows no committee: those arrive as VALUES.
        for (final coupling in const [
          "import 'discovery.dart'",
          "import 'committee.dart'",
          "import 'specify.dart'",
          "import 'docs_committee.dart'",
        ]) {
          expect(policySource, isNot(contains(coupling)), reason: coupling);
        }
        expect(barrel, contains("export 'src/code/committee_selection.dart';"));
        expect(
          barrel,
          contains("export 'src/code/committee_selection_evidence.dart';"),
        );
      },
    );

    test('the live circuits keep the selector OUT of every route join', () {
      final table =
          <
            ({
              Circuit circuit,
              List<String> full,
              List<String> gating,
              String stage,
            })
          >[
            (
              circuit: kSpecReviewCircuit,
              full: kSpecCommitteeRubrics,
              gating: const [kSpecGatingRubric],
              stage: 'spec_review',
            ),
            (
              circuit: kCodeReviewCircuit,
              full: kCommitteeRubrics,
              gating: kCodeGatingRubrics,
              stage: 'code_review',
            ),
            (
              circuit: kDocsReviewCircuit,
              full: kDocsCommitteeRubrics,
              gating: kDocsGatingRubrics,
              stage: 'code_review',
            ),
          ];
      for (final row in table) {
        final ids = row.circuit.steps.map((s) => s.stepId).toSet();
        expect(
          ids,
          containsAll(row.full),
          reason: 'no semantic lane is suppressed in ${row.circuit.id}',
        );
        expect(ids, contains(kCommitteeSelectionStep));
        final route =
            row.circuit.stepById(row.circuit.terminalStepId)! as CapabilityStep;
        expect(
          route.dependsOn,
          row.full.toSet(),
          reason: '${row.circuit.id} route joins the FULL committee',
        );
        expect(route.dependsOn, isNot(contains(kCommitteeSelectionStep)));
        expect(route.params[kCommitteeSelectionStageParam], row.stage);
        final selector =
            row.circuit.stepById(kCommitteeSelectionStep)! as CapabilityStep;
        expect(selector.capabilityId, kCommitteeSelectionStep);
        expect(selector.params[kCommitteeSelectionStageParam], row.stage);
        expect(selector.params[kCommitteeFullRubricsParam], row.full.join(','));
        expect(
          selector.params[kCommitteeGatingRubricsParam],
          row.gating.join(','),
        );
        // NOTHING in the circuit depends on the selector.
        for (final step in row.circuit.steps) {
          expect(
            step.dependsOn,
            isNot(contains(kCommitteeSelectionStep)),
            reason: '${step.stepId} must not wait for the cost optimizer',
          );
        }
      }
    });
  });
}

// ── fixtures ────────────────────────────────────────────────────────────────

DiscoveryAnchors _anchors({
  int round = 7,
  EvidenceState priorArtState = EvidenceState.complete,
  bool clipped = false,
}) => DiscoveryAnchors(
  round: round,
  workBeadId: 'pow-x',
  anchorsTruncated: clipped,
  beadFields: boundedBeadFields(
    bead('pow-x').copyWith(
      description: 'Extend the gather.',
      design: '## Touches\n- `lib/src/code/discovery.dart`\n',
      acceptanceCriteria: '- [ ] AC-1 — it works',
    ),
  ),
  anchors: [
    ResolvedAnchor(
      anchor: 'lib/src/code/discovery.dart',
      resolved: true,
      contents: boundDiscoveryEvidence(
        kind: 'code-anchor',
        subject: 'lib/src/code/discovery.dart',
        source: '/w/lib/src/code/discovery.dart',
        fullText: 'class AnchorsCapability {}',
      ),
    ),
  ],
  priorArtQueries: [
    PriorArtQueryEvidence(
      id: 'prior-art-query:AnchorsCapability@sha256:fake',
      query: 'AnchorsCapability',
      state: priorArtState,
      error: priorArtState == EvidenceState.failed ? 'boom' : '',
      hits: const [
        PriorArt(
          beadId: 'pow-96y',
          store: 'power_station',
          status: 'closed',
          title: 'the discovery circuit',
          field: 'description',
          snippet: 'a nested read-only gather',
          query: 'AnchorsCapability',
          evidenceId: 'prior-art-hit:pow-96y@sha256:fake',
        ),
      ],
    ),
  ],
  decisionEntries: {_a21.body.id: _a21},
  decisionLookups: [
    DecisionSurfaceEvidence(
      id: 'decision-surface:power_station/lib@sha256:fake',
      surface: 'power_station/lib/src/code/discovery.dart',
      command: 'lunar decisions index --surface power_station/lib',
      state: EvidenceState.complete,
      decisions: [_a21.body.id],
    ),
  ],
);

/// The gather-level decision index the fixture above references: ONE body,
/// carried once, whatever surface selects it.
final DecisionEntryEvidence _a21 = DecisionEntryEvidence(
  identity: 'power_station#a21',
  originRegister: 'power_station',
  originPath: 'docs/decisions',
  slug: 'a21',
  status: 'accepted',
  surfaces: const ['packages/**'],
  entryPath: 'docs/decisions/a21.md',
  body: boundDiscoveryEvidence(
    kind: 'decision-entry',
    subject: 'power_station#a21',
    source: 'docs/decisions/a21.md',
    fullText: 'a lens emits a REPORT, never a letter',
  ),
);

DiscoveryDossier _dossier() => DiscoveryDossier(
  anchors: _anchors(),
  workBeadId: 'pow-x',
  context: const [
    ContextNote(note: 'the gather already resolves this', source: 'lib/a.dart'),
  ],
  flags: const [
    DiscoveryFinding(
      kind: ViolationKind.pattern,
      standard: 'house style',
      quote: 'exhaustive switch',
      contradiction: 'a bare if-chain would drift',
    ),
  ],
);

CommitteeSelectionRun _run({int round = 3, String bead = 'pow-1'}) {
  // A TEST-ONLY diff: `regression-risk` (no runtime change) and
  // `spec-adherence` (test-only change) are the OMITTED lanes the sample
  // exists to measure.
  final evidence = _code(
    changedPaths: const ['test/a_test.dart'],
    intent: const ['title:i'],
    acceptance: const ['acceptance_criteria:a'],
    truncated: true,
    round: round,
  );
  return CommitteeSelectionRun(
    policyVersion: kCommitteeSelectionPolicyVersion,
    stage: CommitteeStage.codeReview,
    workBeadId: bead,
    round: round,
    nodePath: 'pow-1/review/committee-selection',
    evidence: evidence,
    selection: _selectCode(evidence),
    fullRubricIds: kCommitteeRubrics,
    gatingRubricIds: kCodeGatingRubrics,
  );
}

/// A previous spec round over [evidence]: every lane graded `A` unless
/// [grades] says otherwise (a null grade is a lane that recorded none), and a
/// respec stamp on the route when [respec].
CommitteePreviousRound _previous(
  CommitteeSelectionEvidence evidence, {
  Map<String, String?> grades = const {},
  bool respec = false,
}) {
  final route = CommitteeRouteObservation(
    nodePath: 'pow-1/spec_review/route',
    type: 'advance',
    payload: respec
        ? const {'verdict': 'respec', 'grade': 'F', 'rule': 'respec'}
        : const {'verdict': 'advance'},
  );
  final lanes = [
    for (final id in kSpecCommitteeRubrics)
      CommitteeLaneReceipt.derive(
        rubricId: id,
        nodePath: 'pow-1/spec_review/$id',
        workBeadId: 'pow-1',
        routeType: route.type,
        gating: id == kSpecGatingRubric,
        grade: grades.containsKey(id) ? grades[id] : 'A',
        transport: 'file',
      ),
  ];
  return CommitteePreviousRound(
    round: 2,
    evidence: evidence,
    route: route,
    actionLaneIds: [
      for (final lane in lanes)
        if (kCommitteeActionGrades.contains(lane.grade)) lane.rubricId,
    ],
    lanes: lanes,
  );
}

CommitteeShadowReceipt _receipt({int round = 3, String bead = 'pow-1'}) {
  final run = _run(round: round, bead: bead);
  final observation = committeeRouteObservationOf(
    const Advance({'verdict': 'advance', 'fix_in_flight_finding': 'name it'}),
    nodePath: 'pow-1/review/route',
  );
  const costs = {
    kGatingRubric: 0.0,
    kDeclaredTestsRubric: 0.0,
    'spec-adherence': 0.5,
    'regression-risk': 0.49,
    'test-coverage': 0.51,
  };
  const grades = {
    kGatingRubric: 'A',
    kDeclaredTestsRubric: 'A',
    'spec-adherence': 'B',
    'regression-risk': 'D',
    'test-coverage': 'A',
  };
  return buildCommitteeShadowReceipt(
    run: run,
    route: observation,
    lanes: [
      for (final rubricId in kCommitteeRubrics)
        CommitteeLaneReceipt.derive(
          rubricId: rubricId,
          nodePath: 'pow-1/review/$rubricId',
          workBeadId: 'pow-1',
          routeType: observation.type,
          gating: kCodeGatingRubrics.contains(rubricId),
          grade: grades[rubricId],
          transport: 'file',
          rationale: 'lane $rubricId',
          finding: observation.payload['fix_in_flight_finding'],
          model: kCodeGatingRubrics.contains(rubricId) ? null : 'sonnet',
          tokensIn: kCodeGatingRubrics.contains(rubricId) ? null : 1000,
          tokensOut: kCodeGatingRubrics.contains(rubricId) ? null : 100,
          costUsd: costs[rubricId],
          premiumRequests: kCodeGatingRubrics.contains(rubricId) ? null : 0,
          numTurns: kCodeGatingRubrics.contains(rubricId) ? null : 3,
          durationMs: 1000,
        ),
    ],
  );
}

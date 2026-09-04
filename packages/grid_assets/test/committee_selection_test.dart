// The SHADOW committee-selection policy (bead `pow-1nl.1.1`) — the PURE half.
//
// Five named tables, each addressable with `--plain-name`:
//
//  - `policy tables`        the eight deterministic rules, their additive union,
//                           the unconditional gates, the roster ordering and the
//                           closed classifier allowlist;
//  - `stage evidence`       the two stages' independent evidence, their digests
//                           and every lane's input digest;
//  - `shadow receipt`       the strict codecs over trajectory's own value types,
//                           null-versus-zero, and the counterfactual accounting;
//  - `retained corpus replay` the retained typed samples, replayed through pure
//                           Dart with the inference and source Fakes untouched;
//  - `source shape`         the architecture fences.
//
// Fakes, not mocks. Zero inference; the only I/O is a temp dir for the evidence
// source's own read path and the source-shape test's file reads.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart' show bead;
import 'package:grid_trajectory/grid_trajectory.dart'
    show GateDisposition, LaneReport, UsageSample;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

CommitteeSelection _selectSpec(CommitteeSelectionEvidence evidence) =>
    _policy.selectDeterministic(
      evidence: evidence,
      fullRubricIds: kSpecCommitteeRubrics,
      gatingRubricIds: const [kSpecGatingRubric],
    );

CommitteeSelection _selectCode(CommitteeSelectionEvidence evidence) =>
    _policy.selectDeterministic(
      evidence: evidence,
      fullRubricIds: kCommitteeRubrics,
      gatingRubricIds: kCodeGatingRubrics,
    );

void main() {
  group('policy tables', () {
    test('every authored rule id is reachable and stage-scoped', () {
      expect(CommitteeSelectionRule.values.map((r) => r.id), [
        'spec-intent',
        'spec-decisions',
        'spec-acceptance',
        'spec-surface',
        'code-runtime',
        'code-tests',
        'code-docs-metadata',
        'code-decision-sensitive',
      ]);
      expect(_policy.rulesFor(CommitteeStage.specReview).map((r) => r.id), [
        'spec-intent',
        'spec-decisions',
        'spec-acceptance',
        'spec-surface',
      ]);
      expect(_policy.rulesFor(CommitteeStage.codeReview).map((r) => r.id), [
        'code-runtime',
        'code-tests',
        'code-docs-metadata',
        'code-decision-sensitive',
      ]);
      // Every rule id round-trips, so a persisted match is decodable.
      for (final rule in CommitteeSelectionRule.values) {
        expect(CommitteeSelectionRule.fromId(rule.id), rule);
      }
      expect(CommitteeSelectionRule.fromId('no-such-rule'), isNull);
    });

    test('each spec rule fires ALONE on exactly its own evidence', () {
      final table =
          <({String rule, CommitteeSelectionEvidence evidence, String lane})>[
            (
              rule: 'spec-intent',
              evidence: _spec(intent: ['i']),
              lane: 'coherence',
            ),
            (
              rule: 'spec-acceptance',
              evidence: _spec(acceptance: ['a']),
              lane: 'acceptance-testability',
            ),
            (
              rule: 'spec-surface',
              evidence: _spec(paths: ['lib/a.dart|true|d']),
              lane: 'plan-completeness',
            ),
            (
              rule: 'spec-surface',
              evidence: _spec(priorArt: ['hit:x']),
              lane: 'plan-completeness',
            ),
          ];
      for (final row in table) {
        final selection = _selectSpec(row.evidence);
        expect(selection.matchedRuleIds, [row.rule], reason: row.rule);
        expect(
          selection.selectedRubricIds,
          [kSpecGatingRubric, row.lane],
          reason: '${row.rule} selects its lane plus the unconditional gate',
        );
        expect(selection.source, CommitteeSelectionSource.deterministic);
      }
      // `spec-decisions` fires on decision evidence and selects its own lane.
      final decisions = _selectSpec(_spec(decisions: ['surface:x|complete|1']));
      expect(decisions.matchedRuleIds, ['spec-decisions']);
      expect(decisions.selectedRubricIds, [
        kSpecGatingRubric,
        'decision-alignment',
      ]);
    });

    test('spec matches are ADDITIVE and return in ROSTER order', () {
      final selection = _selectSpec(
        _spec(
          intent: ['i'],
          acceptance: ['a'],
          decisions: ['d'],
          paths: ['lib/a.dart|true|x'],
        ),
      );
      expect(selection.matchedRuleIds, [
        'spec-intent',
        'spec-decisions',
        'spec-acceptance',
        'spec-surface',
      ]);
      expect(
        selection.selectedRubricIds,
        kSpecCommitteeRubrics,
        reason: 'four matches union to the whole roster, in DECLARATION order',
      );
    });

    test('code rules read the change SHAPE, additively', () {
      final runtime = _selectCode(
        _code(changedPaths: const ['lib/src/code/committee.dart']),
      );
      expect(runtime.matchedRuleIds, ['code-runtime']);
      expect(runtime.selectedRubricIds, [
        ...kCodeGatingRubrics,
        'spec-adherence',
        'regression-risk',
        'test-coverage',
      ]);

      final tests = _selectCode(
        _code(changedPaths: const ['test/committee_selection_test.dart']),
      );
      expect(
        tests.matchedRuleIds,
        ['code-tests'],
        reason: 'a test-only diff has no runtime behaviour to regress',
      );
      expect(tests.selectedRubricIds, [
        ...kCodeGatingRubrics,
        'spec-adherence',
        'test-coverage',
      ]);

      final prose = _selectCode(
        _code(
          changedPaths: const ['README.md', 'pubspec.yaml', 'CHANGELOG.md'],
        ),
      );
      expect(prose.matchedRuleIds, ['code-docs-metadata']);
      expect(prose.selectedRubricIds, [
        ...kCodeGatingRubrics,
        'spec-adherence',
      ]);

      // ONE runtime path among prose defeats the all-prose rule and adds the
      // full semantic set beside the test lane.
      final mixed = _selectCode(
        _code(
          changedPaths: const [
            'README.md',
            'lib/src/code/committee.dart',
            'test/committee_test.dart',
          ],
        ),
      );
      expect(mixed.matchedRuleIds, ['code-runtime', 'code-tests']);
      expect(mixed.selectedRubricIds, kCommitteeRubrics);

      // Decision evidence widens the blast radius of an otherwise prose diff.
      final sensitive = _selectCode(
        _code(changedPaths: const ['docs/x.md'], decisions: const ['d']),
      );
      expect(sensitive.matchedRuleIds, [
        'code-docs-metadata',
        'code-decision-sensitive',
      ]);
      expect(sensitive.selectedRubricIds, [
        ...kCodeGatingRubrics,
        'spec-adherence',
        'regression-risk',
      ]);
    });

    test('the path predicates classify nested and extension-free shapes', () {
      expect(isCommitteeTestPath('test/a_test.dart'), isTrue);
      expect(isCommitteeTestPath('packages/x/test/a.dart'), isTrue);
      expect(isCommitteeTestPath('lib/src/a_test.dart'), isTrue);
      expect(isCommitteeTestPath('lib/src/a.dart'), isFalse);
      expect(isCommitteeProseOrMetadataPath('LICENSE'), isTrue);
      expect(isCommitteeProseOrMetadataPath('packages/x/CHANGELOG.md'), isTrue);
      expect(isCommitteeProseOrMetadataPath('packages/x/pubspec.yaml'), isTrue);
      expect(isCommitteeProseOrMetadataPath('tool/config.json'), isTrue);
      expect(isCommitteeProseOrMetadataPath('lib/a.dart'), isFalse);
      expect(isCommitteeRuntimePath('lib/a.dart'), isTrue);
      expect(isCommitteeRuntimePath('test/a_test.dart'), isFalse);
      expect(isCommitteeRuntimePath('README.md'), isFalse);
    });

    test('EVERY gate set is unconditional, in all three committees', () {
      // No rule can fire on empty evidence, yet the gates are still selected.
      for (final row in <({List<String> full, List<String> gating})>[
        (full: kSpecCommitteeRubrics, gating: const [kSpecGatingRubric]),
        (full: kCommitteeRubrics, gating: kCodeGatingRubrics),
        (full: kDocsCommitteeRubrics, gating: kDocsGatingRubrics),
      ]) {
        final stage = row.full == kSpecCommitteeRubrics
            ? CommitteeStage.specReview
            : CommitteeStage.codeReview;
        final evidence = CommitteeSelectionEvidence(
          stage: stage,
          workBeadId: 'pow-1',
          round: 1,
        );
        final selection = _policy.selectDeterministic(
          evidence: evidence,
          fullRubricIds: row.full,
          gatingRubricIds: row.gating,
        );
        expect(selection.matchedRuleIds, isEmpty);
        expect(selection.selectedRubricIds, row.gating);
        // The FULL FALLBACK is the whole roster, in declaration order.
        expect(
          _policy
              .selectFullFallback(
                evidence: evidence,
                fullRubricIds: row.full,
                gatingRubricIds: row.gating,
              )
              .selectedRubricIds,
          row.full,
        );
      }
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

    test('the classifier allowlist is CLOSED and rejection is WHOLE', () {
      const active = ['spec-adherence', 'regression-risk', 'test-coverage'];

      final ok = parseCommitteeClassifierResult(
        '{"rubricIds":["test-coverage","spec-adherence","spec-adherence"]}',
        activeSemanticRubricIds: active,
      );
      expect(ok.kind, CommitteeClassifierResultKind.selected);
      expect(ok.rubricIds, [
        'spec-adherence',
        'test-coverage',
      ], reason: 'deduplicated and reordered by the ACTIVE committee');

      // An id outside the allowlist rejects the WHOLE answer — the legal ids in
      // it are NOT quietly kept.
      final unknown = parseCommitteeClassifierResult(
        '{"rubricIds":["spec-adherence","vibes"]}',
        activeSemanticRubricIds: active,
      );
      expect(unknown.kind, CommitteeClassifierResultKind.unknown);
      expect(unknown.rubricIds, isEmpty);
      expect(unknown.rejectedRubricIds, ['spec-adherence', 'vibes']);

      // An allowlisted id that this committee does not run is equally unknown.
      final offRoster = parseCommitteeClassifierResult(
        '{"rubricIds":["coherence"]}',
        activeSemanticRubricIds: active,
      );
      expect(offRoster.kind, CommitteeClassifierResultKind.unknown);

      for (final blank in <String?>[null, '', '   ']) {
        expect(
          parseCommitteeClassifierResult(
            blank,
            activeSemanticRubricIds: active,
          ).kind,
          CommitteeClassifierResultKind.missing,
        );
      }
      for (final bad in const [
        'not json',
        '[]',
        '{"rubricIds":[]}',
        '{"rubricIds":"spec-adherence"}',
        '{"rubricIds":["spec-adherence"],"extra":1}',
        '{"rubricIds":["  "]}',
        '{"rubricIds":[7]}',
      ]) {
        expect(
          parseCommitteeClassifierResult(
            bad,
            activeSemanticRubricIds: active,
          ).kind,
          CommitteeClassifierResultKind.malformed,
          reason: bad,
        );
      }
      // NO arm is ever a grade.
      expect(
        kCommitteeClassifierAllowlist.intersection(const {'A', 'D', 'F'}),
        isEmpty,
      );
    });

    test('a classifier answer never invents a lane the committee lacks', () {
      final selection = _policy.selectFromClassifier(
        evidence: _code(changedPaths: const []),
        fullRubricIds: kDocsCommitteeRubrics,
        gatingRubricIds: kDocsGatingRubrics,
        // `regression-risk` is allowlisted but the DOCS committee does not run
        // it, so composition drops it while the gates stay.
        classifierRubricIds: const ['spec-adherence', 'regression-risk'],
      );
      expect(selection.source, CommitteeSelectionSource.classifier);
      expect(selection.selectedRubricIds, kDocsCommitteeRubrics);
      expect(selection.matchedRuleIds, isEmpty);
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
          'acceptance-testability',
          'coherence',
          'plan-completeness',
          'spec-adherence',
          'spec-validation',
        ],
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
        (json) => json['version'] = 2,
        (json) => json['stage'] = 'design_review',
        (json) => json['round'] = -1,
        (json) => (json['selection']! as Map)['source'] = 'guessing',
        (json) => (json['evidence']! as Map)['stage'] = 'nope',
        (json) => (json['attempts']! as List)[0] = {'attempt': 1},
        (json) => json['policyVersion'] = '',
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
          'spec-adherence',
          'test-coverage',
        ]);
        expect(
          receipt.omittedRubricIds,
          ['regression-risk'],
          reason: 'the hypothetical omission is the whole point of the sample',
        );
        expect(receipt.actionLaneIds, ['regression-risk']);
        expect(receipt.route.type, 'advance');
        expect(receipt.gateDisposition, GateDisposition.overridden);
        expect(receipt.lanes, hasLength(kCommitteeRubrics.length));
        expect(receipt.run.selection.laneInputDigests.keys, kCommitteeRubrics);
        expect(receipt.downstreamJoinKeys['workBeadId'], 'pow-1');
        expect(receipt.downstreamJoinKeys['siblingScope'], 'pow-1/review/');
        expect(receipt.sampleId, hasLength(64));
        expect(receipt.joinId, hasLength(64));

        // The counterfactual EXCLUDES the omitted lane and INCLUDES the
        // classifier attempts; the actual excludes the classifier.
        expect(receipt.actual.contributingRunIds, kCommitteeRubrics);
        expect(receipt.counterfactual.contributingRunIds, [
          ...receipt.selectedRubricIds,
          'classifier-attempt-1',
        ]);
        expect(receipt.classifier.contributingRunIds, ['classifier-attempt-1']);
        expect(receipt.actual.costUsd, closeTo(1.5, 1e-9));
        expect(receipt.counterfactual.costUsd, closeTo(1.02, 1e-9));
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
  });

  group('retained corpus replay', () {
    test('every retained sample reproduces itself, source-free', () {
      final rows =
          jsonDecode(
                File(
                  'test/fixtures/committee_selection_corpus.json',
                ).readAsStringSync(),
              )
              as List<Object?>;
      expect(rows, hasLength(2));
      for (final row in rows) {
        final recorded = CommitteeShadowReceipt.fromJson(row);
        expect(recorded, isNotNull, reason: 'the corpus decodes STRICTLY');
        final replayed = replayCommitteeShadowReceipt(recorded!);
        expect(replayed.toJson(), recorded.toJson());
        expect(replayed.sampleId, recorded.sampleId);
        expect(replayed.joinId, recorded.joinId);
        expect(
          replayed.run.selection.selectedRubricIds,
          recorded.run.selection.selectedRubricIds,
        );
        expect(replayed.omittedRubricIds, recorded.omittedRubricIds);
        expect(
          replayed.counterfactual.costUsd,
          recorded.counterfactual.costUsd,
        );
      }
      // The corpus covers BOTH provenances, and the fallback sample omits
      // nothing (that is what a full fallback means).
      final sources = [
        for (final row in rows)
          CommitteeShadowReceipt.fromJson(row)!.run.selection.source,
      ];
      expect(sources, [
        CommitteeSelectionSource.deterministic,
        CommitteeSelectionSource.fullFallback,
      ]);
      final fallback = CommitteeShadowReceipt.fromJson(rows.last)!;
      expect(fallback.omittedRubricIds, isEmpty);
      expect(fallback.run.attempts, hasLength(2));
      expect(fallback.run.attempts.map((a) => a.kind), [
        CommitteeClassifierResultKind.malformed,
        CommitteeClassifierResultKind.unknown,
      ]);
      // Replay is a PURE function of the receipt: it takes no evidence source
      // and no classifier, so there is nothing for it to read. The control is
      // that MUTATING the recorded evidence moves the replayed selection —
      // which it could not do if replay consulted anything else.
      final recorded = CommitteeShadowReceipt.fromJson(rows.first)!;
      final rewritten = CommitteeSelectionRun(
        policyVersion: recorded.run.policyVersion,
        stage: recorded.run.stage,
        workBeadId: recorded.run.workBeadId,
        round: recorded.run.round,
        nodePath: recorded.run.nodePath,
        // Add DECISION evidence the sample did not have: `spec-decisions` must
        // now fire and `decision-alignment` must stop being omitted.
        evidence: CommitteeSelectionEvidence(
          stage: recorded.run.evidence.stage,
          workBeadId: recorded.run.evidence.workBeadId,
          round: recorded.run.evidence.round,
          intent: recorded.run.evidence.intent,
          acceptance: recorded.run.evidence.acceptance,
          decisions: const ['surface:power_station/lib|complete|1'],
        ),
        selection: recorded.run.selection,
        fullRubricIds: recorded.run.fullRubricIds,
        gatingRubricIds: recorded.run.gatingRubricIds,
        attempts: recorded.run.attempts,
      );
      expect(replayCommitteeSelectionRun(rewritten).selection.matchedRuleIds, [
        'spec-intent',
        'spec-decisions',
        'spec-acceptance',
      ]);
      expect(
        replayCommitteeSelectionRun(rewritten).selection.selectedRubricIds,
        contains('decision-alignment'),
      );
      expect(
        recorded.omittedRubricIds,
        contains('decision-alignment'),
        reason:
            'the RECORDED sample omitted it — the mutation is what moved it',
      );
    });

    test('replay re-derives the selection rather than trusting it', () {
      // A run whose recorded selection DISAGREES with its own evidence is
      // corrected by replay — that is what makes drift visible.
      final honest = _run();
      final lying = CommitteeSelectionRun(
        policyVersion: honest.policyVersion,
        stage: honest.stage,
        workBeadId: honest.workBeadId,
        round: honest.round,
        nodePath: honest.nodePath,
        evidence: honest.evidence,
        selection: kCommitteeSelectionPolicy.selectFullFallback(
          evidence: honest.evidence,
          fullRubricIds: honest.fullRubricIds,
          gatingRubricIds: honest.gatingRubricIds,
        ),
        fullRubricIds: honest.fullRubricIds,
        gatingRubricIds: honest.gatingRubricIds,
        attempts: honest.attempts,
      );
      expect(
        replayCommitteeSelectionRun(lying).selection.selectedRubricIds,
        honest.selection.selectedRubricIds,
      );
      expect(
        replayCommitteeSelectionRun(lying).selection.source,
        CommitteeSelectionSource.deterministic,
      );
    });
  });

  group('source shape', () {
    final policySource = File(
      'lib/src/code/committee_selection.dart',
    ).readAsStringSync();
    final evidenceSource = File(
      'lib/src/code/committee_selection_evidence.dart',
    ).readAsStringSync();
    final barrel = File('lib/grid_assets.dart').readAsStringSync();

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
        // The rules and the constants live in the POLICY library, not elsewhere.
        for (final rule in CommitteeSelectionRule.values) {
          expect(policySource, contains("'${rule.id}'"), reason: rule.id);
        }
        expect(policySource, contains('kCommitteeClassifierAllowlist'));
        expect(
          evidenceSource,
          isNot(contains('CommitteeSelectionRule')),
          reason: 'the adapter adapts facts; it never carries policy',
        );
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
  decisionLookups: [
    DecisionSurfaceEvidence(
      id: 'decision-surface:power_station/lib@sha256:fake',
      surface: 'power_station/lib/src/code/discovery.dart',
      command: 'lunar decisions index --surface power_station/lib',
      state: EvidenceState.complete,
      decisions: [
        DecisionEntryEvidence(
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
        ),
      ],
    ),
  ],
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

CommitteeSelectionRun _run() {
  // A TEST-ONLY diff: `code-tests` fires and `code-runtime` does not, so
  // `regression-risk` is the OMITTED lane the sample exists to measure.
  final evidence = _code(
    changedPaths: const ['test/a_test.dart'],
    intent: const ['title:i'],
    acceptance: const ['acceptance_criteria:a'],
    truncated: true,
  );
  return CommitteeSelectionRun(
    policyVersion: kCommitteeSelectionPolicyVersion,
    stage: CommitteeStage.codeReview,
    workBeadId: 'pow-1',
    round: 3,
    nodePath: 'pow-1/review/committee-selection',
    evidence: evidence,
    selection: _selectCode(evidence),
    fullRubricIds: kCommitteeRubrics,
    gatingRubricIds: kCodeGatingRubrics,
    attempts: [
      CommitteeClassifierAttempt(
        attempt: 1,
        kind: CommitteeClassifierResultKind.selected,
        usage: const UsageSample(
          lane: kCommitteeSelectionStep,
          beadId: 'pow-1',
          fromFallback: false,
          costUsd: 0.01,
          durationMs: 400,
        ),
        acceptedRubricIds: const ['spec-adherence'],
        outputDigest: 'a' * 64,
        launched: true,
        model: 'haiku',
        tokensIn: 900,
        tokensOut: 40,
        costUsd: 0.01,
        premiumRequests: 0,
        numTurns: 1,
        harnessDurationMs: 400,
      ),
    ],
  );
}

CommitteeShadowReceipt _receipt() {
  final run = _run();
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

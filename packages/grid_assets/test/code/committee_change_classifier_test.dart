// The deterministic per-run committee classifier (bead `pow-1d2x`) — the
// acceptance probes, each addressable with `--plain-name`:
//
//  - `docs test and decision shapes`         a docs-only, metadata-only,
//                                            test-only, mixed or runtime diff
//                                            elects only the lanes it can
//                                            exercise; a spec citing no decision
//                                            elects no decision-alignment lane,
//                                            and a FAILED lookup falls back;
//  - `unchanged acceptance skips regrade`    a later graded spec round with
//                                            byte-identical acceptance evidence
//                                            omits acceptance-testability, gates
//                                            retained;
//  - `targeted respec preserves sibling verdicts`
//                                            a respec round elects exactly the
//                                            prior action lanes plus the gates,
//                                            and its receipt carries the prior
//                                            verdicts of every omitted sibling;
//  - `retained corpus measures selectivity`  the checked-in shadow corpus —
//                                            twelve receipts retained verbatim
//                                            from real rounds — replayed
//                                            chronologically, is selective on
//                                            exactly one round, each omission
//                                            named, with no effect of any kind.
//
// Pure Dart over hand-built values and one checked-in fixture. Fakes, not
// mocks; no process, no model, no working-directory mutation.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

const _policy = kCommitteeSelectionPolicy;

/// The retained shadow receipts checked in as the corpus fixture.
const kRetainedCorpusRounds = 12;

/// The retained rounds on which policy v2 omits at least one lane.
const kRetainedCorpusSelectiveRounds = 1;

const _cited = 'decision:decision-entry:power_station#a21@sha256:fake';
const _emptyLookup = 'surface:power_station/lib|complete|decision-surface:x';

CommitteeSelectionEvidence _code(List<String> changedPaths) =>
    CommitteeSelectionEvidence(
      stage: CommitteeStage.codeReview,
      workBeadId: 'pow-1',
      round: 1,
      intent: const ['title:i'],
      changedPaths: changedPaths,
      pinnedDiffDigest: 'sha-of-the-pinned-diff',
    );

CommitteeSelectionEvidence _spec({
  List<String> intent = const ['title:i'],
  List<String> acceptance = const ['acceptance_criteria:a'],
  List<String> decisions = const [_emptyLookup],
  List<String> missing = const [],
  int round = 1,
}) => CommitteeSelectionEvidence(
  stage: CommitteeStage.specReview,
  workBeadId: 'pow-1',
  round: round,
  intent: intent,
  acceptance: acceptance,
  decisions: decisions,
  missingEvidenceIds: missing,
);

CommitteeSelection _classifyCode(List<String> changedPaths) => _policy.classify(
  evidence: _code(changedPaths),
  fullRubricIds: kCommitteeRubrics,
  gatingRubricIds: kCodeGatingRubrics,
);

CommitteeSelection _classifySpec(
  CommitteeSelectionEvidence evidence, {
  CommitteePreviousRound? previous,
}) => _policy.classify(
  evidence: evidence,
  fullRubricIds: kSpecCommitteeRubrics,
  gatingRubricIds: const [kSpecGatingRubric],
  previous: previous,
);

List<String> _omitted(CommitteeSelection selection) => [
  for (final decision in selection.laneDecisions)
    if (!decision.elected) decision.rubricId,
];

String _ruleOf(CommitteeSelection selection, String rubricId) =>
    selection.decisionFor(rubricId)!.rule.id;

/// One graded spec round over [evidence], routed [routePayload]: every lane
/// `A` unless [grades] says otherwise.
CommitteeShadowReceipt _gradedSpecRound(
  CommitteeSelectionEvidence evidence, {
  Map<String, String> grades = const {},
  Map<String, String> routePayload = const {'verdict': 'advance'},
  CommitteeShadowReceipt? previous,
  String transport = 'file',
}) {
  final prior = previous == null
      ? null
      : CommitteePreviousRound.fromReceipt(previous);
  final run = CommitteeSelectionRun(
    policyVersion: _policy.policyVersion,
    stage: CommitteeStage.specReview,
    workBeadId: 'pow-1',
    round: evidence.round,
    nodePath: 'pow-1/spec_review/committee-selection',
    selection: _classifySpec(evidence, previous: prior),
    evidence: evidence,
    fullRubricIds: kSpecCommitteeRubrics,
    gatingRubricIds: const [kSpecGatingRubric],
    previous: prior,
  );
  return buildCommitteeShadowReceipt(
    run: run,
    route: CommitteeRouteObservation(
      nodePath: 'pow-1/spec_review/route',
      type: 'advance',
      payload: routePayload,
    ),
    lanes: [
      for (final id in kSpecCommitteeRubrics)
        CommitteeLaneReceipt.derive(
          rubricId: id,
          nodePath: 'pow-1/spec_review/$id',
          workBeadId: 'pow-1',
          routeType: 'advance',
          gating: id == kSpecGatingRubric,
          grade: grades[id] ?? 'A',
          transport: transport,
          rationale: 'round ${evidence.round} lane $id',
          model: id == kSpecGatingRubric ? null : 'sonnet',
          costUsd: id == kSpecGatingRubric ? 0 : 0.3,
          durationMs: 1000,
        ),
    ],
  );
}

void main() {
  test('docs test and decision shapes', () {
    // A DOCS-ONLY diff has nothing to regress and nothing to cover.
    final docs = _classifyCode(const ['docs/guide.md', 'README.md']);
    expect(_omitted(docs), ['regression-risk', 'test-coverage']);
    expect(_ruleOf(docs, 'regression-risk'), 'no-runtime-change');
    expect(_ruleOf(docs, 'test-coverage'), 'no-test-change');
    expect(_ruleOf(docs, 'spec-adherence'), 'metadata-change');

    // METADATA-ONLY is the same shape as docs.
    final metadata = _classifyCode(const ['pubspec.yaml', 'CHANGELOG.md']);
    expect(_omitted(metadata), ['regression-risk', 'test-coverage']);

    // A TEST-ONLY diff elects coverage and nothing else semantic.
    final tests = _classifyCode(const ['test/a_test.dart']);
    expect(_omitted(tests), ['spec-adherence', 'regression-risk']);
    expect(_ruleOf(tests, 'spec-adherence'), 'test-only-change');
    expect(_ruleOf(tests, 'regression-risk'), 'no-runtime-change');
    expect(_ruleOf(tests, 'test-coverage'), 'test-change');

    // MIXED metadata + tests elects both non-runtime lanes, never regression.
    final mixed = _classifyCode(const ['README.md', 'test/a_test.dart']);
    expect(_omitted(mixed), ['regression-risk']);

    // ANY runtime path elects every semantic code lane.
    final runtime = _classifyCode(const ['README.md', 'lib/src/a.dart']);
    expect(_omitted(runtime), isEmpty);
    expect(runtime.selectedRubricIds, kCommitteeRubrics);

    // Every code shape keeps the deterministic gates.
    for (final selection in [docs, metadata, tests, mixed, runtime]) {
      expect(selection.selectedRubricIds, containsAll(kCodeGatingRubrics));
      for (final gate in kCodeGatingRubrics) {
        expect(_ruleOf(selection, gate), 'gate-always');
      }
    }

    // A spec whose COMPLETE lookup names no decision elects no
    // decision-alignment lane; a cited decision or departure elects it.
    final uncited = _classifySpec(_spec());
    expect(_omitted(uncited), ['decision-alignment']);
    expect(_ruleOf(uncited, 'decision-alignment'), 'no-cited-decision');
    expect(
      _ruleOf(
        _classifySpec(_spec(decisions: const [_emptyLookup, _cited])),
        'decision-alignment',
      ),
      'cited-decision',
    );
    expect(
      _ruleOf(
        _classifySpec(_spec(decisions: const ['departure:abc'])),
        'decision-alignment',
      ),
      'cited-decision',
    );

    // A FAILED or unavailable lookup is not an empty result: full fallback.
    final failed = _classifySpec(
      _spec(missing: const ['decisions:power_station/lib']),
    );
    expect(failed.source, CommitteeSelectionSource.fullFallback);
    expect(failed.selectedRubricIds, kSpecCommitteeRubrics);
    expect(_ruleOf(failed, 'decision-alignment'), 'full-fallback');

    // A FIRST graded round elects coherence, testability and completeness.
    for (final lane in const [
      'coherence',
      'acceptance-testability',
      'plan-completeness',
    ]) {
      expect(_ruleOf(uncited, lane), 'first-round');
    }
    expect(_ruleOf(uncited, kSpecGatingRubric), 'gate-always');
  });

  test('unchanged acceptance skips regrade', () {
    final first = _gradedSpecRound(
      _spec(decisions: const [_emptyLookup, _cited]),
      routePayload: const {'verdict': 'advance'},
    );
    // The design moved, the acceptance criteria did not.
    final later = _classifySpec(
      _spec(
        intent: const ['title:i', 'design:rewritten'],
        decisions: const [_emptyLookup, _cited],
        round: 2,
      ),
      previous: CommitteePreviousRound.fromReceipt(first),
    );
    expect(_omitted(later), ['acceptance-testability']);
    expect(_ruleOf(later, 'acceptance-testability'), 'acceptance-unchanged');
    expect(_ruleOf(later, 'coherence'), 'facts-changed');
    expect(_ruleOf(later, 'plan-completeness'), 'facts-changed');
    expect(_ruleOf(later, 'decision-alignment'), 'facts-changed');
    expect(later.selectedRubricIds, contains(kSpecGatingRubric));
    expect(_ruleOf(later, kSpecGatingRubric), 'gate-always');

    // ONE changed acceptance byte re-elects the lane.
    final edited = _classifySpec(
      _spec(
        acceptance: const ['acceptance_criteria:a2'],
        decisions: const [_emptyLookup, _cited],
        round: 2,
      ),
      previous: CommitteePreviousRound.fromReceipt(first),
    );
    expect(_ruleOf(edited, 'acceptance-testability'), 'facts-changed');
  });

  test('targeted respec preserves sibling verdicts', () {
    final evidence = _spec(decisions: const [_emptyLookup, _cited]);
    // ROUND 1: plan-completeness returns an action grade, siblings pass, and
    // the route stamps the invalidating respec grade.
    final first = _gradedSpecRound(
      evidence,
      grades: const {'coherence': 'B', 'plan-completeness': 'D'},
      routePayload: const {'verdict': 'respec', 'grade': 'F', 'rule': 'respec'},
      transport: 'file',
    );
    expect(first.actionLaneIds, ['plan-completeness']);

    // ROUND 2: the respecced spec — the full committee still runs in shadow
    // (its round-2 observation uses another transport), but the selection is
    // the gate plus the ONE action lane.
    final second = _gradedSpecRound(
      _spec(
        intent: const ['title:i', 'design:respecced'],
        decisions: const [_emptyLookup, _cited],
        round: 2,
      ),
      grades: const {'coherence': 'C'},
      previous: first,
      transport: 'envelope',
    );
    expect(second.selectedRubricIds, [kSpecGatingRubric, 'plan-completeness']);
    expect(
      _ruleOf(second.run.selection, 'plan-completeness'),
      'targeted-respec-action',
    );
    for (final sibling in const [
      'coherence',
      'decision-alignment',
      'acceptance-testability',
    ]) {
      expect(
        _ruleOf(second.run.selection, sibling),
        'targeted-respec-preserved',
      );
    }
    // The receipt carries the ROUND-1 verdict of every omitted sibling — grade
    // AND transport — never the round-2 observation.
    expect(
      second.preservedLanes.map((lane) => lane.rubricId),
      second.omittedRubricIds,
    );
    expect(
      {for (final lane in second.preservedLanes) lane.rubricId: lane.grade},
      {
        'coherence': 'B',
        'decision-alignment': 'A',
        'acceptance-testability': 'A',
      },
    );
    expect(second.preservedLanes.map((lane) => lane.transport).toSet(), {
      'file',
    });
    // The current full run stays the authoritative OBSERVATION.
    expect(second.lanes.map((lane) => lane.rubricId), kSpecCommitteeRubrics);
    expect(
      second.lanes.singleWhere((lane) => lane.rubricId == 'coherence').grade,
      'C',
    );
    expect(
      jsonDecode(
        committeeShadowResultProjection(
          second,
        )['committeeShadowPreservedLaneGrades']!,
      ),
      {
        'coherence': 'B',
        'decision-alignment': 'A',
        'acceptance-testability': 'A',
      },
    );
    // It round-trips through the strict codec, snapshot included.
    final decoded = CommitteeShadowReceipt.fromJson(
      jsonDecode(jsonEncode(second.toJson())),
    )!;
    expect(decoded.toJson(), second.toJson());
  });

  test('retained corpus measures selectivity', () {
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
    expect(rows, hasLength(kRetainedCorpusRounds));
    final recorded = [
      for (final row in rows) CommitteeShadowReceipt.fromJson(row),
    ];
    expect(recorded, everyElement(isNotNull), reason: 'decodes STRICTLY');
    final corpus = recorded.cast<CommitteeShadowReceipt>();
    // Retained verbatim from two real beads' worktrees, in source order.
    expect(
      {for (final r in corpus) r.run.workBeadId},
      {'pow-zqo1', 'pow-1d2x'},
    );
    expect(
      [for (final r in corpus) r.sampleId],
      [
        '393dd65cce8fcd7031e0c5cd23ea06d7484ef5f749cb4502456eda95515659e1',
        '4c5b67434b7c10a689995bc637dde03673983c5061dac9dbe957d016cd2b4330',
        '4b2954fa2497a47a8076364128b6236c50faae444394e71afbde37957b4012c0',
        '4c693f43f4514840bbefc40746098f99033c5206a9238b117bc247939c77eeab',
        'c9bd217a48d990a021a341e9efefec82ecd1417f5da28e2684f7445232e78636',
        '1ed05d126c120acb704dd511c5eaa5e9ede381f8f80a416d89c1ea11d851d83f',
        '397ba721f5367696600397e396a6c38e9dadb9657df968b9611fdfd9348a4b08',
        '98770152f692efce96a4a90265afaadfaffdbe4b20afd23421399a636ae11ee2',
        '6d7ea6cb5704012f85ac7b9cd0bbc4db11412fb17f629d8d792a311e57d6b664',
        'f2421796d3a38eef9464315d4ef8b0fbcc4446bbcc640a424184266928d8f11c',
        '5232c44de931c55c39517a1270961df9834395c8f113a5fbb8e432362ececcf0',
        '667d94799825242f606b20eab4c10b33f3c6eb3acee75bf060bab9c2940d1c42',
      ],
    );
    // The corpus is observation data: every row recorded its stage's FULL
    // committee, and every row spent a distinct cost vector (no row is a
    // duplicated or authored copy of another).
    for (final receipt in corpus) {
      expect(
        receipt.lanes.map((lane) => lane.rubricId),
        switch (receipt.run.stage) {
          CommitteeStage.specReview => kSpecCommitteeRubrics,
          CommitteeStage.codeReview => kCommitteeRubrics,
        },
      );
    }
    String costVector(CommitteeShadowReceipt receipt) =>
        canonicalCommitteeJson([
          for (final lane in receipt.lanes)
            [
              lane.rubricId,
              lane.costUsd,
              lane.tokensIn,
              lane.tokensOut,
              lane.durationMs,
            ],
        ]);
    // The cost vector is each row's identity across replay: the join id is
    // shared by every round-zero receipt of one bead and stage.
    final costVectors = {
      for (final receipt in corpus) costVector(receipt): receipt,
    };
    expect(costVectors, hasLength(kRetainedCorpusRounds));

    // Replay is PURE: no filesystem effect is possible inside it.
    late List<CommitteeShadowReceipt> replayed;
    IOOverrides.runZoned(
      () => replayed = reclassifyCommitteeShadowCorpus(corpus),
      createFile: (path) => throw StateError('replay touched $path'),
      createDirectory: (path) => throw StateError('replay touched $path'),
      createLink: (path) => throw StateError('replay touched $path'),
    );
    expect(replayed, hasLength(corpus.length));
    expect(
      [
        for (final receipt in reclassifyCommitteeShadowCorpus(corpus))
          receipt.toJson(),
      ],
      [for (final receipt in replayed) receipt.toJson()],
      reason: 'deterministic',
    );

    // One measurement per receipt: elected and omitted counts plus the rule
    // that omitted each lane.
    final measurements = [
      for (final receipt in replayed)
        (
          sampleId: costVectors[costVector(receipt)]!.sampleId,
          elected: receipt.selectedRubricIds.length,
          omitted: receipt.omittedRubricIds.length,
          rules: {
            for (final decision in receipt.run.selection.laneDecisions)
              if (!decision.elected) decision.rubricId: decision.rule.id,
          },
        ),
    ];
    final selective = measurements.where((m) => m.omitted > 0).toList();
    expect(selective, hasLength(kRetainedCorpusSelectiveRounds));
    expect(
      selective.single.sampleId,
      '98770152f692efce96a4a90265afaadfaffdbe4b20afd23421399a636ae11ee2',
    );
    expect(selective.single.elected, 4);
    expect(selective.single.rules, {'decision-alignment': 'no-cited-decision'});
    for (final m in measurements.where((m) => m.omitted == 0)) {
      final source = corpus.singleWhere((r) => r.sampleId == m.sampleId);
      expect(m.elected, source.run.fullRubricIds.length, reason: m.sampleId);
      expect(m.rules, isEmpty, reason: m.sampleId);
    }
    for (final receipt in replayed) {
      final run = receipt.run;
      expect(run.policyVersion, kCommitteeSelectionPolicyVersion);
      expect(run.attempts, isEmpty, reason: 'no inference was spent');
      for (final omitted in receipt.omittedRubricIds) {
        final decisions = run.selection.laneDecisions
            .where((decision) => decision.rubricId == omitted)
            .toList();
        expect(decisions, hasLength(1), reason: omitted);
        expect(decisions.single.elected, isFalse);
        expect(decisions.single.rule.id, isNotEmpty);
      }
      for (final gate in run.gatingRubricIds) {
        expect(receipt.selectedRubricIds, contains(gate));
      }
      // No routing, grading or rewind authority: the recorded route and the
      // recorded full-committee grades are carried, never produced.
      final source = costVectors[costVector(receipt)]!;
      expect(receipt.route.toJson(), source.route.toJson());
      expect(
        [for (final lane in receipt.lanes) lane.grade],
        [for (final lane in source.lanes) lane.grade],
      );
    }
  });
}

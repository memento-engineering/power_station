// The SHADOW committee selector in composition (beads `pow-1nl.1.1`,
// `pow-1d2x`).
//
// Three named tables, each addressable with `--plain-name`:
//
//  - `shadow authority`  the full committee still runs, its route join is
//                        unchanged, its node paths are stable, and the
//                        authoritative verdict comes back BYTE-FOR-BYTE — under
//                        selector success, store success, and every failure of
//                        both;
//  - `deterministic shadow capability`
//                        the selector classifies with no inference seam at
//                        all, reads the previous round's receipt before it
//                        writes, preserves a targeted respec's sibling verdicts
//                        in the receipt, and never replays a sibling;
//  - `durable step results`
//                        the selection run and the shadow receipt are promoted
//                        onto the step-result maps, bounded to identities,
//                        digests, ids and counts, and still reconstruct after
//                        the per-round worktree is reaped.
//
// Fakes, not mocks: the store, the evidence source and the authoritative route
// are all hand-written recorders. No process is ever spawned and no model is
// ever called.
import 'dart:convert';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:grid_trajectory/grid_trajectory.dart' show GateDisposition;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';
import 'support/package_root.dart';

// ── Fakes ───────────────────────────────────────────────────────────────────

/// An in-memory [CommitteeSelectionStore] that can be made to throw.
class _RecordingStore implements CommitteeSelectionStore {
  final Map<String, CommitteeSelectionRun> runs = {};
  final List<CommitteeShadowReceipt> receipts = [];
  final List<int> previousReads = [];
  bool throwOnRead = false;
  bool throwOnWrite = false;

  @override
  CommitteeSelectionRun? readRun(String workspaceDir, CommitteeStage stage) {
    if (throwOnRead) throw StateError('read exploded');
    return runs['$workspaceDir|${stage.wire}'];
  }

  @override
  void writeRun(String workspaceDir, CommitteeSelectionRun run) {
    if (throwOnWrite) throw StateError('write exploded');
    runs['$workspaceDir|${run.stage.wire}'] = run;
  }

  @override
  void writeReceipt(String workspaceDir, CommitteeShadowReceipt receipt) {
    if (throwOnWrite) throw StateError('write exploded');
    receipts.add(receipt);
  }

  @override
  CommitteeShadowReceipt? readPreviousReceipt(
    String workspaceDir, {
    required CommitteeStage stage,
    required String workBeadId,
    required int round,
  }) {
    previousReads.add(round);
    if (throwOnRead) throw StateError('read exploded');
    CommitteeShadowReceipt? best;
    for (final receipt in receipts) {
      final run = receipt.run;
      if (run.stage != stage ||
          run.workBeadId != workBeadId ||
          run.round >= round) {
        continue;
      }
      if (best == null || run.round > best.run.round) best = receipt;
    }
    return best;
  }
}

/// A canned evidence source that records every read.
class _CannedEvidence implements CommitteeSelectionEvidenceSource {
  _CannedEvidence(this.evidence, {this.error});

  final CommitteeSelectionEvidence Function(CommitteeStage stage) evidence;
  final Object? error;
  int reads = 0;

  @override
  CommitteeSelectionEvidence read({
    required CommitteeStage stage,
    required String workBeadId,
    required String workspaceDir,
  }) {
    reads++;
    final failure = error;
    if (failure != null) throw failure;
    return evidence(stage);
  }
}

/// The AUTHORITATIVE route, faked: answers ONE verdict object and counts calls.
class _FakeRoute extends RouteCapability {
  _FakeRoute(this.verdict);

  final RouteVerdict verdict;
  int calls = 0;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    calls++;
    return verdict;
  }
}

/// A route that THROWS — the wrapper must not swallow it into a fake verdict.
class _ThrowingRoute extends RouteCapability {
  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async =>
      throw StateError('the delegate exploded');
}

// ── the promoted key sets ───────────────────────────────────────────────────

/// EXACTLY what a selector step result promotes — spelled out here so a key
/// added or renamed in the library trips this suite rather than a downstream
/// fold.
const Set<String> _kSelectorKeys = {
  'shadow',
  'source',
  'stage',
  'selected',
  'matchedRules',
  'classifierAttempts',
  'sampleId',
  'joinId',
  'policyVersion',
  'workBeadId',
  'round',
  'nodePath',
  'omitted',
  'evidenceDigest',
  'missingEvidenceIds',
  'laneInputDigests',
  'classifierAttemptKinds',
  'laneDecisions',
  'previousRound',
};

/// EXACTLY the reserved entries a shadowed advance promotes.
const Set<String> _kShadowKeys = {
  'committeeShadowSampleId',
  'committeeShadowJoinId',
  'committeeShadowPolicyVersion',
  'committeeShadowWorkBeadId',
  'committeeShadowRound',
  'committeeShadowNodePath',
  'committeeShadowRouteNodePath',
  'committeeShadowStage',
  'committeeShadowSource',
  'committeeShadowSelected',
  'committeeShadowOmitted',
  'committeeShadowMatchedRules',
  'committeeShadowEvidenceDigest',
  'committeeShadowMissingEvidenceIds',
  'committeeShadowLaneInputDigests',
  'committeeShadowClassifierAttemptKinds',
  'committeeShadowActionLaneIds',
  'committeeShadowGateDisposition',
  'committeeShadowDownstreamJoinKeys',
  'committeeShadowOmittedLaneGrades',
  'committeeShadowOmittedLaneTransports',
  'committeeShadowOmittedLaneDispositions',
  'committeeShadowActualContributingRunIds',
  'committeeShadowActualMissingLaneIds',
  'committeeShadowActualTokensIn',
  'committeeShadowActualTokensOut',
  'committeeShadowActualCostUsd',
  'committeeShadowCounterfactualContributingRunIds',
  'committeeShadowCounterfactualMissingLaneIds',
  'committeeShadowCounterfactualTokensIn',
  'committeeShadowCounterfactualTokensOut',
  'committeeShadowCounterfactualCostUsd',
  'committeeShadowTruncated',
  'committeeShadowMissingFields',
  'committeeShadowLaneDecisions',
  'committeeShadowPreviousRound',
  'committeeShadowPreservedLaneGrades',
  'committeeShadowPreservedLaneTransports',
};

// ── helpers ─────────────────────────────────────────────────────────────────

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// An UNCERTAIN code shape: real evidence, but the pinned diff names no target
/// — the shape that elects the FULL committee.
CommitteeSelectionEvidence _uncertainCode() => CommitteeSelectionEvidence(
  stage: CommitteeStage.codeReview,
  workBeadId: 'tg-1',
  round: 1,
  intent: const ['title:bead-field:tg-1.title@sha256:aa'],
  missingEvidenceIds: const ['pinned-diff:no-targets'],
);

/// A TEST-ONLY code shape: it elects the gates and `test-coverage` alone.
CommitteeSelectionEvidence _testOnlyCode() => CommitteeSelectionEvidence(
  stage: CommitteeStage.codeReview,
  workBeadId: 'tg-1',
  round: 1,
  intent: const ['title:bead-field:tg-1.title@sha256:aa'],
  changedPaths: const ['test/committee_test.dart'],
  pinnedDiffDigest: 'b' * 64,
);

/// A RUNTIME code shape: one runtime path elects every semantic lane.
CommitteeSelectionEvidence _knownCode() => CommitteeSelectionEvidence(
  stage: CommitteeStage.codeReview,
  workBeadId: 'tg-1',
  round: 1,
  intent: const ['title:bead-field:tg-1.title@sha256:aa'],
  changedPaths: const ['lib/src/code/committee.dart'],
  pinnedDiffDigest: 'a' * 64,
);

({FakeTreeContext context, StepArgs args}) _selectorContext(
  String workspaceDir, {
  CommitteeSelectionPolicy? policy,
}) => (
  context: FakeTreeContext(
    values: {
      Bead: bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
      if (policy != null) CommitteeSelectionPolicy: policy,
    },
  ),
  args: stepArgs(
    'tg-1/review/committee-selection',
    params: {
      kCommitteeSelectionStageParam: 'code_review',
      kCommitteeFullRubricsParam:
          'code-validation,declared-tests-present,'
          'spec-adherence,regression-risk,test-coverage',
      kCommitteeGatingRubricsParam: 'code-validation,declared-tests-present',
      'grid.round': '1',
    },
  ),
);

CommitteeSelectionCapability _selector({
  required _CannedEvidence evidence,
  required _RecordingStore store,
}) => CommitteeSelectionCapability(evidenceSource: evidence, store: store);

/// The ONE route-shaped context both wrapper tables share.
({FakeTreeContext context, StepArgs args}) _routeContext(
  String workspaceDir, {
  Map<String, Map<String, String>> results = const {},
}) => (
  context: FakeTreeContext(
    values: {
      Bead: bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
      SiblingView: SiblingView(results: results),
    },
  ),
  args: stepArgs(
    'tg-1/review/route',
    params: {
      'critics':
          'code-validation,declared-tests-present,spec-adherence,'
          'regression-risk,test-coverage',
      'gating': 'code-validation,declared-tests-present',
      kCommitteeSelectionStageParam: 'code_review',
      'grid.round': '1',
    },
  ),
);

Map<String, Map<String, String>> _fullCommitteeResults() => {
  for (final id in kCommitteeRubrics)
    'tg-1/review/$id': {
      'grade': id == 'regression-risk' ? 'D' : 'A',
      'transport': 'file',
      'rationale': 'lane $id',
      if (!kCodeGatingRubrics.contains(id)) ...{
        'model': 'sonnet',
        'tokensIn': '1000',
        'tokensOut': '100',
        'costUsd': '0.5',
        'numTurns': '3',
        'harnessDurationMs': '60000',
        'premiumRequests': '0',
      },
    },
};

({FakeTreeContext context, StepArgs args}) _specSelectorContext(
  String workspaceDir, {
  required int round,
}) => (
  context: FakeTreeContext(
    values: {
      Bead: bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
    },
  ),
  args: stepArgs(
    'tg-1/spec_review/committee-selection',
    params: {
      kCommitteeSelectionStageParam: 'spec_review',
      kCommitteeFullRubricsParam: kSpecCommitteeRubrics.join(','),
      kCommitteeGatingRubricsParam: kSpecGatingRubric,
      'grid.round': '$round',
    },
  ),
);

({FakeTreeContext context, StepArgs args}) _specRouteContext(
  String workspaceDir, {
  required int round,
  required Map<String, Map<String, String>> results,
}) => (
  context: FakeTreeContext(
    values: {
      Bead: bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
      SiblingView: SiblingView(results: results),
    },
  ),
  args: stepArgs(
    'tg-1/spec_review/route',
    params: {
      'critics': kSpecCommitteeRubrics.join(','),
      'gating': kSpecGatingRubric,
      kCommitteeSelectionStageParam: 'spec_review',
      'grid.round': '$round',
    },
  ),
);

/// The spec committee's lane results: every lane `A` unless [grades] says
/// otherwise, all over one [transport].
Map<String, Map<String, String>> _specResults(
  Map<String, String> grades, {
  required String transport,
}) => {
  for (final id in kSpecCommitteeRubrics)
    'tg-1/spec_review/$id': {
      'grade': grades[id] ?? 'A',
      'transport': transport,
      'rationale': 'lane $id',
    },
};

/// [run]'s lane decisions as the canonical `rubric id -> rule id` column.
String _laneDecisionsOf(CommitteeSelectionRun run) => canonicalCommitteeJson({
  for (final decision in run.selection.laneDecisions)
    decision.rubricId: decision.rule.id,
});

// ── the in-process committee fixture ────────────────────────────────────────

NodeCursor _done() => const NodeCursor(state: StepState.complete);

/// Mounts the `code_review` circuit through the FULL path and records every
/// leaf execution KEYED BY THE ENGINE-PROVIDED NODE PATH.
class _Committee {
  _Committee()
    : fakes = buildFakes(),
      reg = RecordingCapabilityRegistry(
        circuits: const {'code_review': kCodeReviewCircuit},
      ),
      joined = JoinedSnapshotNotifier(JoinedSnapshot.empty()),
      owner = TreeOwner();

  final Fakes fakes;
  final RecordingCapabilityRegistry reg;
  final JoinedSnapshotNotifier joined;
  final TreeOwner owner;
  final Map<String, NodeCursor> _cursor = {};
  final List<String> starts = [];

  void mount() {
    _push();
    owner.mountRoot(
      ProviderScope(
        child: InheritedSeed<JoinedSnapshotNotifier>(
          value: joined,
          child: InheritedSeed<StationServices>(
            value: fakes.ctx,
            child: InheritedSeed<CapabilityRegistry>(
              value: reg,
              child: InheritedSeed<SessionResolver>(
                value: CircuitResolver((_) => kCodeReviewCircuit),
                child: Station([
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(
                      const SubstationConfig(
                        substationId: 'tg',
                        ownedSubstations: {'tg'},
                      ),
                    ),
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    _collect();
  }

  void advance(Map<String, NodeCursor> delta) {
    _cursor.addAll(delta);
    _push();
    owner.flush();
    _collect();
  }

  void _collect() {
    for (final event in reg.events) {
      if (!event.startsWith('START ')) continue;
      final open = event.indexOf('(');
      starts.add(event.substring(open + 1, event.length - 1));
    }
    reg.events.clear();
  }

  void _push() => joined.push(
    JoinedSnapshot(
      graph: GraphSnapshot.fromParts(
        beads: [
          const Bead(
            id: 'tg-1',
            issueType: IssueType.task,
            status: BeadStatus.open,
          ),
        ],
        dependencies: const [],
        readyIds: const {'tg-1'},
        capturedAt: DateTime(2026),
      ),
      sessionsByWorkBead: {
        'tg-1': SessionProjection(
          workBeadId: 'tg-1',
          sessionId: 'tgdog-s',
          cursor: _cursor,
        ),
      },
    ),
  );

  void dispose() => owner.dispose();
}

void main() {
  group('shadow authority', () {
    test('every original lane still executes ONCE, at its stable node path, '
        'and the route opens without the selector', () {
      final c = _Committee()..mount();
      addTearDown(c.dispose);
      c.advance({'tg-1/clear-critique': _done()});
      c.advance({'tg-1/pin-diff': _done()});
      c.advance({
        'tg-1/format-clean': _done(),
        'tg-1/declared-tests-present': _done(),
      });
      c.advance({for (final id in kCommitteeRubrics) 'tg-1/$id': _done()});

      // EVERY lane of the current committee mounted, exactly once, at the node
      // path it has always had — the selector added a sibling, never a rename.
      for (final id in [
        kClearCritiqueStep,
        kPinDiffStep,
        kFormatCleanStep,
        ...kCommitteeRubrics,
        kCommitteeSelectionStep,
        'route',
      ]) {
        expect(
          c.starts.where((path) => path == 'tgdog-s/tg-1/$id'),
          hasLength(1),
          reason: '$id must mount exactly once, at tgdog-s/tg-1/$id',
        );
      }
      // The selector's cursor was NEVER advanced, yet the route still ran.
      expect(c.starts, contains('tgdog-s/tg-1/route'));
      expect(
        c.starts.where((path) => path.endsWith('/committee-selection')),
        hasLength(1),
      );
    });

    test('the wrapper returns the delegate ruling unchanged for every arm — '
        'the lossy arms as the delegate OBJECT — and calls it exactly '
        'once', () async {
      final dir = _tempDir('shadow-route-');
      for (final verdict in <RouteVerdict>[
        const Advance({'verdict': 'advance'}),
        const Rewind({'specify'}, 'respec'),
        const Escalate('hard block'),
      ]) {
        final delegate = _FakeRoute(verdict);
        final store = _RecordingStore();
        final wrapper = CommitteeShadowRouteCapability(
          delegate: delegate,
          store: store,
        );
        final ctx = _routeContext(dir.path, results: _fullCommitteeResults());
        final returned = await wrapper.route(ctx.context, ctx.args);
        expect(delegate.calls, 1);
        expect(store.receipts, hasLength(1));
        expect(store.receipts.single.route.type, committeeRouteTypeOf(verdict));

        // An ADVANCE already carries a result map, so the shadow's durable
        // copy rides it: every delegate entry survives untouched and the only
        // additions are the RESERVED `committeeShadow*` ones.
        if (verdict is Advance) {
          final payload = (returned as Advance).payload!;
          expect({
            for (final entry in payload.entries)
              if (!entry.key.startsWith('committeeShadow'))
                entry.key: entry.value,
          }, verdict.payload);
          expect(payload, {
            ...?verdict.payload,
            ...committeeShadowResultProjection(store.receipts.single),
          }, reason: 'the reserved projection is the ONLY addition');
          continue;
        }
        // A rewind and an escalate carry no result map at all, so there is
        // nowhere to promote to — they come back as the delegate's own object.
        expect(identical(returned, verdict), isTrue);
      }
    });

    test('a store that throws on READ or WRITE changes nothing about the '
        'verdict', () async {
      final dir = _tempDir('shadow-route-throws-');
      const verdict = Escalate('a critic returned F (test-coverage) — rework');
      for (final broken in <void Function(_RecordingStore)>[
        (store) => store.throwOnRead = true,
        (store) => store.throwOnWrite = true,
      ]) {
        final delegate = _FakeRoute(verdict);
        final store = _RecordingStore();
        broken(store);
        final ctx = _routeContext(dir.path, results: _fullCommitteeResults());
        final returned = await CommitteeShadowRouteCapability(
          delegate: delegate,
          store: store,
        ).route(ctx.context, ctx.args);
        expect(identical(returned, verdict), isTrue);
        expect(delegate.calls, 1);
        expect(store.receipts, isEmpty);
      }
    });

    test('a THROWING delegate still throws — the wrapper never substitutes a '
        'verdict of its own', () async {
      final dir = _tempDir('shadow-route-delegate-throws-');
      final ctx = _routeContext(dir.path);
      await expectLater(
        CommitteeShadowRouteCapability(
          delegate: _ThrowingRoute(),
          store: _RecordingStore(),
        ).route(ctx.context, ctx.args),
        throwsA(isA<StateError>()),
      );
    });

    test('a fresh run is joined; an absent or stale one is an explicit FULL '
        'FALLBACK and never waits for selection work', () async {
      final dir = _tempDir('shadow-route-join-');
      final store = _RecordingStore();
      final ctx = _routeContext(dir.path, results: _fullCommitteeResults());
      const verdict = Advance({
        'verdict': 'advance',
        'fix_in_flight_finding': 'name the omitted lane',
      });

      // 1. NO run on disk when the route joins.
      await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(verdict),
        store: store,
      ).route(ctx.context, ctx.args);
      final absent = store.receipts.single;
      expect(
        absent.run.selection.source,
        CommitteeSelectionSource.fullFallback,
      );
      expect(absent.selectedRubricIds, kCommitteeRubrics);
      expect(absent.omittedRubricIds, isEmpty);
      expect(absent.missingFields, contains('selection-run:absent'));

      // 2. A run from ANOTHER round is stale — same posture, named.
      final selectorCtx = _selectorContext(dir.path);
      await _selector(
        evidence: _CannedEvidence((_) => _knownCode()),
        store: store,
      ).run(selectorCtx.context, selectorCtx.args);
      final stored = store.runs.values.single;
      store.runs['${dir.path}|code_review'] = CommitteeSelectionRun(
        policyVersion: stored.policyVersion,
        stage: stored.stage,
        workBeadId: stored.workBeadId,
        round: 99,
        nodePath: stored.nodePath,
        selection: stored.selection,
        evidence: stored.evidence,
        fullRubricIds: stored.fullRubricIds,
        gatingRubricIds: stored.gatingRubricIds,
      );
      store.receipts.clear();
      await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(verdict),
        store: store,
      ).route(ctx.context, ctx.args);
      expect(
        store.receipts.single.missingFields,
        contains('selection-run:stale'),
      );

      // 3. The FRESH run is joined and its omission is recorded beside the
      //    committee's ACTUAL grades and their provenance.
      store.runs['${dir.path}|code_review'] = stored;
      store.receipts.clear();
      await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(verdict),
        store: store,
      ).route(ctx.context, ctx.args);
      final joined = store.receipts.single;
      expect(
        joined.run.selection.source,
        CommitteeSelectionSource.deterministic,
      );
      expect(joined.selectedRubricIds, kCommitteeRubrics);
      expect(joined.actionLaneIds, ['regression-risk']);
      final adverse = joined.lanes.singleWhere(
        (lane) => lane.rubricId == 'regression-risk',
      );
      expect(adverse.grade, 'D');
      expect(adverse.transport, 'file');
      expect(adverse.finding, 'name the omitted lane');
      expect(adverse.model, 'sonnet');
      expect(adverse.gateDisposition, GateDisposition.overridden);
      expect(joined.actual.costUsd, closeTo(1.5, 1e-9));
      expect(joined.downstreamJoinKeys['siblingScope'], 'tg-1/review/');
    });

    test('the selector NEVER grades, gates, rewinds or fails', () async {
      final dir = _tempDir('shadow-selector-ok-');
      final store = _RecordingStore();
      for (final evidence in [_knownCode(), _uncertainCode()]) {
        final ctx = _selectorContext(dir.path);
        final outcome = await _selector(
          evidence: _CannedEvidence((_) => evidence),
          store: store,
        ).run(ctx.context, ctx.args);
        expect(outcome, isA<Ok>());
        expect(outcome, isNot(isA<Failed>()));
        final payload = (outcome as Ok).payload!;
        expect(payload.containsKey('grade'), isFalse);
        expect(payload['shadow'], 'selection');
      }
      // A THROWING evidence source is typed provenance, still an Ok.
      final ctx = _selectorContext(dir.path);
      final outcome = await _selector(
        evidence: _CannedEvidence(
          (_) => _knownCode(),
          error: StateError('gather exploded'),
        ),
        store: store,
      ).run(ctx.context, ctx.args);
      expect(outcome, isA<Ok>());
      expect(
        (outcome as Ok).payload!['missingFields'],
        contains('evidence-source:'),
      );

      // A THROWING store is likewise recorded, never raised.
      final failing = _RecordingStore()..throwOnWrite = true;
      final third = _selectorContext(dir.path);
      final result = await _selector(
        evidence: _CannedEvidence((_) => _knownCode()),
        store: failing,
      ).run(third.context, third.args);
      expect(result, isA<Ok>());
      expect(
        (result as Ok).payload!['missingFields'],
        contains('selection-write:'),
      );
    });

    test('the resolver mounts the policy VALUE and re-derives the shape on '
        'every build', () {
      const custom = CommitteeSelectionPolicy(policyVersion: '1');
      const resolver = ChangeShapeCircuitResolver(
        kCodeCircuit,
        selectionPolicy: custom,
      );
      final seed = resolver.sessionFor(bead: workBead('tg-1'));
      expect(seed, isA<InheritedSeed<CommitteeSelectionPolicy>>());
      expect(
        (seed as InheritedSeed<CommitteeSelectionPolicy>).value,
        same(custom),
      );

      // The classification is RECOMPUTED per bead — nothing is cached.
      final docsBead = workBead(
        'tg-2',
      ).copyWith(design: '## Touches\n- `docs/x.md`\n');
      final codeBead = workBead(
        'tg-3',
      ).copyWith(design: '## Touches\n- `lib/a.dart`\n');
      expect(
        (resolver.circuitFor(changeShapeOf(docsBead)).stepById(kReviewStepId)!
                as SubCircuitStep)
            .circuitId,
        kDocsReviewCircuitId,
      );
      expect(
        (resolver.circuitFor(changeShapeOf(codeBead)).stepById(kReviewStepId)!
                as SubCircuitStep)
            .circuitId,
        'code_review',
      );
      // Two successive builds over DIFFERENT beads produce different trees.
      expect(
        resolver.sessionFor(bead: docsBead),
        isA<InheritedSeed<CommitteeSelectionPolicy>>(),
      );
      expect(
        resolver.sessionFor(bead: codeBead),
        isA<InheritedSeed<CommitteeSelectionPolicy>>(),
      );
    });
  });

  group('deterministic shadow capability', () {
    test('uncertain evidence records a FULL FALLBACK with no inference seam '
        'to call', () async {
      final dir = _tempDir('deterministic-fallback-');
      final store = _RecordingStore();
      for (final evidence in <CommitteeSelectionEvidence>[
        _uncertainCode(),
        CommitteeSelectionEvidence(
          stage: CommitteeStage.codeReview,
          workBeadId: 'tg-1',
          round: 1,
          missingEvidenceIds: const ['anchors', 'dossier', 'pinned-diff'],
        ),
      ]) {
        final ctx = _selectorContext(dir.path);
        final outcome = await _selector(
          evidence: _CannedEvidence((_) => evidence),
          store: store,
        ).run(ctx.context, ctx.args);
        final run = store.runs.values.single;
        expect(run.selection.source, CommitteeSelectionSource.fullFallback);
        expect(run.selection.selectedRubricIds, kCommitteeRubrics);
        expect(run.attempts, isEmpty, reason: 'there is no classifier at all');
        expect(
          {
            for (final decision in run.selection.laneDecisions)
              decision.rubricId: decision.rule.id,
          },
          {
            for (final gate in kCodeGatingRubrics) gate: 'gate-always',
            'spec-adherence': 'full-fallback',
            'regression-risk': 'full-fallback',
            'test-coverage': 'full-fallback',
          },
        );
        final payload = (outcome as Ok).payload!;
        expect(payload['classifierAttempts'], '0');
        expect(payload['matchedRules'], 'gate-always,full-fallback');
      }
    });

    test('a change shape elects per lane with a named rule', () async {
      final dir = _tempDir('deterministic-shape-');
      final store = _RecordingStore();
      final ctx = _selectorContext(dir.path);
      final outcome = await _selector(
        evidence: _CannedEvidence((_) => _testOnlyCode()),
        store: store,
      ).run(ctx.context, ctx.args);
      final run = store.runs.values.single;
      expect(run.selection.source, CommitteeSelectionSource.deterministic);
      expect(run.selection.selectedRubricIds, [
        ...kCodeGatingRubrics,
        'test-coverage',
      ]);
      final payload = (outcome as Ok).payload!;
      expect(jsonDecode(payload['laneDecisions']!), {
        for (final gate in kCodeGatingRubrics) gate: 'gate-always',
        'spec-adherence': 'test-only-change',
        'regression-risk': 'no-runtime-change',
        'test-coverage': 'test-change',
      });
      expect(payload['omitted'], 'spec-adherence,regression-risk');
      expect(payload['previousRound'], 'null');
      expect(store.previousReads, [1], reason: 'read BEFORE the write');
    });

    test('a targeted respec preserves sibling verdicts and stays '
        'observational', () async {
      final dir = _tempDir('deterministic-respec-');
      final store = _RecordingStore();
      final evidence = _CannedEvidence(
        (stage) => CommitteeSelectionEvidence(
          stage: stage,
          workBeadId: 'tg-1',
          round: 0,
          intent: const ['title:bead-field:tg-1.title@sha256:aa'],
          acceptance: const [
            'acceptance_criteria:bead-field:tg-1.ac@sha256:bb',
          ],
          decisions: const [
            'surface:power_station/lib|complete|decision-surface:x',
            'decision:decision-entry:power_station#a21@sha256:cc',
          ],
        ),
      );
      final selector = _selector(evidence: evidence, store: store);

      // ROUND 1: the first graded round elects the whole spec committee; the
      // route RESPECS on plan-completeness and stamps the invalidating grade.
      final first = _specSelectorContext(dir.path, round: 1);
      await selector.run(first.context, first.args);
      expect(
        store.runs.values.single.selection.selectedRubricIds,
        kSpecCommitteeRubrics,
      );
      const respec = Advance({
        'verdict': 'respec',
        'grade': 'F',
        'rule': 'respec',
        'round': '1',
      });
      final firstRoute = _specRouteContext(
        dir.path,
        round: 1,
        results: _specResults({'plan-completeness': 'D'}, transport: 'file'),
      );
      await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(respec),
        store: store,
      ).route(firstRoute.context, firstRoute.args);
      expect(store.receipts.single.actionLaneIds, ['plan-completeness']);

      // ROUND 2: the selector reads round 1's receipt and elects the gate plus
      // the ONE action lane; every sibling is preserved, not re-run.
      final second = _specSelectorContext(dir.path, round: 2);
      await selector.run(second.context, second.args);
      final run = store.runs.values.single;
      expect(run.previous!.round, 1);
      expect(run.selection.selectedRubricIds, [
        kSpecGatingRubric,
        'plan-completeness',
      ]);
      expect(
        run.selection.decisionFor('coherence')!.rule,
        CommitteeLaneRule.targetedRespecPreserved,
      );
      expect(evidence.reads, 2, reason: 'one gather read per invocation');

      // The FULL committee still ran round 2 and the delegate still rules: each
      // arm comes back as the delegate ruled it.
      for (final verdict in <RouteVerdict>[
        const Advance({'verdict': 'advance'}),
        const Rewind({'specify'}, 'respec'),
        const Escalate('hard block'),
      ]) {
        store.receipts.removeWhere((receipt) => receipt.run.round == 2);
        final secondRoute = _specRouteContext(
          dir.path,
          round: 2,
          results: _specResults(const {}, transport: 'envelope'),
        );
        final delegate = _FakeRoute(verdict);
        final returned = await CommitteeShadowRouteCapability(
          delegate: delegate,
          store: store,
        ).route(secondRoute.context, secondRoute.args);
        expect(delegate.calls, 1);
        final receipt = store.receipts.last;
        expect(receipt.run.round, 2);
        expect(
          receipt.lanes.map((lane) => lane.rubricId),
          kSpecCommitteeRubrics,
          reason: 'the current full run is the authoritative observation',
        );
        expect(
          {
            for (final lane in receipt.preservedLanes)
              lane.rubricId: lane.grade,
          },
          {
            'coherence': 'A',
            'decision-alignment': 'A',
            'acceptance-testability': 'A',
          },
          reason: 'the ROUND-1 verdicts, not the round-2 observation',
        );
        expect(receipt.preservedLanes.map((lane) => lane.transport).toSet(), {
          'file',
        });
        switch (verdict) {
          case Advance(:final payload):
            final promoted = (returned as Advance).payload!;
            expect({
              for (final entry in promoted.entries)
                if (!entry.key.startsWith('committeeShadow'))
                  entry.key: entry.value,
            }, payload);
            expect(
              jsonDecode(promoted['committeeShadowPreservedLaneGrades']!),
              {
                'coherence': 'A',
                'decision-alignment': 'A',
                'acceptance-testability': 'A',
              },
            );
            expect(promoted['committeeShadowPreviousRound'], '1');
          case Rewind() || Escalate():
            expect(identical(returned, verdict), isTrue);
        }
      }
    });

    test(
      'a throwing previous-receipt read is provenance, never a throw',
      () async {
        final dir = _tempDir('deterministic-previous-throws-');
        final store = _RecordingStore()..throwOnRead = true;
        final ctx = _selectorContext(dir.path);
        final outcome = await _selector(
          evidence: _CannedEvidence((_) => _knownCode()),
          store: store,
        ).run(ctx.context, ctx.args);
        expect(outcome, isA<Ok>());
        final payload = (outcome as Ok).payload!;
        expect(payload.containsKey('grade'), isFalse);
        expect(payload['missingFields'], contains('previous-receipt:'));
        expect(store.runs.values.single.previous, isNull);
      },
    );

    test('selection replays NO sibling: one gather read per invocation, no '
        'receipt, byte-identical on re-run', () async {
      final dir = _tempDir('deterministic-isolation-');
      final evidence = _CannedEvidence((_) => _testOnlyCode());
      final store = _RecordingStore();
      final selector = _selector(evidence: evidence, store: store);
      final ctx = _selectorContext(dir.path);
      await selector.run(ctx.context, ctx.args);
      expect(evidence.reads, 1);
      final first = store.runs.values.single.toJson();
      final again = _selectorContext(dir.path);
      await selector.run(again.context, again.args);
      expect(evidence.reads, 2);
      expect(store.runs.values.single.toJson(), first);
      expect(store.receipts, isEmpty, reason: 'the selector writes no receipt');
    });

    test('the registry composes NO classifier inference seam', () {
      final registry = File(
        p.join(packageRoot(), 'lib', 'src', 'code', 'code_capabilities.dart'),
      ).readAsStringSync();
      expect(registry, isNot(contains('committeeClassifier')));
      final mount = registry.substring(
        registry.indexOf(
          'kCommitteeSelectionStep: CommitteeSelectionCapability(',
        ),
      );
      final args = mount.substring(0, mount.indexOf('store: selectionStore'));
      expect(args, isNot(contains('classifier')));
      expect(args, isNot(contains('inference')));
    });
  });

  group('durable step results', () {
    test('selector result promotes durable run fields', () async {
      final dir = _tempDir('durable-selector-');
      final store = _RecordingStore();
      final ctx = _selectorContext(dir.path);
      final outcome = await _selector(
        evidence: _CannedEvidence((_) => _knownCode()),
        store: store,
      ).run(ctx.context, ctx.args);

      // The six the committee report already folds over, byte for byte.
      final payload = (outcome as Ok).payload!;
      expect(payload['shadow'], 'selection');
      expect(payload['source'], 'deterministic');
      expect(payload['stage'], 'code_review');
      expect(payload['selected'], kCommitteeRubrics.join(','));
      expect(payload['matchedRules'], 'gate-always,runtime-change');
      expect(payload['classifierAttempts'], '0');

      // …and the evidence packet that used to die with the worktree.
      final run = store.runs.values.single;
      expect(payload['policyVersion'], kCommitteeSelectionPolicyVersion);
      expect(payload['workBeadId'], 'tg-1');
      expect(payload['round'], '1');
      expect(payload['nodePath'], 'tg-1/review/committee-selection');
      expect(payload['omitted'], '');
      expect(payload['evidenceDigest'], run.selection.evidenceDigest);
      expect(payload['evidenceDigest'], hasLength(64));
      expect(payload['missingEvidenceIds'], '');
      expect(payload['classifierAttemptKinds'], '');
      expect(
        payload['laneInputDigests'],
        canonicalCommitteeJson(run.selection.laneInputDigests),
      );
      expect(
        payload['sampleId'],
        committeeSampleId(
          policyVersion: run.policyVersion,
          stage: run.stage,
          workBeadId: run.workBeadId,
          round: run.round,
          evidenceDigest: run.selection.evidenceDigest,
        ),
      );
      expect(
        payload['joinId'],
        committeeJoinId(
          stage: run.stage,
          workBeadId: run.workBeadId,
          round: run.round,
          routeParentPath: 'tg-1/review',
        ),
      );
      expect(payload, committeeSelectionResultProjection(run));

      expect(payload['laneDecisions'], _laneDecisionsOf(run));
      expect(payload['previousRound'], 'null');

      // An UNCERTAIN round records its full fallback and the gap that caused
      // it — and spends no classifier attempt, because there is none.
      final fallbackStore = _RecordingStore();
      final fallback = _selectorContext(dir.path);
      final fellBack = await _selector(
        evidence: _CannedEvidence((_) => _uncertainCode()),
        store: fallbackStore,
      ).run(fallback.context, fallback.args);
      final second = (fellBack as Ok).payload!;
      expect(second['classifierAttempts'], '0');
      expect(second['classifierAttemptKinds'], '');
      expect(second['source'], 'fullFallback');
      expect(second['missingEvidenceIds'], 'pinned-diff:no-targets');
      expect(second['omitted'], '');

      // An unusable step declaration still records the SAME thin skip.
      final skipped = await _selector(
        evidence: _CannedEvidence((_) => _knownCode()),
        store: _RecordingStore(),
      ).run(ctx.context, stepArgs('tg-1/review/committee-selection'));
      expect((skipped as Ok).payload, {
        'shadow': 'skipped',
        'missingFields': kCommitteeSelectionStageParam,
      });
    });

    test('route result promotes durable receipt fields', () async {
      final dir = _tempDir('durable-route-');
      final store = _RecordingStore();

      // A TEST-ONLY selection, so the OMISSION set — the whole point of the
      // sample — is non-empty.
      final selectorCtx = _selectorContext(dir.path);
      final selected = await _selector(
        evidence: _CannedEvidence((_) => _testOnlyCode()),
        store: store,
      ).run(selectorCtx.context, selectorCtx.args);
      final selectorPayload = (selected as Ok).payload!;

      const delegatePayload = {
        'verdict': 'advance',
        'fix_in_flight_finding': 'name the omitted lane',
      };
      final ctx = _routeContext(dir.path, results: _fullCommitteeResults());
      final returned = await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(const Advance(delegatePayload)),
        store: store,
      ).route(ctx.context, ctx.args);

      final payload = (returned as Advance).payload!;
      final receipt = store.receipts.single;
      expect(payload, {
        ...delegatePayload,
        ...committeeShadowResultProjection(receipt),
      });

      // Both ends of the round carry the SAME identities, so a per-rule fold
      // joins selector to route without ever opening a worktree.
      expect(payload['committeeShadowSampleId'], selectorPayload['sampleId']);
      expect(payload['committeeShadowJoinId'], selectorPayload['joinId']);
      expect(payload['committeeShadowSelected'], selectorPayload['selected']);
      expect(payload['committeeShadowOmitted'], selectorPayload['omitted']);
      expect(
        payload['committeeShadowNodePath'],
        'tg-1/review/committee-selection',
      );
      expect(payload['committeeShadowRouteNodePath'], 'tg-1/review/route');
      expect(payload['committeeShadowSource'], 'deterministic');
      expect(payload['committeeShadowClassifierAttemptKinds'], '');
      expect(
        payload['committeeShadowLaneDecisions'],
        selectorPayload['laneDecisions'],
      );
      expect(payload['committeeShadowPreservedLaneGrades'], '{}');
      expect(
        payload['committeeShadowOmitted'],
        'spec-adherence,regression-risk',
      );

      // What the omitted lanes ACTUALLY did, per rule.
      expect(jsonDecode(payload['committeeShadowOmittedLaneGrades']!), {
        'spec-adherence': 'A',
        'regression-risk': 'D',
      });
      expect(jsonDecode(payload['committeeShadowOmittedLaneTransports']!), {
        'spec-adherence': 'file',
        'regression-risk': 'file',
      });
      expect(jsonDecode(payload['committeeShadowOmittedLaneDispositions']!), {
        'spec-adherence': null,
        'regression-risk': 'overridden',
      });
      expect(payload['committeeShadowGateDisposition'], 'overridden');
      expect(payload['committeeShadowActionLaneIds'], 'regression-risk');

      // The accounting: real totals where every contributor reported, and the
      // literal null — never a pretended zero — where one did not.
      expect(payload['committeeShadowActualTokensIn'], '3000');
      expect(payload['committeeShadowActualTokensOut'], '300');
      expect(payload['committeeShadowActualCostUsd'], '1.5');
      expect(
        committeeCsv(payload['committeeShadowActualContributingRunIds']),
        kCommitteeRubrics,
      );
      expect(receipt.counterfactual.tokensIn, 1000);
      expect(payload['committeeShadowCounterfactualTokensIn'], '1000');
      expect(payload['committeeShadowCounterfactualTokensOut'], '100');
      expect(payload['committeeShadowCounterfactualCostUsd'], '0.5');
      expect(
        committeeCsv(
          payload['committeeShadowCounterfactualContributingRunIds'],
        ),
        [...kCodeGatingRubrics, 'test-coverage'],
      );

      // A failed IN-ROUND artifact write never discards the durable copy.
      final broken = _RecordingStore()
        ..runs['${dir.path}|code_review'] = store.runs.values.single
        ..throwOnWrite = true;
      final survived = await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(const Advance(delegatePayload)),
        store: broken,
      ).route(ctx.context, ctx.args);
      expect(broken.receipts, isEmpty);
      expect((survived as Advance).payload, payload);
    });

    test('step-result projections are bounded canonical data', () {
      const prose = 'PROSE-SENTINEL';
      const policy = kCommitteeSelectionPolicy;
      final evidence = CommitteeSelectionEvidence(
        stage: CommitteeStage.codeReview,
        workBeadId: 'tg-1',
        round: 4,
        intent: ['intent-$prose'],
        acceptance: ['acceptance-$prose'],
        paths: ['paths-$prose'],
        decisions: ['decisions-$prose'],
        priorArt: ['prior-art-$prose'],
        context: ['context-$prose'],
        flags: ['flags-$prose'],
        changedPaths: ['test/${prose}_test.dart'],
        pinnedDiffDigest: 'a' * 64,
        missingEvidenceIds: const ['dossier'],
      );
      final run = CommitteeSelectionRun(
        policyVersion: policy.policyVersion,
        stage: CommitteeStage.codeReview,
        workBeadId: 'tg-1',
        round: 4,
        nodePath: 'tg-1/review/committee-selection',
        selection: policy.classify(
          evidence: evidence,
          fullRubricIds: kCommitteeRubrics,
          gatingRubricIds: kCodeGatingRubrics,
        ),
        evidence: evidence,
        fullRubricIds: kCommitteeRubrics,
        gatingRubricIds: kCodeGatingRubrics,
      );
      final receipt = buildCommitteeShadowReceipt(
        run: run,
        route: CommitteeRouteObservation(
          nodePath: 'tg-1/review/route',
          type: 'advance',
          reason: 'route-$prose',
          payload: {kCommitteeFixInFlightFindingKey: 'finding-$prose'},
        ),
        lanes: [
          for (final id in kCommitteeRubrics)
            CommitteeLaneReceipt.derive(
              rubricId: id,
              nodePath: 'tg-1/review/$id',
              workBeadId: 'tg-1',
              routeType: 'advance',
              gating: kCodeGatingRubrics.contains(id),
              grade: 'A',
              transport: 'file',
              rationale: 'rationale-$prose',
              finding: 'finding-$prose',
              owner: 'owner-$prose',
              refinement: 'refinement-$prose',
              model: 'model-$prose',
              tokensIn: 10,
              tokensOut: 2,
              costUsd: 0.25,
              premiumRequests: 0,
              numTurns: 1,
              durationMs: 50,
            ),
        ],
      );

      final selector = committeeSelectionResultProjection(run);
      final shadow = committeeShadowResultProjection(receipt);
      expect(selector.keys.toSet(), _kSelectorKeys);
      expect(selector, hasLength(19));
      expect(shadow.keys.toSet(), _kShadowKeys);
      expect(shadow, hasLength(38));
      for (final key in shadow.keys) {
        expect(
          key,
          startsWith('committeeShadow'),
          reason: 'the prefix is the RESERVATION a conforming route respects',
        );
      }

      // Identities, digests, ids and counts ONLY: every prose column the
      // receipt keeps stays behind.
      for (final projection in [selector, shadow]) {
        for (final entry in projection.entries) {
          expect(entry.key, isNot(contains(prose)));
          expect(entry.value, isNot(contains(prose)));
        }
      }

      // Canonical encodings: CSV for ordered ids, sorted canonical JSON for
      // maps, JSON literals for numbers and booleans.
      expect(selector['selected'], run.selection.selectedRubricIds.join(','));
      expect(
        shadow['committeeShadowOmitted'],
        receipt.omittedRubricIds.join(','),
      );
      expect(selector['round'], '4');
      expect(shadow['committeeShadowRound'], '4');
      expect(shadow['committeeShadowTruncated'], 'false');
      final digests =
          jsonDecode(selector['laneInputDigests']!) as Map<String, Object?>;
      expect(digests.keys.toList(), digests.keys.toList()..sort());
      expect(digests, run.selection.laneInputDigests);
    });

    test('step results survive worktree deletion', () async {
      final dir = _tempDir('durable-reaped-');
      const store = FileCommitteeSelectionStore();
      final selectorCtx = _selectorContext(dir.path);
      final selected = await CommitteeSelectionCapability(
        evidenceSource: _CannedEvidence((_) => _testOnlyCode()),
        store: store,
      ).run(selectorCtx.context, selectorCtx.args);
      final selectorPayload = (selected as Ok).payload!;

      final ctx = _routeContext(dir.path, results: _fullCommitteeResults());
      final returned = await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(const Advance({'verdict': 'advance'})),
        store: store,
      ).route(ctx.context, ctx.args);
      final routePayload = (returned as Advance).payload!;

      // The in-round artifacts, while the worktree still exists.
      final runPath = committeeSelectionRunPath(
        dir.path,
        CommitteeStage.codeReview,
      );
      final receiptPath = committeeShadowReceiptPath(
        dir.path,
        selectorPayload['sampleId']!,
      );
      final run = CommitteeSelectionRun.fromJson(
        jsonDecode(File(runPath).readAsStringSync()),
      )!;
      final receipt = CommitteeShadowReceipt.fromJson(
        jsonDecode(File(receiptPath).readAsStringSync()),
      )!;

      // The session closes and the three-gate seam reaps the worktree whole.
      dir.deleteSync(recursive: true);
      expect(File(runPath).existsSync(), isFalse);
      expect(File(receiptPath).existsSync(), isFalse);

      // Everything the packet named still reconstructs from the step results.
      expect(selectorPayload['policyVersion'], run.policyVersion);
      expect(selectorPayload['workBeadId'], run.workBeadId);
      expect(selectorPayload['stage'], run.stage.wire);
      expect(selectorPayload['nodePath'], run.nodePath);
      expect(selectorPayload['source'], run.selection.source.wire);
      expect(int.parse(selectorPayload['round']!), run.round);
      expect(selectorPayload['evidenceDigest'], run.selection.evidenceDigest);
      expect(
        committeeCsv(selectorPayload['selected']),
        run.selection.selectedRubricIds,
      );
      expect(
        committeeCsv(selectorPayload['matchedRules']),
        run.selection.matchedRuleIds,
      );
      expect(
        committeeCsv(selectorPayload['omitted']),
        receipt.omittedRubricIds,
      );
      expect(
        committeeCsv(selectorPayload['missingEvidenceIds']),
        run.evidence.missingEvidenceIds,
      );
      expect(committeeCsv(selectorPayload['classifierAttemptKinds']), [
        for (final attempt in run.attempts) attempt.kind.wire,
      ]);
      expect(selectorPayload['classifierAttempts'], '${run.attempts.length}');
      expect(
        jsonDecode(selectorPayload['laneInputDigests']!),
        run.selection.laneInputDigests,
      );
      expect(selectorPayload['sampleId'], receipt.sampleId);
      expect(selectorPayload['joinId'], receipt.joinId);

      expect(routePayload['committeeShadowSampleId'], receipt.sampleId);
      expect(routePayload['committeeShadowJoinId'], receipt.joinId);
      expect(routePayload['committeeShadowNodePath'], receipt.run.nodePath);
      expect(
        routePayload['committeeShadowRouteNodePath'],
        receipt.route.nodePath,
      );
      expect(
        jsonDecode(routePayload['committeeShadowDownstreamJoinKeys']!),
        receipt.downstreamJoinKeys,
      );
      expect(
        committeeCsv(routePayload['committeeShadowActionLaneIds']),
        receipt.actionLaneIds,
      );
      expect(jsonDecode(routePayload['committeeShadowOmittedLaneGrades']!), {
        for (final id in receipt.omittedRubricIds)
          id: receipt.lanes.singleWhere((lane) => lane.rubricId == id).grade,
      });
      expect(
        jsonDecode(routePayload['committeeShadowOmittedLaneTransports']!),
        {
          for (final id in receipt.omittedRubricIds)
            id: receipt.lanes
                .singleWhere((lane) => lane.rubricId == id)
                .transport,
        },
      );
      expect(
        jsonDecode(routePayload['committeeShadowOmittedLaneDispositions']!),
        {'spec-adherence': null, 'regression-risk': 'overridden'},
      );
      expect(
        committeeCsv(routePayload['committeeShadowActualContributingRunIds']),
        receipt.actual.contributingRunIds,
      );
      expect(
        committeeCsv(routePayload['committeeShadowActualMissingLaneIds']),
        receipt.actual.missingLaneIds,
      );
      expect(
        jsonDecode(routePayload['committeeShadowActualTokensIn']!),
        receipt.actual.tokensIn,
      );
      expect(
        jsonDecode(routePayload['committeeShadowActualTokensOut']!),
        receipt.actual.tokensOut,
      );
      expect(
        jsonDecode(routePayload['committeeShadowActualCostUsd']!),
        receipt.actual.costUsd,
      );
      expect(receipt.counterfactual.costUsd, 0.5);
      expect(routePayload['committeeShadowCounterfactualCostUsd'], '0.5');
      expect(
        jsonDecode(routePayload['committeeShadowLaneDecisions']!),
        jsonDecode(selectorPayload['laneDecisions']!),
      );
      expect(
        routePayload['committeeShadowTruncated'],
        canonicalCommitteeJson(receipt.truncated),
      );
      expect(
        committeeCsv(routePayload['committeeShadowMissingFields']),
        receipt.missingFields,
      );

      // The whole packet, both halves, reconstructed from the reaped round.
      expect(selectorPayload, committeeSelectionResultProjection(run));
      expect(routePayload, {
        'verdict': 'advance',
        ...committeeShadowResultProjection(receipt),
      });
    });

    test('file store schema is version 2', () async {
      final dir = _tempDir('durable-schema-');
      const store = FileCommitteeSelectionStore();
      final selectorCtx = _selectorContext(dir.path);
      final selected = await CommitteeSelectionCapability(
        evidenceSource: _CannedEvidence((_) => _knownCode()),
        store: store,
      ).run(selectorCtx.context, selectorCtx.args);
      final sampleId = ((selected as Ok).payload!)['sampleId']!;

      final ctx = _routeContext(dir.path, results: _fullCommitteeResults());
      await CommitteeShadowRouteCapability(
        delegate: _FakeRoute(const Advance({'verdict': 'advance'})),
        store: store,
      ).route(ctx.context, ctx.args);

      // The IN-ROUND working artifact keeps its existing home and shape: the
      // step result is the durable COPY, never a replacement.
      final runPath = committeeSelectionRunPath(
        dir.path,
        CommitteeStage.codeReview,
      );
      final receiptPath = committeeShadowReceiptPath(dir.path, sampleId);
      expect(runPath, startsWith(dir.path));
      expect(
        runPath,
        endsWith('/$kCommitteeSelectionDir/code_review.selection.json'),
      );
      expect(receiptPath, startsWith(dir.path));
      expect(
        receiptPath,
        endsWith('/$kCommitteeSelectionDir/receipts/$sampleId.json'),
      );

      final runJson =
          jsonDecode(File(runPath).readAsStringSync()) as Map<String, Object?>;
      expect(
        runJson.keys.join(','),
        'version,policyVersion,stage,workBeadId,round,nodePath,selection,'
        'evidence,fullRubricIds,gatingRubricIds,attempts,missingFields,'
        'previous',
      );
      expect(runJson['version'], kCommitteeSelectionWireVersion);
      expect(runJson['version'], 2);

      final receiptJson =
          jsonDecode(File(receiptPath).readAsStringSync())
              as Map<String, Object?>;
      expect(
        receiptJson.keys.join(','),
        'version,sampleId,joinId,run,route,selectedRubricIds,omittedRubricIds,'
        'lanes,actionLaneIds,gateDisposition,downstreamJoinKeys,actual,'
        'classifier,counterfactual,truncated,missingFields,preservedLanes',
      );
      expect(receiptJson['version'], 2);
    });

    test('durable carrier source-shape fence', () {
      final source = File(
        p.join(packageRoot(), 'lib', 'src', 'code', 'committee_selection.dart'),
      ).readAsStringSync();
      final code = [
        for (final line in source.split('\n'))
          if (!line.trimLeft().startsWith('//')) line,
      ].join('\n');

      // ONE store implementation, and only the two writes it already had.
      expect(
        'implements CommitteeSelectionStore'.allMatches(code),
        hasLength(1),
      );
      expect(
        'store.writeRun(workspaceDir, run)'.allMatches(code),
        hasLength(1),
      );
      expect('store.writeReceipt('.allMatches(code), hasLength(1));
      expect(
        'writeAsStringSync'.allMatches(code),
        hasLength(1),
        reason: 'the store\'s own temporary-file write is the ONLY file sink',
      );

      // The projections reach the two EXISTING result carriers and nothing
      // else: one declaration plus one consumer each.
      expect(
        'committeeSelectionResultProjection('.allMatches(code),
        hasLength(2),
      );
      expect('committeeShadowResultProjection('.allMatches(code), hasLength(2));
      expect(
        code,
        contains('final payload = committeeSelectionResultProjection(run);'),
      );
      expect(code, contains('return Ok(payload);'));
      expect(code, contains('...committeeShadowResultProjection(receipt),'));

      // No second sink, and no verification-family record: those types are
      // DEFINED but never emitted, so routing here would reproduce that bug.
      for (final forbidden in const [
        'verify.verdict',
        'verify.usage',
        'TrajectoryDb',
        'TrajectoryAppender',
        'TrajectoryStore',
        'TrajectoryRecord',
        'HttpClient',
        'WebSocket',
        'Socket',
        'openWrite',
        'writeAsBytes',
        'IOSink',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: 'the durable carrier is the step result, not a new sink',
        );
      }
    });
  });
}

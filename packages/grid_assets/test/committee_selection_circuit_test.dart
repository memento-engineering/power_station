// The SHADOW committee selector in composition (bead `pow-1nl.1.1`).
//
// Two named tables, each addressable with `--plain-name`:
//
//  - `shadow authority`  the full committee still runs, its route join is
//                        unchanged, its node paths are stable, and the
//                        authoritative verdict comes back BYTE-FOR-BYTE — under
//                        selector success, store success, and every failure of
//                        both;
//  - `classifier retry`  an unknown shape retries the classifier lane exactly
//                        once, a second non-result records `fullFallback`, a
//                        deterministic match spends nothing, and no sibling is
//                        ever replayed.
//
// Fakes, not mocks: the inference seam, the store, the evidence source and the
// authoritative route are all hand-written recorders. No process is ever
// spawned and no model is ever called.
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart' show RuntimeConfig;
import 'package:grid_sdk/grid_sdk.dart' show ProviderScope;
import 'package:grid_trajectory/grid_trajectory.dart' show GateDisposition;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

// ── Fakes ───────────────────────────────────────────────────────────────────

/// A counting classifier: answers the next scripted output and records the
/// [RuntimeConfig] it was handed (so the model stamp is inspectable).
class _CountingClassifier {
  _CountingClassifier(this.answers);

  final List<({bool ok, String output})> answers;
  final List<RuntimeConfig> calls = [];

  Future<({bool ok, String output})> call(RuntimeConfig config) async {
    calls.add(config);
    return calls.length <= answers.length
        ? answers[calls.length - 1]
        : (ok: false, output: '');
  }
}

/// An in-memory [CommitteeSelectionStore] that can be made to throw.
class _RecordingStore implements CommitteeSelectionStore {
  final Map<String, CommitteeSelectionRun> runs = {};
  final List<CommitteeShadowReceipt> receipts = [];
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

// ── helpers ─────────────────────────────────────────────────────────────────

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// An UNKNOWN code shape: real evidence, but no rule recognises it (no changed
/// paths, no governing decisions) — the ONLY shape a classifier is reached for.
CommitteeSelectionEvidence _unknownCode() => CommitteeSelectionEvidence(
  stage: CommitteeStage.codeReview,
  workBeadId: 'tg-1',
  round: 1,
  intent: const ['title:bead-field:tg-1.title@sha256:aa'],
  missingEvidenceIds: const ['pinned-diff:no-targets'],
);

/// A DETERMINISTIC code shape: one runtime path, three rules' worth of lanes.
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
  required _CountingClassifier classifier,
  required _CannedEvidence evidence,
  required _RecordingStore store,
}) => CommitteeSelectionCapability(
  classifier: classifier.call,
  evidenceSource: evidence,
  store: store,
);

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
        c.starts.where((p) => p.endsWith('/committee-selection')),
        hasLength(1),
      );
    });

    test('the wrapper returns the delegate verdict OBJECT, unchanged, for '
        'every arm — and calls the delegate exactly once', () async {
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
        expect(identical(returned, verdict), isTrue);
        expect(delegate.calls, 1);
        expect(store.receipts, hasLength(1));
        expect(store.receipts.single.route.type, committeeRouteTypeOf(verdict));
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
        'FALLBACK and never waits for the classifier', () async {
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
        classifier: _CountingClassifier(const []),
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
      for (final evidence in [_knownCode(), _unknownCode()]) {
        final ctx = _selectorContext(dir.path);
        final outcome = await _selector(
          classifier: _CountingClassifier(const []),
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
        classifier: _CountingClassifier(const []),
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
        classifier: _CountingClassifier(const []),
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

  group('classifier retry', () {
    test('an unknown shape retries ONCE, then records fullFallback', () async {
      final dir = _tempDir('classifier-retry-');
      final classifier = _CountingClassifier(const [
        (ok: true, output: 'not json at all'),
        (ok: true, output: '{"rubricIds":["adr-alignment"]}'),
      ]);
      final store = _RecordingStore();
      final ctx = _selectorContext(dir.path);
      final outcome = await _selector(
        classifier: classifier,
        evidence: _CannedEvidence((_) => _unknownCode()),
        store: store,
      ).run(ctx.context, ctx.args);

      expect(
        classifier.calls,
        hasLength(kCommitteeClassifierAttempts),
        reason: 'the first call plus EXACTLY one retry',
      );
      final run = store.runs.values.single;
      expect(run.selection.source, CommitteeSelectionSource.fullFallback);
      expect(run.selection.selectedRubricIds, kCommitteeRubrics);
      expect(run.selection.matchedRuleIds, isEmpty);
      expect(run.attempts.map((a) => a.kind), [
        CommitteeClassifierResultKind.malformed,
        CommitteeClassifierResultKind.unknown,
      ]);
      expect(run.attempts.last.rejectedRubricIds, ['adr-alignment']);
      // A20(3): the ladder ALWAYS stamps an explicit model, so no classifier
      // spawn is ever unpinned.
      for (final config in classifier.calls) {
        expect(config.args, contains('--model'));
        expect(
          config.args[config.args.indexOf('--model') + 1],
          kCheapModelDefault,
        );
      }
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload!['classifierAttempts'], '2');
    });

    test('the FIRST legal answer ends the loop', () async {
      final dir = _tempDir('classifier-accept-');
      final classifier = _CountingClassifier(const [
        (ok: true, output: '{"rubricIds":["test-coverage","spec-adherence"]}'),
        (ok: true, output: '{"rubricIds":["regression-risk"]}'),
      ]);
      final store = _RecordingStore();
      final ctx = _selectorContext(dir.path);
      await _selector(
        classifier: classifier,
        evidence: _CannedEvidence((_) => _unknownCode()),
        store: store,
      ).run(ctx.context, ctx.args);
      expect(classifier.calls, hasLength(1));
      final run = store.runs.values.single;
      expect(run.selection.source, CommitteeSelectionSource.classifier);
      expect(run.selection.selectedRubricIds, [
        ...kCodeGatingRubrics,
        'spec-adherence',
        'test-coverage',
      ]);
      expect(run.attempts.single.acceptedRubricIds, [
        'spec-adherence',
        'test-coverage',
      ]);
      expect(run.attempts.single.launched, isTrue);
      expect(run.attempts.single.outputDigest, hasLength(64));
    });

    test('a non-successful run and a blank answer are typed MISSING, not a '
        'grade', () async {
      final dir = _tempDir('classifier-missing-');
      final classifier = _CountingClassifier(const [
        (ok: false, output: '{"rubricIds":["spec-adherence"]}'),
        (ok: true, output: '   '),
      ]);
      final store = _RecordingStore();
      final ctx = _selectorContext(dir.path);
      await _selector(
        classifier: classifier,
        evidence: _CannedEvidence((_) => _unknownCode()),
        store: store,
      ).run(ctx.context, ctx.args);
      expect(classifier.calls, hasLength(2));
      final run = store.runs.values.single;
      expect(run.attempts.map((a) => a.kind), [
        CommitteeClassifierResultKind.missing,
        CommitteeClassifierResultKind.missing,
      ]);
      expect(run.attempts.first.reason, 'classifier:not-ok');
      expect(run.selection.source, CommitteeSelectionSource.fullFallback);
    });

    test('a DETERMINISTIC match spends nothing at all', () async {
      final dir = _tempDir('classifier-skipped-');
      final classifier = _CountingClassifier(const [
        (ok: true, output: '{"rubricIds":["spec-adherence"]}'),
      ]);
      final store = _RecordingStore();
      final ctx = _selectorContext(dir.path);
      await _selector(
        classifier: classifier,
        evidence: _CannedEvidence((_) => _knownCode()),
        store: store,
      ).run(ctx.context, ctx.args);
      expect(classifier.calls, isEmpty);
      final run = store.runs.values.single;
      expect(run.selection.source, CommitteeSelectionSource.deterministic);
      expect(run.selection.matchedRuleIds, ['code-runtime']);
      expect(run.attempts, isEmpty);
    });

    test('no live workspace records two MISSING attempts and launches no '
        'process (the offline fixture posture)', () async {
      final classifier = _CountingClassifier(const [
        (ok: true, output: '{"rubricIds":["spec-adherence"]}'),
      ]);
      final store = _RecordingStore();
      final ctx = _selectorContext('/grid/worktrees/does-not-exist/tg-1');
      final outcome = await _selector(
        classifier: classifier,
        evidence: _CannedEvidence((_) => _unknownCode()),
        store: store,
      ).run(ctx.context, ctx.args);
      expect(classifier.calls, isEmpty);
      final run = store.runs.values.single;
      expect(run.attempts, hasLength(kCommitteeClassifierAttempts));
      expect(run.attempts.map((a) => a.reason), [
        'no-live-workspace',
        'no-live-workspace',
      ]);
      expect(run.attempts.every((a) => a.launched), isFalse);
      expect(run.selection.source, CommitteeSelectionSource.fullFallback);
      expect(outcome, isA<Ok>());
    });

    test('a shape with NO evidence at all falls back without paying for a '
        'guess', () async {
      final dir = _tempDir('classifier-no-evidence-');
      final classifier = _CountingClassifier(const []);
      final store = _RecordingStore();
      final ctx = _selectorContext(dir.path);
      await _selector(
        classifier: classifier,
        evidence: _CannedEvidence(
          (stage) => CommitteeSelectionEvidence(
            stage: stage,
            workBeadId: 'tg-1',
            round: 1,
            missingEvidenceIds: const ['anchors', 'dossier', 'pinned-diff'],
          ),
        ),
        store: store,
      ).run(ctx.context, ctx.args);
      expect(classifier.calls, isEmpty);
      expect(store.runs.values.single.attempts.map((a) => a.reason), [
        'no-evidence',
        'no-evidence',
      ]);
    });

    test('a retry replays NO sibling: the selector reads evidence once per '
        'invocation and touches no other node', () async {
      final dir = _tempDir('classifier-isolation-');
      // FOUR scripted answers: two per invocation, so the second run is an
      // exact repeat rather than a differently-starved one.
      final classifier = _CountingClassifier(const [
        (ok: true, output: 'garbage'),
        (ok: true, output: 'garbage'),
        (ok: true, output: 'garbage'),
        (ok: true, output: 'garbage'),
      ]);
      final evidence = _CannedEvidence((_) => _unknownCode());
      final store = _RecordingStore();
      final selector = _selector(
        classifier: classifier,
        evidence: evidence,
        store: store,
      );
      final ctx = _selectorContext(dir.path);
      await selector.run(ctx.context, ctx.args);
      expect(
        evidence.reads,
        1,
        reason: 'the retry re-runs the CLASSIFIER lane, not the gather',
      );
      final first = store.runs.values.single.toJson();

      // Re-running ONLY the selection capability, with the same evidence, is
      // byte-identical: nothing about the committee siblings moved.
      final again = _selectorContext(dir.path);
      await selector.run(again.context, again.args);
      expect(evidence.reads, 2);
      expect(store.runs.values.single.toJson(), first);
      expect(classifier.calls, hasLength(4));
      expect(store.receipts, isEmpty, reason: 'the selector writes no receipt');
    });
  });
}

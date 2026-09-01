// The SPEC stage, offline end-to-end (bead `pow-6ao`).
//
// Drives the specify → spec-committee head of the `code` circuit through the
// REAL StationKernel + CircuitResolver + buildCodeRegistry, advancing the
// per-node cursor via the fake STATE source (the bridge re-projecting each
// chokepoint write) and feeding the spec grades through the same STATE
// source's `grid.result.*` keys.
//
// Three proofs:
//  - the HAPPY path: a driven bead runs a specify stage in its worktree (the
//    spawned brief carries the spec contract — bd writes, ADR-alignment grep,
//    pre-convene re-validation); the spec committee fans its four LLM lanes
//    out IN PARALLEL while the deterministic gating lane runs for real; an
//    all-pass route advances; ONLY THEN does the build agent spawn.
//  - the GATING-F path: `spec-validation` F (here: the REAL structural gate
//    grading a spec-less bead) → the route parks at a GATE (state=gated, a
//    `type=gate` bead minted — the SAME gated machinery the code committee
//    uses) and the build agent NEVER spawns; the session never closes.
//  - the REAL structural gate's provenance: driven against a bead with NO
//    spec, the gating lane's own chokepoint write records grade=F with the
//    findings — the fail direction is a safe PARK, never a silent advance.
//  - the RESPEC path: a critic D WITH a rationale makes the route COMPLETE
//    carrying an invalidating `grade: F` on its own result, and the engine
//    DERIVES the backward wave off the route's declared `validates` edge —
//    `specify` re-mints as a successor incarnation on a `supersedes` chain,
//    with no gate bead, no human, no session re-mint.
//
// Offline — FAKES, no live tg/gc/claude/bd/git/network.

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

GraphSnapshot _state(List<Bead> beads) => _graph(beads: beads, ready: const {});

/// Every state push in this suite carries the spec circuit's whole CHEAP HEAD
/// complete ([kSpecHeadNodes]: the readiness ladder + the discovery circuit) —
/// dropping those keys would re-mount the head AND re-classify the session onto a
/// FROZEN older circuit (`circuit_migration.dart`), so the suite would silently
/// drive a shape it is not testing. Their own choreography lives in
/// `readiness_acceptance_test.dart` and `discovery_acceptance_test.dart`; here
/// the head is fast-forwarded so the SPEC stage stays the focus.
List<Bead> _session({
  Set<String> completed = const {},
  Set<String> gated = const {},
  Map<String, String> grades = const {},
  Map<String, Map<String, String>> results = const {},
}) => committeeSession(
  completed: {...kSpecHeadNodes, ...completed},
  gated: gated,
  grades: {...kReadinessGradeA, ...grades},
  results: results,
);

const _sid = 'tgdog-sess1';
String _step(String relPath) => '$_sid/tg-1/$relPath';

/// The four LLM spec-critic provider names (the gating lane is a
/// ServiceCapability — it never spawns).
final List<String> _specCriticSteps = [
  for (final n in kSpecCriticNodes) _step(n),
];

StationKernel _buildKernel(
  Fakes f,
  FakeSnapshotSource work,
  FakeSnapshotSource state, {
  BdRunner Function(String workspaceRoot)? specifyBdRunnerFor,
  ExplorationTransport? transport,
}) {
  final bridge = StationJoinBridge(work: work, state: state);
  return StationKernel(
    bridge: bridge,
    stationServices: f.ctx,
    resolver: kCodeResolver,
    registry: buildCodeRegistry(
      rubrics: (id) => '($id rubric bands)',
      gitRunner: f.git,
      shellRunner: RecordingShellRunner(),
      critiqueDirClearer: (_) {},
      specifyBdRunnerFor:
          specifyBdRunnerFor ??
          (_) => SpecifyReadbackBdRunner(beads: [durableSpecifiedBead('tg-1')]),
    ),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(
          const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        ),
        services: ServiceBundle(transport: transport),
        key: const ValueKey('scope.tg'),
      ),
    ],
  );
}

/// True iff some chokepoint `update` targeting [relPath]'s OWN `type=step`
/// bead (id `'$_sid-${relPath with dashes}'`, [stepBead]'s shape) wrote
/// `grid.step.state` == [stateName] — the molecule model's per-node cursor
/// write (tg-eli phase 2): NO `{nodePath}` infix (the bead IS the node), so
/// this checks the TARGET bead id, not a nodePath-keyed metadata field, unlike
/// the retired flat model's `grid.cursor.<nodePath>.state`.
bool _wroteCursor(Fakes f, String relPath, String stateName) {
  final targetId = '$_sid-${relPath.replaceAll('/', '-')}';
  return f.runner.callsFor('update').any((c) {
    if (c.length < 2 || c[1] != targetId) return false;
    return callMetadata(c)[MoleculeStepKeys.state] == stateName;
  });
}

/// The result [field] some chokepoint `update` recorded for [relPath], or
/// null when no update carries that engine-owned result key.
String? _resultField(Fakes f, String relPath, String field) {
  final key = ResultKeys.keyFor('tg-1/$relPath', field);
  for (final c in f.runner.callsFor('update')) {
    final v = callMetadata(c)[key];
    if (v is String) return v;
  }
  return null;
}

bool _gateMinted(Fakes f) =>
    f.runner.callsFor('create').any((c) => c.join(' ').contains('gate'));

/// Re-stages the `type=step` bead(s) named in [grades]/[results] within
/// [beads] with their result metadata embedded ON THE STEP BEAD ITSELF (each
/// step's OWN [StepState] left untouched) — the shape the molecule model's
/// live route decision actually reads
/// (`session_scope.dart`'s `results = stepResults`, built by scanning every
/// `type=step` bead's OWN `grid.result.*` keys), unlike [committeeSession]'s
/// own `grades:`/`results:` params, which stage that payload on the SESSION
/// bead (harmless for an already-`completed` fast-forwarded node — its own
/// route decision was baked in when it was marked complete — but invisible to
/// a route that is about to mount and decide LIVE off its siblings' grades).
/// Mirrors `circuit_acceptance_test.dart`'s `_withGradedCritics`, generalized
/// to any relPath (the spec committee's gating lane included) and to a
/// [results] payload (grade + rationale) for the fixable-respec arm.
List<Bead> _withGraded(
  List<Bead> beads, {
  Map<String, String> grades = const {},
  Map<String, Map<String, String>> results = const {},
}) {
  final payloadByRelPath = <String, Map<String, String>>{
    for (final entry in grades.entries) entry.key: {'grade': entry.value},
    for (final entry in results.entries) entry.key: entry.value,
  };
  final relPathById = {
    for (final relPath in payloadByRelPath.keys)
      '$_sid-${relPath.replaceAll('/', '-')}': relPath,
  };
  return [
    for (final b in beads)
      if (relPathById.containsKey(b.id))
        b.copyWith(
          metadata: {
            ...b.metadata,
            ...nodeResultMetadata(
              'tg-1/${relPathById[b.id]!}',
              payloadByRelPath[relPathById[b.id]!],
            ),
          },
        )
      else
        b,
  ];
}

/// The `reason` the chokepoint stamped on the minted gate bead. The reason is
/// NOT in the `create` argv — `StationBeadWriter.createGate` mints the bead with
/// a `grid gate <session>@<node>` title and then stamps `reason` (with the
/// substation + `blocks`/`node` linkage) in a follow-up `update --metadata`.
String? _gateReason(Fakes f) {
  for (final c in f.runner.callsFor('update')) {
    final reason = callMetadata(c)['reason'];
    if (reason is String) return reason;
  }
  return null;
}

/// Pumps the event queue until the fake harness reaches a FIXED POINT — no new
/// provider spawn/exit AND no new bd runner call across [stableRounds]
/// CONSECUTIVE checks — or [maxPumps] pumps have run, whichever comes first.
/// Built on the shared bounded [settle] helper (`asset_fakes.dart`).
///
/// The molecule model's per-push reconcile is a materially LONGER async chain
/// than the retired flat cursor's single write (tg-eli phase 2): a fresh
/// mint's own pour (`create --graph`) can sit through many consecutive
/// no-visible-change pumps before its reply lands and the cascade resumes, so
/// a single quiet pump is NOT proof of quiescence — [stableRounds] guards
/// against declaring victory on a plateau that is still mid-flight. Still
/// fails a genuine regression (it never quiesces, so it exhausts [maxPumps]).
Future<void> _settle(
  Fakes f, {
  int maxPumps = 1000,
  int stableRounds = 50,
}) async {
  var stable = 0;
  var prevStarted = -1;
  var prevCalls = -1;
  await settle(() {
    final started = f.provider.started.length;
    final calls = f.runner.calls.length;
    if (started == prevStarted && calls == prevCalls) {
      stable++;
    } else {
      stable = 0;
    }
    prevStarted = started;
    prevCalls = calls;
    return stable >= stableRounds;
  }, maxPumps: maxPumps);
}

void main() {
  group('the spec stage — happy path (specify → spec committee → build)', () {
    test('specify spawns FIRST with the spec-contract brief; the four spec '
        'critics fan out IN PARALLEL; an all-pass spec route advances; only '
        'then does the build agent spawn', () async {
      final f = buildFakes(createdId: _sid);
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final specifyReadback = SpecifyReadbackBdRunner(
        beads: [durableSpecifiedBead('tg-1')],
      );
      final kernel = _buildKernel(
        f,
        work,
        state,
        specifyBdRunnerFor: (_) => specifyReadback,
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await _settle(f);

      // 1) a ready owned task → the READINESS LADDER's `intake` head mounts
      //    (bead `pow-q7n`) — deterministic, ZERO agents. Re-project the ladder
      //    complete (cursor adoption) → SPECIFY spawns as the first AGENT (the
      //    1-wide head of the spec phase; the build agent does NOT).
      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await _settle(f);
      expect(
        f.provider.started,
        isEmpty,
        reason: 'the ladder head spawns NO agent — intake is deterministic',
      );
      state.push(_state(ladderDoneSession(id: _sid)));
      await _settle(f);
      // The mount→spawn chain makes no observable fake call until the spawn
      // ITSELF, so pure quiescence can declare victory a beat early. Wait for
      // the spawn — bounded, so a specify that never mounts still FAILS below.
      await settle(() => f.provider.started.isNotEmpty, maxPumps: 1000);
      expect(f.provider.started.map((s) => s.name), [_step(kSpecifyNode)]);
      f.provider.emit(
        SessionStarted(name: _step(kSpecifyNode), pid: 102, pgid: 101),
      );
      await _settle(f);
      final specify = f.provider.started.single.config;
      // The architect brief rides the argv: the bd CLI spec writes, the
      // mandatory ADR-alignment grep of the substation register, and the
      // pre-convene re-validation.
      expect(specify.command, 'sh');
      expect(specify.args, contains('claude'));
      final brief = specify.args.last;
      expect(brief, contains('bd update tg-1 --actor specify --acceptance'));
      expect(brief, contains('bd update tg-1 --actor specify --design'));
      expect(brief, contains('## ADR Alignment'));
      expect(brief, contains(localDecisionRegisterListCommand()));
      expect(
        brief,
        contains(
          localDecisionRegisterGrepCommand(
            r'<keyword1>\|<keyword2>\|<keyword3>',
          ),
        ),
      );
      for (final directory in kLocalDecisionRegisterDirectories) {
        expect(brief, contains(directory));
      }
      expect(brief, contains('the_grid#admission-authority-boundary'));
      expect(brief, contains('Pre-convene re-validation'));

      // 2) specify completes → the spec committee's hygiene step runs for
      //    real (a ServiceCapability, no spawn); re-project its completion.
      f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
      await settle(
        () => _wroteCursor(f, kSpecifyNode, 'complete'),
        maxPumps: 1000,
      );
      expect(_wroteCursor(f, kSpecifyNode, 'complete'), isTrue);
      expect(specifyReadback.calls.single.first, 'query');
      expect(
        specifyReadback.beads.single.acceptanceCriteria.trim(),
        isNotEmpty,
      );
      expect(specifyReadback.beads.single.design.trim(), isNotEmpty);
      state.push(_state(_session(completed: {kSpecifyNode})));
      await _settle(f);
      state.push(
        _state(_session(completed: {kSpecifyNode, kSpecClearCritiqueNode})),
      );
      await _settle(f);

      // 3) the four LLM spec critics fanned out IN PARALLEL; the gating
      //    lane is a ServiceCapability (no spawn) that ran FOR REAL against
      //    the ambient bead — which carries NO spec here, so its own
      //    chokepoint write records the fail-closed structural F with the
      //    findings (the provenance proof).
      final started = f.provider.started.map((s) => s.name).toSet();
      for (final critic in _specCriticSteps) {
        expect(
          started,
          contains(critic),
          reason: 'spec critic $critic fanned out after specify',
        );
      }
      expect(
        started,
        isNot(contains(_step(kAgentNode))),
        reason: 'the build agent must NOT spawn before the spec gate',
      );
      expect(
        _wroteCursor(f, kSpecGateNode, 'complete'),
        isTrue,
        reason:
            'the structural gate always COMPLETES — the grade is '
            'data; the route is the single decision point',
      );
      expect(
        _resultField(f, kSpecGateNode, 'grade'),
        'F',
        reason: 'a spec-less bead grades a REAL structural F',
      );
      expect(
        _resultField(f, kSpecGateNode, 'rationale'),
        contains('## Implementation Plan'),
        reason: 'the findings are LOUD — each missing element named',
      );
      // An LLM lane's prompt: the spec framing + the absolute verdict path.
      final coherence = f.provider.started.firstWhere(
        (s) => s.name == _step('spec_review/coherence'),
      );
      expect(coherence.config.command, 'sh');
      expect(coherence.config.args, contains('claude'));
      expect(coherence.config.args.last, contains('NOT been built'));
      expect(
        coherence.config.args.last,
        contains('.grid/critique/coherence.json'),
      );

      // 4) all lanes complete with PASSING grades (the synthetic STATE
      //    overrides the real F — the happy-path arm) → the route advances.
      for (final critic in _specCriticSteps) {
        f.provider.emit(Exited(name: critic, exitCode: 0));
      }
      await _settle(f);
      state.push(
        _state(
          _withGraded(
            _session(
              completed: {
                kSpecifyNode,
                kSpecClearCritiqueNode,
                kSpecGateNode,
                ...kSpecCriticNodes,
              },
            ),
            grades: kSpecGradesAllA,
          ),
        ),
      );
      await _settle(f);
      expect(
        _wroteCursor(f, kSpecRouteNode, 'complete'),
        isTrue,
        reason: 'all-pass → the spec route advanced (Ok), never gated',
      );
      expect(_gateMinted(f), isFalse);

      // 5) the spec route's advance unblocks the BUILD agent (`agent`
      //    dependsOn spec_review → its terminal route) — the spec phase
      //    complete, the build phase begins.
      state.push(
        _state(_session(completed: kSpecPhaseNodes, grades: kSpecGradesAllA)),
      );
      await _settle(f);
      expect(
        f.provider.started.map((s) => s.name),
        contains(_step(kAgentNode)),
        reason: 'ONLY a passing spec proceeds to the build',
      );
    });
  });

  test(
    'a clean agent exit with an absent spec write fails and flares',
    () async {
      final f = buildFakes(createdId: _sid);
      final transport = RecordingExplorationTransport();
      final specifyReadback = SpecifyReadbackBdRunner(
        beads: [workBead('tg-1')],
      );
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final kernel = _buildKernel(
        f,
        work,
        state,
        specifyBdRunnerFor: (_) => specifyReadback,
        transport: transport,
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await _settle(f);
      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await _settle(f);
      state.push(_state(ladderDoneSession(id: _sid)));
      await settle(
        () => f.provider.started.any(
          (spawn) => spawn.name == _step(kSpecifyNode),
        ),
        maxPumps: 1000,
      );
      f.provider.emit(
        SessionStarted(name: _step(kSpecifyNode), pid: 102, pgid: 101),
      );
      await _settle(f);

      f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
      await settle(
        () =>
            _wroteCursor(f, kSpecifyNode, 'failed') &&
            transport.named('step.failed').isNotEmpty,
        maxPumps: 1000,
      );

      expect(_wroteCursor(f, kSpecifyNode, 'failed'), isTrue);
      expect(_wroteCursor(f, kSpecifyNode, 'complete'), isFalse);
      expect(specifyReadback.calls, [
        ['query', 'id=tg-1', '--json', '--limit', '0'],
      ]);
      expect(
        transport.named('step.failed').single.data['nodePath'],
        'tg-1/$kSpecifyNode',
      );
      final started = f.provider.started.map((spawn) => spawn.name).toSet();
      for (final critic in _specCriticSteps) {
        expect(started, isNot(contains(critic)));
      }
    },
  );

  group('the spec stage — gating-F parks at a GATE (no build)', () {
    test('spec-validation F → the route mints a type=gate bead, writes the '
        'route GATED (the SAME gated state the code committee uses), and the '
        'build agent NEVER spawns', () async {
      final f = buildFakes(createdId: _sid);
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final kernel = _buildKernel(f, work, state);
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await _settle(f);
      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await _settle(f);
      f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
      await _settle(f);
      state.push(
        _state(_session(completed: {kSpecifyNode, kSpecClearCritiqueNode})),
      );
      await _settle(f);
      for (final critic in _specCriticSteps) {
        f.provider.emit(Exited(name: critic, exitCode: 0));
      }
      await _settle(f);

      // The gating lane graded F (a placeholder / spec-less bead); the
      // judgement lanes passed → the route's matrix is a HARD BLOCK.
      state.push(
        _state(
          _withGraded(
            _session(
              completed: {
                kSpecifyNode,
                kSpecClearCritiqueNode,
                kSpecGateNode,
                ...kSpecCriticNodes,
              },
            ),
            grades: {...kSpecGradesAllA, kSpecGateNode: 'F'},
          ),
        ),
      );
      await _settle(f);
      // Same beat: the route's async prelude is silent, so wait for its
      // chokepoint write rather than for quiescence alone.
      await settle(
        () => _wroteCursor(f, kSpecRouteNode, 'gated'),
        maxPumps: 1000,
      );

      expect(
        _wroteCursor(f, kSpecRouteNode, 'gated'),
        isTrue,
        reason: 'a gating-F parks the spec route (state=gated)',
      );
      expect(_wroteCursor(f, kSpecRouteNode, 'complete'), isFalse);
      expect(
        _gateMinted(f),
        isTrue,
        reason:
            'a real type=gate bead was minted — the existing gated '
            'machinery, not a new state',
      );
      // The ESCALATE arm's reason reaches the parked bead and NAMES the lane
      // that hard-blocked (ADR-0000 A13(5)) — a structural F is a human
      // ruling, never an auto-respec.
      expect(_gateReason(f), contains('spec-validation'));
      expect(_gateReason(f), contains('hard block'));

      // Surface the gated cursor → the build agent's dep is never
      // satisfied: no build spawn, no session close.
      state.push(
        _state(
          _session(
            completed: {
              kSpecifyNode,
              kSpecClearCritiqueNode,
              kSpecGateNode,
              ...kSpecCriticNodes,
            },
            gated: {kSpecRouteNode},
            grades: {...kSpecGradesAllA, kSpecGateNode: 'F'},
          ),
        ),
      );
      await _settle(f);
      expect(
        f.provider.started.map((s) => s.name),
        isNot(contains(_step(kAgentNode))),
        reason: 'a failed spec NEVER reaches the build',
      );
      expect(
        f.runner.callsFor('close'),
        isEmpty,
        reason: 'a parked session never closes',
      );
    });
  });

  group('the spec stage — a FIXABLE spec INVALIDATES the specify sub-DAG '
      '(beads `pow-7nm` + `pow-ui8`)', () {
    test(
      'a critic D WITH a rationale stamps an invalidating F on the route, and '
      'the engine DERIVES a successor incarnation for `specify` + everything '
      'downstream IN-SESSION — no type=gate bead, no human, no session '
      're-mint; the build agent never spawns and the session never closes',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle(f);
        work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
        await _settle(f);
        f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
        await _settle(f);
        state.push(
          _state(_session(completed: {kSpecifyNode, kSpecClearCritiqueNode})),
        );
        await _settle(f);
        for (final critic in _specCriticSteps) {
          f.provider.emit(Exited(name: critic, exitCode: 0));
        }
        await _settle(f);

        // The gating lane is clean; ONE judgement lane graded D and said WHY —
        // an actionable critic grade carrying a rationale: the FIXABLE arm.
        state.push(
          _state(
            _withGraded(
              _session(
                completed: {
                  kSpecifyNode,
                  kSpecClearCritiqueNode,
                  kSpecGateNode,
                  ...kSpecCriticNodes,
                },
              ),
              grades: kSpecGradesAllA,
              results: const {
                'spec_review/plan-completeness': {
                  'grade': 'D',
                  'rationale': 'step 3 names no test command',
                },
              },
            ),
          ),
        );
        await _settle(f);

        // The route's own async prelude makes NO observable fake call, so
        // pure quiescence can declare victory before its chokepoint write
        // lands. Wait for the write ITSELF — bounded, so a route that never
        // completes still FAILS the expectation below instead of hanging.
        await settle(
          () => _wroteCursor(f, kSpecRouteNode, 'complete'),
          maxPumps: 1000,
        );

        // The RESPEC arm STAMPS: the route COMPLETES and records the
        // invalidating structured verdict on its OWN result node. It reports NO
        // rewind (the engine routes a reported one to a supervised failure) and
        // parks NOTHING.
        expect(
          _wroteCursor(f, kSpecRouteNode, 'complete'),
          isTrue,
          reason:
              'the route terminalises POSITIVELY — that is exactly what '
              'makes it a valid `validates` SOURCE for the derivation',
        );
        expect(_resultField(f, kSpecRouteNode, 'grade'), 'F');
        expect(_resultField(f, kSpecRouteNode, 'verdict'), 'respec');
        expect(
          _gateMinted(f),
          isFalse,
          reason:
              'a respec mints NO type=gate bead (that is Escalate — a '
              'human park)',
        );
        expect(_wroteCursor(f, kSpecRouteNode, 'gated'), isFalse);

        // Re-project the stamp: the route's OWN step bead now carries
        // `state=complete` + `grade=F`. That snapshot is what the engine's
        // derivation reads off the route step's declared `validates` edge.
        state.push(
          _state(
            _withGraded(
              _session(
                completed: {
                  kSpecifyNode,
                  kSpecClearCritiqueNode,
                  kSpecGateNode,
                  ...kSpecCriticNodes,
                  kSpecRouteNode,
                },
              ),
              grades: {...kSpecGradesAllA, kSpecRouteNode: 'F'},
              results: const {
                'spec_review/plan-completeness': {
                  'grade': 'D',
                  'rationale': 'step 3 names no test command',
                },
              },
            ),
          ),
        );
        await _settle(f);

        // Same posture for the mint: it is scheduled off `build` as a
        // microtask chain that only becomes observable at the `bd dep` call.
        bool mintedSuccessor() => f.runner
            .callsFor('dep')
            .any(
              (c) =>
                  c.contains('supersedes') &&
                  c.contains('$_sid-${kSpecifyNode.replaceAll('/', '-')}'),
            );
        await settle(mintedSuccessor, maxPumps: 1000);

        // BACKWARD MOTION IS DERIVED: the engine mints a SUCCESSOR incarnation
        // `type=step` bead for the invalidated `specify` node and links it to
        // the prior incarnation with a `supersedes` dependency — the new bead
        // id is the re-key that makes keyed reconcile re-run the sub-DAG
        // VIRGIN. No chokepoint rewind write exists any more.
        expect(
          mintedSuccessor(),
          isTrue,
          reason: 'the derivation minted `specify`\'s successor incarnation',
        );

        // NOT a park: still no gate bead, still no human.
        expect(_gateMinted(f), isFalse);

        // The build agent's dep (spec_review → its terminal route) never
        // clears: the route is itself inside `specify`'s invalidated closure,
        // so it is withheld from the frontier while the spec is re-specified.
        expect(
          f.provider.started.map((s) => s.name),
          isNot(contains(_step(kAgentNode))),
          reason: 'a fixable spec re-specs — it NEVER reaches the build',
        );
        expect(
          f.runner.callsFor('close'),
          isEmpty,
          reason:
              'the session stays LIVE across the derived wave — a respec '
              'is not a re-mint',
        );
      },
    );
  });
}

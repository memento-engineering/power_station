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
//
// Offline — FAKES, no live tg/gc/claude/bd/git/network.
import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

GraphSnapshot _state(Bead session) => _graph(beads: [session], ready: const {});

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
  FakeSnapshotSource state,
) {
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
    ),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(
          const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        ),
        key: const ValueKey('scope.tg'),
      ),
    ],
  );
}

/// True iff some chokepoint `update` wrote `grid.cursor.tg-1/<relPath>.state`
/// == [stateName].
bool _wroteCursor(Fakes f, String relPath, String stateName) =>
    f.runner.callsFor('update').any((c) {
      final i = c.indexOf('--metadata');
      if (i < 0 || i + 1 >= c.length) return false;
      final md = jsonDecode(c[i + 1]) as Map<String, dynamic>;
      return md['grid.cursor.tg-1/$relPath.state'] == stateName;
    });

/// The `grid.result.tg-1/<relPath>.<field>` value some chokepoint `update`
/// recorded, or null — the per-lane provenance the host persisted.
String? _resultField(Fakes f, String relPath, String field) {
  for (final c in f.runner.callsFor('update')) {
    final i = c.indexOf('--metadata');
    if (i < 0 || i + 1 >= c.length) continue;
    final md = jsonDecode(c[i + 1]) as Map<String, dynamic>;
    final v = md['grid.result.tg-1/$relPath.$field'];
    if (v is String) return v;
  }
  return null;
}

bool _gateMinted(Fakes f) =>
    f.runner.callsFor('create').any((c) => c.join(' ').contains('gate'));

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

void main() {
  group('the spec stage — happy path (specify → spec committee → build)', () {
    test(
      'specify spawns FIRST with the spec-contract brief; the four spec '
      'critics fan out IN PARALLEL; an all-pass spec route advances; only '
      'then does the build agent spawn',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        // 1) a ready owned task → SPECIFY spawns (the 1-wide head of `code`;
        //    the build agent does NOT).
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await _settle();
        expect(f.provider.started.map((s) => s.name), [_step('specify')]);
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
        expect(brief, contains('docs/adr/*.md'));
        expect(brief, contains('Pre-convene re-validation'));

        // 2) specify completes → the spec committee's hygiene step runs for
        //    real (a ServiceCapability, no spawn); re-project its completion.
        f.provider.emit(Exited(name: _step('specify'), exitCode: 0));
        await _settle();
        state.push(_state(committeeSession(completed: {kSpecifyNode})));
        await _settle();
        state.push(_state(committeeSession(
          completed: {kSpecifyNode, kSpecClearCritiqueNode},
        )));
        await _settle();

        // 3) the four LLM spec critics fanned out IN PARALLEL; the gating
        //    lane is a ServiceCapability (no spawn) that ran FOR REAL against
        //    the ambient bead — which carries NO spec here, so its own
        //    chokepoint write records the fail-closed structural F with the
        //    findings (the provenance proof).
        final started = f.provider.started.map((s) => s.name).toSet();
        for (final critic in _specCriticSteps) {
          expect(started, contains(critic),
              reason: 'spec critic $critic fanned out after specify');
        }
        expect(
          started,
          isNot(contains(_step(kAgentNode))),
          reason: 'the build agent must NOT spawn before the spec gate',
        );
        expect(_wroteCursor(f, kSpecGateNode, 'complete'), isTrue,
            reason: 'the structural gate always COMPLETES — the grade is '
                'data; the route is the single decision point');
        expect(_resultField(f, kSpecGateNode, 'grade'), 'F',
            reason: 'a spec-less bead grades a REAL structural F');
        expect(
          _resultField(f, kSpecGateNode, 'rationale'),
          contains('## Implementation Plan'),
          reason: 'the findings are LOUD — each missing element named',
        );
        // An LLM lane's prompt: the spec framing + the absolute verdict path.
        final coherence = f.provider.started
            .firstWhere((s) => s.name == _step('spec_review/coherence'));
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
        await _settle();
        state.push(_state(committeeSession(
          completed: {
            kSpecifyNode,
            kSpecClearCritiqueNode,
            kSpecGateNode,
            ...kSpecCriticNodes,
          },
          grades: kSpecGradesAllA,
        )));
        await _settle();
        expect(_wroteCursor(f, kSpecRouteNode, 'complete'), isTrue,
            reason: 'all-pass → the spec route advanced (Ok), never gated');
        expect(_gateMinted(f), isFalse);

        // 5) the spec route's advance unblocks the BUILD agent (`agent`
        //    dependsOn spec_review → its terminal route) — the spec phase
        //    complete, the build phase begins.
        state.push(_state(committeeSession(
          completed: kSpecPhaseNodes,
          grades: kSpecGradesAllA,
        )));
        await _settle();
        expect(
          f.provider.started.map((s) => s.name),
          contains(_step(kAgentNode)),
          reason: 'ONLY a passing spec proceeds to the build',
        );
      },
    );
  });

  group('the spec stage — gating-F parks at a GATE (no build)', () {
    test(
      'spec-validation F → the route mints a type=gate bead, writes the '
      'route GATED (the SAME gated state the code committee uses), and the '
      'build agent NEVER spawns',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await _settle();
        f.provider.emit(Exited(name: _step('specify'), exitCode: 0));
        await _settle();
        state.push(_state(committeeSession(
          completed: {kSpecifyNode, kSpecClearCritiqueNode},
        )));
        await _settle();
        for (final critic in _specCriticSteps) {
          f.provider.emit(Exited(name: critic, exitCode: 0));
        }
        await _settle();

        // The gating lane graded F (a placeholder / spec-less bead); the
        // judgement lanes passed → the route's matrix is a HARD BLOCK.
        state.push(_state(committeeSession(
          completed: {
            kSpecifyNode,
            kSpecClearCritiqueNode,
            kSpecGateNode,
            ...kSpecCriticNodes,
          },
          grades: {...kSpecGradesAllA, kSpecGateNode: 'F'},
        )));
        await _settle();

        expect(_wroteCursor(f, kSpecRouteNode, 'gated'), isTrue,
            reason: 'a gating-F parks the spec route (state=gated)');
        expect(_wroteCursor(f, kSpecRouteNode, 'complete'), isFalse);
        expect(_gateMinted(f), isTrue,
            reason: 'a real type=gate bead was minted — the existing gated '
                'machinery, not a new state');

        // Surface the gated cursor → the build agent's dep is never
        // satisfied: no build spawn, no session close.
        state.push(_state(committeeSession(
          completed: {
            kSpecifyNode,
            kSpecClearCritiqueNode,
            kSpecGateNode,
            ...kSpecCriticNodes,
          },
          gated: {kSpecRouteNode},
          grades: {...kSpecGradesAllA, kSpecGateNode: 'F'},
        )));
        await _settle();
        expect(
          f.provider.started.map((s) => s.name),
          isNot(contains(_step(kAgentNode))),
          reason: 'a failed spec NEVER reaches the build',
        );
        expect(f.runner.callsFor('close'), isEmpty,
            reason: 'a parked session never closes');
      },
    );
  });
}

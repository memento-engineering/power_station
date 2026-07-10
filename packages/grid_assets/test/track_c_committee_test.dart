// Track C4 — the committee circuit's frontier (fan-out + await-all join).
//
// Mounts the `code_review` circuit through the FULL new path (CircuitResolver →
// SessionScope → CircuitScope → CapabilityHosts), with the per-node cursor
// advanced via the join (simulating the bridge re-projecting each chokepoint
// write). The four critics are dep-free ⇒ they fan out IN PARALLEL; the `route`
// step depends on all four ⇒ it is withheld until every critic reaches a
// positive terminal (the await-all barrier, already proven by the Burn). A
// recording registry's fake leaf records START/STOP so the frontier is
// observable. Zero I/O.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

NodeCursor _done() => const NodeCursor(state: StepState.complete);

class _Committee {
  _Committee(this.beadId)
    : fakes = buildFakes(),
      reg = RecordingCapabilityRegistry(
        circuits: const {'code_review': kCodeReviewCircuit},
      ),
      joined = JoinedSnapshotNotifier(JoinedSnapshot.empty()),
      owner = TreeOwner();

  final String beadId;
  final Fakes fakes;
  final RecordingCapabilityRegistry reg;
  final JoinedSnapshotNotifier joined;
  final TreeOwner owner;

  final Map<String, NodeCursor> _cursor = {};

  List<String> get events => reg.events;

  void mount() {
    _push();
    owner.mountRoot(
      InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: reg,
            child: InheritedSeed<SessionResolver>(
              value: CircuitResolver((_) => kCodeReviewCircuit),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(_tgConfig),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void advance(Map<String, NodeCursor> delta) {
    events.clear();
    _cursor.addAll(delta);
    _push();
    owner.flush();
  }

  void _push() {
    joined.push(
      JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [Bead(id: beadId, issueType: IssueType.task, status: BeadStatus.open)],
          dependencies: const [],
          readyIds: {beadId},
          capturedAt: DateTime(2026),
        ),
        sessionsByWorkBead: {
          beadId: SessionProjection(
            workBeadId: beadId,
            sessionId: 'tgdog-s',
            cursor: _cursor,
          ),
        },
      ),
    );
  }

  void dispose() => owner.dispose();
}

String _c(String stepId) => 'critic(tgdog-s/tg-1/$stepId)';

void main() {
  group('Track C4 — the code_review committee frontier', () {
    test('at mount, clear-critique starts ALONE (gate-integrity #3) — pin-diff '
        'and the four critics `dependsOn` it and wait', () {
      final c = _Committee('tg-1')..mount();
      addTearDown(c.dispose);
      expect(c.events, ['START clear-critique(tgdog-s/tg-1/clear-critique)']);
    });

    test('once clear-critique completes, pin-diff starts ALONE (scope-pinning, '
        'bead pow-6wo) — the four critics `dependsOn` it and wait', () {
      final c = _Committee('tg-1')..mount();
      addTearDown(c.dispose);
      c.advance({'tg-1/clear-critique': _done()});
      // pin-diff is the sole dependent of clear-critique — the critics wait on
      // IT, so pin-diff START is the only mount (clear-critique also STOPs on
      // the reconcile); no critic or route mounts yet.
      expect(c.events, contains('START pin-diff(tgdog-s/tg-1/pin-diff)'));
      expect(c.events.any((e) => e.contains('critic(')), isFalse);
      expect(c.events.any((e) => e.contains('route(')), isFalse);
    });

    test('once pin-diff completes, the four critics fan out IN '
        'PARALLEL; route is withheld', () {
      final c = _Committee('tg-1')..mount();
      addTearDown(c.dispose);
      c.advance({'tg-1/clear-critique': _done()});
      c.advance({'tg-1/clear-critique': _done(), 'tg-1/pin-diff': _done()});
      // All four critic lanes mount together (dependsOn ONLY pin-diff →
      // parallel fan-out amongst themselves).
      expect(
        c.events,
        containsAll([
          'START ${_c('code-validation')}',
          'START ${_c('spec-adherence')}',
          'START ${_c('regression-risk')}',
          'START ${_c('test-coverage')}',
        ]),
      );
      // The route awaits all four — it must NOT have mounted yet.
      expect(c.events.any((e) => e.contains('route(')), isFalse);
    });

    test('route mounts only once ALL four critics reach a positive terminal '
        '(await-all barrier, with a positive control)', () {
      final c = _Committee('tg-1')..mount();
      addTearDown(c.dispose);
      c.advance({'tg-1/clear-critique': _done()});
      c.advance({'tg-1/clear-critique': _done(), 'tg-1/pin-diff': _done()});

      // Three of four complete — the barrier stays closed (negative control).
      c.advance({
        'tg-1/code-validation': _done(),
        'tg-1/spec-adherence': _done(),
        'tg-1/regression-risk': _done(),
      });
      expect(
        c.events.any((e) => e.contains('route(')),
        isFalse,
        reason: 'one critic still pending ⇒ the await-all barrier holds',
      );

      // The fourth completes — the barrier opens, route mounts (positive
      // control: the withholding above was the barrier itself).
      c.advance({
        'tg-1/code-validation': _done(),
        'tg-1/spec-adherence': _done(),
        'tg-1/regression-risk': _done(),
        'tg-1/test-coverage': _done(),
      });
      expect(
        c.events.any((e) => e.contains('START route(tgdog-s/tg-1/route)')),
        isTrue,
        reason: 'all four critics terminal → the await-all barrier opens',
      );
    });
  });
}

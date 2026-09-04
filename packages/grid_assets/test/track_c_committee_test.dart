// Track C4 — the committee circuit's frontier (fan-out + await-all join).
//
// Mounts the `code_review` circuit through the FULL new path (CircuitResolver →
// SessionScope → CircuitScope → CapabilityHosts), with the per-node cursor
// advanced via the join (simulating the bridge re-projecting each chokepoint
// write). The shape under test is
// `clear-critique → pin-diff → {format-clean, declared-tests-present} →
// {code-validation, spec-adherence, regression-risk, test-coverage} → route`:
// the two DETERMINISTIC checks (bead `pow-jicn`) are the whole frontier after
// pin-diff, the four critics depend on BOTH and so fan out IN PARALLEL only
// once both land, and the `route` step depends on all four ⇒ it is withheld
// until every critic reaches a positive terminal (the await-all barrier,
// already proven by the Burn). A recording registry's fake leaf records
// START/STOP so the frontier is observable. Zero I/O.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderScope;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _tgConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
);

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
      // The availability registry the production root (runGrid)
      // always mounts — watch<T>() misses park here instead of asserting.
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
                    configNotifier: SubstationConfigNotifier(_tgConfig),
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
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
          beads: [
            Bead(
              id: beadId,
              issueType: IssueType.task,
              status: BeadStatus.open,
            ),
          ],
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
const _declared =
    'START declared-tests-present(tgdog-s/tg-1/declared-tests-present)';

void main() {
  group('Track C4 — the code_review committee frontier', () {
    test('at mount, clear-critique starts ALONE (gate-integrity #3) — pin-diff '
        'and the four critics `dependsOn` it and wait', () {
      expect(kCodeReviewCircuit.maxRestarts, 3);
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

    test('once pin-diff completes, the DETERMINISTIC FRONTIER fans out ALONE '
        '(bead pow-jicn) — the four critics `dependsOn` BOTH and wait', () {
      final c = _Committee('tg-1')..mount();
      addTearDown(c.dispose);
      c.advance({'tg-1/clear-critique': _done()});
      c.advance({'tg-1/clear-critique': _done(), 'tg-1/pin-diff': _done()});
      // format-clean + declared-tests-present are the only dependents of
      // pin-diff — the cheap, agent-free checks run BEFORE a priced lane.
      expect(
        c.events,
        containsAll([
          'START format-clean(tgdog-s/tg-1/format-clean)',
          _declared,
        ]),
      );
      expect(c.events.any((e) => e.contains('critic(')), isFalse);
      expect(c.events.any((e) => e.contains('route(')), isFalse);
    });

    test('ONE deterministic sibling is not enough — the four critics stay '
        'withheld until BOTH complete, then fan out IN PARALLEL', () {
      final c = _Committee('tg-1')..mount();
      addTearDown(c.dispose);
      c.advance({'tg-1/clear-critique': _done()});
      c.advance({'tg-1/clear-critique': _done(), 'tg-1/pin-diff': _done()});

      // Only format-clean completes — no critic may mount (negative control:
      // this is what a `declared-tests-present` non-result withholds).
      c.advance({'tg-1/format-clean': _done()});
      expect(
        c.events.any((e) => e.contains('critic(')),
        isFalse,
        reason: 'declared-tests-present still pending ⇒ every lane waits',
      );

      // Both complete — all four critic lanes mount together (they depend on
      // exactly the frontier, so the fan-out amongst themselves is parallel).
      c.advance({
        'tg-1/format-clean': _done(),
        'tg-1/declared-tests-present': _done(),
      });
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
      c.advance({'tg-1/format-clean': _done()});

      // Three of four complete — the barrier stays closed (negative control).
      c.advance({
        'tg-1/format-clean': _done(),
        'tg-1/code-validation': _done(),
        'tg-1/declared-tests-present': _done(),
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
        'tg-1/format-clean': _done(),
        'tg-1/code-validation': _done(),
        'tg-1/declared-tests-present': _done(),
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

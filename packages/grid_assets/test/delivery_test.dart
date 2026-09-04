// The DELIVERY seam (M5 D-4a) — `deliver` replaced `land`.
//
// Delivery is the ACTUATION of the ROOT circuit's terminal Advance, so the land
// step's coverage is split along the engine's own seam and lands here:
// DeliverRouteCapability (the terminal route — it reads the tree, composes the
// PR title/body, writes the body ledger, advances) and GitHubPrDelivery (the
// bound DeliveryMethod — commit residue → force-with-lease push → open-or-REUSE).
//
// Fakes only; the sole real I/O is a temp worktree (the body ledger, and the
// describe pass's worktree-exists guard, read the real filesystem).
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../grid_assets/test/support/asset_fakes.dart';

/// The terminal route's context. [delivery] bound ⇒ the live arm; null ⇒ the
/// commit-only arm. [siblings] is the SESSION-WIDE view `SessionScope` mounts —
/// keyed by full nodePath, which is what lets a ROOT-level `deliver` node resolve
/// the receipt's `<bead>/land/*` keys.
FakeTreeContext _deliverContext({
  required String workspaceDir,
  DeliveryMethod? delivery,
  Bead? beadOverride,
  PrComposition? composition,
  SiblingView? siblings,
}) => FakeTreeContext(
  values: {
    Bead: beadOverride ?? bead('tg-1'),
    Workspace: testWorkspace(
      'tg-1',
      workspaceDir: workspaceDir,
      branch: 'grid/tg-1',
      baseBranch: 'main',
    ),
    ServiceBundle: ServiceBundle(delivery: delivery),
    SiblingView: siblings ?? const SiblingView(),
    if (composition != null) PrComposition: composition,
  },
);

/// The ROOT circuit's terminal node path (`<bead>/deliver`).
StepArgs _deliverArgs() => stepArgs('tg-1/$kDeliverStep');

void main() {
  group('the ROOT circuit delivers at its TERMINAL', () {
    test(
      '`deliver` is a FLAT route step and IS the delivery terminal — a '
      'SubCircuitStep tail would silently degrade the station to commit-only',
      () {
        final byId = {for (final s in kCodeCircuit.steps) s.stepId: s};
        expect(byId[kDeliverStep], isA<CapabilityStep>());
        expect(byId[kDeliverStep]!.dependsOn, {'land'});
        expect(kCodeCircuit.terminalStepId, kDeliverStep);
        expect(
          isDeliveryTerminal(
            circuit: kCodeCircuit,
            circuitPath: 'tg-1',
            stepId: kDeliverStep,
            beadId: 'tg-1',
          ),
          isTrue,
        );
      },
    );

    test('the landing sub-circuit no longer carries a `land` step — the PR is '
        'not a step at all', () {
      expect(
        kLandingCircuit.steps.map((s) => s.stepId),
        isNot(contains('land')),
      );
      expect(kLandingCircuit.terminalStepId, 'revalidate');
    });

    // That the REGISTRY actually binds a capability at `deliver` is proven end
    // to end, through the real kernel, by `acceptance/circuit_acceptance_test`:
    // an unbound capability id mounts an inert leaf and the circuit visibly
    // stalls, so the acceptance drive could not reach the terminal at all.
    test('the terminal step names the SAME capability id the registry binds — '
        'one constant, so the circuit and the registry cannot drift', () {
      final terminal = kCodeCircuit.steps
          .whereType<CapabilityStep>()
          .firstWhere((s) => s.stepId == kCodeCircuit.terminalStepId);
      expect(terminal.capabilityId, kDeliverStep);
    });
  });

  group('DeliverRouteCapability — the terminal route', () {
    late Directory work;
    setUp(() => work = Directory.systemTemp.createTempSync('deliver-route-'));
    tearDown(() => work.deleteSync(recursive: true));

    test('NO delivery bound ⇒ a BARE Advance with no payload, and ZERO '
        'inference spent (the commit-only arm never buys a token)', () async {
      final outcome = await DeliverRouteCapability(
        // An exploding runner: reaching inference at all would fail the test.
        inference: FakeInferenceRunner(output: 'never', ok: false),
      ).route(_deliverContext(workspaceDir: work.path), _deliverArgs());
      expect(outcome, isA<Advance>());
      expect((outcome as Advance).payload, isNull);
      expect(
        File(prBodyPath(work.path)).existsSync(),
        isFalse,
        reason: 'no body ledger is written in the commit-only arm',
      );
    });

    test('delivery bound ⇒ Advance carrying the composed pr_title, and the '
        'composed BODY is on disk at the worktree ledger (kilobytes of prose '
        'never ride the payload into the session bead)', () async {
      final outcome = await const DeliverRouteCapability().route(
        _deliverContext(
          workspaceDir: work.path,
          delivery: _FakeDelivery(),
          beadOverride: bead('tg-1').copyWith(
            title: 'better + configurable PR titles',
            issueType: IssueType.feature,
            metadata: const {'rig': 'power_station'},
          ),
          // The SESSION-WIDE sibling view: the receipt's absolute `<bead>/land/*`
          // keys resolve from this ROOT-level node exactly as they did from the
          // old `<bead>/land/land`.
          siblings: const SiblingView(
            results: {
              'tg-1/land/rebase': {'outcome': 'clean'},
              'tg-1/land/revalidate': {'outcome': 'passed', 'rc': '0'},
              'tg-1/review/route': {
                'grades': 'code-validation=A,spec-adherence=B',
                'spread': '1',
                'rule': 'all-approve',
              },
            },
          ),
        ),
        _deliverArgs(),
      );

      expect(outcome, isA<Advance>());
      final payload = (outcome as Advance).payload!;
      expect(
        payload['pr_title'],
        'feat(power_station): better + configurable PR titles',
      );
      expect(payload['title_source'], 'fallback');
      expect(payload['verdict'], 'deliver');
      expect(payload['validation_rc'], '0');
      expect(payload['committee_grades'], 'code-validation=A,spec-adherence=B');
      expect(
        payload.values.join().length,
        lessThan(500),
        reason: 'the multi-KB body is NOT in the payload',
      );

      final body = File(prBodyPath(work.path)).readAsStringSync();
      expect(body, contains('## Circuit receipt'));
      expect(body, contains('- rebase: clean'));
      expect(body, contains('- revalidate: passed'));
      expect(body, contains('code-validation=A'));
      expect(body.trimRight(), endsWith('Refs: tg-1'));
    });

    test('copies failing landing receipts unchanged into delivery', () async {
      final outcome = await const DeliverRouteCapability().route(
        _deliverContext(
          workspaceDir: work.path,
          delivery: _FakeDelivery(),
          siblings: const SiblingView(
            results: {
              'tg-1/land/revalidate': {'rc': '7'},
              'tg-1/review/route': {
                'grades': 'code-validation=C,spec-adherence=B',
              },
            },
          ),
        ),
        _deliverArgs(),
      );
      final payload = (outcome as Advance).payload!;
      expect(payload['validation_rc'], '7');
      expect(payload['committee_grades'], 'code-validation=C,spec-adherence=B');
    });

    test(
      'an unwritable body ledger throws a RouteFailure — never a PR that '
      'drops the committee grades and the circuit receipt on the floor',
      () async {
        // `.grid` occupied by a FILE ⇒ createSync(recursive: true) throws.
        File(p.join(work.path, '.grid'))
          ..createSync(recursive: true)
          ..writeAsStringSync('not a directory');
        await expectLater(
          const DeliverRouteCapability().route(
            _deliverContext(workspaceDir: work.path, delivery: _FakeDelivery()),
            _deliverArgs(),
          ),
          throwsA(
            isA<RouteFailure>().having(
              (e) => e.reason,
              'reason',
              contains('PR body ledger'),
            ),
          ),
        );
      },
    );

    test('a METERED describe call projects its usage into the terminal payload '
        'and never overwrites a route key', () async {
      File(p.join(work.path, usageReportPath('tg-1/$kDeliverStep')))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'result':
                '{"type":"feat","description":"do a thing",'
                '"summary":"A first sentence. A second one."}',
            'usage': {'input_tokens': 700, 'output_tokens': 90},
            'num_turns': 1,
            'modelUsage': {'claude-haiku-4-5': <String, Object?>{}},
          }),
        );
      final outcome =
          await DeliverRouteCapability(
            gitRunner: CannedGitRunner(log: 'feat(x): do a thing\x00'),
            inference: FakeInferenceRunner(),
          ).route(
            _deliverContext(workspaceDir: work.path, delivery: _FakeDelivery()),
            _deliverArgs(),
          );
      final payload = (outcome as Advance).payload!;
      expect(payload['tokensIn'], '700');
      expect(payload['tokensOut'], '90');
      expect(payload['numTurns'], '1');
      expect(payload['model'], 'claude-haiku-4-5');
      expect(payload['describe_harness'], 'claude');
      expect(payload['describe_model'], 'haiku');
      expect(payload['describe_stop'], 'ok');
      // The route's own keys are intact.
      expect(payload['verdict'], 'deliver');
      expect(payload['title_source'], 'inference');
      expect(payload['pr_title'], startsWith('feat'));
    });

    test('an OFFLINE workspace (no worktree on disk) still advances — the body '
        'ledger is skipped and delivery opens with an empty body; a land never '
        'fails over PR prose', () async {
      final outcome = await const DeliverRouteCapability().route(
        _deliverContext(
          workspaceDir: '/grid/worktrees/does-not-exist-tg-1',
          delivery: _FakeDelivery(),
        ),
        _deliverArgs(),
      );
      expect(outcome, isA<Advance>());
      expect((outcome as Advance).payload!['pr_title'], isNotEmpty);
    });
  });
}

/// A bound delivery method whose presence arms the generic terminal route.
class _FakeDelivery implements DeliveryMethod {
  final List<DeliveryRequest> requests = <DeliveryRequest>[];

  @override
  String get id => 'fake';

  @override
  Future<StepOutcome> deliver(DeliveryRequest request) async {
    requests.add(request);
    return const Ok();
  }
}

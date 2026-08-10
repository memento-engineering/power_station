// M5 "The Circuit" — Track E2: the verify-first committee, offline end-to-end.
//
// Drives the FULL committee-wired `code` path through the REAL StationKernel +
// CircuitResolver + buildCodeRegistry (agent → review[4 critics ∥ → route] →
// land), advancing the per-node cursor via the fake STATE source (the bridge
// re-projecting each chokepoint write) and feeding the critics' grades through
// the same STATE source's `grid.result.*` keys (what the host's result() would
// have persisted; the route reads them via the threaded SiblingView, D-5).
//
// Three proofs: the happy path (agent → 4 critics IN PARALLEL → route advances →
// land → session close); the gating-F path (code-validation F → route parks at a
// GATE — a `type=gate` bead minted, land NEVER runs, the session NEVER closes);
// and flares emitted on the transitions. Offline — FAKES, no live
// tg/gc/claude/git/network.
import 'dart:convert';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../../../grid_assets/test/support/asset_fakes.dart';

// A recording, emit-only exploration transport (D-8): captures every flare.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

GraphSnapshot _state(List<Bead> beads) => _graph(beads: beads, ready: const {});

const _sid = 'tgdog-sess1';
String _step(String relPath) => '$_sid/tg-1/$relPath';

// The committee critic provider names, in committee order.
final List<String> _criticSteps = [for (final n in kCriticNodes) _step(n)];

/// The committee session with the SPEC phase (bead `pow-6ao`) fast-forwarded
/// (fully complete + all-A — cursor adoption: already-complete steps never
/// mount). This test's focus is the CODE committee; the spec phase's own
/// choreography is `spec_stage_acceptance_test.dart`.
List<Bead> _session({
  Set<String> completed = const {},
  Set<String> gated = const {},
  Map<String, String> grades = const {},
  bool closed = false,
}) => committeeSession(
  completed: {...kSpecPhaseNodes, ...completed},
  gated: gated,
  grades: {...kSpecGradesAllA, ...grades},
  closed: closed,
);

/// Re-stages every `kCriticNodes` `type=step` bead in [beads] with an all-A
/// `grid.result.tg-1/review/<rubric>.grade` key ALREADY embedded in its
/// metadata — its OWN [StepState] (`pending`/`complete`/`gated`) is left
/// UNTOUCHED, only the result key is added, so a still-`pending` critic bead
/// still mounts + spawns for real. See the call site's doc for why this
/// pre-staged-on-the-bead-itself shape is what the molecule model's
/// `SiblingView` actually reads (`session_scope.dart`'s `results =
/// stepResults`), unlike [committeeSession]'s own `grades:` (session-bead
/// only, the flat model's shape).
List<Bead> _withGradedCritics(List<Bead> beads) {
  final criticIds = {
    for (final n in kCriticNodes) '$_sid-${n.replaceAll('/', '-')}': n,
  };
  return [
    for (final b in beads)
      if (criticIds.containsKey(b.id))
        b.copyWith(
          metadata: {
            ...b.metadata,
            ...nodeResultMetadata('tg-1/${criticIds[b.id]}', {'grade': 'A'}),
          },
        )
      else
        b,
  ];
}

/// Re-stages the `deliver` `type=step` bead in [beads] with a
/// `grid.result.tg-1/deliver.delivery` key embedded (its OWN [StepState] left
/// untouched) — `SessionScope._deliveryOutcomeReady` (`session_scope.dart`)
/// gates the terminal close on THIS key being present on the delivery node's
/// OWN result slice, the SAME step-bead-only shape [_withGradedCritics] docs:
/// the real `deliver` route already wrote it for real (this drive's OWN
/// earlier chokepoint write carries `grid.result.tg-1/deliver.delivery:
/// "github-pr"`), but that write landed on the REAL bd runner, never on this
/// fake [state] source — so the close check reads it only once THIS push
/// re-stages it, exactly like every other post-hoc cursor re-projection this
/// suite does.
List<Bead> _withDeliveryResult(List<Bead> beads) {
  final deliverId = '$_sid-$kDeliverNode';
  return [
    for (final b in beads)
      if (b.id == deliverId)
        b.copyWith(
          metadata: {
            ...b.metadata,
            ...nodeResultMetadata('tg-1/$kDeliverNode', {
              'delivery': 'github-pr',
            }),
          },
        )
      else
        b,
  ];
}

StationKernel _buildKernel(
  Fakes f,
  FakeSnapshotSource work,
  FakeSnapshotSource state, {
  required String workspaceRoot,
  ExplorationTransport? transport,
  ShellRunner? shellRunner,
}) {
  final bridge = StationJoinBridge(work: work, state: state);
  return StationKernel(
    bridge: bridge,
    stationServices: f.ctx,
    resolver: kCodeResolver,
    // Inject an inline rubric source so the committee is hermetic (no disk read);
    // the on-disk Packaged-AI-Asset loader is exercised by track_d_assets_test.
    // The landing circuit's rebase/revalidate (`tg-rm5`) reuse the SAME
    // recording git fake `land` already lands through, plus a recording shell
    // fake so `revalidate` never spawns a real process.
    registry: buildCodeRegistry(
      rubrics: (id) => '($id rubric bands)',
      // Wrapped so `PinDiffCapability`'s OWN `git rev-parse --show-toplevel`
      // probe (`committee.dart`, bead `pow-4pr`) reads back the REAL checkout
      // root [_provisionCheckout] planted, instead of the bare recorder's
      // ALWAYS-empty output (which resolves, via `path.canonicalize('')`, to
      // this TEST PROCESS's own cwd — never the workspace — so pin-diff would
      // fail-closed refuse every run as an "ancestor checkout" mismatch).
      // Every other subcommand (`fetch`/`rebase`/`add`/`commit`/`push`) still
      // rides straight through to `f.git`, recorded exactly as before.
      gitRunner: _ToplevelAwareGitRunner(
        f.git,
        WorktreeLayout.worktreePath(workspaceRoot, 'tg', 'tg-1'),
      ),
      shellRunner: shellRunner ?? RecordingShellRunner(),
      // A no-op clearer (gate-integrity #3): offline — fakes only, never a
      // real filesystem touch at the synthetic `/grid/worktrees/...` path.
      critiqueDirClearer: (_) {},
      // `buildCodeRegistry`'s OWN default is `inference ?? const
      // SystemInferenceRunner()` — a REAL subprocess runner
      // (`code_capabilities.dart`). Every other offline suite either drives
      // `DeliverRouteCapability` bare (leaving `inference` genuinely null,
      // `pr_describe.dart`'s first guard) or provisions no on-disk workspace
      // (the SECOND guard), so the real runner is never reached. THIS suite
      // does both — a REAL git checkout ([_provisionCheckout]) AND the full
      // `buildCodeRegistry` wiring — so leaving `inference` unset would let
      // `describeBranch` fall through both guards and spawn a REAL `claude`
      // subprocess at the terminal `deliver` route, hanging the suite well
      // past `_settle`'s bounded pump budget (no bd write ever lands for
      // `deliver`, and delivery never actuates — the exact symptom: `land`
      // rebase/revalidate complete for real, but `git.subcommands` never
      // gains `add`/`commit`/`push`). A [FakeInferenceRunner] is the same
      // Fakes-not-mocks seam `spec_stage_acceptance_test.dart`'s committee
      // critics ride; an empty/ok response is fine — `describeBranch` falls
      // back to the deterministic id-free subject on unparseable output.
      inference: FakeInferenceRunner(),
    ),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(
          const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        ),
        // The land SourceControl + the flare transport are provided AT THE SCOPE
        // (ADR-0008 D5 / D-8). ROOTED at a real temp dir ([workspaceRoot],
        // [_provisionCheckout]'d with a REAL git checkout BEFORE the kernel
        // ever mounts an agent step) rather than the bare `/grid/worktrees/...`
        // synthetic placeholder: the molecule model's live ProcessLeaseVendor
        // allocation now runs `assertProvisionedCheckout` (ADR-0009 D3, bead
        // `tg-6jn`) before EVERY agent spawn, which fail-closed REFUSES a
        // workspace with no on-disk `.git` — a real check the retired flat
        // model's capability mount never performed. The land STAGE's own git
        // calls still ride the recording fake (`f.git`), never real git.
        services: ServiceBundle(
          // The source control PROVISIONS; the bound DELIVERY METHOD is what a
          // terminal advance actuates (M5 D-4a). gitRunner: the SAME recording
          // fake gitOps wraps, so the force-with-lease push records offline
          // (never real git).
          sourceControl: GitSourceControl(
            root: RootCheckout(
              path: workspaceRoot,
              substation: 'tg',
              defaultBranch: 'main',
            ),
          ),
          delivery: GitHubPrDelivery(
            gitOps: GitOps(f.git),
            prOpener: f.pr,
            gitRunner: f.git,
          ),
          transport: transport,
        ),
        key: const ValueKey('scope.tg'),
      ),
    ],
  );
}

/// Wraps a [GitRunner] (the bare recorder, `f.git`) so THREE `PinDiffCapability`
/// reads (`committee.dart`, bead `pow-4pr`) answer as a genuine, non-empty
/// checkout+delta would, instead of the bare recorder's ALWAYS-empty `output`
/// (correct for the LAND stage's `fetch`/`rebase`/`add`/`commit`/`push`, which
/// this suite only asserts by subcommand — never their output):
///  - `rev-parse --show-toplevel` → [toplevel] (else `path.canonicalize('')`
///    resolves the empty output to this TEST PROCESS's own cwd, never the
///    workspace, so pin-diff refuses every run as an ancestor-checkout
///    mismatch);
///  - `diff <base>...HEAD` → a non-empty placeholder body (else pin-diff reads
///    an EMPTY delta and Escalates as a stale/no-op bead — A9's empty-delta
///    gate — which this suite's happy path is not testing);
///  - `log --oneline <base>..HEAD` → one placeholder commit line (provenance
///    only; not itself gating, but kept consistent with a non-empty diff).
/// Every OTHER subcommand still delegates straight through, recorded
/// identically to the unwrapped fake.
class _ToplevelAwareGitRunner implements GitRunner {
  _ToplevelAwareGitRunner(this._inner, this.toplevel);

  final GitRunner _inner;
  final String toplevel;

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    final result = await _inner.run(
      workingDirectory: workingDirectory,
      args: args,
    );
    if (args.length >= 2 &&
        args[0] == 'rev-parse' &&
        args[1] == '--show-toplevel') {
      return GitRunResult(exitCode: result.exitCode, output: toplevel);
    }
    if (args.isNotEmpty && args[0] == 'diff') {
      return GitRunResult(
        exitCode: result.exitCode,
        output: '--- a/CHANGE.md\n+++ b/CHANGE.md\n@@ -0,0 +1 @@\n+change\n',
      );
    }
    if (args.isNotEmpty && args[0] == 'log') {
      return GitRunResult(exitCode: result.exitCode, output: 'abc1234 change');
    }
    return result;
  }
}

/// Pre-provisions a REAL git checkout for [beadId] under [root] — at the
/// exact path a real [RootCheckout] resolves (`WorktreeLayout.worktreePath`)
/// — so BOTH `assertProvisionedCheckout` (ADR-0009 D3, bead `tg-6jn`, the
/// ProcessLeaseVendor allocation guard EVERY agent capability mount now runs)
/// AND `PinDiffCapability`'s OWN real `git rev-parse --show-toplevel` probe
/// (bead `pow-4pr` — it shells real git directly, `committee.dart`, never the
/// injected recording fake) see a genuine checkout, instead of refusing the
/// molecule model's live workspace requirement. A bare `.git` marker directory
/// is NOT enough — `PinDiffCapability` distinguishes "workspace absent" (a
/// graceful no-op) from "workspace present but not a real checkout" (a fail-
/// closed `RouteFailure`), so this mirrors `track_c_pin_diff_test.dart`'s own
/// REAL-git fixture pattern: an origin repo with one seed commit, cloned into
/// the worktree path, checked out onto the bead's own branch. Only the
/// SCAFFOLDING is real git; every DRIVEN git op in the circuit itself still
/// rides the recording fake (`f.git`), never real git.
void _provisionCheckout(String root, String beadId) {
  final origin = Directory('$root/origin-src')..createSync(recursive: true);
  _git(['init', '-q', '-b', 'main'], origin.path);
  File('${origin.path}/SEED.md').writeAsStringSync('seed\n');
  _git(['add', '.'], origin.path);
  _commit(origin.path, 'seed');

  final workspaceDir = WorktreeLayout.worktreePath(root, 'tg', beadId);
  Directory(workspaceDir).parent.createSync(recursive: true);
  _git(['clone', '-q', origin.path, workspaceDir]);
  _git([
    'checkout',
    '-q',
    '-b',
    WorktreeLayout.branchFor(beadId),
  ], workspaceDir);
  // A REAL commit beyond origin/main — `PinDiffCapability`'s own stale/no-op
  // guard (`committee.dart`) hard-gates a branch with ZERO delta ("nothing for
  // the critics to review"); the offline circuit under test always drives a
  // bead with a real change, so the fixture must carry one too.
  File('$workspaceDir/CHANGE.md').writeAsStringSync('change\n');
  _git(['add', '.'], workspaceDir);
  _commit(workspaceDir, 'change');
}

/// Runs `git` in [cwd] (defaulting to the process cwd, fine for `clone` whose
/// target is an absolute path), asserting success — real-git FIXTURE SETUP
/// only, mirroring `track_c_pin_diff_test.dart`'s `_git` helper.
void _git(List<String> args, [String? cwd]) {
  final r = Process.runSync('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail(
      'git ${args.join(' ')}${cwd == null ? '' : ' in $cwd'} failed '
      '(${r.exitCode}): ${r.stderr}\n${r.stdout}',
    );
  }
}

/// A commit with a fixed, config-independent identity — mirrors
/// `track_c_pin_diff_test.dart`'s `_commit` helper.
void _commit(String cwd, String message) => _git([
  '-c',
  'user.name=grid-assets-test',
  '-c',
  'user.email=grid-assets-test@memento.engineering',
  'commit',
  '-q',
  '-m',
  message,
], cwd);

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

/// True iff a `type=gate` bead was minted through the chokepoint (createGate).
bool _gateMinted(Fakes f) =>
    f.runner.callsFor('create').any((c) => c.join(' ').contains('gate'));

/// Marks [name] STARTED before this drive emits its `Exited` — the
/// completion-fence contract (`270f9c6`, "prove inferred exits before
/// advancing"): an `Exited` for a name the allocation never observed
/// `SessionStarted` for is a STALE/unproven exit and is correctly dropped,
/// never advancing the step. Mirrors `invariant_4_a37_pristine_source_test
/// .dart`'s own `SessionStarted` emission ahead of its `Exited`.
Future<void> _markStarted(Fakes f, String name) async {
  f.provider.emit(SessionStarted(name: name, pid: 1, pgid: 1));
  await pumpEventQueue();
}

/// Plants the REAL critique artifacts an all-pass round would have written —
/// the gating lane's `.rc` (`CriticCapability.result`, `committee.dart`: an
/// exit-code text, `'0'` ⇒ grade A) and each LLM critic's verdict JSON
/// (`grade`/`nodePath`/`round`, `verdictJsonTemplate`'s shape) — into the REAL
/// git checkout BEFORE this drive emits the matching `Exited`. The molecule
/// model computes `result()` SYNCHRONOUSLY off the real workspace the instant
/// the exit lands (no state-observation round-trip the retired flat model
/// needed), so a manually-pushed `grades:` override arrives too late to beat
/// the real fail-closed default this suite's synthetic `sh`/`claude` spawns
/// never actually satisfy — planting the files IS the round, same as a real
/// pass would leave behind.
void _plantAllPassVerdicts(String workspaceDir, String workBeadId) {
  final dir = Directory('$workspaceDir/.grid/critique')
    ..createSync(recursive: true);
  File(
    '${dir.path}/${kCriticNodes.first.split('/').last}.rc',
  ).writeAsStringSync('0');
  for (final rubric in kCriticNodes.skip(1).map((n) => n.split('/').last)) {
    File('${dir.path}/$rubric.json').writeAsStringSync(
      jsonEncode({
        'grade': 'A',
        'nodePath': '$workBeadId/review/$rubric',
        'round': 0,
      }),
    );
  }
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
  group('The Circuit — happy path (agent → committee → route → land → close)', () {
    test('the four critics fan out IN PARALLEL; all-pass routes to land; the '
        'session closes', () async {
      final f = buildFakes(createdId: _sid);
      f.pr.url = 'https://github.com/memento/genesis/pull/9';
      final transport = _RecordingTransport();
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final tmp = Directory.systemTemp.createTempSync('circuit-acc');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _provisionCheckout(tmp.path, 'tg-1');
      final kernel = _buildKernel(
        f,
        work,
        state,
        workspaceRoot: tmp.path,
        transport: transport,
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await _settle(f);

      // 1) a ready owned task → the READINESS LADDER's `intake` head mounts
      //    (bead `pow-q7n`, a zero-agent ServiceCapability — nothing spawns);
      //    re-project it complete → SPECIFY spawns (bead `pow-6ao`);
      //    fast-forward its phase (an all-pass spec committee via cursor
      //    adoption) → the build agent swaps in.
      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await _settle(f);
      expect(
        f.provider.started,
        isEmpty,
        reason: 'the ladder head spawns NO agent — intake is deterministic',
      );
      state.push(_state(ladderDoneSession(id: _sid)));
      await _settle(f);
      expect(f.provider.started.map((s) => s.name), [_step(kSpecifyNode)]);
      await _markStarted(f, _step(kSpecifyNode));
      f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
      await _settle(f);
      state.push(_state(_session()));
      await _settle(f);
      expect(f.provider.started.map((s) => s.name).last, _step('agent'));

      // 2) agent completes → its host writes agent=complete (+ flares); the
      //    STATE source surfaces the advance → the `review` sub-circuit inflates
      //    its FOUR critic lanes IN PARALLEL.
      await _markStarted(f, _step('agent'));
      f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
      await _settle(f);
      state.push(_state(_session(completed: {kAgentNode})));
      await _settle(f);

      // clear-critique (gate-integrity #3, dep-free) mounted + ran for real
      // — no provider spawn (a ServiceCapability, like rebase/revalidate);
      // the bridge re-projects its completion so pin-diff (which `dependsOn`
      // it) becomes ready.
      state.push(_state(_session(completed: {kAgentNode, kClearCritiqueNode})));
      await _settle(f);

      // pin-diff (scope-pinning, bead pow-6wo) then ran for real — another
      // ServiceCapability, no provider spawn, against the REAL git checkout
      // [_provisionCheckout] planted. Re-project its completion before the
      // four critics (which now `dependsOn` it) become ready.
      state.push(
        _state(
          _session(completed: {kAgentNode, kClearCritiqueNode, kPinDiffNode}),
        ),
      );
      await _settle(f);

      final startedAfterAgent = f.provider.started.map((s) => s.name).toSet();
      for (final critic in _criticSteps) {
        expect(
          startedAfterAgent.contains(critic),
          isTrue,
          reason: 'critic $critic fanned out after the agent',
        );
      }
      // Both lanes spawn `sh` (FT-2 wraps claude for usage capture): the
      // gating lane runs the Validation Plan, an LLM lane exec's claude.
      final gating = f.provider.started.firstWhere(
        (s) => s.name == _step(kCriticNodes.first),
      );
      expect(gating.config.command, 'sh');
      expect(
        gating.config.args[1],
        contains('.grid/critique/code-validation.rc'),
      );
      final llm = f.provider.started.firstWhere(
        (s) => s.name == _step(kCriticNodes[1]),
      );
      expect(llm.config.command, 'sh');
      expect(llm.config.args, contains('claude'));

      // 3) all four critics complete with PASSING grades → the route joins
      //    (await-all), reads the grades via the SiblingView, and advances (Ok).
      _plantAllPassVerdicts(
        WorktreeLayout.worktreePath(tmp.path, 'tg', 'tg-1'),
        'tg-1',
      );
      // Re-project all four critics COMPLETE + all-A BEFORE this drive ever
      // emits their `Exited` — not after: the molecule model computes the
      // route's `SiblingView` off the LATEST pushed [state] the instant its
      // OWN real completion write lands (no external re-observation
      // round-trip the retired flat model needed), so a push that arrives
      // only AFTER `Exited` is already too late for the SAME synchronous
      // cascade that mounts the route. The four spawns already proven above
      // are the REAL fan-out proof; this re-projection is what a real
      // pass's OWN chokepoint writes would have left in the state store by
      // the time an external observer (this fake) caught up.
      state.push(
        _state(
          _withGradedCritics(
            _session(
              completed: {
                kAgentNode,
                kClearCritiqueNode,
                kPinDiffNode,
                ...kCriticNodes,
              },
            ),
          ),
        ),
      );
      await _settle(f);
      for (final critic in _criticSteps) {
        await _markStarted(f, critic);
        f.provider.emit(Exited(name: critic, exitCode: 0));
      }
      await _settle(f);
      expect(
        _wroteCursor(f, kRouteNode, 'complete'),
        isTrue,
        reason: 'all-pass → the route advanced (Ok), never gated',
      );
      expect(_gateMinted(f), isFalse, reason: 'no gate on the happy path');

      // 4) route complete → the `land` SubCircuitStep inflates (`tg-rm5`):
      //    rebase → revalidate → land, each a ServiceCapability (no
      //    provider spawn) running for real through the fakes.
      state.push(
        _state(
          _session(
            completed: {kAgentNode, ...kCriticNodes, kRouteNode},
            grades: {for (final n in kCriticNodes) n: 'A'},
          ),
        ),
      );
      await _settle(f);
      expect(
        _wroteCursor(f, kRebaseNode, 'complete'),
        isTrue,
        reason: 'rebase ran clean (the recording git fake is ok by default)',
      );

      state.push(
        _state(
          _session(
            completed: {kAgentNode, ...kCriticNodes, kRouteNode, kRebaseNode},
            grades: {for (final n in kCriticNodes) n: 'A'},
          ),
        ),
      );
      await _settle(f);
      expect(
        _wroteCursor(f, kRevalidateNode, 'complete'),
        isTrue,
        reason:
            'revalidate ran clean (the recording shell fake is ok by default)',
      );

      state.push(
        _state(
          _session(
            completed: {
              kAgentNode,
              ...kCriticNodes,
              kRouteNode,
              kRebaseNode,
              kRevalidateNode,
            },
            grades: {for (final n in kCriticNodes) n: 'A'},
          ),
        ),
      );
      await _settle(f);
      expect(
        f.git.subcommands,
        containsAll(<String>['fetch', 'rebase', 'add', 'commit', 'push']),
      );
      expect(f.pr.opened, isNotEmpty, reason: 'the terminal advance delivered');
      // The PR TITLE is composed by the terminal route and crosses the
      // value-only DeliveryRequest payload, so it rides this offline drive.
      expect(f.pr.opened.last.title, isNotEmpty);
      // The BODY crosses a WORKTREE LEDGER (`.grid/pr-body.md`, M5 D-4a — a
      // multi-KB body must not ride the terminal payload into the session
      // bead's metadata), so it is proven over a REAL worktree, route →
      // ledger → method: this drive's worktree is the REAL checkout
      // [_provisionCheckout] planted (bead `tg-6jn`'s `assertProvisionedCheckout`
      // guard, wired in ALONGSIDE this suite's molecule migration, requires
      // exactly that on-disk checkout for every OTHER agent mount too — the
      // synthetic `/grid/worktrees/...` placeholder the pre-migration suite
      // used no longer mounts at all), so the route's ledger write lands for
      // real and delivery reads it back non-empty — the circuit receipt
      // (rebase/revalidate outcomes + the describe pass's provenance).
      expect(f.pr.opened.last.body, isNotEmpty);
      expect(f.pr.opened.last.body, contains('## Circuit receipt'));
      expect(f.pr.opened.last.body, contains('rebase: clean'));
      expect(f.pr.opened.last.body, contains('revalidate: passed'));

      // 5) land complete (the terminal step) → SessionScope closes the session.
      state.push(
        _state(
          _withDeliveryResult(
            _session(
              completed: {
                kAgentNode,
                ...kCriticNodes,
                kRouteNode,
                kRebaseNode,
                kRevalidateNode,
                kDeliverNode,
              },
              grades: {for (final n in kCriticNodes) n: 'A'},
            ),
          ),
        ),
      );
      await _settle(f);
      expect(
        f.runner.callsFor('close').where((c) => c[1] == _sid),
        hasLength(1),
        reason: 'land is the terminalStepId → the session closes',
      );

      // 6) flares fired on the transitions (non-blocking, D-8).
      expect(
        transport.flares.map((e) => e.name),
        containsAll(<String>['step.complete']),
      );
      expect(
        transport.flares.every((e) => e.data['sessionId'] == _sid),
        isTrue,
        reason: 'every flare carries the session id',
      );
    });
  });

  group('The Circuit — gating-F parks at a GATE (no auto-advance to land)', () {
    test('code-validation F → the route mints a type=gate bead, writes the route '
        'GATED, and land NEVER runs nor closes the session', () async {
      final f = buildFakes(createdId: _sid);
      final transport = _RecordingTransport();
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final tmp = Directory.systemTemp.createTempSync('circuit-acc');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _provisionCheckout(tmp.path, 'tg-1');
      final kernel = _buildKernel(
        f,
        work,
        state,
        workspaceRoot: tmp.path,
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
      // Fast-forward the spec phase (bead `pow-6ao`): specify exits, the
      // spec committee all-passes via cursor adoption → the agent swaps in.
      await _markStarted(f, _step(kSpecifyNode));
      f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
      await _settle(f);
      state.push(_state(_session()));
      await _settle(f);
      await _markStarted(f, _step('agent'));
      f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
      await _settle(f);
      state.push(_state(_session(completed: {kAgentNode})));
      await _settle(f);
      // clear-critique (gate-integrity #3) then pin-diff (scope-pinning, bead
      // pow-6wo) ran for real; re-project both completions so the four
      // critics — which now transitively dependsOn them — mount.
      state.push(
        _state(
          _session(completed: {kAgentNode, kClearCritiqueNode, kPinDiffNode}),
        ),
      );
      await _settle(f);
      for (final critic in _criticSteps) {
        await _markStarted(f, critic);
        f.provider.emit(Exited(name: critic, exitCode: 0));
      }
      await _settle(f);

      // The gating lane (code-validation) graded F (a non-zero Validation Plan);
      // the others passed → the route's matrix is a HARD BLOCK.
      state.push(
        _state(
          _session(
            completed: {kAgentNode, ...kCriticNodes},
            grades: {
              kCriticNodes.first: 'F', // code-validation
              for (final n in kCriticNodes.skip(1)) n: 'A',
            },
          ),
        ),
      );
      await _settle(f);
      expect(
        _wroteCursor(f, kRouteNode, 'gated'),
        isTrue,
        reason: 'a gating-F parks the route (state=gated), never complete',
      );
      expect(
        _wroteCursor(f, kRouteNode, 'complete'),
        isFalse,
        reason: 'the route did NOT advance',
      );
      expect(
        _gateMinted(f),
        isTrue,
        reason: 'a real type=gate bead was minted',
      );
      expect(transport.flares.map((e) => e.name), contains('step.gated'));

      // Surface the gated cursor (as the store would re-project it) → the route
      // parks, land's dep is never satisfied → land NEVER runs, the session
      // NEVER closes. (Positive control: the happy-path test proves land DOES
      // run + close when the route advances.)
      state.push(
        _state(
          _session(
            completed: {kAgentNode, ...kCriticNodes},
            gated: {kRouteNode},
            grades: {
              kCriticNodes.first: 'F',
              for (final n in kCriticNodes.skip(1)) n: 'A',
            },
          ),
        ),
      );
      await _settle(f);
      expect(f.git.subcommands, isEmpty, reason: 'land never committed');
      expect(f.pr.opened, isEmpty, reason: 'land never opened a PR');
      expect(_wroteCursor(f, kDeliverNode, 'complete'), isFalse);
      expect(
        f.runner.callsFor('close'),
        isEmpty,
        reason: 'a parked session never closes',
      );
    });
  });
}

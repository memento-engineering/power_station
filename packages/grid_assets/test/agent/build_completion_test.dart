// The BUILD step's ROUND-COMMIT fence — the build seat's half of "a oneTurn
// session's completion is judged by COMMIT PRESENCE, not by turn count or exit
// signal" (`the_grid#a38-first-live-arm-proven-the-oneturn-quarantine-fix-three-f`).
//
// The measured round (lunar_station-a7w, 2026-09-13, session tranquility-srjvmb,
// the codex build seat): the builder read its `<bead-id> + instruction` task
// prompt as a `/discover` DIRECTED request, loaded the skill, and ended the turn
// after ONE turn with no edits and no commit. The worktree sat at HEAD == local
// main, clean. The round advanced to review anyway, where code-validation and
// declared-tests-present hard-blocked and two critics graded F — every one of
// them a CONSEQUENCE of the one fact nothing downstream could name. A human
// ruling was spent on what should have been a builder refusal or a retry.
//
// A49 already recorded the shape of the hole it leaves open: the existing
// `CompletionContract.committedWorkspace` fence proves "committed OR never
// edited", so a clean-because-empty tree passes it. This suite pins the other
// half — a round whose base is still its own HEAD.
//
// Offline only: every git call rides an injected fake, and the one real
// filesystem touch is a temp workspace dir (its EXISTENCE is what arms the
// fence; nothing here runs git).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// The harness's own last words — what the builder said instead of committing,
/// verbatim from the measured round's `telemetry/…_agent.usage.json`.
const String _harnessFinalMessage =
    "I'm using the `discover` skill because this is a directed bead request. "
    "I'll load its instructions and bead context, then implement, validate, and "
    'commit only within this worktree.';

/// A [GitRunner] that answers ONLY the round-commit count and records every
/// argv it was handed. Fakes, not mocks: it returns canned answers and asserts
/// nothing itself.
class _CountingGitRunner implements GitRunner {
  _CountingGitRunner({this.output = '1', this.ok = true});

  /// The `rev-list --count` stdout (`''` and `'not-a-number'` are the two
  /// unreadable shapes).
  final String output;

  /// Whether the count call exits zero.
  final bool ok;

  /// Every argv, in call order.
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    return GitRunResult(exitCode: ok ? 0 : 128, output: output);
  }
}

/// A [GitRunner] whose every call THROWS — the "git would not launch at all"
/// shape, which must fail closed rather than escape the result hook untyped.
class _ExplodingGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => throw const ProcessException('git', <String>['rev-list']);
}

/// The mere PRESENCE of a [SourceControl] is what tells the fence the workspace
/// is a real, addressable checkout (the engine's own work-signal fence disarms
/// on exactly the same condition).
class _FakeSourceControl implements SourceControl {
  @override
  String workspaceFor(String beadId) => '/w/$beadId';

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  String get baseBranch => 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}
}

/// A minimal supervised-runtime fake: accepts writes once started and replays
/// protocol frames on demand. Same shape as the sibling channel suites'.
class _Runtime implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final StreamController<List<int>> _output = StreamController<List<int>>();
  bool running = false;

  void emitFrame(Map<String, Object?> frame) =>
      _output.add(utf8.encode('${jsonEncode(frame)}\n'));

  @override
  String exitOutputOf(String name) => '';

  @override
  Future<void> start(String name, RuntimeConfig config) async => running = true;

  @override
  Future<void> stop(String name) async => running = false;

  @override
  Future<void> interrupt(String name) async {}

  @override
  Future<void> write(String name, List<int> bytes) async {
    if (!running) throw SessionNotWritable(name, 'not running');
  }

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream<String>.empty();

  @override
  Stream<List<int>> interactionOutput(String name) => _output.stream;

  @override
  bool isRunning(String name) => running;

  @override
  bool processAlive(String name) => running;

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      running ? const <String>['session'] : const <String>[];

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeEvent? terminalOf(String name) => null;

  @override
  ({int pid, int? pgid})? identityOf(String name) =>
      running ? (pid: 1, pgid: 1) : null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> dispose() async {
    // `close()` on a single-subscription controller with NO listener never
    // completes, so it is fired and forgotten — same posture as the sibling
    // channel suites' runtime fake.
    if (!_output.isClosed) unawaited(_output.close());
    await _events.close();
  }
}

/// A channel adapter over one-line JSON frames — enough protocol to deliver a
/// brief and report ONE completion carrying the harness's final `text`.
class _ProbeAdapter implements AgentSessionAdapter {
  @override
  String get id => 'probe';

  @override
  RuntimeConfig launch({
    required AgentEnvironment environment,
    required Workspace workspace,
    String? model,
    Uri? endpoint,
    String? usageOut,
  }) => RuntimeConfig(
    workDir: workspace.workspaceDir,
    command: 'probe',
    lifecycle: Lifecycle.longLived,
  );

  @override
  List<int> encodeBrief(AgentBrief brief) => utf8.encode('brief\n');

  @override
  List<int> encodeSteer(String text) => utf8.encode('steer\n');

  @override
  Stream<AgentProtocolEvent> decode(Stream<List<int>> stdout) => stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map((line) {
        final frame = jsonDecode(line) as Map<String, dynamic>;
        return AgentProtocolEvent.completed(
          result: <String, String>{'text': frame['text'] as String},
          usage: const UsageReport(numTurns: 1),
        );
      });
}

/// A temp directory that EXISTS — the fence's live-workspace condition.
Directory _workspace() {
  final dir = Directory.systemTemp.createTempSync('grid_build_completion_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Plants the harness's `--output-format json` envelope the ARGV leg recovers
/// its final message from.
void _writeEnvelope(String workspaceDir, String nodePath, {String? text}) =>
    writeUsageEnvelope(
      workspaceDir: workspaceDir,
      usageOut: usageReportPath(nodePath),
      content: usageEnvelopeJson(
        result: text,
        tokensIn: 900,
        tokensOut: 120,
        numTurns: 1,
        model: 'gpt-5.6-sol',
      ),
    );

/// The ambient tree the build seat's effect edges read. [sourceControlled] off
/// is the OFFLINE posture (`SessionScope`'s synthetic workspace, or a
/// composition with no source control at all).
FakeTreeContext _tree(
  String workspaceDir, {
  bool sourceControlled = true,
  String baseBranch = 'main',
  AgentEnvironment? environment,
}) => FakeTreeContext(
  values: <Type, Object>{
    Bead: bead('pow-1'),
    Workspace: Workspace(
      workspaceDir: workspaceDir,
      branch: 'grid/pow-1',
      baseBranch: baseBranch,
    ),
    AgentConfig: const AgentConfig(harness: 'probe'),
    EnvironmentRegistry: EnvironmentRegistry(
      custom: <String, AgentEnvironment>{
        'probe':
            environment ??
            const AgentEnvironment(
              command: 'probe',
              promptMode: PromptMode.arg,
            ),
      },
    ),
    if (sourceControlled)
      ServiceBundle: ServiceBundle(sourceControl: _FakeSourceControl()),
  },
);

const String _nodePath = 'pow-1/agent';

void main() {
  group('the ARGV leg refuses a round that committed nothing', () {
    test('AC-1 — zero commits beyond the round base is a typed noResult '
        'carrying the harness\'s own final message', () async {
      final dir = _workspace();
      _writeEnvelope(dir.path, _nodePath, text: _harnessFinalMessage);
      final git = _CountingGitRunner(output: '0');

      await expectLater(
        AgentCapability(
          gitRunner: git,
        ).result(_tree(dir.path), stepArgs(_nodePath)),
        throwsA(
          isA<CapabilityFailure>()
              .having((f) => f.kind, 'kind', CapabilityFailureKind.noResult)
              .having(
                (f) => f.reason,
                'reason',
                contains(kNoRoundCommitDiagnostic),
              )
              .having((f) => f.reason, 'reason', contains(_harnessFinalMessage))
              .having(
                (f) => f.reason,
                'reason',
                startsWith('agent failed (exit 0) [argv]: '),
              ),
        ),
      );

      // The count is the LOCAL base branch, never `origin/<base>`: a station
      // whose local base is ahead of its remote would otherwise be measured
      // against a ref that is not the tree its worktree was cut from.
      expect(git.calls.single, <String>['rev-list', '--count', 'main..HEAD']);
    });

    test('AC-1 — the refusal withholds review: `review` depends on `agent`, '
        'and a failed step is not a positive terminal', () {
      final review = kCodeCircuit.steps.whereType<SubCircuitStep>().singleWhere(
        (step) => step.stepId == 'review',
      );
      expect(review.dependsOn, <String>{'agent'});
    });

    test(
      'a harness that wrote NO envelope still refuses, and says so',
      () async {
        final dir = _workspace();
        await expectLater(
          AgentCapability(
            gitRunner: _CountingGitRunner(output: '0'),
          ).result(_tree(dir.path), stepArgs(_nodePath)),
          throwsA(
            isA<CapabilityFailure>().having(
              (f) => f.reason,
              'reason',
              contains('<no output captured>'),
            ),
          ),
        );
      },
    );

    test('an UNREADABLE count fails closed — and says something different from '
        '"there is no commit"', () async {
      final dir = _workspace();
      for (final git in <GitRunner>[
        _CountingGitRunner(output: '3', ok: false),
        _CountingGitRunner(output: 'not-a-number'),
        _CountingGitRunner(output: ''),
        _ExplodingGitRunner(),
      ]) {
        await expectLater(
          AgentCapability(
            gitRunner: git,
          ).result(_tree(dir.path), stepArgs(_nodePath)),
          throwsA(
            isA<CapabilityFailure>()
                .having((f) => f.kind, 'kind', CapabilityFailureKind.noResult)
                .having(
                  (f) => f.reason,
                  'reason',
                  contains(kRoundCommitUnreadableDiagnostic),
                )
                .having(
                  (f) => f.reason,
                  'reason',
                  isNot(contains(kNoRoundCommitDiagnostic)),
                ),
          ),
          reason: 'runner $git must fail closed',
        );
      }
    });

    test('a BLANK base branch is unreadable, not a pass — and spends no git '
        'call guessing', () async {
      final dir = _workspace();
      final git = _CountingGitRunner(output: '7');
      await expectLater(
        AgentCapability(
          gitRunner: git,
        ).result(_tree(dir.path, baseBranch: '   '), stepArgs(_nodePath)),
        throwsA(
          isA<CapabilityFailure>().having(
            (f) => f.reason,
            'reason',
            contains(kRoundCommitUnreadableDiagnostic),
          ),
        ),
      );
      expect(git.calls, isEmpty);
    });
  });

  group('AC-4 — a round that DID commit is untouched', () {
    test(
      'a positive count forwards the existing usage payload byte for byte',
      () async {
        final dir = _workspace();
        _writeEnvelope(dir.path, _nodePath, text: 'committed the work');
        final git = _CountingGitRunner(output: '2');

        final fenced = await AgentCapability(
          gitRunner: git,
        ).result(_tree(dir.path), stepArgs(_nodePath));
        // The SAME map the hook returned before the fence existed: an
        // unfenced capability over the identical envelope and tree.
        final unfenced = await const AgentCapability().result(
          _tree(dir.path, sourceControlled: false),
          stepArgs(_nodePath),
        );

        expect(fenced, unfenced);
        expect(fenced, containsPair('tokensIn', '900'));
        expect(fenced, containsPair('numTurns', '1'));
        expect(fenced, containsPair('model', 'gpt-5.6-sol'));
      },
    );

    test('the OFFLINE posture is preserved: no source control, or no workspace '
        'on disk, spends no git call at all', () async {
      final dir = _workspace();
      _writeEnvelope(dir.path, _nodePath, text: 'anything');

      final unmounted = _CountingGitRunner(output: '0');
      expect(
        await AgentCapability(
          gitRunner: unmounted,
        ).result(_tree(dir.path, sourceControlled: false), stepArgs(_nodePath)),
        isNotNull,
      );
      expect(unmounted.calls, isEmpty);

      final absent = _CountingGitRunner(output: '0');
      expect(
        await AgentCapability(
          gitRunner: absent,
        ).result(_tree('/grid/worktrees/pow-1'), stepArgs(_nodePath)),
        isNull,
      );
      expect(absent.calls, isEmpty);
    });
  });

  group('AC-3 — the CHANNEL leg refuses the same round, the same way', () {
    /// Builds the capability's own channel session over the probe adapter and
    /// drives it to its first terminal.
    Future<ProcessSessionUpdate> driveChannel({
      required String workspaceDir,
      required GitRunner git,
      required String text,
    }) async {
      final runtime = _Runtime();
      addTearDown(runtime.dispose);
      final capability = AgentCapability(
        // NO asset registry: this isolates the session, so the provision leg
        // materializes nothing into the worktree at all.
        sessionAdapters: AgentSessionAdapterRegistry(
          <String, AgentSessionAdapter>{'probe': _ProbeAdapter()},
        ),
        gitRunner: git,
      );
      final tree = _tree(
        workspaceDir,
        environment: const AgentEnvironment(
          command: 'probe',
          promptMode: PromptMode.none,
          sessionAdapter: 'probe',
        ),
      );
      final session = capability.createSession(
        runtime: runtime,
        name: 'session',
        attemptId: 'a1',
        instanceFence: 'f1',
        context: tree,
        args: stepArgs(_nodePath),
      )!;
      expect(
        session,
        isA<ArtifactFencedSession>(),
        reason:
            'the channel leg never reaches the engine process dispatcher, '
            'so the fence has to be re-applied by the decorator',
      );
      await runtime.start(
        'session',
        const RuntimeConfig(
          workDir: '/tmp',
          command: 'probe',
          lifecycle: Lifecycle.longLived,
        ),
      );
      final terminal = driveProcessSession(
        session: session,
        runtimeEvents: runtime.events,
      );
      await pumpEventQueue();
      runtime.emitFrame(<String, Object?>{'text': text});
      return terminal;
    }

    test('a one-turn completion with no commit is a FAILURE carrying its own '
        'final text', () async {
      final dir = _workspace();
      final update = await driveChannel(
        workspaceDir: dir.path,
        git: _CountingGitRunner(output: '0'),
        text: _harnessFinalMessage,
      );

      expect(update, isA<ProcessSessionFailed>());
      final failed = update as ProcessSessionFailed;
      expect(failed.kind, CapabilityFailureKind.noResult);
      expect(failed.reason, startsWith('agent failed (exit 0) [probe]: '));
      expect(failed.reason, contains(kNoRoundCommitDiagnostic));
      expect(failed.reason, contains(_harnessFinalMessage));
    });

    test('a committed round still COMPLETES over the channel', () async {
      final dir = _workspace();
      final update = await driveChannel(
        workspaceDir: dir.path,
        git: _CountingGitRunner(output: '1'),
        text: 'committed the work',
      );

      expect(update, isA<ProcessSessionCompleted>());
      expect(
        (update as ProcessSessionCompleted).result,
        containsPair('text', 'committed the work'),
      );
    });

    test('both legs refuse with the SAME diagnostic and the SAME harness '
        'message — only the transport bracket differs', () async {
      final dir = _workspace();
      _writeEnvelope(dir.path, _nodePath, text: _harnessFinalMessage);

      final channel =
          await driveChannel(
                workspaceDir: dir.path,
                git: _CountingGitRunner(output: '0'),
                text: _harnessFinalMessage,
              )
              as ProcessSessionFailed;
      String? argv;
      try {
        await AgentCapability(
          gitRunner: _CountingGitRunner(output: '0'),
        ).result(_tree(dir.path), stepArgs(_nodePath));
      } on CapabilityFailure catch (failure) {
        argv = failure.reason;
      }

      expect(argv, isNotNull);
      expect(
        channel.reason.replaceFirst('[probe]', '[transport]'),
        argv!.replaceFirst('[argv]', '[transport]'),
      );
    });
  });

  group('the empty round gets ONE retry, then parks VISIBLY', () {
    test('AC-3 — noResult is tightened to one initial ride plus one retry, '
        'parking at a gate on the second', () {
      final policy = const AgentCapability().supervisionPolicy(
        stepArgs(_nodePath),
      );
      final retry = policy.policyFor(CapabilityFailureKind.noResult);
      // The engine tests exhaustion AFTER incrementing the restart cursor, so
      // two is one initial ride plus one retry.
      expect(retry.maxRestarts, 2);
      expect(retry.onExhaustion, ExhaustionBehavior.parkAtGate);
      expect(retry.backoff, Backoff.standard);
      // Only noResult is narrowed: a harness that itself failed keeps the
      // circuit's own budget.
      expect(policy.policyFor(CapabilityFailureKind.work), const RetryPolicy());
    });

    test('the declared completion contract keeps the INTERRUPTED-tree fence '
        'composed alongside it', () {
      expect(
        const AgentCapability().completionContract,
        CompletionContract.committedWorkspace,
      );
    });
  });
}

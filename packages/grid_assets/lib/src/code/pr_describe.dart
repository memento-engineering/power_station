/// The DESCRIBE pass (bead `pow-8dx`) — ONE cheap inference call over the bead
/// branch's ACTUAL delta, producing the PR title + the human digest
/// ([PrDescription]).
///
/// **Why a call and not a template** (Nico, 2026-07-12): a title derived from
/// the bead can only ever restate the bead. A title derived from the DIFF says
/// what actually changed — which is the whole point of a conventional-commit
/// git log. So the land step reads the branch's own delta with git and hands it
/// to a CHEAP model (`haiku` by default) as a bounded MANIFEST of facts
/// (`describe_manifest.dart`), never as a patch, in a pure text→JSON
/// completion: no tools, no file writes, no wandering — the model sees exactly
/// the change the committee graded (the same `origin/<base>...HEAD` three-dot
/// range [PinDiffCapability] pins the critics to) and nothing else.
///
/// **Why a [ServiceCapability]'s injected runner and not a new spawned step**:
/// the landing circuit's own doctrine (`landing.dart`) — "`rebase` and
/// `revalidate` are [ServiceCapability]s (not spawned jobs): each is a short,
/// bounded, deterministic operation … and it lets both skip to a clean,
/// PROCESS-FREE [Ok] when land isn't wired". A bounded one-shot completion is
/// that same class of operation, and running it INSIDE the land step (rather
/// than as a new node) keeps a multi-KB PR body out of the session bead's
/// `grid.result.*` metadata, adds no cursor key to migrate (`pow-3p4`), and
/// preserves the landing phase's "no supervised process spawns" property the
/// acceptance suite fences. The HARNESS is reused verbatim
/// ([AgentHarness.spawnFor] — the same renderer the committee's critics ride),
/// so the claude flags, the model selection and the keychain-auth story are
/// identical.
///
/// **FAIL-SAFE, always** — the description is PROVENANCE, never a gate: no
/// runner wired, no worktree on disk, an unreadable log, an empty CHANGED-FILE
/// set, an
/// illegal harness/target combo, a non-zero run, a timeout, or unparseable
/// output each return the empty [DescribeOutcome], and the composition falls
/// back to its deterministic id-free subject. A land NEVER fails over PR prose.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../agent/agent_environment.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/usage_report.dart';
import 'describe_manifest.dart';
import 'docs_committee.dart';
import 'pr_composition.dart';

/// The injectable ONE-SHOT inference seam (Fakes, not mocks — the offline suite
/// always injects). Mirrors [GitRunner]'s shape, but for a harness-rendered
/// [RuntimeConfig] whose stdout is the answer.
abstract interface class InferenceRunner {
  /// Runs [config] to completion in its `workDir` and returns its stdout.
  /// NEVER throws — a launch failure, a timeout, or a non-zero exit is reported
  /// as a non-[InferenceResult.ok] result.
  Future<InferenceResult> run(RuntimeConfig config);
}

/// The result of one [InferenceRunner.run] — success plus the captured stdout.
class InferenceResult {
  /// Creates the result.
  const InferenceResult({required this.ok, required this.output});

  /// Whether the run exited clean (exit 0, no timeout, no launch failure).
  final bool ok;

  /// The run's stdout (the model's answer; empty on a failure).
  final String output;
}

/// The real [InferenceRunner]: `Process.start`s the harness-rendered argv (NO
/// shell — no word-splitting of a prompt that contains a whole diff), collects
/// stdout, and KILLS the child at [timeout] (a hung `claude` must never wedge a
/// land). Constructed as [buildCodeRegistry]'s default; the offline suite always
/// injects a fake.
class SystemInferenceRunner implements InferenceRunner {
  /// Creates the runner over the wall-clock [timeout] a describe call gets.
  const SystemInferenceRunner({this.timeout = const Duration(minutes: 3)});

  /// The wall-clock cap on one describe call; on expiry the child is SIGKILLed
  /// and the run reports not-ok (the composition then falls back).
  final Duration timeout;

  @override
  Future<InferenceResult> run(RuntimeConfig config) async {
    try {
      final process = await Process.start(
        config.command,
        config.args,
        workingDirectory: config.workDir,
        environment: config.env.isEmpty ? null : config.env,
      );
      // Drain BOTH pipes before awaiting the exit code — a child that fills an
      // undrained stderr pipe would deadlock.
      final stdoutText = process.stdout.transform(utf8.decoder).join();
      final stderrText = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      final output = await stdoutText;
      await stderrText;
      return InferenceResult(ok: code == 0, output: output);
    } catch (_) {
      // A `claude` that will not launch — fail-safe, never a throw into land.
      return const InferenceResult(ok: false, output: '');
    }
  }
}

/// What the describe pass produced — the inferred [description] (null ⇒ the
/// deterministic fallback), the branch's [commits] policy report, which channel
/// produced the title ([source]: `inference` | `fallback`), and the call's
/// [usage].
class DescribeOutcome {
  /// Creates the outcome; the const default IS the fallback (no inference, no
  /// commits read, no usage spent).
  const DescribeOutcome({
    this.description,
    this.commits = const CommitLintReport(),
    this.source = 'fallback',
    this.usage = const {},
  });

  /// The inferred title/body parts; null ⇒ fall back deterministically.
  final PrDescription? description;

  /// The branch's commit-policy report (receipt provenance).
  final CommitLintReport commits;

  /// `inference` | `fallback` — receipt provenance.
  final String source;

  /// The FT-2 usage fields this describe call spent, ready to merge into the
  /// terminal route's `Advance` payload (`grid.result.<nodePath>.*` — the
  /// station's normal usage projection, A20(5)). EMPTY when no call was made.
  final Map<String, String> usage;
}

/// Reads the bead branch's own delta AS FACTS and runs the ONE-SHOT describe
/// inference over a bounded manifest of them. Every failure path returns a
/// fallback [DescribeOutcome] — the description is decoration, never a land
/// blocker.
///
/// [nodePath] is the delivering node's path: it names the FT-2 telemetry file
/// this call's usage envelope lands at ([usageReportPath]), so the otherwise
/// unmetered describe call is projected exactly like every spawned seat's. Its
/// cost is priced off [ambient]'s declared `modelPrices` when the harness
/// reports none, and [flare] — the route's own `ExplorationTransport.flare`,
/// injected because this is a pure function over its inputs — names a model
/// that has no declared price (bead `pow-zetn`).
///
/// The two guards that keep the WHOLE offline suite free of real git and real
/// claude are the first two lines: an unwired [inference] (a bare
/// `const DeliverRouteCapability()` — every offline unit test) and a workspace dir
/// does not exist on disk (the synthetic `/grid/worktrees/…` and `/w/tg-1` paths
/// every offline fixture mounts) each return before ANY subprocess. The
/// dir-existence posture is the same one `PinDiffCapability` and
/// `AgentCapability`'s pub linkage already take; a LIVE land always has a real
/// worktree the agent just worked in.
Future<DescribeOutcome> describeBranch({
  required Bead bead,
  required String beadId,
  required String nodePath,
  required Workspace workspace,
  required PrComposition composition,
  required AgentConfig ambient,
  required EnvironmentRegistry registry,
  List<DescribeReceipt> receipts = const [],
  GitRunner? git,
  InferenceRunner? inference,
  UsageFlare? flare,
}) async {
  if (inference == null) return const DescribeOutcome();
  if (!Directory(workspace.workspaceDir).existsSync()) {
    return const DescribeOutcome();
  }

  final runner = git ?? SystemGitRunner();
  final workDir = workspace.workspaceDir;
  final base = 'origin/${workspace.baseBranch}';

  // The branch's OWN commits (subject + body, NUL-separated) — the commit-policy
  // lint's input (directive item 5) and the manifest's canonical account of what
  // changed and why.
  final log = await runner.run(
    workingDirectory: workDir,
    args: ['log', '--format=%s%n%b%x00', '$base..HEAD'],
  );
  final messages = log.ok ? _records(log.output) : const <String>[];
  final commits = lintCommitSubjects(
    messages,
    foreignRef: beadId,
    trailerToken: composition.trailerToken,
  );

  // The branch's delta as FACTS, never as a patch: name-status + numstat (both
  // `-z`) and the aggregate shortstat, over the SAME three-dot merge-base range
  // `PinDiffCapability` pins the critics to — so the PR still describes exactly
  // the code the committee graded. The patch-producing `git diff $base...HEAD`
  // read is GONE: nothing here reads a hunk.
  final nameStatus = await runner.run(
    workingDirectory: workDir,
    args: ['diff', '--name-status', '-z', '$base...HEAD'],
  );
  final numstat = await runner.run(
    workingDirectory: workDir,
    args: ['diff', '--numstat', '-z', '$base...HEAD'],
  );
  final shortstat = await runner.run(
    workingDirectory: workDir,
    args: ['diff', '--shortstat', '$base...HEAD'],
  );
  if (!nameStatus.ok) return DescribeOutcome(commits: commits);
  final files = changedFilesFrom(
    nameStatus: nameStatus.output,
    numstat: numstat.ok ? numstat.output : '',
  );
  if (files.isEmpty) return DescribeOutcome(commits: commits);

  // The AMBIENT AgentConfig ONLY (never the bead's `grid.agent` envelope): the
  // describe pass is STATION policy over the landing prose, not the bead's work
  // agent — a bead that pins its own coding harness/model must not re-point the
  // PR description at it. The composition's cheap `model` is merged over the
  // station's params. An unknown harness or an illegal harness × target combo
  // FALLS BACK (this is decoration; `resolveAgentConfig`'s fail-closed throw is
  // for WORK, not for prose).
  final config = ambient.merge(params: {'model': composition.model});
  final AgentEnvironment env;
  try {
    env = registry.resolve(config.harness);
  } on EnvironmentRegistryError {
    return DescribeOutcome(commits: commits);
  }
  if (env.validate() != null) return DescribeOutcome(commits: commits);

  final manifest = buildDescribeManifest(
    DescribeManifest(
      beadId: beadId,
      beadTitle: bead.title,
      baseBranch: workspace.baseBranch,
      intent: bead.acceptanceCriteria,
      commits: messages,
      files: files,
      shortstat: shortstat.ok ? shortstat.output : '',
      shape: changeShapeOf(bead),
      receipts: receipts,
    ),
  );

  final run = await inference.run(
    spawnFor(
      environment: env,
      model: config.params['model'],
      brief: AgentBrief(
        task: buildDescribePrompt(
          beadId: beadId,
          manifest: manifest,
          trailerToken: composition.trailerToken,
        ),
      ),
      workspace: workspace,
      // FT-2 capture: the describe call was the one inference the station spent
      // unmetered. `describe` is ambient claude (provider-managed): no endpoint.
      usageOut: usageReportPath(nodePath),
    ),
  );
  // With capture armed the harness redirects its WHOLE `--output-format json`
  // envelope to the telemetry file, so the model's answer is that envelope's
  // `result` text; a harness with no usage surface still answers on stdout.
  // Both reads are fail-safe (absent/unreadable/malformed ⇒ null / '').
  final answer = readEnvelopeResultText(workDir, nodePath) ?? run.output;
  final described = run.ok ? PrDescription.parse(answer) : null;
  final model = config.params['model'];
  return DescribeOutcome(
    description: described,
    commits: commits,
    source: described == null ? 'fallback' : 'inference',
    usage: {
      // The describe pass prices off the AMBIENT config's declared table — the
      // same value every other lane's usage merge reads (bead `pow-zetn`).
      ...readUsageFields(
        workDir,
        nodePath,
        modelPrices: ambient.modelPrices,
        flare: flare,
      ),
      'describe_harness': config.harness,
      if (model != null && model.isNotEmpty) 'describe_model': model,
      'describe_stop': run.ok ? 'ok' : 'failed',
    },
  );
}

/// The non-blank NUL-separated records of a `git log --format=…%x00` body.
List<String> _records(String output) => [
  for (final record in output.split('\x00'))
    if (record.trim().isNotEmpty) record.trim(),
];

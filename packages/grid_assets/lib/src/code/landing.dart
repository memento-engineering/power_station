/// The LANDING circuit (bead `tg-rm5`) — `rebase → revalidate → land`, a
/// [SubCircuitStep] the `code` circuit's own `land` step now inflates
/// (replacing the flat `land` [CapabilityStep] M5 Track E shipped).
///
/// **Why**: with N parallel beads landing against one repo, the second bead to
/// land was validated against a `main` that has since moved (its own
/// Validation Plan ran BEFORE the first bead's PR merged) — the stale-base
/// hole. This circuit closes it: rebase the bead branch onto the CURRENT base
/// before re-running the bead's OWN Validation Plan against the REBASED tree,
/// gating (never silently forcing through) on either a rebase conflict or a
/// revalidation failure. Both `rebase` and `revalidate` are [ServiceCapability]s
/// (not spawned jobs): each is a short, bounded, deterministic operation —
/// consistent with [LandCapability]'s own commit/push/PR orchestration, and it
/// lets both skip to a clean, PROCESS-FREE [Ok] when land isn't wired (the
/// commit-only early arm), exactly like [LandCapability] already does.
///
/// **Design ruling (Nico + operator, 2026-07-03) — supersedes the original
/// `grid.base` design-note ask**: there is NO `grid.base` metadata key, and
/// none is planned. (1) A hard `dependsOn` already suffices for STACKING
/// today: a dependent bead's worktree is cut from a root head that already
/// contains its parent once the parent lands (dependency serialization), and
/// the factory's circuit latency (minutes, not the human-review-latency a
/// stacked-branch workflow exists to avoid) removes the usual motive for
/// stacking. (2) IF stacking ever earns its way in (long dependent chains
/// where circuit latency compounds), it is a TYPED DEPENDENCY EDGE — e.g.
/// `stacks-on:<bead>` — carrying both ordering AND a base pointer, consumed by
/// THIS landing circuit (the worktree cuts from the target bead's branch, the
/// branch name derived via `beadId -> grid/<beadId>`, never carried as bead
/// metadata) — landing a stack in dependency order. Never a metadata key;
/// branch names never appear in bead data.
///
/// **The receipt-regression callout**: `PrOpener.open`/`GhPrOpener` (grid_runtime)
/// already carry a `body` param through to `gh pr create --body`, but the
/// engine's `SourceControl.openPr` (grid_engine) never grew one — so `land`
/// has only ever opened EMPTY-body PRs, dropping the code-review committee's
/// grade/route provenance (and now this circuit's rebase/revalidate outcome)
/// on the floor. [buildCircuitReceipt] assembles that provenance; until a
/// future the_grid change widens `SourceControl.openPr` itself,
/// [ReceiptCapableSourceControl] (`code_capabilities.dart`) is the power_station-
/// local stopgap `LandCapability` detects via `is` to actually thread it into
/// the real PR body today.
///
/// **Rework-aware delivery (`tg-w3c`)**: after a rework round REBASES the
/// branch, the `land` step's plain push is refused non-fast-forward and its
/// `gh pr create` errors "already exists" — wedging a DONE, approved bead into
/// escalation. [ReworkAwareSourceControl] is the SAME `is`-detected stopgap
/// posture: force-with-lease push + idempotent (reuse-an-open-PR) open, each
/// returning the git/gh output so the land step stamps the stderr tail as the
/// FT-1 `failureReason`.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// The landing circuit (id `landing`) — `code`'s own `land` step now inflates
/// this as a [SubCircuitStep] instead of a flat [CapabilityStep] (M5 Track E's
/// shape). `rebase` and `revalidate` each gate (never silently force) on
/// failure; `land` (unchanged: commit → push → open PR) only runs once both
/// have advanced clean.
const Circuit kLandingCircuit = Circuit(
  id: 'landing',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'rebase', capabilityId: 'rebase'),
    CapabilityStep(
      stepId: 'revalidate',
      capabilityId: 'revalidate',
      dependsOn: {'rebase'},
    ),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'revalidate'}),
  ],
);

/// The REBASE step — rebases the bead branch onto the CURRENT base branch tip.
/// A conflict (or any other rebase failure) ABORTS the rebase (never leaves
/// the worktree mid-rebase) and [Gate]s with the git output as provenance —
/// never a silent force-through. Offline-safe: mirrors [LandCapability]'s own
/// no-op posture — when land isn't wired (`--land` off, the commit-only early
/// arm), this skips straight to [Ok] with NO git call at all.
class RebaseCapability extends ServiceCapability {
  /// Creates the capability, optionally over an injected [runner] (tests
  /// inject the SAME [RecordingGitRunner] fake `GitSourceControl`'s `GitOps`
  /// already uses — Fakes, not mocks); defaults to the real [SystemGitRunner].
  const RebaseCapability({GitRunner? runner}) : _runner = runner;

  final GitRunner? _runner;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final services =
        context.getInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final sc = services.sourceControl;
    if (sc == null || !sc.canLand || workspace == null) return const Ok();

    final runner = _runner ?? SystemGitRunner();
    final workDir = workspace.workspaceDir;
    final base = workspace.baseBranch;

    final fetch = await runner.run(
      workingDirectory: workDir,
      args: ['fetch', 'origin', base],
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');
    if (!fetch.ok) {
      return Failed('git fetch origin $base failed: ${fetch.output.trim()}');
    }

    final rebase = await runner.run(
      workingDirectory: workDir,
      args: ['rebase', 'origin/$base'],
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');
    if (rebase.ok) return const Ok({'outcome': 'clean'});

    // Never leave the worktree mid-rebase; the abort result is best-effort
    // (the Gate below is what matters — the conflict provenance).
    await runner.run(workingDirectory: workDir, args: ['rebase', '--abort']);
    return Gate('rebase onto $base conflicted: ${rebase.output.trim()}');
  }
}

/// The REVALIDATE step — re-runs the bead's OWN Validation Plan (the SAME
/// command the code-review committee's gating lane runs,
/// `committee.dart`'s `kGatingRubric`) against the REBASED tree, closing the
/// stale-base hole (a plan that passed pre-rebase may fail post-rebase). A
/// non-zero plan [Gate]s with the captured output as provenance — never a
/// silent advance. Offline-safe: mirrors [RebaseCapability] — when land isn't
/// wired, skips straight to [Ok] with NO shell exec at all (a plan re-run
/// only matters when a rebase actually moved the tree to re-validate
/// against).
class RevalidateCapability extends ServiceCapability {
  /// Creates the capability, optionally over an injected [runner] (tests
  /// inject a recording fake — Fakes, not mocks); defaults to the real
  /// [SystemShellRunner].
  const RevalidateCapability({ShellRunner? runner}) : _runner = runner;

  final ShellRunner? _runner;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final services =
        context.getInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final sc = services.sourceControl;
    if (sc == null || !sc.canLand || workspace == null || bead == null) {
      return const Ok();
    }

    final runner = _runner ?? const SystemShellRunner();
    final result = await runner.run(
      workingDirectory: workspace.workspaceDir,
      command: _validationPlan(bead),
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');
    if (result.ok) return const Ok({'outcome': 'passed'});
    return Gate('revalidate failed: ${_truncate(result.output)}');
  }
}

/// The injectable shell-exec seam [RevalidateCapability] runs the bead's
/// Validation Plan through — mirrors [GitRunner]'s shape (Fakes, not mocks),
/// but for an arbitrary shell command rather than `git`.
abstract interface class ShellRunner {
  /// Runs [command] via `sh -c` with [workingDirectory] as the cwd. Never
  /// throws — a launch failure is reported as a non-zero [ShellRunResult].
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
  });
}

/// The result of one [ShellRunner.run] — the exit code and combined
/// stdout+stderr.
class ShellRunResult {
  /// Creates the result.
  const ShellRunResult({required this.exitCode, required this.output});

  /// The process exit code.
  final int exitCode;

  /// stdout and stderr combined.
  final String output;

  /// Whether the command succeeded (exit 0).
  bool get ok => exitCode == 0;
}

/// The real [ShellRunner]: execs `sh -c <command>` via `dart:io`. Constructed
/// as [RevalidateCapability]'s default; the offline test suite always injects
/// a fake.
class SystemShellRunner implements ShellRunner {
  /// Creates the runner.
  const SystemShellRunner();

  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
  }) async {
    final result = await Process.run(
      'sh',
      ['-c', command],
      workingDirectory: workingDirectory,
    );
    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString();
    return ShellRunResult(
      exitCode: result.exitCode,
      output: stderr.isEmpty ? stdout : '$stdout$stderr',
    );
  }
}

/// Assembles the landing circuit's OWN PR-body provenance section (`tg-rm5`):
/// the rebase/revalidate outcomes, read via the ambient [SiblingView] at
/// [beadId]'s absolute node paths. The code-review committee's grade line MOVED
/// to `PrSection.committeeGrades` and the description/commit-policy provenance
/// lines are appended by that section's renderer (`pr_composition.dart`, bead
/// `pow-8dx`) — this receipt now carries ONLY what the landing circuit itself
/// did. Pure + deterministic (no I/O) so it is unit-testable in isolation.
String buildCircuitReceipt({
  required String beadId,
  required SiblingView siblings,
}) {
  final rebase = siblings.resultOf('$beadId/land/rebase');
  final revalidate = siblings.resultOf('$beadId/land/revalidate');
  final b = StringBuffer()
    ..writeln('## Circuit receipt')
    ..writeln()
    ..writeln('- rebase: ${rebase['outcome'] ?? 'clean'}')
    ..writeln('- revalidate: ${revalidate['outcome'] ?? 'passed'}');
  return b.toString();
}

/// A [SourceControl] widened for REWORK-AWARE delivery (bead `tg-w3c`) — the
/// same power_station-local, `is`-detected stopgap posture as
/// [ReceiptCapableSourceControl] / [TreeVerifiableSourceControl]
/// (`code_capabilities.dart`), but for the two land-step operations a
/// preceding REWORK ROUND breaks once it rebases the bead branch (live
/// evidence: tg-hsh round 2, session tgdog-6d8):
///
///  1. **push** — a rework round REBASES the branch, so its plain `git push`
///     (`SourceControl.push`, `git push -u`) is refused NON-FAST-FORWARD.
///     [pushForBranch] force-pushes with `--force-with-lease` ALWAYS — safe
///     because it is the CIRCUIT'S OWN branch (`grid/<beadId>`), and the lease
///     still refuses if a racing writer moved the remote out from under it.
///     It returns the git result (ok + combined output) — the engine's
///     `SourceControl.push` is `void`, dropping BOTH the force semantics and
///     the stderr the land step must stamp as its `failureReason`.
///  2. **PR open** — round one's PR is still OPEN, so `gh pr create`
///     (`SourceControl.openPr`) errors "a pull request already exists".
///     [openOrReusePr] treats an already-open PR as SUCCESS (returns its url)
///     instead of a null that becomes a generic `Failed` → retry →
///     breaker-exhausted → escalation of a bead whose work was DONE and
///     approved.
///
/// [LandCapability] detects this via `is` and prefers these over the plain
/// [SourceControl.push] / [SourceControl.openPr]; a bare [SourceControl] (a
/// test fake, or a future non-Git impl) still lands through the unwidened
/// interface methods.
abstract interface class ReworkAwareSourceControl implements SourceControl {
  /// Force-with-lease push of [branch] to [remote] from [workspaceDir] — the
  /// rework-safe replacement for [SourceControl.push]. Returns the push's
  /// success plus the git combined output (the land step stamps its
  /// [LandPushOutcome.output] TAIL as the FT-1 `failureReason` on failure).
  Future<LandPushOutcome> pushForBranch({
    required String workspaceDir,
    required String remote,
    required String branch,
  });

  /// Opens a PR for [branch] against [baseBranch] with [body], or — when one is
  /// already OPEN for [branch] — REUSES it (idempotent). Returns the url on an
  /// open OR a reuse, or a failure reason (the gh stderr) when neither.
  Future<LandPrOutcome> openOrReusePr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body,
  });
}

/// The result of [ReworkAwareSourceControl.pushForBranch] — the push's success
/// and its combined git stdout+stderr, so the land step can stamp the
/// [output] tail as the FT-1 `failureReason` on a non-[ok] push.
class LandPushOutcome {
  /// Creates the outcome.
  const LandPushOutcome({required this.ok, required this.output});

  /// Whether the force-with-lease push succeeded.
  final bool ok;

  /// The git combined stdout+stderr (empty on a clean push).
  final String output;
}

/// The result of [ReworkAwareSourceControl.openOrReusePr] — a [url] on a fresh
/// open OR a reuse ([reused] true when an already-open PR was adopted), or a
/// [failureReason] (the gh stderr) when neither.
class LandPrOutcome {
  const LandPrOutcome._({this.url, this.reused = false, this.failureReason});

  /// A PR was freshly opened at [url].
  factory LandPrOutcome.opened(String url) => LandPrOutcome._(url: url);

  /// An already-open PR for the branch was REUSED (idempotent land) at [url].
  factory LandPrOutcome.reused(String url) =>
      LandPrOutcome._(url: url, reused: true);

  /// Neither open nor reuse — [reason] is the gh stderr the land step stamps.
  factory LandPrOutcome.failed(String reason) =>
      LandPrOutcome._(failureReason: reason);

  /// The opened/reused PR url; null on failure.
  final String? url;

  /// Whether an already-open PR was reused rather than freshly opened.
  final bool reused;

  /// The failure reason (gh stderr); null on success.
  final String? failureReason;

  /// Whether the land delivered a PR (opened or reused).
  bool get ok => url != null;
}

/// Whether [ghOutput] is `gh pr create`'s "a pull request … already exists"
/// refusal — the rework-round symptom (round one's PR is still open). Detected
/// so [ReworkAwareSourceControl.openOrReusePr] treats it as success rather than
/// a failure that escalates a DONE bead.
bool isPrAlreadyOpen(String ghOutput) => ghOutput.contains('already exists');

/// The PR url embedded in gh output — both a successful `gh pr create` (stdout)
/// and its "already exists" refusal (which prints the open PR's url) carry one.
/// Returns null when none is present.
String? extractPrUrl(String output) =>
    RegExp(r'https?://\S+/pull/\d+').firstMatch(output)?.group(0);

/// The TAIL of git/gh combined output — what the land step stamps as its FT-1
/// `failureReason` so an operator sees WHY without forensics. The useful line
/// is at the END (git/gh print progress first, the fatal message last) and the
/// engine truncates a `failureReason` to its FIRST `kMaxReasonChars`; taking
/// the tail keeps the diagnosis, not the noise. A leading `…` marks a cut.
String landReasonTail(String output, [int max = 400]) {
  final trimmed = output.trim();
  return trimmed.length <= max
      ? trimmed
      : '…${trimmed.substring(trimmed.length - max)}';
}

/// The bead's OWN Validation Plan command — mirrors `committee.dart`'s
/// identical private helper (duplicated rather than shared, so this file
/// doesn't couple to the review committee's file layout for one four-line
/// pure function). A plan-less bead defaults to `false` (an explicit
/// non-zero) so it Gates rather than silently passing.
String _validationPlan(Bead bead) {
  final plan = bead.metadata['validation_plan'];
  if (plan is String && plan.trim().isNotEmpty) return plan.trim();
  return 'false';
}

/// Caps captured process output embedded in a [Gate] reason — a runaway
/// Validation Plan log must not blow up a gate bead's metadata.
String _truncate(String s, [int max = 2000]) {
  final trimmed = s.trim();
  return trimmed.length <= max
      ? trimmed
      : '${trimmed.substring(0, max)}\n… (truncated)';
}

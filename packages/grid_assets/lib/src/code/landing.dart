/// The LANDING PREPARATION circuit (bead `tg-rm5`) — `rebase → revalidate`, a
/// [SubCircuitStep] the `code` circuit's own `land` step inflates.
///
/// **Why**: with N parallel beads landing against one repo, the second bead to
/// land was validated against a `main` that has since moved (its own
/// Validation Plan ran BEFORE the first bead's PR merged) — the stale-base
/// hole. This circuit closes it: rebase the bead branch onto the CURRENT base
/// before re-running the bead's OWN Validation Plan against the REBASED tree,
/// ESCALATING (never silently forcing through) on either a rebase conflict or a
/// revalidation failure. Both `rebase` and `revalidate` are [RouteCapability]s
/// (not spawned jobs): each is a short, bounded, deterministic operation, and it
/// lets both skip to a clean, PROCESS-FREE [Advance] when no delivery method is
/// bound (the commit-only arm).
///
/// **The PR itself is no longer a step** (M5 D-4a): `deliver` — the ROOT `code`
/// circuit's TERMINAL route (`delivery.dart`) — actuates the substation's bound
/// `DeliveryMethod` on its advance. Delivery is the ACTUATION of a terminal
/// advance, never a step and never a verdict of its own, so this circuit prepares
/// and the root delivers. Its `rebase`/`revalidate` step ids are unchanged, so
/// the `<bead>/land/*` node paths [buildCircuitReceipt] reads still resolve (the
/// root keeps its sub-circuit step id `land`).
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
/// **The receipt** ([buildCircuitReceipt]): this circuit's rebase/revalidate
/// outcomes, read off the ambient `SiblingView` at the bead's absolute node
/// paths. It rides the PR body the GitHub PR delivery method opens with. The three
/// `is`-detected `SourceControl` widenings that used to thread it there — the
/// receipt-regression, tree-verification and rework-aware stopgaps — are GONE:
/// each existed only because the ENGINE's `SourceControl` could not carry the
/// verb, and M5 D-4a stripped those verbs off the interface entirely. A delivery
/// method owns git DIRECTLY now, so the outcome shapes below ([LandPushOutcome],
/// [LandPrOutcome], [isPrAlreadyOpen], [extractPrUrl]) survive as ITS
/// vocabulary — force-with-lease push and reuse-an-open-PR (which the App
/// identity now performs by ASKING GitHub for the branch's open PR, leaving the
/// two `gh`-transcript readers as vocabulary for a `gh`-shaped opener). The
/// stderr tail an operator reads as the FT-1 `failureReason` is assembled by
/// [capturedOutputReason]'s mechanism, which moved to `captured_output.dart` so
/// the standalone ACP bridge could share it.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../agent/captured_output.dart';
import '../agent/path_check.dart';
import '../assets/overlay_materializer.dart';
import 'route_failure.dart';

/// The landing PREPARATION circuit (id `landing`) — `rebase → revalidate`, which
/// `code`'s own `land` step inflates as a [SubCircuitStep]. Each step ESCALATES
/// (never silently forces) on failure.
///
/// The PR itself is NOT a step here: `deliver` — the ROOT circuit's terminal
/// route — actuates the substation's bound `DeliveryMethod` on its advance (M5
/// D-4a), and it `dependsOn` this circuit's terminal, so nothing leaves the
/// station until both preparation steps advance clean.
const Circuit kLandingCircuit = Circuit(
  id: 'landing',
  terminalStepId: 'revalidate',
  steps: [
    CapabilityStep(stepId: 'rebase', capabilityId: 'rebase'),
    CapabilityStep(
      stepId: 'revalidate',
      capabilityId: 'revalidate',
      dependsOn: {'rebase'},
    ),
  ],
);

/// The REBASE step — rebases the bead branch onto the CURRENT base branch tip.
/// A conflict (or any other rebase failure) ABORTS the rebase (never leaves
/// the worktree mid-rebase) and [Escalate]s with the git output as provenance —
/// never a silent force-through.
///
/// Offline-safe: with NO delivery method bound, nothing will leave the station,
/// so there is nothing to rebase ONTO — this skips straight to [Advance] with NO
/// git call at all. ("Is landing armed?" became "which delivery method did this
/// substation bind?", and none is a valid binding — M5 D-4a.)
class RebaseCapability extends RouteCapability {
  /// Creates the capability, optionally over an injected [runner] (tests
  /// inject the SAME [RecordingGitRunner] fake the GitHub PR delivery method's `GitOps`
  /// already uses — Fakes, not mocks); defaults to the real [SystemGitRunner].
  const RebaseCapability({
    GitRunner? runner,
    List<String> materializedSubtrees = kWorktreeOverlaySubtrees,
  }) : _runner = runner,
       _materializedSubtrees = materializedSubtrees;

  final GitRunner? _runner;
  final List<String> _materializedSubtrees;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    final services =
        context.getInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (services.delivery == null || workspace == null) return const Advance();

    final runner = _runner ?? SystemGitRunner();
    final workDir = workspace.workspaceDir;
    final base = workspace.baseBranch;

    final tracked = await runner.run(
      workingDirectory: workDir,
      args: ['ls-files', '--', ..._materializedSubtrees],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;
    if (!tracked.ok) {
      throw RouteFailure(
        'could not enumerate materializer-owned paths before rebase: '
        '${tracked.output.trim()}',
      );
    }
    final trackedPaths = tracked.output
        .split('\n')
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList();
    if (trackedPaths.isNotEmpty) {
      final restore = await runner.run(
        workingDirectory: workDir,
        args: [
          'restore',
          '--source=HEAD',
          '--staged',
          '--worktree',
          '--',
          ...trackedPaths,
        ],
      );
      if (args.cancel.isCancelled) throw kRouteCancelled;
      if (!restore.ok) {
        throw RouteFailure(
          'could not restore materializer-owned paths before rebase: '
          '${restore.output.trim()}',
        );
      }
    }
    final residue = await runner.run(
      workingDirectory: workDir,
      args: ['status', '--porcelain'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;
    if (!residue.ok) {
      throw RouteFailure(
        'could not verify a clean worktree before rebase: '
        '${residue.output.trim()}',
      );
    }
    if (residue.output.trim().isNotEmpty) {
      return Escalate(
        'rebase refused: uncommitted changes remain outside the materialized '
        'overlay scopes: ${residue.output.trim()}',
      );
    }

    final fetch = await runner.run(
      workingDirectory: workDir,
      args: ['fetch', 'origin', base],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;
    if (!fetch.ok) {
      throw RouteFailure(
        'git fetch origin $base failed: ${fetch.output.trim()}',
      );
    }

    final rebase = await runner.run(
      workingDirectory: workDir,
      args: ['rebase', 'origin/$base'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;
    if (rebase.ok) return const Advance({'outcome': 'clean'});

    // Never leave the worktree mid-rebase; the abort result is best-effort
    // (the Escalate below is what matters — the conflict provenance).
    await runner.run(workingDirectory: workDir, args: ['rebase', '--abort']);
    return Escalate('rebase onto $base conflicted: ${rebase.output.trim()}');
  }
}

/// The REVALIDATE step — re-runs the bead's OWN Validation Plan (the SAME
/// command the code-review committee's gating lane runs,
/// `committee.dart`'s `kGatingRubric`) against the REBASED tree, closing the
/// stale-base hole (a plan that passed pre-rebase may fail post-rebase). A
/// non-zero plan [Escalate]s with the captured output as provenance — never a
/// silent advance. Offline-safe: mirrors [RebaseCapability] — with no delivery
/// method bound, skips straight to [Advance] with NO shell exec at all (a plan
/// re-run only matters when a rebase actually moved the tree to re-validate
/// against).
class RevalidateCapability extends RouteCapability {
  /// Creates the capability, optionally over an injected [runner] (tests
  /// inject a recording fake — Fakes, not mocks); defaults to the real
  /// [SystemShellRunner].
  const RevalidateCapability({ShellRunner? runner}) : _runner = runner;

  final ShellRunner? _runner;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    final services =
        context.getInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (services.delivery == null || workspace == null || bead == null) {
      return const Advance();
    }

    final runner = _runner ?? const SystemShellRunner();
    final plan = _validationPlan(bead);
    final result = await runner.run(
      workingDirectory: workspace.workspaceDir,
      command: plan,
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;
    if (result.ok) return const Advance({'outcome': 'passed'});
    final diagnostic = pathCheckDiagnostic(plan, result.exitCode);
    final suffix = diagnostic == null ? '' : '; $diagnostic';
    // The exit code LEADS (the class of failure), then the PATH diagnostic,
    // then the log — advice-stripped and TAIL-cut, because the fatal line is
    // LAST and the old head truncation cut exactly it (bead `pow-gy41`).
    final log = landReasonTail(
      planOutputWithoutPubAdvice(result.output),
      kRevalidateReasonTailChars,
    );
    return Escalate('revalidate failed (exit ${result.exitCode})$suffix: $log');
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
    final result = await Process.run('sh', [
      '-c',
      command,
    ], workingDirectory: workingDirectory);
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

/// The result of a delivery method's force-with-lease push — the push's success
/// and its combined git stdout+stderr, so delivery can stamp the [output] tail as
/// the FT-1 `failureReason` on a non-[ok] push.
///
/// Force-with-lease ALWAYS (bead `tg-w3c`, live evidence tg-hsh round 2, session
/// tgdog-6d8): a preceding REWORK ROUND rebases the bead branch, so a plain push
/// is refused NON-FAST-FORWARD. Forcing is safe — it is the circuit's OWN branch
/// (`grid/<beadId>`) — and the lease still refuses if a racing writer moved the
/// remote out from under it.
class LandPushOutcome {
  /// Creates the outcome.
  const LandPushOutcome({required this.ok, required this.output});

  /// Whether the force-with-lease push succeeded.
  final bool ok;

  /// The git combined stdout+stderr (empty on a clean push).
  final String output;
}

/// The result of a delivery method's REUSE-or-open — a [url] (with its [number]
/// when the opener supplies one) on a reuse ([reused] true when an already-open
/// PR was adopted) OR a fresh open, or a [failureReason] when neither.
///
/// Reuse is what makes delivery IDEMPOTENT across a rework round (bead `tg-w3c`):
/// round one's PR is still OPEN, and adopting it is a SUCCESS (the branch is
/// delivered and the PR is there), not a failure that escalates a DONE, approved
/// bead. The App-identity delivery ASKS GitHub for that PR before creating one,
/// so reuse no longer depends on recognising a creation refusal after the fact.
class LandPrOutcome {
  const LandPrOutcome._({
    this.url,
    this.number,
    this.reused = false,
    this.failureReason,
  });

  /// A PR was freshly opened at [url], carrying [number] when the opener
  /// supplied one (the `gh` opener does not; the App opener always does).
  factory LandPrOutcome.opened(String url, {int? number}) =>
      LandPrOutcome._(url: url, number: number);

  /// An already-open PR for the branch was REUSED (idempotent land) at [url].
  /// A reuse always names its [number] — it was read off the PR itself.
  factory LandPrOutcome.reused(String url, {required int number}) =>
      LandPrOutcome._(url: url, number: number, reused: true);

  /// Neither open nor reuse — [reason] is the opener failure delivery stamps.
  factory LandPrOutcome.failed(String reason) =>
      LandPrOutcome._(failureReason: reason);

  /// The opened/reused PR url; null on failure.
  final String? url;

  /// The opened/reused PR number, when the opener supplied it.
  final int? number;

  /// Whether an already-open PR was reused rather than freshly opened.
  final bool reused;

  /// The failure reason; null on success.
  ///
  /// NOT captured process output — it is derived from the opener's own HTTP
  /// response (or its `gh` stderr). So
  /// `power_station#captured-process-output-escalates-tail-first`, which shapes
  /// this file's CAPTURED-LOG escalations as
  /// `'<verb> failed (exit N)<suffix>: <tail>'` over
  /// [planOutputWithoutPubAdvice] (first caller [RevalidateCapability.route]),
  /// governs a different path and is untouched here. Delivery passes this
  /// reason through [landReasonTail] alone — the posture
  /// `power_station#app-pr-transport-encodes-utf8-and-escalates-type-first`
  /// already set for it: type first, cause LAST, so the tail keeps the cause.
  final String? failureReason;

  /// Whether delivery produced a PR (opened or reused).
  bool get ok => url != null;
}

/// Whether [ghOutput] is `gh pr create`'s "a pull request … already exists"
/// refusal — the rework-round symptom (round one's PR is still open).
///
/// A PASSIVE reading of a refusal, kept as landing vocabulary for a `gh`-shaped
/// opener. The App-identity delivery no longer infers reuse this way: it ASKS
/// GitHub for the branch's open PR before creating one, so a refusal that
/// reaches it is a real refusal.
bool isPrAlreadyOpen(String ghOutput) => ghOutput.contains('already exists');

/// The PR url embedded in gh output — both a successful `gh pr create` (stdout)
/// and its "already exists" refusal (which prints the open PR's url) carry one.
/// Returns null when none is present.
String? extractPrUrl(String output) =>
    RegExp(r'https?://\S+/pull/\d+').firstMatch(output)?.group(0);

/// The bead's OWN Validation Plan command — mirrors `committee.dart`'s
/// identical private helper (duplicated rather than shared, so this file
/// doesn't couple to the review committee's file layout for one four-line
/// pure function). A plan-less bead defaults to `false` (an explicit
/// non-zero) so it ESCALATES rather than silently passing.
String _validationPlan(Bead bead) {
  final plan = bead.metadata['validation_plan'];
  if (plan is String && plan.trim().isNotEmpty) return plan.trim();
  return 'false';
}

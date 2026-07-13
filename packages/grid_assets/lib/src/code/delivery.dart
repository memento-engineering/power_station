/// The DELIVERY seam (M5 D-4a) — `deliver` replaces `land`.
///
/// Delivery is the ACTUATION of the ROOT circuit's terminal [Advance], not a step
/// and not a verdict: [DeliverRouteCapability] is that terminal route, and
/// [GitHubPrDelivery] is the substation's bound [DeliveryMethod] the engine
/// actuates when it advances. UNBOUND ⇒ commit-only (the posture the retired
/// armed-flag expressed as "unarmed").
///
/// The split follows the engine's own seam: a [DeliveryMethod] receives plain
/// VALUES (a [DeliveryRequest]) and NEVER a `TreeContext`, so a long push/PR
/// round-trip cannot race an unmount into a thrown tree lookup. Everything that
/// must be read from the tree — the ambient [SiblingView] the PR body's circuit
/// receipt and committee grades come from, the [PrComposition] knob, the agent
/// scope the describe pass rides — is read by the ROUTE, at its entry.
///
/// This library SUPERSEDES the three `is`-detected `SourceControl` widenings —
/// ADR-0000 A5's `TreeVerifiableSourceControl`, `tg-rm5`'s
/// `ReceiptCapableSourceControl`, `tg-w3c`'s `ReworkAwareSourceControl` — and
/// A7(3)'s `GitSourceControl.withPrOpener` enrichment seam. Each existed ONLY
/// because the ENGINE's `SourceControl` could not carry the verb, and M5 D-4a
/// stripped those verbs off the interface entirely. Git ownership is now
/// UNCONDITIONAL here, not opt-in-detected — the exact retirement A5's own
/// `Affects` note named.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_harness.dart';
import 'conventional_commit.dart';
import 'landing.dart';
import 'pr_composition.dart';
import 'pr_describe.dart';
import 'route_failure.dart';

/// The ROOT circuit's terminal step id — the ONE node whose advance delivers.
const String kDeliverStep = 'deliver';

/// The workspace-relative path the terminal route writes the composed PR body to,
/// and [GitHubPrDelivery] reads it back from. A worktree ledger, exactly like the
/// respec ledger and the discovery dossier: it keeps kilobytes of prose OUT of
/// the session bead's metadata (a terminal [Advance] payload is persisted under
/// `grid.result.<nodePath>.*`) while still crossing the value-only
/// [DeliveryRequest] seam.
const String kPrBodyRelPath = '.grid/pr-body.md';

/// The absolute PR-body ledger path inside [workspaceDir].
String prBodyPath(String workspaceDir) => p.join(workspaceDir, kPrBodyRelPath);

/// The ROOT `code` circuit's TERMINAL ROUTE — the node whose [Advance] the engine
/// answers by actuating the substation's bound [DeliveryMethod]
/// ([isDeliveryTerminal]). It decides NOTHING about the work's quality (the
/// committee already did): it composes what delivery needs and advances.
///
/// The PR opens with an INFERRED, strict Conventional Commits v1.0.0 TITLE and a
/// section-COMPOSED body: `pr_describe.dart` runs ONE cheap inference pass over
/// the branch's ACTUAL delta and `pr_composition.dart` renders it — the what/why
/// summary FIRST, then the circuit receipt, the committee grades, the bead's
/// validation plan, and LAST the footers, where the bead id rides its git TRAILER
/// and NOWHERE else. Every inference failure path (not wired, offline, a failed
/// run, unparseable output) falls back to a DETERMINISTIC, id-free conventional
/// subject — delivery never fails over PR prose.
///
/// With NO delivery bound it advances BARE — commit-only — and never spends an
/// inference token in that arm.
class DeliverRouteCapability extends RouteCapability {
  /// Creates the terminal route over the optional [gitRunner] (the describe
  /// pass's branch-delta reads; null ⇒ the real [SystemGitRunner]) and the
  /// optional [inference] runner (null ⇒ NO describe pass at all — the
  /// deterministic fallback title with ZERO git and ZERO inference, which is
  /// every offline unit test).
  const DeliverRouteCapability({
    GitRunner? gitRunner,
    InferenceRunner? inference,
  }) : _gitRunner = gitRunner,
       _inference = inference;

  final GitRunner? _gitRunner;
  final InferenceRunner? _inference;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read every ambient value at ENTRY (synchronously, while mounted); after
    // every await only the captured values + the cancel token are touched.
    final services =
        context.getInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final bead =
        context.getInheritedSeedOfExactType<Bead>() ?? Bead(id: args.beadId);
    final composition =
        context.getInheritedSeedOfExactType<PrComposition>() ??
        const PrComposition();
    final agentConfig =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final harnesses =
        context.getInheritedSeedOfExactType<AgentHarnessRegistry>() ??
        buildAgentHarnessRegistry();

    // Commit-only: no method bound, or no workspace to deliver FROM. The engine
    // completes the terminal node and delivers nothing.
    if (services.delivery == null || workspace == null) return const Advance();

    // THE DESCRIBE PASS: one cheap inference call over the branch's ACTUAL delta.
    // Fail-safe by construction — every failure path yields the deterministic,
    // id-free fallback subject.
    final described = await describeBranch(
      bead: bead,
      beadId: args.beadId,
      workspace: workspace,
      composition: composition,
      ambient: agentConfig,
      registry: harnesses,
      git: _gitRunner,
      inference: _inference,
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;

    // `siblings` is the SESSION-WIDE view SessionScope mounts (keyed by full
    // nodePath), so the receipt's `<bead>/land/rebase` keys resolve from this
    // ROOT-level node exactly as they did from the old `<bead>/land/land`.
    final prContext = PrCompositionContext(
      beadId: args.beadId,
      bead: bead,
      siblings: siblings,
      description: described.description,
      commits: described.commits,
      titleSource: described.source,
    );
    final title = composition.titleOf(prContext);
    final body = composition.bodyOf(prContext);

    // The body ledger. Offline (a synthetic workspace that is not on disk) the
    // write is skipped and delivery opens the PR with an EMPTY body — a land
    // never fails over PR prose (fail-SAFE).
    final dir = workspace.workspaceDir;
    if (Directory(dir).existsSync()) {
      try {
        File(prBodyPath(dir))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(body);
      } catch (e) {
        throw RouteFailure(
          'deliver: could not write the PR body ledger at ${prBodyPath(dir)} — '
          '$e. Refusing to open a PR that drops the committee grades and the '
          'circuit receipt on the floor.',
        );
      }
    }

    return Advance({
      'verdict': 'deliver',
      'pr_title': title,
      'title_source': described.source,
    });
  }
}

/// The substation's GitHub DELIVERY METHOD — commit residue → force-with-lease
/// push → open-or-REUSE the PR. The CODE domain's answer to "how does work leave
/// the station" (M5 D-4a: the engine knows delivery in CONCEPT, the asset in
/// DETAIL).
///
/// It is IDEMPOTENT by construction, which is what lets a rework round (which
/// REBASED the branch and left round one's PR open) deliver at all: a plain push
/// is refused non-fast-forward and `gh pr create` errors "already exists", which
/// used to wedge a DONE, approved bead into escalation. Force-with-lease is safe
/// — it is the circuit's OWN branch (`grid/<beadId>`) — and the lease still
/// refuses if a racing writer moved the remote.
///
/// The residue check IS ADR-0000 A5's committed-the-WHOLE-tree guarantee,
/// re-homed: the SAME [GitOps.hasUncommittedWork] three-gate probe A5 chose,
/// still fail-closed on an unreadable probe, still never-push-on-residue. What
/// changed is that it is now UNCONDITIONAL (a delivery method owns git by
/// definition) instead of detected off A5's OPT-IN marker interface — strictly
/// stronger, because a bare `SourceControl` fake can no longer skip the
/// guarantee. A botched commit that captured a SUBSET of the reviewed tree (the
/// tg-x1j r1 incident A5 names) [Failed]s and NEVER pushes; a [Failed] delivery
/// routes the terminal node to SUPERVISION and never silently advances.
class GitHubPrDelivery implements DeliveryMethod {
  /// Creates the method over the commit/push [gitOps], the [prOpener], and the
  /// raw [gitRunner] the force-push runs through (null ⇒ the real, clean-env
  /// [SystemGitRunner]; tests inject the SAME recording fake [gitOps] wraps).
  /// [composition] supplies the trailer token the residue commit stamps.
  const GitHubPrDelivery({
    required GitOps gitOps,
    required PrOpener prOpener,
    GitRunner? gitRunner,
    this.composition = const PrComposition(),
  }) : _gitOps = gitOps,
       _prOpener = prOpener,
       _gitRunner = gitRunner;

  final GitOps _gitOps;
  final PrOpener _prOpener;
  final GitRunner? _gitRunner;

  /// The substation's PR-shaping knob (its trailer token).
  final PrComposition composition;

  @override
  String get id => 'github-pr';

  @override
  Future<StepOutcome> deliver(DeliveryRequest request) async {
    final workspaceDir = request.workspace.workspaceDir;

    // The residue commit obeys the SAME policy the build agent is briefed with:
    // a conventional subject, the bead id in a git TRAILER, never in the subject.
    // It no-ops on a clean tree.
    await _gitOps.commitAll(
      workDir: workspaceDir,
      message: composeCommitMessage(
        subject: const ConventionalSubject(
          type: 'chore',
          description: 'commit residual review changes',
        ),
        trailers: {composition.trailerToken: request.bead.id},
      ),
    );

    // A5's guarantee, now unconditional. Fail-closed: an unreadable probe is
    // treated as unsafe, never trusted clean.
    final residue = switch (await _gitOps.hasUncommittedWork(workspaceDir)) {
      GateOutcome.clear => null,
      GateOutcome.present =>
        'uncommitted changes remain in the workspace after the residue commit',
      GateOutcome.probeError =>
        'could not verify a clean tree (the git status probe failed) — '
            'fail-closed, treated as unsafe',
    };
    if (residue != null) {
      return Failed(
        'delivery committed a SUBSET of the reviewed tree (the tg-x1j r1 class '
        'of incident) — never pushed: $residue',
      );
    }

    final push = await _push(
      workspaceDir: workspaceDir,
      branch: request.workspace.branch,
    );
    if (!push.ok) {
      return Failed(
        'force-with-lease push refused — ${landReasonTail(push.output)}',
      );
    }

    // The title the terminal route composed. The fallback is reached only
    // defensively (a payload with no title): it is the DETERMINISTIC conventional
    // subject, never the retired id-carrying subject.
    final pr = await _openOrReuse(
      workspace: request.workspace,
      workspaceDir: workspaceDir,
      title:
          request.payload['pr_title'] ??
          fallbackSubjectFor(
            request.bead,
            foreignRef: request.bead.id,
          ).format(),
      body: _readBody(workspaceDir),
    );
    if (!pr.ok) {
      return Failed(
        'pr open failed — ${landReasonTail(pr.failureReason ?? '')}',
      );
    }
    return Ok({'pr_url': pr.url!, 'reused': '${pr.reused}'});
  }

  /// `--force-with-lease` ALWAYS: a rework round rebased this branch, so a plain
  /// push is refused non-fast-forward. `-u` keeps upstream set.
  Future<LandPushOutcome> _push({
    required String workspaceDir,
    required String branch,
  }) async {
    final runner = _gitRunner ?? SystemGitRunner();
    final result = await runner.run(
      workingDirectory: workspaceDir,
      args: ['push', '--force-with-lease', '-u', 'origin', branch],
    );
    return LandPushOutcome(ok: result.ok, output: result.output);
  }

  /// Opens the PR, or REUSES the one a prior round left open (idempotent).
  Future<LandPrOutcome> _openOrReuse({
    required Workspace workspace,
    required String workspaceDir,
    required String title,
    required String body,
  }) async {
    final result = await _prOpener.open(
      workDir: workspaceDir,
      branch: workspace.branch,
      baseBranch: workspace.baseBranch,
      title: title,
      body: body,
    );
    if (result.isOpened) return LandPrOutcome.opened(result.ref!.url);
    // Idempotent: `gh pr create` refusing because a prior round's PR is still
    // OPEN is a SUCCESS, not a failure — the branch is delivered and the PR is
    // there. An "already exists" without a parseable url still counts as reused
    // (the PR exists) rather than escalating a DONE bead.
    final reason = result.failure?.reason ?? 'pr open did not complete';
    if (isPrAlreadyOpen(reason)) {
      return LandPrOutcome.reused(extractPrUrl(reason) ?? '');
    }
    return LandPrOutcome.failed(reason);
  }

  /// The composed PR body the terminal route left in the worktree ledger; an
  /// absent/unreadable ledger is an EMPTY body — a land never fails over PR
  /// prose.
  String _readBody(String workspaceDir) {
    try {
      final file = File(prBodyPath(workspaceDir));
      return file.existsSync() ? file.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }
}

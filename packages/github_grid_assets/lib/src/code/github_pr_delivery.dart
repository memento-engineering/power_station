library;

import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'github_app_pr_opener.dart';

/// The substation's GitHub delivery method: commit residue, force-with-lease
/// push, then reuse or open the pull request.
///
/// It is idempotent so a rework round can deliver after rebasing while the
/// prior round's pull request remains open. Reuse is ACTIVE, not inferred: with
/// the App opener bound, delivery asks GitHub for the branch's open pull
/// request FIRST and refreshes it, because a creation POST against a branch
/// that already has one is refused `HTTP 422` and used to strand a green,
/// already-delivered round. The residue check preserves the committed-whole-tree
/// guarantee and fails closed when the probe is unreadable.
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
    return Ok({
      'pr_url': pr.url!,
      if (pr.number case final number?) 'pr_number': '$number',
      'reused': '${pr.reused}',
    });
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

  /// REUSES the PR a prior round left open, or opens a new one (idempotent).
  ///
  /// The reuse probe runs only for the [GitHubAppPrOpener], which owns the
  /// authenticated client the filtered lookup needs; a `gh`-shaped or fake
  /// opener keeps the create-only path. A lookup or update GitHub REFUSED is a
  /// failure, never a fall-through to create: only an EMPTY lookup — GitHub
  /// answering that this branch has no open PR — licenses the POST, and a 422
  /// after that answer is therefore a real refusal that keeps escalating.
  Future<LandPrOutcome> _openOrReuse({
    required Workspace workspace,
    required String workspaceDir,
    required String title,
    required String body,
  }) async {
    if (_prOpener case final GitHubAppPrOpener appOpener) {
      final existing = await appOpener.reuseOpen(
        workDir: workspaceDir,
        branch: workspace.branch,
        baseBranch: workspace.baseBranch,
        title: title,
        body: body,
      );
      if (existing != null) {
        if (!existing.isOpened) {
          return LandPrOutcome.failed(
            existing.failure?.reason ?? 'open PR reuse did not complete',
          );
        }
        final ref = existing.ref!;
        final number = ref.number;
        if (number == null) {
          return LandPrOutcome.failed(
            'GitHub open-PR lookup returned no usable pull request number',
          );
        }
        return LandPrOutcome.reused(ref.url, number: number);
      }
    }

    final result = await _prOpener.open(
      workDir: workspaceDir,
      branch: workspace.branch,
      baseBranch: workspace.baseBranch,
      title: title,
      body: body,
    );
    if (result.isOpened) {
      final ref = result.ref!;
      return LandPrOutcome.opened(ref.url, number: ref.number);
    }
    return LandPrOutcome.failed(
      result.failure?.reason ?? 'pr open did not complete',
    );
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

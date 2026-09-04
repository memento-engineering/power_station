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
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

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

/// A [DeliveryRequest] for [workspaceDir] carrying the terminal advance's
/// [payload] (what the engine hands the bound method).
DeliveryRequest _request({
  required String workspaceDir,
  Map<String, String> payload = const {},
  Bead? beadOverride,
}) => DeliveryRequest(
  bead: beadOverride ?? bead('tg-1'),
  sessionId: 'tgdog-1',
  nodePath: 'tg-1/$kDeliverStep',
  workspace: testWorkspace(
    'tg-1',
    workspaceDir: workspaceDir,
    branch: 'grid/tg-1',
    baseBranch: 'main',
  ),
  payload: payload,
);

void main() {
  group('GitHubPrDelivery — the bound method', () {
    late Directory work;
    setUp(() => work = Directory.systemTemp.createTempSync('deliver-method-'));
    tearDown(() => work.deleteSync(recursive: true));

    GitHubPrDelivery method({
      required GitRunner git,
      required PrOpener pr,
      PrComposition composition = const PrComposition(),
    }) => GitHubPrDelivery(
      gitOps: GitOps(git),
      prOpener: pr,
      gitRunner: git,
      composition: composition,
    );

    test('a clean tree: commit → force-with-lease push → open ⇒ Ok(pr_url); '
        'the push argv is EXACTLY the rework-safe one', () async {
      final git = RecordingGitRunner();
      final pr = FakePrOpener(url: 'https://github.com/memento/x/pull/7');
      final outcome = await method(git: git, pr: pr).deliver(
        _request(
          workspaceDir: work.path,
          payload: const {'pr_title': 'feat(x): do the thing'},
        ),
      );

      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {
        'pr_url': 'https://github.com/memento/x/pull/7',
        'reused': 'false',
      });
      final push = git.calls
          .map((c) => c.args)
          .firstWhere((a) => a.isNotEmpty && a.first == 'push');
      expect(push, ['push', '--force-with-lease', '-u', 'origin', 'grid/tg-1']);
      expect(pr.opened.single.title, 'feat(x): do the thing');
    });

    test('the residue COMMIT follows the policy: a conventional subject with '
        'the bead in a TRAILER — never the old `grid: land <id>`', () async {
      final git = RecordingGitRunner();
      await method(
        git: git,
        pr: FakePrOpener(),
      ).deliver(_request(workspaceDir: work.path));
      final commit = git.calls
          .map((c) => c.args)
          .firstWhere((a) => a.isNotEmpty && a.first == 'commit');
      expect(
        commit.last,
        'chore: commit residual review changes\n\nRefs: tg-1',
      );
      expect(commit.last, isNot(contains('grid: land')));
    });

    test('a RESIDUAL tree (the commit captured a SUBSET of the reviewed tree — '
        'the tg-x1j r1 class of incident) ⇒ Failed, and the PR is NEVER opened '
        '— A5\'s guarantee, now UNCONDITIONAL', () async {
      final git = _ResidueGitRunner();
      final pr = FakePrOpener();
      final outcome = await method(
        git: git,
        pr: pr,
      ).deliver(_request(workspaceDir: work.path));

      expect(outcome, isA<Failed>());
      expect(
        (outcome as Failed).reason,
        contains('SUBSET of the reviewed tree'),
      );
      expect(pr.opened, isEmpty, reason: 'a residual tree is NEVER pushed');
      expect(
        git.subcommands,
        isNot(contains('push')),
        reason: 'and never pushed either',
      );
    });

    test('an UNREADABLE residue probe ⇒ Failed (fail-closed: never trusted '
        'clean), and the PR is never opened', () async {
      final git = _ProbeErrorGitRunner();
      final pr = FakePrOpener();
      final outcome = await method(
        git: git,
        pr: pr,
      ).deliver(_request(workspaceDir: work.path));

      expect(outcome, isA<Failed>());
      expect((outcome as Failed).reason, contains('fail-closed'));
      expect(pr.opened, isEmpty);
    });

    test('a force-with-lease push the lease REFUSES (a racing writer moved the '
        'remote) ⇒ Failed with the git stderr TAIL as the reason (FT-1 '
        'failureReason), and NEVER opens a PR', () async {
      final git = _RejectedPushRunner();
      final pr = FakePrOpener();
      final outcome = await method(
        git: git,
        pr: pr,
      ).deliver(_request(workspaceDir: work.path));

      expect(outcome, isA<Failed>());
      final reason = (outcome as Failed).reason;
      expect(reason, contains('force-with-lease push refused'));
      expect(
        reason,
        contains('[rejected]'),
        reason: 'the git stderr tail is stamped so the operator sees WHY',
      );
      expect(pr.opened, isEmpty, reason: 'a refused push never opens a PR');
    });

    test('a rework round left round one\'s PR OPEN: `gh pr create`\'s "already '
        'exists" refusal is REUSED ⇒ Ok(pr_url, reused), never an escalation of '
        'a DONE, approved bead', () async {
      final git = RecordingGitRunner();
      final pr = _AlreadyOpenPrOpener('https://github.com/memento/x/pull/9');
      final outcome = await method(
        git: git,
        pr: pr,
      ).deliver(_request(workspaceDir: work.path));

      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {
        'pr_url': 'https://github.com/memento/x/pull/9',
        'reused': 'true',
      });
    });

    test(
      'an already-open PR whose url gh did not print is STILL reused (the '
      'branch is delivered, the PR exists) ⇒ Ok, never an escalation',
      () async {
        final outcome = await method(
          git: RecordingGitRunner(),
          pr: _AlreadyOpenPrOpener(''),
        ).deliver(_request(workspaceDir: work.path));

        expect(outcome, isA<Ok>());
        expect((outcome as Ok).payload, {'pr_url': '', 'reused': 'true'});
      },
    );

    test('an EMPTY payload ⇒ the DETERMINISTIC conventional fallback subject: '
        'it lints clean and carries NO bead id (never the retired '
        '`grid: land <id>` form)', () async {
      final pr = FakePrOpener();
      await method(git: RecordingGitRunner(), pr: pr).deliver(
        _request(
          workspaceDir: work.path,
          beadOverride: bead('tg-1').copyWith(
            title: 'better + configurable PR titles',
            issueType: IssueType.feature,
            metadata: const {'rig': 'power_station'},
          ),
        ),
      );
      final title = pr.opened.single.title;
      expect(title, 'feat(power_station): better + configurable PR titles');
      expect(lintConventionalSubject(title, foreignRef: 'tg-1'), isEmpty);
      expect(title, isNot(contains('tg-1')));
    });

    test('the body LEDGER the terminal route left in the worktree reaches the '
        'opener\'s `body` argument verbatim', () async {
      File(prBodyPath(work.path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('## Summary\n\nthe composed body\n\nRefs: tg-1\n');
      final pr = FakePrOpener();
      await method(
        git: RecordingGitRunner(),
        pr: pr,
      ).deliver(_request(workspaceDir: work.path));
      expect(
        pr.opened.single.body,
        '## Summary\n\nthe composed body\n\nRefs: tg-1\n',
      );
    });

    test('an ABSENT body ledger opens with an EMPTY body — a land never fails '
        'over PR prose (fail-SAFE)', () async {
      final pr = FakePrOpener();
      final outcome = await method(
        git: RecordingGitRunner(),
        pr: pr,
      ).deliver(_request(workspaceDir: work.path));
      expect(outcome, isA<Ok>());
      expect(pr.opened.single.body, isEmpty);
    });

    test('a mounted PrComposition re-tokens the residue commit\'s trailer (the '
        'configurable knob)', () async {
      final git = RecordingGitRunner();
      await method(
        git: git,
        pr: FakePrOpener(),
        composition: const PrComposition(trailerToken: 'Bead'),
      ).deliver(_request(workspaceDir: work.path));
      final commit = git.calls
          .map((c) => c.args)
          .firstWhere((a) => a.isNotEmpty && a.first == 'commit');
      expect(commit.last, endsWith('Bead: tg-1'));
    });
  });

  // The route COMPOSES and the method ACTUATES — these drive BOTH halves in
  // sequence, which is exactly the wire the engine runs (a terminal Advance's
  // payload becomes the DeliveryRequest's payload).
  group('route → method, end to end (the pow-8dx PR composition, across the '
      'new seam)', () {
    late Directory work;
    setUp(() => work = Directory.systemTemp.createTempSync('deliver-e2e-'));
    tearDown(() => work.deleteSync(recursive: true));

    /// Drives the terminal route, then hands its advance payload to the bound
    /// method — the engine's own sequence.
    Future<StepOutcome> deliverThrough({
      required GitRunner git,
      required PrOpener pr,
      InferenceRunner? inference,
      GitRunner? describeGit,
      Bead? beadOverride,
      PrComposition? composition,
    }) async {
      final delivery = GitHubPrDelivery(
        gitOps: GitOps(git),
        prOpener: pr,
        gitRunner: git,
        composition: composition ?? const PrComposition(),
      );
      final verdict =
          await DeliverRouteCapability(
            gitRunner: describeGit,
            inference: inference,
          ).route(
            _deliverContext(
              workspaceDir: work.path,
              delivery: delivery,
              beadOverride: beadOverride,
              composition: composition,
              siblings: const SiblingView(
                results: {
                  'tg-1/land/rebase': {'outcome': 'clean'},
                  'tg-1/land/revalidate': {'outcome': 'passed'},
                },
              ),
            ),
            _deliverArgs(),
          );
      return delivery.deliver(
        _request(
          workspaceDir: work.path,
          payload: (verdict as Advance).payload ?? const {},
          beadOverride: beadOverride,
        ),
      );
    }

    test(
      'NO inference wired (the offline posture) ⇒ the deterministic, id-free '
      'fallback title, ZERO git READS beyond the delivery itself, and the PR '
      'still opens',
      () async {
        final git = RecordingGitRunner();
        final pr = FakePrOpener();
        final outcome = await deliverThrough(
          git: git,
          pr: pr,
          beadOverride: bead('tg-1').copyWith(
            title: 'better + configurable PR titles',
            issueType: IssueType.feature,
            metadata: const {'rig': 'power_station'},
          ),
        );

        expect(outcome, isA<Ok>());
        final opened = pr.opened.single;
        expect(
          opened.title,
          'feat(power_station): better + configurable PR titles',
        );
        expect(
          lintConventionalSubject(opened.title, foreignRef: 'tg-1'),
          isEmpty,
        );
        expect(git.subcommands, isNot(contains('diff')));
        expect(opened.body, contains('- description: fallback'));
        expect(opened.body.trimRight(), endsWith('Refs: tg-1'));
      },
    );

    test(
      'inference wired over a REAL worktree: the title is the INFERRED '
      'conventional subject, the body COMPOSES the inferred prose WITH the '
      'circuit receipt, and the bead id appears ONLY in the trailer',
      () async {
        final describeGit = CannedGitRunner(
          log: 'feat(landing): read the branch delta\n\nRefs: tg-1\x00',
          diff: '--- a/lib/x.dart\n+++ b/lib/x.dart\n+the change',
        );
        final pr = FakePrOpener();
        final outcome = await deliverThrough(
          git: RecordingGitRunner(),
          pr: pr,
          describeGit: describeGit,
          inference: FakeInferenceRunner(
            output:
                '{"type":"feat","scope":"landing","breaking":false,'
                '"description":"Infer the pr title from the branch diff.",'
                '"summary":"The land step now describes the actual diff.",'
                '"breakingChange":""}',
          ),
        );

        expect(outcome, isA<Ok>());
        final opened = pr.opened.single;
        expect(
          opened.title,
          'feat(landing): infer the pr title from the branch diff',
        );
        expect(
          lintConventionalSubject(opened.title, foreignRef: 'tg-1'),
          isEmpty,
        );
        // COMPOSED, not clobbered (pow-yny): the DIGEST leads, then the receipt.
        expect(opened.body, startsWith('## Summary'));
        expect(
          opened.body,
          contains('The land step now describes the actual diff.'),
        );
        expect(opened.body, contains('## Circuit receipt'));
        expect(opened.body, contains('- description: inference'));
        expect(
          opened.body,
          contains('- commits: 1 (1 conventional, 1 trailered)'),
        );
        // THE POLICY: the bead id appears EXACTLY once, on the trailer line.
        expect('tg-1'.allMatches(opened.body).length, 1);
        expect(opened.body.trimRight(), endsWith('Refs: tg-1'));
      },
    );

    test('a mounted PrComposition reshapes the trailer token and the sections '
        'at the route edge (the configurable knob)', () async {
      final git = RecordingGitRunner();
      final pr = FakePrOpener();
      await deliverThrough(
        git: git,
        pr: pr,
        composition: const PrComposition(
          trailerToken: 'Bead',
          sections: [PrSection.circuitReceipt, PrSection.trailers],
        ),
      );
      final opened = pr.opened.single;
      expect(opened.body, contains('## Circuit receipt'));
      expect(opened.body.trimRight(), endsWith('Bead: tg-1'));
      // The knob also re-tokens the RESIDUE COMMIT's trailer.
      final commit = git.calls
          .map((c) => c.args)
          .firstWhere((a) => a.isNotEmpty && a.first == 'commit');
      expect(commit.last, endsWith('Bead: tg-1'));
    });

    test('an inference run that FAILS still delivers — the description is '
        'decoration, never a delivery blocker', () async {
      final pr = FakePrOpener();
      final outcome = await deliverThrough(
        git: RecordingGitRunner(),
        pr: pr,
        describeGit: CannedGitRunner(diff: 'a diff'),
        inference: FakeInferenceRunner(output: 'I refuse.', ok: false),
      );
      expect(outcome, isA<Ok>());
      expect(pr.opened.single.title, 'chore: $kFallbackDescription');
      expect(pr.opened.single.body, contains('- description: fallback'));
    });
  });
}

/// A [GitRunner] whose `status --porcelain` reports RESIDUE — the commit
/// captured a SUBSET of the reviewed tree (the tg-x1j r1 incident).
class _ResidueGitRunner implements GitRunner {
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    final root = gitRootProbeAnswer(
      workingDirectory: workingDirectory,
      args: args,
    );
    if (root != null) return root;
    calls.add(List.unmodifiable(args));
    if (args.isNotEmpty && args.first == 'status') {
      return const GitRunResult(
        exitCode: 0,
        output: ' M packages/grid_engine/lib/src/circuit/session_scope.dart\n',
      );
    }
    return const GitRunResult(exitCode: 0, output: '');
  }

  List<String> get subcommands => [
    for (final c in calls) c.isNotEmpty ? c.first : '',
  ];
}

/// A [GitRunner] whose `status --porcelain` probe itself FAILS — the residue
/// check cannot run, so delivery must fail CLOSED (never trust it clean).
class _ProbeErrorGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    final root = gitRootProbeAnswer(
      workingDirectory: workingDirectory,
      args: args,
    );
    if (root != null) return root;
    return args.isNotEmpty && args.first == 'status'
        ? const GitRunResult(
            exitCode: 128,
            output: 'fatal: not a git repository',
          )
        : const GitRunResult(exitCode: 0, output: '');
  }
}

/// A [GitRunner] whose `push` fails (exit 1) with a realistic force-with-lease
/// REJECTION transcript, while add/commit/status succeed — the "lease refused (a
/// racing writer moved the remote)" path. The fatal line is LAST, so delivery's
/// stderr-tail stamping is exercised.
class _RejectedPushRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    final root = gitRootProbeAnswer(
      workingDirectory: workingDirectory,
      args: args,
    );
    if (root != null) return root;
    if (args.isNotEmpty && args.first == 'push') {
      return const GitRunResult(
        exitCode: 1,
        output:
            'To github.com:memento/x.git\n'
            ' ! [rejected]        grid/tg-1 -> grid/tg-1 (stale info)\n'
            'error: failed to push some refs to '
            "'github.com:memento/x.git'",
      );
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}

/// A [PrOpener] that always REFUSES with gh's "a pull request … already exists"
/// transcript (round one's PR is still open) — the rework-round idempotency case.
/// [existingUrl] is echoed on the refusal's url line ('' models a gh that printed
/// no url).
class _AlreadyOpenPrOpener implements PrOpener {
  _AlreadyOpenPrOpener(this.existingUrl);

  final String existingUrl;

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.failed(
    PrOpenFailure(
      'gh pr create failed: a pull request for branch "$branch" into branch '
      '"$baseBranch" already exists:\n$existingUrl',
    ),
  );
}

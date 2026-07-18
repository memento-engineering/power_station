/// The adversarial code-committee — a reentrant sub-circuit composed at the
/// existing `CircuitScope` seam (ADR-0008 D2/D4 / M5 "The Circuit" Track C).
///
/// factoryskills' code review runs ONE critic per rubric in ISOLATION
/// (anti-anchoring: a critic sees only its own rubric, never the others' grades),
/// fans the four critics out in parallel, then a `route` step aggregates their
/// grades through a deterministic matrix (asset policy, never engine). The
/// committee is just circuit wiring + two `Capability` leaves — the parallelism +
/// await-all join is already proven by the Burn (M4-P1 Track J); no new engine
/// machinery is introduced here.
///
/// The four lanes:
///  - `code-validation` — the GATING lane: runs the bead's OWN Validation Plan in
///    the workspace (a real `sh` command); grade A iff every command was zero,
///    else F. A non-zero plan is a HARD block, decided by the route.
///  - `spec-adherence` / `regression-risk` / `test-coverage` — three LLM critics:
///    each RIDES the resolved agent harness (ADR-0008 Decision 10 — critics are
///    agents; `claude` by default) with ONLY its own rubric and writes a verdict
///    JSON the `result()` hook parses into a grade.
///
/// **Gate-integrity #3 — the stale-shadow + no-file transport miss (bead
/// `tg-bns`)**: a rework round reuses the SAME workspace directory, so
/// `.grid/critique/<rubric>.json` (and the gating lane's `.rc`) from a PRIOR
/// round survives on disk. When the CURRENT round's critic exits clean but
/// (tg-291's residual risk) never writes its file, `result()` was reading the
/// PREVIOUS round's file — a stale grade impersonating a fresh one, not a
/// recognized miss. Two independent, defense-in-depth fixes:
///  1. [ClearCritiqueCapability] (`clear-critique`) — a dep-free step every
///     critic lane `dependsOn` — wipes `.grid/critique/` at the START of every
///     round, before any lane can read or write.
///  2. Every LLM verdict JSON carries TWO freshness stamps, and
///     [_verdictFromFile] REJECTS a file that fails EITHER — falling through to
///     the envelope/fail-closed transports exactly as if the file were absent:
///     `nodePath` (A4) fences a verdict some OTHER node wrote, and `round`
///     (A15(5) alt-A — the node's own `rewindCount`, read via the ambient
///     [SiblingView]) fences a verdict THIS node wrote in an EARLIER round. The
///     round stamp is what makes fix 1 a BELT rather than the guarantee: under
///     `RouteVerdict.Rewind` the node path does not move, so `nodePath` alone
///     cannot tell round N's surviving file from round N+1's.
///     (The gating lane's `.rc` needs no stamp — fix 1 alone clears it every
///     round, and it carries no separate fallback transport.)
///  Every verdict's result payload also carries a `transport` field
///  (`file`/`envelope`/`fail-closed-default`) naming which of the three
///  channels actually produced the grade — durable, queryable provenance
///  (visible on `grid.result.<nodePath>.transport`) rather than a silent
///  choice, so a false-gate post-mortem never again has to guess which path
///  fired (case B: a fail-closed default with NO rationale was itself a gap —
///  it now always carries one).
///
/// **The flaky write path itself (item 4, root-cause)**: the two live
/// incidents #3 addressed (tg-x1j r3 regression-risk: 346s/28-turns/no file;
/// tg-42f r1 test-coverage: 13-turns/no file, no stale shadow) had no captured
/// transcript to confirm WHY the critic's own file-write tool call never landed
/// — cwd drift, a turn-budget cutoff before the write, or prompt drift were all
/// plausible and not distinguishable from static review alone; the #3 fixes
/// close the SYMPTOM (a stale/absent file being mis-scored) regardless of which.
///
/// **Gate-integrity #4 — the cwd-relative write path, confirmed (bead
/// `tg-r66`)**: a later live incident (session `tgdog-snp`/`tg-m2q` r1,
/// 2026-07-07) DID capture the cwd-drift hypothesis in the act: the critic
/// prompt asked for the RELATIVE path `.grid/critique/<rubric>.json`, and a
/// `test-coverage` critic that `cd`d into a package to run `dart test`
/// resolved it against its new cwd, writing a STRAY verdict at
/// `packages/grid_assets/.grid/critique/test-coverage.json` — so the canonical
/// path was empty AND the stdout envelope parse missed the critic's
/// `## Grade: A` summary shape ⇒ a false fail-closed F ⇒ ps#11's false gate.
/// Three defense-in-depth fixes: (1) [CriticCapability.buildCriticPrompt] now
/// interpolates the workspace-derived ABSOLUTE canonical path, so the write is
/// cwd-invariant; (2) [_strayVerdict] is a read-side belt that accepts a
/// round-fresh stray `.grid/critique/<rubric>.json` found anywhere under the
/// worktree (the `nodePath` freshness stamp keeps it safe); (3) the envelope
/// fallback ([_verdictFromHeading]) now also recognizes a `Grade: <A-F>`
/// heading, not just `Verdict:`. A critic that keeps failing to write a
/// canonical file now reliably grades a LOUD, provenanced fail-closed F every
/// round (or is recovered from the stray/envelope), never a silently-recycled
/// stale grade.
///
/// **A third, DISTINCT incident class (tg-83y r3, 2026-07-04) is OUT OF SCOPE
/// here**: the LLM lanes graded against a tree the agent was still editing
/// (its final commit landed AFTER the grading window), and the gating lane's
/// re-run still F'd against what looked like the committed tree — an
/// intra-round ORDERING bug (the review sub-circuit mounting before the
/// agent's completion is truly durable), not a transport miss. Nothing in
/// this file can fix it: every capability here reads the ambient [Workspace]
/// / bead state the_grid's engine hands it at entry and trusts it; the fix is
/// upstream, in the_grid's own session/reconcile sequencing (gating the
/// `review` mount on the agent step's durable completion — a fence/commit —
/// and running against the COMMITTED tree state), tracked alongside
/// `SCRATCH-orchestration-determinism.md`'s I-catalog in that repo.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/site_binding.dart';
import '../agent/usage_report.dart';
import 'route_failure.dart';

/// The gating rubric id — its grade `F` is a hard block (a non-zero Validation
/// Plan command), decided by the route's matrix.
const String kGatingRubric = 'code-validation';

/// The three LLM critic rubric ids (each graded in isolation by a `claude`
/// critic; anti-anchoring).
const List<String> kLlmRubrics = [
  'spec-adherence',
  'regression-risk',
  'test-coverage',
];

/// Every committee rubric id, in declaration order (the gating lane first).
const List<String> kCommitteeRubrics = [kGatingRubric, ...kLlmRubrics];

/// The workspace-relative directory each critic writes its verdict / rc into.
const String _critiqueDir = '.grid/critique';

/// The hygiene step id every critic lane transitively `dependsOn`
/// (gate-integrity #3) — wipes [_critiqueDir] before any lane can read or
/// write this round.
const String kClearCritiqueStep = 'clear-critique';

/// The diff-pinning pre-critic step id (bead `pow-6wo`) every critic lane
/// `dependsOn`. [PinDiffCapability] computes the bead BRANCH'S OWN delta
/// (`git diff origin/<base>...HEAD`) and pins it as the critics' review scope —
/// and, when that delta is EMPTY, [Escalate]s the whole round (a stale/no-op bead)
/// so the critics never grade PRE-EXISTING mainline work as if it were the
/// bead's diff (the live finding this step exists to close). Runs AFTER
/// [kClearCritiqueStep] so its pinned-diff file survives that round's wipe.
const String kPinDiffStep = 'pin-diff';

/// The file [PinDiffCapability] pins the review scope into — the bead branch's
/// own diff, under [_critiqueDir] (round-fresh: cleared every round by
/// [kClearCritiqueStep], which [kPinDiffStep] `dependsOn`, then rewritten). Each
/// LLM critic's prompt points here as its EXCLUSIVE review scope.
const String _pinnedDiffName = 'pinned.diff';

/// The absolute path the pinned review-scope diff lives at under [workspaceDir]
/// — derived identically by [PinDiffCapability] (the writer) and
/// [CriticCapability.buildCriticPrompt] (which names it to the critic).
String pinnedDiffPath(String workspaceDir) =>
    p.join(workspaceDir, _critiqueDir, _pinnedDiffName);

/// The absolute path of the round's critique dir under [workspaceDir] — the
/// canonical home of every lane's verdict file (`<rubric>.json`). Derived
/// identically by [ClearCritiqueCapability] (the code + spec committees' wipe)
/// and by `IntakeCapability` (the readiness lane's own wipe, bead `pow-q7n`),
/// so the two can never drift.
String critiqueDirPath(String workspaceDir) =>
    p.join(workspaceDir, _critiqueDir);

/// The real [DirectoryClearer]: deletes [dir] (if present) and recreates it
/// empty. Public so every hygiene step that wipes the critique dir shares ONE
/// implementation (tests inject a no-op instead).
void clearDirectory(String dir) {
  final d = Directory(dir);
  if (d.existsSync()) d.deleteSync(recursive: true);
  d.createSync(recursive: true);
}

/// The parent node path of [nodePath] (`'a/b/route'` → `'a/b'`), so a join step
/// computes its sibling lane paths (`'$parentPath/$laneId'`). ONE definition —
/// every route in this pack derives its siblings the same way.
String parentPath(String nodePath) {
  final i = nodePath.lastIndexOf('/');
  return i < 0 ? '' : nodePath.substring(0, i);
}

/// The verdict JSON's ROUND stamp key (A15(5) alt-A) — ONE name, written by
/// every critic prompt ([verdictJsonTemplate]) and read by the verdict parser,
/// so the writer and reader can never drift apart.
const String kVerdictRoundKey = 'round';

/// THIS node's ROUND — the `rewindCount` the engine bumps on every rewind wave
/// that re-keys it (the_grid `tg-o90`), read off the ambient [SiblingView] with
/// the EFFECT verb at a capability's spawn/result edge (ADR-0008 D3 — never a
/// subscription). It is the HONEST counter A15(2) established: a [Rewind] does
/// not re-mint the session, so the cursor SURVIVES the round. It is the SAME
/// counter `SpecRouteCapability` escalates on (`respec.dart`), so the round a
/// critic stamps and the round the route bounds are one number.
///
/// A node the cursor does not know yet (a first, never-rewound incarnation) is
/// round 0 — [SiblingView.cursorOf]'s own default. ZERO I/O, so it holds in the
/// offline/dry-run posture too.
int roundOf(TreeContext context, String nodePath) =>
    (context.getInheritedSeedOfExactType<SiblingView>() ?? const SiblingView())
        .cursorOf(nodePath)
        .rewindCount;

/// The verdict JSON SHAPE every critic prompt hands its critic — the TWO
/// freshness stamps side by side: [nodePath] (A4's FOREIGN-NODE fence — WHOSE
/// verdict is this?) and [round] (A15(5) alt-A's ROUND fence — WHICH round's?).
/// [rationaleHint] lets a lane phrase its own rationale ask (the readiness lens
/// wants the fix, not just the why) without forking the shape.
///
/// ONE writer-side definition, shared by all three critic families (code, spec,
/// readiness), because they share ONE reader ([_verdictFromFile]; ADR-0000
/// A13(3)): a lane that omitted the round stamp would fail-close every verdict
/// it wrote.
String verdictJsonTemplate({
  required String rubric,
  required String nodePath,
  required int round,
  String rationaleHint = '<why>',
}) =>
    '{"rubric":"$rubric","version":1,"grade":"<A-F>",'
    '"rationale":"$rationaleHint","nodePath":"$nodePath",'
    '"$kVerdictRoundKey":$round}';

/// The stamp instruction that follows [verdictJsonTemplate] in every critic
/// prompt: both stamps are FIXED and copied verbatim. LOUD about the
/// consequence — a verdict carrying the wrong stamps is DISCARDED, never
/// repaired.
const String kVerdictStampInstruction =
    'The `nodePath` and `round` values above are FIXED — copy them '
    'byte-for-byte into your verdict. `nodePath` proves the verdict is YOURS '
    'and not another node\'s stray file; `round` proves it is THIS round\'s — a '
    'rework wave re-runs you in the SAME worktree under the SAME node path, so '
    'an earlier round\'s verdict file is otherwise indistinguishable from '
    'yours. A verdict carrying the wrong stamps (or none) is DISCARDED and the '
    'lane grades F.';

/// A pluggable source of a rubric's prose text by id (D-9: the Packaged-AI-Asset
/// loader replaces the inline placeholder). Returns the rubric body a critic's
/// prompt embeds.
typedef RubricSource = String Function(String rubricId);

/// The pluggable critique-dir hygiene seam [ClearCritiqueCapability] uses
/// (D-9-style injection, mirrors [RubricSource]) — defaults to the real
/// delete+recreate; tests inject a no-op so the offline suite never touches a
/// real filesystem at a synthetic workspace path.
typedef DirectoryClearer = void Function(String dir);

/// The adversarial code-committee circuit (id `code_review`) — a hygiene step
/// (gate-integrity #3, [ClearCritiqueCapability]) → a diff-pinning pre-critic
/// step (bead `pow-6wo`, [PinDiffCapability]) → four critic lanes fanned out in
/// parallel → a `route` step that joins on all four and aggregates their grades
/// (M5 Track C / C1).
///
/// **Scope-pinning (bead `pow-6wo`)**: [kPinDiffStep] runs BEFORE any critic and
/// computes the bead branch's OWN delta (`git diff origin/<base>...HEAD`). An
/// EMPTY delta — the live-arm finding: a branch with ZERO commits beyond
/// origin/main whose work was already shipped in mainline, yet whose critics
/// graded that PRE-EXISTING mainline work A/B — [Escalate]s the whole round for a
/// human ruling INSTEAD of reaching the critics. A non-empty delta is pinned to
/// a file each critic reviews as its EXCLUSIVE scope (never free rein of the
/// worktree). The four critics `dependsOn` [kPinDiffStep], so its [Escalate]
/// withholds them.
///
/// Reentrant: composed at the same `CircuitScope` seam as any other circuit, so
/// Track E can drop it in as the `code` circuit's `verify` via a `SubCircuitStep`
/// with zero engine changes.
const Circuit kCodeReviewCircuit = Circuit(
  id: 'code_review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: kClearCritiqueStep, capabilityId: kClearCritiqueStep),
    CapabilityStep(
      stepId: kPinDiffStep,
      capabilityId: kPinDiffStep,
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: kGatingRubric,
      capabilityId: 'critic',
      params: {'rubric': kGatingRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'spec-adherence',
      capabilityId: 'critic',
      params: {'rubric': 'spec-adherence'},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'regression-risk',
      capabilityId: 'critic',
      params: {'rubric': 'regression-risk'},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'test-coverage',
      capabilityId: 'critic',
      params: {'rubric': 'test-coverage'},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {
        kGatingRubric,
        'spec-adherence',
        'regression-risk',
        'test-coverage',
      },
      params: {
        'critics': 'code-validation,spec-adherence,regression-risk,test-coverage',
        'gating': kGatingRubric,
      },
    ),
  ],
);

/// Wipes [_critiqueDir] at the START of every committee round — a
/// [ServiceCapability] all four critic lanes `dependsOn`, so it always
/// completes before any lane can read OR write a verdict (gate-integrity #3).
/// A rework round reuses the SAME workspace directory, so a prior round's
/// verdict/rc file otherwise survives on disk; clearing first turns a
/// critic's missing write back into a recognizable miss instead of a stale
/// grade impersonating a fresh one.
///
/// Best-effort BY DESIGN: a delete/recreate failure never Gates the round — the
/// gating lane's own `sh -c` script always `mkdir -p`s the dir again regardless.
///
/// **A BELT, not the guarantee (A15(5) alt-A, bead `pow-05f`)**. It was the
/// whole round-freshness guarantee for exactly one amendment: A4 made the
/// `nodePath` stamp the round fence on the premise that a round re-keys the
/// bead id to `<bead>#rN` — and neither a `grid rework` round (A14(5)) nor a
/// `RouteVerdict.Rewind` wave (tg-o90 — only a `rewindCount` bump) does, so the
/// path is byte-identical round to round. The verdict now STAMPS ITS ROUND
/// ([verdictJsonTemplate], [roundOf]) and [_verdictFromFile] VERIFIES it, so a
/// stale verdict file that SURVIVES a failed wipe is caught positively at the
/// READ. The wipe stays and still earns its place — it keeps the workspace
/// honest (a critic that writes nothing this round leaves no shadow at all),
/// and the gating lane's `.rc` carries NO stamp, so the wipe remains ITS
/// freshness fence — but a failed wipe can no longer produce a stale LLM grade.
/// The spec circuit still wires it DOWNSTREAM of `specify` (`kSpecReviewCircuit`)
/// so it re-runs on every auto-respec wave.
class ClearCritiqueCapability extends ServiceCapability {
  /// Creates the capability, optionally over an injected [clearer] (tests
  /// inject a no-op so the offline suite never touches a real filesystem at a
  /// synthetic workspace path — Fakes, not mocks); defaults to the real
  /// delete+recreate.
  const ClearCritiqueCapability({DirectoryClearer? clearer}) : _clearer = clearer;

  final DirectoryClearer? _clearer;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return const Ok();
    try {
      (_clearer ?? clearDirectory)(critiqueDirPath(workspace.workspaceDir));
    } catch (_) {
      // Best-effort hygiene — the freshness stamp is the fail-safe backstop.
    }
    return const Ok();
  }
}

/// Pins the CRITICS' REVIEW SCOPE to the bead branch's OWN delta (bead
/// `pow-6wo`) — a [ServiceCapability] every critic lane `dependsOn`, so it
/// always runs BEFORE any critic and can withhold them.
///
/// **The invariant it protects (LOUD-or-gone)**: a critic must grade the
/// **bead branch's own delta**, never the ambient worktree. The live-arm
/// finding: 4 of 6 ready beads were already shipped in mainline; for two the
/// branch had ZERO commits beyond origin/main, yet the critics graded that
/// PRE-EXISTING mainline work A/B-range as if it were the bead's diff (one
/// spec-adherence A explicitly cited a months-old mainline commit). Nothing
/// pinned the review to the branch's own delta.
///
/// This step computes that delta once, up front:
///  - `git log --oneline origin/<base>..HEAD` — the commit list under review
///    (provenance);
///  - `git diff origin/<base>...HEAD` — the branch's own change from the
///    MERGE-BASE (three-dot: a base that moved forward while the bead ran can
///    never widen the scope), pinned to [pinnedDiffPath] for the critics.
///
/// Three terminals:
///  - **EMPTY delta ⇒ [Escalate]** — the distinct no-op outcome. A branch with
///    no reviewable change routes to a human ruling INSTEAD of reaching the
///    critics (a stale bead whose work is already in mainline, or a net-zero
///    diff). The critics `dependsOn` this step, so the escalation withholds them
///    — they never run against a scope that isn't the bead's.
///  - **git could not compute the delta ⇒ a thrown [RouteFailure]** — LOUD. An
///    unresolvable `origin/<base>` (or a `git` that won't launch) means the scope
///    is UNKNOWN; failing closed routes to supervision rather than silently
///    escalating (a false stale-bead flag) or silently advancing (critics with an
///    empty scope).
///  - **non-empty delta ⇒ [Advance]** — the pinned diff is written and the round
///    proceeds; the payload carries route-style provenance
///    (`base`/`commits`/`diffBytes`).
///  - **a workspace dir that EXISTS but is not itself the checkout root ⇒ a
///    thrown [RouteFailure]** — the checkout-root guard (bead `pow-4pr`). When
///    provisioning fails sourceless (scaffold residue without a checkout, bead
///    `pow-2ts`), `git` walks UP from the workspace dir to an ANCESTOR checkout
///    and computes the WRONG delta — the live space-ojl incident held a real,
///    validation-green branch as 'stale/no-op — ZERO commits'. Before any
///    log/diff, the guard probes `git rev-parse --show-toplevel` in the
///    workspace dir and requires it to resolve to the workspace dir ITSELF.
///    Both sides are SYMLINK-resolved before comparing: `git` resolves `/tmp`
///    → `/private/tmp` on macOS, a lexical canonicalize does not.
///
/// Offline/dry-run posture: a null [Workspace], or a workspace directory that
/// does not exist on disk (the synthetic `/grid/worktrees/...` path an offline
/// suite mounts, or a build with no worktree materialized), skips straight to
/// [Advance] with NO git call — the same no-op posture as
/// [GitSourceControl.provisionWorkspace] / [AgentCapability] pub-linkage. A
/// LIVE review always has a real worktree the agent just worked in, so the
/// scope guard runs when it matters; the checkout-root guard fires ONLY for a
/// present-but-wrong dir, so this posture is untouched.
class PinDiffCapability extends RouteCapability {
  /// Creates the capability, optionally over an injected [runner] (tests
  /// inject a recording/canned fake — Fakes, not mocks); defaults to the real
  /// [SystemGitRunner], mirroring [RebaseCapability]'s own seam.
  const PinDiffCapability({GitRunner? runner}) : _runner = runner;

  final GitRunner? _runner;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient workspace at ENTRY (while mounted); after every await
    // only the captured values + the cancel token are touched.
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return const Advance();
    final workspaceDir = workspace.workspaceDir;
    // Offline/dry-run: no real worktree to diff — no-op (same posture as
    // GitSourceControl.provisionWorkspace / AgentCapability._linkWorkspace).
    if (!Directory(workspaceDir).existsSync()) return const Advance();

    final runner = _runner ?? SystemGitRunner();
    final baseRef = 'origin/${workspace.baseBranch}';

    // The checkout-root guard (bead pow-4pr): the dir EXISTS — before trusting
    // it as the diff scope, require it to BE the checkout root. `git` walks up
    // to an ancestor checkout from a sourceless scaffold dir (the space-ojl
    // shape), so `--is-inside-work-tree` would pass exactly when it must not.
    final toplevel = await runner.run(
      workingDirectory: workspaceDir,
      args: ['rev-parse', '--show-toplevel'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;
    if (!toplevel.ok) {
      throw RouteFailure(
        'pin-diff: $workspaceDir exists but holds no git checkout '
        '(`git rev-parse --show-toplevel` failed: '
        '${_reasonTail(toplevel.output)}) — a sourceless workspace '
        '(provisioning failure, bead pow-2ts). Refusing rather than minting a '
        'false stale/no-op verdict.',
      );
    }
    final expectedRoot = _resolvedPath(workspaceDir);
    final resolvedTopLevel = _resolvedPath(toplevel.output.trim());
    if (!p.equals(expectedRoot, resolvedTopLevel)) {
      throw RouteFailure(
        'pin-diff: the checkout root for $workspaceDir is resolved toplevel '
        '$resolvedTopLevel — the workspace dir sits INSIDE an ancestor '
        'checkout instead of being one (expected $expectedRoot). The diff '
        'would be computed against the WRONG tree. Refusing rather than '
        'minting a false stale/no-op verdict (the space-ojl shape).',
      );
    }

    // The commit list on THIS branch beyond the base (provenance; `log base..HEAD`).
    final log = await runner.run(
      workingDirectory: workspaceDir,
      args: ['log', '--oneline', '$baseRef..HEAD'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;

    // The pinned review scope — the branch's OWN delta from the merge-base
    // (`diff base...HEAD`, three-dot).
    final diff = await runner.run(
      workingDirectory: workspaceDir,
      args: ['diff', '$baseRef...HEAD'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;

    // git could not compute the delta (unresolvable base ref, or a git that
    // won't launch) — the scope is UNKNOWN. Fail LOUD (never a silent escalation
    // that masquerades as a stale bead, nor a silent advance handing critics an
    // empty scope).
    if (!diff.ok) {
      throw RouteFailure(
        'pin-diff: could not compute `git diff $baseRef...HEAD` in '
        '$workspaceDir — ${_reasonTail(diff.output)}',
      );
    }

    final commits = _commitLines(log.output);
    final diffText = diff.output;

    // EMPTY delta ⇒ the distinct no-op terminal: a human ruling, not the critics
    // (A9's empty-delta gate, re-homed onto Escalate — the SAME park).
    if (diffText.trim().isEmpty) {
      return Escalate(
        commits.isEmpty
            ? 'pin-diff: stale/no-op bead — the branch has ZERO commits beyond '
                  '$baseRef, so `git diff $baseRef...HEAD` is EMPTY. Nothing for '
                  'the critics to review (the work is likely already in '
                  'mainline). Routed for a human ruling instead of critique.'
            : 'pin-diff: no-op bead — ${commits.length} commit(s) beyond '
                  '$baseRef, but their net `git diff $baseRef...HEAD` is EMPTY. '
                  'Nothing for the critics to review. Routed for a human ruling '
                  'instead of critique.',
      );
    }

    // Pin the scope for the critics (round-fresh — clear-critique wiped
    // .grid/critique first, and this step `dependsOn` it). A write that cannot
    // land means the critics would fall back to free rein of the worktree — the
    // exact failure being closed — so it fails LOUD, never a silent advance.
    try {
      _writePinnedDiff(workspaceDir, baseRef, workspace.branch, commits, diffText);
    } catch (e) {
      throw RouteFailure('pin-diff: could not write the pinned diff — $e');
    }

    return Advance({
      'base': baseRef,
      'commits': '${commits.length}',
      'diffBytes': '${diffText.length}',
    });
  }

  /// Writes the pinned review scope to [pinnedDiffPath]: a short header naming
  /// the branch, the base, and the commits under review, followed by the raw
  /// `git diff` body the critics read.
  void _writePinnedDiff(
    String workspaceDir,
    String baseRef,
    String branch,
    List<String> commits,
    String diff,
  ) {
    final header = StringBuffer()
      ..writeln('# Pinned review scope: $branch vs $baseRef')
      ..writeln('# `git diff $baseRef...HEAD` — the ONLY code this bead changed.')
      ..writeln('# Commits under review (`git log $baseRef..HEAD`):');
    if (commits.isEmpty) {
      header.writeln('#   (none)');
    } else {
      for (final c in commits) {
        header.writeln('#   $c');
      }
    }
    header.writeln();
    File(pinnedDiffPath(workspaceDir))
      ..createSync(recursive: true)
      ..writeAsStringSync('$header$diff');
  }

  /// A path prepared for root comparison: SYMLINKS RESOLVED, then lexically
  /// canonicalized. `git rev-parse --show-toplevel` reports the symlink-resolved
  /// root (`/private/tmp/...` on macOS) while the ambient workspace dir is
  /// usually unresolved (`/tmp/...`); `p.canonicalize` alone is purely lexical
  /// and would read those as DIFFERENT roots — a spurious refusal on every
  /// genuine checkout under a symlinked parent. A path that cannot resolve
  /// (vanished mid-route) falls back to the lexical form so the refusal message
  /// carries the literal path.
  static String _resolvedPath(String path) {
    try {
      return p.canonicalize(Directory(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      return p.canonicalize(path);
    }
  }
}

/// The non-empty, trimmed lines of a `git log --oneline` body — the commits on
/// the branch beyond the base, in `<sha> <subject>` form.
List<String> _commitLines(String logOutput) => logOutput
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

/// The TAIL of git combined output — the useful diagnosis is the LAST line
/// (git prints progress first, the fatal message last), and a `Failed` reason
/// is truncated to its FIRST chars downstream; taking the tail keeps the
/// diagnosis, not the noise. A leading `…` marks a cut.
String _reasonTail(String output, [int max = 300]) {
  final trimmed = output.trim();
  return trimmed.length <= max
      ? trimmed
      : '…${trimmed.substring(trimmed.length - max)}';
}

/// One critic, in isolation — a [ProcessCapability] whose `params['rubric']`
/// selects the lane (C2). Two flavors behind the single `critic` capability id:
///
///  - the GATING `code-validation` lane runs the bead's OWN Validation Plan via
///    `sh`: it wraps the plan so the plan's exit code is captured to an rc file,
///    so ANY terminal exit `complete`s the step (the grade — A iff the plan was
///    zero, else F — rides the [result] hook, leaving the route as the single
///    decision point: no retry storm on a deterministic command failure). It is
///    a VALIDATION RUNNER, not an agent — it keeps its direct `sh -c` config;
///  - the three LLM lanes RIDE THE HARNESS (ADR-0008 Decision 10 — critics are
///    agents), in the **GRADE role** ([AgentRole.grade], bead `pow-edp`): the
///    effective [AgentConfig] resolves through the same ladder as the coding
///    agent but off the GRADER rung — a critic reads a pinned diff against ONE
///    rubric and writes a letter, so absent a bead or `--grader-model` override
///    it rides the MID tier ([kMidModelDefault], `sonnet`) while the build rides
///    the FRONTIER tier ([kFrontierModelDefault], `opus`). The resolved harness
///    carries the critic's prompt (ONLY its own rubric); the verdict JSON is
///    parsed by the [result] hook, which also merges the harness's CAPTURE-ONLY
///    usage telemetry (FT-2 — tokens/cost/turns/duration, and the `model` that
///    actually ran) alongside the grade (fail-safe: no usage ⇒ just the grade).
///
/// A capability reads its ambient values — the work [Bead], the [Workspace],
/// the agent scope — with the effect verb (`getInheritedSeedOfExactType`) at
/// entry, and holds no writer/notifier: the four derailment-invariants hold by
/// layering + the host's single write-locus.
class CriticCapability extends ProcessCapability {
  /// Creates the critic, optionally over a [rubrics] source (D-9 wires the
  /// Packaged-AI-Asset loader; absent ⇒ an inline placeholder so C is testable
  /// with no real assets).
  const CriticCapability({RubricSource? rubrics}) : _rubrics = rubrics;

  final RubricSource? _rubrics;

  /// The injected rubric source (D-9) — exposed for subclasses: the
  /// spec-readiness committee's `SpecCriticCapability` (bead `pow-6ao`)
  /// embeds prose from the SAME source into its own prompt shape.
  @protected
  RubricSource? get rubricSource => _rubrics;

  String _rubricOf(StepArgs args) => args.params['rubric'] ?? '';

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // Read the ambient values at ENTRY (synchronously, while mounted).
    final rubric = _rubricOf(args);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'CriticCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    if (rubric == kGatingRubric) {
      // The validation runner — a deterministic `sh -c`, NOT an agent.
      return RuntimeConfig(
        workDir: workspace.workspaceDir,
        command: 'sh',
        args: ['-c', _gatingScript(_validationPlan(bead))],
        lifecycle: Lifecycle.oneTurn,
      );
    }
    // The critic lanes are agents (ADR-0008 Decision 10): resolve the
    // effective config through the ladder and delegate the invocation to the
    // resolved harness — exactly like AgentCapability.spawn.
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final config = resolveAgentConfig(
      role: AgentRole.grade,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
    );
    final environment = registry.resolve(config.harness);
    return spawnFor(
      environment: environment,
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(name: config.harness, environment: environment),
      brief: AgentBrief(
        task: buildCriticPrompt(
          bead,
          rubric,
          args.nodePath,
          workspace.workspaceDir,
          round: roundOf(context, args.nodePath),
        ),
      ),
      workspace: workspace,
      // CAPTURE-ONLY usage telemetry (FT-2): the resolved harness (claude)
      // redirects its `--output-format json` envelope here; result() merges the
      // fields into the critic's payload. The verdict file the critic writes is
      // a separate path, so capture never touches the grade.
      usageOut: usageReportPath(args.nodePath),
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) {
    // The lane is encoded in the event name (`$sessionId/.../$stepId`, and the
    // step id IS the rubric id) — the only lane signal available to the
    // ctx-free interpretEvent. The GATING lane `complete`s on ANY terminal exit
    // (the grade rides result()); the LLM lanes use the standard job mapping (a
    // clean exit completes, a non-zero exit / death fails).
    final isGating = event.name.endsWith('/$kGatingRubric');
    if (isGating) {
      return switch (event) {
        Exited() => StepSignal.complete,
        Died() => StepSignal.failed,
        _ => StepSignal.none,
      };
    }
    return switch (event) {
      Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
      Exited() || Died() => StepSignal.failed,
      _ => StepSignal.none,
    };
  }

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async {
    // Read the ambient workspace at ENTRY (while mounted); only the captured
    // value is touched below.
    final rubric = _rubricOf(args);
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) {
      throw StateError(
        'CriticCapability.result requires the ambient Workspace '
        '(SessionScope mounts it)',
      );
    }
    final workspaceDir = workspace.workspaceDir;
    // THIS round — the node's own `rewindCount` (A15(5) alt-A), read at ENTRY
    // with the workspace. The gating lane ignores it: its `.rc` carries no
    // stamp and the wipe is still ITS freshness fence.
    final round = roundOf(context, args.nodePath);
    if (rubric == kGatingRubric) {
      // The plan's exit code, captured by the spawn wrapper. Fail-closed: a
      // missing rc (the plan never ran) grades F — a plan-less bead must NEVER
      // silently pass. [ClearCritiqueCapability] wipes this file every round,
      // so an rc found here is guaranteed fresh — no separate stamp needed.
      final rc = File(p.join(workspaceDir, _critiqueDir, '$kGatingRubric.rc'));
      if (!rc.existsSync()) {
        return const {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale': 'no validation-plan rc file — fail-closed default',
        };
      }
      final code = rc.readAsStringSync().trim();
      return {'grade': code == '0' ? 'A' : 'F', 'transport': 'file'};
    }
    // An LLM critic's verdict JSON. Fail-closed: a missing / malformed / STALE
    // verdict (no file, unparseable JSON, no readable `grade`, a `nodePath`
    // stamp naming ANOTHER node — gate-integrity #3 — or a `round` stamp naming
    // an EARLIER round of THIS node — A15(5) alt-A) falls back, in
    // order, to a round-fresh STRAY verdict (gate-integrity #4 — a critic that
    // cd'd mid-run wrote the file under a subdir instead of the canonical path;
    // [_strayVerdict]) then to the captured harness RESULT TEXT (tg-291 — the
    // verdict-transport brittleness: a critic that graded cleanly but wrote its
    // verdict into stdout instead of the file must not be scored F on a
    // transport slip alone). The canonical FILE wins whenever it parses AND is
    // fresh; only an absent/malformed/stale canonical file consults the
    // fallbacks. No parseable verdict ANYWHERE still grades F — every path now
    // names its own `transport` (`file`/`file-stray`/`envelope`/
    // `fail-closed-default`), so a false-gate post-mortem never has to guess
    // which channel produced the grade.
    final verdict = File(p.join(workspaceDir, _critiqueDir, '$rubric.json'));
    final graded =
        _verdictFromFile(
          verdict,
          expectedNodePath: args.nodePath,
          expectedRound: round,
        ) ??
        _strayVerdict(workspaceDir, rubric, args.nodePath, round) ??
        _verdictFromResultText(
          readEnvelopeResultText(workspaceDir, args.nodePath),
        ) ??
        const {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale':
              'no parseable verdict via file or envelope — fail-closed default',
        };
    // Merge the CAPTURE-ONLY usage telemetry (FT-2) into the payload. FAIL-SAFE:
    // an absent / malformed envelope yields no fields, NEVER a throw — the grade
    // (fail-closed above) is unaffected. Collision-safe keys (grade/rationale vs
    // tokensIn/…), so the merge never shadows the verdict.
    final usage = readUsageFields(workspaceDir, args.nodePath);
    return usage.isEmpty ? graded : {...graded, ...usage};
  }

  /// The rubric prose embedded in a critic's prompt — the injected [rubrics]
  /// source (D-9), or an inline placeholder so C is testable with no assets.
  String _rubricText(String rubric) =>
      _rubrics?.call(rubric) ??
      '(rubric `$rubric` — the Packaged-AI-Asset loader supplies the bands in '
          'Track D)';

  /// Assembles the LLM critic's prompt for [rubric] over the work [bead] —
  /// names ONLY its own rubric (anti-anchoring: a critic must not see the other
  /// lanes' concerns or grades), carries the full bead, and instructs a single
  /// A–F grade written as a verdict JSON. Rides the harness as a bare
  /// `AgentBrief(task: …)` (no working agreement, no context blocks — so the
  /// rendered brief IS this prompt, byte-identical).
  ///
  /// The file-write instruction is deliberately the LAST thing the prompt says
  /// (tg-291 — recency: a model observed to state a clean verdict in its
  /// response prose while skipping the file write, tripping a false gate on the
  /// fail-closed missing-file rule). It is imperative, names the exact path, and
  /// is explicit that stating the verdict in prose does NOT satisfy it — the
  /// file write is REQUIRED regardless. `result()` still has a stdout-envelope
  /// fallback for when a critic slips anyway; this hardening is to make the
  /// slip rarer, not to rely on the fallback.
  ///
  /// The verdict JSON also carries TWO FRESHNESS STAMPS ([verdictJsonTemplate]),
  /// both copied byte-for-byte: [nodePath] (gate-integrity #3 — WHOSE verdict is
  /// this?) and [round] (A15(5) alt-A — WHICH round's?, this node's own
  /// `rewindCount` via [roundOf]). [_verdictFromFile] rejects a file that fails
  /// EITHER, so a verdict left over from an earlier round in the SAME reused
  /// workspace directory — where the node path is byte-identical, and only the
  /// round differs — is never silently read as this round's.
  ///
  /// **Gate-integrity #4 — the cwd-relative write path (bead `tg-r66`)**: the
  /// path handed to the critic is the workspace-derived ABSOLUTE canonical
  /// path (`[workspaceDir]/.grid/critique/<rubric>.json`), NOT a
  /// workspace-relative one. A critic that `cd`s mid-run (`test-coverage` cd's
  /// into a package to run `dart test` — the chronically flaky lane) would
  /// resolve a relative `.grid/critique/<rubric>.json` against its CURRENT cwd
  /// and write a STRAY verdict under the package (observed live:
  /// `packages/grid_assets/.grid/critique/test-coverage.json`), leaving the
  /// canonical path empty ⇒ a false fail-closed gate. An absolute path is
  /// cwd-invariant, so the write lands where `result()` reads regardless of
  /// where the critic wandered. ([_strayVerdict] is the read-side belt for a
  /// critic that still writes off-path some other way.)
  ///
  /// **Scope-pinning (bead `pow-6wo`)**: the prompt names the pinned-diff file
  /// ([pinnedDiffPath]) [PinDiffCapability] wrote — the bead branch's OWN delta
  /// (`git diff origin/<base>...HEAD`) — as the critic's EXCLUSIVE review scope.
  /// The live finding this closes: with the bead's work already in mainline,
  /// critics graded PRE-EXISTING mainline code A/B as if it were the bead's
  /// diff. The instruction is explicit that code outside the pinned diff is OUT
  /// OF SCOPE, so a critic cannot credit (or blame) work the bead did not do.
  /// (An EMPTY delta never reaches here — [PinDiffCapability] gates the round
  /// upstream.)
  ///
  /// Exposed for unit tests.
  String buildCriticPrompt(
    Bead bead,
    String rubric,
    String nodePath,
    String workspaceDir, {
    required int round,
  }) {
    final path = p.join(workspaceDir, _critiqueDir, '$rubric.json');
    final diffPath = pinnedDiffPath(workspaceDir);
    final b = StringBuffer()
      ..writeln('# Code review — rubric: `$rubric`')
      ..writeln()
      ..writeln(
        'You are ONE critic in an adversarial committee. Review the work ONLY '
        'against the `$rubric` rubric below — do not weigh any other concern.',
      )
      ..writeln()
      ..writeln('## Rubric: $rubric')
      ..writeln(_rubricText(rubric))
      ..write(_beadBlock(bead))
      ..writeln()
      ..writeln('## Review scope — the pinned diff (READ THIS FIRST)')
      ..writeln(
        'Your review is scoped to EXACTLY this bead branch\'s OWN change — its '
        'delta from the base branch (`git diff origin/<base>...HEAD`), pinned '
        'at the ABSOLUTE path `$diffPath`. Read that file FIRST: it is the ONLY '
        'code this bead changed.',
      )
      ..writeln(
        'Grade ONLY what that diff changes. Code the diff does not touch is OUT '
        'OF SCOPE — do NOT grade pre-existing code, and do NOT credit (or blame) '
        'work that is already in mainline outside this diff. If you cannot point '
        'a claim to a hunk of the pinned diff, it does not belong in your grade.',
      )
      ..writeln()
      ..writeln('## Your verdict')
      ..writeln(
        'Grade the work A (best) through F (worst) against `$rubric` ONLY. '
        'Your verdict is JSON of this exact shape:',
      )
      ..writeln(
        verdictJsonTemplate(rubric: rubric, nodePath: nodePath, round: round),
      )
      ..writeln()
      ..writeln(kVerdictStampInstruction)
      ..writeln()
      ..writeln(
        'You MUST write that JSON to the exact ABSOLUTE path `$path` before you '
        'finish. It is an absolute path on purpose — write it there regardless '
        'of your current working directory (if you `cd` elsewhere to run a '
        'command, this path still resolves to the right file). This is REQUIRED '
        'even if you also state your verdict in your response text — stating the '
        'grade in prose alone does NOT satisfy this instruction. Write the file '
        'at `$path`.',
      );
    return b.toString();
  }
}

/// The route/aggregate step — a [ServiceCapability] that reads its sibling
/// critics' grades through the AMBIENT [SiblingView] (mounted by
/// `SessionScope`; read with the effect verb — D-5, never a subscription/
/// re-query) and applies the deterministic matrix (C3, asset policy):
///
///  - the gating critic grade `F` (a non-zero Validation Plan) → [Escalate]
///    (hard block);
///  - a grade SPREAD ≥ 3 letters across the lanes → [Escalate] (human ultimatum);
///  - any NON-gating critic at `D`/`F` → [Escalate] (rework — the `restForOne`
///    transitive re-key is deferred, so a D/F parks at the bound handler for now);
///  - else (all A–C, gating not F, spread < 3) → [Advance] (on to delivery).
///
/// The [Advance] payload carries ROUTE PROVENANCE (FT-2, CAPTURE-ONLY): the
/// grade vector consumed (`grades` — `lane=grade` CSV in [kCommitteeRubrics]
/// order), the computed `spread`, and the matrix arm that fired (`rule` =
/// `all-approve`) — making the keep/kill export self-contained without changing
/// the matrix. Escalations are UNCHANGED (their reason string already names the
/// rule).
///
/// Fail-closed: an unread / missing sibling grade is treated as `F`, so a forged
/// or absent grade can NEVER advance (the mutation-tested property).
///
/// GENERIC over its `critics`/`gating` params (bead `pow-6ao`): the SAME
/// capability joins the spec-readiness committee (`specify.dart`'s
/// `kSpecReviewCircuit` — gating `spec-validation` + four spec critics) with
/// its own param set; the matrix, the fail-closed defaults, and the provenance
/// payload are committee-agnostic.
///
/// NAMED `CodeRouteCapability`, not `RouteCapability`: the engine now EXPORTS an
/// abstract `RouteCapability` (the route primitive this extends), so the short
/// name is taken. The STEP id stays `route` — it is a persisted cursor key.
class CodeRouteCapability extends RouteCapability {
  /// Creates the code committee's route.
  const CodeRouteCapability();

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient sibling view at ENTRY (while mounted); the matrix below
    // is pure over the captured values.
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final parent = parentPath(args.nodePath);
    final gating = args.params['gating'] ?? '';
    final criticIds = (args.params['critics'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Read each lane's RAW grade once (null/empty ⇒ missing), then the
    // fail-closed grade used by the block rules (missing ⇒ F).
    final rawGrades = <String, String?>{
      for (final id in criticIds)
        id: siblings.resultOf('$parent/$id')['grade'],
    };
    final grades = <String, String>{
      for (final entry in rawGrades.entries)
        entry.key: _normalizeGrade(entry.value),
    };

    // 1. the gating lane failed (a non-zero Validation Plan / a structurally
    // broken spec, or a missing gating grade) — a hard block. The reason names
    // the gating LANE (this route serves both the code and the spec committee,
    // bead `pow-6ao`), so the parked gate says which gate fired.
    if (grades[gating] == 'F') {
      return Escalate('$gating failed: hard block');
    }

    // 2. a grade spread ≥ 3 letters across the PRESENT lanes — a human
    // ultimatum. Missing grades are IGNORED here (they are already caught by
    // the fail-closed gating/D-F block rules), so the spread reflects only the
    // grades the critics actually returned.
    final indices = [
      for (final entry in rawGrades.entries)
        if (entry.value != null && entry.value!.trim().isNotEmpty)
          _gradeIndex(_normalizeGrade(entry.value)),
    ];
    final spread = indices.isEmpty
        ? 0
        : indices.reduce(math.max) - indices.reduce(math.min);
    if (spread >= 3) return const Escalate('grade spread ≥ 3 — human ultimatum');

    // 3. any non-gating critic at D/F — rework → restForOne re-key is deferred
    // (build-order); a D/F parks at the bound handler for now.
    for (final entry in grades.entries) {
      if (entry.key == gating) continue;
      if (entry.value == 'D' || entry.value == 'F') {
        return const Escalate('a critic returned D/F — rework');
      }
    }

    // 4. all A–C, gating clean, spread < 3 — advance. The advance payload
    // carries the ROUTE PROVENANCE (FT-2): the per-lane grade vector it consumed
    // (CSV `lane=grade` in kCommitteeRubrics order), the computed spread, and the
    // matrix arm that fired (`all-approve`) — so the keep/kill export is
    // self-contained. Escalations keep their reason string (it names the rule).
    final gradesCsv = criticIds.map((id) => '$id=${grades[id]}').join(',');
    return Advance({
      'verdict': 'advance',
      'grades': gradesCsv,
      'spread': '$spread',
      'rule': 'all-approve',
    });
  }
}

/// The default code-committee critic-id index of [grade] (A=0 … F=5); a grade
/// outside `A..F` clamps to F (the fail-closed worst).
int _gradeIndex(String grade) {
  const ladder = ['A', 'B', 'C', 'D', 'E', 'F'];
  final i = ladder.indexOf(grade);
  return i < 0 ? ladder.length - 1 : i;
}

/// Normalizes a raw sibling grade to an upper-case letter, fail-closing a
/// null/empty grade to `F`.
String _normalizeGrade(String? grade) =>
    (grade == null || grade.trim().isEmpty) ? 'F' : grade.trim().toUpperCase();

/// The bead's OWN Validation Plan — the `validation_plan` metadata command. A
/// plan-less bead defaults to `false` (an explicit non-zero) so it grades F
/// rather than silently passing.
String _validationPlan(Bead bead) {
  final plan = bead.metadata['validation_plan'];
  if (plan is String && plan.trim().isNotEmpty) return plan.trim();
  return 'false';
}

/// The `sh -c` script the gating lane runs: ensure the critique dir, run the
/// plan in a subshell, and capture ITS exit code to the rc file `result()`
/// reads. The outer `sh` exits clean regardless, so the step always `complete`s
/// and the route is the single decision point.
String _gatingScript(String plan) =>
    'mkdir -p $_critiqueDir; ( $plan ) ; echo \$? > $_critiqueDir/$kGatingRubric.rc';

/// Renders the full work bead into a prompt block (title/description/design/
/// acceptance/notes) — the load-bearing review input.
String _beadBlock(Bead bead) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final b = StringBuffer()
    ..writeln()
    ..writeln('## The work bead')
    ..writeln('`${bead.id}` — $title');
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    b
      ..writeln()
      ..writeln('### $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  return b.toString();
}

/// The verdict's ROUND stamp as an int — `null` when the stamp is ABSENT or
/// unreadable. A JSON number and its string form both read (a critic that wrote
/// `"round":"2"` made a formatting slip, not a stale verdict); anything else is
/// a MISS, which fail-closes exactly like a foreign `nodePath` does.
int? _stampedRound(Object? raw) => switch (raw) {
  final num round => round.toInt(),
  final String round => int.tryParse(round.trim()),
  _ => null,
};

/// The verdict file's grade, when it parses AND is FRESH — `null` for an absent
/// file, invalid JSON, a missing/blank `grade`, a `nodePath` stamp that doesn't
/// match [expectedNodePath], OR a `round` stamp that doesn't match
/// [expectedRound]. The TWO stamps fence two DIFFERENT staleness modes and both
/// are load-bearing: `nodePath` rejects a verdict some OTHER node wrote (a stray
/// write, a mis-keyed lane — A4); `round` rejects a verdict THIS node wrote in
/// an EARLIER round (A15(5) alt-A — under `RouteVerdict.Rewind` the node path is
/// byte-identical round to round, so `nodePath` alone cannot see it). An absent
/// or unreadable round stamp is a MISS, not a pass. Every miss is treated as
/// "unparseable" so [CriticCapability.result] falls through to the stray /
/// RESULT TEXT / fail-closed chain (tg-291). Never throws.
Map<String, String>? _verdictFromFile(
  File verdict, {
  required String expectedNodePath,
  required int expectedRound,
}) {
  if (!verdict.existsSync()) return null;
  try {
    final json = jsonDecode(verdict.readAsStringSync()) as Map<String, dynamic>;
    final grade = (json['grade'] as String?)?.trim().toUpperCase();
    if (grade == null || grade.isEmpty) return null;
    final stampedNodePath = (json['nodePath'] as String?)?.trim();
    if (stampedNodePath != expectedNodePath) return null; // a FOREIGN node's.
    if (_stampedRound(json[kVerdictRoundKey]) != expectedRound) {
      return null; // a STALE round's — same node, earlier wave.
    }
    final rationale = (json['rationale'] as String?)?.trim() ?? '';
    return {
      'grade': grade,
      'transport': 'file',
      if (rationale.isNotEmpty) 'rationale': rationale,
    };
  } catch (_) {
    return null;
  }
}

/// A round-fresh verdict a critic wrote to a STRAY
/// `.../.grid/critique/<rubric>.json` somewhere OTHER than the canonical
/// workspace-root path — the read-side belt for gate-integrity #4 (bead
/// `tg-r66`). A critic that `cd`s mid-run (`test-coverage` cd's into a package
/// to run `dart test`) can resolve the verdict path against its current cwd and
/// write it under the package instead of at the worktree root (observed live:
/// `packages/grid_assets/.grid/critique/test-coverage.json`). [buildCriticPrompt]
/// now hands the critic the ABSOLUTE path so the write lands correctly, but this
/// belt recovers a verdict a critic still writes off-path some other way.
///
/// Walks [workspaceDir] for every `.grid/critique/<rubric>.json` and returns the
/// FIRST whose stamps match THIS node and THIS round — the `nodePath` + `round`
/// stamps (gate-integrity #3, A15(5) alt-A) are exactly what makes accepting an
/// off-path file safe: a stale or foreign stray can never match, so a leftover
/// from an earlier round is never misread as this round's verdict. The canonical
/// path is skipped (the caller already consulted it). `null` when no fresh stray
/// exists. Best-effort: never throws.
Map<String, String>? _strayVerdict(
  String workspaceDir,
  String rubric,
  String expectedNodePath,
  int expectedRound,
) {
  final canonical =
      p.canonicalize(p.join(workspaceDir, _critiqueDir, '$rubric.json'));
  for (final file in _strayVerdictFiles(workspaceDir, rubric)) {
    if (p.canonicalize(file.path) == canonical) continue; // the canonical path.
    final graded = _verdictFromFile(
      file,
      expectedNodePath: expectedNodePath,
      expectedRound: expectedRound,
    );
    if (graded != null) return {...graded, 'transport': 'file-stray'};
  }
  return null;
}

/// Every `.../.grid/critique/<rubric>.json` file under [root], found by a
/// bounded DFS that prunes VCS/build/dependency dirs (`.git`, `.dart_tool`,
/// `node_modules`, `build`) so the fallback walk stays cheap. Symlinks are not
/// followed. Best-effort: an unreadable directory is skipped, never thrown.
Iterable<File> _strayVerdictFiles(String root, String rubric) sync* {
  const prune = {'.git', '.dart_tool', 'node_modules', 'build'};
  final target = p.join(_critiqueDir, '$rubric.json'); // '.grid/critique/<r>.json'
  final stack = <Directory>[Directory(root)];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue; // unreadable — skip this subtree.
    }
    for (final entry in entries) {
      if (entry is Directory) {
        if (!prune.contains(p.basename(entry.path))) stack.add(entry);
      } else if (entry is File && _endsWithPath(entry.path, target)) {
        yield entry;
      }
    }
  }
}

/// Whether [path] ends with the relative [suffix] on a path-separator boundary
/// (so `.../pkg/.grid/critique/r.json` matches `.grid/critique/r.json`, but
/// `.../x.grid/critique/r.json` would not spuriously match `grid/critique/…`).
bool _endsWithPath(String path, String suffix) {
  if (!path.endsWith(suffix)) return false;
  if (path.length == suffix.length) return true;
  final boundary = path[path.length - suffix.length - 1];
  return boundary == p.separator || boundary == '/';
}

/// Recovers a verdict from a critic's raw harness RESULT TEXT (tg-291) — the
/// fallback transport [CriticCapability.result] consults when the verdict file
/// is absent or unparseable. FT-2 already captures the harness's
/// `--output-format json` result envelope for telemetry; its `result` field is
/// the critic's full stdout text, which sometimes carries the verdict the
/// critic forgot to also write to disk.
///
/// Recognizes, in order:
///  1. an embedded JSON verdict object (fenced or inline — `{"grade":...}`);
///  2. a `Verdict: <A-F>` OR `Grade: <A-F>` heading (markdown `##` and other
///     lead-ins allowed), with the prose that follows it as rationale — a
///     critic that summarizes with `## Grade: A` instead of `Verdict:` was
///     silently missed before (gate-integrity #4, bead `tg-r66`: the live
///     false gate whose stray file the belt above now also recovers).
///
/// Every recovered rationale is marked `[from result envelope]` so a grade
/// that rode this fallback is visibly distinguishable downstream. `null` when
/// neither shape yields a parseable grade (the caller then fail-closes to F).
Map<String, String>? _verdictFromResultText(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return _verdictFromEmbeddedJson(trimmed) ?? _verdictFromHeading(trimmed);
}

/// A single-letter A-F grade — the same strict shape [_verdictHeading]
/// enforces via its capture group. [buildCriticPrompt] hands the critic a
/// LITERAL `"grade":"<A-F>"` template; without this check, an echoed
/// template/example object in a stdout preamble would parse as a "valid"
/// verdict (tg-291 rework round 1). `grade` is already upper-cased by the
/// caller before this check runs.
final RegExp _validGradeLetter = RegExp(r'^[A-F]$');

/// Scans [text] for EVERY balanced-brace `{...}` substring that decodes as
/// JSON carrying a `grade` matching [_validGradeLetter] exactly, and returns
/// the LAST such match. A verdict concludes a critic's output — any earlier
/// object (an echoed prompt template, a worked example in prose) is a
/// preamble, not the verdict, so the first match must NOT win (tg-291 rework
/// round 1: a false ADVANCE was possible when a real F verdict followed an
/// earlier template/example echo with a matched-looking grade).
Map<String, String>? _verdictFromEmbeddedJson(String text) {
  Map<String, String>? last;
  for (var start = 0; start < text.length; start++) {
    if (text[start] != '{') continue;
    var depth = 0;
    for (var end = start; end < text.length; end++) {
      if (text[end] == '{') depth++;
      if (text[end] == '}') {
        depth--;
        if (depth != 0) continue;
        try {
          final json = jsonDecode(text.substring(start, end + 1));
          if (json is Map) {
            final grade = (json['grade'] as String?)?.trim().toUpperCase();
            if (grade != null && _validGradeLetter.hasMatch(grade)) {
              final rationale = (json['rationale'] as String?)?.trim() ?? '';
              last = {
                'grade': grade,
                'transport': 'envelope',
                'rationale': rationale.isEmpty
                    ? '[from result envelope]'
                    : '$rationale [from result envelope]',
              };
            }
          }
        } catch (_) {
          // not a decodable/relevant object at this start — keep scanning.
        }
        break; // matched braces exhausted for this start; try the next '{'.
      }
    }
  }
  return last;
}

/// A `Verdict: <A-F>` or `Grade: <A-F>` heading (case-insensitive) — the
/// prose-heading shapes a critic falls back to when it states its verdict in
/// plain text (tg-291), including the markdown `## Grade: A` summary a critic
/// was observed to emit while skipping the file write (gate-integrity #4,
/// bead `tg-r66`). The keyword is immediately followed by `:` (optional
/// whitespace only), so the `"grade":"A"` inside an echoed JSON template — where
/// a `"` sits between the word and the colon — never matches here (that shape is
/// already handled by [_verdictFromEmbeddedJson]).
final RegExp _verdictHeading =
    RegExp(r'(?:verdict|grade)\s*:\s*([A-Fa-f])\b', caseSensitive: false);

/// The prose that follows the LAST `Verdict:`/`Grade: <A-F>` heading in [text],
/// as a grade + marked rationale — `null` when no heading is present. A verdict
/// concludes a critic's output, so an earlier heading (a worked example, a
/// restated instruction) must not win over a later, real one — mirrors
/// [_verdictFromEmbeddedJson]'s last-match scan (tg-291 rework round 2: an
/// early "Verdict: A" followed by a real, later "Verdict: F" must yield F, not
/// the earlier A).
Map<String, String>? _verdictFromHeading(String text) {
  final matches = _verdictHeading.allMatches(text);
  if (matches.isEmpty) return null;
  final match = matches.last;
  final grade = match.group(1)!.toUpperCase();
  final rationale = text.substring(match.end).trim();
  return {
    'grade': grade,
    'transport': 'envelope',
    'rationale': rationale.isEmpty
        ? '[from result envelope]'
        : '$rationale [from result envelope]',
  };
}

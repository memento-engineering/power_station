/// The DELIVERY seam (M5 D-4a) — `deliver` replaces `land`.
///
/// Delivery is the ACTUATION of the ROOT circuit's terminal [Advance], not a step
/// and not a verdict: [DeliverRouteCapability] is that terminal route, and
/// A domain delivery method is the substation's bound [DeliveryMethod] the engine
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
/// This library SUPERSEDES the three `is`-detected `SourceControl` widenings and
/// the PR-opener enrichment seam that preceded it (the retirements are recorded,
/// with their governing amendments, in ADR-0000 A25). Each existed ONLY because
/// the ENGINE's `SourceControl` could not carry the verb, and M5 D-4a stripped
/// those verbs off the interface entirely. Git ownership is now UNCONDITIONAL
/// here, not opt-in-detected — a bare source-control fake can no longer skip the
/// committed-the-WHOLE-tree guarantee.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import 'describe_manifest.dart';
import 'pr_composition.dart';
import 'pr_describe.dart';
import 'route_failure.dart';

/// The ROOT circuit's terminal step id — the ONE node whose advance delivers.
const String kDeliverStep = 'deliver';

/// The workspace-relative path the terminal route writes the composed PR body to,
/// and the bound delivery method reads it back from. A worktree ledger, exactly like the
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
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();

    // Commit-only: no method bound, or no workspace to deliver FROM. The engine
    // completes the terminal node and delivers nothing.
    if (services.delivery == null || workspace == null) return const Advance();

    // The observer-written receipts, read at ENTRY from the SESSION-WIDE
    // sibling view: the SAME values the PR body's receipt sections render, so
    // the manifest and the body can never tell a reader different stories.
    final validation = siblings.resultOf('${args.beadId}/land/revalidate');
    final review = siblings.resultOf('${args.beadId}/review/route');

    // THE DESCRIBE PASS: one cheap inference call over a BOUNDED MANIFEST of
    // the branch's facts. Fail-safe by construction — every failure path yields
    // the deterministic, id-free fallback subject.
    final described = await describeBranch(
      bead: bead,
      beadId: args.beadId,
      nodePath: args.nodePath,
      workspace: workspace,
      composition: composition,
      ambient: agentConfig,
      registry: harnesses,
      receipts: [
        DescribeReceipt(
          label: 'validation',
          nodePath: '${args.beadId}/land/revalidate',
          result: validation,
        ),
        DescribeReceipt(
          label: 'committee',
          nodePath: '${args.beadId}/review/route',
          result: review,
        ),
      ],
      git: _gitRunner,
      inference: _inference,
      flare: services.transport?.flare,
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
      // The describe call's FT-2 usage FIRST, so the route's own keys always
      // win a collision: telemetry can never rewrite a verdict.
      ...described.usage,
      'verdict': 'deliver',
      'pr_title': title,
      'title_source': described.source,
      'validation_rc': validation['rc'] ?? '0',
      'committee_grades': review['grades'] ?? '',
    });
  }
}

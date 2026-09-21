/// The PRE-STAMP ADVISORY — the spec-review readiness lens and the discovery
/// evidence gather, run by the FILING VERBS against the filing as it will be
/// mounted, BEFORE the approval stamp.
///
/// **The gap.** Measured 2026-09-15 over lunar epoch 85: of 36 mounts, ~17 hit
/// a spec-readiness hold or a discovery hold at `spec_review` before any
/// specify agent ran — stale line citations, phantom decision tokens in prose,
/// undecided forks, unacknowledged departures, a clipped decision entry. Every
/// one of those cost a mint, a discovery gather, a lens run, a gate, an
/// operator cure round at full context, a rework and a re-mint. The lenses were
/// RIGHT every time; they simply ran at the most expensive point in the
/// circuit. Running the SAME judgement at the stamp moves each of those cures
/// into the refiner's interview, where the bead text is already open.
///
/// **It is a new CALL SITE, not a new predicate.** The readiness half is the
/// shipped [intakeFindings] plus the shipped [ReadinessCriticCapability] lens
/// prompt, decided by the shipped [decideReadiness]. The discovery half is the
/// shipped [gatherDiscoveryAnchors] plus the shipped three-lens fan-out,
/// decided by the shipped [decideDiscovery]. Nothing here mints a fourth
/// completeness predicate, and nothing here re-derives a bound — which is what
/// `power_station#the-refiner-exit-oracle-is-the-filing-verb` permits and what
/// `power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`
/// requires.
///
/// **It publishes NOTHING.** Every lens rides [LensInProcessTransport]: no
/// critique file, no discovery report, no dossier, no session, no round, no
/// node path, no usage capture. The verdict is returned in-process and rendered
/// by the verb. That is what keeps
/// `power_station#readiness-route-joins-on-a-published-verdict-never-on-absence`
/// untouched — a spec-review route still joins only on its own published
/// verdict, and an advisory run can neither satisfy nor collide with it.
///
/// **It runs LAST before the stamp, and never before the mechanical rows.**
/// `memento-engineering#approval-is-stamped-last-and-an-agent-stamps-its-own-bugs`
/// fixes the order: file unapproved → dedupe → wire deps → every
/// [FilingRequirement] row → THIS advisory → stamp. The mechanical rows are
/// FREE and they already refuse a phantom canonical citation, an unparseable
/// plan, an absolute path and a NUL byte; spending inference to re-discover
/// any of those would be the waste this advisory exists to remove. A failing row refuses on its own, and
/// the advisory never runs to mask it.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../agent/agent_harness.dart'
    show AgentConfig, buildBuiltinEnvironmentRegistry;
import '../agent/environment_registry.dart';
import '../agent/site_binding.dart';
import '../assets/asset_loader.dart' show PackagedAssetLoader;
import '../assets/overlay_materializer.dart' show kDefaultOverlayRunner;
import '../code/committee.dart'
    show LensInProcessTransport, RubricSource, verdictFromResultText;
import '../code/discovery.dart';
import '../code/pr_describe.dart' show InferenceRunner, SystemInferenceRunner;
import '../code/readiness.dart';
import '../code/specify.dart' show kSpecCommitteeRubrics;

/// WHETHER a filing evaluation runs the pre-stamp advisory.
///
/// Three arms, because "do not run it" and "run it and record that it was
/// waived" are different facts about a stamp and must not share a spelling.
enum FilingAdvisoryMode {
  /// Do not run it, and say nothing about it. The default for every
  /// non-verb consumer — the mount explainer, the reconciler's eligibility
  /// read, an internal completeness check — none of which is a stamp moment
  /// and none of which should spend inference.
  off,

  /// Run it. The `filing` and `approve` verbs' default.
  run,

  /// Skip it DELIBERATELY, and record the waiver on the stamp
  /// ([kApprovedAdvisoryKey], [kReadinessSkippedKey]). The rare mount-anyway.
  skip,
}

/// What the advisory concluded. Sealed: consumed with an exhaustive `switch`.
sealed class FilingAdvisoryVerdict {
  /// Creates a verdict.
  const FilingAdvisoryVerdict();

  /// Whether the stamp may proceed.
  bool get passed;

  /// Structured command/UI representation.
  Map<String, Object?> toJson();
}

/// The lenses PASSED — the readiness lens graded [readinessGrade] (`A`–`C`) and
/// the discovery matrix advanced.
final class FilingAdvisoryPassed extends FilingAdvisoryVerdict {
  /// Creates the passing verdict over the lens's own letter.
  const FilingAdvisoryPassed({required this.readinessGrade});

  /// The `bead-readiness` lens's letter — recorded on the stamp as
  /// [kReadinessGradeKey], so a receipt says what was judged and how well.
  final String readinessGrade;

  @override
  bool get passed => true;

  @override
  Map<String, Object?> toJson() => {
    'outcome': 'passed',
    'readiness_grade': readinessGrade,
  };
}

/// A lens REFUSED — [reason] is that lens's OWN fix text, verbatim.
///
/// Verbatim is the whole point: the refiner reads the identical hold a
/// `spec_review` gate would have parked with, at the moment the bead text is
/// open, instead of an operator reading it a round later out of a gate bead.
final class FilingAdvisoryRefused extends FilingAdvisoryVerdict {
  /// Creates the refusal.
  const FilingAdvisoryRefused({required this.rule, required this.reason});

  /// The arm that fired: `intake`, `readiness`, `discovery`,
  /// `discovery-evidence`, or `transport` for a lens that did not complete.
  final String rule;

  /// The owning lens's fix text, byte-for-byte.
  final String reason;

  @override
  bool get passed => false;

  @override
  Map<String, Object?> toJson() => {
    'outcome': 'refused',
    'rule': rule,
    'reason': reason,
  };
}

/// The advisory was WAIVED — [FilingAdvisoryMode.skip]. No inference ran, and
/// nothing was judged.
final class FilingAdvisorySkipped extends FilingAdvisoryVerdict {
  /// Creates the waiver.
  const FilingAdvisorySkipped();

  @override
  bool get passed => true;

  @override
  Map<String, Object?> toJson() => const {'outcome': 'skipped'};
}

/// The injectable advisory seam (Fakes, not mocks — the offline suite always
/// injects). One method, no mutation surface: an advisory READS a bead and
/// answers about it.
abstract interface class FilingAdvisory {
  /// Judges [bead], which was read out of the store at [storeRoot].
  ///
  /// Receives the EXACT bead the filing rows were evaluated over, never a
  /// second read: an advisory judging a different revision than the one about
  /// to be stamped would be a receipt for something nobody checked.
  Future<FilingAdvisoryVerdict> evaluate({
    required String storeRoot,
    required Bead bead,
  });
}

/// The bead-under-advisory's inert workspace branch fields.
///
/// A pre-stamp run has no worktree and no branch: the store root IS the
/// checkout, and nothing on this path reads [Workspace.branch] or
/// [Workspace.baseBranch] — only [Workspace.workspaceDir], which becomes the
/// spawned lens's working directory. The value is named rather than blank so a
/// reader of a spawn's `workDir` can tell a pre-stamp run from a session one.
const String kPreStampAdvisoryBranch = 'pre-stamp-advisory';

/// The node path a pre-stamp lens prompt is stamped with.
///
/// There is no node. The stamps ride the prompt because they are part of the
/// SHARED prompt body — dropping them would fork the text this advisory exists
/// to keep identical — and this value is deliberately not a session node path,
/// so a report carrying it could never clear a real route's freshness fence
/// even if one somehow reached disk.
const String kPreStampAdvisoryNodePath = 'pre-stamp-advisory';

/// The session id a pre-stamp lens prompt is stamped with — see
/// [kPreStampAdvisoryNodePath]; there is no session either.
const String kPreStampAdvisorySessionId = 'pre-stamp-advisory';

/// The round a pre-stamp run gathers and judges its FIRST pass at.
const int kPreStampAdvisoryRound = 0;

/// The LIVE [FilingAdvisory]: the shipped readiness lens, then the shipped
/// discovery gather and its three lenses, decided by the shipped matrices.
///
/// ORCHESTRATION ONLY. Every judgement below belongs to a function this class
/// calls and does not own — [intakeFindings], [decideReadiness],
/// [gatherDiscoveryAnchors], [decideDiscovery] — and every refusal carries that
/// function's own text. The only thing this class decides is the ORDER: cheap
/// deterministic checks first, then one mid-tier lens, then three cheap lenses,
/// and stop at the first refusal.
///
/// Config is VALUES and impls are DI throughout: the seams default to the live
/// compositions ([SystemInferenceRunner], the built-in environment registry,
/// the packaged rubrics, the on-disk anchor resolver) and a test injects Fakes
/// so the offline suite spawns nothing.
final class PreStampAdvisory implements FilingAdvisory {
  /// Composes the advisory over its seams.
  ///
  /// [inference] is the ONE process seam; with it unwired nothing spawns.
  /// [decisions] is the SAME roster-mode `DecisionIndexSource` the filing
  /// evidence gather runs, so the two halves of one verb ask the register one
  /// way. [priorArt] is null by default — no station search is composed here
  /// and the gather records that as unavailable rather than as "no hits".
  PreStampAdvisory({
    InferenceRunner? inference,
    AgentConfig? ambient,
    EnvironmentRegistry? registry,
    SiteBinding siteBinding = SiteBinding.none,
    RubricSource? rubrics,
    List<String> rubricIds = kSpecCommitteeRubrics,
    AnchorResolver? anchorResolver,
    PriorArtSource? priorArt,
    DecisionIndexSource? decisions,
    HistorySource? history,
    GitRunner? git,
    String decisionRunner = kDefaultOverlayRunner,
    String? decisionGridHome,
    String substation = '',
  }) : _inference = inference ?? const SystemInferenceRunner(),
       _ambient = ambient ?? const AgentConfig(),
       _registry = registry ?? buildBuiltinEnvironmentRegistry(),
       _siteBinding = siteBinding,
       _rubrics = rubrics ?? PackagedAssetLoader().rubricSource,
       _rubricIds = rubricIds,
       _anchorResolver = anchorResolver,
       _priorArt = priorArt,
       _decisions = decisions,
       _history = history ?? gitHistorySource(git ?? SystemGitRunner()),
       _decisionRunner = decisionRunner,
       _decisionGridHome = decisionGridHome,
       _substation = substation;

  final InferenceRunner _inference;
  final AgentConfig _ambient;
  final EnvironmentRegistry _registry;
  final SiteBinding _siteBinding;
  final RubricSource _rubrics;
  final List<String> _rubricIds;
  final AnchorResolver? _anchorResolver;
  final PriorArtSource? _priorArt;
  final DecisionIndexSource? _decisions;
  final HistorySource _history;
  final String _decisionRunner;
  final String? _decisionGridHome;
  final String _substation;

  @override
  Future<FilingAdvisoryVerdict> evaluate({
    required String storeRoot,
    required Bead bead,
  }) async {
    // TIER 1 — the deterministic intake contract, ZERO agents. A bead that
    // cannot reach the readiness lane in the circuit does not reach it here.
    final findings = intakeFindings(bead);
    if (findings.isNotEmpty) {
      return FilingAdvisoryRefused(
        rule: 'intake',
        reason: renderIntakeHold(bead, findings),
      );
    }

    final workspace = Workspace(
      workspaceDir: storeRoot,
      branch: kPreStampAdvisoryBranch,
      baseBranch: kPreStampAdvisoryBranch,
    );

    // TIER 2 — the `bead-readiness` judgement, ONE mid-tier lens.
    final readiness = await _readiness(bead: bead, workspace: workspace);
    final String grade;
    switch (readiness) {
      case FilingAdvisoryRefused():
        return readiness;
      case FilingAdvisoryPassed(:final readinessGrade):
        grade = readinessGrade;
      case FilingAdvisorySkipped():
        // GUARD (the named invariant: only the VERB waives, never a lens).
        // Named rather than defaulted, and LOUD rather than passed through: a
        // waiver arriving from here would stamp a bead nothing judged while
        // recording that a lens had run.
        throw StateError(
          'pre-stamp advisory: the readiness half returned a WAIVER, which '
          'only the verb may produce — a lens cannot waive itself',
        );
    }

    // TIER 3 — the discovery gather + its three cheap lenses, re-gathered once
    // exactly as the circuit's own route re-gathers.
    final discovery = await _discovery(
      bead: bead,
      workspace: workspace,
      storeRoot: storeRoot,
    );
    return discovery ?? FilingAdvisoryPassed(readinessGrade: grade);
  }

  /// The readiness half: one lens, the shared prompt, the shared decoder, the
  /// shared matrix.
  ///
  /// A lens that did NOT complete, or completed and published nothing this
  /// decoder can read, refuses LOUDLY under the `transport` rule. It is never
  /// converted into a bead hold (the bead was not judged) and never into a free
  /// pass (nothing said it was ready) — the same three-state discipline
  /// `readiness-route-joins-on-a-published-verdict-never-on-absence` fixed for
  /// the route, held on a call site that has no lane to wait for.
  Future<FilingAdvisoryVerdict> _readiness({
    required Bead bead,
    required Workspace workspace,
  }) async {
    final run = await _inference.run(
      readinessLensRuntimeConfig(
        bead: bead,
        workspace: workspace,
        rubric: kReadinessRubric,
        nodePath: kPreStampAdvisoryNodePath,
        round: kPreStampAdvisoryRound,
        transport: const LensInProcessTransport(),
        ambient: _ambient,
        registry: _registry,
        siteBinding: _siteBinding,
        rubrics: _rubrics,
        decisionRunner: _decisionRunner,
        decisionGridHome: _decisionGridHome,
      ),
    );
    if (!run.ok) {
      return const FilingAdvisoryRefused(
        rule: 'transport',
        reason:
            'PRE-STAMP ADVISORY FAILED — the `$kReadinessRubric` lens did not '
            'complete, so this bead was NOT judged. That is a defect in the '
            'advisory run, not a verdict about the filing: refusing LOUDLY '
            'rather than stamping over a lens nobody heard from. Re-run '
            'approve, or waive the advisory with --readiness=skip and own the '
            'waiver on the receipt.',
      );
    }
    final candidate = verdictFromResultText(run.output);
    final verdict = decideReadiness(
      grade: candidate?['grade'],
      rationale: candidate?['rationale'] ?? '',
    );
    return switch (verdict) {
      ReadinessDrive(:final grade) => FilingAdvisoryPassed(
        readinessGrade: grade,
      ),
      ReadinessHold(:final reason) => FilingAdvisoryRefused(
        rule: 'readiness',
        reason: reason,
      ),
      ReadinessAbsent() => const FilingAdvisoryRefused(
        rule: 'transport',
        reason:
            'PRE-STAMP ADVISORY FAILED — the `$kReadinessRubric` lens ran to '
            'completion and returned no readable grade, so this bead was NOT '
            'judged. A completed lens that published nothing is a broken run, '
            'not a hold: refusing LOUDLY rather than reading silence as either '
            'verdict. Re-run approve, or waive the advisory with '
            '--readiness=skip and own the waiver on the receipt.',
      ),
    };
  }

  /// The discovery half: the deterministic gather, three cheap lenses in
  /// parallel, the shared matrix — and ONE re-gather, the circuit's own bound.
  ///
  /// Returns null when the matrix ADVANCED; a refusal otherwise. A lens whose
  /// reply carries no readable report is handed to [decideDiscovery] as a
  /// MISSING lane, exactly as the route hands it an absent artifact: the gate
  /// never fires on absence, the whole gather re-runs once, and at the cap the
  /// miss rides the verdict rather than holding the bead.
  Future<FilingAdvisoryVerdict?> _discovery({
    required Bead bead,
    required Workspace workspace,
    required String storeRoot,
  }) async {
    for (var round = 0; ; round++) {
      final anchors = await gatherDiscoveryAnchors(
        bead: bead,
        workspaceDir: storeRoot,
        round: round,
        substation: _substation,
        live: Directory(storeRoot).existsSync(),
        rubricIds: _rubricIds,
        rubrics: _rubrics,
        resolver: _anchorResolver,
        priorArt: _priorArt,
        decisions: _decisions,
        history: _history,
      );
      // `gatherDiscoveryAnchors` answers null only for a cancellation, and this
      // call site passes no cancel predicate.
      if (anchors == null) {
        throw StateError(
          'pre-stamp advisory: the deterministic gather unwound without a '
          'cancel predicate — that is a defect in the gather, not a verdict',
        );
      }
      final lanes = <String, DiscoveryLensOutcome?>{};
      final replies = await Future.wait([
        for (final lens in kDiscoveryLenses)
          _inference
              .run(
                discoveryLensRuntimeConfig(
                  bead: bead,
                  workspace: workspace,
                  lens: lens,
                  sessionId: kPreStampAdvisorySessionId,
                  nodePath: kPreStampAdvisoryNodePath,
                  round: round,
                  anchors: anchors,
                  transport: const LensInProcessTransport(),
                  ambient: _ambient,
                  registry: _registry,
                  siteBinding: _siteBinding,
                ),
              )
              .then(
                (result) => (
                  lens: lens,
                  outcome: result.ok
                      ? discoveryLensOutcomeFromResultText(
                          result.output,
                          lens: lens,
                        )
                      : null,
                ),
              ),
      ]);
      for (final reply in replies) {
        lanes[reply.lens] = reply.outcome;
      }

      final verdict = decideDiscovery(
        lanes: lanes,
        anchors: anchors,
        workBead: bead,
        priorRound: round,
      );
      switch (verdict) {
        case DiscoveryAdvance():
          return null;
        case DiscoveryHold(:final reason):
          return FilingAdvisoryRefused(rule: 'discovery', reason: reason);
        case DiscoveryEvidenceHold(:final reason):
          return FilingAdvisoryRefused(
            rule: 'discovery-evidence',
            reason: reason,
          );
        case DiscoveryRegather():
          // The matrix only returns this arm BELOW `kMaxRegatherRounds`, so the
          // loop is bounded by the same constant the circuit's route is.
          continue;
      }
    }
  }
}

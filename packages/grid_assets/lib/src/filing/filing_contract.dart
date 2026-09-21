import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:crypto/crypto.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;

import '../code/discovery.dart'
    show
        DecisionEntryEvidence,
        DecisionGatherEvidence,
        DecisionIndexSource,
        EvidenceState;
import '../search/station_search.dart';
import 'approval_stamp.dart';
import 'filing_text.dart';

/// The eleven mechanical checks reported for a newly filed bead.
///
/// The first four are PRESENCE: is the field there at all. The six after them
/// are VIABILITY: can what the field holds actually work. The last is CONTENT:
/// does the text itself survive being written and read back. A bead used to
/// pass filing with a validation plan the gating lane cannot parse, an
/// absolute path that turns the anchor extractor's receipt into a FAILED
/// record, an id nobody minted, an acceptance version that goes stale on the
/// next release wave, a citation of a decision the round itself creates, or a
/// code unit that corrupts the bead at exec time. Each of those cost a round,
/// and each was carried afterwards as a REMEMBERED rule — a rule that binds
/// only the agent who reads it, and the agents most likely to skip it are the
/// ones under the most context pressure. A rule a machine can enforce belongs
/// in the machine — the ruling bead `org-gze` carries, which is what this enum
/// is the machine half of.
///
/// The order is STABLE and the wire names are the contract: skills, UIs and
/// the approval preflight all read rows by [wire], in
/// [FilingRequirement.values] order.
enum FilingRequirement {
  driveableType('driveable_type'),
  validationPlan('validation_plan'),
  acceptanceCriteria('acceptance_criteria'),
  dependencies('dependencies'),
  validationPlanSyntax('validation_plan_syntax'),
  validationPlanPortability('validation_plan_portability'),
  repoRelativePaths('repo_relative_paths'),
  beadReferences('bead_references'),
  releaseVersions('release_versions'),
  decisionReferences('decision_references'),
  noCorruptingText('no_corrupting_text');

  const FilingRequirement(this.wire);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;
}

/// One deterministic filing requirement result.
final class FilingRequirementRow {
  /// Creates one result row.
  const FilingRequirementRow({
    required this.requirement,
    required this.passed,
    required this.detail,
  });

  /// Requirement evaluated by this row.
  final FilingRequirement requirement;

  /// Whether the filed bead satisfies the requirement.
  final bool passed;

  /// Human-readable evidence or correction.
  final String detail;

  /// Structured command/UI representation.
  Map<String, Object> toJson() => {
    'requirement': requirement.wire,
    'passed': passed,
    'detail': detail,
  };
}

/// The complete filing report for one bead id.
final class FilingReport {
  /// Creates a report.
  const FilingReport({
    required this.beadId,
    required this.requirements,
    this.approvalRevision = '',
    this.error,
  });

  /// Creates the loud unknown-id report with no passing rows.
  factory FilingReport.missing(String beadId) => FilingReport(
    beadId: beadId,
    requirements: const <FilingRequirementRow>[],
    error: 'bead not found',
  );

  /// Bead id checked.
  final String beadId;

  /// Eleven rows for a found bead, in [FilingRequirement.values] order.
  final List<FilingRequirementRow> requirements;

  /// The revision this filing WOULD be approved against — the deterministic
  /// digest of the bead CONTENT the rows are evaluated over. Empty for a report
  /// with no bead to evaluate.
  ///
  /// [FilingEvidence] is deliberately NOT in it: a parse outcome, an id catalog
  /// and the roster's posture are all facts about the WORLD, not about the
  /// bead, and a receipt must not be revoked by a store nobody edited.
  ///
  /// This is what `ApproveService` stamps as `grid.approved_rev`. The mount
  /// gate does not compare it against the stamped one (see
  /// `mountEligibilityFindings`); what that gate reads off the receipt is its
  /// SCHEME VERSION, which tells a receipt minted under the current basis from
  /// one minted under a retired, unreproducible one.
  final String approvalRevision;

  /// Lookup-level refusal; non-null reports never pass.
  final String? error;

  /// True only for a found bead with exactly eleven passing rows.
  bool get passed =>
      error == null &&
      requirements.length == FilingRequirement.values.length &&
      requirements.every((row) => row.passed);

  /// Structured command/UI representation.
  Map<String, Object> toJson() => {
    'id': beadId,
    'passed': passed,
    'approval_revision': approvalRevision,
    'requirements': [for (final row in requirements) row.toJson()],
    if (error case final error?) 'error': error,
  };
}

/// What the station ROSTER said about one `external:` row's project.
enum ExternalResolution {
  /// The roster arms a substation of that name — the row is an ordinary
  /// prerequisite and the dependencies requirement passes on it.
  armed,

  /// The roster was consulted and arms NO substation of that name. An edge
  /// naming a store this station does not arm is never a silent pass.
  notArmed,

  /// The roster was NOT consulted, so nothing can be said about the project.
  /// Fail-closed, exactly as [notArmed] is: an unasked roster cannot clear a
  /// cross-project blocker.
  unconsulted,
}

/// One `external:<project>:<capability>` dependency row, with what the roster
/// said about its project.
final class ExternalBlocker {
  /// Binds [ref] to its [resolution].
  const ExternalBlocker({required this.ref, required this.resolution});

  /// The parsed row — bd's OWN type
  /// ([ExternalDepRef], `beads_dart`), never a second spelling of it.
  final ExternalDepRef ref;

  /// The roster's answer about [ExternalDepRef.project].
  final ExternalResolution resolution;

  /// Whether this row clears the dependencies requirement.
  bool get passed => switch (resolution) {
    ExternalResolution.armed => true,
    ExternalResolution.notArmed || ExternalResolution.unconsulted => false,
  };
}

/// The dependencies requirement's whole content: the PROJECTION of the
/// dependency rows bd holds for one bead.
///
/// `power_station#the-dependencies-row-is-a-projection-of-bd-dependency-rows`
/// — ruled by Nico on 2026-09-13 under
/// `the_grid#the-grid-is-a-beads-controller`: a blocker is a declaration bd
/// holds, and bd's rows are the single typed view of it. Bead PROSE is never
/// read for blockers; a `Blocked by` sentence is prose, and the hyphenated
/// spelling is the same prose. There is nothing to compare the rows AGAINST,
/// so the row reports what bd holds and refuses only what the roster cannot
/// resolve.
final class DependencyProjection {
  /// Creates a projection over already-classified rows.
  const DependencyProjection({
    required this.local,
    required this.external,
    required this.armedSubstations,
  });

  /// Projects [beadId]'s own outgoing BLOCKING rows out of [dependencies].
  ///
  /// [armedSubstations] is the station's roster by NAME, or null when no
  /// roster was supplied — the [ExternalResolution.unconsulted] arm.
  factory DependencyProjection.of({
    required String beadId,
    required Iterable<BeadDependency> dependencies,
    required Set<String>? armedSubstations,
  }) {
    final local = <String>{};
    final external = <String, ExternalBlocker>{};
    for (final edge in dependencies) {
      if (edge.issueId != beadId || edge.type != DependencyType.blocks) {
        continue;
      }
      // bd's own parser decides what an `external:` target is. A malformed
      // spelling parses to null and is read as a LOCAL id — exactly what bd
      // does with it, so the projection never invents a third reading.
      final ref = ExternalDepRef.parse(edge.dependsOnId);
      if (ref == null) {
        local.add(edge.dependsOnId);
        continue;
      }
      external[ref.wire] = ExternalBlocker(
        ref: ref,
        resolution: armedSubstations == null
            ? ExternalResolution.unconsulted
            : armedSubstations.contains(ref.project)
            ? ExternalResolution.armed
            : ExternalResolution.notArmed,
      );
    }
    return DependencyProjection(
      local: local.toList()..sort(),
      external: (external.keys.toList()..sort())
          .map((wire) => external[wire]!)
          .toList(growable: false),
      armedSubstations: armedSubstations,
    );
  }

  /// The same-store blocking targets, sorted. bd's own `bd ready` business —
  /// the projection reports them and judges nothing about them.
  final List<String> local;

  /// The `external:` blocking rows, sorted by wire form, each carrying its
  /// roster resolution.
  final List<ExternalBlocker> external;

  /// The roster the external rows were resolved against, or null when none
  /// was supplied.
  final Set<String>? armedSubstations;

  /// True unless an external row named a project the roster cannot resolve.
  bool get passed => external.every((blocker) => blocker.passed);

  /// The armed roster as an operator reads it.
  String get _armedRoster {
    final armed = armedSubstations;
    if (armed == null) return '<not consulted>';
    if (armed.isEmpty) return '<none>';
    return (armed.toList()..sort()).join(', ');
  }

  /// The evidence line: what bd holds, and — when it refuses — which row the
  /// roster could not resolve and what to do about it.
  String get detail {
    final refusals = [
      for (final blocker in external)
        if (!blocker.passed)
          switch (blocker.resolution) {
            ExternalResolution.notArmed =>
              '${blocker.ref.wire} names "${blocker.ref.project}", which this '
                  'station does not arm (armed: $_armedRoster) — arm that '
                  'substation, or re-point the row at one the roster carries',
            ExternalResolution.unconsulted =>
              '${blocker.ref.wire} is unresolved: no station roster was '
                  'supplied, so "${blocker.ref.project}" cannot be resolved to '
                  'an armed substation — the composition that builds this verb '
                  'passes its armed roster in as armedSubstations, and until '
                  'one does every external: row refuses here',
            ExternalResolution.armed => '',
          },
    ];
    if (refusals.isNotEmpty) {
      return 'unresolvable external dependency rows: ${refusals.join('; ')}';
    }
    final rows = [
      ...local,
      for (final blocker in external) '${blocker.ref.wire} (armed)',
    ];
    return rows.isEmpty
        ? 'bd holds no blocking dependency rows'
        : 'bd dependency rows: ${rows.join(', ')}';
  }

  /// The approval-revision basis: the ROWS bd holds, never the roster's answer
  /// about them.
  ///
  /// The roster is the STATION's posture, not the bead's content — the same
  /// reason the basis has always recorded the proofs FOUND rather than the
  /// posture of the lookup. Arming a substation must not revoke a governor's
  /// approval of a bead nobody edited.
  List<Map<String, Object?>> get basis => [
    for (final id in local) {'id': id, 'kind': 'local'},
    for (final blocker in external)
      {'id': blocker.ref.wire, 'kind': 'external'},
  ];
}

/// The approval revision of one evaluated filing, under the CURRENT scheme
/// version ([kFilingApprovalRevisionPrefix]).
///
/// It digests exactly what an approval is a judgement ABOUT: the bead's work
/// fields, its validation plan, and the DEPENDENCY ROWS bd holds for it
/// ([DependencyProjection.basis]). Lifecycle timestamps, status,
/// assignee/owner, result metadata and the receipt itself are all EXCLUDED, so
/// stamping the receipt can never invalidate the receipt it stamps, and a bead
/// moving through its lifecycle does not revoke a governor's approval of its
/// content. The station's ROSTER is excluded for the same reason: arming a
/// substation is the station's posture, not the bead's content.
///
/// The basis has NO link-proof member. The retired one recorded that a
/// cross-store link bead had been FOUND for each declared id; the hard cut
/// that retired cross-store link beads made it permanently false, so no
/// evaluation could ever reproduce a receipt carrying it. It is replaced —
/// not pinned, and not dropped in place — by the rows bd itself holds, typed
/// `local` or `external`, which is the one surface a cross-project blocker
/// still lives on.
///
/// That replacement is a new receipt SCHEME, so the version in
/// [kFilingApprovalRevisionPrefix] moved with it and every receipt minted
/// under the retired one reads as stale EXACTLY ONCE
/// ([isStaleFilingApprovalStamp]). There is no dual-basis compatibility path:
/// this function is the only thing that mints a revision, and it mints one
/// version.
String _approvalRevisionOf(Bead bead, DependencyProjection dependencies) {
  final plan = bead.metadata['validation_plan'];
  final basis = <String, Object?>{
    'id': bead.id,
    'title': bead.title,
    'description': bead.description,
    'design': bead.design,
    'acceptanceCriteria': bead.acceptanceCriteria,
    'notes': bead.notes,
    'specId': bead.specId,
    'issueType': bead.issueType.wire,
    'priority': bead.priority,
    'validationPlan': plan is String ? plan : null,
    'dependencies': dependencies.basis,
  };
  final digest = sha256.convert(utf8.encode(jsonEncode(basis)));
  return '$kFilingApprovalRevisionPrefix$digest';
}

/// The shell the GATING lane actually invokes the validation plan with
/// (`sh -c '( … )'`). `SpecifyCapability` parses against the same one, so the
/// two verbs cannot disagree about what "parses" means.
const String kFilingLaneShell = 'sh';

/// The PORTABILITY shell. `sh` is bash 3.2 on a developer's mac and dash on
/// CI, and a Bash-only construct dies under dash at PARSE — no log, no return
/// code, surfacing as a harness throttle rather than as a bad plan. Parsing
/// against dash here is what turns that into a legible refusal at filing time.
const String kFilingPortabilityShell = 'dash';

/// ONE shell's answer about whether a validation plan PARSES.
final class ValidationPlanParseResult {
  /// Records [shell]'s [exitCode] and its own first word on why.
  const ValidationPlanParseResult({
    required this.shell,
    required this.exitCode,
    this.diagnostic = '',
  });

  /// The shell that was asked.
  final String shell;

  /// Its exit code. Zero is a parse; anything else is a refusal.
  final int exitCode;

  /// The shell's OWN first line of complaint — the text an author can act on.
  final String diagnostic;

  /// Whether [shell] parsed the plan.
  bool get parsed => exitCode == 0;
}

/// The injectable PARSE seam — it never EXECUTES the plan.
///
/// One seam, two consumers: the filing contract's two plan rows and
/// `SpecifyCapability`'s authored-plan floor. Tests implement a Fake (never a
/// mock) so the offline suite spawns no shell at all.
abstract interface class ValidationPlanProbe {
  /// Asks [shell] whether [plan] parses, from [workingDirectory].
  Future<ValidationPlanParseResult> parse({
    required String shell,
    required String plan,
    required String workingDirectory,
  });
}

/// The named refusal for a parse shell that is NOT INSTALLED — distinct from a
/// shell that ran and crashed, because only one of those says anything about
/// the plan.
final class ValidationPlanShellMissing implements Exception {
  /// Names the shell that could not be started.
  const ValidationPlanShellMissing(this.shell, this.cause);

  /// The executable that is absent.
  final String shell;

  /// The spawn failure underneath.
  final Object cause;

  @override
  String toString() => '$shell is not installed on this machine ($cause)';
}

/// The real [ValidationPlanProbe]: `<shell> -n -c '( <plan> )'`.
///
/// `-n` parses and NEVER executes, and the plan is wrapped in the exact group
/// the gating lane wraps it in, so what is checked is what will run.
final class SystemValidationPlanProbe implements ValidationPlanProbe {
  /// Creates the stateless probe.
  const SystemValidationPlanProbe();

  @override
  Future<ValidationPlanParseResult> parse({
    required String shell,
    required String plan,
    required String workingDirectory,
  }) async {
    final ProcessResult run;
    try {
      run = await Process.run(shell, [
        '-n',
        '-c',
        '( ${plan.trim()} )',
      ], workingDirectory: workingDirectory);
    } on ProcessException catch (error) {
      // ENOENT on the EXECUTABLE, not on the plan: tell the caller which it
      // was, because a shell nobody installed says nothing about the bead.
      //
      // ENOENT is AMBIGUOUS, though — a working directory that does not exist
      // raises the same errno — so the shell is only blamed when the directory
      // it was to run in is really there. A refusal that named the wrong one
      // would send an operator off to install a shell they already have.
      if (error.errorCode == 2 && Directory(workingDirectory).existsSync()) {
        throw ValidationPlanShellMissing(shell, error);
      }
      rethrow;
    }
    return ValidationPlanParseResult(
      shell: shell,
      exitCode: run.exitCode,
      diagnostic: shellParseDiagnostic(
        shell: shell,
        exitCode: run.exitCode,
        stderr: '${run.stderr}',
      ),
    );
  }
}

/// The shell's OWN first word on why it refused — the line an author can act
/// on (`unexpected EOF while looking for matching …`). A silent shell falls
/// back to the exit code, so the reason is never empty.
String shellParseDiagnostic({
  required String shell,
  required int exitCode,
  required String stderr,
}) {
  final complaint = stderr.trim();
  if (complaint.isEmpty) return '$shell -n exited $exitCode';
  return complaint.split('\n').first.trim();
}

/// What the six VIABILITY rows are judged against — everything a pure
/// evaluator cannot decide from the bead's own text.
///
/// Every leg has THREE states, never two: answered, answered-negative, and
/// NOT ANSWERED. An unavailable leg is never read as an empty one — "no store
/// holds this id" and "nobody asked a store" are different facts, and only the
/// first may refuse a bead for citing an id. A missing leg refuses ONLY when
/// the bead carries a token that needs it, and the refusal names the token and
/// the source that did not answer.
final class FilingEvidence {
  /// Binds whatever was gathered. Every leg defaults to NOT ANSWERED.
  const FilingEvidence({
    this.lanePlanParse,
    this.lanePlanProbeFailure = '',
    this.portablePlanParse,
    this.portablePlanProbeFailure = '',
    this.beadCatalogs = const {},
    this.beadCatalogFailures = const {},
    this.decisionRegisters,
    this.decisionIdentities = const {},
    this.decisionAliases = const {},
    this.absentDecisions = const {},
    this.reportedDecisionAliases = const {},
    this.decisionIndexFailure = '',
  });

  /// The evidence a caller who composed NO source has: nothing was looked up.
  ///
  /// This is explicitly NOT an empty catalog. A bead citing nothing passes
  /// every viability row against it; a bead citing something is refused
  /// NAMING what nobody looked up.
  ///
  /// One row cannot keep that promise, and says so instead of faking it: a
  /// bead id is only TELLABLE from prose against the set of store prefixes a
  /// catalog was read for, so with no catalog at all the `bead_references` row
  /// reports NOT CHECKED rather than either refusing every hyphenated word or
  /// claiming the text cites none.
  static const FilingEvidence unavailable = FilingEvidence();

  /// [kFilingLaneShell]'s answer, or null when it was never asked.
  final ValidationPlanParseResult? lanePlanParse;

  /// Why the lane probe did not answer — empty unless it failed.
  final String lanePlanProbeFailure;

  /// [kFilingPortabilityShell]'s answer, or null when it was never asked.
  final ValidationPlanParseResult? portablePlanParse;

  /// Why the portability probe did not answer — empty unless it failed.
  final String portablePlanProbeFailure;

  /// COMPLETE all-status id catalogs, keyed by the store PREFIX they were read
  /// under. A prefix present here was read whole, so an id under it that is
  /// absent from the set was never minted.
  final Map<String, Set<String>> beadCatalogs;

  /// Why a prefix's store could not answer, keyed by that prefix. A prefix
  /// here is unavailable, never empty.
  final Map<String, String> beadCatalogFailures;

  /// The registers the decision index ANSWERED with, lowercased, or null when
  /// no index answered at all. A canonical citation under a register nobody
  /// indexed is prose, exactly as it is in discovery's own gather.
  final Set<String>? decisionRegisters;

  /// Canonical `<register>#<slug>` identities the index returned, lowercased.
  final Set<String> decisionIdentities;

  /// Legacy `a<n>` / `adr-<nnnn>` aliases those same entries carry.
  final Set<String> decisionAliases;

  /// Citations the index PROVED absent from its whole register — completed
  /// negative evidence, and the only thing that may refuse a citation.
  ///
  /// CANONICAL citations only. A legacy id the same completed lookup could not
  /// answer arrives in [reportedDecisionAliases] instead.
  final Set<String> absentDecisions;

  /// Legacy `adr-<nnnn>` aliases a COMPLETED lookup answered by REPORTING them
  /// rather than by failing, lowercased.
  ///
  /// Also completed evidence, and the other half of it: the index looked, the
  /// register does not hold the id, and that is deliberately not a refusal
  /// (`power_station#notes-are-receipts-and-a-phantom-legacy-token-is-reported-not-failed`).
  /// The register's own log file is spelled `ADR-0000`, so a failure over an
  /// unresolvable legacy token is a hold nothing can clear. The row PASSES and
  /// names the exact slice, which is what keeps a genuine misspelling visible.
  final Set<String> reportedDecisionAliases;

  /// Why the decision index did not answer — empty unless it failed.
  final String decisionIndexFailure;

  /// Whether any decision lookup landed at all.
  bool get hasDecisionAnswer => decisionRegisters != null;
}

/// The asynchronous seam that GATHERS [FilingEvidence] for one bead.
///
/// Kept off [FilingContract] on purpose: the contract stays synchronous and
/// pure, so the same evaluation runs in a test, in a Flutter app and in the
/// CLI with no IO of its own.
abstract interface class FilingEvidenceSource {
  /// Gathers the evidence [bead] needs, reading the store at [storeRoot].
  Future<FilingEvidence> gather({
    required String storeRoot,
    required Bead bead,
  });
}

/// The default [SubstationBeadSource] for an id CATALOG: one scoped
/// `bd list -t <type> --status all --json --limit 0` per stable
/// [IssueType.coreTypes] value.
///
/// The scope is the ratified one, and the entry that ratifies it is
/// `power_station#the-per-store-bead-read-is-scoped-never-the-export-surface`
/// (which amends A11 clause (3), where the per-store read used to be
/// `bd export --all`). No source in this package issues that argv: on the
/// house CGO-free `bd` every store is a proxied server, where `bd export --all`
/// exits 1 with "export is not supported in proxied-server mode", and older
/// builds were worse — exit ZERO with an empty export against a NON-empty
/// store. An empty read is the one answer that must never be produced here,
/// because an empty catalog would refuse every id a bead cites, so any nonzero
/// exit, malformed envelope, malformed row or wrong-type row is ONE
/// incomplete-store failure rather than a short list.
///
/// That entry is also what permits a second implementation beside
/// [BdExportBeadSource]: the search corpus answers "what MATCHES", this
/// answers "does this id EXIST", and only the second has to tell an absent id
/// apart from an unreachable store.
///
/// Read-only by construction (A37): one read method, no mutation surface,
/// never `bd show`.
class BdListAllStatusBeadSource implements SubstationBeadSource {
  /// Creates the source over the injectable per-root spawn seam.
  const BdListAllStatusBeadSource({
    BdRunner Function(String storeRoot) runnerFor = _processBdRunnerFor,
  }) : _runnerFor = runnerFor;

  final BdRunner Function(String storeRoot) _runnerFor;

  @override
  Future<List<Bead>> read(sdk.SubstationScope scope) async {
    final runner = _runnerFor(scope.root);
    final byId = <String, Bead>{};
    for (final type in IssueType.coreTypes) {
      final argv = [
        'list',
        '-t',
        type.wire,
        '--status',
        'all',
        '--json',
        '--limit',
        '0',
      ];
      final result = await runner.run(argv);
      if (!result.ok) {
        throw StateError(
          'bd ${argv.join(' ')} in ${scope.root} exited ${result.exitCode}: '
          '${result.stderr.trim().isEmpty ? result.stdout.trim() : result.stderr.trim()}',
        );
      }
      final envelope = BdEnvelope.parse(result.stdout);
      for (final row in envelope.dataList) {
        final bead = Bead.fromJson(row);
        if (bead.issueType != type) {
          throw StateError(
            'bd ${argv.join(' ')} in ${scope.root} answered a '
            '${bead.issueType.wire} row for ${bead.id}',
          );
        }
        byId[bead.id] = bead;
      }
    }
    return byId.values.toList(growable: false);
  }
}

BdRunner _processBdRunnerFor(String storeRoot) =>
    ProcessBdRunner(workspaceRoot: storeRoot);

/// The LIVE [FilingEvidenceSource]: two parse probes, one all-status id
/// catalog per distinct store, and one roster-mode decision-index lookup.
///
/// Every leg is optional and every ABSENT leg is recorded as unavailable, not
/// as an empty answer. Nothing here is asked unless the bead carries a token
/// that needs it: a bead citing no id reads no catalog, and a bead citing no
/// decision runs no index.
final class SystemFilingEvidenceSource implements FilingEvidenceSource {
  /// Composes the live evidence legs.
  ///
  /// [owning] is the substation whose store the bead is being filed in — its
  /// name roster-qualifies the decision surfaces, and its prefix keys the
  /// current catalog. [attached] are the station's other armed substations,
  /// each read once. [decisions] is the same injected `DecisionIndexSource`
  /// seam discovery gathers through; absent ⇒ no index runs.
  const SystemFilingEvidenceSource({
    this.probe = const SystemValidationPlanProbe(),
    this.catalog = const BdListAllStatusBeadSource(),
    this.owning,
    this.attached = const [],
    this.decisions,
  });

  /// The parse seam both plan rows are judged on.
  final ValidationPlanProbe probe;

  /// The per-store all-status read.
  final SubstationBeadSource catalog;

  /// The substation this filing belongs to, or null when none was composed.
  final sdk.SubstationScope? owning;

  /// The station's other armed substations.
  final List<sdk.SubstationScope> attached;

  /// The roster-mode decision index, or null when none was composed.
  final DecisionIndexSource? decisions;

  @override
  Future<FilingEvidence> gather({
    required String storeRoot,
    required Bead bead,
  }) async {
    final plan = beadTextOf(bead, BeadTextField.validationPlan).trim();
    ValidationPlanParseResult? lane;
    ValidationPlanParseResult? portable;
    var laneFailure = '';
    var portableFailure = '';
    if (plan.isNotEmpty) {
      try {
        lane = await probe.parse(
          shell: kFilingLaneShell,
          plan: plan,
          workingDirectory: storeRoot,
        );
      } on Object catch (error) {
        laneFailure = '$kFilingLaneShell probe failed: $error';
      }
      if (lane != null && lane.parsed) {
        try {
          portable = await probe.parse(
            shell: kFilingPortabilityShell,
            plan: plan,
            workingDirectory: storeRoot,
          );
        } on Object catch (error) {
          // A dash nobody installed and a dash that crashed are both the
          // ABSENCE of an answer, and neither says the plan is portable. The
          // exception's own name carries which it was into the row.
          portableFailure = '$kFilingPortabilityShell probe failed: $error';
        }
      }
    }

    final catalogs = <String, Set<String>>{};
    final catalogFailures = <String, String>{};
    // The OWNING store answers at the per-run root the verb was pointed at;
    // every other scope answers at its own. Each distinct store is read ONCE.
    final scopes = <String, sdk.SubstationScope>{};
    final own = owning;
    if (own != null) {
      scopes[own.prefix] = sdk.SubstationScope(
        name: own.name,
        root: storeRoot,
        prefix: own.prefix,
      );
    }
    for (final scope in attached) {
      scopes.putIfAbsent(scope.prefix, () => scope);
    }
    if (beadIdReferences(bead, prefixes: scopes.keys.toSet()).isNotEmpty) {
      for (final entry in scopes.entries) {
        try {
          final beads = await catalog.read(entry.value);
          catalogs[entry.key] = {for (final row in beads) row.id};
        } on Object catch (error) {
          catalogFailures[entry.key] =
              'all-status read of ${entry.value.name} '
              '(${entry.value.root}) failed: $error';
        }
      }
    } else {
      // Nothing to resolve — but the PREFIXES still have to be declared, or a
      // scanner with no prefixes would report a vacuous pass over text nobody
      // scanned. An empty complete catalog under a prefix with no citation is
      // exactly as true as a read would have been.
      for (final prefix in scopes.keys) {
        catalogs[prefix] = const <String>{};
      }
    }

    final index = decisions;
    Set<String>? registers;
    final identities = <String>{};
    final aliases = <String>{};
    final absent = <String>{};
    final reported = <String>{};
    var indexFailure = '';
    if (index != null && own != null) {
      // Roster-qualified surfaces: the bead's own repository-relative anchors
      // under the owning substation's name. A bead naming no file still has an
      // existence surface — the substation's README — because citation
      // EXISTENCE is a register-wide question the index answers register-wide.
      final anchors = beadAnchors(bead).paths;
      final surfaces = [
        for (final anchor in anchors) '${own.name}/$anchor',
        if (anchors.isEmpty) '${own.name}/README.md',
      ];
      try {
        final gather = await index(storeRoot, surfaces, bead);
        for (final entry in gather.decisionEntries.values) {
          identities.add(entry.identity.toLowerCase());
          final alias = legacyDecisionAlias(entry.slug);
          if (alias.isNotEmpty) aliases.add(alias);
        }
        // ANSWERED means at least one lookup reached a verdict — a complete or
        // clipped union, or the one failure that IS a verdict (a citation the
        // whole register does not hold). An index that only crashed answered
        // nothing, and its registers must stay null so an unanswered citation
        // reads as unavailable rather than as prose.
        var answered = false;
        for (final lookup in gather.decisionLookups) {
          final absentLabels = _absentLabelsOf(lookup.error);
          if (absentLabels.isNotEmpty) {
            absent.addAll(absentLabels);
            answered = true;
            continue;
          }
          switch (lookup.state) {
            case EvidenceState.complete:
            case EvidenceState.truncated:
              // The record's ONE detail member carries a REPORT on an answered
              // surface, and only a well-formed one clears anything: a detail
              // that parses to no alias leaves every citation exactly as
              // unresolved as it was.
              reported.addAll(reportedLegacyDecisionAliases(lookup.error));
              answered = true;
            case EvidenceState.failed:
              indexFailure =
                  'decision index on ${lookup.surface}: ${lookup.error}';
            case EvidenceState.unavailable:
              indexFailure = 'decision index on ${lookup.surface} was not run';
          }
        }
        registers = answered ? _registersOf(gather) : null;
        if (gather.decisionLookups.isEmpty) {
          registers = null;
          indexFailure = 'decision index answered no lookup record';
        }
      } on Object catch (error) {
        registers = null;
        indexFailure = 'decision index failed: $error';
      }
    } else if (index == null) {
      indexFailure = 'no decision index was composed';
    } else {
      indexFailure = 'no owning substation scope was composed';
    }

    return FilingEvidence(
      lanePlanParse: lane,
      lanePlanProbeFailure: laneFailure,
      portablePlanParse: portable,
      portablePlanProbeFailure: portableFailure,
      beadCatalogs: catalogs,
      beadCatalogFailures: catalogFailures,
      decisionRegisters: registers,
      decisionIdentities: identities,
      decisionAliases: aliases,
      absentDecisions: absent,
      reportedDecisionAliases: reported,
      decisionIndexFailure: indexFailure,
    );
  }

  Set<String> _registersOf(DecisionGatherEvidence gather) => {
    for (final DecisionEntryEvidence entry in gather.decisionEntries.values)
      entry.originRegister.toLowerCase(),
  };
}

/// The index's one COMPLETED-NEGATIVE outcome, and the only one that may
/// refuse a citation. Every other failure is unavailability.
const String kDecisionAbsentPrefix = 'named decision absent from index: ';

Set<String> _absentLabelsOf(String error) {
  final at = error.indexOf(kDecisionAbsentPrefix);
  if (at < 0) return const {};
  return {
    for (final label
        in error.substring(at + kDecisionAbsentPrefix.length).split(','))
      if (label.trim().isNotEmpty) label.trim().toLowerCase(),
  };
}

/// Pure evaluator for the eleven-row filing report.
///
/// This is the FILING COMPLETENESS contract of
/// `power_station#approval-is-the-stamp-the-grid-approved-label-retires` —
/// *"FILING COMPLETENESS in `lib/src/filing/`, MOUNT ELIGIBILITY in
/// `lib/src/code/`, neither subsuming the other, no third completeness
/// predicate minted"*. The roster resolution of an `external:` row is a
/// refinement of this contract's own dependency row, and the six VIABILITY
/// rows and the one CONTENT row are further requirements OF THIS CONTRACT —
/// mount eligibility is untouched and no second checker is minted beside
/// filing.
final class FilingContract {
  /// Creates the stateless evaluator.
  const FilingContract();

  /// Evaluates [bead] against the dependency rows bd holds for it.
  ///
  /// The dependencies row is a PURE PROJECTION of those rows — local targets
  /// and `external:<project>:<capability>` targets alike — with each external
  /// row resolved through [armedSubstations], the station's roster by NAME.
  /// Bead PROSE is never read: `Blocked-by: pow-x` and `Blocked by pow-x` are
  /// both sentences, and both project identically because neither is a row.
  ///
  /// [armedSubstations] is NULL when no roster was supplied. An unasked roster
  /// cannot clear a cross-project blocker, so an external row then refuses
  /// fail-closed exactly as an unarmed project does — the difference is in the
  /// detail, which says which condition it is and what to do about it.
  /// [evidence] is what the six VIABILITY rows are judged against. It is
  /// REQUIRED and never defaulted: a caller that gathered nothing passes
  /// [FilingEvidence.unavailable], which refuses a bead for the tokens nobody
  /// could resolve rather than silently clearing them. The CONTENT row reads
  /// no evidence at all — the bead's own text is the whole question — so it
  /// answers the same under either posture.
  FilingReport evaluate(
    Bead bead,
    Iterable<BeadDependency> dependencies, {
    required FilingEvidence evidence,
    Set<String>? armedSubstations,
  }) => _evaluateWithProjection(
    bead,
    dependencies,
    evidence: evidence,
    armedSubstations: armedSubstations,
  ).report;

  /// [evaluate], RETAINING the projection the dependencies row was rendered
  /// from.
  ///
  /// The mount explainer's own `dependencies` precondition is a REFINEMENT of
  /// this very projection — the rows bd holds, plus whether each local target
  /// is still open — so it consumes the one this evaluation already built.
  /// Rebuilding a second projection from a second read is how the two verbs
  /// would come to disagree about the same rows.
  ({DependencyProjection dependencyProjection, FilingReport report})
  _evaluateWithProjection(
    Bead bead,
    Iterable<BeadDependency> dependencies, {
    required FilingEvidence evidence,
    Set<String>? armedSubstations,
  }) {
    final validationPlan = bead.metadata['validation_plan'];
    final projection = DependencyProjection.of(
      beadId: bead.id,
      dependencies: dependencies,
      armedSubstations: armedSubstations,
    );
    final report = FilingReport(
      beadId: bead.id,
      approvalRevision: _approvalRevisionOf(bead, projection),
      requirements: [
        FilingRequirementRow(
          requirement: FilingRequirement.driveableType,
          passed: bead.issueType.isDriveable,
          detail: bead.issueType.isDriveable
              ? '${bead.issueType.wire} is driveable'
              : '${bead.issueType.wire} is not driveable',
        ),
        FilingRequirementRow(
          requirement: FilingRequirement.validationPlan,
          passed: validationPlan is String && validationPlan.trim().isNotEmpty,
          detail: validationPlan is String && validationPlan.trim().isNotEmpty
              ? 'validation_plan is present'
              : 'validation_plan is blank',
        ),
        FilingRequirementRow(
          requirement: FilingRequirement.acceptanceCriteria,
          passed: bead.acceptanceCriteria.trim().isNotEmpty,
          detail: bead.acceptanceCriteria.trim().isNotEmpty
              ? 'acceptance_criteria is present'
              : 'acceptance_criteria is blank',
        ),
        FilingRequirementRow(
          requirement: FilingRequirement.dependencies,
          passed: projection.passed,
          detail: projection.detail,
        ),
        _validationPlanSyntaxRow(bead, evidence),
        _validationPlanPortabilityRow(bead, evidence),
        _repoRelativePathsRow(bead),
        _beadReferencesRow(bead, evidence),
        _releaseVersionsRow(bead),
        _decisionReferencesRow(bead, evidence),
        _noCorruptingTextRow(bead),
      ],
    );
    return (dependencyProjection: projection, report: report);
  }
}

/// Renders [slices] as `"text" (field:offset)`, joined in the field/offset
/// order the scanners already returned them in.
String _named(Iterable<BeadTextSlice> slices) =>
    slices.map((slice) => '"${slice.text}" (${slice.location})').join(', ');

/// The plan's exact offending text, so a refusal can be SEARCHED for rather
/// than guessed at.
String _planSlice(String plan, String diagnostic) =>
    validationPlanOffendingSlice(plan, diagnostic);

FilingRequirementRow _validationPlanSyntaxRow(
  Bead bead,
  FilingEvidence evidence,
) {
  final plan = beadTextOf(bead, BeadTextField.validationPlan).trim();
  if (plan.isEmpty) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.validationPlanSyntax,
      passed: true,
      detail:
          'no validation_plan to parse — the validation_plan row carries the '
          'blank',
    );
  }
  final parse = evidence.lanePlanParse;
  if (parse == null) {
    return FilingRequirementRow(
      requirement: FilingRequirement.validationPlanSyntax,
      passed: false,
      detail:
          'no $kFilingLaneShell parse of the validation_plan was gathered'
          '${evidence.lanePlanProbeFailure.isEmpty ? '' : ' — '
                    '${evidence.lanePlanProbeFailure}'}; the plan checked is '
          '"${_planSlice(plan, '')}" — restore complete evidence and rerun',
    );
  }
  if (parse.parsed) {
    return FilingRequirementRow(
      requirement: FilingRequirement.validationPlanSyntax,
      passed: true,
      detail: 'validation_plan parses under ${parse.shell}',
    );
  }
  return FilingRequirementRow(
    requirement: FilingRequirement.validationPlanSyntax,
    passed: false,
    detail:
        'validation_plan does not parse under ${parse.shell}: '
        '${parse.diagnostic}; offending text '
        '"${_planSlice(plan, parse.diagnostic)}" — '
        'rewrite as one parseable POSIX-shell command',
  );
}

FilingRequirementRow _validationPlanPortabilityRow(
  Bead bead,
  FilingEvidence evidence,
) {
  final plan = beadTextOf(bead, BeadTextField.validationPlan).trim();
  if (plan.isEmpty) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.validationPlanPortability,
      passed: true,
      detail:
          'no validation_plan to parse — the validation_plan row carries the '
          'blank',
    );
  }
  // Until SYNTAX passes there is nothing portability can add: a plan no shell
  // parses would refuse twice and name the same text twice.
  final lane = evidence.lanePlanParse;
  if (lane == null || !lane.parsed) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.validationPlanPortability,
      passed: true,
      detail:
          'not probed — the validation_plan_syntax row is answered first and '
          'carries this plan',
    );
  }
  final parse = evidence.portablePlanParse;
  if (parse == null) {
    return FilingRequirementRow(
      requirement: FilingRequirement.validationPlanPortability,
      passed: false,
      detail:
          'no $kFilingPortabilityShell parse of the validation_plan was '
          'gathered'
          '${evidence.portablePlanProbeFailure.isEmpty ? '' : ' — '
                    '${evidence.portablePlanProbeFailure}'}; the plan checked is '
          '"${_planSlice(plan, '')}" — restore complete evidence and rerun',
    );
  }
  if (parse.parsed) {
    return FilingRequirementRow(
      requirement: FilingRequirement.validationPlanPortability,
      passed: true,
      detail: 'validation_plan parses under ${parse.shell}',
    );
  }
  return FilingRequirementRow(
    requirement: FilingRequirement.validationPlanPortability,
    passed: false,
    detail:
        'validation_plan parses under ${lane.shell} but not under '
        '${parse.shell}: ${parse.diagnostic}; offending text '
        '"${_planSlice(plan, parse.diagnostic)}" — '
        'replace the Bash-only construct with POSIX sh syntax',
  );
}

FilingRequirementRow _repoRelativePathsRow(Bead bead) {
  final found = absolutePathReferences(bead);
  return FilingRequirementRow(
    requirement: FilingRequirement.repoRelativePaths,
    passed: found.isEmpty,
    detail: found.isEmpty
        ? 'every file anchor in the bead text is repository-relative'
        : 'absolute file path in bead text: ${_named(found)} — '
              'use a repository-relative path',
  );
}

FilingRequirementRow _beadReferencesRow(Bead bead, FilingEvidence evidence) {
  final prefixes = {
    ...evidence.beadCatalogs.keys,
    ...evidence.beadCatalogFailures.keys,
  };
  // Without a prefix set there is no id GRAMMAR at all: `filing-nosuch` and
  // `fail-closed` are the same shape, and only the stores the caller holds a
  // catalog for tell them apart. So a row handed NO catalog never established
  // that the text cites nothing — it never had a question to ask. It cannot
  // refuse either: inventing a grammar here would refuse every hyphenated word
  // in the org, the false refusal this contract is most careful about. It
  // passes and says WHICH it is, because a detail claiming a finding nobody
  // made is the precise confusion the three-state evidence exists to remove.
  if (prefixes.isEmpty) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.beadReferences,
      passed: true,
      detail:
          'not checked — no store catalog was composed, so no bead-id grammar '
          'applies here; compose the owning substation scope to have this row '
          'answer',
    );
  }
  final found = beadIdReferences(bead, prefixes: prefixes);
  if (found.isEmpty) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.beadReferences,
      passed: true,
      detail: 'the bead text cites no bead id',
    );
  }
  final unresolved = <BeadTextSlice>[];
  final unavailable = <BeadTextSlice>[];
  final sources = <String>{};
  for (final slice in found) {
    final prefix = beadIdPrefixOf(slice.text);
    final catalog = evidence.beadCatalogs[prefix];
    if (catalog == null) {
      unavailable.add(slice);
      sources.add(
        evidence.beadCatalogFailures[prefix] ??
            'no all-status catalog was read for the "$prefix" store',
      );
      continue;
    }
    if (!catalog.contains(slice.text)) unresolved.add(slice);
  }
  if (unavailable.isNotEmpty) {
    return FilingRequirementRow(
      requirement: FilingRequirement.beadReferences,
      passed: false,
      detail:
          'bead id evidence is unavailable for ${_named(unavailable)}: '
          '${(sources.toList()..sort()).join('; ')} — '
          'restore complete evidence and rerun',
    );
  }
  return FilingRequirementRow(
    requirement: FilingRequirement.beadReferences,
    passed: unresolved.isEmpty,
    detail: unresolved.isEmpty
        ? 'every cited bead id exists: '
              '${found.map((slice) => slice.text).toSet().join(', ')}'
        : 'no attached store holds ${_named(unresolved)} — '
              'mint it before citing it or cite an existing attached-store id',
  );
}

FilingRequirementRow _releaseVersionsRow(Bead bead) {
  final found = exactReleaseVersions(bead);
  return FilingRequirementRow(
    requirement: FilingRequirement.releaseVersions,
    passed: found.isEmpty,
    detail: found.isEmpty
        ? 'acceptance_criteria pins no exact release version'
        : 'exact release version pinned in acceptance_criteria: '
              '${_named(found)} — '
              'use release-relative language or a version range',
  );
}

FilingRequirementRow _decisionReferencesRow(
  Bead bead,
  FilingEvidence evidence,
) {
  // WHICH registers a canonical citation may name depends on whether anything
  // answered. When an index ANSWERED, a token under a register it never
  // mentioned is prose — refusing on it would hold a bead over a hash in a
  // sentence. When NOTHING answered, there is no such reading available: every
  // cited register is a register nobody looked at, and the citation is
  // unavailable rather than cleared.
  final byKey = <String, DecisionReference>{};
  for (final reference in decisionReferences(
    bead,
    knownRegisters: evidence.decisionRegisters ?? citedDecisionRegisters(bead),
  )) {
    byKey[reference.key] = reference;
  }
  // A citation the index PROVED absent is decided whether or not this gather's
  // entries happened to name its register: the index answered about the
  // citation itself, and "nobody indexed that register" is only a reason to
  // read a token as prose while nothing has been said about it.
  for (final reference in decisionReferences(
    bead,
    knownRegisters: citedDecisionRegisters(bead),
  )) {
    if (evidence.absentDecisions.contains(reference.label.toLowerCase())) {
      byKey.putIfAbsent(reference.key, () => reference);
    }
  }
  final found = byKey.values.toList(growable: false);
  if (found.isEmpty) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.decisionReferences,
      passed: true,
      detail: 'the bead text cites no decision',
    );
  }
  final recorded = <DecisionReference>[];
  final reported = <DecisionReference>[];
  final missing = <DecisionReference>[];
  final unavailable = <DecisionReference>[];
  for (final reference in found) {
    final resolved = reference.isCanonical
        ? evidence.decisionIdentities.contains(reference.identity)
        : evidence.decisionAliases.contains(reference.alias);
    if (resolved) {
      recorded.add(reference);
      continue;
    }
    // A LEGACY id the index answered by REPORTING is answered — it simply is
    // not a refusal. Never canonical: an authored `<register>#<slug>` under an
    // indexed register is a citation nobody writes by accident.
    if (!reference.isCanonical &&
        evidence.reportedDecisionAliases.contains(reference.alias)) {
      reported.add(reference);
      continue;
    }
    if (evidence.absentDecisions.contains(reference.label.toLowerCase())) {
      missing.add(reference);
    } else {
      unavailable.add(reference);
    }
  }
  if (unavailable.isNotEmpty) {
    final source = evidence.decisionIndexFailure.isEmpty
        ? 'the decision index answered no verdict on it'
        : evidence.decisionIndexFailure;
    return FilingRequirementRow(
      requirement: FilingRequirement.decisionReferences,
      passed: false,
      detail:
          'decision evidence is unavailable for '
          '${_named([for (final reference in unavailable) reference.slice])}: '
          '$source — restore complete evidence and rerun',
    );
  }
  return FilingRequirementRow(
    requirement: FilingRequirement.decisionReferences,
    passed: missing.isEmpty,
    detail: missing.isEmpty
        ? [
            if (recorded.isNotEmpty)
              'every cited decision is recorded: '
                  '${recorded.map((reference) => reference.key).join(', ')}',
            if (reported.isNotEmpty)
              'no register holds '
                  '${_named([for (final reference in reported) reference.slice])}'
                  ' — REPORTED, never refused: a legacy id in prose may name no '
                  'entry at all, the register log itself among them',
          ].join('; ')
        : 'no register holds '
              '${_named([for (final reference in missing) reference.slice])} — '
              'a round may not cite a decision it creates; cite an existing '
              'entry or describe the proposed entry without a citation',
  );
}

// ── the CONTENT row: text that corrupts the bead it is written into ─────────

/// The BODY fields the content row scans, in the order a refusal names them.
///
/// `title` and `validation_plan` are deliberately OUT. The plan is a shell
/// PROGRAM, where a backtick is the author's own command substitution and the
/// two plan rows already judge whether it works. The title is the one-line
/// summary the rule that cost the round never covered, and widening this row
/// onto it is a ruling of its own rather than a silent extension of this one.
const List<BeadTextField> _corruptibleFields = [
  BeadTextField.description,
  BeadTextField.design,
  BeadTextField.acceptanceCriteria,
  BeadTextField.notes,
];

/// The code units that corrupt a bead at EXEC time, by the name a refusal
/// calls them.
const Map<int, String> _corruptingUnits = {0x00: 'NUL', 0x60: 'backtick'};

/// How many corrupting SITES one refusal names before it reports the rest as a
/// count.
///
/// A bead that writes prose in markdown carries hundreds of backticks, and
/// naming every one produced a detail tens of kilobytes long — which does not
/// make the correction clearer and does blow the mount explainer's own byte
/// budget, so the report it rides out on could not be rendered at all. The
/// named sites are the ones an author edits first; the count is what tells
/// them how much is left.
const int _maxNamedCorruptingSites = 12;

/// [unit] as the PRINTABLE escape a refusal quotes it BY, never as itself.
///
/// The escape is not decoration: a detail is written back onto a bead and read
/// out of one, so a refusal that quoted the raw code unit would carry the very
/// corruption it is refusing.
String _printableUnit(int unit) =>
    r'\u' + unit.toRadixString(16).padLeft(4, '0');

/// The CONTENT row: the bead's own body text carries no NUL byte and no
/// backtick.
///
/// Both corrupt at exec time — a NUL TRUNCATES the write, and a backtick is
/// COMMAND-SUBSTITUTED by the shell that carries the field — and `bd` reports
/// success either way. The bead then files clean, mounts, and dies later in a
/// way that does not name its own cause, which is exactly the failure a
/// remembered rule cannot catch: it is invisible at the moment it is made.
///
/// This row gathers NOTHING. It is a scan of the bead's own text, so it
/// answers identically under [FilingEvidence.unavailable] and under a complete
/// live gather — there is no world-fact for it to be judged against.
FilingRequirementRow _noCorruptingTextRow(Bead bead) {
  final found = <String>[];
  for (final field in _corruptibleFields) {
    final text = beadTextOf(bead, field);
    for (var at = 0; at < text.length; at++) {
      final name = _corruptingUnits[text.codeUnitAt(at)];
      if (name == null) continue;
      final slice = BeadTextSlice(field: field, offset: at, text: text[at]);
      found.add(
        '$name "${_printableUnit(text.codeUnitAt(at))}" (${slice.location})',
      );
    }
  }
  final named = found.take(_maxNamedCorruptingSites).join(', ');
  final rest = found.length - _maxNamedCorruptingSites;
  return FilingRequirementRow(
    requirement: FilingRequirement.noCorruptingText,
    passed: found.isEmpty,
    detail: found.isEmpty
        ? 'description, design, acceptance_criteria and notes contain no NUL '
              'byte or backtick'
        : 'corrupting bead text: $named${rest > 0 ? ', and $rest more' : ''} — '
              'remove NUL bytes and backticks before filing',
  );
}

/// UI-drivable filing lookup plus contract evaluation — the ONE read/gather/
/// evaluate path the filing verb, the approve verb and the mount gate share.
final class FilingService {
  /// Creates the service over the existing source extension, the pure
  /// contract, and the evidence the viability rows are judged against.
  ///
  /// [evidence] is NULLABLE and defaults to none: a caller that composed no
  /// source gets [FilingEvidence.unavailable] — explicit unavailability, never
  /// an empty catalog. The live default composition is bound where the verbs
  /// are constructed (`FilingCommand`, `ApproveService`), so a test or an
  /// alternate station overrides it by injecting its own
  /// [FilingEvidenceSource] (or a whole [FilingService]).
  const FilingService({
    this.source = const ExactSubstationBeadSource(),
    this.contract = const FilingContract(),
    this.evidence,
  });

  /// Exact read source.
  final ExactSubstationBeadSource source;

  /// Pure contract evaluator.
  final FilingContract contract;

  /// The viability-evidence gather, or null when none was composed.
  final FilingEvidenceSource? evidence;

  /// Reads [beadId] in the store rooted at [storeRoot] and evaluates it,
  /// returning BOTH the exact bead read and its report.
  ///
  /// This is the ONE read/evaluate path: the filing verb, the approve verb and
  /// the mount gate all reach the store through it, so the report's
  /// [FilingReport.approvalRevision] is always the digest of the very bead
  /// alongside it.
  ///
  /// ONE store answers it. The dependencies row is a projection of the rows
  /// this store holds, cross-project rows included: bd carries those as
  /// `external:<project>:<capability>` targets on its own RECORD surface
  /// ([ExactSubstationBeadSource.readExact]), so there is no second store to
  /// consult and no link bead to read.
  ///
  /// [DependencyProjection] rides back out beside the report, and is null only
  /// when there was no bead to evaluate. A consumer that needs the ROWS — the
  /// mount explainer refines them with each local target's open/closed state —
  /// reads the projection this evaluation already built instead of rebuilding
  /// one, so the two verbs cannot disagree about the same rows.
  Future<
    ({
      Bead? bead,
      DependencyProjection? dependencyProjection,
      FilingReport report,
    })
  >
  inspect({
    required String storeRoot,
    required String beadId,
    Set<String>? armedSubstations,
  }) async {
    final read = await source.readExact(storeRoot: storeRoot, beadId: beadId);
    final bead = read.bead;
    if (bead == null) {
      return (
        bead: null,
        dependencyProjection: null,
        report: FilingReport.missing(beadId),
      );
    }
    // ONE gather per found bead, after the exact read and never before it:
    // there is nothing to gather evidence about until a bead exists.
    final gathered =
        await evidence?.gather(storeRoot: storeRoot, bead: bead) ??
        FilingEvidence.unavailable;
    final evaluated = contract._evaluateWithProjection(
      bead,
      read.dependencies,
      evidence: gathered,
      armedSubstations: armedSubstations,
    );
    return (
      bead: bead,
      dependencyProjection: evaluated.dependencyProjection,
      report: evaluated.report,
    );
  }

  /// Checks [beadId] in the store rooted at [storeRoot] — [inspect] without
  /// the bead.
  Future<FilingReport> check({
    required String storeRoot,
    required String beadId,
    Set<String>? armedSubstations,
  }) async => (await inspect(
    storeRoot: storeRoot,
    beadId: beadId,
    armedSubstations: armedSubstations,
  )).report;
}

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:crypto/crypto.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../code/discovery.dart'
    show DecisionGatherEvidence, DecisionIndexSource, EvidenceState;
import '../search/station_search.dart';
import 'approval_stamp.dart';
import 'filing_text.dart';

/// The ten mechanical checks reported for a newly filed bead.
///
/// The first four ask whether a field is PRESENT. The six after them ask
/// whether what is present is VIABLE — decidable from the bead's own text plus
/// evidence the caller supplies, and nothing else. A check that needs
/// execution (how long a plan runs) or blast-radius judgement (whether a plan
/// covers every affected consumer) is deliberately NOT here: it would refuse
/// legitimate work, and a false refusal at the front door is worse than the
/// round it would have saved.
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
  decisionReferences('decision_references');

  const FilingRequirement(this.wire);

  /// Stable JSON name consumed by skills and UIs.
  final String wire;
}

// ── viability evidence ───────────────────────────────────────────────────────

/// The shell the gating lane runs a validation plan under. `sh` on the lane
/// host is whatever that host's `sh` is — bash 3.2 on macOS, dash on CI.
const String kLaneShell = 'sh';

/// The STRICTLY POSIX shell a plan is re-parsed under. CI's `sh` is this, so a
/// plan that only bash accepts dies there — at PARSE, with no log and no return
/// code, which surfaces as a harness throttle rather than as a bad plan.
const String kPortabilityShell = 'dash';

/// The outcome of ONE non-executing shell parse of a validation plan.
sealed class PlanParse {
  /// Allows subclass const constructors.
  const PlanParse();
}

/// The shell PARSED the plan.
final class PlanParsed extends PlanParse {
  /// Creates the success.
  const PlanParsed();
}

/// The shell REFUSED the plan, carrying its own first diagnostic line.
final class PlanRefused extends PlanParse {
  /// Creates the refusal.
  const PlanRefused({required this.exitCode, required this.diagnostic});

  /// The shell's exit code.
  final int exitCode;

  /// The shell's OWN first word on why it refused — never empty; a silent
  /// shell falls back to its exit code.
  final String diagnostic;
}

/// The probe never RAN, so nothing can be concluded about the plan.
final class PlanUnavailable extends PlanParse {
  /// Creates the unavailable record.
  const PlanUnavailable(this.reason);

  /// The named reason nobody could look.
  final String reason;
}

/// The injectable, non-executing parse seam.
///
/// ONE implementation answers both the filing contract and the Specify stage's
/// authored-plan floor, so the two can never disagree about whether a plan
/// parses.
abstract interface class ValidationPlanProbe {
  /// Parses [plan] under [shell], from [workingDirectory], WITHOUT running it.
  Future<PlanParse> parse({
    required String plan,
    required String shell,
    required String workingDirectory,
  });
}

/// The default [ValidationPlanProbe]: `<shell> -n -c '( <plan> )'`.
///
/// `-n` parses and NEVER executes, and the plan is wrapped in the exact group
/// the gating lane wraps it in, so what is checked is what will run.
///
/// [ValidationPlanProbe.parse]'s working directory is honoured only when it
/// EXISTS. `-n` runs no command, so nothing resolves relative to the cwd and
/// the verdict is identical either way — but spawning INTO a directory that is
/// not there fails the spawn, which would turn a moved or synthetic store root
/// into a refusal about the plan. The cwd is a courtesy here; the parse is not.
final class SystemValidationPlanProbe implements ValidationPlanProbe {
  /// Creates the process-backed probe.
  const SystemValidationPlanProbe();

  @override
  Future<PlanParse> parse({
    required String plan,
    required String shell,
    required String workingDirectory,
  }) async {
    final ProcessResult parsed;
    try {
      parsed = await Process.run(
        shell,
        ['-n', '-c', '( ${plan.trim()} )'],
        workingDirectory: Directory(workingDirectory).existsSync()
            ? workingDirectory
            : null,
      );
    } on Object catch (error) {
      return PlanUnavailable('$shell could not be run: $error');
    }
    if (parsed.exitCode == 0) return const PlanParsed();
    final complaint = '${parsed.stderr}'.trim();
    return PlanRefused(
      exitCode: parsed.exitCode,
      diagnostic: complaint.isEmpty
          ? '$shell -n exited ${parsed.exitCode}'
          : complaint.split('\n').first.trim(),
    );
  }
}

/// What the all-status roster read across the attached stores answers with.
sealed class BeadIdCatalog {
  /// Allows subclass const constructors.
  const BeadIdCatalog();
}

/// Every bead id the attached stores hold, at every status. COMPLETE by
/// construction — an id absent from here does not exist.
final class BeadIdsRead extends BeadIdCatalog {
  /// Creates the catalog.
  const BeadIdsRead(this.ids);

  /// The complete id set.
  final Set<String> ids;
}

/// A store could not be read, so ABSENCE proves nothing.
final class BeadIdsUnavailable extends BeadIdCatalog {
  /// Creates the unavailable record.
  const BeadIdsUnavailable(this.reason);

  /// The named reason the catalog is incomplete.
  final String reason;
}

/// What the roster-wide decision index answers with.
sealed class DecisionCatalog {
  /// Allows subclass const constructors.
  const DecisionCatalog();
}

/// The recorded decision identities the index returned, plus the legacy
/// `adr-<nnnn>` aliases derived from their slugs.
final class DecisionsRead extends DecisionCatalog {
  /// Creates the catalog. Both sets are normalized lowercase.
  const DecisionsRead({required this.identities, required this.aliases});

  /// Canonical `<register>#<slug>` identities.
  final Set<String> identities;

  /// Legacy `adr-<nnnn>` ids the returned slugs carry.
  final Set<String> aliases;

  /// The registers this catalog ANSWERED for. A canonical token under a
  /// register nobody indexed is prose, not a citation.
  Set<String> get registers => {
    for (final identity in identities)
      identity.substring(0, identity.indexOf('#')),
  };
}

/// The index crashed or was never wired, so ABSENCE proves nothing.
final class DecisionsUnavailable extends DecisionCatalog {
  /// Creates the unavailable record.
  const DecisionsUnavailable(this.reason);

  /// The named reason the union is unreadable.
  final String reason;
}

/// Everything [FilingContract.evaluate] judges bead-text VIABILITY against
/// that it cannot decide from the text alone.
///
/// A null catalog or parse means NOBODY LOOKED — which is only ever correct
/// when the bead carries no token of that kind. The contract is what decides
/// that: it scans first, and a found token with no evidence behind it refuses
/// by SOURCE rather than silently reading as absent.
final class FilingEvidence {
  /// Creates the evidence.
  const FilingEvidence({
    this.attachedPrefixes = const {},
    this.laneParse,
    this.portabilityParse,
    this.beads,
    this.decisions,
  });

  /// The evidence of a round where nothing was looked up. A bead citing no id,
  /// no decision and carrying no plan passes every viability row on it; one
  /// that cites something does not.
  const FilingEvidence.unconsulted() : this();

  /// The id prefixes of the checked store and every attached store — the whole
  /// fence [beadIdReferences] reads with.
  final Set<String> attachedPrefixes;

  /// The lane shell's parse of the bead's validation plan, or null when there
  /// was no plan to parse.
  final PlanParse? laneParse;

  /// Dash's parse of the same plan, or null when the lane shell refused it
  /// first (portability is a question about a plan that already parses).
  final PlanParse? portabilityParse;

  /// The all-status bead-id catalog, or null when nothing asked for one.
  final BeadIdCatalog? beads;

  /// The recorded-decision catalog, or null when nothing asked for one.
  final DecisionCatalog? decisions;
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

  /// Ten rows for a found bead, in [FilingRequirement.values] order.
  final List<FilingRequirementRow> requirements;

  /// The revision this filing WOULD be approved against — the deterministic
  /// digest of the bead CONTENT every row is evaluated over. Empty for a
  /// report with no bead to evaluate.
  ///
  /// The viability rows added no basis of their own: they read the same work
  /// fields and the same validation plan the digest already covers, so a bead
  /// whose text is unchanged keeps the receipt it earned.
  ///
  /// This is what `ApproveService` stamps as `grid.approved_rev` and what the
  /// mount gate re-derives to tell a live receipt from a stale one.
  final String approvalRevision;

  /// Lookup-level refusal; non-null reports never pass.
  final String? error;

  /// True only for a found bead with exactly ten passing rows.
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

/// Splits a description where a blocker DECLARATION can end: a sentence
/// terminator followed by whitespace or end-of-input, or a line break. A `.`
/// followed by a word character stays inside its segment, so dotted child ids
/// (`pow-n6n.1`) survive the split.
final RegExp _segmentBreak = RegExp(r'(?:[.!?;](?=\s|$)|\n)+');

/// A segment DECLARES blockers only when it OPENS with the phrase, after any
/// list or quote marker: `Blocked by: pow-one` on its own line declares, and
/// `pow-pry0 carries a 'DEPENDS ON: tg-1n4y' receipt` only MENTIONS one.
final RegExp _leadingBlockerPhrase = RegExp(
  r'^[\s>*#-]*(?:\d+[.)]\s*)?(?:blocked\s+(?:by|on)|depends\s+on)\b',
  caseSensitive: false,
);

/// A `<prefix>-<tail>` token — the SHAPE of a bead id. Shape alone does not
/// make one: [_isBeadId] decides.
final RegExp _candidateId = RegExp(r'\b[a-z][a-z0-9_]*(?:-[a-z0-9_.]+)+\b');

final RegExp _digit = RegExp(r'[0-9]');

/// The store prefix of [id] — `pow` for `pow-n6n.1`; empty when [id] carries
/// no prefix at all.
String _prefixOf(String id) {
  final hyphen = id.indexOf('-');
  return hyphen <= 0 ? '' : id.substring(0, hyphen);
}

/// True when [candidate] reads as a bead id rather than a hyphenated English
/// compound (`cross-store`, `read-only`): its prefix is one this check already
/// knows ([knownPrefixes] — the checked bead's own store, plus the store of
/// every blocker already wired), or its tail carries a digit.
///
/// The prefix arm is what keeps digitless ids (`pow-one`, `filing-blocker`)
/// readable; requiring a digit alone would silently stop naming them.
bool _isBeadId(String candidate, Set<String> knownPrefixes) {
  final hyphen = candidate.indexOf('-');
  return knownPrefixes.contains(candidate.substring(0, hyphen)) ||
      _digit.hasMatch(candidate.substring(hyphen + 1));
}

/// The blocker ids DECLARED by [description] — read ONLY from segments that
/// open with a blocker phrase, and only from tokens [_isBeadId] accepts.
Set<String> _namedBlockers(String description, Set<String> knownPrefixes) => {
  for (final segment in description.split(_segmentBreak))
    if (_leadingBlockerPhrase.matchAsPrefix(segment) case final phrase?)
      for (final match in _candidateId.allMatches(
        segment.substring(phrase.end),
      ))
        if (_isBeadId(match.group(0)!, knownPrefixes)) match.group(0)!,
};

BdRunner _processRunnerFor(String stateRoot) =>
    ProcessBdRunner(workspaceRoot: stateRoot);

/// Reads the station's own state store for open link beads that wire a named
/// cross-store blocker.
final class CrossLinkBlockerSource {
  /// Creates the source over an injectable spawn seam.
  const CrossLinkBlockerSource({
    BdRunner Function(String stateRoot) runnerFor = _processRunnerFor,
  }) : _runnerFor = runnerFor;

  final BdRunner Function(String stateRoot) _runnerFor;

  /// The blocker ids wired for [beadId] by an open link bead in [stateRoot].
  Future<Set<String>> wiredFor({
    required String stateRoot,
    required String beadId,
  }) async {
    final scope = await BdCliService(
      _runnerFor(stateRoot),
    ).listScope(type: GridIssueTypes.link, status: BeadStatus.open);
    final snapshot = GraphSnapshot.fromParts(
      beads: scope.beads,
      dependencies: const <BeadDependency>[],
      readyIds: const <String>[],
      capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    return {
      for (final link in projectCrossLinks(snapshot))
        if (link.from == beadId && link.to.isNotEmpty) link.to,
    };
  }
}

/// The dependency detail for unwired blockers the state store was never asked
/// about — an UNCHECKED condition, never the fact that the edge is missing.
///
/// A refiner instructed by `missing outgoing blocks edges` wires each named id;
/// told that about an edge an open link bead already carries, it writes a
/// duplicate. So the two conditions get two strings.
const String kUnconsultedCrossStoreDetail =
    'cross-store edges not consulted — pass --state-root';

/// The version-1 approval revision of one evaluated filing.
///
/// It digests exactly what an approval is a judgement ABOUT: the bead's work
/// fields, its validation plan, and — per named blocker, sorted — whether a
/// local outgoing `blocks` edge and an open linked-blocker proof were found.
/// Lifecycle timestamps, status, assignee/owner, result metadata and the
/// receipt itself are all EXCLUDED, so stamping the receipt can never
/// invalidate the receipt it stamps, and a bead moving through its lifecycle
/// does not revoke a governor's approval of its content.
String _approvalRevisionOf(
  Bead bead, {
  required Set<String> named,
  required Set<String> localBlocks,
  required Set<String>? linkedBlockers,
}) {
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
    'dependencies': [
      for (final id in named.toList()..sort())
        {
          'id': id,
          'blocks': localBlocks.contains(id),
          'linked': linkedBlockers?.contains(id) ?? false,
        },
    ],
  };
  final digest = sha256.convert(utf8.encode(jsonEncode(basis)));
  return '$kFilingApprovalRevisionPrefix$digest';
}

/// The instruction appended to every unavailable-evidence refusal. An
/// unconsulted lookup is reported as UNCHECKED and never as missing, so the
/// caller is told to restore the source rather than to edit the bead.
const String kRestoreEvidenceDetail = 'restore the evidence source and rerun';

/// The six correction clauses. Each one names what to DO, because a check that
/// only says "invalid" moves the guessing rather than removing it.
const String kSyntaxCorrection = 'rewrite as one parseable POSIX-shell command';

/// The portability clause.
const String kPortabilityCorrection =
    'replace the Bash-only construct with POSIX sh syntax';

/// The absolute-path clause.
const String kRepoRelativeCorrection = 'use a repository-relative path';

/// The unminted-bead-id clause.
const String kBeadReferenceCorrection =
    'mint it before citing it or cite an existing attached-store id';

/// The pinned-release clause.
const String kReleaseVersionCorrection =
    'use release-relative language or a version range';

/// The self-citing-decision clause.
const String kDecisionReferenceCorrection =
    'a round may not cite a decision it creates; cite an existing entry or '
    'describe the proposed entry without a citation';

/// The `validation_plan_syntax` row: does the lane shell PARSE the plan?
///
/// A blank plan is the presence row's to own and passes here — this contract
/// mints no second completeness predicate.
FilingRequirementRow _syntaxRow(String plan, PlanParse? parse) {
  const requirement = FilingRequirement.validationPlanSyntax;
  if (plan.trim().isEmpty) {
    return const FilingRequirementRow(
      requirement: requirement,
      passed: true,
      detail: 'no validation_plan to parse',
    );
  }
  return switch (parse) {
    PlanParsed() => const FilingRequirementRow(
      requirement: requirement,
      passed: true,
      detail: 'validation_plan parses under $kLaneShell',
    ),
    PlanRefused(:final diagnostic) => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'validation_plan does not parse: '
          '${validationPlanOffendingSlice(plan, diagnostic: diagnostic)} '
          '— $kSyntaxCorrection ($diagnostic)',
    ),
    PlanUnavailable(:final reason) => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'validation_plan was not parsed: $reason; $kRestoreEvidenceDetail',
    ),
    null => const FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'validation_plan was not parsed: no $kLaneShell probe ran; '
          '$kRestoreEvidenceDetail',
    ),
  };
}

/// The `validation_plan_portability` row: does DASH parse a plan the lane
/// shell already accepted?
///
/// It is a question ABOUT a parseable plan, so a plan the lane shell refused is
/// reported here as not evaluated — the syntax row already fails the report,
/// and naming the same defect twice tells the refiner nothing new.
FilingRequirementRow _portabilityRow(
  String plan,
  PlanParse? laneParse,
  PlanParse? parse,
) {
  const requirement = FilingRequirement.validationPlanPortability;
  if (plan.trim().isEmpty) {
    return const FilingRequirementRow(
      requirement: requirement,
      passed: true,
      detail: 'no validation_plan to parse',
    );
  }
  if (laneParse is! PlanParsed) {
    return const FilingRequirementRow(
      requirement: requirement,
      passed: true,
      detail: 'not evaluated — validation_plan_syntax refused first',
    );
  }
  return switch (parse) {
    PlanParsed() => const FilingRequirementRow(
      requirement: requirement,
      passed: true,
      detail: 'validation_plan parses under $kPortabilityShell',
    ),
    PlanRefused(:final diagnostic) => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'validation_plan is $kPortabilityShell-incompatible: '
          '${validationPlanOffendingSlice(plan, diagnostic: diagnostic)} '
          '— $kPortabilityCorrection ($diagnostic)',
    ),
    PlanUnavailable(:final reason) => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'validation_plan portability is unchecked: $reason; '
          '$kRestoreEvidenceDetail',
    ),
    null => const FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'validation_plan portability is unchecked: no $kPortabilityShell '
          'probe ran; $kRestoreEvidenceDetail',
    ),
  };
}

/// The `repo_relative_paths` row — decided from the bead text alone.
FilingRequirementRow _repoRelativeRow(Bead bead) {
  final rooted = absolutePathReferences(bead);
  if (rooted.isEmpty) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.repoRelativePaths,
      passed: true,
      detail: 'every file path is repository-relative',
    );
  }
  return FilingRequirementRow(
    requirement: FilingRequirement.repoRelativePaths,
    passed: false,
    detail:
        'absolute file paths: '
        '${[for (final slice in rooted) slice.text].join(', ')} '
        '— $kRepoRelativeCorrection',
  );
}

/// The `bead_references` row: every id-shaped token under an attached-store
/// prefix must EXIST in the complete all-status catalog.
FilingRequirementRow _beadReferenceRow(
  Bead bead,
  Set<String> prefixes,
  BeadIdCatalog? catalog,
) {
  const requirement = FilingRequirement.beadReferences;
  final cited = [
    for (final slice in beadIdReferences(bead, prefixes: prefixes))
      if (slice.text != bead.id) slice.text,
  ];
  if (cited.isEmpty) {
    return const FilingRequirementRow(
      requirement: requirement,
      passed: true,
      detail: 'no attached-store bead ids are cited',
    );
  }
  return switch (catalog) {
    BeadIdsRead(:final ids) => () {
      final absent = [
        for (final id in cited)
          if (!ids.contains(id)) id,
      ];
      return absent.isEmpty
          ? FilingRequirementRow(
              requirement: requirement,
              passed: true,
              detail: 'every cited bead id exists: ${cited.join(', ')}',
            )
          : FilingRequirementRow(
              requirement: requirement,
              passed: false,
              detail:
                  'unminted bead ids: ${absent.join(', ')} '
                  '— $kBeadReferenceCorrection',
            );
    }(),
    BeadIdsUnavailable(:final reason) => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'bead-id existence is unchecked for ${cited.join(', ')}: $reason; '
          '$kRestoreEvidenceDetail',
    ),
    null => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'bead-id existence is unchecked for ${cited.join(', ')}: no store '
          'catalog was read; $kRestoreEvidenceDetail',
    ),
  };
}

/// The `release_versions` row — decided from the acceptance criteria alone.
FilingRequirementRow _releaseVersionRow(Bead bead) {
  final pinned = exactReleaseVersions(bead);
  if (pinned.isEmpty) {
    return const FilingRequirementRow(
      requirement: FilingRequirement.releaseVersions,
      passed: true,
      detail: 'acceptance_criteria pins no exact release',
    );
  }
  return FilingRequirementRow(
    requirement: FilingRequirement.releaseVersions,
    passed: false,
    detail:
        'exact release versions in acceptance_criteria: '
        '${[for (final slice in pinned) slice.text].join(', ')} '
        '— $kReleaseVersionCorrection',
  );
}

/// The `decision_references` row: every EXPLICIT citation must already be
/// recorded.
///
/// A canonical token under a register the catalog never answered for is PROSE,
/// not a citation — failing a bead over a hash in a sentence is exactly the
/// false refusal this contract must not make.
FilingRequirementRow _decisionReferenceRow(
  Bead bead,
  DecisionCatalog? catalog,
) {
  const requirement = FilingRequirement.decisionReferences;
  final cited = decisionReferences(bead);
  if (cited.isEmpty) {
    return const FilingRequirementRow(
      requirement: requirement,
      passed: true,
      detail: 'no decisions are cited',
    );
  }
  return switch (catalog) {
    DecisionsRead(:final identities, :final aliases, :final registers) => () {
      final absent = <String>[];
      for (final reference in cited) {
        if (reference.alias.isNotEmpty) {
          if (!aliases.contains(reference.alias)) {
            absent.add(reference.citation);
          }
          continue;
        }
        if (!registers.contains(reference.register)) continue;
        if (!identities.contains(reference.identity)) {
          absent.add(reference.citation);
        }
      }
      return absent.isEmpty
          ? FilingRequirementRow(
              requirement: requirement,
              passed: true,
              detail:
                  'every cited decision is recorded: '
                  '${[for (final r in cited) r.citation].join(', ')}',
            )
          : FilingRequirementRow(
              requirement: requirement,
              passed: false,
              detail:
                  'unrecorded decision citations: ${absent.join(', ')} '
                  '— $kDecisionReferenceCorrection',
            );
    }(),
    DecisionsUnavailable(:final reason) => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'decision existence is unchecked for '
          '${[for (final r in cited) r.citation].join(', ')}: $reason; '
          '$kRestoreEvidenceDetail',
    ),
    null => FilingRequirementRow(
      requirement: requirement,
      passed: false,
      detail:
          'decision existence is unchecked for '
          '${[for (final r in cited) r.citation].join(', ')}: no decision '
          'index was read; $kRestoreEvidenceDetail',
    ),
  };
}

/// Pure evaluator for the ten-row filing report.
///
/// This is the FILING COMPLETENESS contract of
/// `power_station#approval-is-the-stamp-the-grid-approved-label-retires` —
/// *"FILING COMPLETENESS in `lib/src/filing/`, MOUNT ELIGIBILITY in
/// `lib/src/code/`, neither subsuming the other, no third completeness
/// predicate minted"*. The unchecked cross-store arm is a refinement of this
/// contract's own dependency row, not an eleventh requirement and not a second
/// predicate, and the six VIABILITY rows live here for the same reason: they
/// judge the same filing, so they are rows of this contract rather than a
/// second checker beside it.
final class FilingContract {
  /// Creates the stateless evaluator.
  const FilingContract();

  /// Evaluates [bead] against its [dependencies] and the blockers wired by
  /// open cross-store link beads ([linkedBlockers]).
  ///
  /// [linkedBlockers] is NULL when the state store was not consulted, and an
  /// empty set when it was consulted and no link matched. The two differ: an
  /// unconsulted store cannot say a cross-store blocker is unwired, so its
  /// unwired foreign ids are reported through [kUnconsultedCrossStoreDetail]
  /// and never as missing outgoing edges.
  ///
  /// A blocker is DECLARED by a description segment that OPENS with
  /// `Blocked by` / `Blocked on` / `Depends on`; a mid-sentence mention of the
  /// phrase declares nothing. Within such a segment a `<prefix>-<tail>` token
  /// is a bead id when its prefix is the bead's own store or that of an
  /// already-wired blocker, or when its tail carries a digit.
  ///
  /// [evidence] carries what the six VIABILITY rows cannot decide from the
  /// text: the two shell parses of the validation plan, the all-status bead-id
  /// catalog, and the recorded-decision union. It is REQUIRED, not defaulted:
  /// a caller that forgets it would silently grade every citation as
  /// unchecked, and the whole point of these rows is that a gap is loud.
  ///
  /// This stays SYNCHRONOUS and PURE. Collecting the evidence is
  /// [FilingEvidenceSource]'s job; judging it is this one's.
  FilingReport evaluate(
    Bead bead,
    Iterable<BeadDependency> dependencies, {
    required FilingEvidence evidence,
    Set<String>? linkedBlockers,
  }) {
    final validationPlan = bead.metadata['validation_plan'];
    final plan = BeadTextField.validationPlan.read(bead);
    final localBlocks = {
      for (final edge in dependencies)
        if (edge.issueId == bead.id && edge.type == DependencyType.blocks)
          edge.dependsOnId,
    };
    final wired = {...localBlocks, ...?linkedBlockers};
    final ownPrefix = _prefixOf(bead.id);
    final knownPrefixes = <String>{
      ownPrefix,
      for (final id in wired) _prefixOf(id),
    }..remove('');
    final named = _namedBlockers(bead.description, knownPrefixes);
    final missing = named.difference(wired).toList()..sort();
    final dependencyPass = missing.isEmpty;
    // With the store unconsulted only the checked bead's OWN store can be
    // called missing; every foreign id is merely unchecked.
    final local = linkedBlockers != null
        ? missing
        : [
            for (final id in missing)
              if (_prefixOf(id) == ownPrefix) id,
          ];
    final hasUnconsulted = local.length != missing.length;
    final dependencyDetail = dependencyPass
        ? (named.isEmpty
              ? 'no local blockers named'
              : 'all named local blockers are wired')
        : [
            if (local.isNotEmpty)
              'missing outgoing blocks edges: ${local.join(', ')}',
            if (hasUnconsulted) kUnconsultedCrossStoreDetail,
          ].join('; ');
    return FilingReport(
      beadId: bead.id,
      approvalRevision: _approvalRevisionOf(
        bead,
        named: named,
        localBlocks: localBlocks,
        linkedBlockers: linkedBlockers,
      ),
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
          passed: dependencyPass,
          detail: dependencyDetail,
        ),
        _syntaxRow(plan, evidence.laneParse),
        _portabilityRow(plan, evidence.laneParse, evidence.portabilityParse),
        _repoRelativeRow(bead),
        _beadReferenceRow(
          bead,
          {ownPrefix, ...evidence.attachedPrefixes}..remove(''),
          evidence.beads,
        ),
        _releaseVersionRow(bead),
        _decisionReferenceRow(bead, evidence.decisions),
      ],
    );
  }
}

/// Collects the out-of-band facts the six viability rows are judged against.
///
/// READ-ONLY by construction, exactly as [SubstationBeadSource] is: one read
/// method, no mutation surface, so a filing check cannot write a store *by
/// type*. Tests implement this with Fakes.
abstract interface class FilingEvidenceSource {
  /// Gathers the evidence for [bead], whose own store is rooted at
  /// [storeRoot].
  ///
  /// A lookup nothing in the bead asks for is NOT performed: a bead citing no
  /// decision costs no index run, and a bead with no plan costs no shell.
  Future<FilingEvidence> collect({
    required Bead bead,
    required String storeRoot,
  });
}

/// The [FilingEvidenceSource] that looks NOTHING up.
///
/// For the caller that reads a bead and its [FilingReport.approvalRevision]
/// and nothing else — the mount-eligibility recheck. That revision digests
/// bead CONTENT, which the six viability rows contribute nothing to, so
/// collecting the evidence would buy two process spawns and a store read per
/// bead on a resident station's tick and change no answer that caller reads.
///
/// It is NOT a quiet pass: the rows it yields say UNCHECKED for every citation
/// the bead carries, so a caller that does start reading them sees a refusal
/// naming the missing source rather than a clean report it did not earn.
final class UnconsultedFilingEvidenceSource implements FilingEvidenceSource {
  /// Creates the source.
  const UnconsultedFilingEvidenceSource();

  @override
  Future<FilingEvidence> collect({
    required Bead bead,
    required String storeRoot,
  }) async => const FilingEvidence.unconsulted();
}

/// The default [FilingEvidenceSource]: two non-executing shell parses, one
/// all-status read per distinct attached store, and one roster-mode decision
/// index run over the bead's own anchors.
///
/// Every lookup is LAZY and every failure is NAMED. A store that refuses to be
/// read, an index that crashes, and a shell that cannot be spawned all produce
/// an unavailable catalog carrying the reason — never an empty one, because an
/// empty catalog would prove that a cited id or decision does not exist.
final class SystemFilingEvidenceSource implements FilingEvidenceSource {
  /// Creates the source over its four seams.
  ///
  /// [owningScope] is the substation whose store is being filed against; with
  /// none bound it is derived from the store root, whose basename names the
  /// substation and whose bead prefix is the checked bead's own. [attached] is
  /// the composed roster — the OTHER stores whose ids a bead may legitimately
  /// cite. [decisions] is the composing station's roster-mode index verb;
  /// absent, a cited decision is UNCHECKED rather than absent.
  const SystemFilingEvidenceSource({
    this.probe = const SystemValidationPlanProbe(),
    this.beads = const BdExportBeadSource(),
    this.owningScope,
    this.attached = const [],
    this.decisions,
  });

  /// The non-executing parse seam, shared with the Specify stage.
  final ValidationPlanProbe probe;

  /// The per-store read seam.
  final SubstationBeadSource beads;

  /// The substation that owns the checked store, when one is bound.
  final sdk.SubstationScope? owningScope;

  /// The other attached substations, in roster order.
  final List<sdk.SubstationScope> attached;

  /// The composing station's decision-index verb.
  final DecisionIndexSource? decisions;

  @override
  Future<FilingEvidence> collect({
    required Bead bead,
    required String storeRoot,
  }) async {
    final owning = _owningScopeFor(bead, storeRoot);
    final prefixes = <String>{
      _prefixOf(bead.id),
      if (owning != null) owning.prefix,
      for (final scope in attached) scope.prefix,
    }..remove('');

    return FilingEvidence(
      attachedPrefixes: prefixes,
      laneParse: await _parse(bead, storeRoot, kLaneShell),
      portabilityParse: await _portability(bead, storeRoot),
      beads: await _beadCatalog(bead, prefixes, owning),
      decisions: await _decisionCatalog(bead, storeRoot, owning),
    );
  }

  /// The scope that owns [storeRoot]. A blank root names no substation, and a
  /// derived scope is honest: the basename IS the substation name the roster
  /// uses, and the checked bead's own id carries its store's prefix.
  sdk.SubstationScope? _owningScopeFor(Bead bead, String storeRoot) {
    final bound = owningScope;
    if (bound != null) return bound;
    final root = storeRoot.trim();
    if (root.isEmpty) return null;
    return sdk.SubstationScope(
      name: p.basename(p.normalize(root)),
      root: root,
      prefix: _prefixOf(bead.id),
    );
  }

  Future<PlanParse?> _parse(Bead bead, String storeRoot, String shell) async {
    final plan = BeadTextField.validationPlan.read(bead);
    if (plan.trim().isEmpty) return null;
    return probe.parse(plan: plan, shell: shell, workingDirectory: storeRoot);
  }

  /// Dash is asked ONLY about a plan the lane shell already accepted: a plan
  /// that does not parse at all has nothing to say about portability.
  Future<PlanParse?> _portability(Bead bead, String storeRoot) async {
    final plan = BeadTextField.validationPlan.read(bead);
    if (plan.trim().isEmpty) return null;
    final lane = await probe.parse(
      plan: plan,
      shell: kLaneShell,
      workingDirectory: storeRoot,
    );
    if (lane is! PlanParsed) return null;
    return probe.parse(
      plan: plan,
      shell: kPortabilityShell,
      workingDirectory: storeRoot,
    );
  }

  /// Every read must ANSWER before an id is treated as absent — a partial
  /// union is an unavailable catalog, not a smaller one.
  Future<BeadIdCatalog?> _beadCatalog(
    Bead bead,
    Set<String> prefixes,
    sdk.SubstationScope? owning,
  ) async {
    final cited = beadIdReferences(bead, prefixes: prefixes);
    if (cited.every((slice) => slice.text == bead.id)) return null;
    if (owning == null) {
      return const BeadIdsUnavailable(
        'no owning substation is bound for the checked store',
      );
    }
    final stores = <String, sdk.SubstationScope>{owning.root: owning};
    for (final scope in attached) {
      stores.putIfAbsent(scope.root, () => scope);
    }
    final ids = <String>{};
    for (final scope in stores.values) {
      try {
        for (final found in await beads.read(scope)) {
          ids.add(found.id);
        }
      } on Object catch (error) {
        return BeadIdsUnavailable('${scope.name} (${scope.root}): $error');
      }
    }
    return BeadIdsRead(ids);
  }

  /// The roster-qualified surfaces the index is asked about are the bead's own
  /// file anchors. A bead naming none still gets an existence surface — its
  /// substation's `README.md` — because existence is a register-wide question
  /// and the verb needs some surface to be invoked over.
  Future<DecisionCatalog?> _decisionCatalog(
    Bead bead,
    String storeRoot,
    sdk.SubstationScope? owning,
  ) async {
    if (decisionReferences(bead).isEmpty) return null;
    if (owning == null) {
      return const DecisionsUnavailable(
        'no owning substation is bound for the checked store',
      );
    }
    final index = decisions;
    if (index == null) {
      return const DecisionsUnavailable(
        'no decision index is bound — compose one through '
        'SystemFilingEvidenceSource(decisions:)',
      );
    }
    final anchors = beadAnchors(bead).paths;
    final surfaces = anchors.isEmpty
        ? ['${owning.name}/README.md']
        : [for (final anchor in anchors) '${owning.name}/$anchor'];
    final DecisionGatherEvidence gather;
    try {
      gather = await index(storeRoot, surfaces, bead);
    } on Object catch (error) {
      return DecisionsUnavailable('decision index failed: $error');
    }
    for (final lookup in gather.decisionLookups) {
      if (lookup.state == EvidenceState.failed) {
        return DecisionsUnavailable(
          'decision index failed for ${lookup.surface}: ${lookup.error}',
        );
      }
    }
    if (gather.decisionLookups.isNotEmpty &&
        gather.decisionLookups.every(
          (lookup) => lookup.state == EvidenceState.unavailable,
        )) {
      return const DecisionsUnavailable('no decision lookup ran');
    }
    return DecisionsRead(
      identities: {
        for (final entry in gather.decisionEntries.values)
          entry.identity.toLowerCase(),
      },
      aliases: {
        for (final entry in gather.decisionEntries.values)
          if (legacyDecisionAlias(entry.slug) case final alias
              when alias.isNotEmpty)
            alias,
      },
    );
  }
}

/// UI-drivable filing lookup plus contract evaluation.
final class FilingService {
  /// Creates the service over the existing source extension and pure contract.
  const FilingService({
    this.source = const ExactSubstationBeadSource(),
    this.contract = const FilingContract(),
    this.links = const CrossLinkBlockerSource(),
    this.evidence = const SystemFilingEvidenceSource(),
  });

  /// Exact read source.
  final ExactSubstationBeadSource source;

  /// Pure contract evaluator.
  final FilingContract contract;

  /// The station state store's cross-link reader.
  final CrossLinkBlockerSource links;

  /// The viability-evidence collector. Read-only, and consulted exactly ONCE
  /// per inspection, after the exact bead read that tells it what to look up.
  final FilingEvidenceSource evidence;

  /// Reads [beadId] in the store rooted at [storeRoot] and evaluates it,
  /// returning BOTH the exact bead read and its report.
  ///
  /// This is the ONE read/evaluate path: the filing verb, the approve verb and
  /// the mount gate all reach the store through it, so the report's
  /// [FilingReport.approvalRevision] is always the digest of the very bead
  /// alongside it.
  ///
  /// [evidence] is collected ONCE, here, from the bead that was just read —
  /// after it, because what to look up is a question only the bead's own text
  /// answers.
  ///
  /// A null [stateRoot] leaves the cross-store link beads UNREAD, and that is
  /// what the contract is told: it receives null rather than an empty set, so
  /// an unconsulted lookup is never reported as an absent edge.
  Future<({Bead? bead, FilingReport report})> inspect({
    required String storeRoot,
    required String beadId,
    String? stateRoot,
  }) async {
    final read = await source.readExact(storeRoot: storeRoot, beadId: beadId);
    final bead = read.bead;
    if (bead == null) {
      return (bead: null, report: FilingReport.missing(beadId));
    }
    return (
      bead: bead,
      report: contract.evaluate(
        bead,
        read.dependencies,
        evidence: await evidence.collect(bead: bead, storeRoot: storeRoot),
        linkedBlockers: stateRoot == null
            ? null
            : await links.wiredFor(stateRoot: stateRoot, beadId: beadId),
      ),
    );
  }

  /// Checks [beadId] in the store rooted at [storeRoot] — [inspect] without
  /// the bead.
  Future<FilingReport> check({
    required String storeRoot,
    required String beadId,
    String? stateRoot,
  }) async => (await inspect(
    storeRoot: storeRoot,
    beadId: beadId,
    stateRoot: stateRoot,
  )).report;
}

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

import '../search/station_search.dart';

/// The four mechanical checks reported for a newly filed bead.
enum FilingRequirement {
  driveableType('driveable_type'),
  validationPlan('validation_plan'),
  acceptanceCriteria('acceptance_criteria'),
  dependencies('dependencies');

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

  /// Four rows for a found bead, in [FilingRequirement.values] order.
  final List<FilingRequirementRow> requirements;

  /// Lookup-level refusal; non-null reports never pass.
  final String? error;

  /// True only for a found bead with exactly four passing rows.
  bool get passed =>
      error == null &&
      requirements.length == FilingRequirement.values.length &&
      requirements.every((row) => row.passed);

  /// Structured command/UI representation.
  Map<String, Object> toJson() => {
    'id': beadId,
    'passed': passed,
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

/// Pure evaluator for the four-row filing report.
final class FilingContract {
  /// Creates the stateless evaluator.
  const FilingContract();

  /// Evaluates [bead] against its [dependencies] and blockers wired by open
  /// cross-store link beads ([linkedBlockers]).
  ///
  /// A blocker is DECLARED by a description segment that OPENS with
  /// `Blocked by` / `Blocked on` / `Depends on`; a mid-sentence mention of the
  /// phrase declares nothing. Within such a segment a `<prefix>-<tail>` token
  /// is a bead id when its prefix is the bead's own store or that of an
  /// already-wired blocker, or when its tail carries a digit.
  FilingReport evaluate(
    Bead bead,
    Iterable<BeadDependency> dependencies, {
    Set<String> linkedBlockers = const {},
  }) {
    final validationPlan = bead.metadata['validation_plan'];
    final wired = {
      for (final edge in dependencies)
        if (edge.issueId == bead.id && edge.type == DependencyType.blocks)
          edge.dependsOnId,
      ...linkedBlockers,
    };
    final knownPrefixes = <String>{
      _prefixOf(bead.id),
      for (final id in wired) _prefixOf(id),
    }..remove('');
    final named = _namedBlockers(bead.description, knownPrefixes);
    final missing = named.difference(wired).toList()..sort();
    final dependencyPass = missing.isEmpty;
    return FilingReport(
      beadId: bead.id,
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
          detail: dependencyPass
              ? (named.isEmpty
                    ? 'no local blockers named'
                    : 'all named local blockers are wired')
              : 'missing outgoing blocks edges: ${missing.join(', ')}',
        ),
      ],
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
  });

  /// Exact read source.
  final ExactSubstationBeadSource source;

  /// Pure contract evaluator.
  final FilingContract contract;

  /// The station state store's cross-link reader.
  final CrossLinkBlockerSource links;

  /// Checks [beadId] in the store rooted at [storeRoot].
  Future<FilingReport> check({
    required String storeRoot,
    required String beadId,
    String? stateRoot,
  }) async {
    final read = await source.readExact(storeRoot: storeRoot, beadId: beadId);
    final bead = read.bead;
    if (bead == null) return FilingReport.missing(beadId);
    final linked = stateRoot == null
        ? const <String>{}
        : await links.wiredFor(stateRoot: stateRoot, beadId: beadId);
    return contract.evaluate(bead, read.dependencies, linkedBlockers: linked);
  }
}

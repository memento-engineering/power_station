/// The SHADOW committee-selection policy (bead `pow-1nl.1.1`) — typed Dart, and
/// the ONLY place the selection rules live.
///
/// The two review committees are the station's largest recurring inference
/// spend: every round runs EVERY semantic lane, whether or not the change has
/// anything for that lane to say. This library asks the cheaper question —
/// *which lanes would this change actually have needed?* — beside the real
/// committee, and records the answer as a typed receipt. It is SHADOW-ONLY:
///
///  - the current full spec/code/docs committees still run and stay
///    authoritative; no semantic lane is suppressed;
///  - [CommitteeSelectionCapability] always resolves to [Ok] and NEVER emits a
///    grade, an [Escalate], a [Rewind] or a [Failed] — the cost optimizer must
///    never gate throughput;
///  - [CommitteeShadowRouteCapability] never converts, substitutes or waits on
///    the authoritative ruling: a rewind and an escalate come back as the
///    delegate's own verdict OBJECT, and an advance comes back with its own
///    payload intact, carrying the shadow's RESERVED `committeeShadow*`
///    bookkeeping entries beside it.
///
/// **Selection is stage-specific.** `spec_review` reasons over the round-stamped
/// discovery artifacts (intent, decisions, paths, prior art); `code_review`
/// reasons over the actual pinned `origin/<base>...HEAD` diff, supplemented by
/// the same dossier. Each stage digests its own evidence
/// ([CommitteeSelectionPolicy.evidenceDigestOf]) and the two digests can never
/// collide, because the stage wire value is hashed in.
///
/// **Classification is DETERMINISTIC and PER LANE.** One pure pass
/// ([CommitteeSelectionPolicy.classify]) emits exactly one
/// [CommitteeLaneDecision] for every active roster lane: elected or omitted,
/// with the stable [CommitteeLaneRule] that decided it. The change shape and
/// the evidence shape select the lanes — a docs-only or test-only diff elects
/// no regression-risk lane, a spec citing no decision elects no
/// decision-alignment lane, a later spec round re-runs only the lanes whose
/// facts moved, and a respec round re-runs ONLY the lanes that returned an
/// action grade while their siblings' verdicts are preserved
/// ([CommitteeShadowReceipt.preservedLanes]). The deterministic gates are
/// always elected. Uncertain evidence — a missing, empty or failed critical
/// input — elects the FULL committee as [CommitteeSelectionSource.fullFallback].
/// No inference runs anywhere in selection.
///
/// **The report vocabulary is REUSED, not re-minted** (Nico, 2026-09-04, gate
/// `tranquility-er3o99` D1/D2): [GateDisposition], [LaneReport] and
/// [UsageSample] arrive from `grid_trajectory`'s public barrel and are carried
/// BY COMPOSITION inside [CommitteeLaneReceipt] / [CommitteeUsageAccounting],
/// which add only the per-sample columns the trajectory AGGREGATE does not
/// expose. Nothing here touches that package's store mechanics (its connection,
/// DDL, appender or fence layers), so promoting the vocabulary later moves the
/// value types without dragging a database into `grid_assets`.
///
/// **The step RESULT is the durable copy.** Both artifacts are written under
/// the workspace, and the workspace is the per-round WORKTREE — reaped at
/// session close, taking the whole evidence packet with it. So the packet also
/// rides the result map the engine appends beside each step transition
/// ([committeeSelectionResultProjection], [committeeShadowResultProjection]):
/// the carrier a later fold ALREADY reads, COMPOSED — never a second sink and
/// never a new record type. The worktree file stays the IN-ROUND working
/// artifact (the observer's source, the posture the critic verdict already
/// has); the step result is the copy that outlives the round.
///
/// **The policy source of truth is THIS FILE.** There is no configuration
/// document, no reload path, no watcher and no second committee pipeline: the
/// rules are const values, the capability composes at the existing
/// `ServiceCapability` / `RouteCapability` / `Circuit` seams, and the policy
/// VALUE reaches a capability through the tree (ADR-0008 D-H: config = values in
/// the tree, impls = DI).
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:crypto/crypto.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_trajectory/grid_trajectory.dart'
    show GateDisposition, LaneReport, UsageSample;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'review_path.dart';

// ── identity ────────────────────────────────────────────────────────────────

/// This policy's version stamp — every selection carries it and every digest
/// hashes it in, so a policy-2 selection is never mistaken for a policy-1 one.
const String kCommitteeSelectionPolicyVersion = '2';

/// The wire version a run or receipt is WRITTEN at. Version 1 (the retained
/// pre-classifier corpus) still decodes; it carries no lane decisions, no
/// previous-round snapshot and no preserved lanes.
const int kCommitteeSelectionWireVersion = 2;

/// The step AND capability id the shadow selector mounts under, in all three
/// review circuits.
const String kCommitteeSelectionStep = 'committee-selection';

/// The step param naming the [CommitteeStage] a selector (or a shadowed route)
/// runs for.
const String kCommitteeSelectionStageParam = 'committeeStage';

/// The step param carrying the ACTIVE full committee roster, as a CSV of rubric
/// ids in declaration order. It arrives as a VALUE so this library never
/// imports a committee's roster constant.
const String kCommitteeFullRubricsParam = 'committeeFullRubrics';

/// The step param carrying the ACTIVE deterministic gate ids, as a CSV. These
/// lanes are ALWAYS elected, whatever the rest of the classification says.
const String kCommitteeGatingRubricsParam = 'committeeGatingRubrics';

/// The workspace-relative directory the shadow artifacts live in — deliberately
/// NOT `.grid/critique`, whose ownership stays with verdict freshness
/// (`power_station#a4-gate-integrity-3-bead-tg-bns-the-verdict-freshness-stamp`).
const String kCommitteeSelectionDir = '.grid/committee-selection';

/// The route payload key a respec stamps its invalidating grade under.
const String kCommitteeRouteGradeKey = 'grade';

/// The grade a spec route stamps when it RESPECS — the invalidating verdict
/// that makes the next round a targeted rewind.
const String kCommitteeRespecGrade = 'F';

// ── closed vocabularies ─────────────────────────────────────────────────────

/// Which committee a selection was computed for. The two stages read DIFFERENT
/// evidence, so the wire value is hashed into every digest.
enum CommitteeStage {
  /// The spec-readiness committee — evidence is the round-stamped discovery
  /// gather and dossier; there is no diff yet.
  specReview('spec_review'),

  /// The code (and docs) committee — evidence is the pinned branch diff plus
  /// that same dossier.
  codeReview('code_review');

  const CommitteeStage(this.wire);

  /// The stable JSON/param spelling.
  final String wire;

  /// The stage [wire] names, or null when it names none (fail-closed: an
  /// unknown stage is refused, never coerced to a default).
  static CommitteeStage? fromWire(Object? wire) => switch (wire) {
    'spec_review' => CommitteeStage.specReview,
    'code_review' => CommitteeStage.codeReview,
    _ => null,
  };
}

/// WHICH channel produced a selection.
enum CommitteeSelectionSource {
  /// The per-lane classification decided every lane; no inference ran.
  deterministic,

  /// A policy-1 selection the retired bounded classifier answered. Decoded for
  /// the retained corpus only — policy 2 never produces it.
  classifier,

  /// The evidence was too uncertain to omit anything — the current FULL
  /// committee is elected, unchanged.
  fullFallback;

  /// The stable JSON spelling.
  String get wire => name;

  /// The source [wire] names, or null when it names none.
  static CommitteeSelectionSource? fromWire(Object? wire) => switch (wire) {
    'deterministic' => CommitteeSelectionSource.deterministic,
    'classifier' => CommitteeSelectionSource.classifier,
    'fullFallback' => CommitteeSelectionSource.fullFallback,
    _ => null,
  };
}

/// What one policy-1 classifier call produced — retained so the version-1
/// corpus still decodes. Three of the four arms are NON-RESULTS: they are facts
/// about the call, never a judgement about the work, and none of them is ever a
/// letter grade.
enum CommitteeClassifierResultKind {
  /// A well-formed answer, entirely inside the allowlist and the active roster.
  selected,

  /// No output at all — an unwired seam, a blank answer, or a run that did not
  /// exit clean.
  missing,

  /// Output arrived but does not decode into the one legal shape.
  malformed,

  /// Output decoded, but names at least one rubric id we do not run.
  unknown;

  /// The stable JSON spelling.
  String get wire => name;

  /// The kind [wire] names, or null when it names none.
  static CommitteeClassifierResultKind? fromWire(Object? wire) =>
      switch (wire) {
        'selected' => CommitteeClassifierResultKind.selected,
        'missing' => CommitteeClassifierResultKind.missing,
        'malformed' => CommitteeClassifierResultKind.malformed,
        'unknown' => CommitteeClassifierResultKind.unknown,
        _ => null,
      };
}

// ── canonical hashing ───────────────────────────────────────────────────────

/// [value] as canonical JSON: every map's keys sorted, recursively, so two
/// structurally equal facts always render the same bytes.
String canonicalCommitteeJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) => switch (value) {
  final Map<String, Object?> map => {
    for (final key in map.keys.toList()..sort()) key: _canonical(map[key]),
  },
  final Map<Object?, Object?> map => {
    for (final key in map.keys.map((k) => '$k').toList()..sort())
      key: _canonical(map[key]),
  },
  final List<Object?> list => [for (final item in list) _canonical(item)],
  _ => value,
};

/// The SHA-256 of [value]'s canonical JSON — the one digest function every
/// identity in this library is derived with.
String committeeDigest(Object? value) =>
    sha256.convert(utf8.encode(canonicalCommitteeJson(value))).toString();

/// The engine-injected circuit round for this step, fail-safe to `0`.
///
/// Reads the engine's own reserved `grid.round` param. It is deliberately
/// SILENT on a miss: this is shadow telemetry, and a diagnostic on a step that
/// can never gate would be noise on every offline fixture.
///
/// The round is SESSION-LOCAL: `grid.round` restarts at zero when a governor
/// rework remounts the circuit. Prior-round comparison (the
/// `acceptance-unchanged` rule and targeted respec preservation) is therefore
/// delivered only for strictly later rounds inside the same mounted session; a
/// rework starts a new series with no previous round.
int committeeSelectionRound(StepArgs args) =>
    int.tryParse(
      (args.params['grid.round'] ?? kCommitteeSelectionStageParam).trim(),
    ) ??
    0;

/// The parent node path of [nodePath] (`a/b/route` → `a/b`) — how a join step
/// derives its sibling lane paths.
String committeeSelectionParentPath(String nodePath) {
  final cut = nodePath.lastIndexOf('/');
  return cut < 0 ? '' : nodePath.substring(0, cut);
}

/// The non-blank, trimmed members of a CSV step param, in order.
List<String> committeeCsv(String? raw) => [
  for (final part in (raw ?? '').split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

// ── the normalized stage evidence ───────────────────────────────────────────

/// The NORMALIZED facts a stage's rules and lane digests are computed over.
///
/// Deliberately stage-agnostic and source-agnostic: it names WHAT was found,
/// never WHERE from. That is what keeps this library free of the discovery,
/// committee, specify and docs libraries — the adapter in
/// `committee_selection_evidence.dart` is the only thing that knows those
/// shapes. Every list is a normalized, sorted, deduplicated set of canonical
/// evidence identities.
@immutable
final class CommitteeSelectionEvidence {
  /// Creates the normalized evidence; every list is copied, deduplicated and
  /// sorted so the digest is independent of the adapter's iteration order.
  CommitteeSelectionEvidence({
    required this.stage,
    required this.workBeadId,
    required this.round,
    Iterable<String> intent = const [],
    Iterable<String> acceptance = const [],
    Iterable<String> paths = const [],
    Iterable<String> decisions = const [],
    Iterable<String> priorArt = const [],
    Iterable<String> context = const [],
    Iterable<String> flags = const [],
    Iterable<String> changedPaths = const [],
    Iterable<String> missingEvidenceIds = const [],
    this.pinnedDiffDigest = '',
    this.truncated = false,
  }) : intent = _sortedSet(intent),
       acceptance = _sortedSet(acceptance),
       paths = _sortedSet(paths),
       decisions = _sortedSet(decisions),
       priorArt = _sortedSet(priorArt),
       context = _sortedSet(context),
       flags = _sortedSet(flags),
       changedPaths = _sortedSet(changedPaths),
       missingEvidenceIds = _sortedSet(missingEvidenceIds);

  /// The committee this evidence was gathered for.
  final CommitteeStage stage;

  /// The work bead the round belongs to.
  final String workBeadId;

  /// The discovery/committee round the evidence was stamped in.
  final int round;

  /// The bead's own INTENT — its title, description and design, bounded.
  final List<String> intent;

  /// The bead's acceptance criteria, bounded.
  final List<String> acceptance;

  /// The bead's resolved PATH anchors (each with whether it exists today).
  final List<String> paths;

  /// The roster-qualified decision lookups plus any declared departures.
  final List<String> decisions;

  /// The prior-art queries and their hits.
  final List<String> priorArt;

  /// The dossier's context notes.
  final List<String> context;

  /// The dossier's non-gating flags.
  final List<String> flags;

  /// The diff's changed target paths — `code_review` only; empty for
  /// `spec_review`, which has no diff by construction.
  final List<String> changedPaths;

  /// The SHA-256 of the COMPLETE pinned diff file, or empty when there is none.
  final String pinnedDiffDigest;

  /// Everything the adapter could NOT resolve, named. A missing artifact is a
  /// FACT here, never an exception and never synthetic clean evidence.
  final List<String> missingEvidenceIds;

  /// Whether any contributing artifact reported itself clipped.
  final bool truncated;

  /// True when nothing at all was resolved — an unknown ROUND, which elects the
  /// full committee ([committeeEvidenceIsUncertain]).
  bool get isEmpty =>
      intent.isEmpty &&
      acceptance.isEmpty &&
      paths.isEmpty &&
      decisions.isEmpty &&
      priorArt.isEmpty &&
      context.isEmpty &&
      flags.isEmpty &&
      changedPaths.isEmpty &&
      pinnedDiffDigest.isEmpty;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'stage': stage.wire,
    'workBeadId': workBeadId,
    'round': round,
    'intent': intent,
    'acceptance': acceptance,
    'paths': paths,
    'decisions': decisions,
    'priorArt': priorArt,
    'context': context,
    'flags': flags,
    'changedPaths': changedPaths,
    'pinnedDiffDigest': pinnedDiffDigest,
    'missingEvidenceIds': missingEvidenceIds,
    'truncated': truncated,
  };

  /// Decodes evidence STRICTLY: a non-map, an unknown stage wire, a negative or
  /// non-integer round, or a non-list fact lane yields null.
  static CommitteeSelectionEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final stage = CommitteeStage.fromWire(json['stage']);
    final round = json['round'];
    if (stage == null || round is! int || round < 0) return null;
    final intent = _stringList(json['intent']);
    final acceptance = _stringList(json['acceptance']);
    final paths = _stringList(json['paths']);
    final decisions = _stringList(json['decisions']);
    final priorArt = _stringList(json['priorArt']);
    final context = _stringList(json['context']);
    final flags = _stringList(json['flags']);
    final changedPaths = _stringList(json['changedPaths']);
    final missing = _stringList(json['missingEvidenceIds']);
    if (intent == null ||
        acceptance == null ||
        paths == null ||
        decisions == null ||
        priorArt == null ||
        context == null ||
        flags == null ||
        changedPaths == null ||
        missing == null) {
      return null;
    }
    return CommitteeSelectionEvidence(
      stage: stage,
      workBeadId: (json['workBeadId'] as String?)?.trim() ?? '',
      round: round,
      intent: intent,
      acceptance: acceptance,
      paths: paths,
      decisions: decisions,
      priorArt: priorArt,
      context: context,
      flags: flags,
      changedPaths: changedPaths,
      pinnedDiffDigest: (json['pinnedDiffDigest'] as String?)?.trim() ?? '',
      missingEvidenceIds: missing,
      truncated: json['truncated'] == true,
    );
  }
}

/// The pluggable source of one stage's [CommitteeSelectionEvidence].
///
/// Declared HERE and implemented in `committee_selection_evidence.dart`, which
/// is the only library that knows the discovery artifacts and the pinned diff.
abstract interface class CommitteeSelectionEvidenceSource {
  /// Reads the normalized evidence for [stage] at [workspaceDir]. A missing or
  /// malformed artifact is reported through
  /// [CommitteeSelectionEvidence.missingEvidenceIds], never thrown.
  CommitteeSelectionEvidence read({
    required CommitteeStage stage,
    required String workBeadId,
    required String workspaceDir,
  });
}

/// Derives the ABSOLUTE pinned-diff path under a workspace — injected rather
/// than imported, so this library stays free of `committee.dart`.
typedef CommitteePinnedDiffPath = String Function(String workspaceDir);

// ── the change-shape predicates ─────────────────────────────────────────────

/// Whether [path] is a TEST surface — a `test` root, a nested `test` directory,
/// or a Dart test file.
bool isCommitteeTestPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.startsWith('test/') ||
      normalized.contains('/test/') ||
      _basename(normalized).endsWith('_test.dart');
}

String _basename(String path) => path.split('/').last;

/// What ONE changed path is, for lane election.
enum CommitteeDiffPathKind {
  /// Prose or configuration ([isMetadataPath]) — nothing runs, nothing to
  /// cover.
  metadata,

  /// A test surface ([isCommitteeTestPath]) that is not prose.
  test,

  /// Anything else — the fail-to-code default, so an unlisted surface always
  /// elects the full semantic code committee.
  runtime,
}

/// [path]'s kind. Prose wins over the test predicate (a `test/README.md`
/// documents, it does not test); a test surface wins over configuration (a
/// `test/fixtures/x.json` is test data); everything else unlisted is runtime.
CommitteeDiffPathKind committeeDiffPathKindOf(String path) {
  if (isDocsPath(path)) return CommitteeDiffPathKind.metadata;
  if (isCommitteeTestPath(path)) return CommitteeDiffPathKind.test;
  if (isMetadataPath(path)) return CommitteeDiffPathKind.metadata;
  return CommitteeDiffPathKind.runtime;
}

/// Whether one normalized decision fact NAMES a decision — a resolved
/// `decision:` body or a declared `departure:`. A `surface:` lookup record is
/// not a citation: a completed lookup that found nothing is a real empty
/// result.
bool isCommitteeCitedDecision(String fact) =>
    fact.startsWith('decision:') || fact.startsWith('departure:');

/// The missing-evidence ids that make ANY stage's facts too uncertain to omit
/// a lane.
const Set<String> kCommitteeCriticalEvidenceIds = {
  'workspace',
  'evidence-source',
  'selection-run',
};

/// The missing-evidence ids that additionally make `spec_review` facts
/// uncertain: without the gather there is no decision lookup to trust.
const Set<String> kCommitteeSpecCriticalEvidenceIds = {
  'anchors',
  'anchors:work-bead-mismatch',
  'round',
};

/// Whether [evidence] is too uncertain to omit any lane — the loud FULL
/// FALLBACK trigger.
///
/// Every stage: nothing resolved at all, or a critical input
/// ([kCommitteeCriticalEvidenceIds]) missing. `spec_review`: the gather is
/// absent or foreign ([kCommitteeSpecCriticalEvidenceIds]), or any decision
/// lookup failed or was unavailable (`decisions:<surface>`) — an empty union is
/// a real result, a crashed lookup is not. `code_review`: the pinned diff is
/// missing, clipped or names no target (`pinned-diff…`), or there is no diff
/// digest or changed path to classify.
bool committeeEvidenceIsUncertain(CommitteeSelectionEvidence evidence) {
  if (evidence.isEmpty) return true;
  for (final id in evidence.missingEvidenceIds) {
    if (kCommitteeCriticalEvidenceIds.contains(id)) return true;
    final stageCritical = switch (evidence.stage) {
      CommitteeStage.specReview =>
        kCommitteeSpecCriticalEvidenceIds.contains(id) ||
            id.startsWith('decisions:'),
      CommitteeStage.codeReview => id.startsWith('pinned-diff'),
    };
    if (stageCritical) return true;
  }
  return switch (evidence.stage) {
    CommitteeStage.specReview => false,
    CommitteeStage.codeReview =>
      evidence.pinnedDiffDigest.isEmpty || evidence.changedPaths.isEmpty,
  };
}

// ── the lane rules ──────────────────────────────────────────────────────────

/// Whether a lane would run.
enum CommitteeLaneDisposition {
  /// The lane runs.
  elected,

  /// The lane does not run — its rule names why.
  omitted;

  /// The stable JSON spelling.
  String get wire => name;

  /// The disposition [wire] names, or null when it names none.
  static CommitteeLaneDisposition? fromWire(Object? wire) => switch (wire) {
    'elected' => CommitteeLaneDisposition.elected,
    'omitted' => CommitteeLaneDisposition.omitted,
    _ => null,
  };
}

/// The CLOSED set of reasons one lane is elected or omitted — the whole
/// policy, as const values. A rule FIXES its disposition, so a decision can
/// never be "omitted because the change is runtime".
enum CommitteeLaneRule {
  /// A deterministic gate: always elected.
  gateAlways('gate-always', CommitteeLaneDisposition.elected),

  /// The evidence was uncertain ([committeeEvidenceIsUncertain]): every lane
  /// is elected.
  fullFallback('full-fallback', CommitteeLaneDisposition.elected),

  /// A lane this policy has no rule for: elected, never silently dropped.
  unrecognizedLane('unrecognized-lane', CommitteeLaneDisposition.elected),

  /// `code_review`: the diff touches runtime behaviour — every semantic code
  /// lane runs.
  runtimeChange('runtime-change', CommitteeLaneDisposition.elected),

  /// `code_review`: a non-runtime diff that touches prose or configuration —
  /// adherence still has something to judge.
  metadataChange('metadata-change', CommitteeLaneDisposition.elected),

  /// `code_review`: a non-runtime diff that touches tests — coverage still has
  /// something to judge.
  testChange('test-change', CommitteeLaneDisposition.elected),

  /// `code_review`: no runtime path changed, so there is nothing to regress.
  noRuntimeChange('no-runtime-change', CommitteeLaneDisposition.omitted),

  /// `code_review`: a non-runtime diff with no test path, so there is no
  /// coverage to grade.
  noTestChange('no-test-change', CommitteeLaneDisposition.omitted),

  /// `code_review`: every changed path is a test surface, so there is no
  /// specified behaviour for adherence to judge.
  testOnlyChange('test-only-change', CommitteeLaneDisposition.omitted),

  /// `spec_review`: the first graded round of a spec — the lane has never
  /// judged it.
  firstRound('first-round', CommitteeLaneDisposition.elected),

  /// `spec_review`: the evidence names a decision or a declared departure.
  citedDecision('cited-decision', CommitteeLaneDisposition.elected),

  /// `spec_review`: the complete decision lookup names no decision.
  noCitedDecision('no-cited-decision', CommitteeLaneDisposition.omitted),

  /// `spec_review`: a later round whose facts for this lane moved since the
  /// previous graded round.
  factsChanged('facts-changed', CommitteeLaneDisposition.elected),

  /// `spec_review`: the lane's facts did not move, but the previous round
  /// recorded no verdict for it to carry forward.
  noPriorVerdict('no-prior-verdict', CommitteeLaneDisposition.elected),

  /// `spec_review`: a later round whose facts for this lane are identical to
  /// the previous graded round — its verdict is preserved.
  factsUnchanged('facts-unchanged', CommitteeLaneDisposition.omitted),

  /// `spec_review`: the acceptance evidence is byte-identical to the previous
  /// graded round — the testability verdict is preserved.
  acceptanceUnchanged('acceptance-unchanged', CommitteeLaneDisposition.omitted),

  /// `spec_review`: a respec round, and this lane returned an action grade in
  /// the round that respecced — it re-runs.
  targetedRespecAction(
    'targeted-respec-action',
    CommitteeLaneDisposition.elected,
  ),

  /// `spec_review`: a respec round, and this lane did NOT return an action
  /// grade — its verdict is preserved.
  targetedRespecPreserved(
    'targeted-respec-preserved',
    CommitteeLaneDisposition.omitted,
  );

  const CommitteeLaneRule(this.id, this.disposition);

  /// This rule's stable id — persisted in every lane decision.
  final String id;

  /// What this rule does to its lane.
  final CommitteeLaneDisposition disposition;

  /// Whether an omission under this rule CARRIES the previous round's verdict
  /// forward rather than declaring the lane irrelevant.
  bool get preservesPriorVerdict => switch (this) {
    CommitteeLaneRule.factsUnchanged ||
    CommitteeLaneRule.acceptanceUnchanged ||
    CommitteeLaneRule.targetedRespecPreserved => true,
    CommitteeLaneRule.gateAlways ||
    CommitteeLaneRule.fullFallback ||
    CommitteeLaneRule.unrecognizedLane ||
    CommitteeLaneRule.runtimeChange ||
    CommitteeLaneRule.metadataChange ||
    CommitteeLaneRule.testChange ||
    CommitteeLaneRule.noRuntimeChange ||
    CommitteeLaneRule.noTestChange ||
    CommitteeLaneRule.testOnlyChange ||
    CommitteeLaneRule.firstRound ||
    CommitteeLaneRule.citedDecision ||
    CommitteeLaneRule.noCitedDecision ||
    CommitteeLaneRule.factsChanged ||
    CommitteeLaneRule.noPriorVerdict ||
    CommitteeLaneRule.targetedRespecAction => false,
  };

  /// The rule [id] names, or null when it names none.
  static CommitteeLaneRule? fromId(Object? id) {
    for (final rule in CommitteeLaneRule.values) {
      if (rule.id == id) return rule;
    }
    return null;
  }
}

/// ONE active lane's election — its rubric id, its disposition, and the rule
/// that decided it.
@immutable
final class CommitteeLaneDecision {
  /// Creates the decision; the disposition follows from [rule].
  const CommitteeLaneDecision({required this.rubricId, required this.rule});

  /// The lane.
  final String rubricId;

  /// The rule that decided it.
  final CommitteeLaneRule rule;

  /// Whether the lane runs.
  CommitteeLaneDisposition get disposition => rule.disposition;

  /// Whether the lane runs, as a bool.
  bool get elected => disposition == CommitteeLaneDisposition.elected;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'rubricId': rubricId,
    'disposition': disposition.wire,
    'rule': rule.id,
  };

  /// Decodes a decision STRICTLY: a blank rubric id, an unknown rule, or a
  /// disposition that disagrees with its rule yields null.
  static CommitteeLaneDecision? fromJson(Object? json) {
    if (json is! Map) return null;
    final rubricId = (json['rubricId'] as String?)?.trim() ?? '';
    final rule = CommitteeLaneRule.fromId(json['rule']);
    final disposition = CommitteeLaneDisposition.fromWire(json['disposition']);
    if (rubricId.isEmpty || rule == null || disposition != rule.disposition) {
      return null;
    }
    return CommitteeLaneDecision(rubricId: rubricId, rule: rule);
  }
}

// ── the selection ───────────────────────────────────────────────────────────

/// ONE stage's hypothetical committee — what the shadow WOULD have run.
@immutable
final class CommitteeSelection {
  /// Creates the selection; every collection is copied.
  CommitteeSelection({
    required this.policyVersion,
    required this.evidenceDigest,
    required Iterable<String> matchedRuleIds,
    required Iterable<String> selectedRubricIds,
    required this.source,
    required Map<String, String> laneInputDigests,
    Iterable<CommitteeLaneDecision> laneDecisions = const [],
  }) : matchedRuleIds = List.unmodifiable(matchedRuleIds),
       selectedRubricIds = List.unmodifiable(selectedRubricIds),
       laneInputDigests = Map.unmodifiable(laneInputDigests),
       laneDecisions = List.unmodifiable(laneDecisions);

  /// The policy version that produced this selection.
  final String policyVersion;

  /// The digest of the stage evidence it was computed over.
  final String evidenceDigest;

  /// The distinct rule ids that decided a lane, in roster order — the per-rule
  /// fold key. (A policy-1 selection recorded its additive rule ids here.)
  final List<String> matchedRuleIds;

  /// The hypothetical roster, in the ACTIVE committee's declaration order.
  final List<String> selectedRubricIds;

  /// Which channel produced it.
  final CommitteeSelectionSource source;

  /// Every ACTIVE lane's input digest — selected or omitted, so a later
  /// comparison can tell a lane whose inputs changed from one whose did not.
  final Map<String, String> laneInputDigests;

  /// ONE decision per active roster lane, in roster order: elected or omitted,
  /// and the rule that decided it. Empty only for a policy-1 selection.
  final List<CommitteeLaneDecision> laneDecisions;

  /// The decision for [rubricId], or null when this selection has none.
  CommitteeLaneDecision? decisionFor(String rubricId) {
    for (final decision in laneDecisions) {
      if (decision.rubricId == rubricId) return decision;
    }
    return null;
  }

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'policyVersion': policyVersion,
    'evidenceDigest': evidenceDigest,
    'matchedRuleIds': matchedRuleIds,
    'selectedRubricIds': selectedRubricIds,
    'source': source.wire,
    'laneInputDigests': laneInputDigests,
    // A policy-1 selection decided no lanes and keeps its policy-1 shape.
    if (laneDecisions.isNotEmpty)
      'laneDecisions': [
        for (final decision in laneDecisions) decision.toJson(),
      ],
  };

  /// Decodes a selection STRICTLY; an unknown source wire, a non-string lane
  /// digest, a missing digest, or any malformed lane decision yields null. An
  /// absent `laneDecisions` list is the policy-1 shape and decodes empty.
  static CommitteeSelection? fromJson(Object? json) {
    if (json is! Map) return null;
    final source = CommitteeSelectionSource.fromWire(json['source']);
    final matched = _stringList(json['matchedRuleIds']);
    final selected = _stringList(json['selectedRubricIds']);
    final digests = _stringMap(json['laneInputDigests']);
    final policyVersion = (json['policyVersion'] as String?)?.trim() ?? '';
    final evidenceDigest = (json['evidenceDigest'] as String?)?.trim() ?? '';
    if (source == null ||
        matched == null ||
        selected == null ||
        digests == null ||
        policyVersion.isEmpty ||
        evidenceDigest.isEmpty) {
      return null;
    }
    final rawDecisions = json['laneDecisions'] ?? const <Object?>[];
    if (rawDecisions is! List) return null;
    final decisions = <CommitteeLaneDecision>[];
    for (final entry in rawDecisions) {
      final decision = CommitteeLaneDecision.fromJson(entry);
      if (decision == null) return null;
      decisions.add(decision);
    }
    return CommitteeSelection(
      policyVersion: policyVersion,
      evidenceDigest: evidenceDigest,
      matchedRuleIds: matched,
      selectedRubricIds: selected,
      source: source,
      laneInputDigests: digests,
      laneDecisions: decisions,
    );
  }
}

/// The pure policy: the per-lane classification, the digests and the
/// composition of a [CommitteeSelection]. Immutable, const-constructible and
/// cache-free — it is a VALUE the tree carries, re-read on every build
/// (ADR-0008 D-H).
@immutable
final class CommitteeSelectionPolicy {
  /// Creates the policy at [policyVersion].
  const CommitteeSelectionPolicy({
    this.policyVersion = kCommitteeSelectionPolicyVersion,
  });

  /// The version stamped into every selection and hashed into every digest.
  final String policyVersion;

  /// The ACTIVE semantic lanes — the full roster minus the deterministic gates,
  /// in the roster's declaration order.
  List<String> semanticRubricIds({
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
  }) => [
    for (final id in fullRubricIds)
      if (!gatingRubricIds.contains(id)) id,
  ];

  /// The digest of one stage's evidence — the policy version and the stage wire
  /// value are hashed in, so identical facts under two stages never collide.
  String evidenceDigestOf(CommitteeSelectionEvidence evidence) =>
      committeeDigest({
        'policyVersion': policyVersion,
        'stage': evidence.stage.wire,
        'evidence': evidence.toJson(),
      });

  /// Every ACTIVE lane's input digest, selected or omitted. The rubric id is
  /// hashed in, so two lanes reading the same facts still differ.
  Map<String, String> laneInputDigests({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
  }) => {
    for (final id in fullRubricIds)
      id: committeeDigest({
        'policyVersion': policyVersion,
        'stage': evidence.stage.wire,
        'rubric': id,
        'facts': committeeLaneFacts(id, evidence, gatingRubricIds),
      }),
  };

  /// ONE decision per active roster lane, in roster order — the whole
  /// classification, PURE over its arguments.
  ///
  /// Precedence, per lane: a gate is `gate-always`; uncertain evidence
  /// ([committeeEvidenceIsUncertain]) is `full-fallback`; otherwise the stage
  /// decides. `code_review` reads the pinned diff's path kinds
  /// ([committeeDiffPathKindOf]). `spec_review` reads [previous]: a respec
  /// round (the previous route stamped [kCommitteeRespecGrade] and some
  /// semantic lane returned an action grade) re-runs only those action lanes;
  /// a first round elects every lane but decision-alignment, which needs a
  /// cited decision; a later round re-runs only the lanes whose facts moved.
  /// An omission that carries a verdict forward needs that verdict to exist —
  /// a lane the previous round never graded is elected `no-prior-verdict`.
  List<CommitteeLaneDecision> classifyLanes({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
    CommitteePreviousRound? previous,
  }) {
    final uncertain = committeeEvidenceIsUncertain(evidence);
    final kinds = {
      for (final path in evidence.changedPaths) committeeDiffPathKindOf(path),
    };
    final semantic = semanticRubricIds(
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
    );
    final respec =
        previous != null &&
        previous.isRespec &&
        previous.actionLaneIds.any(semantic.contains);
    return [
      for (final id in fullRubricIds)
        CommitteeLaneDecision(
          rubricId: id,
          rule: gatingRubricIds.contains(id)
              ? CommitteeLaneRule.gateAlways
              : uncertain
              ? CommitteeLaneRule.fullFallback
              : switch (evidence.stage) {
                  CommitteeStage.codeReview => _codeRule(id, kinds),
                  CommitteeStage.specReview => _specRule(
                    id,
                    evidence: evidence,
                    gatingRubricIds: gatingRubricIds,
                    previous: previous,
                    targetedRespec: respec,
                  ),
                },
        ),
    ];
  }

  CommitteeLaneRule _codeRule(String id, Set<CommitteeDiffPathKind> kinds) {
    final runtime = kinds.contains(CommitteeDiffPathKind.runtime);
    return switch (id) {
      'spec-adherence' =>
        runtime
            ? CommitteeLaneRule.runtimeChange
            : kinds.contains(CommitteeDiffPathKind.metadata)
            ? CommitteeLaneRule.metadataChange
            : CommitteeLaneRule.testOnlyChange,
      'regression-risk' =>
        runtime
            ? CommitteeLaneRule.runtimeChange
            : CommitteeLaneRule.noRuntimeChange,
      'test-coverage' =>
        runtime
            ? CommitteeLaneRule.runtimeChange
            : kinds.contains(CommitteeDiffPathKind.test)
            ? CommitteeLaneRule.testChange
            : CommitteeLaneRule.noTestChange,
      _ => CommitteeLaneRule.unrecognizedLane,
    };
  }

  CommitteeLaneRule _specRule(
    String id, {
    required CommitteeSelectionEvidence evidence,
    required List<String> gatingRubricIds,
    required CommitteePreviousRound? previous,
    required bool targetedRespec,
  }) {
    if (!_kSpecSemanticLanes.contains(id)) {
      return CommitteeLaneRule.unrecognizedLane;
    }
    // A preserving omission is only honest when there is a verdict to carry.
    CommitteeLaneRule preserving(CommitteeLaneRule rule) =>
        previous!.hasVerdictFor(id) ? rule : CommitteeLaneRule.noPriorVerdict;

    if (previous != null && targetedRespec) {
      return previous.actionLaneIds.contains(id)
          ? CommitteeLaneRule.targetedRespecAction
          : preserving(CommitteeLaneRule.targetedRespecPreserved);
    }
    final cited = evidence.decisions.any(isCommitteeCitedDecision);
    if (id == 'decision-alignment' && !cited) {
      return CommitteeLaneRule.noCitedDecision;
    }
    if (previous == null) {
      return id == 'decision-alignment'
          ? CommitteeLaneRule.citedDecision
          : CommitteeLaneRule.firstRound;
    }
    final unchanged =
        canonicalCommitteeJson(
          committeeLaneFacts(id, evidence, gatingRubricIds),
        ) ==
        canonicalCommitteeJson(
          committeeLaneFacts(id, previous.evidence, gatingRubricIds),
        );
    if (!unchanged) return CommitteeLaneRule.factsChanged;
    return preserving(
      id == 'acceptance-testability'
          ? CommitteeLaneRule.acceptanceUnchanged
          : CommitteeLaneRule.factsUnchanged,
    );
  }

  /// The selection for [evidence] — [classifyLanes], composed. Every lane is
  /// decided, so the source is [CommitteeSelectionSource.deterministic] unless
  /// the evidence was uncertain.
  CommitteeSelection classify({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
    CommitteePreviousRound? previous,
  }) {
    final decisions = classifyLanes(
      evidence: evidence,
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
      previous: previous,
    );
    return _compose(
      evidence: evidence,
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
      source: committeeEvidenceIsUncertain(evidence)
          ? CommitteeSelectionSource.fullFallback
          : CommitteeSelectionSource.deterministic,
      decisions: decisions,
    );
  }

  /// The FULL current committee — what an absent, stale or unreadable selection
  /// run means when the route joins.
  CommitteeSelection selectFullFallback({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
  }) => _compose(
    evidence: evidence,
    fullRubricIds: fullRubricIds,
    gatingRubricIds: gatingRubricIds,
    source: CommitteeSelectionSource.fullFallback,
    decisions: [
      for (final id in fullRubricIds)
        CommitteeLaneDecision(
          rubricId: id,
          rule: gatingRubricIds.contains(id)
              ? CommitteeLaneRule.gateAlways
              : CommitteeLaneRule.fullFallback,
        ),
    ],
  );

  CommitteeSelection _compose({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
    required CommitteeSelectionSource source,
    required List<CommitteeLaneDecision> decisions,
  }) => CommitteeSelection(
    policyVersion: policyVersion,
    evidenceDigest: evidenceDigestOf(evidence),
    matchedRuleIds: {for (final decision in decisions) decision.rule.id},
    selectedRubricIds: [
      for (final decision in decisions)
        if (decision.elected) decision.rubricId,
    ],
    source: source,
    laneInputDigests: laneInputDigests(
      evidence: evidence,
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
    ),
    laneDecisions: decisions,
  );
}

/// The spec committee's semantic lanes this policy has rules for.
const Set<String> _kSpecSemanticLanes = {
  'coherence',
  'decision-alignment',
  'acceptance-testability',
  'plan-completeness',
};

/// The FACTS one lane actually reads — what its input digest hashes and what a
/// later spec round compares against the previous one. An unrecognised ACTIVE
/// lane hashes the COMPLETE stage evidence, so a lane somebody adds is explicit
/// rather than silently digested over nothing.
///
/// `acceptance-testability` reads the acceptance criteria ALONE: an unchanged
/// criteria set carries its testability verdict forward even when the design
/// around it moved. `decision-alignment` reads the intent beside the decisions,
/// because a rewritten design can depart from a decision that did not change.
Map<String, Object?> committeeLaneFacts(
  String rubricId,
  CommitteeSelectionEvidence evidence,
  List<String> gatingRubricIds,
) => switch (rubricId) {
  'spec-validation' => {
    'intent': evidence.intent,
    'acceptance': evidence.acceptance,
    'paths': evidence.paths,
  },
  'coherence' => {
    'intent': evidence.intent,
    'paths': evidence.paths,
    'priorArt': evidence.priorArt,
  },
  'decision-alignment' => {
    'intent': evidence.intent,
    'decisions': evidence.decisions,
    'paths': evidence.paths,
  },
  'acceptance-testability' => {'acceptance': evidence.acceptance},
  'plan-completeness' => {
    'intent': evidence.intent,
    'paths': evidence.paths,
    'priorArt': evidence.priorArt,
  },
  'spec-adherence' => {
    'pinnedDiffDigest': evidence.pinnedDiffDigest,
    'intent': evidence.intent,
    'acceptance': evidence.acceptance,
  },
  'regression-risk' => {
    'pinnedDiffDigest': evidence.pinnedDiffDigest,
    'paths': evidence.paths,
    'decisions': evidence.decisions,
    'priorArt': evidence.priorArt,
  },
  'test-coverage' => {
    'pinnedDiffDigest': evidence.pinnedDiffDigest,
    'changedPaths': evidence.changedPaths,
    'acceptance': evidence.acceptance,
  },
  _ when gatingRubricIds.contains(rubricId) => {
    'pinnedDiffDigest': evidence.pinnedDiffDigest,
    'changedPaths': evidence.changedPaths,
  },
  _ => {'evidence': evidence.toJson()},
};

/// The policy every circuit mounts by default.
const CommitteeSelectionPolicy kCommitteeSelectionPolicy =
    CommitteeSelectionPolicy();

// ── the policy-1 classifier provenance ──────────────────────────────────────

/// ONE policy-1 classifier call, recorded — including the ones that produced
/// nothing. Policy 2 runs no classifier, so a current run carries none; the
/// type remains so the retained version-1 corpus still decodes and accounts.
@immutable
final class CommitteeClassifierAttempt {
  /// Creates the record.
  CommitteeClassifierAttempt({
    required this.attempt,
    required this.kind,
    required this.usage,
    Iterable<String> acceptedRubricIds = const [],
    Iterable<String> rejectedRubricIds = const [],
    this.outputDigest = '',
    this.reason = '',
    this.launched = false,
    this.model,
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.premiumRequests,
    this.numTurns,
    this.harnessDurationMs,
  }) : acceptedRubricIds = List.unmodifiable(acceptedRubricIds),
       rejectedRubricIds = List.unmodifiable(rejectedRubricIds);

  /// The 1-based attempt number within ONE capability invocation.
  final int attempt;

  /// The typed outcome — never a grade.
  final CommitteeClassifierResultKind kind;

  /// This attempt's usage, in trajectory's own vocabulary.
  final UsageSample usage;

  /// The lanes the answer named and we accepted.
  final List<String> acceptedRubricIds;

  /// The lanes that made an answer unknown.
  final List<String> rejectedRubricIds;

  /// The SHA-256 of the raw answer text (empty when there was none).
  final String outputDigest;

  /// Why a non-result happened, when we know (an unwired seam, a refused
  /// config, a throwing adapter). Provenance only.
  final String reason;

  /// Whether this attempt actually reached the classifier seam. `false` means
  /// nothing was spent — no live workspace, no resolvable cheap environment, a
  /// refused render — so its accounting contributes KNOWN ZEROS rather than a
  /// blank that would have to null a total.
  final bool launched;

  /// The model the ladder stamped for this call.
  final String? model;

  /// `usage.input_tokens`, when the harness reported one.
  final int? tokensIn;

  /// `usage.output_tokens`, when the harness reported one.
  final int? tokensOut;

  /// `total_cost_usd`, when the harness reported one.
  final num? costUsd;

  /// `usage.premiumRequests`, when the harness reported one.
  final num? premiumRequests;

  /// `num_turns`, when the harness reported one.
  final int? numTurns;

  /// The harness-observed wall clock, when it reported one.
  final int? harnessDurationMs;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'attempt': attempt,
    'kind': kind.wire,
    'usage': _usageSampleToJson(usage),
    'acceptedRubricIds': acceptedRubricIds,
    'rejectedRubricIds': rejectedRubricIds,
    'outputDigest': outputDigest,
    'reason': reason,
    'launched': launched,
    'model': model,
    'tokensIn': tokensIn,
    'tokensOut': tokensOut,
    'costUsd': costUsd,
    'premiumRequests': premiumRequests,
    'numTurns': numTurns,
    'harnessDurationMs': harnessDurationMs,
  };

  /// Decodes one attempt STRICTLY; an unknown kind wire, a missing attempt
  /// number or a malformed usage sample yields null.
  static CommitteeClassifierAttempt? fromJson(Object? json) {
    if (json is! Map) return null;
    final attempt = json['attempt'];
    final kind = CommitteeClassifierResultKind.fromWire(json['kind']);
    final usage = _usageSampleFromJson(json['usage']);
    final accepted = _stringList(json['acceptedRubricIds']);
    final rejected = _stringList(json['rejectedRubricIds']);
    if (attempt is! int || kind == null || usage == null) return null;
    if (accepted == null || rejected == null) return null;
    return CommitteeClassifierAttempt(
      attempt: attempt,
      kind: kind,
      usage: usage,
      acceptedRubricIds: accepted,
      rejectedRubricIds: rejected,
      outputDigest: (json['outputDigest'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      launched: json['launched'] == true,
      model: json['model'] as String?,
      tokensIn: _asInt(json['tokensIn']),
      tokensOut: _asInt(json['tokensOut']),
      costUsd: _asNum(json['costUsd']),
      premiumRequests: _asNum(json['premiumRequests']),
      numTurns: _asInt(json['numTurns']),
      harnessDurationMs: _asInt(json['harnessDurationMs']),
    );
  }
}

// ── the persisted run ───────────────────────────────────────────────────────

/// ONE selector invocation's whole durable state — the selection, the evidence
/// it was computed over, the previous round it was compared against, and (for
/// a policy-1 run) every classifier attempt.
@immutable
final class CommitteeSelectionRun {
  /// Creates the run; every collection is copied.
  CommitteeSelectionRun({
    required this.policyVersion,
    required this.stage,
    required this.workBeadId,
    required this.round,
    required this.nodePath,
    required this.selection,
    required this.evidence,
    required Iterable<String> fullRubricIds,
    required Iterable<String> gatingRubricIds,
    Iterable<CommitteeClassifierAttempt> attempts = const [],
    Iterable<String> missingFields = const [],
    this.previous,
    this.wireVersion = kCommitteeSelectionWireVersion,
  }) : fullRubricIds = List.unmodifiable(fullRubricIds),
       gatingRubricIds = List.unmodifiable(gatingRubricIds),
       attempts = List.unmodifiable(attempts),
       missingFields = List.unmodifiable(missingFields);

  /// The policy version that produced it.
  final String policyVersion;

  /// The committee it was computed for.
  final CommitteeStage stage;

  /// The work bead — half of the freshness check a route makes.
  final String workBeadId;

  /// The circuit round — the other half.
  final int round;

  /// The selector step's own node path.
  final String nodePath;

  /// The hypothetical committee.
  final CommitteeSelection selection;

  /// The normalized evidence, retained so a replay needs no source at all.
  final CommitteeSelectionEvidence evidence;

  /// The ACTIVE full roster this run was computed against.
  final List<String> fullRubricIds;

  /// The ACTIVE deterministic gates.
  final List<String> gatingRubricIds;

  /// Every policy-1 classifier attempt, in call order. Always empty for a
  /// policy-2 run.
  final List<CommitteeClassifierAttempt> attempts;

  /// Everything this run could not do, named. Shadow-only: it never gates.
  final List<String> missingFields;

  /// The previous round of the same bead and stage this run was classified
  /// against, captured BEFORE the run was written — null on a first round.
  final CommitteePreviousRound? previous;

  /// The wire version this run was recorded at (1 for the retained corpus).
  final int wireVersion;

  /// Whether [workBeadId]/[round]/[stage] match the joining route's.
  bool isFreshFor({
    required CommitteeStage stage,
    required String workBeadId,
    required int round,
  }) =>
      this.stage == stage &&
      this.workBeadId == workBeadId &&
      this.round == round;

  /// The wire shape. A version-1 run keeps its version-1 shape.
  Map<String, Object?> toJson() => {
    'version': wireVersion,
    'policyVersion': policyVersion,
    'stage': stage.wire,
    'workBeadId': workBeadId,
    'round': round,
    'nodePath': nodePath,
    'selection': selection.toJson(),
    'evidence': evidence.toJson(),
    'fullRubricIds': fullRubricIds,
    'gatingRubricIds': gatingRubricIds,
    'attempts': [for (final attempt in attempts) attempt.toJson()],
    'missingFields': missingFields,
    if (wireVersion >= 2) 'previous': previous?.toJson(),
  };

  /// Decodes a run STRICTLY: any `version` but 1 or 2, an unknown stage, a
  /// negative round, a refused selection/evidence/previous round, or ANY
  /// malformed attempt yields null. A version-2 run must decide every roster
  /// lane exactly once, in roster order.
  static CommitteeSelectionRun? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    if (version != 1 && version != 2) return null;
    final stage = CommitteeStage.fromWire(json['stage']);
    final round = json['round'];
    final selection = CommitteeSelection.fromJson(json['selection']);
    final evidence = CommitteeSelectionEvidence.fromJson(json['evidence']);
    final full = _stringList(json['fullRubricIds']);
    final gating = _stringList(json['gatingRubricIds']);
    final missing = _stringList(json['missingFields']);
    final policyVersion = (json['policyVersion'] as String?)?.trim() ?? '';
    if (stage == null ||
        round is! int ||
        round < 0 ||
        selection == null ||
        evidence == null ||
        full == null ||
        gating == null ||
        missing == null ||
        policyVersion.isEmpty) {
      return null;
    }
    if (version == 2 &&
        canonicalCommitteeJson([
              for (final decision in selection.laneDecisions) decision.rubricId,
            ]) !=
            canonicalCommitteeJson(full)) {
      return null;
    }
    final rawAttempts = json['attempts'];
    if (rawAttempts is! List) return null;
    final attempts = <CommitteeClassifierAttempt>[];
    for (final entry in rawAttempts) {
      final attempt = CommitteeClassifierAttempt.fromJson(entry);
      if (attempt == null) return null;
      attempts.add(attempt);
    }
    final rawPrevious = version == 2 ? json['previous'] : null;
    final previous = CommitteePreviousRound.fromJson(rawPrevious);
    if (rawPrevious != null && previous == null) return null;
    return CommitteeSelectionRun(
      policyVersion: policyVersion,
      stage: stage,
      workBeadId: (json['workBeadId'] as String?)?.trim() ?? '',
      round: round,
      nodePath: (json['nodePath'] as String?) ?? '',
      selection: selection,
      evidence: evidence,
      fullRubricIds: full,
      gatingRubricIds: gating,
      attempts: attempts,
      missingFields: missing,
      previous: previous,
      wireVersion: version as int,
    );
  }
}

/// The PREVIOUS round of the same bead and stage, as a selection input — what
/// the full committee saw and ruled, frozen from that round's receipt.
///
/// It snapshots the receipt's facts, never its own previous round, so a chain
/// of respecs stays one level deep on disk.
@immutable
final class CommitteePreviousRound {
  /// Creates the snapshot; every collection is copied.
  CommitteePreviousRound({
    required this.round,
    required this.evidence,
    required this.route,
    required Iterable<String> actionLaneIds,
    required Iterable<CommitteeLaneReceipt> lanes,
  }) : actionLaneIds = List.unmodifiable(actionLaneIds),
       lanes = List.unmodifiable(lanes);

  /// [receipt] as the next round's previous-round input.
  factory CommitteePreviousRound.fromReceipt(CommitteeShadowReceipt receipt) =>
      CommitteePreviousRound(
        round: receipt.run.round,
        evidence: receipt.run.evidence,
        route: receipt.route,
        actionLaneIds: receipt.actionLaneIds,
        lanes: receipt.lanes,
      );

  /// The previous round's circuit round.
  final int round;

  /// The evidence it was classified over.
  final CommitteeSelectionEvidence evidence;

  /// The authoritative route's ruling on it.
  final CommitteeRouteObservation route;

  /// Its lanes that graded `D`, `E` or `F`.
  final List<String> actionLaneIds;

  /// Every full-committee lane it observed, verdicts included.
  final List<CommitteeLaneReceipt> lanes;

  /// Whether that round RESPECCED — its route stamped the invalidating
  /// [kCommitteeRespecGrade] under [kCommitteeRouteGradeKey].
  bool get isRespec =>
      route.payload[kCommitteeRouteGradeKey]?.trim().toUpperCase() ==
      kCommitteeRespecGrade;

  /// The observed lane [rubricId], or null when the round observed none.
  CommitteeLaneReceipt? laneOf(String rubricId) {
    for (final lane in lanes) {
      if (lane.rubricId == rubricId) return lane;
    }
    return null;
  }

  /// Whether the round recorded a letter grade for [rubricId] — the verdict a
  /// preserving omission carries forward.
  bool hasVerdictFor(String rubricId) =>
      (laneOf(rubricId)?.grade ?? '').trim().isNotEmpty;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'round': round,
    'evidence': evidence.toJson(),
    'route': route.toJson(),
    'actionLaneIds': actionLaneIds,
    'lanes': [for (final lane in lanes) lane.toJson()],
  };

  /// Decodes a snapshot STRICTLY: a negative or non-integer round, refused
  /// evidence/route, a non-list action set or ANY malformed lane yields null.
  static CommitteePreviousRound? fromJson(Object? json) {
    if (json is! Map) return null;
    final round = json['round'];
    final evidence = CommitteeSelectionEvidence.fromJson(json['evidence']);
    final route = CommitteeRouteObservation.fromJson(json['route']);
    final action = _stringList(json['actionLaneIds']);
    final rawLanes = json['lanes'];
    if (round is! int ||
        round < 0 ||
        evidence == null ||
        route == null ||
        action == null ||
        rawLanes is! List) {
      return null;
    }
    final lanes = <CommitteeLaneReceipt>[];
    for (final entry in rawLanes) {
      final lane = CommitteeLaneReceipt.fromJson(entry);
      if (lane == null) return null;
      lanes.add(lane);
    }
    return CommitteePreviousRound(
      round: round,
      evidence: evidence,
      route: route,
      actionLaneIds: action,
      lanes: lanes,
    );
  }
}

// ── the trajectory value codecs (COMPOSITION, never a second vocabulary) ────

/// The grades trajectory's own report counts as ADVERSE. Re-expressed rather
/// than imported: D1 narrows this package's `grid_trajectory` surface to the
/// three VALUE types, so a constant crosses as a literal, not as an import.
const Set<String> kCommitteeAdverseGrades = {'D', 'F'};

/// The grades this pack's route matrices treat as ACTION lanes (`D`/`E`/`F`) —
/// a wider set than [kCommitteeAdverseGrades] by design.
const Set<String> kCommitteeActionGrades = {'D', 'E', 'F'};

/// The transport an OPERATOR RULING stamps on a lane result.
const String kCommitteeOperatorTransport = 'operator-ruling';

String _gateDispositionWire(GateDisposition disposition) =>
    switch (disposition) {
      GateDisposition.overridden => 'overridden',
      GateDisposition.upheld => 'upheld',
      GateDisposition.unresolved => 'unresolved',
    };

GateDisposition? _gateDispositionFromWire(Object? wire) => switch (wire) {
  'overridden' => GateDisposition.overridden,
  'upheld' => GateDisposition.upheld,
  'unresolved' => GateDisposition.unresolved,
  _ => null,
};

Map<String, Object?> _usageSampleToJson(UsageSample sample) => {
  'lane': sample.lane,
  'beadId': sample.beadId,
  'fromFallback': sample.fromFallback,
  'costUsd': sample.costUsd,
  'durationMs': sample.durationMs,
};

UsageSample? _usageSampleFromJson(Object? json) {
  if (json is! Map) return null;
  final lane = json['lane'];
  final fromFallback = json['fromFallback'];
  if (lane is! String || fromFallback is! bool) return null;
  final beadId = json['beadId'];
  if (beadId != null && beadId is! String) return null;
  return UsageSample(
    lane: lane,
    beadId: beadId as String?,
    fromFallback: fromFallback,
    costUsd: _asDouble(json['costUsd']),
    durationMs: _asInt(json['durationMs']),
  );
}

Map<String, Object?> _laneReportToJson(LaneReport report) => {
  'lane': report.lane,
  'gradeCounts': report.gradeCounts,
  'adverseVerdicts': report.adverseVerdicts,
  'gateCausing': report.gateCausing,
  'overridden': report.overridden,
  'upheld': report.upheld,
  'unresolved': report.unresolved,
  'respecConverged': report.respecConverged,
  'respecUnconverged': report.respecUnconverged,
  'respecNoFollowUp': report.respecNoFollowUp,
  'runs': report.runs,
  'runsFromFallback': report.runsFromFallback,
  'meanCostUsd': report.meanCostUsd,
  'meanDurationMs': report.meanDurationMs,
};

LaneReport? _laneReportFromJson(Object? json) {
  if (json is! Map) return null;
  final lane = json['lane'];
  final rawGrades = json['gradeCounts'];
  if (lane is! String || rawGrades is! Map) return null;
  final gradeCounts = <String, int>{};
  for (final entry in rawGrades.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || value is! int) return null;
    gradeCounts[key] = value;
  }
  final counters = <String, int>{};
  for (final field in const [
    'adverseVerdicts',
    'gateCausing',
    'overridden',
    'upheld',
    'unresolved',
    'respecConverged',
    'respecUnconverged',
    'respecNoFollowUp',
    'runs',
    'runsFromFallback',
  ]) {
    final value = json[field];
    if (value is! int) return null;
    counters[field] = value;
  }
  return LaneReport(
    lane: lane,
    gradeCounts: gradeCounts,
    adverseVerdicts: counters['adverseVerdicts']!,
    gateCausing: counters['gateCausing']!,
    overridden: counters['overridden']!,
    upheld: counters['upheld']!,
    unresolved: counters['unresolved']!,
    respecConverged: counters['respecConverged']!,
    respecUnconverged: counters['respecUnconverged']!,
    respecNoFollowUp: counters['respecNoFollowUp']!,
    runs: counters['runs']!,
    runsFromFallback: counters['runsFromFallback']!,
    meanCostUsd: _asDouble(json['meanCostUsd']),
    meanDurationMs: _asInt(json['meanDurationMs']),
  );
}

// ── the shadow receipt ──────────────────────────────────────────────────────

/// ONE full-committee lane, observed — trajectory's [LaneReport] and
/// [UsageSample] carried directly, EXTENDED by composition with the per-sample
/// columns the trajectory aggregate intentionally does not keep.
@immutable
final class CommitteeLaneReceipt {
  /// Creates the receipt from already-derived values; prefer [derive].
  CommitteeLaneReceipt({
    required this.report,
    required this.usage,
    required this.rubricId,
    required this.nodePath,
    required this.gating,
    this.gateDisposition,
    this.grade,
    this.transport,
    this.rationale,
    this.finding,
    this.owner,
    this.refinement,
    this.model,
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.premiumRequests,
    this.numTurns,
    this.durationMs,
    this.truncated = false,
    Iterable<String> missingFields = const [],
  }) : missingFields = List.unmodifiable(missingFields);

  /// Derives the lane receipt from the RAW observation, computing the trajectory
  /// values ([report], [usage], [gateDisposition]) so a replay reproduces them
  /// from the recorded columns alone.
  ///
  /// A DETERMINISTIC gate ([gating]) contributes KNOWN ZERO inference metrics —
  /// it spawned no model. A semantic lane's absent metric stays null and names
  /// itself in [missingFields]; it is never coerced to zero.
  factory CommitteeLaneReceipt.derive({
    required String rubricId,
    required String nodePath,
    required String workBeadId,
    required String routeType,
    required bool gating,
    String? grade,
    String? transport,
    String? rationale,
    String? finding,
    String? owner,
    String? refinement,
    String? model,
    int? tokensIn,
    int? tokensOut,
    num? costUsd,
    num? premiumRequests,
    int? numTurns,
    int? durationMs,
    bool truncated = false,
  }) {
    final resolvedTokensIn = gating ? (tokensIn ?? 0) : tokensIn;
    final resolvedTokensOut = gating ? (tokensOut ?? 0) : tokensOut;
    final resolvedCost = gating ? (costUsd ?? 0) : costUsd;
    final resolvedPremium = gating ? (premiumRequests ?? 0) : premiumRequests;
    final resolvedTurns = gating ? (numTurns ?? 0) : numTurns;
    final normalized = (grade ?? '').trim().toUpperCase();
    final adverse = kCommitteeAdverseGrades.contains(normalized);
    final disposition = committeeGateDispositionFor(
      adverse: adverse,
      transport: transport,
      routeType: routeType,
    );
    final missing = <String>[
      if (normalized.isEmpty) 'grade',
      if (transport == null || transport.trim().isEmpty) 'transport',
      if (resolvedCost == null) 'costUsd',
      if (resolvedTokensIn == null) 'tokensIn',
      if (resolvedTokensOut == null) 'tokensOut',
      if (durationMs == null) 'durationMs',
      if (!gating && (model == null || model.trim().isEmpty)) 'model',
    ];
    return CommitteeLaneReceipt(
      report: LaneReport(
        lane: rubricId,
        gradeCounts: normalized.isEmpty ? const {} : {normalized: 1},
        adverseVerdicts: adverse ? 1 : 0,
        gateCausing: disposition == null ? 0 : 1,
        overridden: disposition == GateDisposition.overridden ? 1 : 0,
        upheld: disposition == GateDisposition.upheld ? 1 : 0,
        unresolved: disposition == GateDisposition.unresolved ? 1 : 0,
        respecConverged: 0,
        respecUnconverged: 0,
        respecNoFollowUp: adverse ? 1 : 0,
        runs: 1,
        runsFromFallback: 0,
        meanCostUsd: resolvedCost?.toDouble(),
        meanDurationMs: durationMs,
      ),
      usage: UsageSample(
        lane: rubricId,
        beadId: workBeadId.isEmpty ? null : workBeadId,
        fromFallback: false,
        costUsd: resolvedCost?.toDouble(),
        durationMs: durationMs,
      ),
      rubricId: rubricId,
      nodePath: nodePath,
      gating: gating,
      gateDisposition: disposition,
      grade: normalized.isEmpty ? null : normalized,
      transport: transport,
      rationale: rationale,
      finding: finding,
      owner: owner,
      refinement: refinement,
      model: model,
      tokensIn: resolvedTokensIn,
      tokensOut: resolvedTokensOut,
      costUsd: resolvedCost,
      premiumRequests: resolvedPremium,
      numTurns: resolvedTurns,
      durationMs: durationMs,
      truncated: truncated,
      missingFields: missing,
    );
  }

  /// The lane's trajectory report — one observation, in their vocabulary.
  final LaneReport report;

  /// The lane's trajectory usage sample.
  final UsageSample usage;

  /// The lane's trajectory gate disposition, when the lane was adverse.
  final GateDisposition? gateDisposition;

  /// The rubric id ([LaneReport.lane], repeated for a direct read).
  final String rubricId;

  /// The lane's FULL node path in the live committee.
  final String nodePath;

  /// Whether this lane is a deterministic gate.
  final bool gating;

  /// The ACTUAL letter grade the authoritative lane recorded.
  final String? grade;

  /// Which channel produced that grade (`file`/`envelope`/…).
  final String? transport;

  /// The lane's own rationale.
  final String? rationale;

  /// The finding the route carried forward, when it carried one.
  final String? finding;

  /// Who can fix an actionable grade.
  final String? owner;

  /// The lane's non-grading bead-graph observation.
  final String? refinement;

  /// The model that actually served the lane.
  final String? model;

  /// Prompt tokens.
  final int? tokensIn;

  /// Completion tokens.
  final int? tokensOut;

  /// Billed cost.
  final num? costUsd;

  /// Premium-request consumption.
  final num? premiumRequests;

  /// Assistant turns.
  final int? numTurns;

  /// Harness-observed wall clock.
  final int? durationMs;

  /// Whether the lane's own evidence reported itself clipped.
  final bool truncated;

  /// Which of this lane's columns were absent, named.
  final List<String> missingFields;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'report': _laneReportToJson(report),
    'usage': _usageSampleToJson(usage),
    'gateDisposition': gateDisposition == null
        ? null
        : _gateDispositionWire(gateDisposition!),
    'rubricId': rubricId,
    'nodePath': nodePath,
    'gating': gating,
    'grade': grade,
    'transport': transport,
    'rationale': rationale,
    'finding': finding,
    'owner': owner,
    'refinement': refinement,
    'model': model,
    'tokensIn': tokensIn,
    'tokensOut': tokensOut,
    'costUsd': costUsd,
    'premiumRequests': premiumRequests,
    'numTurns': numTurns,
    'durationMs': durationMs,
    'truncated': truncated,
    'missingFields': missingFields,
  };

  /// Decodes one lane receipt STRICTLY; a refused report/usage, a present but
  /// unknown gate disposition, or a missing rubric id yields null.
  static CommitteeLaneReceipt? fromJson(Object? json) {
    if (json is! Map) return null;
    final report = _laneReportFromJson(json['report']);
    final usage = _usageSampleFromJson(json['usage']);
    final rubricId = (json['rubricId'] as String?)?.trim() ?? '';
    final gating = json['gating'];
    final missing = _stringList(json['missingFields']);
    if (report == null ||
        usage == null ||
        rubricId.isEmpty ||
        gating is! bool ||
        missing == null) {
      return null;
    }
    final rawDisposition = json['gateDisposition'];
    final disposition = _gateDispositionFromWire(rawDisposition);
    if (rawDisposition != null && disposition == null) return null;
    return CommitteeLaneReceipt(
      report: report,
      usage: usage,
      gateDisposition: disposition,
      rubricId: rubricId,
      nodePath: (json['nodePath'] as String?) ?? '',
      gating: gating,
      grade: json['grade'] as String?,
      transport: json['transport'] as String?,
      rationale: json['rationale'] as String?,
      finding: json['finding'] as String?,
      owner: json['owner'] as String?,
      refinement: json['refinement'] as String?,
      model: json['model'] as String?,
      tokensIn: _asInt(json['tokensIn']),
      tokensOut: _asInt(json['tokensOut']),
      costUsd: _asNum(json['costUsd']),
      premiumRequests: _asNum(json['premiumRequests']),
      numTurns: _asInt(json['numTurns']),
      durationMs: _asInt(json['durationMs']),
      truncated: json['truncated'] == true,
      missingFields: missing,
    );
  }
}

/// The gate disposition ONE adverse lane earned under [routeType].
///
/// Mirrors trajectory's own step-derived rule: an operator ruling on the lane
/// result is an OVERRIDE however the route ruled; an `advance` past an adverse
/// verdict is an override; an `escalate` means the committee was believed; a
/// rewind has resolved nothing yet. A non-adverse lane has no disposition at
/// all — null, never an unearned value.
GateDisposition? committeeGateDispositionFor({
  required bool adverse,
  required String routeType,
  String? transport,
}) {
  if (!adverse) return null;
  if (transport?.trim() == kCommitteeOperatorTransport) {
    return GateDisposition.overridden;
  }
  return switch (routeType) {
    'advance' => GateDisposition.overridden,
    'escalate' => GateDisposition.upheld,
    _ => GateDisposition.unresolved,
  };
}

/// One accounting BLOCK — trajectory's per-run [UsageSample]s carried whole,
/// EXTENDED with the aggregate totals neither [UsageSample] (per-run cost and
/// duration only) nor [LaneReport] (per-lane means and counts only) keeps.
///
/// Every total is NULLABLE and every null names its contributor: a missing
/// metric leaves the aggregate blank rather than pretending the spend was zero.
@immutable
final class CommitteeUsageAccounting {
  /// Creates the block; every collection is copied.
  CommitteeUsageAccounting({
    required Iterable<UsageSample> samples,
    required Iterable<String> contributingRunIds,
    required Iterable<String> missingLaneIds,
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.premiumRequests,
    this.numTurns,
    this.durationMs,
  }) : samples = List.unmodifiable(samples),
       contributingRunIds = List.unmodifiable(contributingRunIds),
       missingLaneIds = List.unmodifiable(missingLaneIds);

  /// Every contributing per-run sample, in trajectory's own vocabulary.
  final List<UsageSample> samples;

  /// What contributed, named — lane node paths and classifier attempt ids.
  final List<String> contributingRunIds;

  /// Which contributors left a metric blank.
  final List<String> missingLaneIds;

  /// Total prompt tokens, or null when a contributor did not report them.
  final int? tokensIn;

  /// Total completion tokens, or null when a contributor did not report them.
  final int? tokensOut;

  /// Total billed cost, or null when a contributor did not report it.
  final double? costUsd;

  /// Total premium requests, or null when a contributor did not report them.
  final num? premiumRequests;

  /// Total assistant turns, or null when a contributor did not report them.
  final int? numTurns;

  /// Total harness wall clock, or null when a contributor did not report it.
  final int? durationMs;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'samples': [for (final sample in samples) _usageSampleToJson(sample)],
    'contributingRunIds': contributingRunIds,
    'missingLaneIds': missingLaneIds,
    'tokensIn': tokensIn,
    'tokensOut': tokensOut,
    'costUsd': costUsd,
    'premiumRequests': premiumRequests,
    'numTurns': numTurns,
    'durationMs': durationMs,
  };

  /// Decodes one block STRICTLY; a refused sample or a non-list id set yields
  /// null.
  static CommitteeUsageAccounting? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawSamples = json['samples'];
    if (rawSamples is! List) return null;
    final samples = <UsageSample>[];
    for (final entry in rawSamples) {
      final sample = _usageSampleFromJson(entry);
      if (sample == null) return null;
      samples.add(sample);
    }
    final runIds = _stringList(json['contributingRunIds']);
    final missing = _stringList(json['missingLaneIds']);
    if (runIds == null || missing == null) return null;
    return CommitteeUsageAccounting(
      samples: samples,
      contributingRunIds: runIds,
      missingLaneIds: missing,
      tokensIn: _asInt(json['tokensIn']),
      tokensOut: _asInt(json['tokensOut']),
      costUsd: _asDouble(json['costUsd']),
      premiumRequests: _asNum(json['premiumRequests']),
      numTurns: _asInt(json['numTurns']),
      durationMs: _asInt(json['durationMs']),
    );
  }
}

/// Folds [lanes] and [attempts] into ONE accounting block.
///
/// A deterministic gate already carries known zeros ([CommitteeLaneReceipt.derive]);
/// a classifier attempt that never launched contributes zeros too. Anything
/// else that is absent nulls its aggregate and names itself.
CommitteeUsageAccounting committeeUsageAccounting({
  required Iterable<CommitteeLaneReceipt> lanes,
  Iterable<CommitteeClassifierAttempt> attempts = const [],
}) {
  final samples = <UsageSample>[];
  final runIds = <String>[];
  final missing = <String>{};
  var tokensIn = 0;
  var tokensOut = 0;
  var cost = 0.0;
  num premium = 0;
  var turns = 0;
  var duration = 0;
  var haveTokensIn = true;
  var haveTokensOut = true;
  var haveCost = true;
  var havePremium = true;
  var haveTurns = true;
  var haveDuration = true;

  void fold({
    required String id,
    required int? inTokens,
    required int? outTokens,
    required num? runCost,
    required num? runPremium,
    required int? runTurns,
    required int? runDuration,
  }) {
    runIds.add(id);
    var complete = true;
    if (inTokens == null) {
      haveTokensIn = false;
      complete = false;
    } else {
      tokensIn += inTokens;
    }
    if (outTokens == null) {
      haveTokensOut = false;
      complete = false;
    } else {
      tokensOut += outTokens;
    }
    if (runCost == null) {
      haveCost = false;
      complete = false;
    } else {
      cost += runCost.toDouble();
    }
    if (runPremium == null) {
      havePremium = false;
      complete = false;
    } else {
      premium += runPremium;
    }
    if (runTurns == null) {
      haveTurns = false;
      complete = false;
    } else {
      turns += runTurns;
    }
    if (runDuration == null) {
      haveDuration = false;
      complete = false;
    } else {
      duration += runDuration;
    }
    if (!complete) missing.add(id);
  }

  for (final lane in lanes) {
    samples.add(lane.usage);
    fold(
      id: lane.rubricId,
      inTokens: lane.tokensIn,
      outTokens: lane.tokensOut,
      runCost: lane.costUsd,
      runPremium: lane.premiumRequests,
      runTurns: lane.numTurns,
      runDuration: lane.durationMs,
    );
  }
  for (final attempt in attempts) {
    samples.add(attempt.usage);
    final launched = attempt.launched;
    fold(
      id: 'classifier-attempt-${attempt.attempt}',
      inTokens: launched ? attempt.tokensIn : (attempt.tokensIn ?? 0),
      outTokens: launched ? attempt.tokensOut : (attempt.tokensOut ?? 0),
      runCost: launched ? attempt.costUsd : (attempt.costUsd ?? 0),
      runPremium: launched
          ? attempt.premiumRequests
          : (attempt.premiumRequests ?? 0),
      runTurns: launched ? attempt.numTurns : (attempt.numTurns ?? 0),
      runDuration: launched
          ? attempt.harnessDurationMs
          : (attempt.harnessDurationMs ?? 0),
    );
  }

  return CommitteeUsageAccounting(
    samples: samples,
    contributingRunIds: runIds,
    missingLaneIds: missing.toList()..sort(),
    tokensIn: haveTokensIn ? tokensIn : null,
    tokensOut: haveTokensOut ? tokensOut : null,
    costUsd: haveCost ? cost : null,
    premiumRequests: havePremium ? premium : null,
    numTurns: haveTurns ? turns : null,
    durationMs: haveDuration ? duration : null,
  );
}

/// The AUTHORITATIVE route's ruling, observed. A shadow receipt records it; it
/// never produces one.
@immutable
final class CommitteeRouteObservation {
  /// Creates the observation; the payload is copied.
  CommitteeRouteObservation({
    required this.nodePath,
    required this.type,
    this.reason = '',
    Map<String, String> payload = const {},
  }) : payload = Map.unmodifiable(payload);

  /// The route step's own node path.
  final String nodePath;

  /// `advance` | `rewind` | `escalate` — encoded by an exhaustive switch over
  /// the engine's sealed [RouteVerdict], for provenance only.
  final String type;

  /// The verdict's own reason string, verbatim.
  final String reason;

  /// The verdict's result payload, verbatim.
  final Map<String, String> payload;

  /// The route's parent path — the sibling scope its lanes share.
  String get parentPath => committeeSelectionParentPath(nodePath);

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'nodePath': nodePath,
    'type': type,
    'reason': reason,
    'payload': payload,
  };

  /// Decodes the observation STRICTLY; a missing type or a non-string payload
  /// value yields null.
  static CommitteeRouteObservation? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = (json['type'] as String?)?.trim() ?? '';
    final payload = _stringMap(json['payload']);
    if (type.isEmpty || payload == null) return null;
    return CommitteeRouteObservation(
      nodePath: (json['nodePath'] as String?) ?? '',
      type: type,
      reason: (json['reason'] as String?) ?? '',
      payload: payload,
    );
  }
}

/// The route [verdict]'s wire type — an exhaustive switch over the engine's
/// sealed verdict, so a new arm cannot be recorded as an old one.
String committeeRouteTypeOf(RouteVerdict verdict) => switch (verdict) {
  Advance() => 'advance',
  Rewind() => 'rewind',
  Escalate() => 'escalate',
};

/// The route [verdict] as an observation at [nodePath].
CommitteeRouteObservation committeeRouteObservationOf(
  RouteVerdict verdict, {
  required String nodePath,
}) => switch (verdict) {
  Advance(:final payload) => CommitteeRouteObservation(
    nodePath: nodePath,
    type: 'advance',
    payload: payload ?? const {},
  ),
  Rewind(:final stepIds, :final reason) => CommitteeRouteObservation(
    nodePath: nodePath,
    type: 'rewind',
    reason: reason,
    payload: {'stepIds': (stepIds.toList()..sort()).join(',')},
  ),
  Escalate(:final reason) => CommitteeRouteObservation(
    nodePath: nodePath,
    type: 'escalate',
    reason: reason,
  ),
};

/// ONE round's whole SHADOW observation — what the full committee actually did,
/// beside what the selector WOULD have run, with the counterfactual spend.
///
/// Non-authoritative by construction: nothing downstream reads it to decide
/// anything. It exists so the question "would selection have been safe here?"
/// is answerable from the ledger instead of from a rerun.
@immutable
final class CommitteeShadowReceipt {
  /// Creates the receipt; prefer [buildCommitteeShadowReceipt], which derives
  /// every identity and accounting block.
  CommitteeShadowReceipt({
    required this.sampleId,
    required this.joinId,
    required this.run,
    required this.route,
    required Iterable<String> selectedRubricIds,
    required Iterable<String> omittedRubricIds,
    required Iterable<CommitteeLaneReceipt> lanes,
    required Iterable<String> actionLaneIds,
    required this.actual,
    required this.classifier,
    required this.counterfactual,
    required Map<String, String> downstreamJoinKeys,
    this.gateDisposition,
    this.truncated = false,
    Iterable<String> missingFields = const [],
    Iterable<CommitteeLaneReceipt> preservedLanes = const [],
  }) : selectedRubricIds = List.unmodifiable(selectedRubricIds),
       omittedRubricIds = List.unmodifiable(omittedRubricIds),
       lanes = List.unmodifiable(lanes),
       preservedLanes = List.unmodifiable(preservedLanes),
       actionLaneIds = List.unmodifiable(actionLaneIds),
       downstreamJoinKeys = Map.unmodifiable(downstreamJoinKeys),
       missingFields = List.unmodifiable(missingFields);

  /// The stable identity of this SAMPLE — policy, stage, bead, round, evidence.
  final String sampleId;

  /// The stable identity of the JOIN this sample belongs to — stage, bead,
  /// round, route parent.
  final String joinId;

  /// The complete selection run, evidence included, so replay needs no source.
  final CommitteeSelectionRun run;

  /// The authoritative route's ruling.
  final CommitteeRouteObservation route;

  /// The lanes the shadow WOULD have run.
  final List<String> selectedRubricIds;

  /// The lanes the shadow would have OMITTED — the whole point of the sample.
  final List<String> omittedRubricIds;

  /// Every FULL-committee lane, observed.
  final List<CommitteeLaneReceipt> lanes;

  /// The PREVIOUS round's verdict for every omitted lane whose rule carries a
  /// verdict forward ([CommitteeLaneRule.preservesPriorVerdict]) — what an
  /// activated selector would hand the route in place of a re-run. The full
  /// [lanes] stay the authoritative observation; this is the counterfactual.
  final List<CommitteeLaneReceipt> preservedLanes;

  /// The lanes that graded `D`, `E` or `F` — this pack's action set.
  final List<String> actionLaneIds;

  /// The route-level gate disposition, when any lane was adverse.
  final GateDisposition? gateDisposition;

  /// The keys a downstream fold joins this sample on.
  final Map<String, String> downstreamJoinKeys;

  /// What the FULL committee actually spent.
  final CommitteeUsageAccounting actual;

  /// What the policy-1 CLASSIFIER spent (always empty under policy 2).
  final CommitteeUsageAccounting classifier;

  /// What the SELECTED committee (plus any policy-1 classifier) WOULD have
  /// spent.
  final CommitteeUsageAccounting counterfactual;

  /// Whether any contributing artifact reported itself clipped.
  final bool truncated;

  /// Everything this receipt could not resolve, named.
  final List<String> missingFields;

  /// The wire shape — at the run's own wire version, so a version-1 receipt
  /// keeps its version-1 shape.
  Map<String, Object?> toJson() => {
    'version': run.wireVersion,
    'sampleId': sampleId,
    'joinId': joinId,
    'run': run.toJson(),
    'route': route.toJson(),
    'selectedRubricIds': selectedRubricIds,
    'omittedRubricIds': omittedRubricIds,
    'lanes': [for (final lane in lanes) lane.toJson()],
    'actionLaneIds': actionLaneIds,
    'gateDisposition': gateDisposition == null
        ? null
        : _gateDispositionWire(gateDisposition!),
    'downstreamJoinKeys': downstreamJoinKeys,
    'actual': actual.toJson(),
    'classifier': classifier.toJson(),
    'counterfactual': counterfactual.toJson(),
    'truncated': truncated,
    'missingFields': missingFields,
    if (run.wireVersion >= 2)
      'preservedLanes': [for (final lane in preservedLanes) lane.toJson()],
  };

  /// Decodes a receipt STRICTLY: any `version` but 1 or 2 (or one that
  /// disagrees with its run's), a refused run/route/lane/accounting block, or a
  /// present-but-unknown gate disposition yields null.
  static CommitteeShadowReceipt? fromJson(Object? json) {
    if (json is! Map) return null;
    final run = CommitteeSelectionRun.fromJson(json['run']);
    if (run == null || json['version'] != run.wireVersion) return null;
    final route = CommitteeRouteObservation.fromJson(json['route']);
    final actual = CommitteeUsageAccounting.fromJson(json['actual']);
    final classifier = CommitteeUsageAccounting.fromJson(json['classifier']);
    final counterfactual = CommitteeUsageAccounting.fromJson(
      json['counterfactual'],
    );
    final selected = _stringList(json['selectedRubricIds']);
    final omitted = _stringList(json['omittedRubricIds']);
    final action = _stringList(json['actionLaneIds']);
    final joinKeys = _stringMap(json['downstreamJoinKeys']);
    final missing = _stringList(json['missingFields']);
    final sampleId = (json['sampleId'] as String?)?.trim() ?? '';
    final joinId = (json['joinId'] as String?)?.trim() ?? '';
    if (route == null ||
        actual == null ||
        classifier == null ||
        counterfactual == null ||
        selected == null ||
        omitted == null ||
        action == null ||
        joinKeys == null ||
        missing == null ||
        sampleId.isEmpty ||
        joinId.isEmpty) {
      return null;
    }
    final lanes = _laneReceipts(json['lanes']);
    final preserved = _laneReceipts(
      run.wireVersion >= 2 ? json['preservedLanes'] : const <Object?>[],
    );
    if (lanes == null || preserved == null) return null;
    final rawDisposition = json['gateDisposition'];
    final disposition = _gateDispositionFromWire(rawDisposition);
    if (rawDisposition != null && disposition == null) return null;
    return CommitteeShadowReceipt(
      sampleId: sampleId,
      joinId: joinId,
      run: run,
      route: route,
      selectedRubricIds: selected,
      omittedRubricIds: omitted,
      lanes: lanes,
      actionLaneIds: action,
      gateDisposition: disposition,
      downstreamJoinKeys: joinKeys,
      actual: actual,
      classifier: classifier,
      counterfactual: counterfactual,
      truncated: json['truncated'] == true,
      missingFields: missing,
      preservedLanes: preserved,
    );
  }
}

List<CommitteeLaneReceipt>? _laneReceipts(Object? json) {
  if (json is! List) return null;
  final lanes = <CommitteeLaneReceipt>[];
  for (final entry in json) {
    final lane = CommitteeLaneReceipt.fromJson(entry);
    if (lane == null) return null;
    lanes.add(lane);
  }
  return lanes;
}

/// The stable SAMPLE identity for one selection.
String committeeSampleId({
  required String policyVersion,
  required CommitteeStage stage,
  required String workBeadId,
  required int round,
  required String evidenceDigest,
}) => committeeDigest({
  'policyVersion': policyVersion,
  'stage': stage.wire,
  'workBeadId': workBeadId,
  'round': round,
  'evidenceDigest': evidenceDigest,
});

/// The stable JOIN identity a downstream fold groups samples by.
String committeeJoinId({
  required CommitteeStage stage,
  required String workBeadId,
  required int round,
  required String routeParentPath,
}) => committeeDigest({
  'stage': stage.wire,
  'workBeadId': workBeadId,
  'round': round,
  'routeParentPath': routeParentPath,
});

/// Assembles ONE receipt from already-observed facts — PURE: no filesystem, no
/// inference, no tree.
///
/// [lanes] arrive derived ([CommitteeLaneReceipt.derive]); every identity,
/// omission set, preserved verdict and accounting block below is computed here,
/// so a replay over the recorded columns reproduces the receipt byte for byte.
/// The preserved verdicts come from the run's own previous-round snapshot.
CommitteeShadowReceipt buildCommitteeShadowReceipt({
  required CommitteeSelectionRun run,
  required CommitteeRouteObservation route,
  required List<CommitteeLaneReceipt> lanes,
  Iterable<String> missingFields = const [],
  bool truncated = false,
}) {
  final selected = run.selection.selectedRubricIds;
  final omitted = [
    for (final id in run.fullRubricIds)
      if (!selected.contains(id)) id,
  ];
  final actionLaneIds = [
    for (final lane in lanes)
      if (kCommitteeActionGrades.contains(lane.grade ?? '')) lane.rubricId,
  ];
  final selectedLanes = [
    for (final lane in lanes)
      if (selected.contains(lane.rubricId)) lane,
  ];
  final previous = run.previous;
  final preservedLanes = [
    if (previous != null)
      for (final decision in run.selection.laneDecisions)
        if (decision.rule.preservesPriorVerdict)
          ?previous.laneOf(decision.rubricId),
  ];
  return CommitteeShadowReceipt(
    sampleId: committeeSampleId(
      policyVersion: run.policyVersion,
      stage: run.stage,
      workBeadId: run.workBeadId,
      round: run.round,
      evidenceDigest: run.selection.evidenceDigest,
    ),
    joinId: committeeJoinId(
      stage: run.stage,
      workBeadId: run.workBeadId,
      round: run.round,
      routeParentPath: route.parentPath,
    ),
    run: run,
    route: route,
    selectedRubricIds: selected,
    omittedRubricIds: omitted,
    lanes: lanes,
    actionLaneIds: actionLaneIds,
    gateDisposition: committeeGateDispositionFor(
      adverse: lanes.any(
        (lane) => kCommitteeAdverseGrades.contains(lane.grade ?? ''),
      ),
      routeType: route.type,
    ),
    downstreamJoinKeys: {
      'workBeadId': run.workBeadId,
      'round': '${run.round}',
      'stage': run.stage.wire,
      'routeNodePath': route.nodePath,
      'siblingScope': '${route.parentPath}/',
    },
    actual: committeeUsageAccounting(lanes: lanes),
    classifier: committeeUsageAccounting(
      lanes: const [],
      attempts: run.attempts,
    ),
    counterfactual: committeeUsageAccounting(
      lanes: selectedLanes,
      attempts: run.attempts,
    ),
    truncated: truncated || run.evidence.truncated,
    missingFields: missingFields,
    preservedLanes: preservedLanes,
  );
}

/// Re-classifies [recorded] under [policy] over its OWN retained evidence — the
/// pure half of replay, and how a policy-1 receipt is measured under policy 2.
///
/// [previous] is the recorded receipt of the preceding round of the same bead
/// and stage; when it is null the run's own previous-round snapshot (a
/// version-2 receipt carries one) is used. It reads no discovery artifact, no
/// diff, no telemetry file and calls no inference: every input is a column of
/// the receipts themselves, and the route observation is carried verbatim — a
/// re-classification never rules, grades or rewinds anything. A version-2
/// receipt re-classified over its own snapshot reproduces itself; one that
/// differs is the policy having drifted.
CommitteeShadowReceipt reclassifyCommitteeShadowReceipt(
  CommitteeShadowReceipt recorded, {
  CommitteeShadowReceipt? previous,
  CommitteeSelectionPolicy policy = kCommitteeSelectionPolicy,
}) {
  final source = recorded.run;
  final prior = previous == null
      ? source.previous
      : CommitteePreviousRound.fromReceipt(previous);
  final run = CommitteeSelectionRun(
    policyVersion: policy.policyVersion,
    stage: source.stage,
    workBeadId: source.workBeadId,
    round: source.round,
    nodePath: source.nodePath,
    selection: policy.classify(
      evidence: source.evidence,
      fullRubricIds: source.fullRubricIds,
      gatingRubricIds: source.gatingRubricIds,
      previous: prior,
    ),
    evidence: source.evidence,
    fullRubricIds: source.fullRubricIds,
    gatingRubricIds: source.gatingRubricIds,
    missingFields: source.missingFields,
    previous: prior,
  );
  return buildCommitteeShadowReceipt(
    run: run,
    route: recorded.route,
    lanes: [
      for (final lane in recorded.lanes)
        CommitteeLaneReceipt.derive(
          rubricId: lane.rubricId,
          nodePath: lane.nodePath,
          workBeadId: source.workBeadId,
          routeType: recorded.route.type,
          gating: lane.gating,
          grade: lane.grade,
          transport: lane.transport,
          rationale: lane.rationale,
          finding: lane.finding,
          owner: lane.owner,
          refinement: lane.refinement,
          model: lane.model,
          tokensIn: lane.tokensIn,
          tokensOut: lane.tokensOut,
          costUsd: lane.costUsd,
          premiumRequests: lane.premiumRequests,
          numTurns: lane.numTurns,
          durationMs: lane.durationMs,
          truncated: lane.truncated,
        ),
    ],
    missingFields: recorded.missingFields,
    truncated: recorded.truncated,
  );
}

/// Re-classifies a retained corpus in CHRONOLOGICAL order: grouped by work bead
/// and stage, ascending by round, each receipt classified against the RECORDED
/// receipt of the round before it (the full committee always ran in shadow, so
/// that is the previous round an activated selector would have seen). The
/// first round of each group has no previous round, and — matching
/// [CommitteeSelectionStore.readPreviousReceipt]'s strictly-lower-round lookup
/// — neither does a receipt whose predecessor carries the SAME round: rounds
/// are session-local ([committeeSelectionRound]), so two round-zero receipts
/// are two rework sessions, not a series. Pure, like
/// [reclassifyCommitteeShadowReceipt].
List<CommitteeShadowReceipt> reclassifyCommitteeShadowCorpus(
  Iterable<CommitteeShadowReceipt> recorded, {
  CommitteeSelectionPolicy policy = kCommitteeSelectionPolicy,
}) {
  final ordered = recorded.toList()
    ..sort((a, b) {
      final bead = a.run.workBeadId.compareTo(b.run.workBeadId);
      if (bead != 0) return bead;
      final stage = a.run.stage.wire.compareTo(b.run.stage.wire);
      if (stage != 0) return stage;
      return a.run.round.compareTo(b.run.round);
    });
  final reclassified = <CommitteeShadowReceipt>[];
  CommitteeShadowReceipt? before;
  for (final receipt in ordered) {
    final sameSeries =
        before != null &&
        before.run.workBeadId == receipt.run.workBeadId &&
        before.run.stage == receipt.run.stage &&
        before.run.round < receipt.run.round;
    reclassified.add(
      reclassifyCommitteeShadowReceipt(
        receipt,
        previous: sameSeries ? before : null,
        policy: policy,
      ),
    );
    before = receipt;
  }
  return reclassified;
}

// ── the durable step-result projections ─────────────────────────────────────

/// [run]'s evidence packet as the step-result entries the engine appends
/// durably beside the step transition — the copy that OUTLIVES the per-round
/// worktree the store's own artifact is reaped with.
///
/// COMPOSITION, not a second sink: the carrier is the existing [Ok] payload a
/// downstream fold already reads, so nothing here mints a record type, opens a
/// file or reaches a database. The worktree artifact stays the in-round working
/// copy; this is the durable one.
///
/// BOUNDED by construction — identities, digests, ids and counts only. No
/// prose, no raw evidence, no rationale: [CommitteeSelectionEvidence]'s fact
/// lanes, a classifier's reason and its output text are all excluded, and the
/// only evidence that crosses is its digest and the NAMES of what was missing.
/// Each lane's decision crosses as `rubric id -> rule id` (`laneDecisions`),
/// and the previous round it was compared against as its round number.
///
/// The `sampleId`/`joinId` here are derived exactly as
/// [buildCommitteeShadowReceipt] derives them, so the selector entry and the
/// later route entry of the same round carry IDENTICAL identities and a
/// per-rule fold can join the two on them.
Map<String, String> committeeSelectionResultProjection(
  CommitteeSelectionRun run,
) {
  final selection = run.selection;
  final selected = selection.selectedRubricIds.toSet();
  return {
    'shadow': 'selection',
    'source': selection.source.wire,
    'stage': run.stage.wire,
    'selected': selection.selectedRubricIds.join(','),
    'matchedRules': selection.matchedRuleIds.join(','),
    'classifierAttempts': '${run.attempts.length}',
    'sampleId': committeeSampleId(
      policyVersion: run.policyVersion,
      stage: run.stage,
      workBeadId: run.workBeadId,
      round: run.round,
      evidenceDigest: selection.evidenceDigest,
    ),
    'joinId': committeeJoinId(
      stage: run.stage,
      workBeadId: run.workBeadId,
      round: run.round,
      routeParentPath: committeeSelectionParentPath(run.nodePath),
    ),
    'policyVersion': run.policyVersion,
    'workBeadId': run.workBeadId,
    'round': canonicalCommitteeJson(run.round),
    'nodePath': run.nodePath,
    'omitted': [
      for (final id in run.fullRubricIds)
        if (!selected.contains(id)) id,
    ].join(','),
    'evidenceDigest': selection.evidenceDigest,
    'missingEvidenceIds': run.evidence.missingEvidenceIds.join(','),
    'laneInputDigests': canonicalCommitteeJson(selection.laneInputDigests),
    'classifierAttemptKinds': [
      for (final attempt in run.attempts) attempt.kind.wire,
    ].join(','),
    'laneDecisions': _laneDecisionsColumn(selection),
    'previousRound': canonicalCommitteeJson(run.previous?.round),
  };
}

/// One `rubric id -> rule id` map over every lane decision, canonical.
String _laneDecisionsColumn(CommitteeSelection selection) =>
    canonicalCommitteeJson({
      for (final decision in selection.laneDecisions)
        decision.rubricId: decision.rule.id,
    });

/// [receipt]'s evidence packet as the RESERVED `committeeShadow*` step-result
/// entries a shadowed advance carries — the durable half of the receipt the
/// worktree file is reaped with.
///
/// The `committeeShadow` prefix is the reservation: a conforming authoritative
/// route payload carries no such key, so spreading these entries LAST can only
/// win a collision against a payload that broke that reservation.
///
/// Same bound as [committeeSelectionResultProjection], applied to the receipt's
/// wider surface: the omitted lanes cross as their rubric ids mapped to a
/// grade, a transport and a gate disposition; every lane's decision crosses as
/// its rule id; the preserved prior verdicts cross as their rubric ids mapped
/// to a grade and a transport; the accounting crosses as contributor ids and
/// totals. A lane's rationale, finding, owner, refinement
/// and model, the route's own reason and payload, and every raw evidence lane
/// are all excluded.
Map<String, String> committeeShadowResultProjection(
  CommitteeShadowReceipt receipt,
) {
  final run = receipt.run;
  final selection = run.selection;
  final lanes = {for (final lane in receipt.lanes) lane.rubricId: lane};

  /// One `omitted rubric id -> column` map, over EVERY omitted lane: a lane the
  /// committee never observed maps to null rather than dropping out, so the
  /// omission set and the observation set always have the same members.
  String omittedColumn(Object? Function(CommitteeLaneReceipt lane) column) =>
      canonicalCommitteeJson({
        for (final id in receipt.omittedRubricIds)
          id: switch (lanes[id]) {
            final CommitteeLaneReceipt lane => column(lane),
            null => null,
          },
      });

  return {
    'committeeShadowSampleId': receipt.sampleId,
    'committeeShadowJoinId': receipt.joinId,
    'committeeShadowPolicyVersion': run.policyVersion,
    'committeeShadowWorkBeadId': run.workBeadId,
    'committeeShadowRound': canonicalCommitteeJson(run.round),
    'committeeShadowNodePath': run.nodePath,
    'committeeShadowRouteNodePath': receipt.route.nodePath,
    'committeeShadowStage': run.stage.wire,
    'committeeShadowSource': selection.source.wire,
    'committeeShadowSelected': receipt.selectedRubricIds.join(','),
    'committeeShadowOmitted': receipt.omittedRubricIds.join(','),
    'committeeShadowMatchedRules': selection.matchedRuleIds.join(','),
    'committeeShadowEvidenceDigest': selection.evidenceDigest,
    'committeeShadowMissingEvidenceIds': run.evidence.missingEvidenceIds.join(
      ',',
    ),
    'committeeShadowLaneInputDigests': canonicalCommitteeJson(
      selection.laneInputDigests,
    ),
    'committeeShadowClassifierAttemptKinds': [
      for (final attempt in run.attempts) attempt.kind.wire,
    ].join(','),
    'committeeShadowActionLaneIds': receipt.actionLaneIds.join(','),
    'committeeShadowGateDisposition': switch (receipt.gateDisposition) {
      final GateDisposition disposition => _gateDispositionWire(disposition),
      null => canonicalCommitteeJson(null),
    },
    'committeeShadowDownstreamJoinKeys': canonicalCommitteeJson(
      receipt.downstreamJoinKeys,
    ),
    'committeeShadowOmittedLaneGrades': omittedColumn((lane) => lane.grade),
    'committeeShadowOmittedLaneTransports': omittedColumn(
      (lane) => lane.transport,
    ),
    'committeeShadowOmittedLaneDispositions': omittedColumn(
      (lane) => switch (lane.gateDisposition) {
        final GateDisposition disposition => _gateDispositionWire(disposition),
        null => null,
      },
    ),
    'committeeShadowActualContributingRunIds': receipt.actual.contributingRunIds
        .join(','),
    'committeeShadowActualMissingLaneIds': receipt.actual.missingLaneIds.join(
      ',',
    ),
    'committeeShadowActualTokensIn': canonicalCommitteeJson(
      receipt.actual.tokensIn,
    ),
    'committeeShadowActualTokensOut': canonicalCommitteeJson(
      receipt.actual.tokensOut,
    ),
    'committeeShadowActualCostUsd': canonicalCommitteeJson(
      receipt.actual.costUsd,
    ),
    'committeeShadowCounterfactualContributingRunIds': receipt
        .counterfactual
        .contributingRunIds
        .join(','),
    'committeeShadowCounterfactualMissingLaneIds': receipt
        .counterfactual
        .missingLaneIds
        .join(','),
    'committeeShadowCounterfactualTokensIn': canonicalCommitteeJson(
      receipt.counterfactual.tokensIn,
    ),
    'committeeShadowCounterfactualTokensOut': canonicalCommitteeJson(
      receipt.counterfactual.tokensOut,
    ),
    'committeeShadowCounterfactualCostUsd': canonicalCommitteeJson(
      receipt.counterfactual.costUsd,
    ),
    'committeeShadowTruncated': canonicalCommitteeJson(receipt.truncated),
    'committeeShadowMissingFields': receipt.missingFields.join(','),
    'committeeShadowLaneDecisions': _laneDecisionsColumn(selection),
    'committeeShadowPreviousRound': canonicalCommitteeJson(run.previous?.round),
    'committeeShadowPreservedLaneGrades': canonicalCommitteeJson({
      for (final lane in receipt.preservedLanes) lane.rubricId: lane.grade,
    }),
    'committeeShadowPreservedLaneTransports': canonicalCommitteeJson({
      for (final lane in receipt.preservedLanes) lane.rubricId: lane.transport,
    }),
  };
}

// ── persistence ─────────────────────────────────────────────────────────────

/// The workspace path one stage's selection run is persisted at.
String committeeSelectionRunPath(String workspaceDir, CommitteeStage stage) => p
    .join(workspaceDir, kCommitteeSelectionDir, '${stage.wire}.selection.json');

/// The workspace path one shadow receipt is persisted at.
String committeeShadowReceiptPath(String workspaceDir, String sampleId) =>
    p.join(workspaceDir, kCommitteeSelectionDir, 'receipts', '$sampleId.json');

/// The shadow artifacts' durable seam (Fakes, not mocks — the offline suite
/// always injects).
abstract interface class CommitteeSelectionStore {
  /// The stage's persisted run, or null when absent/unreadable/version-skewed.
  CommitteeSelectionRun? readRun(String workspaceDir, CommitteeStage stage);

  /// Persists [run] for its own stage.
  void writeRun(String workspaceDir, CommitteeSelectionRun run);

  /// Persists one shadow receipt.
  void writeReceipt(String workspaceDir, CommitteeShadowReceipt receipt);

  /// The receipt of the PREVIOUS round of [workBeadId]'s [stage] — the greatest
  /// recorded round strictly below [round] — or null when there is none.
  /// Read-only.
  ///
  /// Rounds are session-local ([committeeSelectionRound]): a governor rework
  /// remints round zero, so a rework's first round has no previous receipt and
  /// prior-fact comparison resumes only within that rework's own session.
  CommitteeShadowReceipt? readPreviousReceipt(
    String workspaceDir, {
    required CommitteeStage stage,
    required String workBeadId,
    required int round,
  });
}

/// The real [CommitteeSelectionStore]: strict versioned JSON under
/// [kCommitteeSelectionDir], written through a same-directory temporary file so
/// a reader never observes a half-written artifact.
///
/// It NEVER writes under `.grid/critique`, whose ownership stays with verdict
/// freshness. Reads are best-effort (the `readRespecLedger` posture): an absent,
/// unreadable or version-skewed artifact is simply "no run".
class FileCommitteeSelectionStore implements CommitteeSelectionStore {
  /// Creates the store.
  const FileCommitteeSelectionStore();

  @override
  CommitteeSelectionRun? readRun(String workspaceDir, CommitteeStage stage) {
    try {
      final file = File(committeeSelectionRunPath(workspaceDir, stage));
      if (!file.existsSync()) return null;
      return CommitteeSelectionRun.fromJson(
        jsonDecode(file.readAsStringSync()),
      );
    } on Object {
      return null;
    }
  }

  @override
  void writeRun(String workspaceDir, CommitteeSelectionRun run) =>
      _write(committeeSelectionRunPath(workspaceDir, run.stage), run.toJson());

  @override
  void writeReceipt(String workspaceDir, CommitteeShadowReceipt receipt) =>
      _write(
        committeeShadowReceiptPath(workspaceDir, receipt.sampleId),
        receipt.toJson(),
      );

  /// Scans the receipt directory, STRICTLY decoding every `*.json` artifact
  /// (an unreadable or version-skewed one is skipped, never half-read), and
  /// keeps the greatest round below [round] for the same bead and stage. Two
  /// receipts of that round tie-break on the greater sample id, so the answer
  /// never depends on directory order.
  ///
  /// The comparison is session-local: a governor rework remints round zero,
  /// so its first round finds nothing strictly below it and starts a new
  /// series rather than comparing against the previous session's receipts.
  @override
  CommitteeShadowReceipt? readPreviousReceipt(
    String workspaceDir, {
    required CommitteeStage stage,
    required String workBeadId,
    required int round,
  }) {
    final dir = Directory(
      p.dirname(committeeShadowReceiptPath(workspaceDir, '_')),
    );
    if (!dir.existsSync()) return null;
    CommitteeShadowReceipt? best;
    for (final entity in dir.listSync()) {
      if (entity is! File || p.extension(entity.path) != '.json') continue;
      final CommitteeShadowReceipt? receipt;
      try {
        receipt = CommitteeShadowReceipt.fromJson(
          jsonDecode(entity.readAsStringSync()),
        );
      } on Object {
        continue;
      }
      if (receipt == null) continue;
      final run = receipt.run;
      if (run.stage != stage ||
          run.workBeadId != workBeadId ||
          run.round >= round) {
        continue;
      }
      final current = best;
      if (current == null ||
          run.round > current.run.round ||
          (run.round == current.run.round &&
              receipt.sampleId.compareTo(current.sampleId) > 0)) {
        best = receipt;
      }
    }
    return best;
  }

  void _write(String path, Map<String, Object?> json) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final temporary = File('$path.$pid.${_writeToken++}.tmp')
      ..writeAsStringSync(jsonEncode(json), flush: true);
    temporary.renameSync(path);
  }
}

int _writeToken = 0;

// ── the shadow selector capability ──────────────────────────────────────────

/// The SHADOW selector — one [ServiceCapability] per review circuit, mounted
/// BESIDE the full committee and depended on by nothing.
///
/// It classifies DETERMINISTICALLY ([CommitteeSelectionPolicy.classify]) and
/// launches no process: no classifier, no model, no sibling. It always
/// resolves to [Ok] and never carries a `grade`: it cannot [Escalate], cannot
/// [Rewind], cannot report [Failed], and never invokes another circuit node.
/// Every failure it meets — an unreadable artifact, an unreadable previous
/// receipt, a refused write — becomes typed provenance in the persisted run.
class CommitteeSelectionCapability extends ServiceCapability {
  /// Creates the selector over its two injected seams and a defaulted policy
  /// (the ambient `InheritedSeed<CommitteeSelectionPolicy>` wins when mounted).
  const CommitteeSelectionCapability({
    required this.evidenceSource,
    required this.store,
    this.policy = kCommitteeSelectionPolicy,
  });

  /// The stage-evidence adapter.
  final CommitteeSelectionEvidenceSource evidenceSource;

  /// The durable shadow store — written for this run, read for the previous
  /// round's receipt.
  final CommitteeSelectionStore store;

  /// The policy used when the tree mounts none.
  final CommitteeSelectionPolicy policy;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // The EFFECT verb (ADR-0008 D3): read every ambient value once, at the run
    // edge, while mounted.
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final activePolicy =
        context.getInheritedSeedOfExactType<CommitteeSelectionPolicy>() ??
        policy;

    final stage = CommitteeStage.fromWire(
      args.params[kCommitteeSelectionStageParam],
    );
    final fullRubricIds = committeeCsv(args.params[kCommitteeFullRubricsParam]);
    final gatingRubricIds = committeeCsv(
      args.params[kCommitteeGatingRubricsParam],
    );
    final round = committeeSelectionRound(args);
    final workBeadId = bead?.id ?? args.beadId;
    final workspaceDir = workspace?.workspaceDir ?? '';

    // A shadow lane never gates, so an unusable step declaration is RECORDED
    // and returned as Ok — the full committee beside it is untouched either way.
    if (stage == null || fullRubricIds.isEmpty) {
      return Ok({
        'shadow': 'skipped',
        'missingFields': stage == null
            ? kCommitteeSelectionStageParam
            : kCommitteeFullRubricsParam,
      });
    }

    final missingFields = <String>[];
    CommitteeSelectionEvidence evidence;
    try {
      evidence = evidenceSource.read(
        stage: stage,
        workBeadId: workBeadId,
        workspaceDir: workspaceDir,
      );
    } on Object catch (error) {
      missingFields.add('evidence-source:$error');
      evidence = CommitteeSelectionEvidence(
        stage: stage,
        workBeadId: workBeadId,
        round: round,
        missingEvidenceIds: const ['evidence-source'],
      );
    }

    // The previous round is captured BEFORE this run is written, and rides the
    // run itself so a replay needs no store.
    CommitteePreviousRound? previous;
    if (workspaceDir.isNotEmpty) {
      try {
        final receipt = store.readPreviousReceipt(
          workspaceDir,
          stage: stage,
          workBeadId: workBeadId,
          round: round,
        );
        if (receipt != null) {
          previous = CommitteePreviousRound.fromReceipt(receipt);
        }
      } on Object catch (error) {
        missingFields.add('previous-receipt:$error');
      }
    }

    final run = CommitteeSelectionRun(
      policyVersion: activePolicy.policyVersion,
      stage: stage,
      workBeadId: workBeadId,
      round: round,
      nodePath: args.nodePath,
      selection: activePolicy.classify(
        evidence: evidence,
        fullRubricIds: fullRubricIds,
        gatingRubricIds: gatingRubricIds,
        previous: previous,
      ),
      evidence: evidence,
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
      missingFields: missingFields,
      previous: previous,
    );

    // The DURABLE copy: the store write below lands in the per-round worktree
    // and is reaped with it, so the whole evidence packet also rides the step
    // result, which the engine appends beside the step transition.
    final payload = committeeSelectionResultProjection(run);
    if (workspaceDir.isEmpty) {
      return Ok({...payload, 'missingFields': 'workspace'});
    }
    try {
      store.writeRun(workspaceDir, run);
    } on Object catch (error) {
      return Ok({...payload, 'missingFields': 'selection-write:$error'});
    }
    if (missingFields.isEmpty) return Ok(payload);
    return Ok({...payload, 'missingFields': missingFields.join('; ')});
  }
}

// ── the shadow route wrapper ────────────────────────────────────────────────

/// The result keys ONE committee lane records — the columns a shadow receipt
/// reads back off the ambient [SiblingView].
abstract final class CommitteeLaneResultKeys {
  /// The letter grade.
  static const String grade = 'grade';

  /// Which channel produced the grade.
  static const String transport = 'transport';

  /// The lane's own rationale.
  static const String rationale = 'rationale';

  /// Who can fix an actionable grade.
  static const String owner = 'owner';

  /// The lane's non-grading bead-graph observation.
  static const String refinement = 'refinement';

  /// The FT-2 usage columns.
  static const String tokensIn = 'tokensIn';

  /// See [tokensIn].
  static const String tokensOut = 'tokensOut';

  /// See [tokensIn].
  static const String costUsd = 'costUsd';

  /// See [tokensIn].
  static const String premiumRequests = 'premiumRequests';

  /// See [tokensIn].
  static const String numTurns = 'numTurns';

  /// See [tokensIn].
  static const String harnessDurationMs = 'harnessDurationMs';

  /// The model that actually served the lane.
  static const String model = 'model';
}

/// The route payload key carrying the finding an advance forwarded.
const String kCommitteeFixInFlightFindingKey = 'fix_in_flight_finding';

/// The AUTHORITATIVE route, wrapped in shadow bookkeeping.
///
/// It delegates once, writes a receipt beside the answer, and rules exactly
/// what the delegate ruled. A [Rewind] and an [Escalate] carry no result map,
/// so there is nowhere to promote to and the delegate's own OBJECT comes back;
/// an [Advance] comes back carrying its whole payload plus the RESERVED
/// `committeeShadow*` entries of [committeeShadowResultProjection], which is
/// the receipt's only durable copy once the worktree is reaped.
///
/// It never converts, decorates, waits for or substitutes the RULING, and
/// every shadow read/codec/write exception is swallowed — a telemetry failure
/// must not change a routing decision, and a failed artifact write in
/// particular never discards an already-built projection.
class CommitteeShadowRouteCapability extends RouteCapability {
  /// Wraps [delegate], writing receipts through [store].
  const CommitteeShadowRouteCapability({
    required this.delegate,
    required this.store,
    this.policy = kCommitteeSelectionPolicy,
  });

  /// The authoritative route this defers to, unchanged.
  final RouteCapability delegate;

  /// The durable shadow store.
  final CommitteeSelectionStore store;

  /// The policy used when the tree mounts none.
  final CommitteeSelectionPolicy policy;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Capture at ENTRY, before the delegate's await: nothing ambient is read
    // afterwards, so an unmount during the delegate can never be touched here.
    final captured = _CommitteeShadowRouteInput.capture(context, args, policy);
    final verdict = await delegate.route(context, args);
    final input = captured;
    CommitteeShadowReceipt? built;
    if (input != null) {
      try {
        built = input.receiptFor(verdict, store: store);
      } on Object {
        // Shadow telemetry is non-authoritative: a receipt we could not build
        // changes nothing about the verdict below.
      }
      final receipt = built;
      if (receipt != null) {
        try {
          store.writeReceipt(input.workspaceDir, receipt);
        } on Object {
          // The worktree artifact is the IN-ROUND working copy and is written
          // best-effort; losing it never discards the durable projection.
        }
      }
    }
    final receipt = built;
    if (receipt == null) return verdict;
    // The durable copy rides the ONE result carrier the verdict already has.
    // A rewind and an escalate carry none, so they come back as the delegate's
    // own OBJECT — identical, field for field.
    return switch (verdict) {
      Advance(:final payload) => Advance({
        ...?payload,
        ...committeeShadowResultProjection(receipt),
      }),
      Rewind() => verdict,
      Escalate() => verdict,
    };
  }

  @override
  Future<void> teardown(StepArgs args) => delegate.teardown(args);

  @override
  SupervisionPolicy supervisionPolicy(StepArgs args) =>
      delegate.supervisionPolicy(args);
}

/// Everything the shadow route read from the tree, frozen at entry.
class _CommitteeShadowRouteInput {
  _CommitteeShadowRouteInput({
    required this.stage,
    required this.workBeadId,
    required this.round,
    required this.nodePath,
    required this.workspaceDir,
    required this.fullRubricIds,
    required this.gatingRubricIds,
    required this.siblings,
    required this.policy,
  });

  final CommitteeStage stage;
  final String workBeadId;
  final int round;
  final String nodePath;
  final String workspaceDir;
  final List<String> fullRubricIds;
  final List<String> gatingRubricIds;
  final SiblingView siblings;
  final CommitteeSelectionPolicy policy;

  static _CommitteeShadowRouteInput? capture(
    TreeContext context,
    StepArgs args,
    CommitteeSelectionPolicy fallback,
  ) {
    final stage = CommitteeStage.fromWire(
      args.params[kCommitteeSelectionStageParam],
    );
    final full = committeeCsv(args.params['critics']);
    if (stage == null || full.isEmpty) return null;
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final workspaceDir = workspace?.workspaceDir ?? '';
    if (workspaceDir.isEmpty) return null;
    final bead = context.getInheritedSeedOfExactType<Bead>();
    return _CommitteeShadowRouteInput(
      stage: stage,
      workBeadId: bead?.id ?? args.beadId,
      round: committeeSelectionRound(args),
      nodePath: args.nodePath,
      workspaceDir: workspaceDir,
      fullRubricIds: full,
      gatingRubricIds: committeeCsv(args.params['gating']),
      siblings:
          context.getInheritedSeedOfExactType<SiblingView>() ??
          const SiblingView(),
      policy:
          context.getInheritedSeedOfExactType<CommitteeSelectionPolicy>() ??
          fallback,
    );
  }

  CommitteeShadowReceipt receiptFor(
    RouteVerdict verdict, {
    required CommitteeSelectionStore store,
  }) {
    final route = committeeRouteObservationOf(verdict, nodePath: nodePath);
    final missingFields = <String>[];
    final persisted = store.readRun(workspaceDir, stage);
    final fresh =
        persisted != null &&
        persisted.isFreshFor(
          stage: stage,
          workBeadId: workBeadId,
          round: round,
        );
    if (persisted == null) missingFields.add('selection-run:absent');
    if (persisted != null && !fresh) missingFields.add('selection-run:stale');

    // A run that is absent, stale or unreadable when the route joins is an
    // explicit FULL FALLBACK — the route never waits for, or launches,
    // selection work of its own.
    final run = fresh
        ? persisted
        : CommitteeSelectionRun(
            policyVersion: policy.policyVersion,
            stage: stage,
            workBeadId: workBeadId,
            round: round,
            nodePath: nodePath,
            evidence: _emptyEvidence,
            selection: policy.selectFullFallback(
              evidence: _emptyEvidence,
              fullRubricIds: fullRubricIds,
              gatingRubricIds: gatingRubricIds,
            ),
            fullRubricIds: fullRubricIds,
            gatingRubricIds: gatingRubricIds,
            missingFields: const ['selection-run'],
          );

    final parent = committeeSelectionParentPath(nodePath);
    return buildCommitteeShadowReceipt(
      run: run,
      route: route,
      lanes: [
        for (final rubricId in run.fullRubricIds)
          _laneReceiptFor(rubricId, parent: parent, route: route, run: run),
      ],
      missingFields: missingFields,
    );
  }

  CommitteeSelectionEvidence get _emptyEvidence => CommitteeSelectionEvidence(
    stage: stage,
    workBeadId: workBeadId,
    round: round,
    missingEvidenceIds: const ['selection-run'],
  );

  CommitteeLaneReceipt _laneReceiptFor(
    String rubricId, {
    required String parent,
    required CommitteeRouteObservation route,
    required CommitteeSelectionRun run,
  }) {
    final laneNodePath = parent.isEmpty ? rubricId : '$parent/$rubricId';
    final result = siblings.resultOf(laneNodePath);
    final finding = route.payload[kCommitteeFixInFlightFindingKey];
    return CommitteeLaneReceipt.derive(
      rubricId: rubricId,
      nodePath: laneNodePath,
      workBeadId: workBeadId,
      routeType: route.type,
      gating: run.gatingRubricIds.contains(rubricId),
      grade: result[CommitteeLaneResultKeys.grade],
      transport: result[CommitteeLaneResultKeys.transport],
      rationale: result[CommitteeLaneResultKeys.rationale],
      finding: finding == null || finding.trim().isEmpty ? null : finding,
      owner: result[CommitteeLaneResultKeys.owner],
      refinement: result[CommitteeLaneResultKeys.refinement],
      model: result[CommitteeLaneResultKeys.model],
      tokensIn: _asInt(result[CommitteeLaneResultKeys.tokensIn]),
      tokensOut: _asInt(result[CommitteeLaneResultKeys.tokensOut]),
      costUsd: _asNum(result[CommitteeLaneResultKeys.costUsd]),
      premiumRequests: _asNum(result[CommitteeLaneResultKeys.premiumRequests]),
      numTurns: _asInt(result[CommitteeLaneResultKeys.numTurns]),
      durationMs: _asInt(result[CommitteeLaneResultKeys.harnessDurationMs]),
      truncated: run.evidence.truncated,
    );
  }
}

// ── decoding helpers ────────────────────────────────────────────────────────

List<String> _sortedSet(Iterable<String> values) => List.unmodifiable(
  {
    for (final value in values)
      if (value.trim().isNotEmpty) value.trim(),
  }.toList()..sort(),
);

List<String>? _stringList(Object? json) {
  if (json == null) return const [];
  if (json is! List) return null;
  final out = <String>[];
  for (final entry in json) {
    if (entry is! String) return null;
    out.add(entry);
  }
  return out;
}

Map<String, String>? _stringMap(Object? json) {
  if (json == null) return const {};
  if (json is! Map) return null;
  final out = <String, String>{};
  for (final entry in json.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || value is! String) return null;
    out[key] = value;
  }
  return out;
}

int? _asInt(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text.trim()),
  _ => null,
};

num? _asNum(Object? value) => switch (value) {
  final num number => number,
  final String text => num.tryParse(text.trim()),
  _ => null,
};

double? _asDouble(Object? value) => switch (value) {
  final num number => number.toDouble(),
  final String text => double.tryParse(text.trim()),
  _ => null,
};

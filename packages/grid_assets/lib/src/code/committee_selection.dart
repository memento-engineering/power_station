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
///  - [CommitteeShadowRouteCapability] returns the authoritative route's
///    verdict OBJECT unchanged; it only writes a receipt beside it.
///
/// **Selection is stage-specific.** `spec_review` reasons over the round-stamped
/// discovery artifacts (intent, decisions, paths, prior art); `code_review`
/// reasons over the actual pinned `origin/<base>...HEAD` diff, supplemented by
/// the same dossier. Each stage digests its own evidence
/// ([CommitteeSelectionPolicy.evidenceDigestOf]) and the two digests can never
/// collide, because the stage wire value is hashed in.
///
/// **Deterministic rules are ADDITIVE.** Every rule of the stage is evaluated,
/// every match unions its semantic lanes, and the required deterministic gates
/// are always added back. Only a change no rule recognises — an UNKNOWN shape —
/// reaches the bounded classifier, which may pick only from the closed
/// [kCommitteeClassifierAllowlist]. Missing, malformed, unsuccessful or unknown
/// classifier output is a TYPED NON-RESULT ([CommitteeClassifierResultKind]),
/// never a grade: it retries that one lane once, and a second non-result records
/// [CommitteeSelectionSource.fullFallback] over the current full committee.
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
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_trajectory/grid_trajectory.dart'
    show GateDisposition, LaneReport, UsageSample;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_environment.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/model_tier.dart';
import '../agent/seat_environments.dart';
import '../agent/site_binding.dart';
import '../agent/typed_environment.dart';
import '../agent/usage_report.dart';

// ── identity ────────────────────────────────────────────────────────────────

/// This policy's version stamp — every persisted artifact carries it, and a
/// decoder refuses any other value rather than reading an older shape as if it
/// were this one.
const String kCommitteeSelectionPolicyVersion = '1';

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
/// lanes are ALWAYS selected, whatever the rules or the classifier say.
const String kCommitteeGatingRubricsParam = 'committeeGatingRubrics';

/// The workspace-relative directory the shadow artifacts live in — deliberately
/// NOT `.grid/critique`, whose ownership stays with verdict freshness
/// (`power_station#a4-gate-integrity-3-bead-tg-bns-the-verdict-freshness-stamp`).
const String kCommitteeSelectionDir = '.grid/committee-selection';

/// How many times ONE unknown-shape classification may run in a single
/// capability invocation: the first call, plus exactly one retry.
const int kCommitteeClassifierAttempts = 2;

/// The CLOSED set of semantic rubric ids a classifier may name. An answer
/// carrying anything else is rejected WHOLE
/// ([CommitteeClassifierResultKind.unknown]) rather than filtered down to the
/// legal subset — a model that named an id we do not run did not understand the
/// question, and half-believing it would launder that.
const Set<String> kCommitteeClassifierAllowlist = {
  'coherence',
  'decision-alignment',
  'acceptance-testability',
  'plan-completeness',
  'spec-adherence',
  'regression-risk',
  'test-coverage',
};

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
  /// One or more deterministic rules matched; no inference ran.
  deterministic,

  /// No rule matched and the bounded classifier answered inside the allowlist.
  classifier,

  /// No rule matched and the classifier produced two non-results — the current
  /// FULL committee is selected, unchanged.
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

/// What one classifier call produced. Three of the four arms are NON-RESULTS:
/// they are facts about the call, never a judgement about the work, and none of
/// them is ever a letter grade.
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

  /// True when nothing at all was resolved — the shape a rule cannot recognise
  /// and the classifier exists for.
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

/// File extensions (without the separator) that make a changed path PROSE.
const Set<String> kCommitteeProseExtensions = {'md', 'markdown'};

/// File extensions (without the separator) that make a changed path METADATA —
/// a manifest, a lock, a config. A pubspec is covered by the first of these.
const Set<String> kCommitteeMetadataExtensions = {'yaml', 'yml', 'json'};

/// Extension-free basenames that make a changed path METADATA.
const Set<String> kCommitteeMetadataBasenames = {'CHANGELOG', 'LICENSE'};

/// Whether [path] is a TEST surface — a `test` root, a nested `test` directory,
/// or a Dart test file.
bool isCommitteeTestPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.startsWith('test/') ||
      normalized.contains('/test/') ||
      _basename(normalized).endsWith('_test.dart');
}

/// Whether [path] is prose or metadata — the shapes with no runtime behaviour
/// to regress and no test to cover.
bool isCommitteeProseOrMetadataPath(String path) {
  final extension = _extension(path);
  if (kCommitteeProseExtensions.contains(extension)) return true;
  if (kCommitteeMetadataExtensions.contains(extension)) return true;
  final base = _basename(path);
  final dot = base.indexOf('.');
  final stem = dot < 0 ? base : base.substring(0, dot);
  return kCommitteeMetadataBasenames.contains(stem.toUpperCase());
}

/// Whether [path] carries RUNTIME behaviour — anything that is neither a test
/// surface nor prose/metadata.
bool isCommitteeRuntimePath(String path) =>
    !isCommitteeTestPath(path) && !isCommitteeProseOrMetadataPath(path);

String _basename(String path) => path.split('/').last;

String _extension(String path) {
  final base = _basename(path);
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? '' : base.substring(dot + 1).toLowerCase();
}

// ── the rules ───────────────────────────────────────────────────────────────

/// The EIGHT deterministic selection rules — the whole policy, as const values.
///
/// Rules are ADDITIVE: every rule of the stage is evaluated and every match
/// unions its lanes. There is no precedence and no first-match-wins, because a
/// change that is both a runtime change and a decision-sensitive one needs both
/// answers.
enum CommitteeSelectionRule {
  /// The bead states an intent, so COHERENCE has something to judge.
  specIntent('spec-intent', CommitteeStage.specReview, ['coherence']),

  /// Recorded decisions govern the touched surfaces.
  specDecisions('spec-decisions', CommitteeStage.specReview, [
    'decision-alignment',
  ]),

  /// The bead states acceptance criteria to test for testability.
  specAcceptance('spec-acceptance', CommitteeStage.specReview, [
    'acceptance-testability',
  ]),

  /// The bead names surfaces (path anchors or prior art), so the PLAN can be
  /// checked for completeness against them.
  specSurface('spec-surface', CommitteeStage.specReview, ['plan-completeness']),

  /// The diff touches runtime behaviour — the full semantic code committee.
  codeRuntime('code-runtime', CommitteeStage.codeReview, [
    'spec-adherence',
    'regression-risk',
    'test-coverage',
  ]),

  /// The diff touches test surfaces.
  codeTests('code-tests', CommitteeStage.codeReview, [
    'spec-adherence',
    'test-coverage',
  ]),

  /// EVERY changed path is prose or metadata — nothing to regress, nothing to
  /// cover, so only adherence remains.
  codeDocsMetadata('code-docs-metadata', CommitteeStage.codeReview, [
    'spec-adherence',
  ]),

  /// Recorded decisions govern the touched surfaces — the blast radius is
  /// wider than the diff looks.
  codeDecisionSensitive('code-decision-sensitive', CommitteeStage.codeReview, [
    'regression-risk',
  ]);

  const CommitteeSelectionRule(this.id, this.stage, this.rubricIds);

  /// This rule's stable id — persisted in every selection.
  final String id;

  /// The stage this rule belongs to; a rule never fires for the other stage.
  final CommitteeStage stage;

  /// The SEMANTIC lanes this rule selects when it matches.
  final List<String> rubricIds;

  /// Whether [evidence] matches this rule. Pure over the normalized facts.
  bool matches(CommitteeSelectionEvidence evidence) {
    if (evidence.stage != stage) return false;
    return switch (this) {
      CommitteeSelectionRule.specIntent => evidence.intent.isNotEmpty,
      CommitteeSelectionRule.specDecisions => evidence.decisions.isNotEmpty,
      CommitteeSelectionRule.specAcceptance => evidence.acceptance.isNotEmpty,
      CommitteeSelectionRule.specSurface =>
        evidence.paths.isNotEmpty || evidence.priorArt.isNotEmpty,
      CommitteeSelectionRule.codeRuntime => evidence.changedPaths.any(
        isCommitteeRuntimePath,
      ),
      CommitteeSelectionRule.codeTests => evidence.changedPaths.any(
        isCommitteeTestPath,
      ),
      CommitteeSelectionRule.codeDocsMetadata =>
        evidence.changedPaths.isNotEmpty &&
            evidence.changedPaths.every(isCommitteeProseOrMetadataPath),
      CommitteeSelectionRule.codeDecisionSensitive =>
        evidence.decisions.isNotEmpty,
    };
  }

  /// The rule [id] names, or null when it names none.
  static CommitteeSelectionRule? fromId(Object? id) {
    for (final rule in CommitteeSelectionRule.values) {
      if (rule.id == id) return rule;
    }
    return null;
  }
}

/// What the deterministic half of the policy concluded: which rules fired and
/// which SEMANTIC lanes they union to. Empty [ruleIds] is the UNKNOWN shape —
/// the only case a classifier is ever reached for.
typedef CommitteeDeterministicMatch = ({
  List<String> ruleIds,
  List<String> rubricIds,
});

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
  }) : matchedRuleIds = List.unmodifiable(matchedRuleIds),
       selectedRubricIds = List.unmodifiable(selectedRubricIds),
       laneInputDigests = Map.unmodifiable(laneInputDigests);

  /// The policy version that produced this selection.
  final String policyVersion;

  /// The digest of the stage evidence it was computed over.
  final String evidenceDigest;

  /// Which deterministic rules fired, in declaration order. Empty for a
  /// classifier or full-fallback selection.
  final List<String> matchedRuleIds;

  /// The hypothetical roster, in the ACTIVE committee's declaration order.
  final List<String> selectedRubricIds;

  /// Which channel produced it.
  final CommitteeSelectionSource source;

  /// Every ACTIVE lane's input digest — selected or omitted, so a later
  /// comparison can tell a lane whose inputs changed from one whose did not.
  final Map<String, String> laneInputDigests;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'policyVersion': policyVersion,
    'evidenceDigest': evidenceDigest,
    'matchedRuleIds': matchedRuleIds,
    'selectedRubricIds': selectedRubricIds,
    'source': source.wire,
    'laneInputDigests': laneInputDigests,
  };

  /// Decodes a selection STRICTLY; an unknown source wire, a non-string lane
  /// digest, or a missing digest yields null.
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
    return CommitteeSelection(
      policyVersion: policyVersion,
      evidenceDigest: evidenceDigest,
      matchedRuleIds: matched,
      selectedRubricIds: selected,
      source: source,
      laneInputDigests: digests,
    );
  }
}

/// The pure policy: the rules, the digests and the composition of a
/// [CommitteeSelection]. Immutable, const-constructible and cache-free — it is a
/// VALUE the tree carries, re-read on every build (ADR-0008 D-H).
@immutable
final class CommitteeSelectionPolicy {
  /// Creates the policy at [policyVersion].
  const CommitteeSelectionPolicy({
    this.policyVersion = kCommitteeSelectionPolicyVersion,
  });

  /// The version stamped into every selection and hashed into every digest.
  final String policyVersion;

  /// The rules that belong to [stage], in declaration order.
  List<CommitteeSelectionRule> rulesFor(CommitteeStage stage) => [
    for (final rule in CommitteeSelectionRule.values)
      if (rule.stage == stage) rule,
  ];

  /// Evaluates EVERY rule of the evidence's stage and unions the lanes of every
  /// match. Additive by construction: no rule shadows another.
  CommitteeDeterministicMatch match(CommitteeSelectionEvidence evidence) {
    final ruleIds = <String>[];
    final rubricIds = <String>{};
    for (final rule in rulesFor(evidence.stage)) {
      if (!rule.matches(evidence)) continue;
      ruleIds.add(rule.id);
      rubricIds.addAll(rule.rubricIds);
    }
    return (ruleIds: ruleIds, rubricIds: rubricIds.toList()..sort());
  }

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
        'facts': _laneFacts(id, evidence, gatingRubricIds),
      }),
  };

  /// The DETERMINISTIC selection for [evidence]. An empty
  /// [CommitteeSelection.matchedRuleIds] means no rule recognised the shape —
  /// the caller may then classify.
  CommitteeSelection selectDeterministic({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
  }) {
    final matched = match(evidence);
    return _compose(
      evidence: evidence,
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
      source: CommitteeSelectionSource.deterministic,
      matchedRuleIds: matched.ruleIds,
      requestedRubricIds: matched.rubricIds,
    );
  }

  /// The selection for an ACCEPTED classifier answer.
  CommitteeSelection selectFromClassifier({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
    required List<String> classifierRubricIds,
  }) => _compose(
    evidence: evidence,
    fullRubricIds: fullRubricIds,
    gatingRubricIds: gatingRubricIds,
    source: CommitteeSelectionSource.classifier,
    matchedRuleIds: const [],
    requestedRubricIds: classifierRubricIds,
  );

  /// The FULL current committee — what a second classifier non-result falls
  /// back to, and what an unreadable selection run means downstream.
  CommitteeSelection selectFullFallback({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
  }) => _compose(
    evidence: evidence,
    fullRubricIds: fullRubricIds,
    gatingRubricIds: gatingRubricIds,
    source: CommitteeSelectionSource.fullFallback,
    matchedRuleIds: const [],
    requestedRubricIds: fullRubricIds,
  );

  CommitteeSelection _compose({
    required CommitteeSelectionEvidence evidence,
    required List<String> fullRubricIds,
    required List<String> gatingRubricIds,
    required CommitteeSelectionSource source,
    required List<String> matchedRuleIds,
    required List<String> requestedRubricIds,
  }) {
    // The gates are UNCONDITIONAL, and an id outside the active roster is
    // dropped: this policy may never invent a lane the committee does not run.
    final wanted = <String>{...requestedRubricIds, ...gatingRubricIds};
    return CommitteeSelection(
      policyVersion: policyVersion,
      evidenceDigest: evidenceDigestOf(evidence),
      matchedRuleIds: matchedRuleIds,
      selectedRubricIds: [
        for (final id in fullRubricIds)
          if (wanted.contains(id)) id,
      ],
      source: source,
      laneInputDigests: laneInputDigests(
        evidence: evidence,
        fullRubricIds: fullRubricIds,
        gatingRubricIds: gatingRubricIds,
      ),
    );
  }

  /// The FACTS one lane actually reads. An unrecognised ACTIVE lane hashes the
  /// COMPLETE stage evidence, so a lane somebody adds is explicit rather than
  /// silently digested over nothing.
  Map<String, Object?> _laneFacts(
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
      'decisions': evidence.decisions,
      'paths': evidence.paths,
    },
    'acceptance-testability' => {
      'intent': evidence.intent,
      'acceptance': evidence.acceptance,
    },
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
}

/// The policy every circuit mounts by default.
const CommitteeSelectionPolicy kCommitteeSelectionPolicy =
    CommitteeSelectionPolicy();

// ── the bounded classifier ──────────────────────────────────────────────────

/// ONE classifier call's outcome. Three of the four kinds are NON-RESULTS.
@immutable
final class CommitteeClassifierResult {
  const CommitteeClassifierResult._(
    this.kind, {
    this.rubricIds = const [],
    this.rejectedRubricIds = const [],
  });

  /// A well-formed, entirely-legal answer over [rubricIds].
  factory CommitteeClassifierResult.selected(Iterable<String> rubricIds) =>
      CommitteeClassifierResult._(
        CommitteeClassifierResultKind.selected,
        rubricIds: List.unmodifiable(rubricIds),
      );

  /// No output at all.
  const CommitteeClassifierResult.missing()
    : this._(CommitteeClassifierResultKind.missing);

  /// Output that does not decode into the one legal shape.
  const CommitteeClassifierResult.malformed()
    : this._(CommitteeClassifierResultKind.malformed);

  /// Output naming at least one rubric id we do not run — refused WHOLE, with
  /// the offending ids preserved as provenance.
  factory CommitteeClassifierResult.unknown(Iterable<String> rejected) =>
      CommitteeClassifierResult._(
        CommitteeClassifierResultKind.unknown,
        rejectedRubricIds: List.unmodifiable(rejected),
      );

  /// What this call produced.
  final CommitteeClassifierResultKind kind;

  /// The accepted lanes (empty for every non-result).
  final List<String> rubricIds;

  /// The ids that made the answer [CommitteeClassifierResultKind.unknown].
  final List<String> rejectedRubricIds;

  /// Whether this is the one kind that ends the retry loop.
  bool get isSelected => kind == CommitteeClassifierResultKind.selected;
}

/// Decodes ONE classifier answer STRICTLY.
///
/// The legal shape is a single JSON object with EXACTLY a `rubricIds` list of
/// non-empty strings. Null/blank output maps to
/// [CommitteeClassifierResultKind.missing]; a decode failure, a non-object, a
/// non-list, an empty list or an extra key maps to
/// [CommitteeClassifierResultKind.malformed]; any id outside
/// [kCommitteeClassifierAllowlist] or outside [activeSemanticRubricIds] rejects
/// the WHOLE answer as [CommitteeClassifierResultKind.unknown]. A valid answer
/// is deduplicated and reordered by the active committee. No arm is a grade.
CommitteeClassifierResult parseCommitteeClassifierResult(
  String? output, {
  required List<String> activeSemanticRubricIds,
}) {
  if (output == null || output.trim().isEmpty) {
    return const CommitteeClassifierResult.missing();
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(output.trim());
  } on Object {
    return const CommitteeClassifierResult.malformed();
  }
  if (decoded is! Map ||
      decoded.keys.map((key) => '$key').toSet().difference({
        'rubricIds',
      }).isNotEmpty) {
    return const CommitteeClassifierResult.malformed();
  }
  final raw = decoded['rubricIds'];
  if (raw is! List ||
      raw.isEmpty ||
      raw.any((id) => id is! String || id.trim().isEmpty)) {
    return const CommitteeClassifierResult.malformed();
  }
  final requested = {for (final id in raw) (id as String).trim()};
  final active = activeSemanticRubricIds.toSet();
  if (!kCommitteeClassifierAllowlist.containsAll(requested) ||
      !active.containsAll(requested)) {
    return CommitteeClassifierResult.unknown(requested.toList()..sort());
  }
  return CommitteeClassifierResult.selected([
    for (final id in activeSemanticRubricIds)
      if (requested.contains(id)) id,
  ]);
}

/// The injected one-shot classifier seam — the SAME shape the delivery
/// describe pass's runner answers with, so `buildCodeRegistry` adapts the
/// existing [InferenceRunner] rather than growing a second process abstraction.
typedef CommitteeClassifier =
    Future<({bool ok, String output})> Function(RuntimeConfig config);

/// ONE classifier call, recorded — including the ones that produced nothing.
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
/// it was computed over, and every classifier attempt (including the ones that
/// produced nothing).
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

  /// Every classifier attempt, in call order. Empty for a deterministic match.
  final List<CommitteeClassifierAttempt> attempts;

  /// Everything this run could not do, named. Shadow-only: it never gates.
  final List<String> missingFields;

  /// Whether [workBeadId]/[round]/[stage] match the joining route's.
  bool isFreshFor({
    required CommitteeStage stage,
    required String workBeadId,
    required int round,
  }) =>
      this.stage == stage &&
      this.workBeadId == workBeadId &&
      this.round == round;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 1,
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
  };

  /// Decodes a run STRICTLY: any `version` but 1, an unknown stage, a negative
  /// round, a refused selection/evidence, or ANY malformed attempt yields null.
  static CommitteeSelectionRun? fromJson(Object? json) {
    if (json is! Map || json['version'] != 1) return null;
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
    final rawAttempts = json['attempts'];
    if (rawAttempts is! List) return null;
    final attempts = <CommitteeClassifierAttempt>[];
    for (final entry in rawAttempts) {
      final attempt = CommitteeClassifierAttempt.fromJson(entry);
      if (attempt == null) return null;
      attempts.add(attempt);
    }
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
  }) : selectedRubricIds = List.unmodifiable(selectedRubricIds),
       omittedRubricIds = List.unmodifiable(omittedRubricIds),
       lanes = List.unmodifiable(lanes),
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

  /// The lanes that graded `D`, `E` or `F` — this pack's action set.
  final List<String> actionLaneIds;

  /// The route-level gate disposition, when any lane was adverse.
  final GateDisposition? gateDisposition;

  /// The keys a downstream fold joins this sample on.
  final Map<String, String> downstreamJoinKeys;

  /// What the FULL committee actually spent.
  final CommitteeUsageAccounting actual;

  /// What the CLASSIFIER spent (empty for a deterministic match).
  final CommitteeUsageAccounting classifier;

  /// What the SELECTED committee plus the classifier WOULD have spent.
  final CommitteeUsageAccounting counterfactual;

  /// Whether any contributing artifact reported itself clipped.
  final bool truncated;

  /// Everything this receipt could not resolve, named.
  final List<String> missingFields;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 1,
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
  };

  /// Decodes a receipt STRICTLY: any `version` but 1, a refused run/route/lane/
  /// accounting block, or a present-but-unknown gate disposition yields null.
  static CommitteeShadowReceipt? fromJson(Object? json) {
    if (json is! Map || json['version'] != 1) return null;
    final run = CommitteeSelectionRun.fromJson(json['run']);
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
    if (run == null ||
        route == null ||
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
    final rawLanes = json['lanes'];
    if (rawLanes is! List) return null;
    final lanes = <CommitteeLaneReceipt>[];
    for (final entry in rawLanes) {
      final lane = CommitteeLaneReceipt.fromJson(entry);
      if (lane == null) return null;
      lanes.add(lane);
    }
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
    );
  }
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
/// omission set and accounting block below is computed here, so a replay over
/// the recorded columns reproduces the receipt byte for byte.
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
  );
}

/// Re-derives [recorded]'s selection from its OWN retained evidence and
/// attempts — the pure half of replay.
CommitteeSelectionRun replayCommitteeSelectionRun(
  CommitteeSelectionRun recorded,
) {
  final policy = CommitteeSelectionPolicy(
    policyVersion: recorded.policyVersion,
  );
  final matched = policy.match(recorded.evidence);
  final accepted = [
    for (final attempt in recorded.attempts)
      if (attempt.kind == CommitteeClassifierResultKind.selected) attempt,
  ];
  final CommitteeSelection selection;
  if (matched.ruleIds.isNotEmpty) {
    selection = policy.selectDeterministic(
      evidence: recorded.evidence,
      fullRubricIds: recorded.fullRubricIds,
      gatingRubricIds: recorded.gatingRubricIds,
    );
  } else if (accepted.isEmpty) {
    selection = policy.selectFullFallback(
      evidence: recorded.evidence,
      fullRubricIds: recorded.fullRubricIds,
      gatingRubricIds: recorded.gatingRubricIds,
    );
  } else {
    selection = policy.selectFromClassifier(
      evidence: recorded.evidence,
      fullRubricIds: recorded.fullRubricIds,
      gatingRubricIds: recorded.gatingRubricIds,
      classifierRubricIds: accepted.first.acceptedRubricIds,
    );
  }
  return CommitteeSelectionRun(
    policyVersion: recorded.policyVersion,
    stage: recorded.stage,
    workBeadId: recorded.workBeadId,
    round: recorded.round,
    nodePath: recorded.nodePath,
    selection: selection,
    evidence: recorded.evidence,
    fullRubricIds: recorded.fullRubricIds,
    gatingRubricIds: recorded.gatingRubricIds,
    attempts: recorded.attempts,
    missingFields: recorded.missingFields,
  );
}

/// Replays [recorded] through the PURE policy over its own recorded facts.
///
/// It reads no discovery artifact, no diff, no telemetry file and calls no
/// inference: every input is a column of the receipt itself. A reproduced
/// receipt that differs from the recorded one is the policy having drifted.
CommitteeShadowReceipt replayCommitteeShadowReceipt(
  CommitteeShadowReceipt recorded,
) => buildCommitteeShadowReceipt(
  run: replayCommitteeSelectionRun(recorded.run),
  route: recorded.route,
  lanes: [
    for (final lane in recorded.lanes)
      CommitteeLaneReceipt.derive(
        rubricId: lane.rubricId,
        nodePath: lane.nodePath,
        workBeadId: recorded.run.workBeadId,
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

/// The prompt ONE unknown-shape classifier call receives.
///
/// A bounded FACT sheet, never a diff and never a worktree: the shape counts,
/// the changed paths (clipped), and the closed menu it may answer from. The
/// answer must be one JSON object and nothing else.
String buildCommitteeClassifierPrompt({
  required CommitteeSelectionEvidence evidence,
  required List<String> allowedRubricIds,
  int maxChangedPaths = 40,
}) {
  final paths = evidence.changedPaths.take(maxChangedPaths).toList();
  final buffer = StringBuffer()
    ..writeln(
      'Pick the review lanes this change actually needs. Answer with ONE JSON '
      'object and nothing else: {"rubricIds": ["<id>", ...]}.',
    )
    ..writeln()
    ..writeln(
      'Legal ids (the ONLY ones accepted, naming any other id voids '
      'the whole answer): ${allowedRubricIds.join(', ')}.',
    )
    ..writeln()
    ..writeln('## Facts')
    ..writeln('- stage: ${evidence.stage.wire}')
    ..writeln('- intent records: ${evidence.intent.length}')
    ..writeln('- acceptance records: ${evidence.acceptance.length}')
    ..writeln('- resolved path anchors: ${evidence.paths.length}')
    ..writeln('- governing decisions: ${evidence.decisions.length}')
    ..writeln('- prior-art records: ${evidence.priorArt.length}')
    ..writeln('- changed paths: ${evidence.changedPaths.length}')
    ..writeln(
      '- pinned diff: ${evidence.pinnedDiffDigest.isEmpty ? 'none' : 'present'}',
    );
  if (evidence.missingEvidenceIds.isNotEmpty) {
    buffer.writeln(
      '- unresolved evidence: ${evidence.missingEvidenceIds.join(', ')}',
    );
  }
  if (paths.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Changed paths');
    for (final path in paths) {
      buffer.writeln('- $path');
    }
    if (paths.length < evidence.changedPaths.length) {
      buffer.writeln(
        '- … ${evidence.changedPaths.length - paths.length} more (clipped)',
      );
    }
  }
  return buffer.toString();
}

/// The SHADOW selector — one [ServiceCapability] per review circuit, mounted
/// BESIDE the full committee and depended on by nothing.
///
/// It always resolves to [Ok] and never carries a `grade`: it cannot [Escalate],
/// cannot [Rewind], cannot report [Failed], and never invokes another circuit
/// node. Every failure it meets — an unreadable artifact, an unresolvable agent
/// config, a throwing adapter, a refused write — becomes typed provenance in
/// the persisted run.
class CommitteeSelectionCapability extends ServiceCapability {
  /// Creates the selector over its three injected seams and a defaulted policy
  /// (the ambient `InheritedSeed<CommitteeSelectionPolicy>` wins when mounted).
  const CommitteeSelectionCapability({
    required this.classifier,
    required this.evidenceSource,
    required this.store,
    this.policy = kCommitteeSelectionPolicy,
  });

  /// The bounded one-shot classifier seam.
  final CommitteeClassifier classifier;

  /// The stage-evidence adapter.
  final CommitteeSelectionEvidenceSource evidenceSource;

  /// The durable shadow store.
  final CommitteeSelectionStore store;

  /// The policy used when the tree mounts none.
  final CommitteeSelectionPolicy policy;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read EVERY ambient value at entry (synchronously, while mounted); after
    // the first await only the captured values and the cancel token are used.
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final activePolicy =
        context.getInheritedSeedOfExactType<CommitteeSelectionPolicy>() ??
        policy;
    final typedEnvironment = resolveEnvironment<GatherAgentEnvironment>(
      context,
    );

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

    final attempts = <CommitteeClassifierAttempt>[];
    var selection = activePolicy.selectDeterministic(
      evidence: evidence,
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
    );

    // Only an UNKNOWN shape — zero rule matches — is eligible for inference.
    if (selection.matchedRuleIds.isEmpty) {
      final semantic = activePolicy.semanticRubricIds(
        fullRubricIds: fullRubricIds,
        gatingRubricIds: gatingRubricIds,
      );
      CommitteeClassifierAttempt? accepted;
      for (
        var attempt = 1;
        attempt <= kCommitteeClassifierAttempts;
        attempt++
      ) {
        final recorded = await _classifyOnce(
          attempt: attempt,
          args: args,
          evidence: evidence,
          semanticRubricIds: semantic,
          bead: bead,
          workspace: workspace,
          workspaceDir: workspaceDir,
          workBeadId: workBeadId,
          ambient: ambient,
          registry: registry,
          siteBinding: siteBinding,
          typedEnvironment: typedEnvironment,
        );
        attempts.add(recorded);
        if (recorded.kind == CommitteeClassifierResultKind.selected) {
          accepted = recorded;
          break;
        }
        if (args.cancel.isCancelled) {
          missingFields.add('classifier:cancelled');
          break;
        }
      }
      selection = accepted == null
          ? activePolicy.selectFullFallback(
              evidence: evidence,
              fullRubricIds: fullRubricIds,
              gatingRubricIds: gatingRubricIds,
            )
          : activePolicy.selectFromClassifier(
              evidence: evidence,
              fullRubricIds: fullRubricIds,
              gatingRubricIds: gatingRubricIds,
              classifierRubricIds: accepted.acceptedRubricIds,
            );
    }

    final run = CommitteeSelectionRun(
      policyVersion: activePolicy.policyVersion,
      stage: stage,
      workBeadId: workBeadId,
      round: round,
      nodePath: args.nodePath,
      selection: selection,
      evidence: evidence,
      fullRubricIds: fullRubricIds,
      gatingRubricIds: gatingRubricIds,
      attempts: attempts,
      missingFields: missingFields,
    );

    final payload = <String, String>{
      'shadow': 'selection',
      'source': selection.source.wire,
      'stage': stage.wire,
      'selected': selection.selectedRubricIds.join(','),
      'matchedRules': selection.matchedRuleIds.join(','),
      'classifierAttempts': '${attempts.length}',
    };
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

  Future<CommitteeClassifierAttempt> _classifyOnce({
    required int attempt,
    required StepArgs args,
    required CommitteeSelectionEvidence evidence,
    required List<String> semanticRubricIds,
    required Bead? bead,
    required Workspace? workspace,
    required String workspaceDir,
    required String workBeadId,
    required AgentConfig ambient,
    required EnvironmentRegistry registry,
    required SiteBinding siteBinding,
    required AgentEnvironment? typedEnvironment,
  }) async {
    CommitteeClassifierAttempt refused(String reason) =>
        CommitteeClassifierAttempt(
          attempt: attempt,
          kind: CommitteeClassifierResultKind.missing,
          usage: UsageSample(
            lane: kCommitteeSelectionStep,
            beadId: workBeadId.isEmpty ? null : workBeadId,
            fromFallback: false,
            costUsd: 0,
            durationMs: 0,
          ),
          reason: reason,
        );

    if (workspace == null ||
        workspaceDir.isEmpty ||
        !Directory(workspaceDir).existsSync()) {
      return refused('no-live-workspace');
    }
    if (semanticRubricIds.isEmpty) return refused('no-semantic-lanes');
    // NOTHING resolved at all is not an unknown SHAPE — it is an unknown ROUND.
    // A classifier handed zero facts can only guess, and guessing is the one
    // thing this lane must not pay for; the full committee is the honest
    // answer. This is also what keeps the offline suite process-free when a
    // fixture mounts a real directory with no artifacts in it.
    if (evidence.isEmpty) return refused('no-evidence');

    final AgentConfig config;
    try {
      config = resolveAgentConfig(
        // The CHEAP tier: a triage question, never a grading one. The ladder
        // ALWAYS stamps an explicit model into `params['model']`, so this spawn
        // is pinned by construction — there is no unpinned classifier call.
        tier: AgentTier.cheap,
        ambient: ambient,
        beadMetadata: bead?.metadata ?? const {},
        stepParams: args.params,
        registry: registry,
        typedEnvironment: typedEnvironment,
      );
    } on Object catch (error) {
      return refused('agent-config:$error');
    }
    final AgentEnvironment environment;
    try {
      environment = registry.resolve(config.harness);
    } on Object catch (error) {
      return refused('environment:$error');
    }

    final model = config.params['model'];
    final telemetryNode = '${args.nodePath}/classifier-$attempt';
    final RuntimeConfig spawn;
    try {
      spawn = spawnFor(
        environment: environment,
        model: model,
        endpoint: siteBinding.endpointFor(
          name: config.harness,
          environment: environment,
        ),
        brief: AgentBrief(
          task: buildCommitteeClassifierPrompt(
            evidence: evidence,
            allowedRubricIds: semanticRubricIds,
          ),
        ),
        workspace: workspace,
        usageOut: usageReportPath(telemetryNode),
      );
    } on Object catch (error) {
      return refused('spawn:$error');
    }

    ({bool ok, String output}) answer;
    try {
      answer = await classifier(spawn);
    } on Object catch (error) {
      answer = (ok: false, output: '');
      return _attemptFor(
        attempt: attempt,
        result: const CommitteeClassifierResult.missing(),
        answer: answer,
        workspaceDir: workspaceDir,
        telemetryNode: telemetryNode,
        workBeadId: workBeadId,
        model: model,
        reason: 'classifier:$error',
      );
    }

    final text = _envelopeOrStdout(workspaceDir, telemetryNode, answer.output);
    final result = parseCommitteeClassifierResult(
      answer.ok ? text : null,
      activeSemanticRubricIds: semanticRubricIds,
    );
    return _attemptFor(
      attempt: attempt,
      result: result,
      answer: answer,
      workspaceDir: workspaceDir,
      telemetryNode: telemetryNode,
      workBeadId: workBeadId,
      model: model,
      reason: answer.ok ? '' : 'classifier:not-ok',
    );
  }

  CommitteeClassifierAttempt _attemptFor({
    required int attempt,
    required CommitteeClassifierResult result,
    required ({bool ok, String output}) answer,
    required String workspaceDir,
    required String telemetryNode,
    required String workBeadId,
    required String? model,
    required String reason,
  }) {
    final report = _readUsageReport(workspaceDir, telemetryNode);
    final text = answer.output.trim();
    return CommitteeClassifierAttempt(
      attempt: attempt,
      kind: result.kind,
      usage: UsageSample(
        lane: kCommitteeSelectionStep,
        beadId: workBeadId.isEmpty ? null : workBeadId,
        fromFallback: false,
        costUsd: report?.costUsd?.toDouble(),
        durationMs: report?.harnessDurationMs,
      ),
      acceptedRubricIds: result.rubricIds,
      rejectedRubricIds: result.rejectedRubricIds,
      outputDigest: text.isEmpty
          ? ''
          : sha256.convert(utf8.encode(text)).toString(),
      reason: reason,
      launched: true,
      model: report?.model ?? model,
      tokensIn: report?.tokensIn,
      tokensOut: report?.tokensOut,
      costUsd: report?.costUsd,
      premiumRequests: report?.premiumRequests,
      numTurns: report?.numTurns,
      harnessDurationMs: report?.harnessDurationMs,
    );
  }
}

String? _envelopeOrStdout(
  String workspaceDir,
  String nodePath,
  String stdoutText,
) {
  final envelope = readEnvelopeResultText(workspaceDir, nodePath);
  if (envelope != null && envelope.trim().isNotEmpty) return envelope;
  return stdoutText.trim().isEmpty ? null : stdoutText;
}

/// The harness usage envelope for [nodePath], parsed through the ONE FT-2
/// codec. Fail-safe: an absent, unreadable or malformed envelope yields null.
UsageReport? _readUsageReport(String workspaceDir, String nodePath) {
  try {
    final file = File(p.join(workspaceDir, usageReportPath(nodePath)));
    if (!file.existsSync()) return null;
    return UsageReport.tryParse(file.readAsStringSync());
  } on Object {
    return null;
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
/// It delegates once, writes a receipt beside the answer, and returns the
/// delegate's exact [RouteVerdict] OBJECT. It never converts, decorates, waits
/// for or substitutes the verdict, and every shadow read/codec/write exception
/// is swallowed — a telemetry failure must not change a routing decision.
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
    if (input != null) {
      try {
        store.writeReceipt(
          input.workspaceDir,
          input.receiptFor(verdict, store: store),
        );
      } on Object {
        // Shadow telemetry is non-authoritative: a failed receipt changes
        // nothing about the verdict below.
      }
    }
    return verdict;
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
    // classifier work of its own.
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

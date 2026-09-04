/// The DISCOVERY circuit — the nested read-only gather + the CITE-THE-OFFENCE
/// violation gate at the head of `kSpecReviewCircuit`, between the readiness
/// ladder and `specify`.
///
/// **The mandate.** ADR-0000 A17's ratified Status footer names this gap: "A17
/// checks BEAD-readiness — DISTINCT from DISCOVERY-readiness (is the ARCHITECT
/// handed enough context + the grading rubrics to specify well), a new gap being
/// shaped for its own bead."
///
/// **The gap.** The architect ALREADY discovers (it stands in a bare worktree).
/// What it lacks is GUIDANCE: it re-derives what we already know it needs, it
/// never sees the RUBRICS its spec is graded by, and a bead that contradicts a
/// ratified decision only finds out at the spec committee — downstream of the
/// most expensive fan-out in the circuit. This circuit hands the architect the
/// context, and REFUSES to spec a bead that offends a decision already made.
///
/// **Two halves, one circuit:**
///  1. [AnchorsCapability] — the DETERMINISTIC gather (ZERO agents): the spec
///     committee's own grading rubrics, the bead's code anchors resolved to files
///     plus the pattern that surrounds them, and `space search` prior art through
///     the read-only [StationSearchService] seam (ADR-0001: the asset CALLS the
///     deterministic Command's service — it never re-derives search by
///     inference).
///  2. [DiscoveryLensCapability] ×3 — parallel READ-ONLY explorers that declare
///     [AgentTier.cheap]. The GATHER doctrine ADR-0000 A20's REFINED FORWARD
///     footer ratified in outline is the contract this
///     circuit honors: "read-only discovery: it reads the tree, cites what it
///     finds, and DECIDES NOTHING… It is NOT the home for a cheap JUDGEMENT lane
///     (a lane that emits a verdict letter is grading, not gathering)." So a lens
///     emits NO letter — it emits a [LensReport] (context notes + cited
///     violations). The DECISION is [DiscoveryRouteCapability]'s, and it is a
///     pure, deterministic matrix. (ADR-0000 A20's ratified REFINED FORWARD
///     footer is the register side of the same call: "`gather` (the discovery
///     explorers) joins as a third role at the cheap tier.")
///
/// **The CITE-THE-OFFENCE gate.** The route holds a bead ONLY on a violation that
/// NAMES its standard — a RATIFIED ADR/amendment, or an applicable SKILL's
/// instructions ([ViolationKind]). These rules keep it honest, and each is a
/// clause of [gatesTheBead]:
///  - **no citation, no hold.** A finding with an empty `standard` is a VIBE. It
///    can never gate; it rides the dossier as a FLAG.
///  - **the departure clause.** A finding the bead ACKNOWLEDGES ("this departs
///    from X because Y") passes — a considered departure is not an offender, and
///    it is judged downstream by `decision-alignment`. Only an UNWITTING contradiction
///    gates.
///  - **intent, not presence.** A finding the bead's own plan/acceptance REMOVES
///    (the bead IS the fix) passes — discovery runs pre-specify, so the offending
///    text is necessarily still present.
///  - **a recorded entry holds.** A [ViolationKind.decision] gates only on a
///    RECORDED decision entry (it binds on write); anything that is not one
///    rides as a FLAG, never a hold (the 2026-07-14 register foot).
///  - **a pattern needs a precedent.** A [ViolationKind.pattern] deviation gates
///    only when the lens NAMES the precedent it deviates from; otherwise it is a
///    FLAG in the ask, never a hold.
///
/// **The fail directions.** A lens that produces no parseable report is a broken
/// LANE, not a verdict: the route STAMPS an invalidating `grade: 'F'` and, via
/// the `validates: `[kAnchorsStep] edge it declares, the engine re-runs the whole
/// gather sub-DAG VIRGIN — ONCE ([kMaxRegatherRounds]) — and, at the cap, ADVANCES
/// with the miss recorded LOUDLY in the dossier. It never gates on absence (a gate
/// with no cited offence is exactly what this circuit forbids) and it never wedges
/// the governance track (ADR-0000 A17(3): a false HOLD is strictly worse than a
/// wasted specify round).
///
/// **Layering note (do not "fix" into a cycle).** This library imports NOTHING
/// from `specify.dart`: `specify.dart` imports THIS one (for the dossier its
/// brief renders and the circuit id its head names), and the rubric ids the
/// gather pulls arrive as a constructor VALUE ([AnchorsCapability.rubricIds] —
/// config = values, ADR-0008 D-H), wired by `buildCodeRegistry`. That one-way
/// edge is deliberate, and it is the same posture `circuit_migration.dart` and
/// `respec.dart` already hold.
///
/// Naming, once: the `discovery` CIRCUIT is not the `discover` SKILL
/// (`extension/station_overlay/skills/discover/`). The skill is the human front
/// door; this circuit is the in-pipeline gather. They never touch.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:crypto/crypto.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/model_tier.dart';
import '../agent/seat_environments.dart';
import '../agent/site_binding.dart';
import '../agent/typed_environment.dart';
import '../agent/usage_report.dart';
import '../search/station_search.dart';
import 'committee.dart';
import 'decision_register.dart';
import 'landing.dart' show ShellRunner;
import 'respec.dart';
import 'route_failure.dart';

/// The discovery circuit's registry id — and the [SubCircuitStep] id that
/// inflates it inside `spec_review`.
const String kDiscoveryCircuitId = 'discovery';

/// The deterministic gather step (ZERO agents) — the circuit's only dep-free
/// step, and therefore the cursor key the migration guard classifies on.
const String kAnchorsStep = 'anchors';

/// The decision point (ZERO agents) — the circuit's terminal.
const String kDiscoveryRouteStep = 'discovery-route';

/// The CODE lens — what this bead will touch, and the conventions that govern it.
const String kCodeLens = 'explore-code';

/// The DECISION lens — the ADRs and skills that bind; the gate's main evidence.
const String kDecisionLens = 'explore-decision';

/// The PRIOR-ART lens — what has already been done, decided, or attempted here.
const String kPriorArtLens = 'explore-prior-art';

/// Every lens, in declaration order (step ids AND lens ids — one word).
const List<String> kDiscoveryLenses = [kCodeLens, kDecisionLens, kPriorArtLens];

/// How many times the route re-gathers a lens whose report never arrived. ONE: a
/// cheap model slips, a broken lane does not fix itself twice. Strictly below the
/// engine's `kMaxReworkRounds` belt, so the asset's own policy fires first.
const int kMaxRegatherRounds = 1;

/// The bound on the deterministic prior-art pull — each query is one read-only
/// pass over every attached store.
const int kMaxPriorArtQueries = 3;

/// The bound on the anchors pulled out of one bead.
const int kMaxAnchors = 12;

/// The bound on a resolved anchor's SURROUNDING PATTERN (its directory's other
/// files) — enough to show the architect what the neighborhood looks like.
const int kMaxNeighbors = 8;

/// The bound on ONE piece of bounded evidence's rendered SNIPPET. The full text
/// is always hashed; only the snippet is clipped, and a clip is RECORDED
/// ([EvidenceState.truncated]) so bounded evidence can never masquerade as
/// complete evidence.
const int kMaxDiscoverySnippetChars = 4096;

/// The bound on the decision entries kept for ONE roster-qualified surface.
const int kMaxDecisionEntriesPerSurface = 12;

/// The bound on the prior-art hits kept for ONE query.
const int kMaxPriorArtHitsPerQuery = 12;

/// The bound on the git-history commits kept for one round.
const int kMaxHistoryCommits = 12;

/// How COMPLETE one piece of gathered evidence is. Sealed by the enum and
/// consumed with an exhaustive `switch` (house style), so a new state cannot
/// skip a projection's sufficiency check.
///
/// The distinction is the whole point of the canonical profile: an empty
/// successful lookup ([complete]) is a REAL result, where a clipped one
/// ([truncated]), an unwired source ([unavailable]) and a crashed one
/// ([failed]) are known NON-answers. A lens is handed the state, never a bare
/// snippet, so it can never read "nobody looked" as "nothing is there".
///
/// Three of those states are the lens's CONTEXT; only two are a deterministic
/// GAP (`_isDeterministicEvidenceGap`). [truncated] and [failed] override the
/// lens's report with an [InsufficientEvidenceReport] and spend the one-round
/// regather budget, because the gather promised a record and then broke it.
/// [unavailable] does NOT: the optional source was simply never composed, so
/// the lens narrates the limitation and its report stands, exactly as it did
/// before the canonical profile existed.
enum EvidenceState {
  /// The lookup ran and its whole result is carried (an empty result included).
  complete,

  /// The lookup ran but its result was CLIPPED by one of this library's bounds.
  truncated,

  /// No source was wired, so the lookup never ran at all.
  unavailable,

  /// The lookup ran and CRASHED — the detail rides the record's `error`.
  failed;

  /// The state [raw] names — null when it names none (fail-closed: an unknown
  /// state is refused by the decoder rather than silently downgraded).
  static EvidenceState? fromWire(Object? raw) => switch (raw) {
    'complete' => EvidenceState.complete,
    'truncated' => EvidenceState.truncated,
    'unavailable' => EvidenceState.unavailable,
    'failed' => EvidenceState.failed,
    _ => null,
  };
}

/// ONE piece of gathered evidence, BOUNDED: a stable identity, where it came
/// from, the clipped snippet, the digest of the COMPLETE text, and how complete
/// the record is.
///
/// The digest is over the whole text, so a truncated snippet still identifies
/// the artifact it was cut from; [id] carries that digest, which is what makes
/// an evidence id stable across rounds for unchanged evidence and different the
/// moment the underlying text moves.
class BoundedEvidence {
  /// Creates a record. Prefer [boundDiscoveryEvidence], which derives the
  /// digest, the id and the truncation state from the complete text.
  const BoundedEvidence({
    required this.id,
    required this.source,
    required this.snippet,
    required this.digest,
    required this.state,
    this.error = '',
  });

  /// The canonical identity — `<kind>:<subject>@sha256:<digest>`.
  final String id;

  /// WHERE the evidence came from (a file path, a bead field, a command).
  final String source;

  /// The evidence text, clipped to [kMaxDiscoverySnippetChars].
  final String snippet;

  /// The SHA-256 of the COMPLETE text (never of the clipped snippet).
  final String digest;

  /// How complete this record is.
  final EvidenceState state;

  /// The failure detail — REQUIRED (non-empty) for [EvidenceState.failed].
  final String error;

  /// The wire shape (hand-rolled — this pack carries no `json_serializable`).
  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'snippet': snippet,
    'digest': digest,
    'state': state.name,
    'error': error,
  };

  /// Decodes one record STRICTLY: a non-map, an empty id/digest, an unknown
  /// state, or a [EvidenceState.failed] record with no error yields null. The
  /// caller turns that into a refused artifact, never a silently emptied one.
  static BoundedEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['id'] as String?)?.trim() ?? '';
    final digest = (json['digest'] as String?)?.trim() ?? '';
    final state = EvidenceState.fromWire(json['state']);
    if (id.isEmpty || digest.isEmpty || state == null) return null;
    final error = (json['error'] as String?) ?? '';
    if (state == EvidenceState.failed && error.trim().isEmpty) return null;
    return BoundedEvidence(
      id: id,
      source: (json['source'] as String?) ?? '',
      snippet: (json['snippet'] as String?) ?? '',
      digest: digest,
      state: state,
      error: error,
    );
  }
}

/// Bounds [fullText] into one [BoundedEvidence] record: hashes the COMPLETE
/// text, clips the snippet at [kMaxDiscoverySnippetChars], and derives the
/// state ([EvidenceState.truncated] on a clip) unless [state] forces one.
BoundedEvidence boundDiscoveryEvidence({
  required String kind,
  required String subject,
  required String source,
  required String fullText,
  EvidenceState? state,
  String error = '',
}) {
  final digest = sha256.convert(utf8.encode(fullText)).toString();
  final wasTruncated = fullText.length > kMaxDiscoverySnippetChars;
  final resolvedState =
      state ??
      (wasTruncated ? EvidenceState.truncated : EvidenceState.complete);
  return BoundedEvidence(
    id: '$kind:${Uri.encodeComponent(subject)}@sha256:$digest',
    source: source,
    snippet: wasTruncated
        ? fullText.substring(0, kMaxDiscoverySnippetChars)
        : fullText,
    digest: digest,
    state: resolvedState,
    error: error.length > kMaxDiscoverySnippetChars
        ? error.substring(0, kMaxDiscoverySnippetChars)
        : error,
  );
}

/// ONE bead field, bounded — the work bead's own prose, resolved ONCE by the
/// deterministic gather so no lens re-reads the bead through a tool.
class BeadFieldEvidence {
  /// Creates the record.
  const BeadFieldEvidence({
    required this.beadId,
    required this.field,
    required this.evidence,
  });

  /// The bead the field belongs to.
  final String beadId;

  /// Which field.
  final BeadCitationField field;

  /// The bounded field text.
  final BoundedEvidence evidence;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'beadId': beadId,
    'field': field.wire,
    'evidence': evidence.toJson(),
  };

  /// Decodes one record STRICTLY; anything incomplete yields null.
  static BeadFieldEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final beadId = (json['beadId'] as String?)?.trim() ?? '';
    final field = BeadCitationField.fromWire(json['field']);
    final evidence = BoundedEvidence.fromJson(json['evidence']);
    if (beadId.isEmpty || field == null || evidence == null) return null;
    return BeadFieldEvidence(beadId: beadId, field: field, evidence: evidence);
  }
}

/// ONE grading rubric, bounded — its identity plus the digest of its COMPLETE
/// prose. The prose itself still rides `DiscoveryAnchors.rubrics` verbatim (the
/// architect is graded by it), so this record is the IDENTITY, not a second copy.
class RubricEvidence {
  /// Creates the record.
  const RubricEvidence({required this.rubricId, required this.evidence});

  /// The rubric id.
  final String rubricId;

  /// The bounded rubric prose.
  final BoundedEvidence evidence;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'rubricId': rubricId,
    'evidence': evidence.toJson(),
  };

  /// Decodes one record STRICTLY; anything incomplete yields null.
  static RubricEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final rubricId = (json['rubricId'] as String?)?.trim() ?? '';
    final evidence = BoundedEvidence.fromJson(json['evidence']);
    if (rubricId.isEmpty || evidence == null) return null;
    return RubricEvidence(rubricId: rubricId, evidence: evidence);
  }
}

/// ONE prior-art QUERY's coverage — the query, how the search went, and its
/// bounded hits.
///
/// Query-level, not hit-level, on purpose: flattening hits loses the difference
/// between "searched, no hits" and "a roster seat was absent or the read
/// crashed", which is exactly the blindness the prior-art seam exists to remove.
class PriorArtQueryEvidence {
  /// Creates the record.
  const PriorArtQueryEvidence({
    required this.id,
    required this.query,
    required this.state,
    this.truncated = false,
    this.error = '',
    this.hits = const [],
  });

  /// The canonical identity of this query's coverage.
  final String id;

  /// The query as searched.
  final String query;

  /// How the search went.
  final EvidenceState state;

  /// Whether the hit list was clipped at [kMaxPriorArtHitsPerQuery].
  final bool truncated;

  /// The failure detail — REQUIRED (non-empty) for [EvidenceState.failed].
  final String error;

  /// The bounded hits, in search order.
  final List<PriorArt> hits;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'query': query,
    'state': state.name,
    'truncated': truncated,
    'error': error,
    'hits': [for (final hit in hits) hit.toJson()],
  };

  /// Decodes one record STRICTLY: an unknown state, an empty id, a failed
  /// record with no error, or ANY malformed hit yields null (a malformed entry
  /// is never dropped — the whole artifact is refused).
  static PriorArtQueryEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['id'] as String?)?.trim() ?? '';
    final state = EvidenceState.fromWire(json['state']);
    if (id.isEmpty || state == null) return null;
    final error = (json['error'] as String?) ?? '';
    if (state == EvidenceState.failed && error.trim().isEmpty) return null;
    final rawHits = json['hits'];
    if (rawHits is! List) return null;
    final hits = <PriorArt>[];
    for (final entry in rawHits) {
      final hit = PriorArt.fromJson(entry);
      if (hit == null) return null;
      hits.add(hit);
    }
    return PriorArtQueryEvidence(
      id: id,
      query: (json['query'] as String?) ?? '',
      state: state,
      truncated: json['truncated'] == true,
      error: error,
      hits: hits,
    );
  }
}

/// ONE recorded decision entry, resolved from the roster-mode index and read
/// off disk — the canonical `<repo>#<slug>` identity plus its bounded body.
class DecisionEntryEvidence {
  /// Creates the record.
  const DecisionEntryEvidence({
    required this.identity,
    required this.originRegister,
    required this.originPath,
    required this.slug,
    required this.status,
    required this.surfaces,
    required this.entryPath,
    required this.body,
  });

  /// The canonical citation identity — `<originRegister>#<slug>`.
  final String identity;

  /// The register the entry came from (a SIBLING substation binds as a local
  /// one does).
  final String originRegister;

  /// The register directory the index reported.
  final String originPath;

  /// The entry's slug.
  final String slug;

  /// The entry's `status` front-matter value.
  final String status;

  /// The surfaces the entry declares.
  final List<String> surfaces;

  /// The resolved entry file.
  final String entryPath;

  /// The bounded entry body.
  final BoundedEvidence body;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'identity': identity,
    'originRegister': originRegister,
    'originPath': originPath,
    'slug': slug,
    'status': status,
    'surfaces': surfaces,
    'entryPath': entryPath,
    'body': body.toJson(),
  };

  /// Decodes one record STRICTLY; anything incomplete yields null.
  static DecisionEntryEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final identity = (json['identity'] as String?)?.trim() ?? '';
    final slug = (json['slug'] as String?)?.trim() ?? '';
    final body = BoundedEvidence.fromJson(json['body']);
    final rawSurfaces = json['surfaces'];
    if (identity.isEmpty || slug.isEmpty || body == null) return null;
    if (rawSurfaces is! List) return null;
    return DecisionEntryEvidence(
      identity: identity,
      originRegister: (json['originRegister'] as String?) ?? '',
      originPath: (json['originPath'] as String?) ?? '',
      slug: slug,
      status: (json['status'] as String?) ?? '',
      surfaces: [
        for (final surface in rawSurfaces)
          if (surface is String) surface,
      ],
      entryPath: (json['entryPath'] as String?) ?? '',
      body: body,
    );
  }
}

/// ONE roster-qualified surface's decision lookup — the exact command that ran,
/// how it went, and the entries it returned.
class DecisionSurfaceEvidence {
  /// Creates the record.
  const DecisionSurfaceEvidence({
    required this.id,
    required this.surface,
    required this.command,
    required this.state,
    this.truncated = false,
    this.error = '',
    this.decisions = const [],
  });

  /// The canonical identity of this surface's lookup.
  final String id;

  /// The roster-qualified surface queried (`<repo>/<path>`).
  final String surface;

  /// The exact command that ran (provenance — the lens never re-runs it).
  final String command;

  /// How the lookup went. An empty `decisions` list with
  /// [EvidenceState.complete] is a REAL empty union.
  final EvidenceState state;

  /// Whether the entry list was clipped at [kMaxDecisionEntriesPerSurface].
  final bool truncated;

  /// The failure detail — REQUIRED (non-empty) for [EvidenceState.failed].
  final String error;

  /// The entries, in index order.
  final List<DecisionEntryEvidence> decisions;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'surface': surface,
    'command': command,
    'state': state.name,
    'truncated': truncated,
    'error': error,
    'decisions': [for (final entry in decisions) entry.toJson()],
  };

  /// Decodes one record STRICTLY; an unknown state, an empty id, a failed
  /// record with no error, or ANY malformed entry yields null.
  static DecisionSurfaceEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['id'] as String?)?.trim() ?? '';
    final state = EvidenceState.fromWire(json['state']);
    if (id.isEmpty || state == null) return null;
    final error = (json['error'] as String?) ?? '';
    if (state == EvidenceState.failed && error.trim().isEmpty) return null;
    final rawEntries = json['decisions'];
    if (rawEntries is! List) return null;
    final decisions = <DecisionEntryEvidence>[];
    for (final raw in rawEntries) {
      final entry = DecisionEntryEvidence.fromJson(raw);
      if (entry == null) return null;
      decisions.add(entry);
    }
    return DecisionSurfaceEvidence(
      id: id,
      surface: (json['surface'] as String?) ?? '',
      command: (json['command'] as String?) ?? '',
      state: state,
      truncated: json['truncated'] == true,
      error: error,
      decisions: decisions,
    );
  }
}

/// ONE commit touching the bead's resolved surfaces.
class HistoryCommitEvidence {
  /// Creates the record.
  const HistoryCommitEvidence({
    required this.id,
    required this.sha,
    required this.authoredAt,
    required this.subject,
  });

  /// The canonical identity of this commit record.
  final String id;

  /// The full commit SHA.
  final String sha;

  /// The author date, ISO-8601.
  final String authoredAt;

  /// The commit subject line.
  final String subject;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'sha': sha,
    'authoredAt': authoredAt,
    'subject': subject,
  };

  /// Decodes one record STRICTLY; anything incomplete yields null.
  static HistoryCommitEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['id'] as String?)?.trim() ?? '';
    final sha = (json['sha'] as String?)?.trim() ?? '';
    if (id.isEmpty || sha.isEmpty) return null;
    return HistoryCommitEvidence(
      id: id,
      sha: sha,
      authoredAt: (json['authoredAt'] as String?) ?? '',
      subject: (json['subject'] as String?) ?? '',
    );
  }
}

/// The round's git-history evidence over the bead's RESOLVED surfaces — ONE
/// batched read, recorded with its exact command.
class HistoryEvidence {
  /// Creates the record.
  const HistoryEvidence({
    required this.id,
    required this.paths,
    required this.command,
    required this.state,
    this.truncated = false,
    this.error = '',
    this.commits = const [],
  });

  /// The canonical identity of this history read.
  final String id;

  /// The paths the read covered.
  final List<String> paths;

  /// The exact argv that ran (provenance — the lens never re-runs it).
  final String command;

  /// How the read went. An empty `commits` list with [EvidenceState.complete]
  /// is a REAL empty history.
  final EvidenceState state;

  /// Whether the commit list was clipped at [kMaxHistoryCommits].
  final bool truncated;

  /// The failure detail — REQUIRED (non-empty) for [EvidenceState.failed].
  final String error;

  /// The commits, newest first.
  final List<HistoryCommitEvidence> commits;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'paths': paths,
    'command': command,
    'state': state.name,
    'truncated': truncated,
    'error': error,
    'commits': [for (final commit in commits) commit.toJson()],
  };

  /// Decodes the record STRICTLY; an unknown state, an empty id, a failed
  /// record with no error, or ANY malformed commit yields null.
  static HistoryEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['id'] as String?)?.trim() ?? '';
    final state = EvidenceState.fromWire(json['state']);
    if (id.isEmpty || state == null) return null;
    final error = (json['error'] as String?) ?? '';
    if (state == EvidenceState.failed && error.trim().isEmpty) return null;
    final rawPaths = json['paths'];
    final rawCommits = json['commits'];
    if (rawPaths is! List || rawCommits is! List) return null;
    final commits = <HistoryCommitEvidence>[];
    for (final raw in rawCommits) {
      final commit = HistoryCommitEvidence.fromJson(raw);
      if (commit == null) return null;
      commits.add(commit);
    }
    return HistoryEvidence(
      id: id,
      paths: [
        for (final path in rawPaths)
          if (path is String) path,
      ],
      command: (json['command'] as String?) ?? '',
      state: state,
      truncated: json['truncated'] == true,
      error: error,
      commits: commits,
    );
  }
}

/// The discovery round's artifact dir under [workspaceDir]. A SIBLING of
/// `.grid/critique/` (which `ClearCritiqueCapability` wipes every committee
/// round) — the dossier must outlive that wipe: `specify` reads it after it.
String discoveryDirPath(String workspaceDir) =>
    p.join(workspaceDir, '.grid', 'discovery');

/// One lens's report path — the canonical, ABSOLUTE path its prompt names
/// (cwd-invariant, gate-integrity #4).
String lensReportPath(String workspaceDir, String lens) =>
    p.join(discoveryDirPath(workspaceDir), '$lens.json');

/// The deterministic gather's output — read back by every lens prompt and by the
/// route.
String anchorsPath(String workspaceDir) =>
    p.join(discoveryDirPath(workspaceDir), 'anchors.json');

/// The CURATED dossier the route writes on ADVANCE and `buildSpecifyBrief`
/// renders — the whole point of the gather (derived identically by the writer and
/// the reader, the `respecLedgerPath` precedent).
String discoveryDossierPath(String workspaceDir) =>
    p.join(discoveryDirPath(workspaceDir), 'dossier.json');

/// The REGATHER round ledger under [workspaceDir] — the durable round counter
/// [DiscoveryRouteCapability] reads back to apply [kMaxRegatherRounds].
/// Deliberately a SIBLING of `.grid/discovery/` (which [AnchorsCapability] WIPES
/// virgin at the head of every round), so it OUTLIVES that wipe: the full
/// regather wave re-runs `anchors`, which would clobber any counter kept inside
/// the gather dir and restart the bound at 0 forever. The `respecLedgerPath`
/// precedent — derived identically by the writer and the reader.
String discoveryRegatherLedgerPath(String workspaceDir) =>
    p.join(workspaceDir, '.grid', 'discovery-regather.json');

/// What KIND of standard a violation cites. Sealed by the enum — consumed with an
/// exhaustive `switch` (house style), so a new kind cannot skip the gate matrix.
enum ViolationKind {
  /// A RECORDED decision entry — a `docs/decisions/` slug entry, or a legacy
  /// ADR-0000 `A<n>` amendment (converted with `status: accepted`). It binds on
  /// write. Anything that is not a recorded entry is ADVISORY: it can never
  /// HOLD (2026-07-14 register foot); it rides as a flag for `decision-alignment`.
  decision,

  /// An applicable SKILL's instructions (skills TEACH how; ADRs RATIFY the
  /// specific — generic guidance belongs in a skill, not a proliferating ADR).
  skill,

  /// An established code PATTERN. Gates ONLY with a named precedent.
  pattern;

  /// The wire spelling.
  String get wire => name;

  /// The kind [wire] names — null when it names none (fail-closed: an unknown
  /// kind is not a gateable citation).
  static ViolationKind? fromWire(Object? wire) {
    for (final kind in ViolationKind.values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// One CITED finding — the only thing that can hold a bead.
class DiscoveryFinding {
  /// Creates a finding.
  const DiscoveryFinding({
    required this.kind,
    required this.standard,
    required this.quote,
    required this.contradiction,
    this.contradicts = false,
    this.acknowledged = false,
    this.ratified = false,
    this.removesOffence = false,
    this.precedent = '',
  });

  /// What kind of standard is cited.
  final ViolationKind kind;

  /// The CITATION — a legacy clause such as
  /// `docs/adr/ADR-0000-ai-decision-register.md A17(4)`, or a decisions-register
  /// slug such as `the_grid#admission-authority-boundary`. EMPTY means a vibe
  /// and can never gate.
  final String standard;

  /// The cited clause, quoted.
  final String quote;

  /// What the bead does that contradicts it.
  final String contradiction;

  /// Whether the finding POSITIVELY asserts a real, unwitting contradiction. A
  /// lens may name a standard and quote it yet conclude there is NO conflict —
  /// writing "None identified" / "aligned with …" prose into [contradiction]
  /// (non-empty, so it survives [fromJson]). Such a non-finding must NEVER hold
  /// a bead (pow-hf2: the flaky false-hold that taxed pow-ebf.3 / pow-8b3 /
  /// pow-hf2 itself). [gatesTheBead] therefore REQUIRES this to be `true`;
  /// absent/`false` fails OPEN (ADR-0000 A17(3): a false HOLD is strictly worse
  /// than a wasted round, and the spec committee's `decision-alignment` lane
  /// backstops a genuine contradiction downstream).
  final bool contradicts;

  /// Whether the BEAD ITSELF declares the departure ("this departs from X because
  /// Y"). A declared departure PASSES.
  final bool acknowledged;

  /// Whether the cited standard is a RECORDED decision entry — a
  /// `docs/decisions/` slug entry, or a legacy ADR-0000 `A<n>` amendment
  /// (converted with `status: accepted`). For [ViolationKind.decision] ONLY:
  /// anything that is not a recorded entry (`false`) is ADVISORY and can never
  /// HOLD (the 2026-07-14 register-foot ratification). Default `false` —
  /// fail-open on holds (A17(3): a false HOLD is strictly worse than a wasted
  /// round).
  final bool ratified;

  /// Whether the bead's OWN plan/acceptance REMOVES this cited offence — the bead
  /// IS the fix. `true` ⇒ it PASSES (INTENT, NOT PRESENCE): discovery runs
  /// pre-specify, so a fix-the-violation bead necessarily still HAS the offending
  /// text present. Default `false`.
  final bool removesOffence;

  /// For [ViolationKind.pattern] ONLY: the precedent deviated from
  /// (`lib/src/code/committee.dart:CriticCapability`). Empty ⇒ a FLAG, never a
  /// hold.
  final String precedent;

  /// The wire shape (hand-rolled — this pack carries no `json_serializable`).
  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'standard': standard,
    'quote': quote,
    'contradiction': contradiction,
    'contradicts': contradicts,
    'acknowledged': acknowledged,
    'ratified': ratified,
    'removesOffence': removesOffence,
    'precedent': precedent,
  };

  /// Decodes one finding; a non-map, kind-less or contradiction-less entry yields
  /// null (best-effort — a garbled entry degrades to "not reported", never a
  /// throw and never a gate).
  static DiscoveryFinding? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ViolationKind.fromWire(json['kind']);
    final contradiction = (json['contradiction'] as String?)?.trim() ?? '';
    if (kind == null || contradiction.isEmpty) return null;
    return DiscoveryFinding(
      kind: kind,
      standard: (json['standard'] as String?)?.trim() ?? '',
      quote: (json['quote'] as String?)?.trim() ?? '',
      contradiction: contradiction,
      contradicts: json['contradicts'] == true,
      acknowledged: json['acknowledged'] == true,
      ratified: json['ratified'] == true,
      removesOffence: json['removesOffence'] == true,
      precedent: (json['precedent'] as String?)?.trim() ?? '',
    );
  }

  /// The one-line rendering a hold or a dossier prints.
  String get line =>
      '`$standard` — $contradiction'
      '${quote.isEmpty ? '' : ' (the clause: "$quote")'}'
      '${precedent.isEmpty ? '' : ' (precedent: `$precedent`)'}';
}

/// A field on a bead that discovery may cite verbatim.
enum BeadCitationField {
  title,
  description,
  design,
  acceptanceCriteria,
  notes;

  /// The stable JSON spelling used by beads/search.
  String get wire => switch (this) {
    BeadCitationField.title => 'title',
    BeadCitationField.description => 'description',
    BeadCitationField.design => 'design',
    BeadCitationField.acceptanceCriteria => 'acceptance_criteria',
    BeadCitationField.notes => 'notes',
  };

  /// Parses a supported bead-field spelling.
  static BeadCitationField? fromWire(Object? wire) => switch (wire) {
    'title' => BeadCitationField.title,
    'description' => BeadCitationField.description,
    'design' => BeadCitationField.design,
    'acceptance_criteria' => BeadCitationField.acceptanceCriteria,
    'notes' => BeadCitationField.notes,
    _ => null,
  };
}

/// A machine-checkable quotation from one bead field.
class BeadFieldCitation {
  /// Creates a citation of [excerpt] from [field] on [beadId].
  const BeadFieldCitation({
    required this.beadId,
    required this.field,
    required this.excerpt,
  });

  /// The bead whose field was quoted.
  final String beadId;

  /// The field that was quoted.
  final BeadCitationField field;

  /// The verbatim quotation.
  final String excerpt;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'beadId': beadId,
    'field': field.wire,
    'excerpt': excerpt,
  };

  /// Decodes a complete citation; incomplete or unsupported citations are null.
  static BeadFieldCitation? fromJson(Object? json) {
    if (json is! Map) return null;
    final beadId = (json['beadId'] as String?)?.trim() ?? '';
    final field = BeadCitationField.fromWire(json['field']);
    final excerpt = (json['excerpt'] as String?)?.trim() ?? '';
    if (beadId.isEmpty || field == null || excerpt.isEmpty) return null;
    return BeadFieldCitation(beadId: beadId, field: field, excerpt: excerpt);
  }
}

/// One context NOTE — what an explorer FOUND (never a judgement).
class ContextNote {
  /// Creates a note.
  const ContextNote({required this.note, this.source = '', this.beadCitation});

  /// The finding, in the explorer's own words.
  final String note;

  /// Where it was found (a non-bead file path or ADR clause).
  final String source;

  /// The checked bead-field provenance, when this note cites a bead.
  final BeadFieldCitation? beadCitation;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'note': note,
    'source': source,
    if (beadCitation case final citation?) 'beadCitation': citation.toJson(),
  };

  /// Decodes one note; a note-less entry yields null.
  static ContextNote? fromJson(Object? json) {
    if (json is! Map) return null;
    final note = (json['note'] as String?)?.trim() ?? '';
    if (note.isEmpty) return null;
    final beadCitation = BeadFieldCitation.fromJson(json['beadCitation']);
    if (json.containsKey('beadCitation') && beadCitation == null) return null;
    return ContextNote(
      note: note,
      source: (json['source'] as String?)?.trim() ?? '',
      beadCitation: beadCitation,
    );
  }

  /// The one-line rendering the dossier prints.
  String get line => source.isEmpty ? note : '$note (`$source`)';
}

/// ONE lens's OUTCOME — the artifact a read-only explorer writes, and the ONLY
/// thing it writes. Sealed: consumed with an exhaustive `switch`, so a lane
/// that states its evidence was incomplete can never be read as a clean report.
sealed class DiscoveryLensOutcome {
  /// Creates an outcome for [lens].
  const DiscoveryLensOutcome({required this.lens});

  /// The lens that produced it.
  final String lens;

  /// The wire shape.
  Map<String, Object?> toJson();

  /// Decodes either outcome. A `report` outcome — and, for backward
  /// compatibility with an already-stamped same-round v1 file, one carrying NO
  /// `outcome` key at all — decodes as a [LensReport]; an
  /// `insufficient-evidence` outcome as an [InsufficientEvidenceReport].
  static DiscoveryLensOutcome? fromJson(Object? json) => switch (json) {
    final Map<Object?, Object?> value
        when value['outcome'] == 'insufficient-evidence' =>
      InsufficientEvidenceReport.fromJson(value),
    final Map<Object?, Object?> value
        when value['outcome'] == 'report' || !value.containsKey('outcome') =>
      LensReport.fromJson(value),
    _ => null,
  };
}

/// The NORMAL report — what the lens found, and what it found that CONTRADICTS
/// a standard.
final class LensReport extends DiscoveryLensOutcome {
  /// Creates a report.
  const LensReport({
    required super.lens,
    this.context = const [],
    this.violations = const [],
  });

  /// What it found (context for the architect).
  final List<ContextNote> context;

  /// What it found that CONTRADICTS a standard (the gate's evidence).
  final List<DiscoveryFinding> violations;

  /// The wire shape.
  @override
  Map<String, Object?> toJson() => {
    'outcome': 'report',
    'lens': lens,
    'version': 2,
    'context': [for (final c in context) c.toJson()],
    'violations': [for (final v in violations) v.toJson()],
  };

  /// Decodes a report; null for anything unreadable (the route then treats the
  /// lens as MISSING and re-gathers it once).
  static LensReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final lens = (json['lens'] as String?)?.trim() ?? '';
    if (lens.isEmpty) return null;
    final rawContext = json['context'];
    final rawViolations = json['violations'];
    return LensReport(
      lens: lens,
      context: [
        if (rawContext is List)
          for (final entry in rawContext)
            if (ContextNote.fromJson(entry) case final note?) note,
      ],
      violations: [
        if (rawViolations is List)
          for (final entry in rawViolations)
            if (DiscoveryFinding.fromJson(entry) case final finding?) finding,
      ],
    );
  }
}

/// The lens STATES that the canonical evidence it was handed is incomplete —
/// a KNOWN NON-ANSWER, which is neither a clean report nor a missing lane.
///
/// This is the typed exit the projection contract promises: rather than
/// wandering through unbounded tools to fill a hole the deterministic gather
/// already recorded, the lane names the exact evidence ids and their recorded
/// reasons. The route regathers the lane once and then HOLDS on it.
final class InsufficientEvidenceReport extends DiscoveryLensOutcome {
  /// Creates the outcome over its [gaps] (never empty).
  const InsufficientEvidenceReport({required super.lens, required this.gaps});

  /// The named holes, each carrying a canonical evidence id and the recorded
  /// reason it is not complete.
  final List<EvidenceGap> gaps;

  /// The wire shape.
  @override
  Map<String, Object?> toJson() => {
    'outcome': 'insufficient-evidence',
    'lens': lens,
    'version': 2,
    'gaps': [for (final gap in gaps) gap.toJson()],
  };

  /// Decodes the outcome; a lens-less report, a non-list `gaps`, an EMPTY
  /// `gaps`, or ANY malformed gap yields null (an unnamed hole is not a
  /// statement — the lane is then simply MISSING).
  static InsufficientEvidenceReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final lens = (json['lens'] as String?)?.trim() ?? '';
    final raw = json['gaps'];
    if (lens.isEmpty || raw is! List || raw.isEmpty) return null;
    final gaps = <EvidenceGap>[];
    for (final entry in raw) {
      final gap = EvidenceGap.fromJson(entry);
      if (gap == null) return null;
      gaps.add(gap);
    }
    return InsufficientEvidenceReport(lens: lens, gaps: gaps);
  }
}

/// One resolved code ANCHOR — a path the bead NAMES, resolved against the live
/// worktree, with the PATTERN that surrounds it (its directory's other files).
class ResolvedAnchor {
  /// Creates a resolution.
  const ResolvedAnchor({
    required this.anchor,
    required this.resolved,
    required this.contents,
    this.neighbors = const [],
    this.neighborsTruncated = false,
  });

  /// The path the bead named.
  final String anchor;

  /// Whether it exists in the worktree. A bead that names a file which does NOT
  /// exist is stating NEW work — the architect must know which.
  final bool resolved;

  /// The file's BOUNDED contents — the snippet the code lens reads instead of
  /// opening the file itself. A path that does not exist is a COMPLETE negative
  /// lookup (empty snippet, [EvidenceState.complete]); a read that threw is
  /// [EvidenceState.failed] with the exception in its `error`.
  final BoundedEvidence contents;

  /// The other files in its directory (the surrounding pattern), sorted, bounded
  /// by [kMaxNeighbors].
  final List<String> neighbors;

  /// Whether the neighbor list was clipped at [kMaxNeighbors].
  final bool neighborsTruncated;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'anchor': anchor,
    'resolved': resolved,
    'contents': contents.toJson(),
    'neighbors': neighbors,
    'neighborsTruncated': neighborsTruncated,
  };

  /// Decodes one anchor STRICTLY; an anchor-less or contents-less entry yields
  /// null.
  static ResolvedAnchor? fromJson(Object? json) {
    if (json is! Map) return null;
    final anchor = (json['anchor'] as String?)?.trim() ?? '';
    final contents = BoundedEvidence.fromJson(json['contents']);
    if (anchor.isEmpty || contents == null) return null;
    return ResolvedAnchor(
      anchor: anchor,
      resolved: json['resolved'] == true,
      contents: contents,
      neighbors: [
        if (json['neighbors'] case final List<Object?> raw)
          for (final n in raw)
            if (n is String) n,
      ],
      neighborsTruncated: json['neighborsTruncated'] == true,
    );
  }
}

/// The ANCHOR that does not exist in the worktree — a COMPLETE negative lookup
/// (the bead is naming NEW work, or a stale path). Shared by the offline gather
/// and [resolveAnchorOnDisk] so both spell the same record.
ResolvedAnchor unresolvedAnchor(String anchor, {required String source}) =>
    ResolvedAnchor(
      anchor: anchor,
      resolved: false,
      contents: boundDiscoveryEvidence(
        kind: 'code-anchor',
        subject: anchor,
        source: source,
        fullText: '',
      ),
    );

/// One PRIOR-ART hit — a bead or decision that already covered this ground.
class PriorArt {
  /// Creates a hit.
  const PriorArt({
    required this.beadId,
    required this.store,
    required this.status,
    required this.title,
    required this.field,
    required this.snippet,
    required this.query,
    required this.evidenceId,
  });

  /// A hit's canonical evidence identity — derived from its query, bead, field
  /// and snippet, so the id is stable across rounds while the hit is.
  static String identityFor({
    required String query,
    required String beadId,
    required String field,
    required String snippet,
  }) => boundDiscoveryEvidence(
    kind: 'prior-art-hit',
    subject: '$query|$beadId|$field',
    source: 'search:$query',
    fullText: snippet,
  ).id;

  /// The bead that matched.
  final String beadId;

  /// The substation that owns it.
  final String store;

  /// Its status wire (`open`/`closed` — a CLOSED decision is the point).
  final String status;

  /// Its title.
  final String title;

  /// The bead field that matched.
  final String field;

  /// The verbatim search snippet from the matched field.
  final String snippet;

  /// The query that surfaced it (provenance).
  final String query;

  /// This hit's canonical evidence identity ([identityFor]) — PERSISTED, so the
  /// dossier can cite the exact evidence profile without re-deriving it.
  final String evidenceId;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'id': beadId,
    'store': store,
    'status': status,
    'title': title,
    'field': field,
    'snippet': snippet,
    'query': query,
    'evidenceId': evidenceId,
  };

  /// Decodes one hit; incomplete provenance yields null.
  static PriorArt? fromJson(Object? json) {
    if (json is! Map) return null;
    final beadId = (json['id'] as String?)?.trim() ?? '';
    final field = BeadCitationField.fromWire(json['field']);
    final snippet = (json['snippet'] as String?)?.trim() ?? '';
    final evidenceId = (json['evidenceId'] as String?)?.trim() ?? '';
    if (beadId.isEmpty || field == null || snippet.isEmpty) return null;
    if (evidenceId.isEmpty) return null;
    return PriorArt(
      beadId: beadId,
      store: (json['store'] as String?)?.trim() ?? '',
      status: (json['status'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim() ?? '',
      field: field.wire,
      snippet: snippet,
      query: (json['query'] as String?)?.trim() ?? '',
      evidenceId: evidenceId,
    );
  }

  /// The one-line rendering the dossier prints.
  String get line => '`$beadId` ($store, $status) — $title';
}

/// The DETERMINISTIC gather's whole output (zero agents, zero judgement) — the
/// round's CANONICAL EVIDENCE PROFILE.
///
/// Everything the three lenses need is resolved ONCE here and persisted with
/// its provenance, its digest and its [EvidenceState]: the bead's own fields,
/// the code anchors with bounded snippets, the prior-art queries with per-query
/// coverage, the roster-qualified decision lookups, the surfaces' git history,
/// and the grading rubrics. A lens SYNTHESIZES a bounded projection of this
/// artifact ([projectDiscoveryEvidence]); it never re-runs a deterministic
/// lookup of its own.
class DiscoveryAnchors {
  /// Creates the gather.
  const DiscoveryAnchors({
    this.round = -1,
    this.workBeadId = '',
    this.beadFields = const [],
    this.rubrics = const {},
    this.rubricEvidence = const [],
    this.anchors = const [],
    this.symbols = const [],
    this.anchorsTruncated = false,
    this.symbolsTruncated = false,
    this.priorArtQueries = const [],
    this.decisionLookups = const [],
    this.history,
  });

  /// The discovery ROUND this gather was taken in — the freshness stamp a
  /// projection checks before it hands a lens anything. `-1` is the in-memory
  /// "no gather" default; it is never a decoded value.
  final int round;

  /// The work bead this gather was taken for.
  final String workBeadId;

  /// The bead's own fields, bounded — so no lens re-reads the bead.
  final List<BeadFieldEvidence> beadFields;

  /// The spec committee's own grading rubrics, id → prose. ADR-0000 A19's
  /// ratified Status footer names this pull: "A19 is the PRECEDENT for the
  /// rubrics-in-brief principle now generalized by the discovery circuit: A19
  /// shows the architect the STRUCTURAL contract; discovery shows it the FULL
  /// grading rubrics." The architect specs to the same definition the critics
  /// grade by.
  final Map<String, String> rubrics;

  /// The rubric IDENTITIES + digests (the prose itself rides [rubrics]).
  final List<RubricEvidence> rubricEvidence;

  /// The bead's PATH anchors, resolved against the live worktree.
  final List<ResolvedAnchor> anchors;

  /// The bead's SYMBOL anchors (a filesystem cannot resolve these — the code lens
  /// does, and they are the prior-art queries).
  final List<String> symbols;

  /// Whether the PATH-anchor extraction hit [kMaxAnchors] — the bead names more
  /// surfaces than this profile carries.
  final bool anchorsTruncated;

  /// Whether the SYMBOL extraction hit [kMaxAnchors].
  final bool symbolsTruncated;

  /// One coverage record per prior-art QUERY, in query order.
  final List<PriorArtQueryEvidence> priorArtQueries;

  /// One lookup record per roster-qualified SURFACE, in surface order.
  final List<DecisionSurfaceEvidence> decisionLookups;

  /// The round's batched git history over the resolved surfaces.
  final HistoryEvidence? history;

  /// Every prior-art hit, flattened — the shape the dossier's citation
  /// verification consumes. The per-query COVERAGE (which is what tells
  /// "no hits" from "nobody looked") stays on [priorArtQueries].
  List<PriorArt> get priorArt => [
    for (final query in priorArtQueries) ...query.hits,
  ];

  /// Whether every prior-art query actually reached a source — an unwired pull
  /// is reported LOUDLY in the dossier, never mistaken for "no prior art
  /// exists".
  bool get priorArtWired => priorArtQueries.every(
    (query) => query.state != EvidenceState.unavailable,
  );

  /// Every canonical evidence identity this gather carries — the profile the
  /// dossier cites and a downstream consumer verifies against.
  Set<String> get evidenceIds => {
    for (final field in beadFields) field.evidence.id,
    for (final rubric in rubricEvidence) rubric.evidence.id,
    for (final anchor in anchors) anchor.contents.id,
    for (final query in priorArtQueries) query.id,
    for (final query in priorArtQueries)
      for (final hit in query.hits) hit.evidenceId,
    for (final lookup in decisionLookups) lookup.id,
    for (final lookup in decisionLookups)
      for (final decision in lookup.decisions) decision.body.id,
    if (history case final value?) value.id,
    if (history case final value?)
      for (final commit in value.commits) commit.id,
  };

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 2,
    'round': round,
    'workBeadId': workBeadId,
    'beadFields': [for (final f in beadFields) f.toJson()],
    'rubrics': rubrics,
    'rubricEvidence': [for (final r in rubricEvidence) r.toJson()],
    'anchors': [for (final a in anchors) a.toJson()],
    'symbols': symbols,
    'anchorsTruncated': anchorsTruncated,
    'symbolsTruncated': symbolsTruncated,
    'priorArtQueries': [for (final q in priorArtQueries) q.toJson()],
    'decisionLookups': [for (final d in decisionLookups) d.toJson()],
    'history': history?.toJson(),
  };

  /// Decodes the gather STRICTLY — this artifact is the ONLY evidence three
  /// lenses get, so a partial decode is refused rather than silently emptied.
  /// Null for a non-map, any `version` but 2, a negative/non-integer round, an
  /// empty work bead id, ANY malformed nested record (never dropped), an
  /// unknown evidence state, a duplicate evidence id, or a failed record with
  /// no error. The route reads that null as EXPLICIT insufficient evidence.
  static DiscoveryAnchors? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['version'] != 2) return null;
    final round = json['round'];
    final workBeadId = (json['workBeadId'] as String?)?.trim() ?? '';
    if (round is! int || round < 0 || workBeadId.isEmpty) return null;

    final beadFields = _decodeAll(
      json['beadFields'],
      BeadFieldEvidence.fromJson,
    );
    final rubricEvidence = _decodeAll(
      json['rubricEvidence'],
      RubricEvidence.fromJson,
    );
    final anchors = _decodeAll(json['anchors'], ResolvedAnchor.fromJson);
    final priorArtQueries = _decodeAll(
      json['priorArtQueries'],
      PriorArtQueryEvidence.fromJson,
    );
    final decisionLookups = _decodeAll(
      json['decisionLookups'],
      DecisionSurfaceEvidence.fromJson,
    );
    if (beadFields == null ||
        rubricEvidence == null ||
        anchors == null ||
        priorArtQueries == null ||
        decisionLookups == null) {
      return null;
    }
    final rawSymbols = json['symbols'];
    if (rawSymbols is! List) return null;
    final rawHistory = json['history'];
    final history = rawHistory == null
        ? null
        : HistoryEvidence.fromJson(rawHistory);
    if (rawHistory != null && history == null) return null;

    final decoded = DiscoveryAnchors(
      round: round,
      workBeadId: workBeadId,
      beadFields: beadFields,
      rubrics: {
        if (json['rubrics'] case final Map<Object?, Object?> raw)
          for (final entry in raw.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
      rubricEvidence: rubricEvidence,
      anchors: anchors,
      symbols: [
        for (final s in rawSymbols)
          if (s is String) s,
      ],
      anchorsTruncated: json['anchorsTruncated'] == true,
      symbolsTruncated: json['symbolsTruncated'] == true,
      priorArtQueries: priorArtQueries,
      decisionLookups: decisionLookups,
      history: history,
    );
    if (decoded.evidenceIds.length != _evidenceIdCount(decoded)) return null;
    return decoded;
  }

  /// How many evidence ids the record CARRIES (duplicates included) — compared
  /// against the deduplicated [evidenceIds] to refuse a colliding profile.
  static int _evidenceIdCount(DiscoveryAnchors a) =>
      a.beadFields.length +
      a.rubricEvidence.length +
      a.anchors.length +
      a.priorArtQueries.length +
      a.priorArtQueries.fold<int>(0, (n, q) => n + q.hits.length) +
      a.decisionLookups.length +
      a.decisionLookups.fold<int>(0, (n, d) => n + d.decisions.length) +
      (a.history == null ? 0 : 1 + a.history!.commits.length);
}

/// Decodes every entry of [raw] through [decode], REFUSING the whole list when
/// any entry is malformed (a garbled evidence record is never silently dropped
/// out of a canonical artifact). Null ⇒ refuse.
List<T>? _decodeAll<T>(Object? raw, T? Function(Object?) decode) {
  if (raw is! List) return null;
  final out = <T>[];
  for (final entry in raw) {
    final value = decode(entry);
    if (value == null) return null;
    out.add(value);
  }
  return out;
}

/// ONE named hole in a lens's evidence bundle — the canonical id of the record
/// that is not complete, and the RECORDED reason it is not.
class EvidenceGap {
  /// Creates a gap.
  const EvidenceGap({required this.evidenceId, required this.reason});

  /// The canonical evidence id (or the artifact-level key) the gap is about.
  final String evidenceId;

  /// The recorded reason — a source's own error text where there is one.
  final String reason;

  /// The wire shape.
  Map<String, Object?> toJson() => {'evidenceId': evidenceId, 'reason': reason};

  /// Decodes one gap; an id-less or reason-less entry yields null.
  static EvidenceGap? fromJson(Object? json) {
    if (json is! Map) return null;
    final evidenceId = (json['evidenceId'] as String?)?.trim() ?? '';
    final reason = (json['reason'] as String?)?.trim() ?? '';
    if (evidenceId.isEmpty || reason.isEmpty) return null;
    return EvidenceGap(evidenceId: evidenceId, reason: reason);
  }

  /// The one-line rendering a hold or a report prints.
  String get line => '`$evidenceId` — $reason';
}

/// ONE lens's bounded slice of the canonical evidence profile — everything that
/// lens is allowed to see, and NOTHING else.
class DiscoveryEvidenceProjection {
  /// Creates a projection.
  const DiscoveryEvidenceProjection({
    required this.lens,
    required this.round,
    required this.workBeadId,
    required this.evidenceIds,
    required this.renderedEvidence,
    required this.gaps,
  });

  /// The lens this projection is for.
  final String lens;

  /// The round it was projected at.
  final int round;

  /// The work bead it was projected for.
  final String workBeadId;

  /// The canonical ids in this bundle, SORTED.
  final List<String> evidenceIds;

  /// The bundle, rendered for the lens's prompt — state, provenance, digest,
  /// id, snippet and error for every selected record.
  final String renderedEvidence;

  /// Every hole in the bundle. Empty ⇒ the lens may judge.
  final List<EvidenceGap> gaps;

  /// Whether the lens has everything it was promised.
  bool get isSufficient => gaps.isEmpty;
}

/// Projects [anchors] into [lens]'s OWN bundle — the whole reason the gather is
/// deterministic.
///
/// The artifact's [DiscoveryAnchors.round] and [DiscoveryAnchors.workBeadId] are
/// checked FIRST: a bundle from another round or another bead is not this lens's
/// evidence at all. Then the lens's slice is selected and rendered, and any
/// record that is a DETERMINISTIC GAP — [EvidenceState.truncated] or
/// [EvidenceState.failed], per `_isDeterministicEvidenceGap` — plus an
/// extraction truncation marker or an absent history, becomes an [EvidenceGap]
/// carrying the canonical id and the RECORDED reason.
///
/// An [EvidenceState.unavailable] record is RENDERED like every other and
/// contributes its evidence id, but it is NOT a gap: an uncomposed optional
/// source is context the lens narrates around, never an insufficiency that
/// overrides it.
///
/// The slices are ISOLATED by construction: no rubric prose enters a lens; no
/// decision/history/prior-art record enters the code lane; no code snippet,
/// history or prior-art record enters the decision lane; no code snippet or
/// decision record enters the prior-art lane.
DiscoveryEvidenceProjection projectDiscoveryEvidence(
  DiscoveryAnchors anchors, {
  required String lens,
  required int round,
  required String workBeadId,
}) {
  final gaps = <EvidenceGap>[];
  final ids = <String>[];
  final b = StringBuffer();

  if (anchors.round != round) {
    gaps.add(
      EvidenceGap(
        evidenceId: 'gather:round',
        reason:
            'the canonical gather is stamped round ${anchors.round}, not this '
            'round ($round)',
      ),
    );
  }
  if (anchors.workBeadId != workBeadId) {
    gaps.add(
      EvidenceGap(
        evidenceId: 'gather:workBeadId',
        reason:
            'the canonical gather is for `${anchors.workBeadId}`, not this work '
            'bead (`$workBeadId`)',
      ),
    );
  }

  void take(String label, BoundedEvidence evidence) {
    ids.add(evidence.id);
    _renderEvidence(b, label, evidence);
    if (_isDeterministicEvidenceGap(evidence.state)) {
      gaps.add(
        EvidenceGap(
          evidenceId: evidence.id,
          reason: _stateReason(evidence.state, evidence.error),
        ),
      );
    }
  }

  void beadFields() {
    b
      ..writeln('### The work bead, as the gather resolved it')
      ..writeln();
    for (final field in anchors.beadFields) {
      take('${field.beadId}.${field.field.wire}', field.evidence);
    }
  }

  switch (lens) {
    case kCodeLens:
      beadFields();
      b
        ..writeln('### The code this bead names, resolved')
        ..writeln();
      for (final anchor in anchors.anchors) {
        b.writeln(
          anchor.resolved
              ? '#### `${anchor.anchor}` — EXISTS'
              : '#### `${anchor.anchor}` — does NOT exist in this worktree '
                    '(NEW work, or a stale path)',
        );
        take(anchor.anchor, anchor.contents);
        if (anchor.neighbors.isNotEmpty) {
          b.writeln(
            'Its directory also holds: '
            '${anchor.neighbors.map((n) => '`$n`').join(', ')}'
            '${anchor.neighborsTruncated ? ' (CLIPPED)' : ''}',
          );
        }
        b.writeln();
      }
      if (anchors.symbols.isNotEmpty) {
        b
          ..writeln(
            'Symbols the bead names: '
            '${anchors.symbols.map((s) => '`$s`').join(', ')}',
          )
          ..writeln();
      }
      if (anchors.anchorsTruncated) {
        gaps.add(
          const EvidenceGap(
            evidenceId: 'gather:anchors',
            reason:
                'the bead names MORE code surfaces than the gather carries — '
                'the anchor extraction was clipped at its bound',
          ),
        );
      }
      if (anchors.symbolsTruncated) {
        gaps.add(
          const EvidenceGap(
            evidenceId: 'gather:symbols',
            reason:
                'the bead names MORE symbols than the gather carries — the '
                'symbol extraction was clipped at its bound',
          ),
        );
      }
    case kDecisionLens:
      beadFields();
      b
        ..writeln('### The recorded decisions governing this bead\'s surfaces')
        ..writeln();
      if (anchors.decisionLookups.isEmpty) {
        b
          ..writeln(
            'The bead names NO roster-qualified surface, so NO decision lookup '
            'was owed. That is a real empty, not a gap.',
          )
          ..writeln();
      }
      for (final lookup in anchors.decisionLookups) {
        b
          ..writeln('#### Surface `${lookup.surface}`')
          ..writeln(
            '- looked up ALREADY, by the deterministic roster-mode index over '
            'the live mounted-substation roster',
          )
          ..writeln('- state: ${lookup.state.name.toUpperCase()}')
          ..writeln('- id: `${lookup.id}`');
        if (lookup.error.isNotEmpty) b.writeln('- error: ${lookup.error}');
        if (lookup.decisions.isEmpty &&
            lookup.state == EvidenceState.complete) {
          b.writeln(
            '- the union is EMPTY for this surface — a real result, verified.',
          );
        }
        b.writeln();
        ids.add(lookup.id);
        if (_isDeterministicEvidenceGap(lookup.state)) {
          gaps.add(
            EvidenceGap(
              evidenceId: lookup.id,
              reason: _stateReason(lookup.state, lookup.error),
            ),
          );
        }
        for (final decision in lookup.decisions) {
          b.writeln(
            '##### `${decision.identity}` (status: ${decision.status}, '
            'entry: `${decision.entryPath}`)',
          );
          take(decision.identity, decision.body);
        }
      }
    case kPriorArtLens:
      beadFields();
      b
        ..writeln('### Prior art, by query')
        ..writeln();
      if (anchors.priorArtQueries.isEmpty) {
        b
          ..writeln('NO prior-art query was formed for this bead.')
          ..writeln();
      }
      for (final query in anchors.priorArtQueries) {
        b
          ..writeln('#### Query `${query.query}`')
          ..writeln('- state: ${query.state.name.toUpperCase()}')
          ..writeln('- id: `${query.id}`');
        if (query.error.isNotEmpty) b.writeln('- error: ${query.error}');
        if (query.hits.isEmpty && query.state == EvidenceState.complete) {
          b.writeln('- searched, NO hits — a real result, verified.');
        }
        for (final hit in query.hits) {
          b
            ..writeln('- ${hit.line}')
            ..writeln('  - id: `${hit.evidenceId}`')
            ..writeln('  - ${hit.field}: “${hit.snippet}”');
          ids.add(hit.evidenceId);
        }
        b.writeln();
        ids.add(query.id);
        if (_isDeterministicEvidenceGap(query.state)) {
          gaps.add(
            EvidenceGap(
              evidenceId: query.id,
              reason: _stateReason(query.state, query.error),
            ),
          );
        }
      }
      b
        ..writeln('### The history of the surfaces this bead names')
        ..writeln();
      final history = anchors.history;
      if (history == null) {
        gaps.add(
          const EvidenceGap(
            evidenceId: 'gather:history',
            reason: 'the canonical gather carries NO history record at all',
          ),
        );
        b
          ..writeln('NO history record was gathered.')
          ..writeln();
      } else {
        b
          ..writeln(
            '- read ALREADY, by the deterministic gather, over: '
            '${history.paths.map((path) => '`$path`').join(', ')}',
          )
          ..writeln('- state: ${history.state.name.toUpperCase()}')
          ..writeln('- id: `${history.id}`');
        if (history.error.isNotEmpty) b.writeln('- error: ${history.error}');
        if (history.commits.isEmpty &&
            history.state == EvidenceState.complete) {
          b.writeln('- these surfaces have NO history — a real result.');
        }
        for (final commit in history.commits) {
          b.writeln('- ${commit.sha} ${commit.authoredAt} ${commit.subject}');
          ids.add(commit.id);
        }
        b.writeln();
        ids.add(history.id);
        if (_isDeterministicEvidenceGap(history.state)) {
          gaps.add(
            EvidenceGap(
              evidenceId: history.id,
              reason: _stateReason(history.state, history.error),
            ),
          );
        }
      }
    default:
      gaps.add(
        EvidenceGap(
          evidenceId: 'gather:lens',
          reason:
              '`$lens` is not a lens this circuit projects evidence for — no '
              'bundle exists',
        ),
      );
  }

  final sorted = ids.toSet().toList()..sort();
  final manifest = StringBuffer()
    ..writeln('### Canonical evidence identities in THIS bundle')
    ..writeln();
  for (final id in sorted) {
    manifest.writeln('- `$id`');
  }
  manifest.writeln();
  return DiscoveryEvidenceProjection(
    lens: lens,
    round: round,
    workBeadId: workBeadId,
    evidenceIds: sorted,
    renderedEvidence: '$manifest$b',
    gaps: gaps,
  );
}

/// Renders ONE bounded record with everything a lens needs to tell an empty
/// successful lookup from a clipped, unwired or crashed one.
void _renderEvidence(StringBuffer b, String label, BoundedEvidence evidence) {
  b
    ..writeln('- **$label** — ${evidence.state.name.toUpperCase()}')
    ..writeln('  - id: `${evidence.id}`')
    ..writeln('  - source: `${evidence.source}`')
    ..writeln('  - digest: `sha256:${evidence.digest}`');
  if (evidence.error.isNotEmpty) {
    b.writeln('  - error: ${evidence.error}');
  }
  if (evidence.snippet.isEmpty) {
    b.writeln('  - (empty)');
  } else {
    b
      ..writeln('  - text:')
      ..writeln('```')
      ..writeln(evidence.snippet)
      ..writeln('```');
  }
  b.writeln();
}

/// The RECORDED reason a non-complete record is a gap — the source's own error
/// where it has one, else the state's own meaning.
String _stateReason(EvidenceState state, String error) => switch (state) {
  EvidenceState.complete => 'complete',
  EvidenceState.truncated =>
    error.isEmpty ? 'TRUNCATED — the record was clipped at its bound' : error,
  EvidenceState.unavailable =>
    error.isEmpty
        ? 'UNAVAILABLE — no source was wired, so nobody looked'
        : error,
  EvidenceState.failed =>
    error.isEmpty ? 'FAILED — the lookup crashed' : 'FAILED — $error',
};

/// Whether [state] is a DETERMINISTIC GAP — a record the gather PROMISED and
/// then could not deliver, which therefore overrides a lens's report and spends
/// the one-round regather budget.
///
/// Only a source that was PRESENT and then broke qualifies. [EvidenceState
/// .unavailable] means the optional source was never composed — nobody looked —
/// and that is A21(5)'s posture exactly ("a station that composed no
/// `PriorArtSource` gets a dossier line that says NOBODY LOOKED"): it stays
/// VISIBLE in the projection so the lens can narrate the limitation, but it
/// never overrides the lens and never escalates. Absence is not a broken
/// promise; a crash is.
bool _isDeterministicEvidenceGap(EvidenceState state) => switch (state) {
  EvidenceState.complete => false,
  EvidenceState.unavailable => false,
  EvidenceState.truncated => true,
  EvidenceState.failed => true,
};

/// The CURATED context the route hands to the architect — the deterministic
/// gather PLUS what the explorers found, minus what gated.
class DiscoveryDossier {
  /// Creates a dossier.
  const DiscoveryDossier({
    required this.anchors,
    this.workBeadId = '',
    this.context = const [],
    this.flags = const [],
    this.departures = const [],
    this.missingLenses = const [],
    this.evidenceIds = const [],
  });

  /// The deterministic half.
  final DiscoveryAnchors anchors;

  /// The SORTED canonical evidence identities the gather resolved — the public
  /// evidence PROFILE a downstream consumer (the architect's brief, and a later
  /// committee-selection pass) verifies against without a lookup of its own.
  final List<String> evidenceIds;

  /// The bead this dossier was assembled for.
  final String workBeadId;

  /// Every explorer's context notes, in lens order.
  final List<ContextNote> context;

  /// Findings that could NOT gate — an uncited concern, or a pattern deviation
  /// with no named precedent. They ride the brief as FLAGS (the architect answers
  /// them; they never hold the bead).
  final List<DiscoveryFinding> flags;

  /// Cited findings the bead ACKNOWLEDGED — the departure clause. The architect
  /// must CARRY the declared departure into the spec's `## ADR Alignment`.
  final List<DiscoveryFinding> departures;

  /// Lenses that produced no report even after the re-gather — recorded LOUDLY:
  /// the architect must know which lens did NOT run.
  final List<String> missingLenses;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 2,
    'workBeadId': workBeadId,
    'anchors': anchors.toJson(),
    'context': [for (final c in context) c.toJson()],
    'flags': [for (final f in flags) f.toJson()],
    'departures': [for (final d in departures) d.toJson()],
    'missingLenses': missingLenses,
    'evidenceIds': evidenceIds,
  };

  /// Decodes a dossier; null for anything unreadable (the next specify ride then
  /// simply gets no dossier — best-effort, exactly the `readRespecLedger`
  /// posture).
  static DiscoveryDossier? fromJson(Object? json) {
    if (json is! Map) return null;
    final anchors = DiscoveryAnchors.fromJson(json['anchors']);
    if (anchors == null) return null;
    return DiscoveryDossier(
      anchors: anchors,
      workBeadId: (json['workBeadId'] as String?)?.trim() ?? '',
      context: [
        if (json['context'] case final List<Object?> raw)
          for (final entry in raw)
            if (ContextNote.fromJson(entry) case final c?) c,
      ],
      flags: [
        if (json['flags'] case final List<Object?> raw)
          for (final entry in raw)
            if (DiscoveryFinding.fromJson(entry) case final f?) f,
      ],
      departures: [
        if (json['departures'] case final List<Object?> raw)
          for (final entry in raw)
            if (DiscoveryFinding.fromJson(entry) case final d?) d,
      ],
      missingLenses: [
        if (json['missingLenses'] case final List<Object?> raw)
          for (final l in raw)
            if (l is String) l,
      ],
      evidenceIds: [
        if (json['evidenceIds'] case final List<Object?> raw)
          for (final id in raw)
            if (id is String) id,
      ],
    );
  }
}

/// Whether [finding] may HOLD the bead — the whole gate, in one predicate.
///
///  1. NO CITATION, NO HOLD. An empty `standard` is a vibe; a vibe never gates.
///  1b. NO ASSERTED CONTRADICTION, NO HOLD. A finding must POSITIVELY assert a
///     real conflict (`contradicts == true`). A finding that names a standard but
///     concludes there is NO conflict — "None identified", "aligned with …" — is
///     a non-finding and can never gate (pow-hf2). Fails OPEN: absent/`false`
///     advises, never holds.
///  2. THE DEPARTURE CLAUSE. A departure the bead DECLARES is not an offence.
///  3. INTENT, NOT PRESENCE. A bead whose plan/acceptance REMOVES the cited
///     offence IS the fix — it passes. (The CLASS-1 false-positive: a
///     fix-the-violation bead necessarily HAS the offending text present at
///     discovery time, since discovery runs pre-specify.)
///  4. A RECORDED ENTRY HOLDS. A `decision` gates only when the cited standard
///     is a RECORDED decision entry — a `docs/decisions/` slug entry, or a
///     legacy ADR-0000 `A<n>` amendment (converted with `status: accepted`) —
///     which binds on write. Anything that is not a recorded entry is ADVISORY:
///     it rides as a FLAG, never a hold (the CLASS-2 false-positive). A `skill`
///     always gates when cited; a `pattern` needs a named precedent.
///
/// Ratified basis: the 2026-07-14 register-foot ratification ("DISCOVERY GATE:
/// pending amendments are ADVISORY, not binding") supersedes A21(2)'s "pending
/// `A<n>` amendments … they bind" clause, and adds the intent grade per A21's own
/// principle "only an unwitting contradiction gates". Bead `pow-712z` NARROWS
/// what that ruling can discriminate rather than reversing it: after the
/// option-C legacy migration (`decisions#legacy-register-migration`) every
/// converted amendment carries `status: accepted`, so the ADVISORY tier holds no
/// decision entries at all. The predicate below is UNCHANGED — only its
/// population is.
bool gatesTheBead(DiscoveryFinding finding) {
  if (finding.standard.trim().isEmpty) return false;
  if (!finding.contradicts) return false;
  if (finding.acknowledged) return false;
  if (finding.removesOffence) return false;
  return switch (finding.kind) {
    ViolationKind.decision => finding.ratified,
    ViolationKind.skill => true,
    ViolationKind.pattern => finding.precedent.trim().isNotEmpty,
  };
}

/// The discovery route's verdict. Sealed: consumed with an exhaustive `switch`.
sealed class DiscoveryVerdict {
  const DiscoveryVerdict();
}

/// CLEAN — advance into `specify` with [dossier] as the architect's context.
final class DiscoveryAdvance extends DiscoveryVerdict {
  /// Creates an advance over the curated [dossier].
  const DiscoveryAdvance(this.dossier);

  /// The curated context `buildSpecifyBrief` renders.
  final DiscoveryDossier dossier;
}

/// OFFENDER — hold the bead with the CITED offence. Never a vibe.
final class DiscoveryHold extends DiscoveryVerdict {
  /// Creates a hold over the cited [offenses] (never empty).
  const DiscoveryHold({required this.offenses, required this.reason});

  /// Every cited, unacknowledged offence — each one NAMES its standard.
  final List<DiscoveryFinding> offenses;

  /// The refinement ask the parked gate carries.
  final String reason;
}

/// A lens STATED that its canonical evidence is incomplete, and the re-gather
/// bound is spent — a KNOWN NON-ANSWER, held for a human.
///
/// This is the one distinction A21(3) does NOT already cover. An ABSENT lens
/// remains MISSING and eventually ADVANCES (the gate never fires on absence,
/// and a false HOLD is strictly worse than a wasted round). But a lane that
/// says, in a typed report, that required evidence was TRUNCATED or FAILED has
/// answered — with a non-answer. Advancing on that would hand the architect a
/// dossier whose incompleteness nobody ever saw.
///
/// [EvidenceState.unavailable] is on the OTHER side of that line, with absence:
/// an optional source nobody composed is A21(5)'s "NOBODY LOOKED" line, not a
/// broken promise. It never reaches here — the lens narrates without it, its
/// report stands, and no regather budget is spent.
final class DiscoveryEvidenceHold extends DiscoveryVerdict {
  /// Creates the hold over each lens's named [gaps].
  const DiscoveryEvidenceHold({required this.gaps, required this.reason});

  /// The named holes, per lens.
  final Map<String, List<EvidenceGap>> gaps;

  /// The refinement ask the parked gate carries.
  final String reason;
}

/// A lens produced NO parseable report — re-run it VIRGIN (once).
final class DiscoveryRegather extends DiscoveryVerdict {
  /// Creates a re-gather of [lenses].
  const DiscoveryRegather({required this.lenses, required this.reason});

  /// The lens step ids to rewind (siblings of the route in this circuit).
  final Set<String> lenses;

  /// The rewind's human-readable reason (diagnostics only).
  final String reason;
}

/// The DISCOVERY matrix (pure — zero I/O; the whole decision, unit-testable).
///
/// In order:
///  1. any CITED, unacknowledged, gateable violation ⇒ [DiscoveryHold]. The
///     offence is PROVEN — a missing sibling lens cannot unprove it, so the
///     cheapest exit is taken first.
///  2. a lens with NO report, under the cap ⇒ [DiscoveryRegather] — a broken
///     lane, not a verdict. The gate NEVER fires on absence.
///  3. else ⇒ [DiscoveryAdvance], carrying the curated dossier: every context
///     note, every FLAG (uncited concerns + precedent-less pattern deviations),
///     every DECLARED departure, and any lens that stayed silent through the cap.
DiscoveryVerdict decideDiscovery({
  required Map<String, DiscoveryLensOutcome?> lanes,
  required DiscoveryAnchors anchors,
  required Bead workBead,
  required int priorRound,
  int maxRounds = kMaxRegatherRounds,
}) {
  final reports = [
    for (final outcome in lanes.values)
      if (outcome case final LensReport report) report,
  ];
  final insufficient = {
    for (final entry in lanes.entries)
      if (entry.value case final InsufficientEvidenceReport stated)
        entry.key: stated.gaps,
  };
  final violations = [for (final r in reports) ...r.violations];
  final flags = [
    for (final v in violations)
      if (!gatesTheBead(v) && !v.acknowledged) v,
  ];

  // 1. the CITED offences — the only thing that holds a bead. A PROVEN offence
  //    is not unproven by a sibling lane's silence or its evidence hole, so the
  //    cheapest exit is still taken first.
  final offenses = violations.where(gatesTheBead).toList();
  if (offenses.isNotEmpty) {
    return DiscoveryHold(
      offenses: offenses,
      reason: renderDiscoveryHold(offenses: offenses, flags: flags),
    );
  }

  // 2. a lens that never reported, or one that STATED its evidence was
  //    incomplete — re-gather it ONCE, LOUDLY. Both are broken lanes at this
  //    point; what differs is what happens AT the cap (3 below).
  final missing = {
    for (final entry in lanes.entries)
      if (entry.value == null) entry.key,
  };
  final affected = {...missing, ...insufficient.keys};
  if (affected.isNotEmpty && priorRound < maxRounds) {
    return DiscoveryRegather(
      lenses: affected,
      reason:
          'RE-GATHER round ${priorRound + 1}/$maxRounds — '
          '${affected.join(', ')} produced no usable report (a broken LANE, '
          'not a verdict). Re-running the gather VIRGIN; the gate never fires '
          'on absence.',
    );
  }

  // 3. at the cap, the two lanes PART. A lane that STATED incomplete evidence
  //    has answered with a known non-answer: HOLD it for a human. A merely
  //    ABSENT lane still advances with the miss recorded LOUDLY (A21(3)).
  if (insufficient.isNotEmpty) {
    return DiscoveryEvidenceHold(
      gaps: insufficient,
      reason: renderDiscoveryEvidenceHold(insufficient),
    );
  }

  // 4. CLEAN — advance with the curated context.
  return DiscoveryAdvance(
    DiscoveryDossier(
      anchors: anchors,
      workBeadId: workBead.id,
      evidenceIds: anchors.evidenceIds.toList()..sort(),
      context: verifiedContextNotes(
        notes: [for (final r in reports) ...r.context],
        workBead: workBead,
        priorArt: anchors.priorArt,
      ),
      flags: flags,
      departures: [
        for (final v in violations)
          if (v.acknowledged && v.standard.trim().isNotEmpty) v,
      ],
      missingLenses: missing.toList()..sort(),
    ),
  );
}

/// Returns the live value of [field] on [bead].
String beadFieldValue(Bead bead, BeadCitationField field) => switch (field) {
  BeadCitationField.title => bead.title,
  BeadCitationField.description => bead.description,
  BeadCitationField.design => bead.design,
  BeadCitationField.acceptanceCriteria => bead.acceptanceCriteria,
  BeadCitationField.notes => bead.notes,
};

/// Whether [citation] exactly names evidence available to discovery.
bool verifiesBeadCitation({
  required BeadFieldCitation citation,
  required Bead workBead,
  required List<PriorArt> priorArt,
}) {
  if (citation.beadId == workBead.id) {
    return beadFieldValue(workBead, citation.field).contains(citation.excerpt);
  }
  return priorArt.any(
    (hit) =>
        hit.beadId == citation.beadId &&
        hit.field == citation.field.wire &&
        hit.snippet == citation.excerpt,
  );
}

/// Keeps only context whose bead attribution can be checked at assembly time.
List<ContextNote> verifiedContextNotes({
  required Iterable<ContextNote> notes,
  required Bead workBead,
  required List<PriorArt> priorArt,
}) {
  final knownIds = {workBead.id, for (final hit in priorArt) hit.beadId};
  return notes.where((note) {
    final citation = note.beadCitation;
    if (citation != null) {
      return verifiesBeadCitation(
        citation: citation,
        workBead: workBead,
        priorArt: priorArt,
      );
    }
    return !knownIds.any((id) => note.source.contains(id));
  }).toList();
}

/// The REFINEMENT ASK an offending bead parks with — it CITES every offence, and
/// it states the departure clause, so a governor's next move is unambiguous:
/// revise the bead, or DECLARE the departure.
String renderDiscoveryHold({
  required List<DiscoveryFinding> offenses,
  required List<DiscoveryFinding> flags,
}) {
  final b = StringBuffer()
    ..writeln(
      'DISCOVERY HOLD — this bead CONTRADICTS a standard we have already '
      'ratified, and it does not acknowledge the departure. NO specify agent and '
      'NO spec committee ran. It is HELD for refinement, not rejected.',
    )
    ..writeln()
    ..writeln('## The offence(s)');
  for (final offense in offenses) {
    b.writeln('- [${offense.kind.wire}] ${offense.line}');
  }
  b
    ..writeln()
    ..writeln('## Your two exits (either one clears this hold)')
    ..writeln(
      '1. REVISE the bead so it no longer contradicts the cited standard; or',
    )
    ..writeln(
      '2. DECLARE the departure IN the bead — "this departs from <the standard> '
      'because <why>". A considered departure is NOT an offence: it passes this '
      'gate and is judged downstream by the spec committee\'s `decision-alignment` '
      'lane. What this gate refuses is an UNWITTING contradiction.',
    );
  if (flags.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Also flagged (these did NOT hold the bead)');
    for (final flag in flags) {
      b.writeln('- [${flag.kind.wire}] ${flag.line}');
    }
  }
  return b.toString();
}

/// The REFINEMENT ASK a bead parks with when a lens STATED that the canonical
/// evidence it was handed is incomplete — it NAMES each hole by its canonical
/// evidence id and repeats the reason the gather itself recorded, so a
/// governor's next move is unambiguous.
String renderDiscoveryEvidenceHold(Map<String, List<EvidenceGap>> gaps) {
  final b = StringBuffer()
    ..writeln(
      'DISCOVERY EVIDENCE HOLD — the deterministic gather could not resolve '
      'evidence a lens NEEDED, and the re-gather round did not fix it. This is '
      'a KNOWN NON-ANSWER, not a verdict about the bead and not a missing '
      'lane: nothing about this bead was judged. It is HELD, not rejected.',
    )
    ..writeln()
    ..writeln('## The evidence that never landed');
  for (final entry in gaps.entries) {
    b.writeln('- **${entry.key}**');
    for (final gap in entry.value) {
      b.writeln('  - ${gap.line}');
    }
  }
  b
    ..writeln()
    ..writeln('## Your exits (either one clears this hold)')
    ..writeln(
      '1. FIX THE SOURCE the gather could not reach — compose the missing '
      'prior-art/decision/history seam, or repair the surface it crashed on; '
      'or',
    )
    ..writeln(
      '2. NARROW the bead so the evidence it needs fits inside the gather\'s '
      'bounds. Evidence that is clipped, unwired or crashed is not evidence '
      'that is absent — it is evidence nobody has yet.',
    );
  return b.toString();
}

/// The DOSSIER block `buildSpecifyBrief` renders — the architect's curated
/// context. Rubrics FIRST (ADR-0000 A19's Status footer: spec to the definition
/// you are graded by), then the resolved anchors, the prior art, what the
/// explorers found, the flags to answer, and the departures to carry.
String renderDiscoveryDossier(DiscoveryDossier dossier) {
  final a = dossier.anchors;
  final b = StringBuffer()
    ..writeln('## Discovery dossier (READ THIS — it is what the gather found)')
    ..writeln()
    ..writeln(
      'A read-only discovery circuit ran UPSTREAM of you: it pulled the rubrics '
      'your spec will be graded by, resolved the anchors this bead names, '
      'searched the attached stores for prior art, and cleared the bead of any '
      'unacknowledged contradiction of a ratified decision. Use it — do not '
      're-derive it.',
    );

  if (a.rubrics.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        '### How your spec will be graded (the committee\'s own rubrics)',
      );
    for (final entry in a.rubrics.entries) {
      b
        ..writeln()
        ..writeln('#### Rubric: `${entry.key}`')
        ..writeln(entry.value.trim());
    }
  }

  if (a.anchors.isNotEmpty || a.symbols.isNotEmpty) {
    b
      ..writeln()
      ..writeln('### The anchors this bead names, resolved');
    for (final anchor in a.anchors) {
      b.writeln(
        anchor.resolved
            ? '- `${anchor.anchor}` — EXISTS. Its directory also holds: '
                  '${anchor.neighbors.map((n) => '`$n`').join(', ')}'
            : '- `${anchor.anchor}` — does NOT exist in this worktree (the bead '
                  'is naming NEW work, or a stale path — confirm which)',
      );
    }
    if (a.symbols.isNotEmpty) {
      b.writeln(
        '- symbols named: ${a.symbols.map((s) => '`$s`').join(', ')} — grep them '
        'before you plan against them.',
      );
    }
  }

  b
    ..writeln()
    ..writeln('### Prior art (`space search` over the attached stores)');
  if (a.priorArtQueries.isEmpty || !a.priorArtWired) {
    b.writeln(
      '- NOT WIRED — this station composed no prior-art source, so NO search '
      'ran. This is not "no prior art exists": it is "nobody looked".',
    );
  }
  // Per QUERY, never flattened: a failed or clipped sweep can never print as
  // "searched, no hits".
  for (final query in a.priorArtQueries) {
    switch (query.state) {
      case EvidenceState.unavailable:
        continue;
      case EvidenceState.failed:
        b.writeln(
          '- `${query.query}` — the search FAILED (${query.error}). This is '
          'NOT an empty result.',
        );
      case EvidenceState.truncated:
      case EvidenceState.complete:
        if (query.hits.isEmpty) {
          b.writeln('- `${query.query}` — searched, no hits.');
        } else {
          for (final hit in query.hits) {
            b.writeln('- ${hit.line}');
          }
          if (query.truncated) {
            b.writeln(
              '- `${query.query}` — MORE hits exist than the '
              '$kMaxPriorArtHitsPerQuery carried here.',
            );
          }
        }
    }
  }

  if (dossier.context.isNotEmpty) {
    b
      ..writeln()
      ..writeln('### What the explorers found');
    for (final note in dossier.context) {
      b.writeln('- ${renderContextNote(note, dossier.workBeadId)}');
    }
  }

  if (dossier.flags.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        '### Flags — ANSWER these in the spec (they did not hold the bead)',
      );
    for (final flag in dossier.flags) {
      b.writeln('- [${flag.kind.wire}] ${flag.line}');
    }
  }

  if (dossier.departures.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        '### Declared departures — CARRY these into `## ADR Alignment`',
      );
    for (final departure in dossier.departures) {
      b.writeln('- [${departure.kind.wire}] ${departure.line}');
    }
  }

  if (dossier.evidenceIds.isNotEmpty) {
    b
      ..writeln()
      ..writeln('### Canonical evidence identities')
      ..writeln(
        'The exact profile the deterministic gather resolved for this round. '
        'Every note above was synthesized from one of these records — you can '
        'verify what was looked at without looking again.',
      )
      ..writeln();
    for (final id in dossier.evidenceIds) {
      b.writeln('- `$id`');
    }
  }

  if (dossier.missingLenses.isNotEmpty) {
    b
      ..writeln()
      ..writeln('### Lenses that did NOT report')
      ..writeln(
        '- ${dossier.missingLenses.join(', ')} — these lenses produced no report '
        'even after a re-gather. That context is MISSING, not clean: explore '
        'those angles yourself.',
      );
  }
  return b.toString();
}

/// Renders a context note with explicit bead ownership.
String renderContextNote(ContextNote note, String workBeadId) {
  final citation = note.beadCitation;
  if (citation == null) return note.line;
  final ownership = citation.beadId == workBeadId ? 'SELF' : 'FOREIGN';
  return '${note.note} '
      '($ownership ${citation.beadId}.${citation.field.wire}: '
      '“${citation.excerpt}”)';
}

/// The pluggable ANCHOR resolution seam (mirrors [RubricSource]) — ONE call per
/// round over EVERY anchor, so the tree is intaken exactly once. Defaults to
/// [resolveAnchorsOnDisk]; tests inject a Fake so the offline suite never
/// touches a real path.
typedef AnchorResolver =
    List<ResolvedAnchor> Function(String workspaceDir, List<String> anchors);

/// The pluggable PRIOR-ART seam — the deterministic `space search` pull, as one
/// call over every query, answering with per-QUERY coverage. The composing
/// station wires [stationPriorArt] (which resolves the roster from ITS
/// resident-station context); absent ⇒ NO search runs and every query is
/// recorded [EvidenceState.unavailable] (never a silent "no hits").
typedef PriorArtSource =
    Future<List<PriorArtQueryEvidence>> Function(List<String> queries);

/// The pluggable DECISION-INDEX seam — the composing station's roster-mode
/// `decisions index --surface <repo>/<path>` verb, run ONCE per round over
/// every roster-qualified surface. Absent ⇒ every surface is recorded
/// [EvidenceState.unavailable].
typedef DecisionIndexSource =
    Future<List<DecisionSurfaceEvidence>> Function(
      String workspaceDir,
      List<String> rosterQualifiedSurfaces,
    );

/// The pluggable HISTORY seam — one batched `git log` over the round's RESOLVED
/// surfaces. Absent ⇒ the history record is [EvidenceState.unavailable].
typedef HistorySource =
    Future<HistoryEvidence> Function(
      String workspaceDir,
      List<String> resolvedPaths,
    );

/// The real [AnchorResolver]: does the path exist in the worktree, and what else
/// lives in its directory (the SURROUNDING PATTERN the architect must match).
/// Deterministic (sorted) and bounded ([kMaxNeighbors]).
ResolvedAnchor resolveAnchorOnDisk(String workspaceDir, String anchor) {
  final path = p.join(workspaceDir, anchor);
  final file = File(path);
  if (!file.existsSync()) {
    return unresolvedAnchor(anchor, source: workspaceDir);
  }
  try {
    final text = file.readAsStringSync();
    final neighbors =
        file.parent
            .listSync()
            .whereType<File>()
            .map((f) => p.relative(f.path, from: workspaceDir))
            .where((n) => n != anchor)
            .toList()
          ..sort();
    final neighborsTruncated = neighbors.length > kMaxNeighbors;
    return ResolvedAnchor(
      anchor: anchor,
      resolved: true,
      contents: boundDiscoveryEvidence(
        kind: 'code-anchor',
        subject: anchor,
        source: path,
        fullText: text,
        state: neighborsTruncated ? EvidenceState.truncated : null,
      ),
      neighbors: neighbors.take(kMaxNeighbors).toList(),
      neighborsTruncated: neighborsTruncated,
    );
  } catch (e) {
    return ResolvedAnchor(
      anchor: anchor,
      resolved: true,
      contents: boundDiscoveryEvidence(
        kind: 'code-anchor',
        subject: anchor,
        source: path,
        fullText: '',
        state: EvidenceState.failed,
        error: '$e',
      ),
    );
  }
}

/// The bead's own fields, bounded ONCE — the intake block every lens used to
/// re-render from the live bead.
List<BeadFieldEvidence> boundedBeadFields(Bead bead) => [
  for (final field in BeadCitationField.values)
    BeadFieldEvidence(
      beadId: bead.id,
      field: field,
      evidence: boundDiscoveryEvidence(
        kind: 'bead-field',
        subject: '${bead.id}.${field.wire}',
        source: 'bead:${bead.id}#${field.wire}',
        fullText: beadFieldValue(bead, field),
      ),
    ),
];

/// The rubric IDENTITIES for [rubrics] — the digest of each rubric's complete
/// prose, in map order. The prose itself is NOT re-copied: it rides
/// `DiscoveryAnchors.rubrics` verbatim, which is what A19's rubrics-in-brief
/// principle requires.
List<RubricEvidence> rubricEvidenceOf(Map<String, String> rubrics) => [
  for (final entry in rubrics.entries)
    RubricEvidence(
      rubricId: entry.key,
      evidence: boundDiscoveryEvidence(
        kind: 'rubric',
        subject: entry.key,
        source: 'rubric:${entry.key}',
        fullText: entry.value,
      ),
    ),
];

/// The station's real prior-art source (ADR-0001, the coupled skill+command
/// pattern applied one layer in): the asset CALLS the deterministic
/// [StationSearchService] — the SAME UI-drivable service the `search` Command
/// adapts — over the roster resolved from the composing station's delegate.
/// READ-ONLY by construction (A37): the service's only store surface is a
/// single-spawn export.
///
/// A station composes it as
/// `buildCodeRegistry(priorArt: stationPriorArt(() => SpaceDelegate(...)))`.
/// It answers with one [PriorArtQueryEvidence] per requested query, in input
/// order: a seat the service reported [StoreAbsent] or [StoreFailed] makes the
/// query [EvidenceState.failed] with those reasons in its error, because a
/// PARTIAL sweep presented as a clean empty is exactly the blindness the search
/// service's sealed outcomes exist to prevent.
PriorArtSource stationPriorArt(
  sdk.GridDelegate Function() delegate, {
  required String gridHome,
  StationSearchService service = const StationSearchService(),
}) => (queries) async {
  final roster = codedRosterOf(delegate);
  final coverage = <PriorArtQueryEvidence>[];
  for (final query in queries) {
    try {
      final report = await service.search(
        query: query,
        roster: roster,
        gridHome: gridHome,
      );
      final gaps = [
        for (final store in report.stores)
          switch (store) {
            StoreSearched() => null,
            StoreAbsent(:final reason) => 'absent ${store.store.name}: $reason',
            StoreFailed(:final reason) => 'failed ${store.store.name}: $reason',
          },
      ].whereType<String>().toList();
      final all = [
        for (final hit in report.hits)
          PriorArt(
            beadId: hit.beadId,
            store: hit.store,
            status: hit.status,
            title: hit.title,
            field: hit.field,
            snippet: hit.snippet,
            query: query,
            evidenceId: PriorArt.identityFor(
              query: query,
              beadId: hit.beadId,
              field: hit.field,
              snippet: hit.snippet,
            ),
          ),
      ];
      coverage.add(
        _priorArtCoverage(
          query: query,
          hits: all,
          gaps: gaps,
          command: 'search $query',
        ),
      );
    } catch (e) {
      coverage.add(
        _priorArtCoverage(
          query: query,
          hits: const [],
          gaps: ['$e'],
          command: 'search $query',
        ),
      );
    }
  }
  return coverage;
};

/// Assembles ONE query's coverage: caps the hits, records the cap as
/// [EvidenceState.truncated], and turns any roster [gaps] into an explicit
/// [EvidenceState.failed] rather than a clean-looking partial result.
PriorArtQueryEvidence _priorArtCoverage({
  required String query,
  required List<PriorArt> hits,
  required List<String> gaps,
  required String command,
}) {
  final truncated = hits.length > kMaxPriorArtHitsPerQuery;
  final error = gaps.join('; ');
  return PriorArtQueryEvidence(
    id: boundDiscoveryEvidence(
      kind: 'prior-art-query',
      subject: query,
      source: command,
      fullText: hits.map((h) => h.evidenceId).join('\n'),
    ).id,
    query: query,
    state: error.isNotEmpty
        ? EvidenceState.failed
        : (truncated ? EvidenceState.truncated : EvidenceState.complete),
    truncated: truncated,
    error: error,
    hits: hits.take(kMaxPriorArtHitsPerQuery).toList(),
  );
}

/// The real [AnchorResolver]: [resolveAnchorOnDisk] over the whole batch, in
/// input order. ONE tree-intake pass per round.
List<ResolvedAnchor> resolveAnchorsOnDisk(
  String workspaceDir,
  List<String> anchors,
) => [for (final anchor in anchors) resolveAnchorOnDisk(workspaceDir, anchor)];

/// One flat record per deduplicated surface for every arm that never REACHES a
/// shell: no source composed, no runner invocation configured, no grid home
/// bound, and no substation to qualify the surface with.
///
/// The `command` is deliberately EMPTY. Rendering
/// [rosterDecisionIndexCommand]'s default here would stamp a runner verb this
/// pack never ran as the record's provenance — the exact "we looked with
/// `space`" claim that is false on every station whose verb is not `space`.
List<DecisionSurfaceEvidence> _decisionSourceRecords(
  List<String> surfaces, {
  required EvidenceState state,
  required String error,
}) {
  final seen = <String>{};
  return [
    for (final surface in surfaces)
      if (seen.add(surface))
        DecisionSurfaceEvidence(
          id: boundDiscoveryEvidence(
            kind: 'decision-surface',
            subject: surface,
            source: 'decision-index',
            fullText: '',
          ).id,
          surface: surface,
          command: '',
          state: state,
          error: error,
        ),
  ];
}

/// The SHELL fallback [DecisionIndexSource]: the composing station's ROSTER-MODE
/// `decisions index --surface <repo>/<path>` verb, run through the pack's
/// existing [ShellRunner] seam once per deduplicated surface inside ONE batch
/// call.
///
/// It preserves the roster-union contract exactly and only MOVES it: no
/// register-directory argument is ever passed (the omission is what resolves
/// the live roster), every `originRegister` is kept, and each returned `slug`
/// is resolved to its entry file by an exact multiline `slug:` match under its
/// own `originPath`. Zero results at exit 0 is a REAL empty union
/// ([EvidenceState.complete]); a non-zero exit, malformed JSON, a missing or
/// duplicate slug file, or an unreadable entry is [EvidenceState.failed] with
/// the output/exception preserved — a crashed lookup is never graded clean.
///
/// [runnerInvocation] is the composing station's OWN invocation, threaded from
/// `buildCodeRegistry(overlayArgs:)['runner']`. Blank or absent ⇒ NO shell call
/// is made at all and every surface is recorded [EvidenceState.unavailable]:
/// nobody looked, which is explicit context and NOT a deterministic gap.
///
/// [gridHome] is the COMPOSING STATION's grid home, threaded from the same
/// in-store binding (`buildCodeRegistry(overlayArgs:)['gridHome']`), and it is
/// the shell's working directory. It is NOT the work worktree: the runner is
/// the station's own JIT verb (`dart run lunar:lunar …`), which resolves only
/// where that station's package is, so running it from a per-bead worktree dies
/// `Could not find package`. Surfaces are roster-qualified, so the cwd carries
/// no path meaning of its own. Blank or absent ⇒ the same honest absence as a
/// blank runner (`no composing grid home is bound`) — the worktree is NEVER
/// substituted as a fallback.
///
/// A surface still prefixed [kUnknownSubstationPrefix] is likewise never
/// shelled. `<repo>` is the PROMPT placeholder an agent substitutes with its
/// own repository name; handed to a shell it parses as an input redirect
/// (`sh: repo: No such file`), so every lookup crashed and the lens read a
/// systematic failure. Nobody can look without a substation, so that is what
/// gets recorded.
///
/// **This deliberately departs from A23(4)** (`decisions#a23-bead-pow-kzx-the-
/// station-overlay-delivery-lib-renders-an`), which binds the overlay's
/// `runner` arg in-store from `kDefaultOverlayRunner` (`'space'`) with
/// `buildCodeRegistry(overlayArgs:)` overriding, precisely so an unconfigured
/// station still gets a WORKING vended skill. That default is right where A23
/// put it and is untouched: it RENDERS prose into a materialized skill, where a
/// wrong verb is legible to its reader. This is the other kind of use — the
/// pack EXECUTING the verb itself and grading the result as evidence — where
/// the same default is a hazard, not a convenience: on a station whose verb is
/// `dart run lunar:lunar`, `space` is exit 127, and under this circuit's gate a
/// crashed lookup would hold every bead naming a roster-qualified surface. So
/// the executing path takes NO default: it runs only what the station composed,
/// and records honest absence otherwise.
DecisionIndexSource commandDecisionIndexSource(
  ShellRunner runner, {
  String? runnerInvocation,
  String? gridHome,
}) {
  final stationRunner = runnerInvocation?.trim() ?? '';
  final stationGridHome = gridHome?.trim() ?? '';
  return (workspaceDir, surfaces) async {
    final out = <DecisionSurfaceEvidence>[];
    final seen = <String>{};
    for (final surface in surfaces) {
      if (!seen.add(surface)) continue;
      // The three arms that never REACH a shell, in precedence order. Each
      // records the same unavailable shape an absent source does — unwired
      // evidence the lens can read, never a crashed probe it must grade.
      if (surface.startsWith('$kUnknownSubstationPrefix/')) {
        out.addAll(
          _decisionSourceRecords(
            [surface],
            state: EvidenceState.unavailable,
            error: 'substation unknown — no roster-qualified surface',
          ),
        );
        continue;
      }
      if (stationRunner.isEmpty) {
        out.addAll(
          _decisionSourceRecords(
            [surface],
            state: EvidenceState.unavailable,
            error: 'no composing station runner is configured',
          ),
        );
        continue;
      }
      if (stationGridHome.isEmpty) {
        out.addAll(
          _decisionSourceRecords(
            [surface],
            state: EvidenceState.unavailable,
            error: 'no composing grid home is bound',
          ),
        );
        continue;
      }
      final command = rosterDecisionIndexCommand(
        surface: surface,
        runner: stationRunner,
      );
      try {
        final result = await runner.run(
          workingDirectory: stationGridHome,
          command: command,
        );
        if (!result.ok) {
          out.add(
            _decisionSurface(
              surface: surface,
              command: command,
              entries: const [],
              error:
                  'exit ${result.exitCode}: '
                  '${result.output.trim()}',
            ),
          );
          continue;
        }
        out.add(
          _decisionLookup(
            workspaceDir: workspaceDir,
            surface: surface,
            command: command,
            output: result.output,
          ),
        );
      } catch (e) {
        out.add(
          _decisionSurface(
            surface: surface,
            command: command,
            entries: const [],
            error: '$e',
          ),
        );
      }
    }
    return out;
  };
}

/// Parses ONE `decisions index` run and resolves every returned slug on disk.
DecisionSurfaceEvidence _decisionLookup({
  required String workspaceDir,
  required String surface,
  required String command,
  required String output,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(output);
  } catch (e) {
    return _decisionSurface(
      surface: surface,
      command: command,
      entries: const [],
      error: 'malformed index JSON: $e',
    );
  }
  if (decoded is! Map || decoded['spec'] != 1) {
    return _decisionSurface(
      surface: surface,
      command: command,
      entries: const [],
      error: 'index answered no `spec: 1` envelope',
    );
  }
  final raw = decoded['decisions'];
  if (raw is! List) {
    return _decisionSurface(
      surface: surface,
      command: command,
      entries: const [],
      error: 'index answered no `decisions` array',
    );
  }
  final entries = <DecisionEntryEvidence>[];
  for (final record in raw.take(kMaxDecisionEntriesPerSurface)) {
    if (record is! Map) {
      return _decisionSurface(
        surface: surface,
        command: command,
        entries: const [],
        error: 'index answered a non-map decision record',
      );
    }
    final slug = (record['slug'] as String?)?.trim() ?? '';
    final originRegister = (record['originRegister'] as String?)?.trim() ?? '';
    final originPath = (record['originPath'] as String?)?.trim() ?? '';
    if (slug.isEmpty || originRegister.isEmpty || originPath.isEmpty) {
      return _decisionSurface(
        surface: surface,
        command: command,
        entries: const [],
        error: 'index answered a record with no slug/originRegister/originPath',
      );
    }
    final String entryPath;
    final String body;
    try {
      final dir = Directory(
        p.isAbsolute(originPath)
            ? originPath
            : p.join(workspaceDir, originPath),
      );
      final slugLine = RegExp(
        '^\\s*slug:\\s*${RegExp.escape(slug)}\\s*\$',
        multiLine: true,
      );
      final matches = [
        for (final file in dir.listSync().whereType<File>())
          if (file.path.endsWith('.md') &&
              slugLine.hasMatch(file.readAsStringSync()))
            file,
      ];
      if (matches.length != 1) {
        return _decisionSurface(
          surface: surface,
          command: command,
          entries: const [],
          error:
              '${matches.length} entry files match `slug: $slug` under '
              '$originPath (exactly one must)',
        );
      }
      entryPath = matches.single.path;
      body = matches.single.readAsStringSync();
    } catch (e) {
      return _decisionSurface(
        surface: surface,
        command: command,
        entries: const [],
        error: 'could not resolve `slug: $slug` under $originPath — $e',
      );
    }
    entries.add(
      DecisionEntryEvidence(
        identity: '$originRegister#$slug',
        originRegister: originRegister,
        originPath: originPath,
        slug: slug,
        status: (record['status'] as String?)?.trim() ?? '',
        surfaces: [
          if (record['surfaces'] case final List<Object?> declared)
            for (final declaredSurface in declared)
              if (declaredSurface is String) declaredSurface,
        ],
        entryPath: entryPath,
        body: boundDiscoveryEvidence(
          kind: 'decision-entry',
          subject: '$originRegister#$slug',
          source: entryPath,
          fullText: body,
        ),
      ),
    );
  }
  return _decisionSurface(
    surface: surface,
    command: command,
    entries: entries,
    truncated: raw.length > kMaxDecisionEntriesPerSurface,
  );
}

/// Assembles ONE surface's lookup record — the shared shape every arm of
/// [commandDecisionIndexSource] lands on.
DecisionSurfaceEvidence _decisionSurface({
  required String surface,
  required String command,
  required List<DecisionEntryEvidence> entries,
  bool truncated = false,
  String error = '',
}) => DecisionSurfaceEvidence(
  id: boundDiscoveryEvidence(
    kind: 'decision-surface',
    subject: surface,
    source: command,
    fullText: entries.map((e) => e.identity).join('\n'),
  ).id,
  surface: surface,
  command: command,
  state: error.isNotEmpty
      ? EvidenceState.failed
      : (truncated || entries.any((e) => e.body.state != EvidenceState.complete)
            ? EvidenceState.truncated
            : EvidenceState.complete),
  truncated: truncated,
  error: error,
  decisions: entries,
);

/// The real [HistorySource]: ONE `git log` over every resolved surface, through
/// the pack's existing [GitRunner] seam.
///
/// A non-zero git, or a record that does not split into SHA / ISO timestamp /
/// subject, is [EvidenceState.failed]; an EMPTY successful log is
/// [EvidenceState.complete] (a surface with no history is a real answer).
HistorySource gitHistorySource(GitRunner runner) =>
    (workspaceDir, paths) async {
      final args = [
        'log',
        '--max-count=${kMaxHistoryCommits + 1}',
        '--format=%H%x09%aI%x09%s',
        '--',
        ...paths,
      ];
      final command = 'git ${args.join(' ')}';
      try {
        final result = await runner.run(
          workingDirectory: workspaceDir,
          args: args,
        );
        if (!result.ok) {
          return _history(
            paths: paths,
            command: command,
            commits: const [],
            error: 'exit ${result.exitCode}: ${result.output.trim()}',
          );
        }
        final records = result.output
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        final commits = <HistoryCommitEvidence>[];
        for (final record in records.take(kMaxHistoryCommits)) {
          final parts = record.split('\t');
          if (parts.length != 3) {
            return _history(
              paths: paths,
              command: command,
              commits: const [],
              error: 'unparseable log record: $record',
            );
          }
          commits.add(
            HistoryCommitEvidence(
              id: boundDiscoveryEvidence(
                kind: 'history-commit',
                subject: parts[0],
                source: command,
                fullText: record,
              ).id,
              sha: parts[0],
              authoredAt: parts[1],
              subject: parts[2],
            ),
          );
        }
        return _history(
          paths: paths,
          command: command,
          commits: commits,
          truncated: records.length > kMaxHistoryCommits,
        );
      } catch (e) {
        return _history(
          paths: paths,
          command: command,
          commits: const [],
          error: '$e',
        );
      }
    };

/// Assembles the round's history record — the shared shape every arm of
/// [gitHistorySource] lands on.
HistoryEvidence _history({
  required List<String> paths,
  required String command,
  required List<HistoryCommitEvidence> commits,
  bool truncated = false,
  String error = '',
}) => HistoryEvidence(
  id: boundDiscoveryEvidence(
    kind: 'history',
    subject: paths.join('|'),
    source: command,
    fullText: commits.map((c) => c.sha).join('\n'),
  ).id,
  paths: paths,
  command: command,
  state: error.isNotEmpty
      ? EvidenceState.failed
      : (truncated ? EvidenceState.truncated : EvidenceState.complete),
  truncated: truncated,
  error: error,
  commits: commits,
);

/// Every prior-art query's coverage, gathered through [source] — or an explicit
/// [EvidenceState.unavailable] record per query when NO source is wired, and a
/// [EvidenceState.failed] record per query when the batch itself threw.
Future<List<PriorArtQueryEvidence>> gatherPriorArt(
  PriorArtSource? source,
  List<String> queries,
) async {
  List<PriorArtQueryEvidence> flat(EvidenceState state, String error) => [
    for (final query in queries)
      PriorArtQueryEvidence(
        id: boundDiscoveryEvidence(
          kind: 'prior-art-query',
          subject: query,
          source: 'search $query',
          fullText: '',
        ).id,
        query: query,
        state: state,
        error: error,
      ),
  ];
  if (source == null) {
    return flat(EvidenceState.unavailable, 'no prior-art source is composed');
  }
  try {
    return await source(queries);
  } catch (e) {
    return flat(EvidenceState.failed, '$e');
  }
}

/// Every roster-qualified surface's decision lookup, gathered through [source]
/// — or an explicit [EvidenceState.unavailable]/[EvidenceState.failed] record
/// per surface when no source is wired / the batch threw.
///
/// The two arms are NOT the same answer. An absent source is nobody LOOKING;
/// a composed source that threw is a lookup that BROKE. Neither invents a
/// command string it never ran (see [_decisionSourceRecords]).
Future<List<DecisionSurfaceEvidence>> gatherDecisions(
  DecisionIndexSource? source,
  String workspaceDir,
  List<String> surfaces,
) async {
  if (source == null) {
    return _decisionSourceRecords(
      surfaces,
      state: EvidenceState.unavailable,
      error: 'no decision-index source is composed',
    );
  }
  try {
    return await source(workspaceDir, surfaces);
  } catch (e) {
    return _decisionSourceRecords(
      surfaces,
      state: EvidenceState.failed,
      error: '$e',
    );
  }
}

/// The round's git history, gathered through [source] — or an explicit
/// [EvidenceState.unavailable]/[EvidenceState.failed] record when no source is
/// wired / the batch threw.
Future<HistoryEvidence> gatherHistory(
  HistorySource? source,
  String workspaceDir,
  List<String> paths,
) async {
  if (source == null) {
    return HistoryEvidence(
      id: boundDiscoveryEvidence(
        kind: 'history',
        subject: paths.join('|'),
        source: '',
        fullText: '',
      ).id,
      paths: paths,
      command: '',
      state: EvidenceState.unavailable,
      error: 'no history source is composed',
    );
  }
  try {
    return await source(workspaceDir, paths);
  } catch (e) {
    return _history(paths: paths, command: '', commits: const [], error: '$e');
  }
}

/// The PATH + SYMBOL anchors [bead] names — the round's ONLY tree-intake pass.
/// Pure, deterministic (first-appearance order), bounded ([kMaxAnchors]), and
/// exposed for unit tests.
///
/// A PATH is a known-extension repository-relative token, found either inside
/// backticks OR as a plain path token in the prose (a bead that writes
/// lib/src/x.dart without backticks names the same surface). A SYMBOL is a
/// BACKTICKED identifier carrying an inner capital (`buildSpecifyBrief`,
/// `kSpecReviewCircuit`) or an initial one (`Heartbeat`) — which is what keeps
/// ordinary backticked prose (`bd`, `main`, `haiku`) out of the set.
///
/// [pathsTruncated]/[symbolsTruncated] record a hit on [kMaxAnchors]: the bead
/// names MORE surfaces than this profile carries, and a lens must be told that
/// rather than shown a silently short list.
({
  List<String> paths,
  List<String> symbols,
  bool pathsTruncated,
  bool symbolsTruncated,
})
beadAnchors(Bead bead) {
  final text = [
    bead.title,
    bead.description,
    bead.design,
    bead.acceptanceCriteria,
    bead.notes,
  ].join('\n');
  final paths = <String>{};
  final symbols = <String>{};
  for (final match in _anchorSpan.allMatches(text)) {
    final backticked = match.group(1);
    final span = (backticked ?? match.group(2)!).trim();
    if (_isPathAnchor(span)) {
      paths.add(span);
    } else if (backticked != null && _isSymbolAnchor(span)) {
      symbols.add(span);
    }
  }
  return (
    paths: paths.take(kMaxAnchors).toList(),
    symbols: symbols.take(kMaxAnchors).toList(),
    pathsTruncated: paths.length > kMaxAnchors,
    symbolsTruncated: symbols.length > kMaxAnchors,
  );
}

/// A backticked span (group 1) OR a bare repository-relative path token
/// (group 2) — alternated in ONE scan so both sources keep first-appearance
/// order and a backticked path is never re-matched as a bare one.
final RegExp _anchorSpan = RegExp(
  r'`([^`\n]+)`|([\w./-]+\.(?:dart|md|yaml|yml|json))',
);

final RegExp _pathAnchor = RegExp(r'^[\w./-]+\.(dart|md|yaml|yml|json)$');
final RegExp _symbolChars = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
final RegExp _capital = RegExp('[A-Z]');

bool _isPathAnchor(String span) =>
    span.contains('/') && _pathAnchor.hasMatch(span);

bool _isSymbolAnchor(String span) =>
    _symbolChars.hasMatch(span) &&
    span.length >= 4 &&
    (_capital.hasMatch(span[0]) || _capital.hasMatch(span.substring(1)));

/// The PRIOR-ART queries for [bead] — its SYMBOL anchors (a symbol is a
/// high-signal substring query; a whole title is not), else its distinctive title
/// words. Pure, bounded by [kMaxPriorArtQueries], exposed for unit tests.
List<String> priorArtQueries(Bead bead, List<String> symbols) {
  if (symbols.isNotEmpty) return symbols.take(kMaxPriorArtQueries).toList();
  final words = <String>[];
  for (final raw in bead.title.toLowerCase().split(RegExp(r'[^a-z0-9_]+'))) {
    if (raw.length >= 6 && !words.contains(raw)) words.add(raw);
    if (words.length == kMaxPriorArtQueries) break;
  }
  return words;
}

/// The deterministic gather, read back (best-effort — an absent/corrupt file
/// degrades to "no gather", never a throw). The `readRespecLedger` posture.
DiscoveryAnchors? readDiscoveryAnchors(String workspaceDir) =>
    _readJson(anchorsPath(workspaceDir), DiscoveryAnchors.fromJson);

/// The curated dossier, read back — what `SpecifyCapability` hands the architect.
DiscoveryDossier? readDiscoveryDossier(String workspaceDir) =>
    _readJson(discoveryDossierPath(workspaceDir), DiscoveryDossier.fromJson);

T? _readJson<T>(String path, T? Function(Object?) decode) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return decode(jsonDecode(file.readAsStringSync()));
  } catch (_) {
    return null;
  }
}

void _writeJson(String path, Map<String, Object?> json) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(jsonEncode(json));

/// The REGATHER round LEDGER — just the round number, written into the bead's
/// worktree by [DiscoveryRouteCapability] on a [DiscoveryRegather] and read back
/// on the NEXT round to apply the [kMaxRegatherRounds] bound. Unlike the respec
/// ledger it carries NO guidance: a re-gather re-runs the gather VIRGIN, so there
/// is nothing to correct.
class DiscoveryRegatherLedger {
  /// Creates a ledger for [round].
  const DiscoveryRegatherLedger({required this.round});

  /// The regather round this ledger opens (1-based; capped at
  /// [kMaxRegatherRounds]).
  final int round;

  /// The wire shape (hand-rolled — this pack carries no `json_serializable`).
  Map<String, Object?> toJson() => {'version': 1, 'round': round};

  /// Decodes a ledger; null for anything unreadable (no round, bad JSON) — the
  /// caller then treats it as "no prior round".
  static DiscoveryRegatherLedger? fromJson(Object? json) {
    if (json is! Map) return null;
    final round = json['round'];
    if (round is! int || round < 1) return null;
    return DiscoveryRegatherLedger(round: round);
  }
}

/// The regather ledger at [workspaceDir], or null when there is none / it is
/// unreadable. Best-effort: a corrupt ledger degrades to "no prior round" (the
/// counter restarts) — it can never throw into a route.
DiscoveryRegatherLedger? readDiscoveryRegatherLedger(String workspaceDir) =>
    _readJson(
      discoveryRegatherLedgerPath(workspaceDir),
      DiscoveryRegatherLedger.fromJson,
    );

/// Writes [ledger] into [workspaceDir]. THROWS on a write that cannot land — the
/// caller ([DiscoveryRouteCapability]) turns that into a LOUD [RouteFailure]: a
/// regather whose round counter never advances would re-run the gather sub-DAG
/// unbounded until the engine's belt fires (guards LOUD or GONE).
void writeDiscoveryRegatherLedger(
  String workspaceDir,
  DiscoveryRegatherLedger ledger,
) => _writeJson(discoveryRegatherLedgerPath(workspaceDir), ledger.toJson());

/// Deletes the regather ledger at [workspaceDir] — called on a [DiscoveryAdvance]
/// so a LATER rework round can never re-inject a stale round count into a fresh
/// gather. Best-effort: a delete that fails never gates an otherwise-clean
/// advance.
void clearDiscoveryRegatherLedger(String workspaceDir) {
  try {
    final file = File(discoveryRegatherLedgerPath(workspaceDir));
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Hygiene only — a stale ledger is re-overwritten by the next regather anyway.
  }
}

/// The round-aware discovery sweep [AnchorsCapability] runs at the head of
/// every round — the twin of [sweepStaleCritique]. It ensures
/// [discoveryDirPath] exists and deletes every entry in it EXCEPT a lens report
/// of THIS round: a `<lens>.json` whose stamps pass the one shared fence
/// ([_freshLensReport]) for the sibling node path `<circuitPath>/<lens>` at
/// [round]. Everything else — a PRIOR round's report, a FOREIGN node's, an
/// unstamped or unparseable file, and the previous round's `anchors.json` /
/// `dossier.json` (neither carries a lens stamp, and the gather rewrites the
/// first immediately) — is deleted, exactly what the blanket wipe deleted.
///
/// KEEPING this round's reports is the whole point. Under the
/// `validates: `[kAnchorsStep] derived wave the engine re-keys the gather
/// closure NODE BY NODE, so a re-keyed LENS can legitimately write THIS
/// round's report BEFORE this step's own successor runs; a blanket wipe then
/// destroys finished work the route's join can only wait for forever (the lane
/// is terminal — nothing will re-write it). "The wipe only runs at round start"
/// becomes a property of WHAT it deletes, not of WHEN it runs. Best-effort per
/// entry: a survivor is caught by the read fence.
void sweepStaleDiscovery(
  String workspaceDir, {
  required String circuitPath,
  required int round,
}) {
  final dir = Directory(discoveryDirPath(workspaceDir));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    return;
  }
  for (final entry in dir.listSync(followLinks: false)) {
    var keep = false;
    if (entry is File && entry.path.endsWith('.json')) {
      final lens = p.basenameWithoutExtension(entry.path);
      try {
        keep =
            _freshLensReport(
              jsonDecode(entry.readAsStringSync()),
              nodePath: '$circuitPath/$lens',
              round: round,
            ) !=
            null;
      } catch (_) {
        keep = false; // unparseable is stale by construction.
      }
    }
    if (!keep) {
      try {
        entry.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort per entry — a survivor is caught by the read fence.
      }
    }
  }
}

/// TIER 1 of the discovery circuit — the DETERMINISTIC gather (ZERO agents).
///
/// It pulls what a machine can be RIGHT about, so no agent spends a token
/// re-deriving it: the spec committee's OWN rubrics ([rubricIds] through the
/// injected [RubricSource] — ADR-0000 A19's Status footer), the bead's PATH
/// anchors resolved against the live worktree with the pattern that surrounds
/// them, and prior art through the read-only [PriorArtSource].
///
/// It ALSO owns the discovery round's FRESHNESS (the A17(8) posture, one level
/// down): `ClearCritiqueCapability` sweeps `.grid/critique/` only DOWNSTREAM of
/// `specify`, so on a `grid rework` round — same worktree, no re-key, so every
/// node path is byte-identical — the lenses would otherwise read the PREVIOUS
/// round's reports. This step runs at the head of every round, immediately
/// before the lenses, and its ROUND-AWARE SWEEP ([sweepStaleDiscovery]) is
/// their guarantee: it deletes what the read fence would refuse and keeps what
/// THIS round already wrote, so a sweep that lands between lanes is harmless by
/// construction. Best-effort: a sweep that throws never gates the round.
///
/// Offline/dry-run posture: a workspace directory that does not exist on disk
/// (the synthetic path an offline suite mounts) computes the gather and skips the
/// WRITE — the same no-op posture [PinDiffCapability] takes. A write that CANNOT
/// land in a live worktree is [Failed], LOUD: the lenses would explore blind and
/// the architect would get no dossier, which is the whole point of this circuit.
class AnchorsCapability extends ServiceCapability {
  /// Creates the gather over its injected seams (config = VALUES, impls = DI):
  /// [rubricIds] (WHICH rubrics to pull — `buildCodeRegistry` wires the spec
  /// committee's own), [rubrics] (the Packaged-AI-Asset loader), [resolver] (the
  /// anchor probe; null ⇒ [resolveAnchorOnDisk]), [priorArt] (null ⇒ no search
  /// runs, reported LOUDLY) and [clearer] (the offline no-op seam; null ⇒ the
  /// real round-aware [sweepStaleDiscovery]).
  const AnchorsCapability({
    List<String> rubricIds = const [],
    RubricSource? rubrics,
    AnchorResolver? resolver,
    PriorArtSource? priorArt,
    DecisionIndexSource? decisions,
    HistorySource? history,
    DirectoryClearer? clearer,
  }) : _rubricIds = rubricIds,
       _rubrics = rubrics,
       _resolver = resolver,
       _priorArt = priorArt,
       _decisions = decisions,
       _history = history,
       _clearer = clearer;

  final List<String> _rubricIds;
  final RubricSource? _rubrics;
  final AnchorResolver? _resolver;
  final PriorArtSource? _priorArt;
  final DecisionIndexSource? _decisions;
  final HistorySource? _history;
  final DirectoryClearer? _clearer;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); after every await only
    // the captured values + the cancel token are touched (ADR-0008 D3).
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    // The SESSION's own substation — the value the engine stamps as a session
    // bead's `metadata.rig`, mounted here as an ambient config VALUE. A WORK
    // bead carries no `rig` (it is a session-bead field), so deriving the
    // roster prefix from the work bead alone left EVERY surface prefixed
    // `<repo>`.
    final substation = context.getInheritedSeedOfExactType<SubstationConfig>();
    if (bead == null) {
      return const Failed(
        'discovery/anchors: no ambient work bead to gather for (the '
        'WorkBead/SessionScope mounts it)',
      );
    }
    final workspaceDir = workspace?.workspaceDir ?? '';
    final live =
        workspaceDir.isNotEmpty && Directory(workspaceDir).existsSync();

    // Round-freshness: a ROUND-AWARE SWEEP, never a blanket wipe. It deletes
    // exactly what the read fence would refuse and KEEPS a report stamped for
    // this circuit's lens node paths at THIS round, so a sweep landing mid-wave
    // cannot destroy a re-keyed lens's finished work. Best-effort — the A17(8)
    // posture; an injected clearer stays the offline no-op seam.
    if (live) {
      try {
        final clearer = _clearer;
        if (clearer != null) {
          clearer(discoveryDirPath(workspaceDir));
        } else {
          sweepStaleDiscovery(
            workspaceDir,
            circuitPath: parentPath(args.nodePath),
            round: verdictRound(args),
          );
        }
      } catch (_) {
        // Best-effort hygiene (the ClearCritiqueCapability posture).
      }
    }

    // ONE deterministic pass per seam, per round — the whole point of this
    // step. Every source is invoked EXACTLY once, in a fixed order, and the
    // cancel token is checked between them.
    final round = verdictRound(args);
    final extracted = beadAnchors(bead);
    // The bead's own `metadata['rig']` stays an OVERRIDE (the operator bridge
    // that stamps it in flight keeps working); the session config is the
    // standing answer; neither ⇒ '' ⇒ [kUnknownSubstationPrefix], which the
    // decision source records unavailable rather than shelling.
    final rig = bead.metadata['rig'];
    final surfaces = rosterQualifiedPaths(
      paths: extracted.paths,
      substation: [if (rig is String) rig, substation?.substationId ?? '']
          .firstWhere(
            (candidate) => candidate.trim().isNotEmpty,
            orElse: () => '',
          ),
    );
    final resolved = live
        ? (_resolver ?? resolveAnchorsOnDisk)(workspaceDir, extracted.paths)
        : [
            for (final path in extracted.paths)
              unresolvedAnchor(path, source: workspaceDir),
          ];
    final queries = priorArtQueries(bead, extracted.symbols);
    final priorArt = await gatherPriorArt(_priorArt, queries);
    if (args.cancel.isCancelled) return const Failed('cancelled');
    final decisions = await gatherDecisions(_decisions, workspaceDir, surfaces);
    if (args.cancel.isCancelled) return const Failed('cancelled');
    final history = await gatherHistory(_history, workspaceDir, [
      for (final anchor in resolved)
        if (anchor.resolved) anchor.anchor,
    ]);
    if (args.cancel.isCancelled) return const Failed('cancelled');

    final rubricSource = _rubrics;
    final rubricBodies = {
      if (rubricSource != null)
        for (final rubric in _rubricIds) rubric: rubricSource(rubric),
    };
    final anchors = DiscoveryAnchors(
      round: round,
      workBeadId: bead.id,
      beadFields: boundedBeadFields(bead),
      rubrics: rubricBodies,
      rubricEvidence: rubricEvidenceOf(rubricBodies),
      anchors: resolved,
      symbols: extracted.symbols,
      anchorsTruncated: extracted.pathsTruncated,
      symbolsTruncated: extracted.symbolsTruncated,
      priorArtQueries: priorArt,
      decisionLookups: decisions,
      history: history,
    );

    if (live) {
      try {
        _writeJson(anchorsPath(workspaceDir), anchors.toJson());
      } catch (e) {
        return Failed(
          'discovery/anchors: could not write the gather at '
          '${anchorsPath(workspaceDir)} — $e. Refusing to explore blind (every '
          'lens reads it, and the architect\'s dossier is built on it).',
        );
      }
    }

    return Ok({
      kVerdictRoundKey: '$round',
      'anchors': '${anchors.anchors.length}',
      'resolved': '${anchors.anchors.where((a) => a.resolved).length}',
      'symbols': '${extracted.symbols.length}',
      'rubrics': '${anchors.rubrics.length}',
      'decisions': '${decisions.length}',
      'history': '${history.commits.length}',
      'evidence': '${anchors.evidenceIds.length}',
      'priorArt': _priorArt == null
          ? 'not-wired'
          : '${anchors.priorArt.length}',
    });
  }
}

/// The READ-ONLY working agreement every lens rides (A37, and the gather lane's
/// own doctrine: it reads, it CITES, it decides NOTHING).
/// Rendered into the brief, and asserted VERBATIM in test: the one artifact a
/// lens may write is its own report file.
const String kLensWorkingAgreement = '''
- You are READ-ONLY. Do NOT edit any file, do NOT run `git` (no commit, no push,
  no PR), and do NOT touch the bead: no `bd update`, no `bd close`, no bd
  mutation of ANY kind, ever. You are a foreign reader of a live store (A37).
- The ONE artifact you write is your own report file, at the absolute path this
  prompt names. Nothing else.
- You DECIDE nothing. You do not grade, you do not rule, and you do not spec.
  You REPORT what you found and you CITE where you found it. A deterministic
  route reads your report and makes the call.
- Stay CHEAP: you were handed a BOUNDED evidence bundle; synthesize it. Do NOT
  read the tree, do NOT run a decision-index lookup, do NOT run a prior-art
  search, and do NOT read git history — every one of those already ran when a
  source was composed, and the recorded state is in your prompt.
- Use ONLY the supplied projection. If a required record is TRUNCATED or FAILED,
  emit the typed insufficient-evidence report and stop. Do not use a tool to
  fill the hole.
- UNAVAILABLE means the optional deterministic source was absent. Name that
  limitation and synthesize the evidence you do have; do not emit an
  insufficient-evidence report for absence.''';

/// The stamp instruction every lens prompt writes after its report template —
/// the discovery twin of [kVerdictStampInstruction]. BOTH stamps are required
/// and copied verbatim: `nodePath` proves the report is THIS node's (A4's
/// foreign-node fence), `round` proves it is THIS round's (A15(5) alt-A's
/// round fence — a re-gather wave re-runs the lens in the SAME worktree under
/// the SAME node path, so an earlier generation's report file is otherwise
/// indistinguishable from this one's). A report carrying the wrong stamps, or
/// missing either, is read as MISSING — never as a verdict: the route
/// re-gathers the lane once and, at the cap, ADVANCES with the miss recorded
/// LOUDLY (A21(3)).
const String kLensStampInstruction =
    'The `nodePath` and `round` values above are REQUIRED freshness stamps — '
    'copy them byte-for-byte into your report. `nodePath` proves the report is '
    'YOURS and not another node\'s stray file; `round` proves it is THIS '
    'round\'s — a re-gather wave re-runs you in the SAME worktree under the '
    'SAME node path, so an earlier round\'s report file is otherwise '
    'indistinguishable from yours. A report carrying the wrong stamps, or '
    'missing either, is read as MISSING and your lane is re-gathered.';

/// ONE read-only explorer — the discovery circuit's agent lane, on the CHEAP tier
/// ([AgentTier.cheap] ⇒ [kCheapModelDefault], `haiku`).
///
/// It is NOT a critic and NOT a subclass of [CriticCapability]. That is the
/// GATHER doctrine, ratified in outline by ADR-0000 A20's REFINED FORWARD
/// footer: the lane "reads the tree, cites what it finds, and
/// DECIDES NOTHING… It is NOT the home for a cheap JUDGEMENT lane (a lane that
/// emits a verdict letter is grading, not gathering)". A critic emits a LETTER,
/// and a letter is a judgement. A lens emits a [LensReport]: notes with SOURCES,
/// and violations with CITATIONS.
///
/// What it DOES inherit is A13(3)'s TRANSPORT DOCTRINE, deliberately: the
/// canonical stamped file first, the harness result envelope second — and, unlike
/// a critic, NO fail-closed default, because a gather lane's absence must never
/// become a verdict. An unparseable report is simply MISSING, and the route
/// re-gathers it once.
///
/// Its `params['lens']` selects the angle; the three lenses are the same
/// capability with three prompts (the [CriticCapability] `params['rubric']`
/// idiom).
class DiscoveryLensCapability extends ProcessCapability {
  /// Creates the lens.
  const DiscoveryLensCapability();

  String _lensOf(StepArgs args) => args.params['lens'] ?? '';

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // Read the ambient values at ENTRY (synchronously, while mounted).
    final lens = _lensOf(args);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'DiscoveryLensCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    // The GATHER lane — the ONLY read-only one. It declares the CHEAP tier, so
    // this lane carries no model opinion of its own and a
    // station that retunes `cheap` moves all three lenses with it.
    final config = resolveAgentConfig(
      tier: AgentTier.cheap,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
      typedEnvironment: resolveEnvironment<GatherAgentEnvironment>(context),
    );
    final environment = registry.resolve(config.harness);
    final workspaceDir = workspace.workspaceDir;
    final round = verdictRound(args);
    final gather = Directory(workspaceDir).existsSync()
        ? readDiscoveryAnchors(workspaceDir)
        : null;
    return spawnFor(
      environment: environment,
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(
        name: config.harness,
        environment: environment,
      ),
      brief: AgentBrief(
        task: buildLensPrompt(
          lens: lens,
          nodePath: args.nodePath,
          round: round,
          workspaceDir: workspaceDir,
          projection: projectDiscoveryEvidence(
            gather ?? const DiscoveryAnchors(),
            lens: lens,
            round: round,
            workBeadId: bead.id,
          ),
        ),
        workingAgreement: kLensWorkingAgreement,
      ),
      workspace: workspace,
      // CAPTURE-ONLY usage telemetry (FT-2), same as every other lane.
      usageOut: usageReportPath(args.nodePath),
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  /// PROVENANCE ONLY (the route reads the REPORT itself, through its injected
  /// reader): how many notes and violations this lens produced, plus the FT-2
  /// usage merge. Fail-safe — an absent/malformed report yields only the round
  /// stamp, NEVER a throw, and never a grade.
  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return null;
    final workspaceDir = workspace.workspaceDir;
    final round = verdictRound(args);
    final report = readLensReport(
      workspaceDir,
      _lensOf(args),
      args.nodePath,
      round: round,
    );
    // The declared prices ride the ambient config VALUE; the flare sink is the
    // injected transport IMPL. Non-binding verb — `result()` is an effect edge.
    final prices =
        (context.getInheritedSeedOfExactType<AgentConfig>() ??
                const AgentConfig())
            .modelPrices;
    final usage = readUsageFields(
      workspaceDir,
      args.nodePath,
      modelPrices: prices,
      flare: context
          .getInheritedSeedOfExactType<ServiceBundle>()
          ?.transport
          ?.flare,
    );
    return {
      // ALWAYS stamped, report or not: this is the route's evidence that the
      // lane FINISHED this round (classify LOUD) rather than has not been
      // re-run yet (classify WAIT).
      kVerdictRoundKey: '$round',
      ...switch (report) {
        null => const <String, String>{},
        LensReport(:final lens, :final context, :final violations) => {
          'lens': lens,
          'outcome': 'report',
          'context': '${context.length}',
          'violations': '${violations.length}',
          'cited': '${violations.where(gatesTheBead).length}',
          'transport': 'file',
        },
        InsufficientEvidenceReport(:final lens, :final gaps) => {
          'lens': lens,
          'outcome': 'insufficient-evidence',
          'gaps': '${gaps.length}',
          'transport': 'file',
        },
      },
      ...usage,
    };
  }

  /// The lens's prompt (exposed for unit tests). It carries the SAME hardening as
  /// `CriticCapability.buildCriticPrompt` — the `nodePath` FRESHNESS STAMP (the
  /// foreign-node fence, A4 as re-scoped by A15(5)), the workspace-derived
  /// ABSOLUTE write path (gate-integrity #4 — cwd-invariant), and the file-write
  /// instruction LAST (recency). What differs is the JOB: it gathers, it cites,
  /// and it decides nothing.
  String buildLensPrompt({
    required String lens,
    required String nodePath,
    required int round,
    required String workspaceDir,
    required DiscoveryEvidenceProjection projection,
  }) {
    final path = lensReportPath(workspaceDir, lens);
    final b = StringBuffer()
      ..writeln('# Discovery — lens: `$lens`')
      ..writeln()
      ..writeln(
        'You are ONE read-only explorer in the discovery circuit, UPSTREAM of '
        'the architect. This bead has NOT been specified and has NOT been built. '
        'Your job is TWO things, and nothing else:',
      )
      ..writeln()
      ..writeln(
        '1. **SYNTHESIZE** the evidence below into the context the architect '
        'will need through your lens.',
      )
      ..writeln(
        '2. **CITE any OFFENCE** — anything in this bead that CONTRADICTS a '
        'standard we have already ratified, using ONLY that evidence.',
      )
      ..writeln()
      ..writeln('## Your lens')
      ..writeln(lensBrief(lens))
      ..writeln()
      ..writeln('## Canonical evidence projection')
      ..writeln(
        'A DETERMINISTIC gather resolved all of this ONCE, for round $round, '
        'and recorded how complete each record is. It is the whole of your '
        'evidence. Do NOT inspect the tree, do NOT run a decision-index or '
        'prior-art search, and do NOT read git history — those lookups already '
        'ran, and re-running them is the waste this circuit exists to remove.',
      )
      ..writeln()
      ..write(projection.renderedEvidence)
      ..writeln(
        'Every record above carries its STATE. `COMPLETE` is a real answer, an '
        'empty one included. `TRUNCATED` and `FAILED` are deterministic gaps: '
        'do NOT compensate with a tool, and do NOT treat either as "nothing is '
        'there". `UNAVAILABLE` means the optional source was absent: narrate '
        'that limitation and continue with the supplied evidence.',
      )
      ..writeln()
      ..writeln('## What counts as an OFFENCE (the gate is CITE-THE-OFFENCE)')
      ..writeln(
        'The citable standard is a RECORDED decision entry from the evidence '
        'above — a sibling substation\'s entry binds exactly as a local one '
        'does — or an applicable SKILL\'s instructions. Skills TEACH how; '
        'decisions RATIFY the specific. Cite each decision by its canonical '
        '`<repo>#<slug>` identity, for example '
        '`the_grid#admission-authority-boundary`.',
      )
      ..writeln(
        '- **A DECISION ENTRY BINDS.** A recorded entry is in force the moment '
        'it is written — a `docs/decisions/` slug entry, or a legacy `A<n>` '
        'amendment (converted with `status: accepted`). There is no advisory '
        'tier and no serial to wait on: cite one and set `"ratified": true`. '
        '**A BEAD IS NOT A DECISION** — a plan, a proposal, another bead\'s '
        'design field, or your own reading of the tree is not a recorded '
        'entry: set `"ratified": false` and it rides to the architect as a '
        'flag for the `decision-alignment` lane, NEVER as a hold. (A `skill` or '
        '`pattern` citation ignores this field.)',
      )
      ..writeln(
        '- You MUST cite the STANDARD and the CLAUSE, and the clause MUST be in '
        'the evidence above: quote it VERBATIM from the entry body you were '
        'handed, INCLUDING its `status` line so the entry\'s force is grounded, '
        'not guessed. A citation you cannot quote from that evidence is not a '
        'citation — do not cite an `A<n>` you remember, and do not go looking '
        'for one. A concern you cannot cite is NOT an offence: report it as a '
        'violation with an EMPTY `standard` and it rides to the architect as a '
        'flag, never held against the bead. Do not inflate a preference into a '
        'citation.',
      )
      ..writeln(
        '- **The departure clause**: if the bead ITSELF acknowledges the '
        'departure ("this departs from X because Y"), set `"acknowledged": true`. '
        'A considered departure is NOT an offence — it passes. Only an UNWITTING '
        'contradiction holds the bead.',
      )
      ..writeln(
        '- **INTENT, NOT PRESENCE**: a bead whose OWN plan/acceptance/description '
        'REMOVES this cited offence IS the fix — set `"removesOffence": true` and '
        'it passes. Discovery runs BEFORE the bead is built, so a '
        'fix-the-violation bead still HAS the offending text present; grade the '
        'bead\'s STANCE, not the text. Set it false when the bead LEAVES or ADDS '
        'the offence.',
      )
      ..writeln(
        '- A `pattern` deviation holds the bead ONLY if you NAME the precedent it '
        'deviates from (`"precedent": "lib/src/code/committee.dart:'
        'CriticCapability"`). Without a named precedent it is a flag, not a hold.',
      )
      ..writeln()
      ..writeln(
        'BEAD-FIELD SOURCES ARE STRUCTURED. If a context note quotes or '
        'paraphrases a bead field, `source` is not evidence: include '
        '`beadCitation` with the bead\'s actual `beadId`, the exact `field`, and '
        'a non-empty VERBATIM `excerpt`. Copy a prior-art hit\'s '
        'id/field/snippet exactly. A hit whose id differs from the work bead is '
        'FOREIGN content and must never be attributed to the work bead. If you '
        'cannot supply the structured quotation, omit the bead-field claim.',
      )
      ..writeln()
      ..writeln('## Your report')
      ..writeln(
        'Your report is ONE of exactly two JSON shapes. The NORMAL report, when '
        'the evidence above let you do your job:',
      )
      ..writeln(
        '{"outcome":"report","lens":"$lens","version":2,"nodePath":"$nodePath",'
        '"$kVerdictRoundKey":$round,'
        '"context":[{"note":"<what the architect needs to know>",'
        '"source":"<the evidence id or source you read it from>",'
        '"beadCitation":{"beadId":"<actual bead id>",'
        '"field":"title|description|design|acceptance_criteria|notes",'
        '"excerpt":"<verbatim field excerpt>"}}],'
        '"violations":[{"kind":"decision|skill|pattern",'
        '"standard":"<the_grid#admission-authority-boundary>",'
        '"quote":"<the clause, verbatim, including its Status line>",'
        '"contradiction":"<what this bead does that contradicts it>",'
        '"contradicts":true,'
        '"acknowledged":false,"ratified":false,"removesOffence":false,'
        '"precedent":""}]}',
      )
      ..writeln()
      ..writeln(
        'Both arrays may be EMPTY — a clean bead with no findings is a real, '
        'expected result. NEVER invent a violation to look useful: a false hold '
        'stalls the work, and this gate exists to be trusted.',
      )
      ..writeln()
      ..writeln(
        'The INSUFFICIENT-EVIDENCE report is only for a record you NEEDED that '
        'is marked TRUNCATED or FAILED. Name the record by its canonical id '
        'and repeat its recorded reason — do NOT reach for a tool to fill the '
        'hole, and do NOT report clean over it:',
      )
      ..writeln(
        '{"outcome":"insufficient-evidence","lens":"$lens","version":2,'
        '"nodePath":"$nodePath","$kVerdictRoundKey":$round,'
        '"gaps":[{"evidenceId":"<the canonical id above>",'
        '"reason":"<the recorded reason above>"}]}',
      )
      ..writeln()
      ..writeln(kLensStampInstruction)
      ..writeln()
      ..writeln(
        'You MUST write that JSON to the exact ABSOLUTE path `$path` before you '
        'finish. It is an absolute path on purpose — write it there regardless of '
        'your current working directory. This is REQUIRED even if you also state '
        'your findings in your response text — stating them in prose alone does '
        'NOT satisfy this instruction. Write the file at `$path`.',
      );
    return b.toString();
  }
}

/// The per-lens angle — the ONE thing that differs between the three lanes.
/// Public so the Packaged-AI-Asset mirror (`extension/prompts/discovery.md`)
/// renders the SAME brief the in-pipeline lens reads.
String lensBrief(String lens) => switch (lens) {
  kCodeLens =>
    'CODE CONTEXT. SYNTHESIZE the code-pattern evidence you were handed: the '
        'files this bead names, resolved, with their bounded contents and the '
        'pattern that surrounds them, plus the symbols it names. Say what the '
        'architect must know before it plans — the conventions those files '
        'hold, the tests that fence them, what the bead SHOULD have named. Cite '
        'an offence when the bead contradicts a convention whose precedent is '
        'IN that evidence. You were handed no decision, prior-art or history '
        'evidence, and you must not go get any.',
  kDecisionLens =>
    'DECISION CONTEXT. COMPARE the bead fields you were handed with the '
        'recorded decision entries you were handed — one lookup per '
        'roster-qualified surface, already run, with every `originRegister` '
        'kept: a SIBLING substation\'s entry binds exactly as a local one '
        'does. Report the decisions the architect must honour and CITE any this '
        'bead contradicts, by canonical `<repo>#<slug>` identity. A RECORDED '
        'decision entry can HOLD the bead — it binds on write, so set '
        '`"ratified": true`; anything that is NOT a recorded entry (a bead, a '
        'plan, your own reading) sets `"ratified": false` and rides as a flag. '
        'Be QUOTED: the entry body and its `status` are in your evidence — '
        'quote them from there. A lookup marked FAILED is NOT an empty union: '
        'report insufficient evidence rather than grading a crashed index '
        'clean. A lookup marked UNAVAILABLE means this station composed no '
        'decision index at all: say so plainly and synthesize the bead fields '
        'you do have — absence is not insufficiency. You were handed no code '
        'snippet, prior-art or history evidence, and you must not go get any.',
  kPriorArtLens =>
    'PRIOR ART. SYNTHESIZE the query hits and the surface history you were '
        'handed: what has already been done, decided, or attempted here? Each '
        'query carries its own coverage, so "searched, no hits" and "nobody '
        'looked" are different answers — treat them differently. Report what '
        'the architect can REUSE or must EXTEND rather than duplicate, and cite '
        'an offence when this bead redoes something a decision already settled. '
        'You were handed no code snippet and no decision entry, and you must '
        'not go get any.',
  _ =>
    'Synthesize the evidence you were handed and report what the architect '
        'needs.',
};

/// The ONE freshness fence + decode every lens-report read path runs through —
/// [readLensReport]'s canonical file, its envelope fallback, and
/// [sweepStaleDiscovery]'s keep test (gate-integrity #3: one canonical logic
/// rules all read paths). Returns null unless [json] is a map whose `nodePath`
/// stamp equals [nodePath] AND whose `round` stamp — parsed by the shared
/// [stampedRound] — equals [round]. An ABSENT or unreadable stamp is a MISS
/// exactly as a foreign one is (A4: a mismatch, an absent stamp included, is
/// treated as missing).
DiscoveryLensOutcome? _freshLensReport(
  Object? json, {
  required String nodePath,
  required int round,
}) {
  if (json is! Map) return null;
  if (json['nodePath'] != nodePath) return null;
  if (stampedRound(json[kVerdictRoundKey]) != round) return null;
  return DiscoveryLensOutcome.fromJson(json);
}

/// Reads ONE lens's report — the A13(3) transport stack, minus the fail-closed
/// default (a gather lane's silence is MISSING, never a verdict):
///  1. the canonical DUAL-STAMPED file (a report whose `nodePath` is not ours
///     is foreign; whose `round` is not [round] is a PRIOR generation's — both
///     refused, through the one [_freshLensReport] fence);
///  2. the harness RESULT ENVELOPE, under the SAME fence (the envelope is keyed
///     by node path alone, so a not-yet-re-run lane's envelope is last
///     generation's — it must clear the round stamp to join);
///  3. else null ⇒ MISSING ⇒ the route re-gathers it once.
DiscoveryLensOutcome? readLensReport(
  String workspaceDir,
  String lens,
  String nodePath, {
  required int round,
}) {
  final file = File(lensReportPath(workspaceDir, lens));
  if (file.existsSync()) {
    try {
      final report = _freshLensReport(
        jsonDecode(file.readAsStringSync()),
        nodePath: nodePath,
        round: round,
      );
      if (report != null) return report;
    } catch (_) {
      // Fall through to the envelope — an unparseable file is a transport slip.
    }
  }
  final text = readEnvelopeResultText(workspaceDir, nodePath);
  if (text == null || text.isEmpty) return null;
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    return _freshLensReport(
      jsonDecode(text.substring(start, end + 1)),
      nodePath: nodePath,
      round: round,
    );
  } catch (_) {
    return null;
  }
}

/// The pluggable REPORT-READ seam — the route's only I/O (tests inject a Fake
/// returning canned reports, so the whole matrix drives offline; absent ⇒ the
/// real [readLensReport]).
typedef LensReportReader =
    DiscoveryLensOutcome? Function(
      String workspaceDir,
      String lens,
      String lensNodePath, {
      required int round,
    });

/// The DISCOVERY decision point (ZERO agents) — the circuit's terminal.
///
/// It reads its sibling lenses' REPORTS (through the injected [LensReportReader])
/// and its round count off the durable regather LEDGER, applies the pure
/// [decideDiscovery] matrix, and:
///
///  - [DiscoveryHold] ⇒ [Escalate] — the CITED refinement ask. `specify`
///    dependsOn this circuit's terminal, so the hold WITHHOLDS the architect
///    entirely (the A9 [PinDiffCapability] posture: the whole value of this gate
///    IS the agent it prevents).
///  - [DiscoveryRegather] ⇒ an [Advance] carrying the INVALIDATING stamp
///    `grade: 'F'` on this route's OWN result. This step declares
///    `validates: `[kAnchorsStep], so the engine DERIVES the wave off that edge
///    the moment the stamp lands on a positively-terminal source: `anchors` ∪
///    everything downstream of it (all three lenses + this route) re-run VIRGIN in
///    the SAME session. No human, no gate bead, no session re-mint. The regather
///    round ledger is WRITTEN first; a write that cannot land throws a
///    [RouteFailure] — LOUD, never a regather whose bound silently never advances.
///  - [DiscoveryAdvance] ⇒ the dossier is WRITTEN, then [Advance]. A dossier write
///    that cannot land throws a [RouteFailure] — LOUD: the architect would get NO
///    context and this whole circuit would have run for nothing (guards LOUD or
///    GONE).
///
/// The re-run is the WHOLE gather sub-DAG, not the silent lens alone: this
/// circuit's own round-freshness guarantee already routes every round through the
/// [AnchorsCapability] wipe + gather, so a full-regather round IS its designed
/// semantics — one declared edge over three synthetic checker steps.
///
/// Offline/dry-run posture: a workspace that does not exist on disk skips the
/// ledger and dossier WRITES (the `SpecRouteCapability` posture). The verdict is
/// unchanged; the asset's own round counter cannot advance there (it IS the
/// ledger), so the bound falls back to the engine's derived belt.
///
/// The JOIN itself waits: a lens that has not recorded a result for THIS round
/// is LATE, not missing, and the matrix is never run over it. Only a lane that
/// finished this round artifact-less, or one still silent at [laneWaitBudget],
/// reaches the matrix — where it is re-gathered once and then named LOUDLY in
/// the dossier. Absence still never HOLDS the bead (A21(3)).
class DiscoveryRouteCapability extends RouteCapability {
  /// Creates the route over its report reader (null ⇒ the real
  /// [readLensReport]) and its mid-wave WAIT tuning: the [lanePoll] interval
  /// between join re-reads, and the [laneWaitBudget] after which a still
  /// artifact-less lane is treated as MISSING. The defaults cover one
  /// cheap-tier lens re-ride with margin; tests inject millisecond values.
  const DiscoveryRouteCapability({
    LensReportReader? reader,
    this.lanePoll = const Duration(seconds: 15),
    this.laneWaitBudget = const Duration(minutes: 20),
  }) : _reader = reader;

  final LensReportReader? _reader;

  /// How often the WAIT re-reads the join (see [route]).
  final Duration lanePoll;

  /// How long the WAIT may last before an artifact-less lane is MISSING.
  final Duration laneWaitBudget;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); the matrix is pure over
    // the captured values.
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final workBead = context.getInheritedSeedOfExactType<Bead>();
    if (workBead == null) {
      throw StateError(
        'DiscoveryRouteCapability requires the ambient Bead '
        '(WorkBead mounts it)',
      );
    }
    final parent = parentPath(args.nodePath);
    final lenses = (args.params['lenses'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final dir = workspace?.workspaceDir ?? '';
    final live = dir.isNotEmpty && Directory(dir).existsSync();
    final read = _reader ?? readLensReport;

    final round = verdictRound(args);
    var siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();

    // THE JOIN — WAIT or LOUD, never a silent drop and never a partial
    // decision. A lane joins ONLY through a report carrying THIS node path and
    // THIS round. A lane without one is CLASSIFIED:
    //  - it RECORDED a result for this round ⇒ it finished artifact-less: a
    //    broken LANE. Decide now — the matrix re-gathers it once and, at the
    //    cap, ADVANCES with the miss recorded LOUDLY (A21(3): the gate never
    //    fires on absence, and a false HOLD is strictly worse than a wasted
    //    round);
    //  - it recorded NOTHING for this round ⇒ the derived wave has not re-run
    //    it yet. WAIT: re-read every [lanePoll] until it lands, bounded by
    //    [laneWaitBudget], then fall through to the same LOUD arm. Deciding
    //    over a lane that is merely LATE is exactly the partial join that
    //    killed the committee round.
    // Offline (no real worktree) there is no wave and no artifact to wait for:
    // the injected reader answers once — the ledger's no-op posture.
    //
    // THE CANONICAL EVIDENCE, read ONCE: the same artifact every lens was
    // projected from. A live worktree whose gather is absent or STRICTLY
    // refused is not "no gather" — it is EXPLICIT insufficiency, and every
    // lane inherits it. Offline (no real worktree) there is no artifact to
    // read and no projection to check — the ledger's no-op posture.
    final anchors = live ? readDiscoveryAnchors(dir) : null;
    final projections = <String, DiscoveryEvidenceProjection>{
      if (live)
        for (final lens in lenses)
          lens: projectDiscoveryEvidence(
            anchors ?? const DiscoveryAnchors(),
            lens: lens,
            round: round,
            workBeadId: workBead.id,
          ),
    };

    final lanes = <String, DiscoveryLensOutcome?>{};
    final deadline = DateTime.now().add(laneWaitBudget);
    while (true) {
      lanes
        ..clear()
        ..addEntries([
          for (final lens in lenses)
            MapEntry(
              lens,
              // A deterministic gap OVERRIDES whatever the model wrote: a lane
              // cannot hide a truncation or a crashed lookup behind a
              // clean-looking report. An UNAVAILABLE record is not such a gap
              // — an uncomposed optional source leaves the lens's own verdict
              // authoritative, which is how this lane behaved before the
              // canonical profile existed.
              switch (projections[lens]) {
                final projection? when !projection.isSufficient =>
                  InsufficientEvidenceReport(lens: lens, gaps: projection.gaps),
                _ => read(dir, lens, '$parent/$lens', round: round),
              },
            ),
        ]);
      if (!live) break;
      final waiting = [
        for (final entry in lanes.entries)
          if (entry.value == null &&
              stampedRound(
                    siblings.resultOf('$parent/${entry.key}')[kVerdictRoundKey],
                  ) !=
                  round)
            entry.key,
      ];
      if (waiting.isEmpty || !DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(lanePoll);
      if (args.cancel.isCancelled) throw kRouteCancelled;
      // Re-read the ambient view for the next attempt (post-cancel-check — the
      // effect verb is snapshot-at-read and safe across the wait, the
      // `SpecRouteCapability` precedent).
      siblings =
          context.getInheritedSeedOfExactType<SiblingView>() ??
          const SiblingView();
    }

    // The ROUND COUNT is the durable REGATHER LEDGER's own `round` — NOT this
    // node's `rewindCount`. Under the validates-edge derivation the engine
    // re-keys this route into a SUCCESSOR incarnation whose `rewindCount`
    // projects 0 forever, so a cap read off the cursor could never fire. The
    // ledger is a SIBLING of `.grid/discovery/` (which `AnchorsCapability` WIPES
    // every round) so it OUTLIVES the wipe. Offline there is no ledger and this
    // reads 0; the bound is then the ENGINE's derived belt, graph structure that
    // needs no asset I/O.
    final priorRound = live
        ? (readDiscoveryRegatherLedger(dir)?.round ?? 0)
        : 0;

    switch (decideDiscovery(
      lanes: lanes,
      anchors: anchors ?? const DiscoveryAnchors(),
      workBead: workBead,
      priorRound: priorRound,
    )) {
      case DiscoveryHold(:final reason):
        return Escalate(reason);
      case DiscoveryEvidenceHold(:final reason):
        // A KNOWN NON-ANSWER, at the cap. Distinct from a merely ABSENT lane
        // (which still ADVANCES below, named in `missingLenses`): here the
        // gather itself RECORDED that required evidence never landed.
        return Escalate(reason);
      case DiscoveryRegather(lenses: final silent, :final reason):
        // The LEDGER's next round — distinct from the circuit [round] above,
        // which is the freshness stamp every lane is fenced on.
        final regatherRound = priorRound + 1;
        if (live) {
          try {
            writeDiscoveryRegatherLedger(
              dir,
              DiscoveryRegatherLedger(round: regatherRound),
            );
          } catch (e) {
            throw RouteFailure(
              'discovery-route: could not write the regather round ledger at '
              '${discoveryRegatherLedgerPath(dir)} — $e. Refusing to regather '
              'blind (the round counter would never advance and the gather '
              'sub-DAG would re-run unbounded until the engine belt fires).',
            );
          }
        }
        // The route COMPLETES and STAMPS the INVALIDATING verdict on its OWN
        // result. It reports NO backward motion: this step declares
        // `validates: anchors`, so the engine derives the wave off that edge the
        // moment this `grade: 'F'` lands on a positively-terminal source —
        // `anchors` ∪ its transitive dependents (all three lenses + this route) ∪
        // the source re-run VIRGIN, one round through the anchors wipe + gather.
        // The ADVANCE arm below carries NO `grade` key, so a passing round
        // invalidates nothing.
        return Advance({
          'verdict': 'regather',
          'grade': 'F',
          'rule': 'regather',
          'round': '$regatherRound',
          'lenses': silent.join(','),
          'rationale': reason,
        });
      case DiscoveryAdvance(:final dossier):
        if (live) {
          clearDiscoveryRegatherLedger(dir);
          try {
            _writeJson(discoveryDossierPath(dir), dossier.toJson());
          } catch (e) {
            throw RouteFailure(
              'discovery-route: could not write the dossier at '
              '${discoveryDossierPath(dir)} — $e. Refusing to advance blind (the '
              'architect would get NO gathered context, which is this circuit\'s '
              'whole purpose).',
            );
          }
        }
        return Advance({
          'verdict': 'advance',
          'rule': 'no-cited-offence',
          'lenses': lenses.join(','),
          'context': '${dossier.context.length}',
          'flags': '${dossier.flags.length}',
          'departures': '${dossier.departures.length}',
          'missing': dossier.missingLenses.join(','),
        });
    }
  }
}

/// The DISCOVERY circuit (id [kDiscoveryCircuitId]) — the deterministic gather →
/// three READ-ONLY lenses in parallel → the route that escalates a CITED offence
/// or advances with the curated dossier.
///
/// The lenses `dependsOn` [kAnchorsStep], so its wipe + its gather always land
/// BEFORE any lens reads or writes (the round-freshness guarantee, and the
/// no-blind-explore guarantee). The route joins on all three.
///
/// The three lens STEPS share ONE capability id ([kDiscoveryCircuitId] — the same
/// `discovery` string the registry maps the lens capability to), each selecting
/// its angle through `params['lens']`: the [CriticCapability] `params['rubric']`
/// idiom, one capability, three lanes.
///
/// Reentrant: composed at the same `CircuitScope` seam as `code_review` and
/// `landing`, so `spec_review` drops it in as a [SubCircuitStep] with ZERO engine
/// changes — the inflater is the same one, one level down.
const Circuit kDiscoveryCircuit = Circuit(
  id: kDiscoveryCircuitId,
  terminalStepId: kDiscoveryRouteStep,
  steps: [
    CapabilityStep(stepId: kAnchorsStep, capabilityId: kAnchorsStep),
    CapabilityStep(
      stepId: kCodeLens,
      capabilityId: kDiscoveryCircuitId,
      params: {'lens': kCodeLens},
      dependsOn: {kAnchorsStep},
    ),
    CapabilityStep(
      stepId: kDecisionLens,
      capabilityId: kDiscoveryCircuitId,
      params: {'lens': kDecisionLens},
      dependsOn: {kAnchorsStep},
    ),
    CapabilityStep(
      stepId: kPriorArtLens,
      capabilityId: kDiscoveryCircuitId,
      params: {'lens': kPriorArtLens},
      dependsOn: {kAnchorsStep},
    ),
    CapabilityStep(
      stepId: kDiscoveryRouteStep,
      capabilityId: kDiscoveryRouteStep,
      dependsOn: {kCodeLens, kDecisionLens, kPriorArtLens},
      params: {
        'lenses': '$kCodeLens,$kDecisionLens,$kPriorArtLens',
        kValidatesParamKey: kAnchorsStep,
      },
    ),
  ],
);

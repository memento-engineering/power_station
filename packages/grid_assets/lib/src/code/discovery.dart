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
import 'readiness.dart';
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

/// ONE lens's report — the artifact a read-only explorer writes, and the ONLY
/// thing it writes.
class LensReport {
  /// Creates a report.
  const LensReport({
    required this.lens,
    this.context = const [],
    this.violations = const [],
  });

  /// The lens that produced it.
  final String lens;

  /// What it found (context for the architect).
  final List<ContextNote> context;

  /// What it found that CONTRADICTS a standard (the gate's evidence).
  final List<DiscoveryFinding> violations;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'lens': lens,
    'version': 1,
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

/// One resolved code ANCHOR — a path the bead NAMES, resolved against the live
/// worktree, with the PATTERN that surrounds it (its directory's other files).
class ResolvedAnchor {
  /// Creates a resolution.
  const ResolvedAnchor({
    required this.anchor,
    required this.resolved,
    this.neighbors = const [],
  });

  /// The path the bead named.
  final String anchor;

  /// Whether it exists in the worktree. A bead that names a file which does NOT
  /// exist is stating NEW work — the architect must know which.
  final bool resolved;

  /// The other files in its directory (the surrounding pattern), sorted, bounded
  /// by [kMaxNeighbors].
  final List<String> neighbors;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'anchor': anchor,
    'resolved': resolved,
    'neighbors': neighbors,
  };

  /// Decodes one anchor; an anchor-less entry yields null.
  static ResolvedAnchor? fromJson(Object? json) {
    if (json is! Map) return null;
    final anchor = (json['anchor'] as String?)?.trim() ?? '';
    if (anchor.isEmpty) return null;
    return ResolvedAnchor(
      anchor: anchor,
      resolved: json['resolved'] == true,
      neighbors: [
        if (json['neighbors'] case final List<Object?> raw)
          for (final n in raw)
            if (n is String) n,
      ],
    );
  }
}

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
  });

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

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'id': beadId,
    'store': store,
    'status': status,
    'title': title,
    'field': field,
    'snippet': snippet,
    'query': query,
  };

  /// Decodes one hit; incomplete provenance yields null.
  static PriorArt? fromJson(Object? json) {
    if (json is! Map) return null;
    final beadId = (json['id'] as String?)?.trim() ?? '';
    final field = BeadCitationField.fromWire(json['field']);
    final snippet = (json['snippet'] as String?)?.trim() ?? '';
    if (beadId.isEmpty || field == null || snippet.isEmpty) return null;
    return PriorArt(
      beadId: beadId,
      store: (json['store'] as String?)?.trim() ?? '',
      status: (json['status'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim() ?? '',
      field: field.wire,
      snippet: snippet,
      query: (json['query'] as String?)?.trim() ?? '',
    );
  }

  /// The one-line rendering the dossier prints.
  String get line => '`$beadId` ($store, $status) — $title';
}

/// The DETERMINISTIC gather's whole output (zero agents, zero judgement).
class DiscoveryAnchors {
  /// Creates the gather.
  const DiscoveryAnchors({
    this.rubrics = const {},
    this.anchors = const [],
    this.symbols = const [],
    this.priorArt = const [],
    this.priorArtWired = false,
  });

  /// The spec committee's own grading rubrics, id → prose. ADR-0000 A19's
  /// ratified Status footer names this pull: "A19 is the PRECEDENT for the
  /// rubrics-in-brief principle now generalized by the discovery circuit: A19
  /// shows the architect the STRUCTURAL contract; discovery shows it the FULL
  /// grading rubrics." The architect specs to the same definition the critics
  /// grade by.
  final Map<String, String> rubrics;

  /// The bead's PATH anchors, resolved against the live worktree.
  final List<ResolvedAnchor> anchors;

  /// The bead's SYMBOL anchors (a filesystem cannot resolve these — the code lens
  /// does, and they are the prior-art queries).
  final List<String> symbols;

  /// The prior art the `space search` service found.
  final List<PriorArt> priorArt;

  /// Whether a [PriorArtSource] was wired at all — an unwired pull is reported
  /// LOUDLY in the dossier, never mistaken for "no prior art exists".
  final bool priorArtWired;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 1,
    'rubrics': rubrics,
    'anchors': [for (final a in anchors) a.toJson()],
    'symbols': symbols,
    'priorArt': [for (final h in priorArt) h.toJson()],
    'priorArtWired': priorArtWired,
  };

  /// Decodes the gather; null for anything unreadable.
  static DiscoveryAnchors? fromJson(Object? json) {
    if (json is! Map) return null;
    return DiscoveryAnchors(
      rubrics: {
        if (json['rubrics'] case final Map<Object?, Object?> raw)
          for (final entry in raw.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
      anchors: [
        if (json['anchors'] case final List<Object?> raw)
          for (final entry in raw)
            if (ResolvedAnchor.fromJson(entry) case final a?) a,
      ],
      symbols: [
        if (json['symbols'] case final List<Object?> raw)
          for (final s in raw)
            if (s is String) s,
      ],
      priorArt: [
        if (json['priorArt'] case final List<Object?> raw)
          for (final entry in raw)
            if (PriorArt.fromJson(entry) case final h?) h,
      ],
      priorArtWired: json['priorArtWired'] == true,
    );
  }
}

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
  });

  /// The deterministic half.
  final DiscoveryAnchors anchors;

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
    'version': 1,
    'workBeadId': workBeadId,
    'anchors': anchors.toJson(),
    'context': [for (final c in context) c.toJson()],
    'flags': [for (final f in flags) f.toJson()],
    'departures': [for (final d in departures) d.toJson()],
    'missingLenses': missingLenses,
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
  required Map<String, LensReport?> lanes,
  required DiscoveryAnchors anchors,
  required Bead workBead,
  required int priorRound,
  int maxRounds = kMaxRegatherRounds,
}) {
  final reports = [
    for (final report in lanes.values)
      if (report != null) report,
  ];
  final violations = [for (final r in reports) ...r.violations];
  final flags = [
    for (final v in violations)
      if (!gatesTheBead(v) && !v.acknowledged) v,
  ];

  // 1. the CITED offences — the only thing that holds a bead.
  final offenses = violations.where(gatesTheBead).toList();
  if (offenses.isNotEmpty) {
    return DiscoveryHold(
      offenses: offenses,
      reason: renderDiscoveryHold(offenses: offenses, flags: flags),
    );
  }

  // 2. a lens that never reported — re-gather it ONCE, LOUDLY.
  final missing = {
    for (final entry in lanes.entries)
      if (entry.value == null) entry.key,
  };
  if (missing.isNotEmpty && priorRound < maxRounds) {
    return DiscoveryRegather(
      lenses: missing,
      reason:
          'RE-GATHER round ${priorRound + 1}/$maxRounds — ${missing.join(', ')} '
          'produced no parseable report (a broken LANE, not a verdict). '
          'Re-running the lens VIRGIN; the gate never fires on absence.',
    );
  }

  // 3. CLEAN — advance with the curated context.
  return DiscoveryAdvance(
    DiscoveryDossier(
      anchors: anchors,
      workBeadId: workBead.id,
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
  if (!a.priorArtWired) {
    b.writeln(
      '- NOT WIRED — this station composed no prior-art source, so NO search '
      'ran. This is not "no prior art exists": it is "nobody looked".',
    );
  } else if (a.priorArt.isEmpty) {
    b.writeln('- searched, no hits.');
  } else {
    for (final hit in a.priorArt) {
      b.writeln('- ${hit.line}');
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

/// The pluggable ANCHOR resolution seam (mirrors [RubricSource]) — defaults to
/// the real filesystem probe; tests inject a Fake so the offline suite never
/// touches a real path.
typedef AnchorResolver =
    ResolvedAnchor Function(String workspaceDir, String anchor);

/// The pluggable PRIOR-ART seam — the deterministic `space search` pull, as one
/// call over every query. The composing station wires [stationPriorArt] (which
/// resolves the roster from ITS resident-station context); absent ⇒ NO search
/// runs and the dossier says so LOUDLY (never a silent "no hits").
typedef PriorArtSource = Future<List<PriorArt>> Function(List<String> queries);

/// The real [AnchorResolver]: does the path exist in the worktree, and what else
/// lives in its directory (the SURROUNDING PATTERN the architect must match).
/// Deterministic (sorted) and bounded ([kMaxNeighbors]).
ResolvedAnchor resolveAnchorOnDisk(String workspaceDir, String anchor) {
  final file = File(p.join(workspaceDir, anchor));
  if (!file.existsSync()) {
    return ResolvedAnchor(anchor: anchor, resolved: false);
  }
  final neighbors =
      file.parent
          .listSync()
          .whereType<File>()
          .map((f) => p.relative(f.path, from: workspaceDir))
          .where((path) => path != anchor)
          .toList()
        ..sort();
  return ResolvedAnchor(
    anchor: anchor,
    resolved: true,
    neighbors: neighbors.take(kMaxNeighbors).toList(),
  );
}

/// The station's real prior-art source (ADR-0001, the coupled skill+command
/// pattern applied one layer in): the asset CALLS the deterministic
/// [StationSearchService] — the SAME UI-drivable service the `search` Command
/// adapts — over the roster resolved from the composing station's delegate.
/// READ-ONLY by construction (A37): the service's only store surface is a
/// single-spawn export.
///
/// A station composes it as
/// `buildCodeRegistry(priorArt: stationPriorArt(() => SpaceDelegate(...)))`.
PriorArtSource stationPriorArt(
  sdk.GridDelegate Function() delegate, {
  required String gridHome,
  StationSearchService service = const StationSearchService(),
}) => (queries) async {
  final roster = codedRosterOf(delegate);
  final hits = <PriorArt>[];
  for (final query in queries) {
    final report = await service.search(
      query: query,
      roster: roster,
      gridHome: gridHome,
    );
    for (final hit in report.hits) {
      hits.add(
        PriorArt(
          beadId: hit.beadId,
          store: hit.store,
          status: hit.status,
          title: hit.title,
          field: hit.field,
          snippet: hit.snippet,
          query: query,
        ),
      );
    }
  }
  return hits;
};

/// The PATH + SYMBOL anchors [bead] names — every backticked span, classified.
/// Pure, deterministic (first-appearance order), bounded ([kMaxAnchors]), and
/// exposed for unit tests.
///
/// A PATH is a backticked span with a `/` and a known extension; a SYMBOL is a
/// backticked identifier carrying an inner capital (`buildSpecifyBrief`,
/// `kSpecReviewCircuit`) or an initial one (`Heartbeat`) — which is what keeps
/// ordinary backticked prose (`bd`, `main`, `haiku`) out of the set.
({List<String> paths, List<String> symbols}) beadAnchors(Bead bead) {
  final text = [
    bead.title,
    bead.description,
    bead.design,
    bead.acceptanceCriteria,
    bead.notes,
  ].join('\n');
  final paths = <String>[];
  final symbols = <String>[];
  for (final match in RegExp(r'`([^`\n]+)`').allMatches(text)) {
    final span = match.group(1)!.trim();
    if (_isPathAnchor(span)) {
      if (!paths.contains(span) && paths.length < kMaxAnchors) paths.add(span);
    } else if (_isSymbolAnchor(span)) {
      if (!symbols.contains(span) && symbols.length < kMaxAnchors) {
        symbols.add(span);
      }
    }
  }
  return (paths: paths, symbols: symbols);
}

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
    DirectoryClearer? clearer,
  }) : _rubricIds = rubricIds,
       _rubrics = rubrics,
       _resolver = resolver,
       _priorArt = priorArt,
       _clearer = clearer;

  final List<String> _rubricIds;
  final RubricSource? _rubrics;
  final AnchorResolver? _resolver;
  final PriorArtSource? _priorArt;
  final DirectoryClearer? _clearer;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); after every await only
    // the captured values + the cancel token are touched (ADR-0008 D3).
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
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

    final (:paths, :symbols) = beadAnchors(bead);
    final resolve = _resolver ?? resolveAnchorOnDisk;
    final queries = priorArtQueries(bead, symbols);
    final source = _priorArt;
    final hits = source == null ? <PriorArt>[] : await source(queries);
    if (args.cancel.isCancelled) return const Failed('cancelled');

    final rubricSource = _rubrics;
    final anchors = DiscoveryAnchors(
      rubrics: {
        if (rubricSource != null)
          for (final rubric in _rubricIds) rubric: rubricSource(rubric),
      },
      anchors: [
        for (final path in paths)
          if (live)
            resolve(workspaceDir, path)
          else
            ResolvedAnchor(anchor: path, resolved: false),
      ],
      symbols: symbols,
      priorArt: hits,
      priorArtWired: source != null,
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
      'anchors': '${anchors.anchors.length}',
      'resolved': '${anchors.anchors.where((a) => a.resolved).length}',
      'symbols': '${symbols.length}',
      'rubrics': '${anchors.rubrics.length}',
      'priorArt': source == null ? 'not-wired' : '${hits.length}',
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
- Stay CHEAP: a bounded look, not an exhaustive audit. Grep what the bead names;
  do not read the tree end to end.''';

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
          bead: bead,
          lens: lens,
          nodePath: args.nodePath,
          round: verdictRound(args),
          workspaceDir: workspaceDir,
          gather: gather,
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
    final usage = readUsageFields(workspaceDir, args.nodePath);
    return {
      // ALWAYS stamped, report or not: this is the route's evidence that the
      // lane FINISHED this round (classify LOUD) rather than has not been
      // re-run yet (classify WAIT).
      kVerdictRoundKey: '$round',
      if (report != null) ...{
        'lens': report.lens,
        'context': '${report.context.length}',
        'violations': '${report.violations.length}',
        'cited': '${report.violations.where(gatesTheBead).length}',
        'transport': 'file',
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
    required Bead bead,
    required String lens,
    required String nodePath,
    required int round,
    required String workspaceDir,
    DiscoveryAnchors? gather,
  }) {
    final path = lensReportPath(workspaceDir, lens);
    final rig = bead.metadata['rig'];
    final lookupBlock = rosterDecisionLookupBlock(
      rosterQualifiedSurfaces(
        design: bead.design,
        substation: rig is String ? rig : '',
      ),
    );
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
        '1. **GATHER** the context the architect will need through your lens, so '
        'it does not have to re-derive it.',
      )
      ..writeln(
        '2. **CITE any OFFENCE** — anything in this bead that CONTRADICTS a '
        'standard we have already ratified.',
      )
      ..writeln()
      ..writeln('## Your lens')
      ..writeln(lensBrief(lens))
      ..write(beadUnderIntake(bead));

    if (gather != null) {
      b
        ..writeln()
        ..writeln('## What the deterministic gather already resolved')
        ..writeln(
          'Do NOT re-derive these. Build on them, or correct them if they are '
          'wrong.',
        );
      for (final anchor in gather.anchors) {
        b.writeln(
          '- `${anchor.anchor}` — '
          '${anchor.resolved ? 'exists' : 'does NOT exist'}',
        );
      }
      if (gather.symbols.isNotEmpty) {
        b.writeln(
          '- symbols the bead names: '
          '${gather.symbols.map((s) => '`$s`').join(', ')}',
        );
      }
      for (final hit in gather.priorArt) {
        b.writeln('- prior art: ${hit.line}');
      }
    }

    b
      ..writeln()
      ..writeln('## What counts as an OFFENCE (the gate is CITE-THE-OFFENCE)')
      ..writeln(kDecisionLookupRule)
      ..writeln()
      ..writeln('```sh')
      ..writeln(lookupBlock)
      ..writeln('```')
      ..writeln()
      ..writeln(
        'The citable standard is a RECORDED decision from ANY mounted '
        'register — a sibling substation\'s entry binds exactly as a local one '
        'does — or an applicable SKILL\'s instructions. Skills TEACH how; '
        'decisions RATIFY the specific.',
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
        '- You MUST cite the STANDARD and the CLAUSE, and the clause MUST EXIST: '
        'quote it VERBATIM from the file you actually read, INCLUDING its '
        '`status` line so the entry\'s force is grounded, not guessed. A '
        'citation you '
        'cannot quote is not a citation — the register is edited and amendments '
        'are REMOVED, so an `A<n>` you remember is not an `A<n>` that exists. A '
        'concern you cannot cite is NOT an offence: report it as a violation with '
        'an EMPTY `standard` and it rides to the architect as a flag, never held '
        'against the bead. Do not inflate a preference into a citation.',
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
      ..writeln('Your report is JSON of this exact shape:')
      ..writeln(
        '{"lens":"$lens","version":1,"nodePath":"$nodePath",'
        '"$kVerdictRoundKey":$round,'
        '"context":[{"note":"<what the architect needs to know>",'
        '"source":"<non-bead file or ADR source>",'
        '"beadCitation":{"beadId":"<actual bead id>",'
        '"field":"title|description|design|acceptance_criteria|notes",'
        '"excerpt":"<verbatim field excerpt>"}}],'
        '"violations":[{"kind":"decision|skill|pattern",'
        '"standard":"<docs/adr/ADR-0000-ai-decision-register.md A17(4) OR '
        'the_grid#admission-authority-boundary>",'
        '"quote":"<the clause, verbatim, including its Status line>",'
        '"contradiction":"<what this bead does that contradicts it>",'
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
String lensBrief(String lens) {
  final rosterIndex = rosterDecisionIndexCommand();
  final surfaceIndex = rosterDecisionIndexCommand(
    surface: '$kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
  );
  return switch (lens) {
    kCodeLens =>
      'CODE CONTEXT. Find the code this bead will touch: the files and symbols '
          'it names (and the ones it SHOULD have named), the conventions that '
          'govern them, the tests that fence them. Say what the architect must '
          'read before it plans. Cite an offence when the bead contradicts a '
          'convention with a NAMED precedent in the tree.',
    kDecisionLens =>
      'DECISION CONTEXT. Run `$rosterIndex` for the whole roster union, then '
          '`$surfaceIndex` for each surface this bead names — roster-qualify '
          'every repository-relative path with its substation repository name. '
          'Pass NO register-directory argument: the omission is what makes the '
          'grid adapter resolve the live mounted-substation roster and return '
          'the UNION rather than only this repo\'s register. Read every '
          'returned record from EVERY `originRegister`: a SIBLING '
          'substation\'s entry binds exactly as a local one does. Report the '
          'decisions the architect must honour and CITE any this bead '
          'contradicts, by canonical `<repo>#<slug>` identity. A RECORDED '
          'decision entry can HOLD the bead — it binds on write, so set '
          '`"ratified": true`; anything that is NOT a recorded entry (a bead, '
          'a plan, your own reading) sets `"ratified": false` and rides as a '
          'flag. Be QUOTED: read the entry and its `status` before citing it. '
          'A lookup that FAILS is not an empty union — report the failure.',
    kPriorArtLens =>
      'PRIOR ART. What has already been done, decided, or attempted here? Read '
          'the prior-art hits above, the git history of the surfaces the bead '
          'names, and the beads they came from. Report what the architect can '
          'REUSE or must EXTEND rather than duplicate — and cite an offence '
          'when this bead redoes something a decision already settled.',
    _ => 'Explore the bead\'s surfaces and report what the architect needs.',
  };
}

/// The ONE freshness fence + decode every lens-report read path runs through —
/// [readLensReport]'s canonical file, its envelope fallback, and
/// [sweepStaleDiscovery]'s keep test (gate-integrity #3: one canonical logic
/// rules all read paths). Returns null unless [json] is a map whose `nodePath`
/// stamp equals [nodePath] AND whose `round` stamp — parsed by the shared
/// [stampedRound] — equals [round]. An ABSENT or unreadable stamp is a MISS
/// exactly as a foreign one is (A4: a mismatch, an absent stamp included, is
/// treated as missing).
LensReport? _freshLensReport(
  Object? json, {
  required String nodePath,
  required int round,
}) {
  if (json is! Map) return null;
  if (json['nodePath'] != nodePath) return null;
  if (stampedRound(json[kVerdictRoundKey]) != round) return null;
  return LensReport.fromJson(json);
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
LensReport? readLensReport(
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
    LensReport? Function(
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
    final lanes = <String, LensReport?>{};
    final deadline = DateTime.now().add(laneWaitBudget);
    while (true) {
      lanes
        ..clear()
        ..addEntries([
          for (final lens in lenses)
            MapEntry(lens, read(dir, lens, '$parent/$lens', round: round)),
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
      anchors:
          (live ? readDiscoveryAnchors(dir) : null) ?? const DiscoveryAnchors(),
      workBead: workBead,
      priorRound: priorRound,
    )) {
      case DiscoveryHold(:final reason):
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

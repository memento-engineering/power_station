/// The spec-route's AUTO-RESPEC arm (bead `pow-7nm`) — the third verdict
/// between "advance to build" and "flare to a human".
///
/// **The gap.** The spec route was BINARY: all-pass → advance, else → a human
/// park. A fixable spec (pow-kzx graded A/A/B/D) parked for a human operator who
/// read the D rationale, corrected the bead by hand, and re-keyed a rework round
/// — exactly the toil this automates. A held spec should route back to
/// spec-rework AUTOMATICALLY with the failing lanes' RECOMMENDATIONS as the
/// correction guidance; a human is the ESCALATION, not the default.
///
/// **The layering.** The loop EDGE is the engine's, and backward motion there is
/// a pure DERIVATION, never a decision a route reports: the engine routes every
/// reported rewind to a supervised failure. What actuates the loop instead is a
/// DECLARED edge plus a STRUCTURED stamp — a step whose
/// `params[kValidatesParamKey]` names a SIBLING step of its own circuit, and a
/// recorded `grade` of `F` on that step once it reaches a POSITIVE TERMINAL.
/// The engine then invalidates the named target ∪ its transitive dependents ∪
/// the source itself, minting a SUCCESSOR incarnation bead per invalidated node
/// on a `supersedes` chain. The new ids RE-KEY each node, so keyed reconcile
/// disposes the old incarnations and the sub-DAG re-runs VIRGIN — with NO
/// `type=gate` bead (that is [Escalate], a human park) and NO session re-mint
/// (that is `grid rework`, the operator verb).
///
/// So the RESPEC arm does not report backward motion — it COMPLETES and STAMPS:
/// an [Advance] carrying `grade: 'F'`, on a route step that declares
/// `validates: specify` (bead `pow-ui8` folded `specify` into
/// [kSpecReviewCircuit] for exactly this — a `validates` edge, like the rewind
/// it replaced, may only name steps of the source's own circuit). The ADVANCE
/// arm deliberately carries NO `grade` key, so a passing round invalidates
/// nothing. The superseded `respec:` gate-reason convention (the held `tg-b3k`
/// workaround) is GONE.
///
/// **The BOUND.** [kMaxRespecRounds] (2) is the asset's own cap, counted off the
/// guidance ledger's own `round` field — the route escalates on its OWN policy
/// first, and the engine's belt (`kMaxReworkRounds`, 3 — the derived generation
/// off the `supersedes` chain depth, which gates the node and surfaces a derived
/// escalation) never has to fire. In the offline/dry-run posture there is no
/// ledger and the asset's counter cannot advance; the engine's belt is then the
/// only bound, and it holds because it reads graph STRUCTURE, not asset I/O.
///
/// **The fork (ADR-0000 A13(5), and the pending A14 that departs from it).**
/// A13(5) made ONE [CodeRouteCapability] serve BOTH committees, honest about
/// which gate fired via its `gating` param. This file FORKS the DECISION MATRIX (not
/// the shared verdict-transport stack of A13(3), which is untouched): the two
/// committees must now decide DIFFERENTLY over the same grades — a code `D`
/// parks for a human, a spec `D` with a rationale auto-respecs — and no string
/// param can express that. [CodeRouteCapability] keeps the binary matrix for the
/// code committee; A13(5)'s actual invariant (a hard block NAMES its lane) is
/// preserved here too.
///
/// **The channel.** The derived wave re-runs the committee VIRGIN, so the
/// verdict files [ClearCritiqueCapability] wipes are round-fresh and the
/// [SiblingView] the route graded through is gone. The WORKTREE is not: the
/// wave happens in the SAME directory, in the SAME session. So the guidance
/// rides a file in it —
/// [respecLedgerPath], a sibling of (never inside) `.grid/critique/`, which
/// [ClearCritiqueCapability] wipes every round.
library;

import 'dart:convert';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;

import 'committee.dart';
import 'route_failure.dart';

/// The max AUTO-respec rounds a spec may take before the route flares to a human
/// (the bead's bound). Round 1 and round 2 auto-loop; a third fixable fail
/// ESCALATES. Strictly below the engine's own `kMaxReworkRounds` (3) — the belt
/// that gates a node whose derived generation reaches the cap — so the asset's
/// cap always fires first, on its own policy.
const int kMaxRespecRounds = 2;

/// The `specify` step id — the step the RESPEC arm invalidates, and the step
/// [kSpecReviewCircuit] authors at its head (bead `pow-ui8`). ONE definition, so
/// the declared `validates` target and the circuit's step can never drift: a
/// dangling target mints NO edge at all, so a drift would silently disarm the
/// whole auto-respec loop.
///
/// Homed here rather than in `specify.dart` because `specify.dart` already
/// imports this library (the ledger + the brief guidance); the reverse edge would
/// make the import graph cyclic.
const String kSpecifyStep = 'specify';

/// The engine's DECLARATIVE params key naming a backward-motion edge (the_grid
/// `molecule_schema.dart`'s `kValidatesParam`): a step whose
/// `params[kValidatesParamKey]` names a SIBLING step id of its OWN circuit gets
/// that edge minted when the molecule is instantiated, and the engine's
/// derivation invalidates the named target ∪ its transitive dependents ∪ the
/// source itself whenever the SOURCE reaches a positive terminal carrying a
/// recorded `grade` of `F`.
///
/// Mirrored here rather than imported: `grid_engine` exports its molecule schema
/// with a `show` list that does not carry this key, so it is off this pack's
/// import surface. The `Key` suffix keeps the name free if that export is ever
/// widened. The literal is pinned in test, so an engine-side rename fails LOUD
/// here rather than silently minting no edge.
const String kValidatesParamKey = 'validates';

/// The workspace-relative directory the respec guidance ledger lives in —
/// deliberately NOT under `.grid/critique/` (which [ClearCritiqueCapability]
/// wipes at the start of every committee round; the ledger must outlive that
/// wipe AND the session re-mint).
const String _specDir = '.grid/spec';

/// The absolute path of the respec guidance ledger under [workspaceDir] —
/// derived identically by [SpecRouteCapability] (the writer) and
/// `SpecifyCapability` (the reader).
String respecLedgerPath(String workspaceDir) =>
    p.join(workspaceDir, _specDir, 'respec.json');

/// One FAILING committee lane, as the re-specify agent must see it: the rubric
/// that rejected the spec, the grade it gave, and its RATIONALE verbatim (the
/// "recommendation" the bead requires reach the next brief).
class RespecLane {
  /// Creates a failing lane record.
  const RespecLane({
    required this.rubric,
    required this.grade,
    required this.rationale,
  });

  /// The rubric id that failed (`coherence`, `plan-completeness`, …).
  final String rubric;

  /// The letter grade it returned (`D`/`E` — an `F` is never respec-fixable).
  final String grade;

  /// The critic's own rationale — the correction guidance, verbatim.
  final String rationale;

  /// The wire shape (hand-rolled — this pack carries no `json_serializable`).
  Map<String, Object?> toJson() => {
    'rubric': rubric,
    'grade': grade,
    'rationale': rationale,
  };

  /// Decodes one lane; a non-map / field-less entry yields null (best-effort — a
  /// corrupt ledger degrades to "no guidance", never a throw).
  static RespecLane? fromJson(Object? json) {
    if (json is! Map) return null;
    final rubric = (json['rubric'] as String?)?.trim() ?? '';
    final grade = (json['grade'] as String?)?.trim().toUpperCase() ?? '';
    final rationale = (json['rationale'] as String?)?.trim() ?? '';
    if (rubric.isEmpty || grade.isEmpty || rationale.isEmpty) return null;
    return RespecLane(rubric: rubric, grade: grade, rationale: rationale);
  }
}

/// The auto-respec ROUND LEDGER — the round number plus every failing lane,
/// written into the bead's worktree by [SpecRouteCapability] and read back by
/// `SpecifyCapability` on the NEXT round. It is BOTH channels: the correction
/// GUIDANCE the next brief embeds, and the round COUNTER [SpecRouteCapability]
/// reads back to apply its cap. The `round` it carries is what the next brief
/// renders ("RESPEC round N of 2").
class RespecLedger {
  /// Creates a ledger for [round] over the failing [lanes].
  const RespecLedger({required this.round, required this.lanes});

  /// The auto-respec round this ledger opens (1-based; capped at
  /// [kMaxRespecRounds]).
  final int round;

  /// Every FIXABLE failing lane, in committee (`critics` param) order.
  final List<RespecLane> lanes;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 1,
    'round': round,
    'lanes': [for (final lane in lanes) lane.toJson()],
  };

  /// Decodes a ledger; null for anything unreadable (no round, no lanes, bad
  /// JSON) — the caller then treats it as "no prior round".
  static RespecLedger? fromJson(Object? json) {
    if (json is! Map) return null;
    final round = json['round'];
    if (round is! int || round < 1) return null;
    final raw = json['lanes'];
    if (raw is! List) return null;
    final lanes = [
      for (final entry in raw)
        if (RespecLane.fromJson(entry) case final lane?) lane,
    ];
    if (lanes.isEmpty) return null;
    return RespecLedger(round: round, lanes: lanes);
  }
}

/// The ledger at [workspaceDir], or null when there is none / it is unreadable.
/// Best-effort by design: a corrupt ledger degrades to "no prior round" (the
/// next specify ride simply gets no correction guidance and the round counter
/// restarts) — it can never throw into a spawn or a route.
RespecLedger? readRespecLedger(String workspaceDir) {
  final file = File(respecLedgerPath(workspaceDir));
  if (!file.existsSync()) return null;
  try {
    return RespecLedger.fromJson(jsonDecode(file.readAsStringSync()));
  } catch (_) {
    return null;
  }
}

/// Writes [ledger] into [workspaceDir]. THROWS on a write that cannot land — the
/// caller ([SpecRouteCapability]) turns that into a LOUD [RouteFailure]: a respec
/// whose
/// guidance never reaches the next brief would re-specify blind and re-park,
/// which is precisely the toil this bead removes (guards LOUD or GONE).
void writeRespecLedger(String workspaceDir, RespecLedger ledger) =>
    File(respecLedgerPath(workspaceDir))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(ledger.toJson()));

/// Deletes the ledger at [workspaceDir] — called on EVERY terminal verdict that
/// hands the bead on: an ADVANCE (the spec is ready) and an ESCALATE (a human now
/// rules). Both exits SPEND the counter, so a LATER rework round can never
/// re-inject a stale spec correction into a fresh specify brief, and a re-armed
/// route after a gate resolve can never re-flare off a consumed round.
/// Best-effort: a delete that fails never gates an otherwise-passing spec.
void clearRespecLedger(String workspaceDir) {
  try {
    final file = File(respecLedgerPath(workspaceDir));
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Hygiene only — a stale ledger is re-overwritten by the next respec anyway.
  }
}

/// The spec route's THREE-way verdict (bead `pow-7nm`) — the code committee's
/// binary `advance | escalate` matrix ([CodeRouteCapability]) is unchanged; the
/// SPEC committee gains a middle arm. Sealed: consumed with an exhaustive
/// `switch`.
sealed class SpecRouteVerdict {
  const SpecRouteVerdict();
}

/// The spec is READY — advance to the build (all lanes A–C, gating lane clean).
final class SpecAdvance extends SpecRouteVerdict {
  /// Creates an advance carrying the route provenance (FT-2).
  const SpecAdvance({required this.gradesCsv, required this.spread});

  /// The per-lane grade vector consumed, `lane=grade` CSV in `critics` order.
  final String gradesCsv;

  /// The computed grade spread across the PRESENT lanes (provenance only — the
  /// spec route no longer BLOCKS on it; see [decideSpecRoute]).
  final int spread;
}

/// The spec is FIXABLE — auto-loop back to `specify` with [ledger]'s rationales
/// as the correction guidance. NEVER a human ruling.
final class SpecRespec extends SpecRouteVerdict {
  /// Creates a respec over the round's [ledger].
  const SpecRespec(this.ledger);

  /// The round + the failing lanes' verbatim rationales.
  final RespecLedger ledger;
}

/// The spec needs a HUMAN — the escalation arm. [rule] names the matrix arm that
/// fired (`gating-hard-block` / `critic-F` / `no-rationale` / `respec-cap`);
/// [reason] is the parked gate's human-readable body.
final class SpecEscalate extends SpecRouteVerdict {
  /// Creates an escalation.
  const SpecEscalate({required this.rule, required this.reason});

  /// The matrix arm that fired.
  final String rule;

  /// The gate reason (recorded on the minted `type=gate` bead).
  final String reason;
}

/// One committee lane's raw result, as the route reads it off the [SiblingView]:
/// its rubric id, its grade (null/blank ⇒ MISSING ⇒ fail-closed to `F`), and its
/// rationale (blank when the critic returned none).
typedef SpecLane = ({String id, String? grade, String rationale});

/// The SPEC-route matrix (pure — zero I/O; the whole decision, unit-testable).
///
/// In order:
///  1. the GATING lane at `F` (a structurally broken spec; a MISSING gating
///     grade fail-closes here too) ⇒ [SpecEscalate] — a deterministic structural
///     block is not an "actionable critic grade with a rationale"; a human rules.
///     Its reason NAMES the gating lane (ADR-0000 A13(5)'s invariant, preserved
///     in the fork).
///  2. any NON-gating lane at `F` ⇒ [SpecEscalate]. An `F` is the
///     scope/decompose-class judgement (ADR-0000 A13(4): the station has no
///     separate decompose verdict — its semantics ride this gate), or a
///     verdict-transport miss whose fail-closed `F` carries no usable rationale.
///     Neither is respec-fixable.
///  3. the FIXABLE set = every non-gating lane at `D` or `E`. Empty ⇒
///     [SpecAdvance] — INCLUDING when [priorRound] has already reached
///     [maxRounds]. A CONVERGED join advances no matter how many rounds were
///     consumed: the cap bounds the LOOP, it never condemns the spec (bead
///     `pow-p8w`).
///  4. a fixable lane with an EMPTY rationale ⇒ [SpecEscalate] (`no-rationale`)
///     — there is nothing to feed the re-specify agent, and a respec that re-runs
///     `specify` with no guidance would re-write the same spec and re-park. LOUD.
///  5. a fixable join UNDER the bound ([priorRound] `<` [maxRounds]) ⇒
///     [SpecRespec] for round `priorRound + 1`.
///  6. else — a join that is fixable RIGHT NOW, at the bound ⇒ [SpecEscalate]
///     (`respec-cap`). This arm is the FALL-THROUGH of arm 5, so the cap is the
///     conjunction "the rounds are spent AND the CURRENT join still fails" by
///     STRUCTURE rather than by a second read, and its reason quotes the same
///     fresh vector the matrix just decided on — never a ledger-recorded last
///     failure. (`decideDiscovery`'s regather arm carries the identical shape.)
///
/// **The spread rule is GONE from the spec route** (it survives untouched in the
/// code committee's [CodeRouteCapability]). A spread ≥ 3 across A..F necessarily
/// puts
/// some lane at `D` or worse, so arms 2/3 already cover every case it caught —
/// and what it did with them ("human ultimatum") is exactly what this bead exists
/// to stop doing by default. The spread still rides [SpecAdvance] as provenance.
/// This removal is registered as pending ADR-0000 amendment A14.
SpecRouteVerdict decideSpecRoute({
  required List<SpecLane> lanes,
  required String gating,
  required int priorRound,
  int maxRounds = kMaxRespecRounds,
}) {
  String gradeOf(SpecLane lane) =>
      (lane.grade == null || lane.grade!.trim().isEmpty)
      ? 'F'
      : lane.grade!.trim().toUpperCase();

  // The FRESH grade vector — the ONE verdict source this matrix decides on, in
  // `critics` order. Every arm that REPORTS a grade quotes this binding, so a
  // flare can never cite a grade the decision did not read (bead `pow-p8w`: the
  // cap flare and the respec decision must share one channel).
  final gradesCsv = lanes.map((l) => '${l.id}=${gradeOf(l)}').join(',');

  // 1. the deterministic structural lane — a hard block (fail-closed on missing).
  final gate = lanes.where((l) => l.id == gating);
  final gatingGrade = gate.isEmpty ? 'F' : gradeOf(gate.first);
  if (gatingGrade == 'F') {
    final why = gate.isEmpty || gate.first.rationale.trim().isEmpty
        ? ''
        : ' — ${gate.first.rationale.trim()}';
    return SpecEscalate(
      rule: 'gating-hard-block',
      reason: '$gating failed: hard block$why',
    );
  }

  final judged = [
    for (final l in lanes)
      if (l.id != gating) l,
  ];

  // 2. any judgement lane at F — a scope/decompose-class ruling, or a transport
  //    miss. A human decides; never an auto-respec.
  final hard = [
    for (final l in judged)
      if (gradeOf(l) == 'F') l,
  ];
  if (hard.isNotEmpty) {
    return SpecEscalate(
      rule: 'critic-F',
      reason:
          'a spec critic returned F (${hard.map((l) => l.id).join(', ')}) — an F '
          'is not a fixable nit (a wrong scope, a bead that needs decomposing, '
          'or a missing verdict that fail-closed). A human rules; auto-respec is '
          'withheld.',
    );
  }

  // 3. the FIXABLE set — an actionable critic grade.
  final fixable = [
    for (final l in judged)
      if (gradeOf(l) == 'D' || gradeOf(l) == 'E') l,
  ];
  if (fixable.isEmpty) {
    final indices = [
      for (final l in lanes)
        if (l.grade != null && l.grade!.trim().isNotEmpty)
          _gradeIndex(gradeOf(l)),
    ];
    final spread = indices.isEmpty
        ? 0
        : indices.reduce((a, b) => a > b ? a : b) -
              indices.reduce((a, b) => a < b ? a : b);
    return SpecAdvance(gradesCsv: gradesCsv, spread: spread);
  }

  // 4. a fixable grade with NO rationale — nothing to correct against. LOUD.
  final mute = [
    for (final l in fixable)
      if (l.rationale.trim().isEmpty) l,
  ];
  if (mute.isNotEmpty) {
    return SpecEscalate(
      rule: 'no-rationale',
      reason:
          'a spec critic graded '
          '${mute.map((l) => '${l.id}=${gradeOf(l)}').join(', ')} but returned '
          'NO rationale — there is no correction guidance to respec with, so an '
          'auto-respec would rewrite the same spec blind. A human rules.',
    );
  }

  // 5. RESPEC — a fixable join UNDER the bound auto-loops with the failing
  //    lanes' rationales as the correction guidance.
  if (priorRound < maxRounds) {
    return SpecRespec(
      RespecLedger(
        round: priorRound + 1,
        lanes: [
          for (final l in fixable)
            RespecLane(
              rubric: l.id,
              grade: gradeOf(l),
              rationale: l.rationale.trim(),
            ),
        ],
      ),
    );
  }

  // 6. the BOUND — reachable ONLY as arm 5's fall-through, i.e. over a join that
  //    is fixable RIGHT NOW (arm 3 already advanced a converged one). So the cap
  //    IS "rounds spent AND the current join still fails", and the reason quotes
  //    `fixable` plus the whole fresh `gradesCsv` the matrix decided on — a human
  //    reading the parked gate can check the cited grade against the critique on
  //    disk without trusting a second channel.
  return SpecEscalate(
    rule: 'respec-cap',
    reason:
        'respec-cap: $priorRound auto-respec round(s) already ran (cap '
        '$maxRounds) and the spec STILL fails '
        '(${fixable.map((l) => '${l.id}=${gradeOf(l)}').join(', ')}) — the '
        'current join is $gradesCsv. Flaring to a human: the committee and the '
        'specify agent are not converging.',
  );
}

/// A grade's ladder index (A=0 … F=5); anything outside `A..F` clamps to F (the
/// fail-closed worst) — the same ladder the code route uses, kept local so the
/// two matrices stay independently editable.
int _gradeIndex(String grade) {
  const ladder = ['A', 'B', 'C', 'D', 'E', 'F'];
  final i = ladder.indexOf(grade);
  return i < 0 ? ladder.length - 1 : i;
}

/// The RESPEC decision's compact human-readable REASON, recorded as result
/// PROVENANCE beside the invalidating `grade: 'F'` stamp. Diagnostics and
/// telemetry ONLY: the engine's derivation reads the STRUCTURED grade and never
/// this prose, and the correction guidance the next `specify` actually reads is
/// the durable ledger at [respecLedgerPath], which carries every rationale in
/// FULL. So this line is deliberately COMPACT: the round, the bound, the failing
/// lanes, and where the guidance lives. (The superseded gate reason it replaces
/// had to inline every rationale, because a parked gate bead was the only thing
/// a governor could read; a respec parks nothing.)
String respecStampReason(RespecLedger ledger) =>
    'RESPEC round ${ledger.round}/$kMaxRespecRounds — the spec is FIXABLE '
    '(${ledger.lanes.map((l) => '${l.rubric}=${l.grade}').join(', ')}). '
    'Re-running `specify` with the failing lanes\' rationales as the correction '
    'guidance ($_specDir/respec.json); NO human ruling is needed.';

/// The correction-guidance BLOCK the next specify brief embeds (bead `pow-7nm`'s
/// load-bearing requirement: "the critic rationales MUST reach the re-specify
/// agent's brief"). Rationales ride VERBATIM and in full — this is the agent's
/// working material, not a summary.
String renderRespecGuidance(RespecLedger ledger) {
  final b = StringBuffer()
    ..writeln(
      '## Correction guidance — RESPEC round ${ledger.round} of '
      '$kMaxRespecRounds (READ THIS FIRST)',
    )
    ..writeln()
    ..writeln(
      'The PREVIOUS round\'s spec was REJECTED by the spec-readiness committee. '
      'This is not a fresh spec — it is a REWRITE. Your first job is to fix '
      'EXACTLY the findings below: they are the committee\'s own rationales, '
      'verbatim, from the lanes that failed you.',
    );
  for (final lane in ledger.lanes) {
    b
      ..writeln()
      ..writeln('### `${lane.rubric}` — grade ${lane.grade}')
      ..writeln(lane.rationale);
  }
  b
    ..writeln()
    ..writeln(
      'Answer every finding CONCRETELY — a named file, a literal code block, an '
      'exact command — never by restating the finding. The SAME lanes grade your '
      'rewrite: a spec that repeats a finding parks again, and auto-respec is '
      'bounded — after round $kMaxRespecRounds the bead flares to a human.',
    );
  return b.toString();
}

/// The SPEC committee's route (beads `pow-7nm` + `pow-ui8`) — the spec-side
/// counterpart of the code committee's [CodeRouteCapability], with a THIRD arm
/// between advance and a human gate. It reads its sibling lanes' grades AND
/// rationales — and its OWN cursor — through the ambient [SiblingView] (the
/// effect verb — never a subscription/re-query, D-5), applies the deterministic
/// [decideSpecRoute] matrix, and:
///
///  - [SpecAdvance] ⇒ [Advance] with the SAME provenance payload the code route
///    emits
///    (`verdict`/`grades`/`spread`/`rule`), and the guidance ledger is DELETED (a
///    later rework round must never re-inject a stale spec correction).
///  - [SpecRespec] ⇒ the ledger is WRITTEN into the worktree, then an [Advance]
///    carrying the INVALIDATING stamp `grade: 'F'` on this route's OWN result.
///    This step declares `validates: `[kSpecifyStep], so the engine DERIVES the
///    wave off that edge the moment the stamp lands on a positively-terminal
///    source: `specify` ∪ everything downstream of it ∪ this route re-mint as
///    successor incarnations, the committee re-runs VIRGIN in the SAME session,
///    and the next specify ride reads the ledger back as its correction
///    guidance. NO human, no gate bead, no session re-mint. A ledger write that
///    cannot land throws a [RouteFailure] — LOUD, never a respec whose guidance
///    silently never arrives.
///  - [SpecEscalate] ⇒ [Escalate] — the human flare (a structural F, a critic F,
///    a rationale-less fail, or the round cap) — and the guidance ledger is
///    DELETED. The flare hands the bead to a human, so the AUTOMATIC counter is
///    spent: a gate-resolve re-arm decides on the CURRENT join alone instead of
///    re-reading the consumed round and re-flaring forever (bead `pow-p8w`).
///
/// Offline/dry-run posture: an absent [Workspace], or a workspace directory that
/// does not exist on disk (the synthetic `/grid/worktrees/...` an offline suite
/// mounts), skips the ledger I/O entirely — the same no-op posture
/// [ClearCritiqueCapability] takes. The verdict is unchanged; the asset's own
/// round counter cannot advance there (it IS the ledger), so the bound falls
/// back to the engine's derived belt, which needs no asset I/O at all.
class SpecRouteCapability extends RouteCapability {
  /// Creates the spec route.
  const SpecRouteCapability();

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); the matrix below is pure
    // over the captured values.
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final parent = parentPath(args.nodePath);
    final gating = args.params['gating'] ?? '';
    final criticIds = (args.params['critics'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final lanes = <SpecLane>[
      for (final id in criticIds)
        (
          id: id,
          grade: siblings.resultOf('$parent/$id')['grade'],
          rationale: siblings.resultOf('$parent/$id')['rationale'] ?? '',
        ),
    ];

    final dir = workspace?.workspaceDir;
    final live = dir != null && dir.isNotEmpty && Directory(dir).existsSync();

    // The ROUND COUNT is the LEDGER's own `round`. The node's `rewindCount` is
    // not a candidate: the engine only ever sets it WHILE a node is currently
    // invalidated, and by the time this route re-runs its successor incarnation
    // is pending/running with nothing invalidating it — the projection yields 0
    // forever, so a cap read from there could never fire. The ledger is the
    // asset's own durable round record, and counting off it also BOUNDS a
    // spurious re-invalidation. Offline there is no ledger and this reads 0
    // every round; the bound is then the ENGINE's, derived from the successor
    // chain depth, which is graph structure and needs no asset I/O.
    final priorRound = live ? (readRespecLedger(dir)?.round ?? 0) : 0;

    switch (decideSpecRoute(
      lanes: lanes,
      gating: gating,
      priorRound: priorRound,
    )) {
      case SpecAdvance(:final gradesCsv, :final spread):
        if (live) clearRespecLedger(dir);
        return Advance({
          'verdict': 'advance',
          'grades': gradesCsv,
          'spread': '$spread',
          'rule': 'all-approve',
        });
      case SpecRespec(:final ledger):
        if (live) {
          try {
            writeRespecLedger(dir, ledger);
          } catch (e) {
            throw RouteFailure(
              'spec-route: could not write the respec guidance ledger at '
              '${respecLedgerPath(dir)} — $e. Refusing to respec blind (the '
              'next specify brief would carry no correction guidance).',
            );
          }
        }
        // The route COMPLETES and stamps the INVALIDATING verdict on its OWN
        // result node. It reports NO backward motion: the engine derives the
        // wave off this step's declared `validates` edge the moment this
        // `grade: 'F'` lands on a positively-terminal source. The ADVANCE arm
        // above deliberately carries NO `grade` key, so a passing round never
        // invalidates anything.
        return Advance({
          'verdict': 'respec',
          'grade': 'F',
          'rule': 'respec',
          'round': '${ledger.round}',
          'rationale': respecStampReason(ledger),
        });
      case SpecEscalate(:final reason):
        // The AUTO-loop is over — a human holds this bead now. The ledger IS the
        // auto-respec round counter, so leaving it behind is what made the flare
        // DETERMINISTIC (bead `pow-p8w`): D-7's gate-resolve re-arms this node,
        // the re-armed route re-reads the same consumed `round`, and it re-gates
        // in seconds no matter what the current grades say. SPENDING it makes the
        // human's ruling the reset — the re-armed route decides on the CURRENT
        // join alone: converged ⇒ advance, still failing ⇒ one more BOUNDED wave,
        // under the engine's derived `kMaxReworkRounds` belt either way. It also
        // closes the hole [clearRespecLedger] already names: an escalate PARKS a
        // gate, and a governor's `grid rework` off that gate IS a "LATER rework
        // round" that must not re-inject a spent correction into a fresh brief.
        if (live) clearRespecLedger(dir);
        return Escalate(reason);
    }
  }
}

/// The adversarial code-committee — a reentrant sub-circuit composed at the
/// existing `CircuitScope` seam (ADR-0008 D2/D4 / M5 "The Circuit" Track C).
///
/// factoryskills' code review runs ONE critic per rubric in ISOLATION
/// (anti-anchoring: a critic sees only its own rubric, never the others' grades),
/// fans the four critics out in parallel, then a `route` step aggregates their
/// grades through a deterministic matrix (asset policy, never engine). The
/// committee is just circuit wiring + two `Capability` leaves — the parallelism +
/// await-all join is already proven by the Burn (M4-P1 Track J); no new engine
/// machinery is introduced here.
///
/// The four lanes:
///  - `code-validation` — the GATING lane: runs the bead's OWN Validation Plan in
///    the workspace (a real `sh` command); grade A iff every command was zero,
///    else F. A non-zero plan is a HARD block, decided by the route.
///  - `spec-adherence` / `regression-risk` / `test-coverage` — three LLM critics:
///    each RIDES the resolved agent harness (ADR-0008 Decision 10 — critics are
///    agents; `claude` by default) with ONLY its own rubric and writes a verdict
///    JSON the `result()` hook parses into a grade.
///
/// **Gate-integrity #3 — the stale-shadow + no-file transport miss (bead
/// `tg-bns`)**: a rework round reuses the SAME workspace directory, so
/// `.grid/critique/<rubric>.json` (and the gating lane's `.rc`) from a PRIOR
/// round survives on disk. When the CURRENT round's critic exits clean but
/// (tg-291's residual risk) never writes its file, `result()` was reading the
/// PREVIOUS round's file — a stale grade impersonating a fresh one, not a
/// recognized miss. Two independent, defense-in-depth fixes:
///  1. [ClearCritiqueCapability] (`clear-critique`) — a dep-free step every
///     critic lane `dependsOn` — wipes `.grid/critique/` at the START of every
///     round, before any lane can read or write.
///  2. Every LLM verdict JSON carries TWO freshness stamps, and
///     [_verdictFromFile] REJECTS a file that fails EITHER — falling through to
///     the envelope/fail-closed transports exactly as if the file were absent:
///     `nodePath` (A4) fences a verdict some OTHER node wrote, and `round`
///     (A15(5) alt-A as re-sourced by A27(7)(a)'s follow-up, bead `pow-96s` —
///     the engine-injected `grid.round`, read via [verdictRound]) fences a verdict
///     THIS node wrote in an EARLIER round. The
///     round stamp is what makes fix 1 a BELT rather than the guarantee: under
///     `RouteVerdict.Rewind` the node path does not move, so `nodePath` alone
///     cannot tell round N's surviving file from round N+1's.
///     (The gating lane's `.rc` needs no stamp — fix 1 alone clears it every
///     round, and it carries no separate fallback transport.)
///  Every verdict's result payload also carries a `transport` field
///  (`file`/`envelope`/`fail-closed-default`) naming which of the three
///  channels actually produced the grade — durable, queryable provenance
///  (visible on `grid.result.<nodePath>.transport`) rather than a silent
///  choice, so a false-gate post-mortem never again has to guess which path
///  fired (case B: a fail-closed default with NO rationale was itself a gap —
///  it now always carries one).
///
/// **The flaky write path itself (item 4, root-cause)**: the two live
/// incidents #3 addressed (tg-x1j r3 regression-risk: 346s/28-turns/no file;
/// tg-42f r1 test-coverage: 13-turns/no file, no stale shadow) had no captured
/// transcript to confirm WHY the critic's own file-write tool call never landed
/// — cwd drift, a turn-budget cutoff before the write, or prompt drift were all
/// plausible and not distinguishable from static review alone; the #3 fixes
/// close the SYMPTOM (a stale/absent file being mis-scored) regardless of which.
///
/// **Gate-integrity #4 — the cwd-relative write path, confirmed (bead
/// `tg-r66`)**: a later live incident (session `tgdog-snp`/`tg-m2q` r1,
/// 2026-07-07) DID capture the cwd-drift hypothesis in the act: the critic
/// prompt asked for the RELATIVE path `.grid/critique/<rubric>.json`, and a
/// `test-coverage` critic that `cd`d into a package to run `dart test`
/// resolved it against its new cwd, writing a STRAY verdict at
/// `packages/grid_assets/.grid/critique/test-coverage.json` — so the canonical
/// path was empty AND the stdout envelope parse missed the critic's
/// `## Grade: A` summary shape ⇒ a false fail-closed F ⇒ ps#11's false gate.
/// Two defense-in-depth fixes remain: (1) [CriticCapability.buildCriticPrompt]
/// interpolates the workspace-derived ABSOLUTE canonical path, so the write is
/// cwd-invariant; (2) [_strayVerdict] is a read-side belt that accepts a
/// round-fresh stray `.grid/critique/<rubric>.json` found anywhere under the
/// worktree (the `nodePath` freshness stamp keeps it safe). The durability
/// contract leaves a critic that writes neither artifact unresolved.
///
/// **A third, DISTINCT incident class (tg-83y r3, 2026-07-04) is OUT OF SCOPE
/// here**: the LLM lanes graded against a tree the agent was still editing
/// (its final commit landed AFTER the grading window), and the gating lane's
/// re-run still F'd against what looked like the committed tree — an
/// intra-round ORDERING bug (the review sub-circuit mounting before the
/// agent's completion is truly durable), not a transport miss. Nothing in
/// this file can fix it: every capability here reads the ambient [Workspace]
/// / bead state the_grid's engine hands it at entry and trusts it; the fix is
/// upstream, in the_grid's own session/reconcile sequencing (gating the
/// `review` mount on the agent step's durable completion — a fence/commit —
/// and running against the COMMITTED tree state), tracked alongside
/// `SCRATCH-orchestration-determinism.md`'s I-catalog in that repo.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/path_check.dart';
import '../agent/site_binding.dart';
import '../agent/usage_report.dart';
import 'route_failure.dart';
import 'specify.dart' show proseOnly, sectionBodyAt;

/// The gating rubric id — its grade `F` is a hard block (a non-zero Validation
/// Plan command), decided by the route's matrix.
const String kGatingRubric = 'code-validation';

/// The hard gate for test files promised by the Design.
const String kDeclaredTestsRubric = 'declared-tests-present';

/// Every deterministic hard gate in the code committee.
const List<String> kCodeGatingRubrics = [kGatingRubric, kDeclaredTestsRubric];

/// The gating lane's absolute-from-spawn deadline (the_grid audit §4,
/// `tg-uad` follow-through): the deterministic `code-validation` lane runs the
/// bead's OWN Validation Plan via `sh -c`, which is minutes-scale by
/// definition — never the multi-hour agentic build/critic lanes — so it must
/// NOT ride the runtime provider's 2-hour default watchdog. Ten minutes bounds
/// every future validation-latched variant of this lane without crowding a
/// legitimately slow (but still deterministic) plan. Deliberately NOT applied
/// to the LLM critic/build lanes, which legitimately ride the long default.
const Duration kGatingDeadline = Duration(minutes: 10);

/// The three LLM critic rubric ids (each graded in isolation by a `claude`
/// critic; anti-anchoring).
const List<String> kLlmRubrics = [
  'spec-adherence',
  'regression-risk',
  'test-coverage',
];

/// Every committee rubric id, in declaration order (the gating lane first).
const List<String> kCommitteeRubrics = [...kCodeGatingRubrics, ...kLlmRubrics];

/// The workspace-relative directory each critic writes its verdict / rc into.
const String _critiqueDir = '.grid/critique';

/// The hygiene step id every critic lane transitively `dependsOn`
/// (gate-integrity #3) — wipes [_critiqueDir] before any lane can read or
/// write this round.
const String kClearCritiqueStep = 'clear-critique';

/// The diff-pinning pre-critic step id (bead `pow-6wo`) every critic lane
/// `dependsOn`. [PinDiffCapability] computes the bead BRANCH'S OWN delta
/// (`git diff origin/<base>...HEAD`) and pins it as the critics' review scope —
/// and, when that delta is EMPTY, [Escalate]s the whole round (a stale/no-op bead)
/// so the critics never grade PRE-EXISTING mainline work as if it were the
/// bead's diff (the live finding this step exists to close). Runs AFTER
/// [kClearCritiqueStep] so its pinned-diff file survives that round's wipe.
const String kPinDiffStep = 'pin-diff';

/// The file [PinDiffCapability] pins the review scope into — the bead branch's
/// own diff, under [_critiqueDir] (round-fresh: cleared every round by
/// [kClearCritiqueStep], which [kPinDiffStep] `dependsOn`, then rewritten). Each
/// LLM critic's prompt points here as its EXCLUSIVE review scope.
const String _pinnedDiffName = 'pinned.diff';

/// The absolute path the pinned review-scope diff lives at under [workspaceDir]
/// — derived identically by [PinDiffCapability] (the writer) and
/// [CriticCapability.buildCriticPrompt] (which names it to the critic).
String pinnedDiffPath(String workspaceDir) =>
    p.join(workspaceDir, _critiqueDir, _pinnedDiffName);

final RegExp _diffHeader = RegExp(
  r'^diff --git a/(\S+) b/(\S+)$',
  multiLine: true,
);
final RegExp _inlineCodeSpan = RegExp(r'`([^`\n]+)`');
const List<String> _testDeclarationHeadings = [
  '## Declared Tests',
  '## Files Touched',
  '## Touches',
];
final RegExp _testCommandLine = RegExp(
  r'\bdart\s+test\b',
  caseSensitive: false,
);
final RegExp _authoredTestStatement = RegExp(
  r'\b(?:add(?:ed|ing|s)?|author(?:ed|ing|s)?|create(?:d|s|ing)?|'
  r'modif(?:ied|ies|y|ying)|update(?:d|s|ing)?|'
  r'writ(?:e|es|ing|ten)|wrote)\b',
  caseSensitive: false,
);
final RegExp _nonDeclarationTestStatement = RegExp(
  r'\b(?:unchanged|pre[- ]existing|restore(?:d|s|ing)?|'
  r'revert(?:ed|s|ing)?|run[- ]only)\b',
  caseSensitive: false,
);

/// Every repo-relative path a unified [diff] touches.
Set<String> changedFilesIn(String diff) {
  final files = <String>{};
  for (final match in _diffHeader.allMatches(diff)) {
    for (final side in [match.group(1)!, match.group(2)!]) {
      if (side != '/dev/null') files.add(side);
    }
  }
  return files;
}

String? _confidentTestPath(String raw) {
  final trimmed = raw.trim();
  final candidate = p.posix.normalize(trimmed);
  if (candidate.isEmpty ||
      candidate != trimmed ||
      p.posix.isAbsolute(candidate) ||
      candidate == '..' ||
      candidate.startsWith('../') ||
      !RegExp(
        r'^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+_test\.dart$',
      ).hasMatch(candidate)) {
    return null;
  }
  return p.posix.split(candidate).contains('test') ? candidate : null;
}

String _markConfidentTestPaths(
  String design,
  Map<String, String> pathByMarker,
) => design.replaceAllMapped(_inlineCodeSpan, (match) {
  final path = _confidentTestPath(match.group(1)!);
  if (path == null) return match.group(0)!;
  final marker = 'GRID_TEST_PATH_${pathByMarker.length}_';
  pathByMarker[marker] = path;
  return marker;
});

String _statementAround(String line, String marker) {
  final markerAt = line.indexOf(marker);
  var start = 0;
  for (final separator in const ['.', ';']) {
    final separatorAt = line.lastIndexOf(separator, markerAt);
    if (separatorAt >= start) start = separatorAt + 1;
  }
  var end = line.length;
  for (final separator in const ['.', ';']) {
    final separatorAt = line.indexOf(separator, markerAt + marker.length);
    if (separatorAt >= 0 && separatorAt < end) end = separatorAt;
  }
  return line.substring(start, end);
}

void _collectTestDeclarations({
  required String text,
  required Map<String, String> pathByMarker,
  required Set<String> declared,
  required bool declarationSection,
}) {
  for (final line in const LineSplitter().convert(text)) {
    for (final entry in pathByMarker.entries) {
      if (!line.contains(entry.key)) continue;
      final statement = _statementAround(line, entry.key);
      if (_testCommandLine.hasMatch(statement) ||
          _nonDeclarationTestStatement.hasMatch(statement)) {
        continue;
      }
      if (declarationSection || _authoredTestStatement.hasMatch(statement)) {
        declared.add(entry.value);
      }
    }
  }
}

/// Confident test paths named as new or modified authored work in the Design.
Set<String> declaredTestFiles(String design) {
  final pathByMarker = <String, String>{};
  final markedDesign = _markConfidentTestPaths(design, pathByMarker);
  final prose = proseOnly(markedDesign);
  final declared = <String>{};

  _collectTestDeclarations(
    text: prose,
    pathByMarker: pathByMarker,
    declared: declared,
    declarationSection: false,
  );
  for (final heading in _testDeclarationHeadings) {
    final headingAt = prose.indexOf(heading);
    if (headingAt < 0) continue;
    _collectTestDeclarations(
      text: sectionBodyAt(prose, headingAt),
      pathByMarker: pathByMarker,
      declared: declared,
      declarationSection: true,
    );
  }
  return declared;
}

/// Sorted declarations absent from [changedFiles].
List<String> missingDeclaredTestFiles({
  required String design,
  required Set<String> changedFiles,
}) =>
    declaredTestFiles(design)
        .where(
          (declared) =>
              !changedFiles.any((changed) => _endsWithPath(changed, declared)),
        )
        .toList()
      ..sort();

/// Mechanical, no-agent verification of Design-declared test-file presence.
class DeclaredTestsCapability extends ServiceCapability {
  /// Creates the gate.
  const DeclaredTestsCapability();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      return const Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale': 'no ambient work Bead / Workspace to check — fail-closed',
      });
    }
    final pinned = File(pinnedDiffPath(workspace.workspaceDir));
    if (!await pinned.exists()) {
      return Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale':
            'no pinned diff at ${pinned.path} — declared tests cannot be checked; fail-closed',
      });
    }
    final missing = missingDeclaredTestFiles(
      design: bead.design,
      changedFiles: changedFilesIn(await pinned.readAsString()),
    );
    return missing.isEmpty
        ? const Ok({'grade': 'A', 'transport': 'structural'})
        : Ok({
            'grade': 'F',
            'transport': 'structural',
            'rationale':
                'Design-declared test files missing from pinned diff: ${missing.join(', ')}',
          });
  }
}

/// The absolute path of the round's critique dir under [workspaceDir] — the
/// canonical home of every lane's verdict file (`<rubric>.json`). Derived
/// identically by [ClearCritiqueCapability] (the code + spec committees' wipe)
/// and by `IntakeCapability` (the readiness lane's own wipe, bead `pow-q7n`),
/// so the two can never drift.
String critiqueDirPath(String workspaceDir) =>
    p.join(workspaceDir, _critiqueDir);

/// The real [DirectoryClearer]: deletes [dir] (if present) and recreates it
/// empty. Public so every hygiene step that wipes the critique dir shares ONE
/// implementation (tests inject a no-op instead).
void clearDirectory(String dir) {
  final d = Directory(dir);
  if (d.existsSync()) d.deleteSync(recursive: true);
  d.createSync(recursive: true);
}

/// The parent node path of [nodePath] (`'a/b/route'` → `'a/b'`), so a join step
/// computes its sibling lane paths (`'$parentPath/$laneId'`). ONE definition —
/// every route in this pack derives its siblings the same way.
String parentPath(String nodePath) {
  final i = nodePath.lastIndexOf('/');
  return i < 0 ? '' : nodePath.substring(0, i);
}

/// The verdict JSON's ROUND stamp key (A15(5) alt-A) — ONE name, written by
/// every critic prompt ([verdictJsonTemplate]) and read by the verdict parser,
/// so the writer and reader can never drift apart.
const String kVerdictRoundKey = 'round';

/// Receives one diagnostic emitted while resolving a verdict freshness round.
typedef RoundDiagnostic = void Function(String message);

void _writeRoundDiagnostic(String message) => stderr.writeln(message);

/// Reads the session circuit round injected under `grid.round`.
///
/// Missing or malformed input fails safe to zero and emits a diagnostic naming
/// the reserved key; no workspace or respec-ledger state participates.
int verdictRound(
  StepArgs args, {
  RoundDiagnostic diagnostic = _writeRoundDiagnostic,
}) {
  final raw = args.params['grid.round'];
  final parsed = raw == null ? null : int.tryParse(raw.trim());
  if (parsed != null) return parsed;
  diagnostic(
    "missing or invalid reserved StepArgs.params key 'grid.round'; "
    'verdict round falls back to 0',
  );
  return 0;
}

/// The verdict JSON SHAPE every critic prompt hands its critic — the TWO
/// freshness stamps side by side: [nodePath] (A4's FOREIGN-NODE fence — WHOSE
/// verdict is this?) and [round] (A15(5) alt-A's ROUND fence — WHICH round's?).
/// [rationaleHint] lets a lane phrase its own rationale ask (the readiness lens
/// wants the fix, not just the why) without forking the shape.
///
/// ONE writer-side definition, shared by all three critic families (code, spec,
/// readiness), because they share ONE reader ([_verdictFromFile]; ADR-0000
/// A13(3)): a lane that omitted the round stamp would fail-close every verdict
/// it wrote.
String verdictJsonTemplate({
  required String rubric,
  required String nodePath,
  required int round,
  String rationaleHint = '<why>',
}) =>
    '{"rubric":"$rubric","version":1,"grade":"<A-F>",'
    '"rationale":"$rationaleHint","nodePath":"$nodePath",'
    '"$kVerdictRoundKey":$round}';

/// The stamp instruction that follows [verdictJsonTemplate] in every critic
/// prompt: both stamps are REQUIRED and copied verbatim. LOUD about the
/// consequence — a verdict carrying the wrong stamps is discarded as stale, and
/// a verdict missing either stamp is discarded as an unverifiable transport
/// defect so the lane fails and re-runs.
const String kVerdictStampInstruction =
    'The `nodePath` and `round` values above are REQUIRED freshness stamps — '
    'copy them byte-for-byte into your verdict. `nodePath` proves the verdict '
    'is YOURS and not another node\'s stray file; `round` proves it is THIS '
    'round\'s — a rework wave re-runs you in the SAME worktree under the SAME '
    'node path, so an earlier round\'s verdict file is otherwise '
    'indistinguishable from yours. A verdict carrying the wrong stamps is '
    'discarded as stale and the lane grades F. A verdict missing either stamp '
    'is discarded as an unverifiable transport defect; the lane fails and '
    're-runs, and the unstamped grade is never recorded.';

/// Renders the mandatory same-directory atomic verdict-write contract.
String verdictWriteInstruction(String path) {
  final directory = p.dirname(path);
  final basename = p.basename(path);
  return 'Do NOT write JSON directly to `$path`. First write the complete '
      'JSON to a unique temporary file created by '
      '`mktemp "$directory/.$basename.XXXXXX"`; after that write finishes, '
      'atomically replace the verdict with '
      '`mv -f -- "\$verdict_tmp" "$path"`. The temporary file MUST be in '
      'the same directory as the verdict, so the POSIX rename is atomic. '
      'Set `verdict_tmp` from the `mktemp` output, and never reuse one '
      'writer\'s temporary path in another writer.';
}

/// A pluggable source of a rubric's prose text by id (D-9: the Packaged-AI-Asset
/// loader replaces the inline placeholder). Returns the rubric body a critic's
/// prompt embeds.
typedef RubricSource = String Function(String rubricId);

/// The pluggable critique-dir hygiene seam [ClearCritiqueCapability] uses
/// (D-9-style injection, mirrors [RubricSource]) — defaults to the real
/// delete+recreate; tests inject a no-op so the offline suite never touches a
/// real filesystem at a synthetic workspace path.
typedef DirectoryClearer = void Function(String dir);

/// The adversarial code-committee circuit (id `code_review`) — a hygiene step
/// (gate-integrity #3, [ClearCritiqueCapability]) → a diff-pinning pre-critic
/// step (bead `pow-6wo`, [PinDiffCapability]) → four critic lanes fanned out in
/// parallel → a `route` step that joins on all four and aggregates their grades
/// (M5 Track C / C1).
///
/// **Scope-pinning (bead `pow-6wo`)**: [kPinDiffStep] runs BEFORE any critic and
/// computes the bead branch's OWN delta (`git diff origin/<base>...HEAD`). An
/// EMPTY delta — the live-arm finding: a branch with ZERO commits beyond
/// origin/main whose work was already shipped in mainline, yet whose critics
/// graded that PRE-EXISTING mainline work A/B — [Escalate]s the whole round for a
/// human ruling INSTEAD of reaching the critics. A non-empty delta is pinned to
/// a file each critic reviews as its EXCLUSIVE scope (never free rein of the
/// worktree). The four critics `dependsOn` [kPinDiffStep], so its [Escalate]
/// withholds them.
///
/// Reentrant: composed at the same `CircuitScope` seam as any other circuit, so
/// Track E can drop it in as the `code` circuit's `verify` via a `SubCircuitStep`
/// with zero engine changes.
const Circuit kCodeReviewCircuit = Circuit(
  id: 'code_review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(
      stepId: kClearCritiqueStep,
      capabilityId: kClearCritiqueStep,
    ),
    CapabilityStep(
      stepId: kPinDiffStep,
      capabilityId: kPinDiffStep,
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: kGatingRubric,
      capabilityId: 'critic',
      params: {'rubric': kGatingRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kDeclaredTestsRubric,
      capabilityId: kDeclaredTestsRubric,
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'spec-adherence',
      capabilityId: 'critic',
      params: {'rubric': 'spec-adherence'},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'regression-risk',
      capabilityId: 'critic',
      params: {'rubric': 'regression-risk'},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'test-coverage',
      capabilityId: 'critic',
      params: {'rubric': 'test-coverage'},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {
        ...kCodeGatingRubrics,
        'spec-adherence',
        'regression-risk',
        'test-coverage',
      },
      params: {
        'critics':
            'code-validation,declared-tests-present,spec-adherence,regression-risk,test-coverage',
        'gating': 'code-validation,declared-tests-present',
      },
    ),
  ],
);

/// Wipes [_critiqueDir] at the START of every committee round — a
/// [ServiceCapability] all four critic lanes `dependsOn`, so it always
/// completes before any lane can read OR write a verdict (gate-integrity #3).
/// A rework round reuses the SAME workspace directory, so a prior round's
/// verdict/rc file otherwise survives on disk; clearing first turns a
/// critic's missing write back into a recognizable miss instead of a stale
/// grade impersonating a fresh one.
///
/// Best-effort BY DESIGN: a delete/recreate failure never Gates the round — the
/// gating lane's own `sh -c` script always `mkdir -p`s the dir again regardless.
///
/// **A BELT, not the guarantee (A15(5) alt-A, bead `pow-05f`)**. It was the
/// whole round-freshness guarantee for exactly one amendment: A4 made the
/// `nodePath` stamp the round fence on the premise that a round re-keys the
/// bead id to `<bead>#rN` — and neither a `grid rework` round (A14(5)) nor a
/// `RouteVerdict.Rewind` wave (tg-o90 — only a `rewindCount` bump) does, so the
/// path is byte-identical round to round. The verdict now STAMPS ITS ROUND
/// ([verdictJsonTemplate], [verdictRound]) and [_verdictFromFile] VERIFIES it, so a
/// stale verdict file that SURVIVES a failed wipe is caught positively at the
/// READ. The wipe stays and still earns its place — it keeps the workspace
/// honest (a critic that writes nothing this round leaves no shadow at all),
/// and the gating lane's `.rc` carries NO stamp, so the wipe remains ITS
/// freshness fence — but a failed wipe can no longer produce a stale LLM grade.
/// The spec circuit still wires it DOWNSTREAM of `specify` (`kSpecReviewCircuit`)
/// so it re-runs on every auto-respec wave.
///
/// **A ROUND-START SWEEP, not a blanket wipe (bridge fix, 2026-07-24 —
/// the tg-60t committee race).** The engine's derived auto-respec wave re-keys
/// the invalidated closure NODE BY NODE, and the stale positive terminals of
/// the not-yet-re-keyed incarnations can let a re-keyed LANE run before this
/// step's own successor does — observed live: two re-keyed lanes graded and
/// wrote CURRENT-round verdicts minutes before clear-critique#2 ran, and the
/// blanket wipe then DESTROYED that same round's finished work, wedging the
/// route's join forever (the lanes were terminal and would never re-write).
/// So the wipe is now round-aware: it deletes exactly what the one shared
/// reader ([_verdictFromFile]) would refuse — a PRIOR round's verdicts, a
/// foreign node's, unstamped/unparseable files, the gating `.rc`, the pinned
/// diff — and KEEPS a verdict stamped with THIS committee's node paths and
/// THIS round ([verdictRound]'s circuit round). A wipe that lands mid-round is then
/// harmless by construction ("the wipe only runs at round start" becomes a
/// property of WHAT it deletes, not of WHEN it runs). Everything a fresh
/// round must not see still dies here; everything this round already produced
/// survives.
class ClearCritiqueCapability extends ServiceCapability {
  /// Creates the capability, optionally over an injected [clearer] (tests
  /// inject a no-op so the offline suite never touches a real filesystem at a
  /// synthetic workspace path — Fakes, not mocks); defaults to the real
  /// round-aware sweep ([sweepStaleCritique]).
  const ClearCritiqueCapability({DirectoryClearer? clearer})
    : _clearer = clearer;

  final DirectoryClearer? _clearer;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return const Ok();
    try {
      final clearer = _clearer;
      if (clearer != null) {
        clearer(critiqueDirPath(workspace.workspaceDir));
      } else {
        sweepStaleCritique(
          workspace.workspaceDir,
          committeePath: parentPath(args.nodePath),
          round: verdictRound(args),
        );
      }
    } catch (_) {
      // Best-effort hygiene — the freshness stamp is the fail-safe backstop.
    }
    return const Ok();
  }
}

/// The round-aware critique sweep [ClearCritiqueCapability] runs: ensures
/// [critiqueDirPath] exists and deletes every entry in it EXCEPT a canonical
/// verdict of THIS round — a `<rubric>.json` whose stamps pass the one shared
/// fence ([_verdictFromFile]) for the sibling node path
/// `<committeePath>/<rubric>` at [round]. Everything else — a prior round's
/// verdict, a foreign node's, an unstamped or unparseable file, the gating
/// `.rc`, `pinned.diff` — is deleted, exactly what the blanket wipe deleted.
///
/// KEEPING the current round's verdicts is the whole point (the tg-60t race):
/// under the derived wave a re-keyed lane can legitimately finish before this
/// step runs, and destroying its verdict wedges the route's join for the rest
/// of the session (the lane is terminal; nothing will ever re-write the file).
/// An unstamped file is deleted silently here — hygiene, never a throw: the
/// LOUD unstamped-verdict refusal belongs to the read path (`result()` / the
/// route join), not to the janitor.
void sweepStaleCritique(
  String workspaceDir, {
  required String committeePath,
  required int round,
}) {
  final dir = Directory(critiqueDirPath(workspaceDir));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    return;
  }
  for (final entry in dir.listSync(followLinks: false)) {
    var keep = false;
    if (entry is File && entry.path.endsWith('.json')) {
      final rubric = p.basenameWithoutExtension(entry.path);
      keep =
          _verdictFromFile(
                entry,
                expectedNodePath: '$committeePath/$rubric',
                expectedRound: round,
              )
              is _VerdictFileAccepted;
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

/// Pins the CRITICS' REVIEW SCOPE to the bead branch's OWN delta (bead
/// `pow-6wo`) — a [ServiceCapability] every critic lane `dependsOn`, so it
/// always runs BEFORE any critic and can withhold them.
///
/// **The invariant it protects (LOUD-or-gone)**: a critic must grade the
/// **bead branch's own delta**, never the ambient worktree. The live-arm
/// finding: 4 of 6 ready beads were already shipped in mainline; for two the
/// branch had ZERO commits beyond origin/main, yet the critics graded that
/// PRE-EXISTING mainline work A/B-range as if it were the bead's diff (one
/// spec-adherence A explicitly cited a months-old mainline commit). Nothing
/// pinned the review to the branch's own delta.
///
/// This step computes that delta once, up front:
///  - `git log --oneline origin/<base>..HEAD` — the commit list under review
///    (provenance);
///  - `git diff origin/<base>...HEAD` — the branch's own change from the
///    MERGE-BASE (three-dot: a base that moved forward while the bead ran can
///    never widen the scope), pinned to [pinnedDiffPath] for the critics.
///
/// Three terminals:
///  - **EMPTY delta ⇒ [Escalate]** — the distinct no-op outcome. A branch with
///    no reviewable change routes to a human ruling INSTEAD of reaching the
///    critics (a stale bead whose work is already in mainline, or a net-zero
///    diff). The critics `dependsOn` this step, so the escalation withholds them
///    — they never run against a scope that isn't the bead's.
///  - **git could not compute the delta ⇒ a thrown [RouteFailure]** — LOUD. An
///    unresolvable `origin/<base>` (or a `git` that won't launch) means the scope
///    is UNKNOWN; failing closed routes to supervision rather than silently
///    escalating (a false stale-bead flag) or silently advancing (critics with an
///    empty scope).
///  - **non-empty delta ⇒ [Advance]** — the pinned diff is written and the round
///    proceeds; the payload carries route-style provenance
///    (`base`/`commits`/`diffBytes`).
///  - **a workspace dir that EXISTS but is not itself the checkout root ⇒ a
///    thrown [RouteFailure]** — the checkout-root guard (bead `pow-4pr`). When
///    provisioning fails sourceless (scaffold residue without a checkout, bead
///    `pow-2ts`), `git` walks UP from the workspace dir to an ANCESTOR checkout
///    and computes the WRONG delta — the live space-ojl incident held a real,
///    validation-green branch as 'stale/no-op — ZERO commits'. Before any
///    log/diff, the guard probes `git rev-parse --show-toplevel` in the
///    workspace dir and requires it to resolve to the workspace dir ITSELF.
///    Both sides are SYMLINK-resolved before comparing: `git` resolves `/tmp`
///    → `/private/tmp` on macOS, a lexical canonicalize does not.
///
/// Offline/dry-run posture: a null [Workspace], or a workspace directory that
/// does not exist on disk (the synthetic `/grid/worktrees/...` path an offline
/// suite mounts, or a build with no worktree materialized), skips straight to
/// [Advance] with NO git call — the same no-op posture as
/// [GitSourceControl.provisionWorkspace] / [AgentCapability] pub-linkage. A
/// LIVE review always has a real worktree the agent just worked in, so the
/// scope guard runs when it matters; the checkout-root guard fires ONLY for a
/// present-but-wrong dir, so this posture is untouched.
class PinDiffCapability extends RouteCapability {
  /// Creates the capability, optionally over an injected [runner] (tests
  /// inject a recording/canned fake — Fakes, not mocks); defaults to the real
  /// [SystemGitRunner], mirroring [RebaseCapability]'s own seam.
  const PinDiffCapability({GitRunner? runner}) : _runner = runner;

  final GitRunner? _runner;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient workspace at ENTRY (while mounted); after every await
    // only the captured values + the cancel token are touched.
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return const Advance();
    final workspaceDir = workspace.workspaceDir;
    // Offline/dry-run: no real worktree to diff — no-op (same posture as
    // GitSourceControl.provisionWorkspace / AgentCapability._linkWorkspace).
    if (!Directory(workspaceDir).existsSync()) return const Advance();

    final runner = _runner ?? SystemGitRunner();
    final baseRef = 'origin/${workspace.baseBranch}';

    // The checkout-root guard (bead pow-4pr): the dir EXISTS — before trusting
    // it as the diff scope, require it to BE the checkout root. `git` walks up
    // to an ancestor checkout from a sourceless scaffold dir (the space-ojl
    // shape), so `--is-inside-work-tree` would pass exactly when it must not.
    final toplevel = await runner.run(
      workingDirectory: workspaceDir,
      args: ['rev-parse', '--show-toplevel'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;
    if (!toplevel.ok) {
      throw RouteFailure(
        'pin-diff: $workspaceDir exists but holds no git checkout '
        '(`git rev-parse --show-toplevel` failed: '
        '${_reasonTail(toplevel.output)}) — a sourceless workspace '
        '(provisioning failure, bead pow-2ts). Refusing rather than minting a '
        'false stale/no-op verdict.',
      );
    }
    final expectedRoot = _resolvedPath(workspaceDir);
    final resolvedTopLevel = _resolvedPath(toplevel.output.trim());
    if (!p.equals(expectedRoot, resolvedTopLevel)) {
      throw RouteFailure(
        'pin-diff: the checkout root for $workspaceDir is resolved toplevel '
        '$resolvedTopLevel — the workspace dir sits INSIDE an ancestor '
        'checkout instead of being one (expected $expectedRoot). The diff '
        'would be computed against the WRONG tree. Refusing rather than '
        'minting a false stale/no-op verdict (the space-ojl shape).',
      );
    }

    // The commit list on THIS branch beyond the base (provenance; `log base..HEAD`).
    final log = await runner.run(
      workingDirectory: workspaceDir,
      args: ['log', '--oneline', '$baseRef..HEAD'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;

    // The pinned review scope — the branch's OWN delta from the merge-base
    // (`diff base...HEAD`, three-dot).
    final diff = await runner.run(
      workingDirectory: workspaceDir,
      args: ['diff', '$baseRef...HEAD'],
    );
    if (args.cancel.isCancelled) throw kRouteCancelled;

    // git could not compute the delta (unresolvable base ref, or a git that
    // won't launch) — the scope is UNKNOWN. Fail LOUD (never a silent escalation
    // that masquerades as a stale bead, nor a silent advance handing critics an
    // empty scope).
    if (!diff.ok) {
      throw RouteFailure(
        'pin-diff: could not compute `git diff $baseRef...HEAD` in '
        '$workspaceDir — ${_reasonTail(diff.output)}',
      );
    }

    final commits = _commitLines(log.output);
    final diffText = diff.output;

    // EMPTY delta ⇒ the distinct no-op terminal: a human ruling, not the critics
    // (A9's empty-delta gate, re-homed onto Escalate — the SAME park).
    if (diffText.trim().isEmpty) {
      return Escalate(
        commits.isEmpty
            ? 'pin-diff: stale/no-op bead — the branch has ZERO commits beyond '
                  '$baseRef, so `git diff $baseRef...HEAD` is EMPTY. Nothing for '
                  'the critics to review (the work is likely already in '
                  'mainline). Routed for a human ruling instead of critique.'
            : 'pin-diff: no-op bead — ${commits.length} commit(s) beyond '
                  '$baseRef, but their net `git diff $baseRef...HEAD` is EMPTY. '
                  'Nothing for the critics to review. Routed for a human ruling '
                  'instead of critique.',
      );
    }

    // Pin the scope for the critics (round-fresh — clear-critique wiped
    // .grid/critique first, and this step `dependsOn` it). A write that cannot
    // land means the critics would fall back to free rein of the worktree — the
    // exact failure being closed — so it fails LOUD, never a silent advance.
    try {
      _writePinnedDiff(
        workspaceDir,
        baseRef,
        workspace.branch,
        commits,
        diffText,
      );
    } catch (e) {
      throw RouteFailure('pin-diff: could not write the pinned diff — $e');
    }

    return Advance({
      'base': baseRef,
      'commits': '${commits.length}',
      'diffBytes': '${diffText.length}',
    });
  }

  /// Writes the pinned review scope to [pinnedDiffPath]: a short header naming
  /// the branch, the base, and the commits under review, followed by the raw
  /// `git diff` body the critics read.
  void _writePinnedDiff(
    String workspaceDir,
    String baseRef,
    String branch,
    List<String> commits,
    String diff,
  ) {
    final header = StringBuffer()
      ..writeln('# Pinned review scope: $branch vs $baseRef')
      ..writeln(
        '# `git diff $baseRef...HEAD` — the ONLY code this bead changed.',
      )
      ..writeln('# Commits under review (`git log $baseRef..HEAD`):');
    if (commits.isEmpty) {
      header.writeln('#   (none)');
    } else {
      for (final c in commits) {
        header.writeln('#   $c');
      }
    }
    header.writeln();
    File(pinnedDiffPath(workspaceDir))
      ..createSync(recursive: true)
      ..writeAsStringSync('$header$diff');
  }

  /// A path prepared for root comparison: SYMLINKS RESOLVED, then lexically
  /// canonicalized. `git rev-parse --show-toplevel` reports the symlink-resolved
  /// root (`/private/tmp/...` on macOS) while the ambient workspace dir is
  /// usually unresolved (`/tmp/...`); `p.canonicalize` alone is purely lexical
  /// and would read those as DIFFERENT roots — a spurious refusal on every
  /// genuine checkout under a symlinked parent. A path that cannot resolve
  /// (vanished mid-route) falls back to the lexical form so the refusal message
  /// carries the literal path.
  static String _resolvedPath(String path) {
    try {
      return p.canonicalize(Directory(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      return p.canonicalize(path);
    }
  }
}

/// The non-empty, trimmed lines of a `git log --oneline` body — the commits on
/// the branch beyond the base, in `<sha> <subject>` form.
List<String> _commitLines(String logOutput) => logOutput
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

/// The TAIL of git combined output — the useful diagnosis is the LAST line
/// (git prints progress first, the fatal message last), and a `Failed` reason
/// is truncated to its FIRST chars downstream; taking the tail keeps the
/// diagnosis, not the noise. A leading `…` marks a cut.
String _reasonTail(String output, [int max = 300]) {
  final trimmed = output.trim();
  return trimmed.length <= max
      ? trimmed
      : '…${trimmed.substring(trimmed.length - max)}';
}

/// One critic, in isolation — a [ProcessCapability] whose `params['rubric']`
/// selects the lane (C2). Two flavors behind the single `critic` capability id:
///
///  - the GATING `code-validation` lane runs the bead's OWN Validation Plan via
///    `sh`: it wraps the plan so the plan's exit code is captured to an rc file,
///    so ANY terminal exit `complete`s the step (the grade — A iff the plan was
///    zero, else F — rides the [result] hook, leaving the route as the single
///    decision point: no retry storm on a deterministic command failure). It is
///    a VALIDATION RUNNER, not an agent — it keeps its direct `sh -c` config;
///  - the three LLM lanes RIDE THE HARNESS (ADR-0008 Decision 10 — critics are
///    agents), in the **GRADE role** ([AgentRole.grade], bead `pow-edp`): the
///    effective [AgentConfig] resolves through the same ladder as the coding
///    agent but off the GRADER rung — a critic reads a pinned diff against ONE
///    rubric and writes a letter, so absent a bead or `--grader-model` override
///    it rides the MID tier ([kMidModelDefault], `sonnet`) while the build rides
///    the FRONTIER tier ([kFrontierModelDefault], `opus`). The resolved harness
///    carries the critic's prompt (ONLY its own rubric); the verdict JSON is
///    parsed by the [result] hook, which also merges the harness's CAPTURE-ONLY
///    usage telemetry (FT-2 — tokens/cost/turns/duration, and the `model` that
///    actually ran) alongside the grade (fail-safe: no usage ⇒ just the grade).
///
/// A capability reads its ambient values — the work [Bead], the [Workspace],
/// the agent scope — with the effect verb (`getInheritedSeedOfExactType`) at
/// entry, and holds no writer/notifier: the four derailment-invariants hold by
/// layering + the host's single write-locus.
class CriticCapability extends ProcessCapability {
  /// Creates the critic, optionally over a [rubrics] source (D-9 wires the
  /// Packaged-AI-Asset loader; absent ⇒ an inline placeholder so C is testable
  /// with no real assets).
  const CriticCapability({
    RubricSource? rubrics,
    @visibleForTesting String Function(File verdict)? verdictTextReader,
  }) : _rubrics = rubrics,
       _verdictTextReader = verdictTextReader ?? _readVerdictText;

  final RubricSource? _rubrics;
  final _VerdictTextReader _verdictTextReader;

  /// The injected rubric source (D-9) — exposed for subclasses: the
  /// spec-readiness committee's `SpecCriticCapability` (bead `pow-6ao`)
  /// embeds prose from the SAME source into its own prompt shape.
  @protected
  RubricSource? get rubricSource => _rubrics;

  String _rubricOf(StepArgs args) => args.params['rubric'] ?? '';

  @override
  CompletionContract get completionContract =>
      CompletionContract.artifactDurability;

  @override
  Future<GateOutcome> probeCompletionArtifact(
    TreeContext context,
    StepArgs args,
  ) async {
    final rubric = _rubricOf(args);
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return GateOutcome.probeError;
    final workspaceDir = workspace.workspaceDir;
    if (rubric == kGatingRubric) {
      try {
        final exists = await File(
          p.join(workspaceDir, _critiqueDir, '$kGatingRubric.rc'),
        ).exists();
        return exists ? GateOutcome.clear : GateOutcome.present;
      } on Object {
        return GateOutcome.probeError;
      }
    }
    try {
      final round = verdictRound(args);
      final durable = currentVerdictOnDisk(
        workspaceDir: workspaceDir,
        rubric: rubric,
        nodePath: args.nodePath,
        round: round,
      );
      if (durable != null) return GateOutcome.clear;

      final recovered = _verdictFromResultText(
        readEnvelopeResultText(workspaceDir, args.nodePath),
      );
      if (recovered == null) return GateOutcome.present;

      final canonical = File(
        p.join(workspaceDir, _critiqueDir, '$rubric.json'),
      );
      await canonical.create(recursive: true);
      await canonical.writeAsString(
        jsonEncode({
          'grade': recovered['grade'],
          'rationale': recovered['rationale'],
          'nodePath': args.nodePath,
          kVerdictRoundKey: round,
        }),
      );
      return currentVerdictFromFile(
                workspaceDir: workspaceDir,
                rubric: rubric,
                nodePath: args.nodePath,
                round: round,
              ) ==
              null
          ? GateOutcome.probeError
          : GateOutcome.clear;
    } on RouteFailure {
      return GateOutcome.probeError;
    } on Object {
      return GateOutcome.probeError;
    }
  }

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // Read the ambient values at ENTRY (synchronously, while mounted).
    final rubric = _rubricOf(args);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'CriticCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    if (rubric == kGatingRubric) {
      // The validation runner — a deterministic `sh -c`, NOT an agent.
      return RuntimeConfig(
        workDir: workspace.workspaceDir,
        command: 'sh',
        args: ['-c', _gatingScript(_validationPlan(bead))],
        lifecycle: Lifecycle.oneTurn,
        deadline: kGatingDeadline,
      );
    }
    // The critic lanes are agents (ADR-0008 Decision 10): resolve the
    // effective config through the ladder and delegate the invocation to the
    // resolved harness — exactly like AgentCapability.spawn.
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final config = resolveAgentConfig(
      role: AgentRole.grade,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
    );
    final environment = registry.resolve(config.harness);
    return spawnFor(
      environment: environment,
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(
        name: config.harness,
        environment: environment,
      ),
      brief: AgentBrief(
        task:
            buildCriticPrompt(
              bead,
              rubric,
              args.nodePath,
              workspace.workspaceDir,
              round: verdictRound(args),
            ) +
            criticRepairInstruction(
              workspaceDir: workspace.workspaceDir,
              rubric: rubric,
              nodePath: args.nodePath,
              round: verdictRound(args),
            ),
      ),
      workspace: workspace,
      // CAPTURE-ONLY usage telemetry (FT-2): the resolved harness (claude)
      // redirects its `--output-format json` envelope here; result() merges the
      // fields into the critic's payload. The verdict file the critic writes is
      // a separate path, so capture never touches the grade.
      usageOut: usageReportPath(args.nodePath),
    );
  }

  /// Returns a corrective instruction when the canonical artifact from a prior
  /// failed attempt violated the verdict contract. Engine supervision restarts
  /// the failed process lane under its default budget; the restarted [spawn]
  /// appends this instruction without replacing the lease-vended allocation.
  @protected
  String criticRepairInstruction({
    required String workspaceDir,
    required String rubric,
    required String nodePath,
    required int round,
  }) {
    final read = _verdictFromFile(
      File(p.join(workspaceDir, _critiqueDir, '$rubric.json')),
      expectedNodePath: nodePath,
      expectedRound: round,
      readText: _verdictTextReader,
    );
    final reason = switch (read) {
      _VerdictFileInvalid(:final reason) => reason,
      _VerdictFileUnstamped(:final reason) => reason,
      _ => null,
    };
    return reason == null
        ? ''
        : '\n\n## Verdict contract repair\n'
              'The previous artifact was refused: $reason\n'
              'Replace it once with strict JSON carrying grade, rationale, '
              'nodePath, and round. Do not recover a grade from prose.';
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) {
    // The lane is encoded in the event name (`$sessionId/.../$stepId`, and the
    // step id IS the rubric id) — the only lane signal available to the
    // ctx-free interpretEvent. The GATING lane `complete`s on ANY terminal exit
    // (the grade rides result()); the LLM lanes use the standard job mapping (a
    // clean exit completes, a non-zero exit / death fails).
    final isGating = event.name.endsWith('/$kGatingRubric');
    if (isGating) {
      return switch (event) {
        Exited() => StepSignal.complete,
        Died() => StepSignal.failed,
        _ => StepSignal.none,
      };
    }
    return switch (event) {
      Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
      Exited() || Died() => StepSignal.failed,
      _ => StepSignal.none,
    };
  }

  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    // Read ambient values at ENTRY (while mounted); only the captured values
    // are touched below.
    final rubric = _rubricOf(args);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) {
      throw StateError(
        'CriticCapability.result requires the ambient Workspace '
        '(SessionScope mounts it)',
      );
    }
    final workspaceDir = workspace.workspaceDir;
    // Resolve the engine-injected circuit round once at entry so every
    // transport for this result carries the same freshness stamp.
    final round = verdictRound(args);
    if (rubric == kGatingRubric) {
      // The plan's exit code, captured by the spawn wrapper. Fail-closed: a
      // missing rc (the plan never ran) grades F — a plan-less bead must NEVER
      // silently pass. [ClearCritiqueCapability] wipes this file every round,
      // so an rc found here is guaranteed fresh — no separate stamp needed.
      final rc = File(p.join(workspaceDir, _critiqueDir, '$kGatingRubric.rc'));
      if (!rc.existsSync()) {
        return {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale': 'no validation-plan rc file — fail-closed default',
          kVerdictRoundKey: '$round',
        };
      }
      final code = rc.readAsStringSync().trim();
      final diagnostic = bead == null
          ? null
          : pathCheckDiagnostic(
              _validationPlan(bead),
              int.tryParse(code) ?? -1,
            );
      return {
        'grade': code == '0' ? 'A' : 'F',
        'transport': 'file',
        kVerdictRoundKey: '$round',
        if (diagnostic != null) 'rationale': diagnostic,
      };
    }
    // The engine's artifact-durability contract withholds completion until a
    // fresh canonical or stray verdict is readable. This second read consumes
    // that same artifact; disappearance between probe and result is a loud
    // race, never a synthesized grade.
    final verdict = File(p.join(workspaceDir, _critiqueDir, '$rubric.json'));
    final graded =
        _payloadOrNull(
          _verdictFromFile(
            verdict,
            expectedNodePath: args.nodePath,
            expectedRound: round,
            readText: _verdictTextReader,
          ),
        ) ??
        _payloadOrNull(
          _strayVerdict(workspaceDir, rubric, args.nodePath, round),
        );
    if (graded == null) {
      throw RouteFailure(
        'critic completion artifact disappeared after the durability probe: '
        '${verdict.path}',
      );
    }
    final stamped = {...graded, kVerdictRoundKey: '$round'};
    // Merge the CAPTURE-ONLY usage telemetry (FT-2) into the payload. FAIL-SAFE:
    // an absent / malformed envelope yields no fields, NEVER a throw — the grade
    // (fail-closed above) is unaffected. Collision-safe keys (grade/rationale vs
    // tokensIn/…), so the merge never shadows the verdict.
    final usage = readUsageFields(workspaceDir, args.nodePath);
    return usage.isEmpty ? stamped : {...stamped, ...usage};
  }

  /// The rubric prose embedded in a critic's prompt — the injected [rubrics]
  /// source (D-9), or an inline placeholder so C is testable with no assets.
  String _rubricText(String rubric) =>
      _rubrics?.call(rubric) ??
      '(rubric `$rubric` — the Packaged-AI-Asset loader supplies the bands in '
          'Track D)';

  /// Assembles the LLM critic's prompt for [rubric] over the work [bead] —
  /// names ONLY its own rubric (anti-anchoring: a critic must not see the other
  /// lanes' concerns or grades), carries the full bead, and instructs a single
  /// A–F grade written as a verdict JSON. Rides the harness as a bare
  /// `AgentBrief(task: …)` (no working agreement, no context blocks — so the
  /// rendered brief IS this prompt, byte-identical).
  ///
  /// The file-write instruction is deliberately the LAST thing the prompt says
  /// (tg-291 — recency: a model observed to state a clean verdict in its
  /// response prose while skipping the file write. It is imperative, names the exact path, and
  /// is explicit that stating the verdict in prose does NOT satisfy it — the
  /// file write is REQUIRED regardless. The durability contract keeps a lane
  /// unresolved until that required artifact exists.
  ///
  /// The verdict JSON also carries TWO FRESHNESS STAMPS ([verdictJsonTemplate]),
  /// both copied byte-for-byte: [nodePath] (gate-integrity #3 — WHOSE verdict is
  /// this?) and [round] (A15(5) alt-A — WHICH round's?, the respec ledger's own
  /// `round` via [verdictRound]). [_verdictFromFile] rejects a file that fails
  /// EITHER, so a verdict left over from an earlier round in the SAME reused
  /// workspace directory — where the node path is byte-identical, and only the
  /// round differs — is never silently read as this round's.
  ///
  /// **Gate-integrity #4 — the cwd-relative write path (bead `tg-r66`)**: the
  /// path handed to the critic is the workspace-derived ABSOLUTE canonical
  /// path (`[workspaceDir]/.grid/critique/<rubric>.json`), NOT a
  /// workspace-relative one. A critic that `cd`s mid-run (`test-coverage` cd's
  /// into a package to run `dart test` — the chronically flaky lane) would
  /// resolve a relative `.grid/critique/<rubric>.json` against its CURRENT cwd
  /// and write a STRAY verdict under the package (observed live:
  /// `packages/grid_assets/.grid/critique/test-coverage.json`), leaving the
  /// canonical path empty ⇒ a false fail-closed gate. An absolute path is
  /// cwd-invariant, so the write lands where `result()` reads regardless of
  /// where the critic wandered. ([_strayVerdict] is the read-side belt for a
  /// critic that still writes off-path some other way.)
  ///
  /// **Scope-pinning (bead `pow-6wo`)**: the prompt names the pinned-diff file
  /// ([pinnedDiffPath]) [PinDiffCapability] wrote — the bead branch's OWN delta
  /// (`git diff origin/<base>...HEAD`) — as the critic's EXCLUSIVE review scope.
  /// The live finding this closes: with the bead's work already in mainline,
  /// critics graded PRE-EXISTING mainline code A/B as if it were the bead's
  /// diff. The instruction is explicit that code outside the pinned diff is OUT
  /// OF SCOPE, so a critic cannot credit (or blame) work the bead did not do.
  /// (An EMPTY delta never reaches here — [PinDiffCapability] gates the round
  /// upstream.)
  ///
  /// Exposed for unit tests.
  String buildCriticPrompt(
    Bead bead,
    String rubric,
    String nodePath,
    String workspaceDir, {
    required int round,
  }) {
    final path = p.join(workspaceDir, _critiqueDir, '$rubric.json');
    final diffPath = pinnedDiffPath(workspaceDir);
    final b = StringBuffer()
      ..writeln('# Code review — rubric: `$rubric`')
      ..writeln()
      ..writeln(
        'You are ONE critic in an adversarial committee. Review the work ONLY '
        'against the `$rubric` rubric below — do not weigh any other concern.',
      )
      ..writeln()
      ..writeln('## Rubric: $rubric')
      ..writeln(_rubricText(rubric))
      ..write(_beadBlock(bead))
      ..writeln()
      ..writeln('## Review scope — the pinned diff (READ THIS FIRST)')
      ..writeln(
        'Your review is scoped to EXACTLY this bead branch\'s OWN change — its '
        'delta from the base branch (`git diff origin/<base>...HEAD`), pinned '
        'at the ABSOLUTE path `$diffPath`. Read that file FIRST: it is the ONLY '
        'code this bead changed.',
      )
      ..writeln(
        'Grade ONLY what that diff changes. Code the diff does not touch is OUT '
        'OF SCOPE — do NOT grade pre-existing code, and do NOT credit (or blame) '
        'work that is already in mainline outside this diff. If you cannot point '
        'a claim to a hunk of the pinned diff, it does not belong in your grade.',
      )
      ..writeln()
      ..writeln('## Your verdict')
      ..writeln(
        'Grade the work A (best) through F (worst) against `$rubric` ONLY. '
        'Your verdict is JSON of this exact shape:',
      )
      ..writeln(
        verdictJsonTemplate(rubric: rubric, nodePath: nodePath, round: round),
      )
      ..writeln()
      ..writeln(kVerdictStampInstruction)
      ..writeln()
      ..writeln(verdictWriteInstruction(path));
    return b.toString();
  }
}

/// The route/aggregate step — a [ServiceCapability] that reads its sibling
/// critics' grades through the AMBIENT [SiblingView] (mounted by
/// `SessionScope`; read with the effect verb — D-5, never a subscription/
/// re-query) and applies the deterministic matrix (C3, asset policy):
///
///  - a GATING lane at grade `F` (a non-zero Validation Plan) → [Escalate]
///    (hard block). `gating` is a lane SET read as a CSV, so a committee whose
///    gate is several deterministic checks (the docs committee's three) needs
///    no second matrix — a single-id value is just a one-element set;
///  - a grade SPREAD ≥ 3 letters across the lanes → [Escalate] (human ultimatum);
///  - any NON-gating critic at `D`/`F` → [Escalate] (rework — the `restForOne`
///    transitive re-key is deferred, so a D/F parks at the bound handler for now);
///  - else (all A–C, gating not F, spread < 3) → [Advance] (on to delivery).
///
/// The [Advance] payload carries ROUTE PROVENANCE (FT-2, CAPTURE-ONLY): the
/// grade vector consumed (`grades` — `lane=grade` CSV in [kCommitteeRubrics]
/// order), the computed `spread`, and the matrix arm that fired (`rule` =
/// `all-approve`) — making the keep/kill export self-contained without changing
/// the matrix. Escalations are UNCHANGED (their reason string already names the
/// rule).
///
/// Fail-closed: an unread / missing sibling grade is treated as `F`, so a forged
/// or absent grade can NEVER advance (the mutation-tested property).
///
/// GENERIC over its `critics`/`gating` params (bead `pow-6ao`): the SAME
/// capability joins the spec-readiness committee (`specify.dart`'s
/// `kSpecReviewCircuit` — gating `spec-validation` + four spec critics) with
/// its own param set; the matrix, the fail-closed defaults, and the provenance
/// payload are committee-agnostic.
///
/// NAMED `CodeRouteCapability`, not `RouteCapability`: the engine now EXPORTS an
/// abstract `RouteCapability` (the route primitive this extends), so the short
/// name is taken. The STEP id stays `route` — it is a persisted cursor key.
class CodeRouteCapability extends RouteCapability {
  /// Creates the code committee's route.
  const CodeRouteCapability();

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient sibling view at ENTRY (while mounted); the matrix below
    // is pure over the captured values.
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final parent = parentPath(args.nodePath);
    // The GATING lane SET: the docs committee's gate is THREE deterministic
    // checks, so `gating` is a CSV exactly like `critics`. A single-id value
    // yields a one-element set — the code and spec committees are unchanged.
    final gating = (args.params['gating'] ?? '')
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final criticIds = (args.params['critics'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Read each lane's RAW grade once (null/empty ⇒ missing), then the
    // fail-closed grade used by the block rules (missing ⇒ F).
    final rawGrades = <String, String?>{
      for (final id in criticIds) id: siblings.resultOf('$parent/$id')['grade'],
    };
    final grades = <String, String>{
      for (final entry in rawGrades.entries)
        entry.key: _normalizeGrade(entry.value),
    };

    // 1. the gating lane failed (a non-zero Validation Plan / a structurally
    // broken spec, or a missing gating grade) — a hard block. The reason names
    // the gating LANE (this route serves both the code and the spec committee,
    // bead `pow-6ao`), so the parked gate says which gate fired.
    final failedGates = gating.where((id) => grades[id] == 'F').toList();
    if (failedGates.isNotEmpty) {
      final failedRationales = [
        for (final id in failedGates)
          if (siblings.resultOf('$parent/$id')['rationale'] case final value?
              when value.trim().isNotEmpty)
            value.trim(),
      ];
      final suffix = failedRationales.isEmpty
          ? ''
          : ': ${failedRationales.join('; ')}';
      return Escalate('${failedGates.join(', ')} failed: hard block$suffix');
    }

    // 2. a grade spread ≥ 3 letters across the PRESENT lanes — a human
    // ultimatum. Missing grades are IGNORED here (they are already caught by
    // the fail-closed gating/D-F block rules), so the spread reflects only the
    // grades the critics actually returned.
    final indices = [
      for (final entry in rawGrades.entries)
        if (entry.value != null && entry.value!.trim().isNotEmpty)
          _gradeIndex(_normalizeGrade(entry.value)),
    ];
    final spread = indices.isEmpty
        ? 0
        : indices.reduce(math.max) - indices.reduce(math.min);
    if (spread >= 3) {
      return const Escalate('grade spread ≥ 3 — human ultimatum');
    }

    // 3. any non-gating critic at D/F — rework → restForOne re-key is deferred
    // (build-order); a D/F parks at the bound handler for now.
    for (final entry in grades.entries) {
      if (gating.contains(entry.key)) continue;
      if (entry.value == 'D' || entry.value == 'F') {
        return const Escalate('a critic returned D/F — rework');
      }
    }

    // 4. all A–C, gating clean, spread < 3 — advance. The advance payload
    // carries the ROUTE PROVENANCE (FT-2): the per-lane grade vector it consumed
    // (CSV `lane=grade` in kCommitteeRubrics order), the computed spread, and the
    // matrix arm that fired (`all-approve`) — so the keep/kill export is
    // self-contained. Escalations keep their reason string (it names the rule).
    final gradesCsv = criticIds.map((id) => '$id=${grades[id]}').join(',');
    return Advance({
      'verdict': 'advance',
      'grades': gradesCsv,
      'spread': '$spread',
      'rule': 'all-approve',
    });
  }
}

/// The default code-committee critic-id index of [grade] (A=0 … F=5); a grade
/// outside `A..F` clamps to F (the fail-closed worst).
int _gradeIndex(String grade) {
  const ladder = ['A', 'B', 'C', 'D', 'E', 'F'];
  final i = ladder.indexOf(grade);
  return i < 0 ? ladder.length - 1 : i;
}

/// Normalizes a raw sibling grade to an upper-case letter, fail-closing a
/// null/empty grade to `F`.
String _normalizeGrade(String? grade) =>
    (grade == null || grade.trim().isEmpty) ? 'F' : grade.trim().toUpperCase();

/// The bead's OWN Validation Plan — the `validation_plan` metadata command. A
/// plan-less bead defaults to `false` (an explicit non-zero) so it grades F
/// rather than silently passing.
String _validationPlan(Bead bead) {
  final plan = bead.metadata['validation_plan'];
  if (plan is String && plan.trim().isNotEmpty) return plan.trim();
  return 'false';
}

/// The `sh -c` script the gating lane runs: ensure the critique dir, run the
/// plan in a subshell, and capture ITS exit code to the rc file `result()`
/// reads. The outer `sh` exits clean regardless, so the step always `complete`s
/// and the route is the single decision point.
String _gatingScript(String plan) =>
    'mkdir -p $_critiqueDir; ( $plan ) ; echo \$? > $_critiqueDir/$kGatingRubric.rc';

/// Renders the full work bead into a prompt block (title/description/design/
/// acceptance/notes) — the load-bearing review input.
String _beadBlock(Bead bead) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final b = StringBuffer()
    ..writeln()
    ..writeln('## The work bead')
    ..writeln('`${bead.id}` — $title');
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    b
      ..writeln()
      ..writeln('### $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  return b.toString();
}

/// The verdict's ROUND stamp as an int — `null` when the stamp is ABSENT or
/// unreadable. A JSON number and its string form both read (a critic that wrote
/// `"round":"2"` made a formatting slip, not a stale verdict); anything else is
/// a MISS, which fail-closes exactly like a foreign `nodePath` does.
int? _stampedRound(Object? raw) => switch (raw) {
  final num round when round.isFinite && round == round.truncateToDouble() =>
    round.toInt(),
  final String round => int.tryParse(round.trim()),
  _ => null,
};

sealed class _VerdictFileRead {
  const _VerdictFileRead();
}

final class _VerdictFileAccepted extends _VerdictFileRead {
  const _VerdictFileAccepted(this.payload);

  final Map<String, String> payload;
}

final class _VerdictFileMissing extends _VerdictFileRead {
  const _VerdictFileMissing();
}

final class _VerdictFileRejected extends _VerdictFileRead {
  const _VerdictFileRejected();
}

final class _VerdictFileInvalid extends _VerdictFileRead {
  const _VerdictFileInvalid(this.path, this.detail);

  final String path;
  final String detail;

  String get reason => 'invalid critic verdict at $path: $detail';
}

final class _VerdictFileUnstamped extends _VerdictFileRead {
  const _VerdictFileUnstamped(this.path);

  final String path;

  String get reason =>
      'verdict present at $path but missing the freshness stamp (nodePath/round)';
}

/// A synchronous verdict read seam used to exercise boundary failures.
typedef _VerdictTextReader = String Function(File verdict);

String _readVerdictText(File verdict) => verdict.readAsStringSync();

String _verdictErrorDetail(Object error) => switch (error) {
  FormatException(:final message) => message,
  FileSystemException(:final message) => message,
  _ => error.toString(),
};

final class _InvalidVerdictFailure extends RouteFailure {
  const _InvalidVerdictFailure(super.reason);
}

Map<String, String>? _payloadOrNull(_VerdictFileRead read) => switch (read) {
  _VerdictFileAccepted(:final payload) => payload,
  _VerdictFileMissing() || _VerdictFileRejected() => null,
  _VerdictFileInvalid(:final reason) => throw _InvalidVerdictFailure(reason),
  _VerdictFileUnstamped(:final reason) => throw RouteFailure(reason),
};

/// The verdict file's grade, when it parses AND is FRESH — `null` for an absent
/// file or a stale/foreign stamp. Invalid JSON, a non-object root, a missing or
/// blank required field, an unreadable round, and an off-ladder grade are
/// [_VerdictFileInvalid]. It rejects a `nodePath` stamp
/// that doesn't match [expectedNodePath], OR a `round` stamp that doesn't match
/// [expectedRound], so stale or foreign stamps continue to the fallback chain
/// per A4/A15. The TWO stamps fence two DIFFERENT staleness modes and both are
/// load-bearing: `nodePath` rejects a verdict some OTHER node wrote (a stray
/// write, a mis-keyed lane — A4); `round` rejects a verdict THIS node wrote in
/// an EARLIER round (A15(5) alt-A — under `RouteVerdict.Rewind` the node path is
/// byte-identical round to round, so `nodePath` alone cannot see it). A malformed
/// or incomplete verdict is surfaced through [_payloadOrNull] as a
/// [RouteFailure], so the lease-vended process allocation reports
/// [AllocationFailed]. Engine supervision may restart the lane under its
/// default budget; the next [CriticCapability.spawn] appends
/// [CriticCapability.criticRepairInstruction]. Only absent, stale, or foreign
/// verdicts are misses that can fall through to the stray / RESULT TEXT /
/// fail-closed chain.
_VerdictFileRead _verdictFromFile(
  File verdict, {
  required String expectedNodePath,
  required int expectedRound,
  _VerdictTextReader readText = _readVerdictText,
}) {
  if (!verdict.existsSync()) return const _VerdictFileMissing();
  try {
    final decoded = jsonDecode(readText(verdict));
    if (decoded is! Map<String, dynamic>) {
      return _VerdictFileInvalid(verdict.path, 'root must be a JSON object');
    }
    final json = decoded;
    final gradeValue = json['grade'];
    final grade = gradeValue is String ? gradeValue.trim().toUpperCase() : '';
    if (grade.isEmpty) {
      return _VerdictFileInvalid(
        verdict.path,
        'grade must be a non-empty string',
      );
    }
    if (!const {'A', 'B', 'C', 'D', 'E', 'F'}.contains(grade)) {
      return _VerdictFileInvalid(verdict.path, 'grade must be one of A–F');
    }
    final rationaleValue = json['rationale'];
    final rationale = rationaleValue is String ? rationaleValue.trim() : '';
    if (rationale.isEmpty) {
      return _VerdictFileInvalid(
        verdict.path,
        'rationale must be a non-empty string',
      );
    }
    final nodePathValue = json['nodePath'];
    final stampedNodePath = nodePathValue is String ? nodePathValue.trim() : '';
    if (stampedNodePath.isEmpty) {
      return _VerdictFileInvalid(
        verdict.path,
        'nodePath must be a non-empty string',
      );
    }
    final stampedRound = _stampedRound(json[kVerdictRoundKey]);
    if (stampedRound == null) {
      return _VerdictFileInvalid(
        verdict.path,
        'round must be an integer or integer-readable string',
      );
    }
    if (stampedNodePath != expectedNodePath) {
      return const _VerdictFileRejected(); // a FOREIGN node's.
    }
    if (stampedRound != expectedRound) {
      return const _VerdictFileRejected(); // a STALE round's.
    }
    return _VerdictFileAccepted({
      'grade': grade,
      'transport': 'file',
      'rationale': rationale,
    });
  } on Object catch (error) {
    return _VerdictFileInvalid(verdict.path, _verdictErrorDetail(error));
  }
}

/// [rubric]'s CANONICAL verdict payload under [workspaceDir], iff it parses AND
/// carries THIS [nodePath] + THIS [round]'s freshness stamps — null for an
/// absent, foreign, or PRIOR-ROUND file. A malformed or incomplete present
/// artifact throws [RouteFailure].
///
/// A thin public wrapper over the ONE parser+fence ([_verdictFromFile] via
/// [_payloadOrNull]) so a route JOIN can apply the same current-round rule
/// `result()` applies, without a second JSON parser: `SpecRouteCapability`
/// (`respec.dart`) sources each judgement lane's grade + rationale from here,
/// and a lane that returns null here does NOT join — the flare reason can never
/// cite a grade for a lane with no current-round artifact on disk. A present,
/// parseable verdict MISSING a freshness stamp throws [RouteFailure] (exactly
/// as it does under `result()`): the critic decided, but the freshness
/// envelope is unverifiable — LOUD, never a silent drop.
Map<String, String>? currentVerdictFromFile({
  required String workspaceDir,
  required String rubric,
  required String nodePath,
  required int round,
}) => _payloadOrNull(
  _verdictFromFile(
    File(p.join(workspaceDir, _critiqueDir, '$rubric.json')),
    expectedNodePath: nodePath,
    expectedRound: round,
  ),
);

/// [currentVerdictFromFile] widened to the SAME transport reach `result()` has
/// for on-disk artifacts: the canonical path first, then the round-fresh STRAY
/// walk (gate-integrity #4 — a critic that `cd`d mid-run and wrote its verdict
/// under a subdir). The route's join reads through THIS (bridge fix,
/// 2026-07-24): a lane whose verdict `result()` accepted as `file-stray` still
/// has a current-round artifact ON DISK, and refusing to join it would wedge
/// the round on a lane that can never re-write. Same fence, same round, same
/// single parser — only the search widens.
Map<String, String>? currentVerdictOnDisk({
  required String workspaceDir,
  required String rubric,
  required String nodePath,
  required int round,
}) =>
    currentVerdictFromFile(
      workspaceDir: workspaceDir,
      rubric: rubric,
      nodePath: nodePath,
      round: round,
    ) ??
    _payloadOrNull(_strayVerdict(workspaceDir, rubric, nodePath, round));

/// A round-fresh verdict a critic wrote to a STRAY
/// `.../.grid/critique/<rubric>.json` somewhere OTHER than the canonical
/// workspace-root path — the read-side belt for gate-integrity #4 (bead
/// `tg-r66`). A critic that `cd`s mid-run (`test-coverage` cd's into a package
/// to run `dart test`) can resolve the verdict path against its current cwd and
/// write it under the package instead of at the worktree root (observed live:
/// `packages/grid_assets/.grid/critique/test-coverage.json`). [buildCriticPrompt]
/// now hands the critic the ABSOLUTE path so the write lands correctly, but this
/// belt recovers a verdict a critic still writes off-path some other way.
///
/// Walks [workspaceDir] for every `.grid/critique/<rubric>.json` and returns the
/// FIRST whose stamps match THIS node and THIS round — the `nodePath` + `round`
/// stamps (gate-integrity #3, A15(5) alt-A) are exactly what makes accepting an
/// off-path file safe: a stale or foreign stray can never match, so a leftover
/// from an earlier round is never misread as this round's verdict. The canonical
/// path is skipped (the caller already consulted it). Absent or malformed stray
/// verdicts continue the fallback chain; stale or foreign stamps continue the
/// fallback chain per A4/A15; a present parseable stray verdict missing the
/// freshness stamp is discarded as [_VerdictFileUnstamped], which fails the lane
/// through [RouteFailure] so the process lane retries. Best-effort for directory
/// traversal; parse outcomes remain explicit.
_VerdictFileRead _strayVerdict(
  String workspaceDir,
  String rubric,
  String expectedNodePath,
  int expectedRound,
) {
  final canonical = p.canonicalize(
    p.join(workspaceDir, _critiqueDir, '$rubric.json'),
  );
  for (final file in _strayVerdictFiles(workspaceDir, rubric)) {
    if (p.canonicalize(file.path) == canonical) continue; // the canonical path.
    final read = _verdictFromFile(
      file,
      expectedNodePath: expectedNodePath,
      expectedRound: expectedRound,
    );
    switch (read) {
      case _VerdictFileAccepted(:final payload):
        return _VerdictFileAccepted({...payload, 'transport': 'file-stray'});
      case _VerdictFileUnstamped():
      case _VerdictFileInvalid():
        return read;
      case _VerdictFileMissing() || _VerdictFileRejected():
        continue;
    }
  }
  return const _VerdictFileMissing();
}

/// Every `.../.grid/critique/<rubric>.json` file under [root], found by a
/// bounded DFS that prunes VCS/build/dependency dirs (`.git`, `.dart_tool`,
/// `node_modules`, `build`) so the fallback walk stays cheap. Symlinks are not
/// followed. Best-effort: an unreadable directory is skipped, never thrown.
Iterable<File> _strayVerdictFiles(String root, String rubric) sync* {
  const prune = {'.git', '.dart_tool', 'node_modules', 'build'};
  final target = p.join(
    _critiqueDir,
    '$rubric.json',
  ); // '.grid/critique/<r>.json'
  final stack = <Directory>[Directory(root)];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue; // unreadable — skip this subtree.
    }
    for (final entry in entries) {
      if (entry is Directory) {
        if (!prune.contains(p.basename(entry.path))) stack.add(entry);
      } else if (entry is File && _endsWithPath(entry.path, target)) {
        yield entry;
      }
    }
  }
}

/// Whether [path] ends with the relative [suffix] on a path-separator boundary
/// (so `.../pkg/.grid/critique/r.json` matches `.grid/critique/r.json`, but
/// `.../x.grid/critique/r.json` would not spuriously match `grid/critique/…`).
bool _endsWithPath(String path, String suffix) {
  if (!path.endsWith(suffix)) return false;
  if (path.length == suffix.length) return true;
  final boundary = path[path.length - suffix.length - 1];
  return boundary == p.separator || boundary == '/';
}

/// Recovers a verdict from the critic's captured stdout so the completion
/// probe can persist it as the canonical durability artifact.
Map<String, String>? _verdictFromResultText(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return _verdictFromEmbeddedJson(trimmed) ?? _verdictFromHeading(trimmed);
}

final RegExp _validGradeLetter = RegExp(r'^[A-F]$');

/// Returns the last valid embedded verdict object from captured stdout.
Map<String, String>? _verdictFromEmbeddedJson(String text) {
  Map<String, String>? last;
  for (var start = 0; start < text.length; start++) {
    if (text[start] != '{') continue;
    var depth = 0;
    for (var end = start; end < text.length; end++) {
      if (text[end] == '{') depth++;
      if (text[end] == '}') {
        depth--;
        if (depth != 0) continue;
        try {
          final json = jsonDecode(text.substring(start, end + 1));
          if (json is Map) {
            final grade = (json['grade'] as String?)?.trim().toUpperCase();
            if (grade != null && _validGradeLetter.hasMatch(grade)) {
              final rationale = (json['rationale'] as String?)?.trim() ?? '';
              last = {
                'grade': grade,
                'transport': 'envelope',
                'rationale': rationale.isEmpty
                    ? '[from result envelope]'
                    : '$rationale [from result envelope]',
              };
            }
          }
        } catch (_) {
          // Not a decodable verdict at this brace; keep scanning.
        }
        break;
      }
    }
  }
  return last;
}

final RegExp _verdictHeading = RegExp(
  r'(?:verdict|grade)\s*:\s*([A-Fa-f])\b',
  caseSensitive: false,
);

/// Returns the last valid verdict heading from captured stdout.
Map<String, String>? _verdictFromHeading(String text) {
  final matches = _verdictHeading.allMatches(text);
  if (matches.isEmpty) return null;
  final match = matches.last;
  final grade = match.group(1)!.toUpperCase();
  final rationale = text.substring(match.end).trim();
  return {
    'grade': grade,
    'transport': 'envelope',
    'rationale': rationale.isEmpty
        ? '[from result envelope]'
        : '$rationale [from result envelope]',
  };
}

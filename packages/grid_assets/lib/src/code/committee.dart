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
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/captured_output.dart';
import '../agent/environment_registry.dart';
import '../agent/model_tier.dart';
import '../agent/seat_environments.dart';
import '../agent/site_binding.dart';
import '../agent/usage_report.dart';
import 'committee_selection.dart';
import 'fix_in_flight.dart';
import 'route_failure.dart';
import 'specify.dart' show headingOffset, proseOnly, sectionBodyAt;
import 'validation.dart';

/// The gating rubric id — its grade `F` is a hard block (a non-zero Validation
/// Plan command), decided by the route's matrix.
const String kGatingRubric = 'code-validation';

/// The hard gate for test files promised by the Design.
const String kDeclaredTestsRubric = 'declared-tests-present';

/// Every deterministic hard gate in the code committee.
const List<String> kCodeGatingRubrics = [kGatingRubric, kDeclaredTestsRubric];

/// The gating lane's absolute-from-start deadline (the_grid audit §4,
/// `tg-uad` follow-through): the deterministic `code-validation` lane runs the
/// bead's OWN Validation Plan via `sh -c`, which is minutes-scale by
/// definition — never the multi-hour agentic build/critic lanes — so it must
/// NOT ride a runtime provider's 2-hour default watchdog. Ten minutes bounds
/// every future validation-latched variant of this lane without crowding a
/// legitimately slow (but still deterministic) plan. Deliberately NOT applied
/// to the LLM critic/build lanes, which legitimately ride the long default.
///
/// **The lane enforces it ITSELF now**
/// (`power_station#code-validation-enforces-its-own-deadline-as-a-service-capability`):
/// `code-validation` is a [ServiceCapability], and the comparison's merge-base
/// run stands in a scratch worktree OUTSIDE any per-bead `RuntimeProvider`, so
/// no provider watchdog could bound it. [SystemShellRunner] terminates the
/// plan's whole process group on this bound and reports `timedOut`. ONE value:
/// this name and [kValidationDeadline] are the same ten minutes.
const Duration kGatingDeadline = kValidationDeadline;

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

/// The workspace-relative path the gating lane tees the Validation Plan's FULL
/// combined stdout+stderr to — named in the failed gate's reason so the
/// engine's head-first `failureReason` cap can never be the only copy of the
/// cause (the live finding: a lane that discarded the plan's output gated a
/// bead with `code-validation failed: hard block` and nothing else, and the
/// operator then had to re-derive by hand what one read would have answered).
///
/// Beside the `.rc` on purpose: they are the ONE run's two artifacts, written
/// by the same script, and [sweepStaleCritique] retires them together.
const String _gatingLogRelativePath = '$_critiqueDir/$kGatingRubric.log';

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

/// The FORMATTING pre-critic step id (bead `pow-jicn`) every critic lane
/// `dependsOn`, sequenced beside [kDeclaredTestsRubric] after [kPinDiffStep].
///
/// The live finding: three codex-built branches in one epoch passed the FULL
/// committee (three inference critics ≈ $0.57/run plus the deterministic gating
/// lane) and were delivered, then failed CI at its FIRST step — the workspace
/// format gate — on four unformatted files each. Every review lane was spent on
/// a diff a one-second deterministic check would have refused, and no merge
/// queue saw green until a human rebased and reformatted by hand.
/// [FormatCleanCapability] asks that question BEFORE the critics. A
/// dirty answer is a typed work failure (never a letter grade), so the round
/// parks with the offending files NAMED and the builder's next round fixes
/// exactly them.
const String kFormatCleanStep = 'format-clean';

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
  r'^\s*Test:\s*(.+)$',
  caseSensitive: false,
  multiLine: true,
);
final RegExp _dartTestCommand = RegExp(
  r'\bdart\s+test\b',
  caseSensitive: false,
);
final RegExp _testCommandPath = RegExp(
  r'(?:^|\s)([A-Za-z0-9_.\/-]+_test\.dart)(?=\s|$)',
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

/// The vocabulary a design uses when it CITES an existing test as the pattern
/// it follows, rather than promising an edit to it — "built on", "the shape
/// already used in", "mirrors", "reuses", "as in".
///
/// Read ONLY inside a per-path window ([_authoredEvidence]), never
/// statement-wide: a cue demotes an edit verb for the path it GOVERNS, so the
/// base-presence exemption reaches the cited file, and never for a sibling path
/// in the same sentence. [_nonDeclarationTestStatement] stays the statement-wide
/// exclusion list and is NOT extended — folding these words into it would widen
/// the exclusion to every path in a sentence, the same over-claim mirrored.
final RegExp _referenceTestStatement = RegExp(
  r'\balready\s+(?:use[sd]|do(?:es)?|ha[sd])\b|'
  // The PATTERN-SOURCE family: a statement that CREATES one file and names an
  // existing suite as the shape it copies ("the _pump patterns from `<A>`",
  // "modelled after `<A>`", "adapted from `<A>`"). Two of these words are
  // ambiguous on their own, and each is narrowed where it is read rather than
  // parsed: `following` cites a source ONLY when a marked test path is the very
  // next token on the line ([_markerForTestPath]), so "Following review, add
  // cases to `<A>`" and "add the following case to `<A>`" stay promises about
  // `<A>`; and `pattern(s) in` is also the authored file's OWN noun phrase
  // ("update the assertion patterns in `<A>`"), which [_authoredEvidence] keeps
  // authored unless a bridge word names a distinct target.
  r'\b(?:built|based)\s+on\b|'
  r'\bmodell?ed\s+(?:on|after)\b|'
  r'\b(?:the\s+)?patterns?\s+(?:from|in)\b|'
  r'\busing\s+(?:the\s+)?patterns?\b|'
  r'\bfollowing\b(?=[ \t]+GRID_TEST_PATH_\d+_)|'
  r'\bin\s+the\s+style\s+of\b|'
  r'\b(?:copied|adapted)\s+from\b|'
  r'\bmirror(?:s|ed|ing)?\b|'
  r'\breus(?:e|es|ed|ing)\b|'
  r'\b(?:the\s+)?same\s+shape\s+as\b|'
  r'\bthe\s+shape\s+used\s+in\b|'
  r'\b(?:like|as\s+in|see)\b',
  caseSensitive: false,
);
final RegExp _testStatementBoundary = RegExp(
  r'[.;](?:[ \t]+|\r?\n|$)|'
  r'\r?\n[ \t]*\r?\n|'
  r'\r?\n(?=[ \t]*(?:[-*+][ \t]+|\d+[.)][ \t]+|#{1,6}[ \t]+))|'
  r'\r?\n(?=[ \t]*(?:Test:|'
  r'(?:add(?:ed|ing|s)?|author(?:ed|ing|s)?|create(?:d|s|ing)?|'
  r'modif(?:ied|ies|y|ying)|update(?:d|s|ing)?|'
  r'writ(?:e|es|ing|ten)|wrote)\b))',
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

String _markerForTestPath(String path, Map<String, String> pathByMarker) {
  final marker = 'GRID_TEST_PATH_${pathByMarker.length}_';
  pathByMarker[marker] = path;
  return marker;
}

String _markTestCommandPaths(String design, Map<String, String> pathByMarker) =>
    design.replaceAllMapped(_testCommandLine, (match) {
      final command = match.group(1)!.replaceAll('`', '');
      if (!_dartTestCommand.hasMatch(command)) return match.group(0)!;
      final markers = <String>[];
      for (final pathMatch in _testCommandPath.allMatches(command)) {
        final path = _confidentTestPath(pathMatch.group(1)!);
        if (path != null) {
          markers.add(_markerForTestPath(path, pathByMarker));
        }
      }
      return markers.isEmpty
          ? match.group(0)!
          : 'Test: dart test ${markers.join(' ')}';
    });

/// An EXACT citation of a Dart file that is NOT a confident test path — the
/// SOURCE sibling an edit verb may govern instead of the test beside it.
///
/// Verbatim: `(?<![A-Za-z0-9_.:/-])(?:package:)?[A-Za-z0-9_.-]+`
/// `(?:/[A-Za-z0-9_.-]+)+(?<!_test)\.dart(?![A-Za-z0-9_./-])`. Read as four
/// decisions, each made here so no reader has to guess:
///
/// - **At least one `/`.** A bare `committee.dart` names a FILE, not a path, and
///   is far too easy to write about a test's own subject; only a path with a
///   directory segment is exact enough to bound evidence. [_confidentTestPath]
///   draws the same line for test paths.
/// - **`package:` optional.** `package:leonard_contract/src/strike_counter.dart`
///   and `lib/src/strike_counter.dart` are the same citation in two spellings;
///   the leading lookbehind rejects `:` so a `package:` URI matches ONCE, whole,
///   never again at its bare-path tail.
/// - **`(?<!_test)` subtracts every `_test.dart` name.** A test path is the
///   other pipeline's business ([_confidentTestPath], [_markerForTestPath]);
///   this matcher answers only for the non-test files that bound it, so the two
///   never claim the same span.
/// - **Punctuation ends it.** The citation is usually UNQUOTED prose, so the
///   trailing lookahead admits `,`/`` ` ``/whitespace/end and a `:544` line
///   suffix, and refuses a longer name (`.dartfile`) or a longer path.
final RegExp _dartPathReference = RegExp(
  r'(?<![A-Za-z0-9_.:/-])'
  r'(?:package:)?'
  r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+'
  r'(?<!_test)\.dart'
  r'(?![A-Za-z0-9_./-])',
);

/// Reserves a BOUNDARY-ONLY marker in [boundaryMarkers] — a token that holds a
/// non-test Dart citation's position through `proseOnly` (which blanks the
/// inline span it was written in) so [_evidenceWindow] can still cut on it.
///
/// It carries NO path, and it is deliberately kept OUT of `pathByMarker`: only
/// that map's entries are bucketed ([_collectTestDeclarations]), so a
/// boundary-only marker structurally cannot reach `authored`, `mentioned` or
/// `fallback`. It bounds evidence; it never claims a file.
String _markerForPathBoundary(Set<String> boundaryMarkers) {
  final marker = 'GRID_SOURCE_PATH_${boundaryMarkers.length}_';
  boundaryMarkers.add(marker);
  return marker;
}

String _markConfidentTestPaths(
  String design,
  Map<String, String> pathByMarker,
  Set<String> boundaryMarkers,
) => design.replaceAllMapped(_inlineCodeSpan, (match) {
  final span = match.group(1)!;
  final path = _confidentTestPath(span);
  if (path != null) return _markerForTestPath(path, pathByMarker);
  // An inline span that is EXACTLY one non-test Dart citation is preserved as a
  // boundary: `proseOnly` would blank it, and a blanked source path cannot stop
  // its own verb from reaching the test path beside it.
  final cited = span.trim();
  return _dartPathReference.stringMatch(cited) == cited
      ? _markerForPathBoundary(boundaryMarkers)
      : match.group(0)!;
});

String _statementAround(String text, String marker) {
  final markerAt = text.indexOf(marker);
  var start = 0;
  var end = text.length;
  for (final boundary in _testStatementBoundary.allMatches(text)) {
    if (boundary.end <= markerAt) {
      start = boundary.end;
      continue;
    }
    if (boundary.start >= markerAt + marker.length) {
      end = boundary.start;
      break;
    }
  }
  return text.substring(start, end);
}

/// The gap between two sibling test paths that carries NO evidence of its own —
/// whitespace, commas, semicolons, backticks and the conjunctions `and`/`or`.
///
/// A run of paths joined only by these separators is ONE list governed by one
/// verb ("Modify `a`, `b`, and `c`"), so [_evidenceWindow] keeps the run whole
/// instead of cutting each path off from the verb that promises it.
final RegExp _testPathListGap = RegExp(
  r'^(?:[\s,;&`]|\band\b|\bor\b)*$',
  caseSensitive: false,
);

/// The slice of [statement] whose words govern the path at [marker]: the
/// maximal RUN of sibling TEST paths containing it, widened to the END of the
/// citation before the run and the START of the citation after it.
///
/// The window is keyed to the cited test path's EXACT occurrence — its own
/// [marker], never its filename stem. A sibling source path is a HARD BOUNDARY:
/// in `create a suite over src/x.dart`, `create` governs `src/x.dart` and the
/// window of a `test/x_test.dart` cited later opens AFTER it, so the two files
/// that merely share the stem `x` never inherit each other's verbs (bead
/// `pow-kdsl`: the retained suite a design only RUNS was read as authored by the
/// verb that created its subject).
///
/// Evidence for one path never leaks onto another. In `Create A, built on the
/// harness B already uses`, the A-B gap carries words, so the two are separate
/// runs: A's window holds "Create" and B's holds only the reference clause.
/// In `Modify A, B, and C` every gap is a bare list separator
/// ([_testPathListGap]), so all three share one window and one verb promises
/// them all — a run widens through a gap only between two TEST paths, because
/// only test paths can share one promise here; a source citation cuts the run
/// whatever separates it, so `Create src/x.dart and A` leaves A unclaimed.
/// [markers] is every test marker in play (`pathByMarker.keys`) and
/// [boundaryMarkers] every preserved inline source citation
/// ([_markerForPathBoundary]); UNQUOTED source citations are found in
/// [statement] directly ([_dartPathReference]). Each occurrence carries its OWN
/// marker, so a marker absent from [statement] cuts nothing.
String _evidenceWindow(
  String statement,
  String marker,
  Iterable<String> markers,
  Iterable<String> boundaryMarkers,
) {
  final markerAt = statement.indexOf(marker);
  if (markerAt < 0) return statement;
  final spans = <({int start, int end, bool boundary})>[
    (start: markerAt, end: markerAt + marker.length, boundary: false),
  ];
  void addOccurrences(String other, {required bool boundary}) {
    var at = statement.indexOf(other);
    while (at >= 0) {
      spans.add((start: at, end: at + other.length, boundary: boundary));
      at = statement.indexOf(other, at + 1);
    }
  }

  for (final other in markers) {
    if (other == marker) continue;
    addOccurrences(other, boundary: false);
  }
  for (final other in boundaryMarkers) {
    addOccurrences(other, boundary: true);
  }
  for (final cited in _dartPathReference.allMatches(statement)) {
    spans.add((start: cited.start, end: cited.end, boundary: true));
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  final self = spans.indexWhere((span) => span.start == markerAt);
  bool listGap(int left) =>
      !spans[left].boundary &&
      !spans[left + 1].boundary &&
      _testPathListGap.hasMatch(
        statement.substring(spans[left].end, spans[left + 1].start),
      );
  var first = self;
  while (first > 0 && listGap(first - 1)) {
    first--;
  }
  var last = self;
  while (last < spans.length - 1 && listGap(last)) {
    last++;
  }
  return statement.substring(
    first == 0 ? 0 : spans[first - 1].end,
    last == spans.length - 1 ? statement.length : spans[last + 1].start,
  );
}

/// Whether [window]'s edit-verb evidence PROMISES the path at [marker].
///
/// An edit verb ([_authoredTestStatement]) must appear in the window at all —
/// no verb, no promise. Which of the two vocabularies GOVERNS the path is then
/// decided by position: the LAST evidence token that ends before the path wins;
/// when nothing precedes the path, the FIRST token that starts after it wins
/// ("`<A>` — modified" is authored; "the harness `<A>` already uses" is a
/// citation); when neither exists, an edit verb elsewhere in the window still
/// claims it. A reference cue ([_referenceTestStatement]) governing the path
/// demotes it to the base-gated `mentioned` bucket — it never exempts it
/// outright.
bool _authoredEvidence(String window, String marker) {
  if (!_authoredTestStatement.hasMatch(window)) return false;
  final markerAt = window.indexOf(marker);
  if (markerAt < 0) return true;
  final markerEnd = markerAt + marker.length;
  bool? governing;
  var lastAt = -1;
  for (final match in _authoredTestStatement.allMatches(window)) {
    if (match.end <= markerAt && match.start > lastAt) {
      lastAt = match.start;
      governing = true;
    }
  }
  for (final match in _referenceTestStatement.allMatches(window)) {
    if (match.end <= markerAt && match.start > lastAt) {
      // `pattern(s) in` is the one cue that is ALSO the authored file's own
      // noun phrase: `Update the assertion patterns in <A>` edits <A>, while
      // `Create this file with the patterns in <A>` cites it. What separates
      // them is a bridge word naming a DISTINCT target — `using`/`with` —
      // between the edit verb and the phrase, so with no bridge the verb keeps
      // the path it already won. Every other cue demotes on position alone.
      Match? authoredBeforeMarker;
      for (final authored in _authoredTestStatement.allMatches(window)) {
        if (authored.end <= markerAt) authoredBeforeMarker = authored;
      }
      final referenceText = match.group(0)!.toLowerCase();
      final authoredMatch = authoredBeforeMarker;
      if (authoredMatch != null) {
        final bridge =
            ' ${window.substring(authoredMatch.end, match.start).trim().toLowerCase()} ';
        final authoredSelfReference =
            const {
              'pattern in',
              'patterns in',
              'the pattern in',
              'the patterns in',
            }.contains(referenceText) &&
            !bridge.contains(' using ') &&
            !bridge.contains(' with ');
        if (authoredSelfReference) continue;
      }
      lastAt = match.start;
      governing = false;
    }
  }
  if (governing != null) return governing;
  var firstAt = window.length;
  for (final match in _authoredTestStatement.allMatches(window)) {
    if (match.start >= markerEnd && match.start < firstAt) {
      firstAt = match.start;
      governing = true;
    }
  }
  for (final match in _referenceTestStatement.allMatches(window)) {
    if (match.start >= markerEnd && match.start < firstAt) {
      firstAt = match.start;
      governing = false;
    }
  }
  return governing ?? true;
}

/// Sorts every marked path in [text] into the bucket its EVIDENCE earns.
///
/// [authored] — the path's own per-path WINDOW carries an explicit edit verb
/// ([_evidenceWindow] + [_authoredEvidence]): a PROMISE about the file whatever
/// the base tree holds. Evidence is scoped to the path it governs, so a sentence
/// that creates one file and CITES another as its pattern promises only the
/// created one. [mentioned] — the marker sits inside a declaration section's
/// body with NO authored evidence (bead `pow-aoa`): the design NAMES the file
/// without claiming an edit, which is evidence only when the file does not exist
/// yet. A marker in neither position is not collected at all.
void _collectTestDeclarations({
  required String text,
  required Map<String, String> pathByMarker,
  required Set<String> boundaryMarkers,
  required Set<String> authored,
  required Set<String> mentioned,
  required bool declarationSection,
}) {
  for (final entry in pathByMarker.entries) {
    if (!text.contains(entry.key)) continue;
    final statement = _statementAround(text, entry.key);
    final window = _evidenceWindow(
      statement,
      entry.key,
      pathByMarker.keys,
      boundaryMarkers,
    );
    if (_authoredEvidence(window, entry.key)) {
      authored.add(entry.value);
      continue;
    }
    // The run-line and non-declaration arms stay STATEMENT-wide: a rewritten
    // `Test: dart test <M1> <M2>` line puts `dart test` outside `<M2>`'s window,
    // so narrowing them would turn a run reference into a declaration.
    if (_dartTestCommand.hasMatch(statement) ||
        _nonDeclarationTestStatement.hasMatch(statement)) {
      continue;
    }
    if (declarationSection) mentioned.add(entry.value);
  }
}

void _collectTestLineFallback({
  required String prose,
  required Map<String, String> pathByMarker,
  required Set<String> fallback,
}) {
  for (final match in _testCommandLine.allMatches(prose)) {
    final command = match.group(1)!;
    if (!_dartTestCommand.hasMatch(command)) continue;
    for (final entry in pathByMarker.entries) {
      if (command.contains(entry.key)) fallback.add(entry.value);
    }
  }
}

/// A design's confident test paths, split by the EVIDENCE that named them.
///
/// [authored] — claimed as new or modified authored work by an explicit edit
/// verb ([_authoredTestStatement]). [mentioned] — named inside a declaration
/// section's body with no edit verb (bead `pow-aoa`). [fallback] — named ONLY by
/// a bare `Test:` run command, the historical fail-closed fallback that applies
/// when the design carries no declaration section at all (bead `pow-qev` r2).
///
/// The buckets answer to different evidence. An authored path is a PROMISE
/// whatever the base tree holds; a bare mention or a `Test:` line naming a file
/// that already exists at the pinned base promises nothing — it is a RUN or a
/// REFERENCE (beads `pow-0jc`, `pow-aoa`). A path with authored evidence is
/// authored: precedence never inverts.
typedef TestDeclarations = ({
  Set<String> authored,
  Set<String> mentioned,
  Set<String> fallback,
});

/// Extracts [TestDeclarations] from [design] — the one extraction pipeline
/// (`_markTestCommandPaths` → `_markConfidentTestPaths` → `proseOnly` →
/// `_collectTestDeclarations`), reporting its three evidence buckets separately.
TestDeclarations testDeclarations(String design) {
  final pathByMarker = <String, String>{};
  // Boundary-only markers stay OUT of `pathByMarker`: they bound evidence
  // ([_evidenceWindow]) and are never bucketed, because only `pathByMarker`'s
  // entries are ([_collectTestDeclarations]).
  final boundaryMarkers = <String>{};
  final commandMarkedDesign = _markTestCommandPaths(design, pathByMarker);
  final markedDesign = _markConfidentTestPaths(
    commandMarkedDesign,
    pathByMarker,
    boundaryMarkers,
  );
  final prose = proseOnly(markedDesign);
  final authored = <String>{};
  final mentioned = <String>{};
  final fallback = <String>{};
  final declarationBodies = <String>[];

  for (final heading in _testDeclarationHeadings) {
    final headingAt = headingOffset(prose, heading);
    if (headingAt < 0) continue;
    declarationBodies.add(sectionBodyAt(prose, headingAt));
  }

  _collectTestDeclarations(
    text: prose,
    pathByMarker: pathByMarker,
    boundaryMarkers: boundaryMarkers,
    authored: authored,
    mentioned: mentioned,
    declarationSection: false,
  );
  for (final body in declarationBodies) {
    _collectTestDeclarations(
      text: body,
      pathByMarker: pathByMarker,
      boundaryMarkers: boundaryMarkers,
      authored: authored,
      mentioned: mentioned,
      declarationSection: true,
    );
  }
  if (declarationBodies.isEmpty) {
    _collectTestLineFallback(
      prose: prose,
      pathByMarker: pathByMarker,
      fallback: fallback,
    );
  }
  // Authored-marker precedence (bead `pow-qev` r1): a path claimed as authored
  // work is never demoted to a bare mention or a run reference by ALSO appearing
  // in a declaration section's prose or in a `Test:` line.
  mentioned.removeAll(authored);
  fallback.removeAll(authored);
  fallback.removeAll(mentioned);
  return (authored: authored, mentioned: mentioned, fallback: fallback);
}

/// Confident test paths the design DECLARES — the gate's obligation set.
///
/// [baseFiles] is the pinned base's file list ([baseTreeFiles]). A path the
/// design names ONLY in a bare `Test:` run command (bead `pow-0jc`) or ONLY as a
/// bare prose mention inside a declaration section (bead `pow-aoa`) AND that
/// already exists at the base is a RUN or a REFERENCE, not a declaration: the
/// design promises nothing about it, so requiring it in the pinned diff would
/// block a change that correctly leaves it alone. An authored edit verb still
/// declares whatever the base holds.
///
/// A citation is matched against [baseFiles] verbatim, or by a UNIQUE
/// path-boundary suffix (a cited `test/x_test.dart` resolves to a base
/// `packages/p/test/x_test.dart`); an AMBIGUOUS suffix — the same basename under
/// two packages — identifies no file and stays a declaration. An EMPTY
/// [baseFiles] — the default, and the answer whenever the base could not be
/// read — keeps every base-gated path a declaration, i.e. `pow-qev`'s
/// fail-closed posture unchanged.
Set<String> declaredTestFiles(
  String design, {
  Set<String> baseFiles = const <String>{},
}) {
  final declarations = testDeclarations(design);
  // A package-relative citation resolves against the repo-root base list by
  // path-boundary suffix — but only when the answer is UNIQUE. Two packages
  // carrying the same test basename identify nothing, so the path stays a
  // declaration (fail-closed, like `pow-qev`'s empty base).
  bool presentAtBase(String path) =>
      baseFiles.contains(path) ||
      baseFiles.where((base) => _endsWithPath(base, path)).length == 1;
  bool absentAtBase(String path) => !presentAtBase(path);
  return {
    ...declarations.authored,
    ...declarations.mentioned.where(absentAtBase),
    ...declarations.fallback.where(absentAtBase),
  };
}

/// Sorted declarations absent from [changedFiles].
List<String> missingDeclaredTestFiles({
  required String design,
  required Set<String> changedFiles,
  Set<String> baseFiles = const <String>{},
}) =>
    declaredTestFiles(design, baseFiles: baseFiles)
        .where(
          (declared) =>
              !changedFiles.any((changed) => _endsWithPath(changed, declared)),
        )
        .toList()
      ..sort();

/// The ONE review base every committee probe measures a round against: the
/// commit the workspace was PROVISIONED from, when the provisioner recorded it
/// ([Workspace.baseSha]), and otherwise the remote base branch.
///
/// A9 pins the critics to the bead branch's OWN delta, and `origin/<baseBranch>`
/// is only a STAND-IN for "the commit this branch was cut from". It stops being
/// one the moment a substation's LOCAL base branch runs ahead of its remote: the
/// live lunar_station-a7w round cut its worktree from a local `main` sitting 55
/// unpushed commits ahead of `origin/main`, so all 55 landed inside
/// `diff origin/main...HEAD` and spec-adherence graded the station's own
/// housekeeping commit — 120 deletions the bead never authored — as the bead's
/// work. The provisioner's recorded SHA names the actual cut, so pinning to it
/// measures exactly the round. Null (a provisioner that records nothing, or the
/// offline synthetic workspace) keeps the remote base branch.
///
/// A REVIEW base only. Landing still rebases onto `origin/<baseBranch>`: remote
/// divergence is reconciled THERE, never in review.
/// PUBLIC because it has exactly ONE home: the declared-tests gate, the
/// diff-pinning step and the two merge-base COMPARISON lanes
/// ([CodeValidationCapability] and `RevalidateCapability`) all ask for the
/// review base here rather than re-deriving `baseSha ?? origin/<base>` — a
/// second derivation is how the two halves of a comparison drift apart.
String reviewBaseRef(Workspace workspace) =>
    workspace.baseSha ?? 'origin/${workspace.baseBranch}';

/// The repo-relative paths tracked at [baseRef] — the pinned base's own file
/// list, read once with `git ls-tree -r --name-only <baseRef>` in
/// [workspaceDir].
///
/// Answers the EMPTY set when the base cannot be read at all: no worktree on
/// disk (A9(5)'s offline/dry-run posture) or a git that could not resolve the
/// ref. Empty means "the base is UNKNOWN", and an unknown base leaves every
/// base-gated path a declaration — a failed probe can only make the gate
/// STRICTER, never laxer, so it invents no verdict of its own.
Future<Set<String>> baseTreeFiles({
  required GitRunner runner,
  required String workspaceDir,
  required String baseRef,
}) async {
  if (!Directory(workspaceDir).existsSync()) return const <String>{};
  final listed = await runner.run(
    workingDirectory: workspaceDir,
    args: ['ls-tree', '-r', '--name-only', baseRef],
  );
  if (!listed.ok) return const <String>{};
  return listed.output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet();
}

/// Mechanical, no-agent verification of Design-declared test-file presence.
class DeclaredTestsCapability extends ServiceCapability {
  /// Creates the gate, optionally over an injected [runner] — the `code`
  /// registry's SHARED git seam (A9(5)); tests inject a canned fake (Fakes,
  /// not mocks). Absent ⇒ the real [SystemGitRunner].
  const DeclaredTestsCapability({GitRunner? runner}) : _runner = runner;

  final GitRunner? _runner;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      return Ok({
        'grade': 'F',
        'transport': 'structural',
        'missing': jsonEncode(const <String>[]),
        'rationale': 'no ambient work Bead / Workspace to check — fail-closed',
      });
    }
    final pinned = File(pinnedDiffPath(workspace.workspaceDir));
    if (!await pinned.exists()) {
      return Ok({
        'grade': 'F',
        'transport': 'structural',
        'missing': jsonEncode(const <String>[]),
        'rationale':
            'no pinned diff at ${pinned.path} — declared tests cannot be checked; fail-closed',
      });
    }
    // A bare `Test:` run line (bead `pow-0jc`) and a bare prose mention inside a
    // declaration section (bead `pow-aoa`) are DECLARATIONS only when the file
    // they name is ABSENT at the pinned base: a file already on the base that
    // the design merely RUNS or REFERS TO is not a promise, and the change is
    // right not to touch it. An authored edit verb never consults the base, so a
    // design whose declarations are all authored costs ZERO git.
    final declarations = testDeclarations(bead.design);
    final baseGated = {...declarations.mentioned, ...declarations.fallback};
    final baseFiles = baseGated.isEmpty
        ? const <String>{}
        : await baseTreeFiles(
            runner: _runner ?? SystemGitRunner(),
            workspaceDir: workspace.workspaceDir,
            baseRef: reviewBaseRef(workspace),
          );
    final missing = missingDeclaredTestFiles(
      design: bead.design,
      changedFiles: changedFilesIn(await pinned.readAsString()),
      baseFiles: baseFiles,
    );
    // The missing set rides the payload as MACHINE-READABLE evidence, sorted,
    // beside the prose rationale: the route subtracts the paths the
    // code-validation comparison proved already fail at the merge-base, and it
    // can only do that from a set it can decode
    // (`power_station#code-validation-hard-blocks-only-branch-regressions`
    // extends the delta rule to this gate). The classification above is
    // UNCHANGED — a declaration is still a promise whatever the base holds.
    return missing.isEmpty
        ? Ok({
            'grade': 'A',
            'transport': 'structural',
            'missing': jsonEncode(const <String>[]),
          })
        : Ok({
            'grade': 'F',
            'transport': 'structural',
            'missing': jsonEncode(missing),
            'rationale':
                'Design-declared test files missing from pinned diff: ${missing.join(', ')}',
          });
  }
}

/// The DETERMINISTIC `code-validation` lane — the bead's own Validation Plan,
/// run on the BRANCH and at its MERGE-BASE, gating only on the difference.
///
/// **Why a service and not a spawned job**
/// (`power_station#code-validation-enforces-its-own-deadline-as-a-service-capability`).
/// The comparison's base run stands in a detached scratch worktree, outside any
/// per-bead `RuntimeProvider` — no provider watchdog could ever bound it, and
/// no runtime event describes it. So the lane owns both runs and its own
/// deadline: [ValidationDeltaRunner] hands each side [kGatingDeadline], and
/// [SystemShellRunner] terminates the plan's whole process group when it
/// elapses. The retired RuntimeProvider watchdog arm — the `Died(reason:
/// 'watchdog: …')` completion and the armed `.grid/critique-incarnation/
/// code-validation.deadline` stamp it graded off — is GONE with the job.
///
/// **Why a delta and not an exit code**
/// (`power_station#code-validation-hard-blocks-only-branch-regressions`). A
/// failure identical on the merge-base is NOT the bead's: it is a host-only
/// flake, another bead's leak, or a pre-existing red. It is reported as a NOTE
/// — named in this lane's artifact as `preexisting`, carried into the PR body's
/// circuit receipt — and it never gates. Only a named test that PASSES at the
/// base and FAILS on the branch is a `regression`, and only regressions grade
/// `F`.
///
/// **The receipts**
/// (`power_station#code-validation-preserves-diagnostics-and-reports-deadline`,
/// as the delta ruling updated it). `.grid/critique/code-validation.log` still
/// holds the branch plan's FULL combined stdout and stderr, and the ten-minute
/// bound is unchanged. `.grid/critique/code-validation.rc` is now the EFFECTIVE
/// delta exit — zero whenever the branch did not regress — because that file is
/// what the landing policy reads as "this round validated"; the RAW branch exit
/// is preserved verbatim as `branchRc` in the JSON artifact beside it, so
/// nothing is lost, only re-homed.
///
/// A run that cannot be compared at all — a base that fails to compile, an
/// `exit 64`, a missing tool, a scratch worktree that could not be made — is a
/// LANE failure with a named cause ([Failed.noResult]), never a bead verdict.
/// It is a RUNNER, not an agent (`power_station#a20-…`): it resolves no
/// `AgentConfig`, names no model, and reads no critic environment.
class CodeValidationCapability extends ServiceCapability {
  /// Creates the lane over the registry's ONE shared merge-base [comparison]
  /// runner (tests inject one built from recording fakes — Fakes, not mocks);
  /// absent ⇒ a default [ValidationDeltaRunner] over the real git and shell
  /// seams.
  const CodeValidationCapability({ValidationDeltaRunner? comparison})
    : _comparison = comparison;

  final ValidationDeltaRunner? _comparison;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (synchronously, while mounted) with the
    // non-binding effect verb — this is a `run` edge (ADR-0008 D3). No
    // AgentConfig, no ModelPreference, no critic environment: a runner resolves
    // none of them.
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final round = verdictRound(args);
    // The OFFLINE posture, identical to every other deterministic lane's: a
    // synthetic workspace that does not exist on disk means there is nothing to
    // compare, so the lane answers with NO process and NO filesystem IO. The
    // arrays are still decodable, because the route decides on them.
    if (bead == null ||
        workspace == null ||
        !Directory(workspace.workspaceDir).existsSync()) {
      return Ok({
        'grade': 'A',
        'transport': _validationTransport,
        'branchRc': '0',
        'regressions': jsonEncode(const <String>[]),
        'preexisting': jsonEncode(const <String>[]),
        kVerdictRoundKey: '$round',
      });
    }

    final workspaceDir = workspace.workspaceDir;
    final comparison = _comparison ?? const ValidationDeltaRunner();
    final logPath = p.join(workspaceDir, _gatingLogRelativePath);
    final ValidationDelta delta;
    try {
      delta = await comparison.compare(
        plan: _validationPlan(bead),
        workspace: workspace,
        // The review base has exactly ONE owner; this lane never re-derives it.
        baseRef: reviewBaseRef(workspace),
        branchLogPath: logPath,
        effectiveRcPath: p.join(
          workspaceDir,
          _critiqueDir,
          '$kGatingRubric.rc',
        ),
      );
    } on ValidationLaneFailure catch (failure) {
      // A base-side cause is persisted BESIDE the branch log, never over it:
      // the two sides' outputs answer different questions.
      if (failure.side != 'branch' && failure.outputTail.trim().isNotEmpty) {
        writeCapturedOutputLog(
          path: p.join(workspaceDir, _critiqueDir, '$kGatingRubric.base.log'),
          output: failure.outputTail,
        );
      }
      _writeValidationArtifact(workspaceDir, {
        'transport': _validationTransport,
        'laneFailure': failure.message,
        'side': failure.side,
        if (failure.baseSha != null) 'baseSha': failure.baseSha,
        kVerdictRoundKey: round,
      });
      // NEVER a bead verdict: the lane could not decide, so it says so.
      return Failed.noResult('code-validation: ${failure.message}');
    }
    if (args.cancel.isCancelled) {
      return const Failed.noResult('code-validation: cancelled');
    }

    final grade = delta.regressions.isEmpty ? 'A' : 'F';
    _writeValidationArtifact(workspaceDir, {
      'grade': grade,
      'transport': _validationTransport,
      'baseSha': delta.baseSha,
      'baseCache': delta.baseCacheHit ? 'hit' : 'miss',
      'branchRc': delta.branchExitCode,
      'regressions': delta.regressions,
      'preexisting': delta.preexisting,
      kVerdictRoundKey: round,
    });
    return Ok({
      'grade': grade,
      'transport': _validationTransport,
      'baseSha': delta.baseSha,
      'baseCache': delta.baseCacheHit ? 'hit' : 'miss',
      'branchRc': '${delta.branchExitCode}',
      'regressions': jsonEncode(delta.regressions),
      'preexisting': jsonEncode(delta.preexisting),
      kVerdictRoundKey: '$round',
    });
  }

  /// Spends exactly ONE attempt on a lane that produced no comparable result,
  /// then parks it at a gate.
  ///
  /// The reasoning the retired process lane recorded holds verbatim: this is a
  /// DETERMINISTIC runner, so re-running it against an unchanged tree cannot
  /// change a `noResult`, and the engine's `infra` backoff would otherwise
  /// spend its whole harness-throttle ladder — the observed 5 + 15 + 30
  /// minutes — before the node parks, leaving the session open with nothing for
  /// the governor's watch to fire on. The engine tests exhaustion AFTER
  /// bumping the restart cursor, so a budget of one makes the first attempt the
  /// last.
  @override
  SupervisionPolicy supervisionPolicy(StepArgs args) => const SupervisionPolicy(
    byKind: {
      CapabilityFailureKind.noResult: RetryPolicy(
        maxRestarts: 1,
        onExhaustion: ExhaustionBehavior.parkAtGate,
      ),
    },
  );
}

/// The transport every `code-validation` payload names — a DELTA against the
/// merge base, not a captured exit code.
const String _validationTransport = 'validation-delta';

/// Writes the lane's JSON artifact atomically, so a reader never sees a
/// half-written verdict.
void _writeValidationArtifact(String workspaceDir, Map<String, Object?> body) {
  final path = p.join(workspaceDir, _critiqueDir, '$kGatingRubric.json');
  try {
    final target = File(path);
    target.parent.createSync(recursive: true);
    File('$path.tmp')
      ..writeAsStringSync(jsonEncode(body))
      ..renameSync(path);
  } on Object {
    // Best-effort, exactly like every other critique-dir write in this file:
    // the payload the route decides on is the STEP RESULT, and an artifact that
    // could not land costs an operator a read, never a verdict.
  }
}

/// Mechanical, no-agent refusal of an UNFORMATTED diff (bead `pow-jicn`).
///
/// Reads the round-fresh pinned scope [PinDiffCapability] wrote, keeps the Dart
/// files it touches that still EXIST in the worktree (a deleted path and a
/// non-Dart path are not formatter inputs), and asks the DART domain's
/// [DartFormatService] whether the formatter would change any of them. The
/// Dart-specific command lives with the Dart pack that vends the `dart` verbs;
/// this step composes it by id, so a substation whose domain is not Dart simply
/// composes nothing.
///
/// It NEVER rewrites the diff on the builder's behalf: a silent reformat would
/// hand the critics code the builder never wrote. A dirty answer is a plain
/// [Failed] — [CapabilityFailureKind.work], because the probe RAN and returned
/// a substantive refusal that names files — and NOT a letter grade, so the
/// route's matrix (and the grade vector it reads) is untouched. The critic
/// lanes `dependsOn` this step, so the refusal withholds every one of them
/// before a single token is spent, and [supervisionPolicy] spends one attempt
/// on it before the host parks it at a gate.
///
/// A probe that cannot decide is a DIFFERENT answer, and equally LOUD: a
/// missing or unreadable pinned scope in a worktree that EXISTS, and a
/// formatter that failed operationally, are typed non-results — never a silent
/// pass, and never confused with a decided dirty verdict.
///
/// Offline/dry-run posture: a null [Workspace], or a workspace directory that
/// does not exist on disk, is a no-op [Ok] with NO process spawned — the same
/// posture [PinDiffCapability] holds for the synthetic `/grid/worktrees/...`
/// path an offline suite mounts.
class FormatCleanCapability extends ServiceCapability {
  /// Creates the gate over the DART domain's [formatter] seam (tests inject a
  /// canned Fake — Fakes, not mocks); absent ⇒ the real [DartFormatService].
  const FormatCleanCapability({
    DartFormatService formatter = const DartFormatService(),
  }) : _formatter = formatter;

  final DartFormatService _formatter;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient workspace at ENTRY (while mounted); after every await
    // only the captured values + the cancel token are touched.
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null || !Directory(workspace.workspaceDir).existsSync()) {
      return const Ok({'checked': '0'});
    }
    final workspaceDir = workspace.workspaceDir;
    final pinned = File(pinnedDiffPath(workspaceDir));
    if (!await pinned.exists()) {
      return Failed.noResult('format-clean: no pinned diff at ${pinned.path}');
    }
    final String diff;
    try {
      diff = await pinned.readAsString();
    } on Object catch (error) {
      return Failed.noResult(
        'format-clean: could not read pinned diff at ${pinned.path}: $error',
      );
    }
    if (args.cancel.isCancelled) {
      return const Failed.noResult('format-clean: cancelled');
    }
    final dartFiles =
        changedFilesIn(diff)
            .where((path) => path.endsWith('.dart'))
            .where((path) => File(p.join(workspaceDir, path)).existsSync())
            .toList()
          ..sort();
    final outcome = await _formatter.check(
      workspaceDir: workspaceDir,
      files: dartFiles,
    );
    if (args.cancel.isCancelled) {
      return const Failed.noResult('format-clean: cancelled');
    }
    return switch (outcome) {
      DartFormatClean(:final files) => Ok({'checked': '${files.length}'}),
      // The formatter DECIDED and named the offending files: substantive work
      // the builder must fix, never an environment refusal the host should
      // read as harness silence.
      DartFormatDirty(:final files) => Failed(
        'format-clean: dart format would change: ${files.join(', ')}',
      ),
      DartFormatProbeFailed(:final file, :final exitCode, :final output) =>
        Failed.noResult(
          'format-clean: dart format probe failed for $file'
          '${exitCode == null ? '' : ' (exit $exitCode)'}'
          '${output.trim().isEmpty ? '' : ': ${output.trim()}'}',
        ),
    };
  }

  /// Spends exactly ONE attempt on a dirty verdict, then parks it at a gate.
  ///
  /// `dart format` is deterministic over an unchanged worktree: a restart
  /// re-reads the same bytes and returns the same file list, so every restart
  /// the circuit's default budget would grant is futile and only delays the
  /// operator's gate. [RetryPolicy.maxRestarts] of one makes the first attempt
  /// the last (the engine tests exhaustion AFTER bumping the restart cursor),
  /// and [ExhaustionBehavior.parkAtGate] hands it to the host's existing
  /// escalation path, so the gate reason NAMES the would-change files.
  ///
  /// Only `work` is declared. An undecidable probe — a missing or unreadable
  /// pinned scope, a formatter that would not launch — keeps the circuit's own
  /// budget, because that IS the transient a restart can clear.
  @override
  SupervisionPolicy supervisionPolicy(StepArgs args) => const SupervisionPolicy(
    byKind: {
      CapabilityFailureKind.work: RetryPolicy(
        maxRestarts: 1,
        onExhaustion: ExhaustionBehavior.parkAtGate,
      ),
    },
  );
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

/// The verdict JSON key naming WHO can fix an actionable (`D`/`E`) grade —
/// bead `pow-hxme`, ADR-0000 A37. Not a freshness stamp (A4 and A15(5) alt-A
/// fence the `nodePath` + `round`): a PAYLOAD column the SPEC route's matrix
/// decides on.
const String kVerdictOwnerKey = 'owner';

/// The fix is derivable from the bead AS WRITTEN plus the tree — re-running
/// `specify` with the critic's rationale can produce it. The auto-respec loop
/// is exactly the right instrument.
const String kOwnerArchitect = 'architect';

/// The fix needs a decision the bead TEXT does not make (which sibling's
/// symbol names win, whether the scope splits, which of two designs is
/// wanted, a policy call). No re-run of the architect can converge, however
/// good it is — the receipt is `pow-n6n.1`, which drew a coherence `D` twice
/// asking the architect to choose between its own names and `pow-n6n.2`'s.
const String kOwnerAuthor = 'author';

/// The closed owner vocabulary. A verdict naming anything else is refused by
/// the ONE decoder — LOUD, never coerced.
const List<String> kVerdictOwners = [kOwnerArchitect, kOwnerAuthor];

/// The verdict JSON key carrying a lane's NON-GRADING observations about the
/// BEAD GRAPH — bead `pow-bhm`'s COHERENCE SCOPE dial (policy Nico-ratified
/// 2026-07-18, interactive session: "Tracker state is never the spec author's
/// defect").
///
/// A PAYLOAD column exactly like [kVerdictOwnerKey] (A37(6)): validated after
/// the grade, never a freshness stamp, never read by a decision matrix. It is
/// OPTIONAL for every family — nothing is ever refused for omitting it — and
/// only the lane whose rubric TEACHES it (`coherence`) is expected to fill it.
const String kVerdictRefinementKey = 'refinement';

/// The REFINEMENT instruction the SPEC critic prompt writes after
/// [kVerdictOwnerInstruction] (bead `pow-bhm`).
const String kVerdictRefinementInstruction =
    'The `$kVerdictRefinementKey` field is OPTIONAL and NEVER grades. Put every '
    'BEAD-GRAPH observation there — a duplicate bead, a dep edge pointing at the '
    'wrong id, tracker hygiene — and nowhere else. Those are TRACKER STATE: they '
    'are real, they are worth filing, and they are not the spec author\'s '
    'defect, so they must not move your letter by one band. The station routes '
    'this field to REFINEMENT (an operator flag), never to a round failure. '
    'Omit the key when you have no such observation.';

/// The verdict JSON's MODEL-AUTHORED round stamp key.
///
/// The critic copies the round from its prompt into [kVerdictRoundKey]
/// ([kVerdictStampInstruction]). When that copy is WRONG, the capability
/// rewrites [kVerdictRoundKey] to the engine-injected round and PRESERVES what
/// the model wrote here — so a contaminated stamp stays visible in the artifact
/// (and in the `critic.verdictRoundRestamped` flare) instead of being erased.
const String kVerdictModelRoundKey = 'model_round';

/// A4's FOREIGN-NODE fence refused the artifact: its `nodePath` stamp names a
/// step other than the one reading it (a stray or mis-keyed write).
const String kVerdictNodePathMismatch = 'nodePath mismatch';

/// A15(5) alt-A's ROUND fence refused the artifact: its `round` stamp names an
/// EARLIER round than the one reading it (a file that survived a rework on the
/// reused worktree).
const String kVerdictRoundPinMismatch = 'round-pin mismatch';

/// The strict decoder refused the artifact's SHAPE — the detail that follows is
/// the parser's own.
const String kVerdictShapeCheckFailed = 'shape check failed';

/// No current-round artifact exists at the canonical path at all.
const String kVerdictArtifactAbsent = 'no current-round verdict artifact';

/// The directory holding each critic lane's INCARNATION MARKER — deliberately
/// OUTSIDE `.grid/critique/`, which [sweepStaleCritique] empties at every round
/// start. A marker that survives an unrelated round is harmless: only a
/// [CriticCapability.spawn] can precede a probe, and every spawn rewrites it.
const String kCriticIncarnationDir = '.grid/critique-incarnation';

/// The incarnation marker for [rubric] under [workspaceDir]: the file whose
/// mtime IS this critic incarnation's spawn instant.
///
/// Written by [CriticCapability.recordCriticIncarnation] at the spawn edge and
/// read by [restampVerdictRound] as the proof that a verdict file on disk was
/// written by THIS incarnation rather than left behind by an earlier one. Keyed
/// by RUBRIC, exactly like the canonical verdict it fences (the three critic
/// families' rubric sets are disjoint, so one key is enough).
String criticIncarnationPath(String workspaceDir, String rubric) =>
    p.join(workspaceDir, kCriticIncarnationDir, '$rubric.spawn');

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
  bool owner = false,
  bool refinement = false,
}) =>
    '{"rubric":"$rubric","version":1,"grade":"<A-F>",'
    '"rationale":"$rationaleHint",'
    '${owner ? '"$kVerdictOwnerKey":"<$kOwnerArchitect|$kOwnerAuthor>",' : ''}'
    '${refinement ? '"$kVerdictRefinementKey":"<bead-graph findings; omit when none>",' : ''}'
    '"nodePath":"$nodePath",'
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

/// The OWNER instruction the SPEC critic prompt writes after
/// [kVerdictStampInstruction] (bead `pow-hxme`). Only the family that is TAUGHT
/// ownership is HELD to it ([CriticCapability.requiresVerdictOwner]).
const String kVerdictOwnerInstruction =
    'The `$kVerdictOwnerKey` field is REQUIRED whenever your grade is `D` or '
    '`E` (on any other grade it is ignored — you may drop the key). It answers '
    'ONE question: WHO can fix this? Write `$kOwnerArchitect` when the fix is '
    'derivable from the bead AS WRITTEN plus the tree — re-running the specify '
    'stage with your rationale would produce it. Write `$kOwnerAuthor` when the '
    'fix needs a decision the bead TEXT does not make: which sibling\'s symbol '
    'names win, whether the scope splits, which of two designs is wanted, a '
    'policy call. An `$kOwnerAuthor` verdict SPENDS NO auto-correction round — '
    'it parks the bead immediately for the human who owns it — so name the '
    'CHOICE and its options in your rationale, not just the defect. A `D` or '
    '`E` carrying no owner is discarded as an unverifiable verdict; the lane '
    'fails and re-runs.';

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

/// WHERE a lens is asked to leave its answer — the ONE axis that differs
/// between the in-pipeline circuits and the filing verbs' pre-stamp advisory.
///
/// Sealed on purpose, and consumed with an exhaustive `switch`: a prompt
/// builder that gained a third destination without answering for it would ship
/// a lens that writes its verdict somewhere nobody reads. Everything ELSE about
/// a lens — its rubric, its prompt body, its verdict schema version, its
/// evidence bounds — is transport-invariant, which is what lets the spec-review
/// route and the pre-stamp advisory share one implementation instead of
/// growing a second lens apiece.
sealed class LensResultTransport {
  /// Creates a transport arm.
  const LensResultTransport();
}

/// The CIRCUIT arm: the lens writes its answer to a stamped file in the
/// worktree, and a route reads it back through the shared freshness fence.
///
/// This is the in-pipeline transport every committee, critic and discovery
/// lens has always ridden. It is what makes a verdict durable across a lane
/// restart, and what a round's join reads.
final class LensArtifactTransport extends LensResultTransport {
  /// Creates the artifact arm.
  const LensArtifactTransport();
}

/// The IN-PROCESS arm: the lens writes NO file and returns its answer as the
/// last JSON value in its reply, which the caller reads off captured stdout.
///
/// Used by the filing verbs' pre-stamp advisory, which runs OUTSIDE any
/// session: it has no node path to key an artifact to, no round to stamp it
/// for, and — deliberately — nothing a spec-review route could ever mistake
/// for a published verdict. A lens spawned on this arm also runs with no usage
/// capture, so its whole answer arrives on stdout.
final class LensInProcessTransport extends LensResultTransport {
  /// Creates the in-process arm.
  const LensInProcessTransport();
}

/// The IN-PROCESS transport's closing instruction — the exact counterpart of
/// [verdictWriteInstruction], and the one paragraph a pre-stamp prompt says
/// differently from the circuit prompt it otherwise shares byte-for-byte.
///
/// It is as emphatic about writing NOTHING as the artifact arm is about
/// writing the file: an advisory that left a verdict on disk could collide
/// with the round artifact a later spec-review lane reads.
const String kInProcessResultInstruction =
    'Emit that JSON as the LAST thing in your reply, and write NO file. There '
    'is no verdict path for this run: you are a PRE-FLIGHT advisory outside '
    'any session, your answer is read from your reply text alone, and a file '
    'you write here would be read by nothing. Do NOT create, move or replace '
    'any file, and do NOT run any command that would.';

/// The pluggable critique-dir hygiene seam [ClearCritiqueCapability] uses
/// (D-9-style injection, mirrors [RubricSource]) — defaults to the real
/// delete+recreate; tests inject a no-op so the offline suite never touches a
/// real filesystem at a synthetic workspace path.
typedef DirectoryClearer = void Function(String dir);

/// The adversarial code-committee circuit (id `code_review`) — a hygiene step
/// (gate-integrity #3, [ClearCritiqueCapability]) → a diff-pinning pre-critic
/// step (bead `pow-6wo`, [PinDiffCapability]) → the DETERMINISTIC FRONTIER
/// ([kFormatCleanStep] + [kDeclaredTestsRubric], fanned out in parallel) → four
/// critic lanes fanned out in parallel → a `route` step that joins on all four
/// and aggregates their grades (M5 Track C / C1).
///
/// **The deterministic frontier (bead `pow-jicn`)**: [kFormatCleanStep] and
/// [kDeclaredTestsRubric] are cheap, agent-free checks over the pinned scope, so
/// they run BEFORE the priced lanes and every critic `dependsOn` BOTH. A
/// [FormatCleanCapability] refusal therefore withholds all four critics —
/// including the three inference ones — instead of letting a diff CI would
/// refuse in one second consume a full committee round first.
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
      stepId: kFormatCleanStep,
      capabilityId: kFormatCleanStep,
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kDeclaredTestsRubric,
      capabilityId: kDeclaredTestsRubric,
      dependsOn: {kPinDiffStep},
    ),
    // The DETERMINISTIC validation lane — bound to its OWN service capability
    // (never the `critic` process family): it compares the bead's Validation
    // Plan against the merge base and gates only on the difference. The step id
    // is UNCHANGED (it is a persisted cursor key); only the binding moved.
    CapabilityStep(
      stepId: kGatingRubric,
      capabilityId: kGatingRubric,
      params: {'rubric': kGatingRubric},
      dependsOn: {kFormatCleanStep, kDeclaredTestsRubric},
    ),
    CapabilityStep(
      stepId: 'spec-adherence',
      capabilityId: 'critic',
      params: {'rubric': 'spec-adherence'},
      dependsOn: {kFormatCleanStep, kDeclaredTestsRubric},
    ),
    CapabilityStep(
      stepId: 'regression-risk',
      capabilityId: 'critic',
      params: {'rubric': 'regression-risk'},
      dependsOn: {kFormatCleanStep, kDeclaredTestsRubric},
    ),
    CapabilityStep(
      stepId: 'test-coverage',
      capabilityId: 'critic',
      params: {'rubric': 'test-coverage'},
      dependsOn: {kFormatCleanStep, kDeclaredTestsRubric},
    ),
    // The SHADOW committee selector (bead `pow-1nl.1.1`) — a NON-AUTHORITATIVE
    // sibling of the priced lanes, not a dependency of any of them and not a
    // dependency of the route. It reads the pinned scope the critics read, asks
    // which lanes this change would actually have needed, and records the
    // answer. Nothing waits for it, so it can never withhold a committee round;
    // it produces no grade, so it can never move one.
    CapabilityStep(
      stepId: kCommitteeSelectionStep,
      capabilityId: kCommitteeSelectionStep,
      dependsOn: {kPinDiffStep},
      params: {
        kCommitteeSelectionStageParam: 'code_review',
        kCommitteeFullRubricsParam:
            'code-validation,declared-tests-present,spec-adherence,regression-risk,test-coverage',
        kCommitteeGatingRubricsParam: 'code-validation,declared-tests-present',
      },
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
        // The stage the SHADOW receipt is filed under. The route's own matrix
        // never reads it (bead `pow-1nl.1.1`).
        kCommitteeSelectionStageParam: 'code_review',
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
/// The base it measures against is [reviewBaseRef] — the provisioner's
/// recorded cut point when the workspace carries one, else `origin/<base>` —
/// resolved ONCE and fed to every probe below and to the pinned header, so the
/// artifact the critics read always names the base it was computed from.
///
/// This step computes that delta once, up front:
///  - `git log --oneline <base>..HEAD` — the commit list under review
///    (provenance);
///  - `git diff <base>...HEAD` — the branch's own change from the MERGE-BASE
///    (three-dot: a base that moved forward while the bead ran can never widen
///    the scope), pinned to [pinnedDiffPath] for the critics.
///
/// Three terminals:
///  - **EMPTY delta ⇒ [Escalate]** — the distinct no-op outcome. A branch with
///    no reviewable change routes to a human ruling INSTEAD of reaching the
///    critics (a stale bead whose work is already in mainline, or a net-zero
///    diff). The critics `dependsOn` this step, so the escalation withholds them
///    — they never run against a scope that isn't the bead's. An empty delta
///    over ZERO commits is disambiguated by `git status --porcelain` FIRST: a
///    DIRTY worktree there is uncommitted work, not staleness, and says so —
///    the live genesis-7ob round ruled a finished, validation-green, merely
///    uncommitted tree a 'stale/no-op bead'. An unreadable status is LOUD.
///  - **git could not compute the delta ⇒ a thrown [RouteFailure]** — LOUD. An
///    unresolvable base — a bad ref, or a recorded SHA this checkout does not
///    hold — (or a `git` that won't launch) means the scope is UNKNOWN; failing
///    closed routes to supervision rather than silently escalating (a false
///    stale-bead flag) or silently advancing (critics with an empty scope).
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
    final baseRef = reviewBaseRef(workspace);

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
      // ZERO commits is NOT automatically a stale bead. A build agent whose
      // turn ended before the commit it had announced leaves the entire change
      // sitting UNCOMMITTED in the worktree — the live genesis-7ob round, where
      // a provider capacity refusal ended the turn, the tree was green and
      // complete, and the human ruling still read 'stale/no-op'. Ask the
      // worktree which of the two it is before naming it.
      if (commits.isEmpty) {
        final status = await runner.run(
          workingDirectory: workspaceDir,
          args: ['status', '--porcelain'],
        );
        if (args.cancel.isCancelled) throw kRouteCancelled;
        // The tree state is UNKNOWN — and both rulings below are claims ABOUT
        // that state. Fail LOUD rather than guess one of them.
        if (!status.ok) {
          throw RouteFailure(
            'pin-diff: could not read `git status --porcelain` in '
            '$workspaceDir — ${_reasonTail(status.output)}',
          );
        }
        if (status.output.trim().isNotEmpty) {
          return Escalate(
            'pin-diff: uncommitted work present — the branch has ZERO commits '
            'beyond $baseRef, but its worktree is DIRTY, so the work was DONE '
            'and never committed (a turn that ended before its commit). This '
            'is neither stale nor a no-op. Routed for a human ruling; the diff '
            'the critics would review does not exist yet.',
          );
        }
      }
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
///    agents), on the **MID tier** ([AgentTier.mid], bead `pow-2c9`): the
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
    // The out-of-band flare sink (D-8, emit-only). This is an EFFECT edge, so
    // the non-binding verb is correct (ADR-0008 D3); absent ⇒ no flares, never
    // a failure. Read at ENTRY, before the first `await`: the sink is captured
    // while the context is provably mounted, so no read of it crosses an async
    // gap.
    final transport = context
        .getInheritedSeedOfExactType<ServiceBundle>()
        ?.transport;
    final workspaceDir = workspace.workspaceDir;
    try {
      final round = verdictRound(args);
      // Nico, 2026-09-01 — keep the clause, change the writer: the round stamp
      // is MODEL-authored, so correct it to the engine-injected round BEFORE
      // the ratified A15(5) alt-A fence reads it — but only on a file THIS
      // incarnation provably wrote.
      final restamp = restampVerdictRound(
        workspaceDir: workspaceDir,
        rubric: rubric,
        nodePath: args.nodePath,
        round: round,
      );
      if (restamp is RoundRestampApplied) {
        transport?.flare('critic.verdictRoundRestamped', {
          'rubric': rubric,
          'nodePath': args.nodePath,
          'round': '$round',
          kVerdictModelRoundKey: restamp.modelRound,
        });
      }
      final durable = currentVerdictOnDisk(
        workspaceDir: workspaceDir,
        rubric: rubric,
        nodePath: args.nodePath,
        round: round,
      );
      if (durable != null) return GateOutcome.clear;

      final recovered = verdictFromResultText(
        readEnvelopeResultText(workspaceDir, args.nodePath),
      );
      if (recovered == null) {
        // The engine now holds the lane on its completion-artifact contract.
        // Flare WHY, so an operator reading a held session attributes the hold
        // to THIS probe instead of misreading the engine's contract message as
        // a lane verdict.
        transport?.flare('critic.verdictProbeUnresolved', {
          'rubric': rubric,
          'nodePath': args.nodePath,
          'round': '$round',
          'fileRound': restamp.fileRound,
          'restamp': switch (restamp) {
            RoundRestampSkipped(:final reason) => 'skipped: $reason',
            RoundRestampUnchanged() => 'unchanged',
            RoundRestampApplied() => 'applied',
          },
          'strayTried': 'true',
          'envelopeTried': 'true',
        });
        return GateOutcome.present;
      }

      final canonical = File(
        p.join(workspaceDir, _critiqueDir, '$rubric.json'),
      );
      await canonical.create(recursive: true);
      final recoveredOwner = recovered[kVerdictOwnerKey];
      final recoveredRefinement = recovered[kVerdictRefinementKey];
      await canonical.writeAsString(
        jsonEncode({
          'grade': recovered['grade'],
          'rationale': recovered['rationale'],
          if (recoveredOwner != null) kVerdictOwnerKey: recoveredOwner,
          if (recoveredRefinement != null)
            kVerdictRefinementKey: recoveredRefinement,
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
    } on CapabilityFailure {
      // The strict decoder already NAMED this failure's kind and bounded its
      // receipt: a malformed completion contract is an `invalidResult`, and
      // flattening it into the fail-closed `probeError` would spend the whole
      // circuit's restart budget on it and read to an operator like an F.
      rethrow;
    } on RouteFailure {
      return GateOutcome.probeError;
    } on Object {
      return GateOutcome.probeError;
    }
  }

  /// EVERY critic lane's invalid-artifact budget — declared once so the gating
  /// rubric's tighter `noResult` policy cannot drift it ([supervisionPolicy]
  /// names the reasoning for both).
  static const RetryPolicy _criticInvalidResultRetry = RetryPolicy(
    maxRestarts: 2,
    backoff: Backoff.standard,
    onExhaustion: ExhaustionBehavior.parkAtGate,
  );

  /// Gives an invalid critic artifact one repair restart before a visible gate.
  ///
  /// The engine tests exhaustion after incrementing the restart cursor, so
  /// [RetryPolicy.maxRestarts] of two means one initial attempt plus one
  /// repair. This conservative bound and [Backoff.standard] remain in force
  /// until tg-5drf supplies retained invalid-output and retry distributions.
  ///
  /// Only `invalidResult` is declared: `work` (a real F) and `noResult` (no
  /// artifact at all) keep the circuit's own budget, so a broken completion
  /// CONTRACT is the only thing this narrows. A re-prompted model legitimately
  /// might not repeat itself.
  ///
  /// The DETERMINISTIC `code-validation` lane's own tighter budget moved with
  /// it to [CodeValidationCapability]: this family is now exclusively the three
  /// model critics.
  @override
  SupervisionPolicy supervisionPolicy(StepArgs args) => const SupervisionPolicy(
    byKind: {CapabilityFailureKind.invalidResult: _criticInvalidResultRetry},
  );

  /// Stamps THIS incarnation's spawn instant for [rubric] under [workspaceDir]
  /// — the marker [restampVerdictRound] reads as its freshness proof.
  ///
  /// Called at the spawn edge by every critic family (this class and the
  /// `SpecCriticCapability` / `ReadinessCriticCapability` overrides), BEFORE
  /// the critic process can write anything, so a verdict file at or after this
  /// mtime is provably this incarnation's.
  ///
  /// BEST-EFFORT, exactly like [ClearCritiqueCapability]'s sweep and for the
  /// same reason: a marker that cannot be written only costs the re-stamp, and
  /// the ratified A15(5) alt-A fence then judges the file exactly as it does
  /// today (fail-closed, never fail-open). It is not silent — the probe's
  /// `critic.verdictProbeUnresolved` flare reports `no incarnation marker`, so
  /// the degradation is traceable. The offline suite's synthetic workspace
  /// dirs take this path.
  @protected
  void recordCriticIncarnation({
    required String workspaceDir,
    required String rubric,
  }) {
    try {
      File(criticIncarnationPath(workspaceDir, rubric))
        ..createSync(recursive: true)
        ..writeAsStringSync(DateTime.now().toUtc().toIso8601String());
    } on Object {
      // Best-effort — see the doc comment above: the ratified round fence is
      // the fail-closed backstop.
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
    // Stamp THIS incarnation before the agent can write its verdict, so the
    // probe can prove a file on disk is ours.
    recordCriticIncarnation(
      workspaceDir: workspace.workspaceDir,
      rubric: rubric,
    );
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
      tier: AgentTier.mid,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
      // Rung 4.5 - the CRITIC seat, routed by this lane (ADR-0006 D4). One
      // mounted value sends `decision-alignment` and `coherence` to different
      // environments; an unrouted lane rides the seat's shared entries.
      typedEnvironment: CriticAgentEnvironment.of(
        context,
        lane: CriticLane(rubric),
      ),
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

  /// Whether THIS critic family's verdicts must NAME an owner
  /// ([kVerdictOwners]) on an actionable `D`/`E` grade — bead `pow-hxme`
  /// (ADR-0000 A37). FALSE here and TRUE in `SpecCriticCapability`: only the
  /// SPEC route ACTS on ownership (an author-owed lane parks instead of
  /// auto-respec'ing), and only the spec critic is TAUGHT the column
  /// ([kVerdictOwnerInstruction]) — a family held to a contract its prompt
  /// never states is the A19 trap.
  @protected
  bool get requiresVerdictOwner => false;

  /// Returns a corrective instruction when the canonical artifact from a prior
  /// failed attempt violated the verdict contract. Engine supervision restarts
  /// the failed process lane under [supervisionPolicy]'s invalid-result budget;
  /// the restarted [spawn] appends this instruction without replacing the
  /// lease-vended allocation. The instruction carries the SAME bounded receipt
  /// the engine was handed ([_InvalidVerdictFailure]), so the repairing critic
  /// reads exactly what the operator does.
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
      requireOwner: requiresVerdictOwner,
      readText: _verdictTextReader,
    );
    final reason = switch (read) {
      _VerdictFileInvalid(:final path, :final detail) => _InvalidVerdictFailure(
        rubric: rubric,
        artifactPath: path,
        detail: detail,
      ).reason,
      _VerdictFileUnstamped(:final reason) => reason,
      _ => null,
    };
    return reason == null
        ? ''
        : '\n\n## Verdict contract repair\n'
              'The previous artifact was refused: $reason\n'
              'Replace it once with strict JSON carrying grade, rationale, '
              'nodePath, round, and — on a D or E — owner. Do not recover a '
              'grade from prose.';
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) {
    // Every lane in this family is an LLM critic now, so the standard job
    // mapping is the whole rule: a clean exit completes, a non-zero exit or a
    // death fails. (The deterministic `code-validation` lane's watchdog arm is
    // GONE with the lane — it is a [ServiceCapability] that bounds its own
    // plan, so no runtime event ever describes it.)
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
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) {
      throw StateError(
        'CriticCapability.result requires the ambient Workspace '
        '(SessionScope mounts it)',
      );
    }
    final workspaceDir = workspace.workspaceDir;
    // The FT-2 usage merge's two ambient reads, taken HERE with the rest — the
    // declared prices (a config VALUE) and the emit-only flare sink (an
    // injected IMPL). Non-binding verb: `result()` is an effect, not a build
    // (ADR-0008 D3).
    final prices =
        (context.getInheritedSeedOfExactType<AgentConfig>() ??
                const AgentConfig())
            .modelPrices;
    final transport = context
        .getInheritedSeedOfExactType<ServiceBundle>()
        ?.transport;
    // Resolve the engine-injected circuit round once at entry so every
    // transport for this result carries the same freshness stamp.
    final round = verdictRound(args);
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
            requireOwner: requiresVerdictOwner,
            readText: _verdictTextReader,
          ),
          rubric: rubric,
        ) ??
        _payloadOrNull(
          _strayVerdict(
            workspaceDir,
            rubric,
            args.nodePath,
            round,
            requireOwner: requiresVerdictOwner,
          ),
          rubric: rubric,
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
    final usage = readUsageFields(
      workspaceDir,
      args.nodePath,
      modelPrices: prices,
      flare: transport?.flare,
    );
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
      );
    // The spec committee may have ADVANCED this bead's spec carrying ONE open
    // finding (bead `pow-bhm`, ratified 2026-07-18) — BINDING on the build under
    // review, so the code committee is the lane that re-checks it. Absent (the
    // ordinary case, an offline/dry-run worktree, or an unreadable carry) the
    // prompt is byte-identical to the pre-`pow-bhm` one.
    final carried = readFixInFlight(workspaceDir);
    if (carried != null) {
      b
        ..writeln()
        ..writeln(renderFixInFlightRecheck(carried));
    }
    b
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

/// The route/aggregate step — a [ServiceCapability] that joins its sibling
/// critics' grades and applies the deterministic matrix (C3, asset policy).
///
/// **The grade SOURCE (decision
/// `review-route-uses-persisted-verdict-artifacts`).** A JUDGEMENT lane's
/// grade is read from the artifact the lane itself persisted —
/// `.grid/critique/<rubric>.json`, through [_reviewRouteVerdictOnDisk], the
/// same [_verdictFromFile] parser and the same `nodePath` + `round` fences the
/// lane wrote with — so the route and the lane are ONE value. A DETERMINISTIC
/// gating lane writes no verdict JSON (`code-validation` leaves an rc; the
/// docs committee's three are pure checks), so its grade rides its own step
/// result through the AMBIENT [SiblingView] (mounted by `SessionScope`; read
/// with the effect verb — D-5, never a subscription/re-query); so does every
/// lane in the offline posture, where there is no real worktree and therefore
/// no artifact to read. The live incident this closes: `regression-risk`
/// persisted grade `B`, and the route escalated `a critic returned F` seven
/// seconds later off a different channel.
///
/// The matrix:
///
///  - a GATING lane at grade `F` (a non-zero Validation Plan) → [Escalate]
///    (hard block). `gating` is a lane SET read as a CSV, so a committee whose
///    gate is several deterministic checks (the docs committee's three) needs
///    no second matrix — a single-id value is just a one-element set;
///  - any NON-gating critic at `F` → [Escalate] (rework);
///  - TWO or more non-gating critics at an ACTION grade (`D`/`E`) → [Escalate]
///    (rework — the round did not converge on a single carriable finding);
///  - a single `E` → [Escalate] (rework: this committee has no auto-correction
///    arm downstream of the build, so an `E` parks);
///  - a single `D` with NO rationale → [Escalate] (there is nothing to carry);
///  - a single `D` WITH a rationale → [Advance] carrying `fix_in_flight` +
///    `fix_in_flight_finding` (`rule` = `single-finding-advance`);
///  - else (all A–C, gating not F) → [Advance] `all-approve` (on to delivery).
///
/// **The re-tuned matrix** (policy Nico-ratified 2026-07-18, interactive
/// session; recorded as the `docs/decisions/` entry
/// `committee-gate-single-finding-advance-and-the-refinement-flag`): hard-gate
/// ONLY on `F` or on two-plus action lanes. A single finding rides the build
/// instead of burning a full rework cycle, and the committee re-checks it at
/// review — every catch keeps its value. This DEPARTS from ratified A14(2),
/// which left this route byte-unchanged for the code committee; the ratified
/// policy names both routes explicitly, and the departure is recorded in that
/// entry. The `spread ≥ 3` "human ultimatum" rule is GONE for A14(4)'s own
/// reason — a spread of 3+ necessarily puts some lane at `D` or worse, so the
/// arms above already cover every case it caught.
///
/// The [Advance] payload carries ROUTE PROVENANCE (FT-2, CAPTURE-ONLY): the
/// grade vector consumed (`grades` — `lane=grade` CSV in [kCommitteeRubrics]
/// order), the computed `spread`, the matrix arm that fired (`rule`), and — on
/// the single-finding arm — the carried lane and its rationale verbatim — making
/// the keep/kill export self-contained without changing the matrix. Escalations
/// are UNCHANGED (their reason string already names the rule).
///
/// Fail-closed, in two shapes. A missing grade on a lane joined through its
/// step result is treated as `F`, so a forged or absent grade can NEVER advance
/// (the mutation-tested property). A judgement lane whose own artifact is
/// absent, malformed, unstamped, foreign-node or PRIOR-round is HELD instead:
/// the route has no grade for it and refuses to invent one, so the gate reads
/// as the artifact fault it is — naming the lane, the failed check and the
/// exact path — rather than as a critic's `F`. Only a grade a critic actually
/// wrote routes as `a critic returned F`, and that escalation NAMES the file it
/// was read from.
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
    // Read the ambient values at ENTRY (while mounted); the matrix below is
    // pure over the captured values. The [Workspace] joins the sibling view
    // here because the LIVE join reads each judgement lane's own artifact off
    // disk (see the class doc's grade-SOURCE contract).
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
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

    final dir = workspace?.workspaceDir;
    final live = dir != null && dir.isNotEmpty && Directory(dir).existsSync();
    // The round is the ARTIFACT fence's input; offline there are no artifacts
    // to fence, so the resolve (and its missing-key diagnostic) is live-only.
    final round = live ? verdictRound(args) : 0;

    // THE JOIN. Read each lane's RAW grade once (null/empty ⇒ missing), its
    // rationale, and — for a lane read off disk — the artifact path that
    // SOURCED the grade.
    //
    // A DETERMINISTIC gating lane writes no verdict JSON (`code-validation`
    // leaves an rc; the docs committee's three are pure checks), so its grade
    // rides its own step result, and a missing one still fail-closes to a hard
    // block below. Every JUDGEMENT lane in a live workspace joins ONLY through
    // its own current-round artifact, through the SAME single reader and the
    // SAME two fences the lane wrote with. Offline (no real worktree) there are
    // no artifacts at all, so every lane joins off the sibling view — the same
    // no-op posture the ledger and critique I/O take.
    final rawGrades = <String, String?>{};
    final rationales = <String, String>{};
    final sources = <String, String>{};
    final unread = <String>[];
    for (final id in criticIds) {
      if (!live || gating.contains(id)) {
        final recorded = siblings.resultOf('$parent/$id');
        rawGrades[id] = recorded['grade'];
        rationales[id] = (recorded['rationale'] ?? '').trim();
        continue;
      }
      switch (_reviewRouteVerdictOnDisk(
        workspaceDir: dir,
        rubric: id,
        nodePath: '$parent/$id',
        round: round,
      )) {
        case _VerdictFileAccepted(:final path, :final payload):
          rawGrades[id] = payload['grade'];
          rationales[id] = (payload['rationale'] ?? '').trim();
          sources[id] = path;
        case _VerdictFileInvalid(:final path, :final detail):
          unread.add('$id — $kVerdictShapeCheckFailed at $path: $detail');
        case _VerdictFileUnstamped(:final path):
          unread.add(
            '$id — missing the freshness stamp (nodePath/round) at $path',
          );
        case _VerdictFileRejected(:final path, :final detail):
          unread.add('$id — $detail at $path');
        case _VerdictFileMissing():
          unread.add(
            '$id — $kVerdictArtifactAbsent at '
            '${p.join(dir, _critiqueDir, '$id.json')}',
          );
      }
    }
    final grades = <String, String>{
      for (final entry in rawGrades.entries)
        entry.key: _normalizeGrade(entry.value),
    };

    // 1. THE DELTA GATE. `code-validation` and `declared-tests-present` are
    // MACHINE-READABLE now: each carries its own decided evidence (a JSON array
    // of regression names; a JSON array of missing declared paths), and the
    // route decides on THAT, not on a letter it would have to re-interpret
    // (`power_station#code-validation-hard-blocks-only-branch-regressions`).
    // Strict: a lane that is present but whose evidence cannot be decoded is a
    // fail-closed lane NON-RESULT, never a silent advance.
    //
    // A lane that recorded NOTHING AT ALL is not an undecodable payload — it is
    // the fail-closed MISSING grade the letter rule already gates on, and it
    // keeps that gate's byte-identical reason.
    final validationResult = siblings.resultOf('$parent/$kGatingRubric');
    final _LaneEvidence? validation =
        gating.contains(kGatingRubric) &&
            rawGrades.containsKey(kGatingRubric) &&
            validationResult.isNotEmpty
        ? _validationEvidence(validationResult)
        : null;
    if (validation is _UndecodableEvidence) {
      return Escalate(
        '$kGatingRubric returned no decodable delta '
        '(${validation.detail}) — the route has no regression set to gate on. '
        'Resolve the lane artifact.',
      );
    }
    final decodedValidation = validation is _DecodedValidation
        ? validation
        : null;

    // A DECLARED test path the branch did not touch stops gating once the
    // comparison PROVED that exact path already fails at the merge-base: the
    // declaration policy is untouched
    // (`power_station#declared-tests-evidence-is-scoped-to-the-path-it-governs`
    // — an authored path is a promise whatever the base holds), and only
    // runtime-confirmed pre-existing failure evidence removes a path from the
    // route's residual hard-block set.
    final declaredResult = siblings.resultOf('$parent/$kDeclaredTestsRubric');
    final declaredMissing =
        gating.contains(kDeclaredTestsRubric) &&
            rawGrades.containsKey(kDeclaredTestsRubric) &&
            declaredResult.isNotEmpty
        ? _declaredMissingEvidence(declaredResult)
        : null;
    if (declaredMissing is _UndecodableEvidence) {
      return Escalate(
        '$kDeclaredTestsRubric returned no decodable missing-path set '
        '(${declaredMissing.detail}) — the route has nothing to gate on. '
        'Resolve the lane artifact.',
      );
    }
    final residualMissing = declaredMissing is _DecodedDeclaredMissing
        ? _missingAfterPreexisting(
            missing: declaredMissing.missing,
            preexisting: decodedValidation?.preexisting ?? const [],
          )
        : const <String>[];

    // The gating lanes that actually gate. The two deterministic delta lanes
    // gate on their EVIDENCE; every other gating lane (the spec committee's
    // structural check, the docs committee's three) keeps its letter rule
    // byte-for-byte. The fail-closed property is UNCHANGED throughout: a
    // missing grade still normalises to `F`, and an `F` a delta lane cannot
    // explain with evidence still gates.
    final failedGates = [
      for (final id in gating)
        if (grades.containsKey(id))
          if (switch (id) {
            kGatingRubric when decodedValidation != null =>
              grades[id] == 'F' || decodedValidation.regressions.isNotEmpty,
            // A decided missing set that the comparison PROVED is entirely
            // pre-existing stops gating; an `F` with NO missing paths at all is
            // the lane's own fail-closed refusal and still does.
            kDeclaredTestsRubric
                when declaredMissing is _DecodedDeclaredMissing =>
              grades[id] == 'F' &&
                  (residualMissing.isNotEmpty ||
                      declaredMissing.missing.isEmpty),
            _ => grades[id] == 'F',
          })
            id,
    ];
    if (failedGates.isNotEmpty) {
      final reasons = <String>[];
      for (final id in failedGates) {
        // EXACTLY the regressions, and the full log. Never the pre-existing
        // names (they are a NOTE, and naming them here is the false-gate prose
        // this bead retired) and never an unfiltered log tail.
        if (id == kGatingRubric &&
            decodedValidation != null &&
            decodedValidation.regressions.isNotEmpty) {
          reasons.add(
            'regressions: ${decodedValidation.regressions.join(', ')}; '
            'full log: $_gatingLogRelativePath',
          );
          continue;
        }
        if (id == kDeclaredTestsRubric && residualMissing.isNotEmpty) {
          reasons.add(
            'Design-declared test files missing from pinned diff: '
            '${residualMissing.join(', ')}',
          );
          continue;
        }
        if (siblings.resultOf('$parent/$id')['rationale'] case final value?
            when value.trim().isNotEmpty) {
          reasons.add(value.trim());
        }
      }
      final suffix = reasons.isEmpty ? '' : ': ${reasons.join('; ')}';
      return Escalate('${failedGates.join(', ')} failed: hard block$suffix');
    }

    // 1b. an ARTIFACT fault on a judgement lane — HELD, never graded. The
    // reader refused (or never found) the lane's own verdict file, so this
    // route has no grade for it and will not invent one: defaulting to the
    // fail-closed `F` here is exactly the false gate this arm exists to end
    // (a lane whose critique JSON says `B` escalating as "a critic returned
    // F"). The reason names the LANE, the failed CHECK, and the exact PATH, so
    // a disagreement between the lane's artifact and the gate is diagnosable
    // from the gate text alone. Still fail-closed — nothing advances — but the
    // fault reads as what it is: an artifact to resolve, not a critic ruling.
    if (unread.isNotEmpty) {
      return Escalate(
        'held: the review route could not read a current-round verdict '
        'artifact for ${unread.length == 1 ? 'a lane' : '${unread.length} '
                  'lanes'} (${unread.join('; ')}). No grade was routed for '
        '${unread.length == 1 ? 'it' : 'them'} — resolve the artifact.',
      );
    }

    // The grade SPREAD across the PRESENT lanes. Missing grades are IGNORED
    // here (they are already caught by the fail-closed gating/F block rules).
    // PROVENANCE ONLY (FT-2) — no arm decides on it any more.
    final indices = [
      for (final entry in rawGrades.entries)
        if (entry.value != null && entry.value!.trim().isNotEmpty)
          _gradeIndex(_normalizeGrade(entry.value)),
    ];
    final spread = indices.isEmpty
        ? 0
        : indices.reduce(math.max) - indices.reduce(math.min);

    // 2. any NON-gating lane at F — the hard, unfixable ruling (bead `pow-bhm`,
    // policy Nico-ratified 2026-07-18: "hard-gate ONLY on F or on two-plus D
    // lanes"). F is the scope/decompose-class judgement or a fail-closed
    // transport miss; neither advances. A MISSING grade normalises to F here,
    // so the fail-closed property is unchanged.
    final failed = [
      for (final entry in grades.entries)
        if (!gating.contains(entry.key) && entry.value == 'F') entry.key,
    ];
    if (failed.isNotEmpty) {
      // NAME the source (AC-2 of the false-F fix): the grade came from THIS
      // file, so a future disagreement between the gate and the lane's own
      // artifact is settled by reading the path the gate printed.
      final readFrom = [
        for (final id in failed)
          if (sources[id] case final path?) path,
      ];
      final source = readFrom.isEmpty
          ? ''
          : '; grade read from ${readFrom.join(', ')}';
      return Escalate(
        'a critic returned F (${failed.join(', ')}) — rework$source',
      );
    }

    // 3. the ACTION set — every non-gating lane at D or E. TWO or more gate;
    // a single E gates (the code committee has no auto-correction arm
    // downstream of the build, so an E parks); a single D ADVANCES below,
    // carrying its finding. The `spread >= 3` "human ultimatum" rule is GONE
    // from this route: a spread of 3+ across A..F necessarily puts some lane at
    // D or worse, so these arms already cover every case it caught — and A14(4)
    // already removed it from the spec route for exactly that reason. The
    // spread rides the advance payload as FT-2 provenance, unchanged. NOTE this
    // arm also CLOSES a pre-existing hole: the deleted loop matched `D`/`F`
    // only, so a lone `E` inside a narrow spread advanced silently.
    final action = [
      for (final entry in grades.entries)
        if (!gating.contains(entry.key) &&
            (entry.value == 'D' || entry.value == 'E'))
          entry.key,
    ];
    if (action.length >= 2) {
      return Escalate(
        'two or more critics returned an action grade '
        '(${action.map((id) => '$id=${grades[id]}').join(', ')}) — rework',
      );
    }
    final single = action.isEmpty ? null : action.single;
    if (single != null && grades[single] == 'E') {
      return Escalate('$single returned E — rework');
    }
    // A carried finding is the RATIONALE, verbatim. A single D that says NOTHING
    // carries nothing, so it cannot advance: LOUD, the same posture the spec
    // route's `no-rationale` arm takes (A14(6)).
    final carried = single == null ? '' : (rationales[single] ?? '');
    if (single != null && carried.isEmpty) {
      return Escalate(
        '$single returned D but NO rationale — there is nothing to carry into '
        'the build as a fix-in-flight item, so the finding would be lost. '
        'Rework.',
      );
    }

    // 4. ADVANCE — a converged join, or a single D whose finding rides along.
    // The payload carries the ROUTE PROVENANCE (FT-2): the per-lane grade vector
    // it consumed (CSV `lane=grade` in kCommitteeRubrics order), the computed
    // spread, the matrix arm that fired, and the carried finding when there is
    // one — so the keep/kill export and the PR digest are self-contained.
    // Escalations keep their reason string (it names the rule).
    final gradesCsv = criticIds.map((id) => '$id=${grades[id]}').join(',');
    return Advance({
      'verdict': 'advance',
      'grades': gradesCsv,
      'spread': '$spread',
      'rule': single == null ? 'all-approve' : 'single-finding-advance',
      if (single != null) 'fix_in_flight': '$single=${grades[single]}',
      if (single != null) 'fix_in_flight_finding': carried,
    });
  }
}

/// One deterministic gating lane's MACHINE-READABLE evidence, as the route
/// decoded it — a decided set, or a named refusal to decide.
///
/// Strict on purpose. The two delta lanes decide on arrays, not letters, so a
/// payload whose array is absent or malformed leaves the route with nothing to
/// gate on; inventing an empty set there would silently advance exactly the
/// round this bead exists to gate, and inventing a full one would reinstate the
/// false block it exists to end.
sealed class _LaneEvidence {
  const _LaneEvidence();
}

/// The code-validation lane's decided delta.
final class _DecodedValidation extends _LaneEvidence {
  const _DecodedValidation({
    required this.regressions,
    required this.preexisting,
  });

  /// Named tests failing on the branch and passing at the merge-base — the
  /// ONLY failures that gate.
  final List<String> regressions;

  /// Named tests failing identically on both sides — evidence, never a gate.
  final List<String> preexisting;
}

/// The declared-tests lane's decided missing-path set.
final class _DecodedDeclaredMissing extends _LaneEvidence {
  const _DecodedDeclaredMissing(this.missing);

  /// Declared test paths absent from the pinned diff.
  final List<String> missing;
}

/// The lane's evidence could not be decoded — [detail] names which field and
/// why, so the held gate is diagnosable from its text alone.
final class _UndecodableEvidence extends _LaneEvidence {
  const _UndecodableEvidence(this.detail);

  /// The named decode failure.
  final String detail;
}

/// Strictly decodes the code-validation lane's `regressions` + `preexisting`
/// arrays out of its step result.
_LaneEvidence _validationEvidence(Map<String, String> result) {
  final regressions = _decodeStringList(result['regressions']);
  if (regressions == null) {
    return const _UndecodableEvidence(
      'regressions is missing or is not a JSON array of strings',
    );
  }
  final preexisting = _decodeStringList(result['preexisting']);
  if (preexisting == null) {
    return const _UndecodableEvidence(
      'preexisting is missing or is not a JSON array of strings',
    );
  }
  return _DecodedValidation(regressions: regressions, preexisting: preexisting);
}

/// Strictly decodes the declared-tests lane's `missing` array out of its step
/// result.
_LaneEvidence _declaredMissingEvidence(Map<String, String> result) {
  final missing = _decodeStringList(result['missing']);
  return missing == null
      ? const _UndecodableEvidence(
          'missing is absent or is not a JSON array of strings',
        )
      : _DecodedDeclaredMissing(missing);
}

/// [raw] decoded as a JSON array of strings, or null on ANY deviation —
/// absent, unparseable, not an array, or an array carrying a non-string.
List<String>? _decodeStringList(String? raw) {
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    if (decoded.any((entry) => entry is! String)) return null;
    return decoded.cast<String>().toList(growable: false);
  } on FormatException {
    return null;
  }
}

/// [missing] minus every declared path a [preexisting] failure PROVES already
/// fails at the merge-base.
///
/// A failing-test name carries its file (`test/x_test.dart 7:5 the case`), so
/// the path it governs is the prefix ending at `_test.dart` — and only when
/// the name carries EXACTLY ONE such token, because two would identify no
/// single file and a guess here would suppress a real gate. The match itself is
/// the gate's own [_endsWithPath] boundary matcher, in either direction: a
/// declaration is repo-relative (`packages/p/test/x_test.dart`) where the
/// runner names its path suite-relative (`test/x_test.dart`), and a boundary
/// match is what makes those the same file without letting `ax_test.dart`
/// answer for `x_test.dart`.
List<String> _missingAfterPreexisting({
  required List<String> missing,
  required List<String> preexisting,
}) {
  final prefixes = [
    for (final name in preexisting)
      if (_failingTestPath(name) case final path?) path,
  ];
  if (prefixes.isEmpty) return List.unmodifiable(missing);
  return List.unmodifiable([
    for (final declared in missing)
      if (!prefixes.any(
        (prefix) =>
            _endsWithPath(prefix, declared) || _endsWithPath(declared, prefix),
      ))
        declared,
  ]);
}

/// The UNIQUE `_test.dart` path a failing-test [name] governs, or null when it
/// names none or more than one.
String? _failingTestPath(String name) {
  const marker = '_test.dart';
  final first = name.indexOf(marker);
  if (first < 0) return null;
  if (name.indexOf(marker, first + marker.length) >= 0) return null;
  final path = name.substring(0, first + marker.length).trim();
  return path.isEmpty ? null : path;
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
///
/// PUBLIC because it is the ONE round-stamp parser this pack owns: the
/// committee's verdict fence ([restampVerdictRound] and the `_verdictFromFile`
/// reader) and the discovery circuit's lens-report fence (`discovery.dart`'s
/// `_freshLensReport`) both read a stamp through it, so the two circuits can
/// never drift on what a round stamp means on the wire.
int? stampedRound(Object? raw) => switch (raw) {
  final num round when round.isFinite && round == round.truncateToDouble() =>
    round.toInt(),
  final String round => int.tryParse(round.trim()),
  _ => null,
};

/// The outcome of the capability-side round re-stamp ([restampVerdictRound]).
///
/// A15(5) alt-A's equality check is UNCHANGED by this union — [_verdictFromFile]
/// still rejects `stampedRound != expectedRound` as STALE. What this reports is
/// WHO wrote the stamp that check reads: the model's copy, or the capability's
/// correction of it.
sealed class RoundRestamp {
  const RoundRestamp(this.fileRound);

  /// The round stamp READ off the verdict file — `''` when there was none to
  /// read (no file, an unparseable file, or no round key).
  final String fileRound;
}

/// The verdict file was left EXACTLY as found: it is absent, unparseable, not
/// provably this incarnation's output, or its round stamp is unusable. The
/// ratified fence then judges it exactly as it does today.
final class RoundRestampSkipped extends RoundRestamp {
  /// Creates a skip carrying its [reason] (flared verbatim) and whatever round
  /// stamp was legible on disk.
  const RoundRestampSkipped(this.reason, {String fileRound = ''})
    : super(fileRound);

  /// Why the file was left untouched.
  final String reason;
}

/// The file was proven fresh and the model's copy already MATCHED the
/// engine-injected round — nothing was rewritten.
final class RoundRestampUnchanged extends RoundRestamp {
  /// Creates the no-op outcome over the (correct) [fileRound].
  const RoundRestampUnchanged(super.fileRound);
}

/// The file was proven fresh and its CONTAMINATED round stamp was rewritten to
/// the engine-injected round; [modelRound] is what the model had written, now
/// preserved in the file under [kVerdictModelRoundKey].
final class RoundRestampApplied extends RoundRestamp {
  /// Creates the applied outcome over the model's [modelRound].
  const RoundRestampApplied(super.modelRound);

  /// The model-authored round, preserved in the file as `model_round`.
  String get modelRound => fileRound;
}

/// Rewrites the canonical `<rubric>.json` round stamp to [round] — the
/// engine-injected `grid.round` read via [verdictRound] — WHEN AND ONLY WHEN
/// the file is provably THIS critic incarnation's output.
///
/// The freshness PROOF is two conjuncts, both required:
///  1. the file's `nodePath` stamp equals [nodePath] (A4's foreign-node fence —
///     never re-stamp another node's file into validity);
///  2. the file's mtime is at or after the incarnation marker's
///     ([criticIncarnationPath]) — this incarnation's spawn instant, stamped
///     before the critic process could write anything.
/// [ClearCritiqueCapability]'s round-start sweep stays the BELT, never the
/// proof (A15(5) alt-A, as ruled 2026-09-01).
///
/// Anything unproven is SKIPPED and the file is left byte-identical, so stale,
/// foreign, missing-round and stray cases reject exactly as they do today.
/// NEVER throws: an IO or decode failure is a [RoundRestampSkipped], leaving the
/// strict-decode contract to [_verdictFromFile], the ONE parser.
RoundRestamp restampVerdictRound({
  required String workspaceDir,
  required String rubric,
  required String nodePath,
  required int round,
}) {
  final verdict = File(p.join(workspaceDir, _critiqueDir, '$rubric.json'));
  final marker = File(criticIncarnationPath(workspaceDir, rubric));
  try {
    if (!verdict.existsSync()) {
      return const RoundRestampSkipped('no canonical verdict file');
    }
    final decoded = jsonDecode(verdict.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return const RoundRestampSkipped('verdict root is not a JSON object');
    }
    final modelRound = stampedRound(decoded[kVerdictRoundKey]);
    final fileRound = modelRound == null ? '' : '$modelRound';
    if (!marker.existsSync()) {
      return RoundRestampSkipped('no incarnation marker', fileRound: fileRound);
    }
    if (verdict.statSync().modified.isBefore(marker.statSync().modified)) {
      return RoundRestampSkipped(
        'verdict predates this incarnation',
        fileRound: fileRound,
      );
    }
    final stampedNodePath = decoded['nodePath'];
    if (stampedNodePath is! String || stampedNodePath.trim() != nodePath) {
      return RoundRestampSkipped(
        'foreign nodePath stamp',
        fileRound: fileRound,
      );
    }
    if (modelRound == null) {
      return const RoundRestampSkipped('no readable round stamp');
    }
    if (modelRound == round) return RoundRestampUnchanged(fileRound);
    // Same-directory atomic replace, the contract the critic itself is held to
    // ([verdictWriteInstruction]) — a reader never sees a half-written verdict.
    final tmp = File('${verdict.path}.restamp')
      ..writeAsStringSync(
        jsonEncode({
          ...decoded,
          kVerdictRoundKey: round,
          kVerdictModelRoundKey: modelRound,
        }),
      );
    tmp.renameSync(verdict.path);
    return RoundRestampApplied(fileRound);
  } on Object {
    return const RoundRestampSkipped('verdict re-stamp failed');
  }
}

sealed class _VerdictFileRead {
  const _VerdictFileRead();
}

final class _VerdictFileAccepted extends _VerdictFileRead {
  const _VerdictFileAccepted(this.path, this.payload);

  /// The artifact this payload was decoded from — the route's grade SOURCE,
  /// named in the gate text so a disagreement is diagnosable from it alone.
  final String path;

  final Map<String, String> payload;
}

final class _VerdictFileMissing extends _VerdictFileRead {
  const _VerdictFileMissing();
}

final class _VerdictFileRejected extends _VerdictFileRead {
  const _VerdictFileRejected(this.path, this.detail);

  /// The refused artifact.
  final String path;

  /// WHICH freshness fence refused it — [kVerdictNodePathMismatch] (A4's
  /// foreign-node fence) or [kVerdictRoundPinMismatch] (A15(5) alt-A's round
  /// fence). A reader that only learns "rejected" cannot tell a stray write
  /// from a surviving prior round.
  final String detail;
}

final class _VerdictFileInvalid extends _VerdictFileRead {
  const _VerdictFileInvalid(this.path, this.detail);

  final String path;
  final String detail;
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

/// A malformed or incomplete verdict artifact, reported through the engine's
/// TYPED non-result seam as [CapabilityFailureKind.invalidResult] — a broken
/// completion CONTRACT, never a substantive `F`.
///
/// The receipt leads with the rubric and the artifact path and only then the
/// parser's own detail, because the engine bounds a reason AT CONSTRUCTION
/// ([kMaxReasonChars]): putting the identity fields first means a long parser
/// detail can be truncated without ever costing an operator the two facts that
/// say WHICH lane and WHICH file to look at.
final class _InvalidVerdictFailure extends CapabilityFailure {
  _InvalidVerdictFailure({
    required String rubric,
    required String artifactPath,
    required String detail,
  }) : super.invalidResult(
         'invalid critic verdict for rubric "$rubric" at $artifactPath: '
         '$detail',
       );
}

Map<String, String>? _payloadOrNull(
  _VerdictFileRead read, {
  required String rubric,
}) => switch (read) {
  _VerdictFileAccepted(:final payload) => payload,
  _VerdictFileMissing() || _VerdictFileRejected() => null,
  _VerdictFileInvalid(:final path, :final detail) =>
    throw _InvalidVerdictFailure(
      rubric: rubric,
      artifactPath: path,
      detail: detail,
    ),
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
/// or incomplete verdict is surfaced through [_payloadOrNull] as an
/// [_InvalidVerdictFailure], so the lease-vended process allocation reports
/// [AllocationFailed] of kind [CapabilityFailureKind.invalidResult] — a broken
/// completion CONTRACT, never a substantive F. Engine supervision restarts the
/// lane under [CriticCapability.supervisionPolicy]'s critic-lane budget, and
/// the next [CriticCapability.spawn] appends
/// [CriticCapability.criticRepairInstruction]. Only absent, stale, or foreign
/// verdicts are misses that can fall through to the stray / RESULT TEXT /
/// fail-closed chain.
_VerdictFileRead _verdictFromFile(
  File verdict, {
  required String expectedNodePath,
  required int expectedRound,
  bool requireOwner = false,
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
    final ownerValue = json[kVerdictOwnerKey];
    final owner = ownerValue is String ? ownerValue.trim().toLowerCase() : '';
    if (owner.isNotEmpty && !kVerdictOwners.contains(owner)) {
      return _VerdictFileInvalid(
        verdict.path,
        '$kVerdictOwnerKey must be one of ${kVerdictOwners.join('|')}',
      );
    }
    if (requireOwner && owner.isEmpty && const {'D', 'E'}.contains(grade)) {
      return _VerdictFileInvalid(
        verdict.path,
        'a grade of $grade REQUIRES $kVerdictOwnerKey '
        '(${kVerdictOwners.join('|')}) — WHO can fix this? An architect-owed '
        'finding auto-respecs; an author-owed one parks for a human.',
      );
    }
    // The NON-GRADING bead-graph column (bead `pow-bhm`) — read AFTER the grade
    // and BEFORE A4's nodePath fence, exactly like `owner` (A37(6)). The read is
    // TOLERANT: a non-String value degrades to '', so this column adds NO second
    // place a verdict can fail its lane (A34(6) — the strict decode above stays
    // the ONE).
    final refinementValue = json[kVerdictRefinementKey];
    final refinement = refinementValue is String ? refinementValue.trim() : '';
    final nodePathValue = json['nodePath'];
    final stampedNodePath = nodePathValue is String ? nodePathValue.trim() : '';
    if (stampedNodePath.isEmpty) {
      return _VerdictFileInvalid(
        verdict.path,
        'nodePath must be a non-empty string',
      );
    }
    final fileRound = stampedRound(json[kVerdictRoundKey]);
    if (fileRound == null) {
      return _VerdictFileInvalid(
        verdict.path,
        'round must be an integer or integer-readable string',
      );
    }
    if (stampedNodePath != expectedNodePath) {
      return _VerdictFileRejected(verdict.path, kVerdictNodePathMismatch);
    }
    if (fileRound != expectedRound) {
      return _VerdictFileRejected(verdict.path, kVerdictRoundPinMismatch);
    }
    return _VerdictFileAccepted(verdict.path, {
      'grade': grade,
      'transport': 'file',
      'rationale': rationale,
      if (owner.isNotEmpty) kVerdictOwnerKey: owner,
      if (refinement.isNotEmpty) kVerdictRefinementKey: refinement,
    });
  } on Object catch (error) {
    return _VerdictFileInvalid(verdict.path, _verdictErrorDetail(error));
  }
}

/// [rubric]'s CANONICAL verdict payload under [workspaceDir], iff it parses AND
/// carries THIS [nodePath] + THIS [round]'s freshness stamps — null for an
/// absent, foreign, or PRIOR-ROUND file. A malformed or incomplete present
/// artifact throws `CapabilityFailure.invalidResult`, naming the rubric, the
/// artifact path, and the parser's own detail.
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
  bool requireOwner = false,
}) => _payloadOrNull(
  _verdictFromFile(
    File(p.join(workspaceDir, _critiqueDir, '$rubric.json')),
    expectedNodePath: nodePath,
    expectedRound: round,
    requireOwner: requireOwner,
  ),
  rubric: rubric,
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
  bool requireOwner = false,
}) =>
    currentVerdictFromFile(
      workspaceDir: workspaceDir,
      rubric: rubric,
      nodePath: nodePath,
      round: round,
      requireOwner: requireOwner,
    ) ??
    _payloadOrNull(
      _strayVerdict(
        workspaceDir,
        rubric,
        nodePath,
        round,
        requireOwner: requireOwner,
      ),
      rubric: rubric,
    );

/// The REVIEW ROUTE's view of [rubric]'s persisted verdict under
/// [workspaceDir] — the same single parser ([_verdictFromFile]), the same two
/// freshness fences, and the same round the lane itself wrote with, so the
/// route and the lane can never hold two different values for one grade.
///
/// It differs from [currentVerdictOnDisk] in ONE way, and that difference is
/// the whole point: a PRESENT canonical artifact is the answer, accepted or
/// REFUSED. [currentVerdictOnDisk] flattens every refusal to `null` and lets
/// the caller's fallback chain continue — which for the route meant a
/// fail-closed `F` while a freshly written critique JSON sat on disk (the live
/// incident this reader exists to end: `regression-risk` graded `B`, routed as
/// `a critic returned F` seven seconds later). Only an ABSENT canonical
/// artifact widens to the [_strayVerdict] belt (gate-integrity #4), because
/// there is then nothing to be superseded.
///
/// The caller renders a refusal as a HELD gate naming the failed check and the
/// path; it never converts one into a grade.
_VerdictFileRead _reviewRouteVerdictOnDisk({
  required String workspaceDir,
  required String rubric,
  required String nodePath,
  required int round,
}) {
  final read = _verdictFromFile(
    File(p.join(workspaceDir, _critiqueDir, '$rubric.json')),
    expectedNodePath: nodePath,
    expectedRound: round,
  );
  if (read is! _VerdictFileMissing) return read;
  return _strayVerdict(workspaceDir, rubric, nodePath, round);
}

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
/// through [RouteFailure] so the process lane retries; a malformed stray fails it
/// through the typed [_InvalidVerdictFailure] instead. Best-effort for directory
/// traversal; parse outcomes remain explicit.
_VerdictFileRead _strayVerdict(
  String workspaceDir,
  String rubric,
  String expectedNodePath,
  int expectedRound, {
  bool requireOwner = false,
}) {
  final canonical = p.canonicalize(
    p.join(workspaceDir, _critiqueDir, '$rubric.json'),
  );
  for (final file in _strayVerdictFiles(workspaceDir, rubric)) {
    if (p.canonicalize(file.path) == canonical) continue; // the canonical path.
    final read = _verdictFromFile(
      file,
      expectedNodePath: expectedNodePath,
      expectedRound: expectedRound,
      requireOwner: requireOwner,
    );
    switch (read) {
      case _VerdictFileAccepted(:final payload):
        return _VerdictFileAccepted(file.path, {
          ...payload,
          'transport': 'file-stray',
        });
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

/// Recovers a verdict from a critic's captured output — the SHARED decoder for
/// every caller that has the lane's answer as TEXT rather than as an artifact.
///
/// Two callers ride it today and they must never drift: the completion probe,
/// which persists the recovery as the canonical durability artifact, and the
/// filing verbs' in-process pre-stamp advisory
/// ([LensInProcessTransport]), which has no artifact at all and reads the
/// harness's stdout directly. A second grade parser beside this one would let
/// the same lens answer two different grades depending on which call site read
/// it, which is exactly the divergence the shared transport stack exists to
/// prevent.
///
/// Returns null for text carrying no well-formed verdict; the caller decides
/// what an unparseable answer means (the probe fails closed, the advisory
/// refuses loudly).
Map<String, String>? verdictFromResultText(String? text) {
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
              final envelopeOwner =
                  (json[kVerdictOwnerKey] as String?)?.trim().toLowerCase() ??
                  '';
              // The bead-graph column survives a transport REPAIR too (bead
              // `pow-bhm`) — A4 fenced three paths and the column rides all of
              // them.
              final envelopeRefinement =
                  (json[kVerdictRefinementKey] as String?)?.trim() ?? '';
              last = {
                'grade': grade,
                'transport': 'envelope',
                'rationale': rationale.isEmpty
                    ? '[from result envelope]'
                    : '$rationale [from result envelope]',
                if (kVerdictOwners.contains(envelopeOwner))
                  kVerdictOwnerKey: envelopeOwner,
                if (envelopeRefinement.isNotEmpty)
                  kVerdictRefinementKey: envelopeRefinement,
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

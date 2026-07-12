/// The PR title/body COMPOSITION and its configurable knob (bead `pow-8dx`).
///
/// **Why**: the landing asset opened every PR as the terse `grid: <bead>` with
/// a receipt-only body (the_grid PR #46's title is literally "grid: tg-6nf"),
/// and [buildCircuitReceipt] WROTE the whole body — clobbering any prose the
/// agent had authored (`pow-yny`, subsumed here). Both halves are fixed at
/// once, per Nico's 2026-07-12 directive:
///
///  - **the TITLE is INFERRED, not templated** — `pr_describe.dart` runs ONE
///    cheap inference pass over the branch's ACTUAL delta and returns a
///    [PrDescription]; [PrComposition.titleOf] renders it through
///    [sanitizeConventionalSubject], so what reaches GitHub is strict
///    Conventional Commits v1.0.0 BY CONSTRUCTION (never the model's raw
///    string). No inference (not wired / offline / failed / unparseable) falls
///    back to a DETERMINISTIC, id-free derivation from the bead
///    ([fallbackSubjectFor]) — the description is decoration, never a land
///    blocker.
///  - **the BODY is a SECTION-composed document** ([PrSection], rendered
///    through ONE exhaustive `switch`): the inferred what/why summary FIRST
///    (composed, never overwritten), then the landing circuit's receipt, the
///    committee's grades, the bead's validation plan, and — LAST — the FOOTERS.
///    A section whose data is absent is OMITTED, never a bare heading.
///  - **the bead id is a git TRAILER, and nowhere else** — `Refs: <bead>` in
///    the trailer block ([PrSection.trailers]). A foreign reference in the
///    subject or the body prose is the exact anti-pattern the policy fixes, so
///    [sanitizeConventionalSubject] strips it from the subject and the describe
///    prompt forbids it in the body.
///
/// [PrComposition] is the knob — a config VALUE a station/substation mounts
/// (`GitHubGridAssets(composition: …)` → `InheritedSeed<PrComposition>`; config
/// = values in the tree, ADR-0008), read by `LandCapability` at its run edge
/// with the non-binding effect verb (ADR-0008 D3). Everything in this library is
/// PURE + deterministic (no I/O); the git reads and the inference call live in
/// `pr_describe.dart` and are threaded in here as DATA.
library;

import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

import 'conventional_commit.dart';
import 'landing.dart';

/// The CHEAP model the one-shot describe pass runs on by default (Nico: "a
/// cheap model is fine" — the call is a single text→JSON completion over a
/// pinned diff, no tool use). Overridable per station via
/// [PrComposition.model].
const String kDefaultDescribeModel = 'haiku';

/// How many off-policy commit subjects the receipt names (the rest are counted,
/// not listed).
const int kMaxLintExamples = 3;

/// The diff the describe prompt carries, capped — a runaway diff must not blow
/// up the inference call's context.
const int kMaxDiffChars = 60000;

/// The bead's own prose the describe prompt carries as WHY-context, capped.
const int kMaxContextChars = 1200;

/// The composable PR-body sections — the landing asset's body is a CONFIGURABLE
/// composition of these (bead `pow-8dx`), rendered through ONE exhaustive
/// `switch` ([renderPrSection]).
enum PrSection {
  /// The INFERRED what/why prose ([PrDescription.body]) — the human-readable
  /// description a reader wants first. Absent inference ⇒ omitted (`pow-yny`:
  /// composed with the provenance below, never clobbered by it).
  summary,

  /// The landing circuit's own provenance ([buildCircuitReceipt] — rebase /
  /// revalidate outcomes) plus this bead's description + commit-policy
  /// provenance lines.
  circuitReceipt,

  /// The code-review committee's route provenance (grades/spread/rule) — MOVED
  /// out of [buildCircuitReceipt] by this bead, at its exact legacy line shape.
  committeeGrades,

  /// The bead's own Validation Plan command (what the gating lane and
  /// `revalidate` actually ran).
  validation,

  /// The FOOTERS, last: the `BREAKING CHANGE:` entry (when the change is
  /// breaking) and the bead-id git trailer (`Refs: <bead>`) — the ONLY place a
  /// foreign reference appears.
  trailers,
}

/// The default section order: the inferred prose leads, provenance follows,
/// trailers close.
const List<PrSection> kDefaultPrSections = [
  PrSection.summary,
  PrSection.circuitReceipt,
  PrSection.committeeGrades,
  PrSection.validation,
  PrSection.trailers,
];

/// What the describe pass INFERRED about the branch's change — the JSON object
/// the model returns, parsed. The asset never renders these strings raw: the
/// title goes through [sanitizeConventionalSubject] (compliant by construction)
/// and the body rides [PrSection.summary].
class PrDescription {
  /// Creates the description.
  const PrDescription({
    required this.type,
    this.scope,
    this.breaking = false,
    required this.description,
    this.body = '',
    this.breakingChange = '',
  });

  /// The conventional-commit type the model chose from the diff.
  final String type;

  /// The scope (the changed area of the code); null ⇒ no scope.
  final String? scope;

  /// Whether the change is BREAKING (`!` + a `BREAKING CHANGE:` footer — each
  /// implies the other; see [PrComposition.subjectOf] / [_trailers]).
  final bool breaking;

  /// The subject's description (imperative, lowercase — re-sanitized anyway).
  final String description;

  /// The PR body prose: WHAT changed + a HIGH-LEVEL WHY, self-contained.
  final String body;

  /// One sentence naming what breaks (the `BREAKING CHANGE:` footer's text).
  final String breakingChange;

  /// Recovers the description from the describe run's raw stdout — the LAST
  /// balanced-brace `{...}` that decodes as JSON carrying a non-blank `type`
  /// AND `description`. LAST, not first: the answer concludes the output, so an
  /// earlier object (an echoed template, a worked example in a preamble) must
  /// never win — the same last-match scan `committee.dart` uses for a critic's
  /// verdict (duplicated rather than shared: that one is private to the
  /// committee's transport stack, and this parse has a different accept
  /// predicate). FAIL-SAFE: `null` for absent/blank/unparseable output — NEVER
  /// a throw.
  static PrDescription? parse(String? stdout) {
    final text = stdout?.trim() ?? '';
    if (text.isEmpty) return null;
    PrDescription? last;
    for (var start = 0; start < text.length; start++) {
      if (text[start] != '{') continue;
      var depth = 0;
      for (var end = start; end < text.length; end++) {
        if (text[end] == '{') depth++;
        if (text[end] != '}') continue;
        depth--;
        if (depth != 0) continue;
        try {
          final decoded = jsonDecode(text.substring(start, end + 1));
          if (decoded is Map) {
            final type = _str(decoded['type']);
            final description = _str(decoded['description']);
            if (type.isNotEmpty && description.isNotEmpty) {
              final scope = _str(decoded['scope']);
              last = PrDescription(
                type: type,
                scope: scope.isEmpty ? null : scope,
                breaking: decoded['breaking'] == true,
                description: description,
                body: _str(decoded['body']),
                breakingChange: _str(decoded['breakingChange']),
              );
            }
          }
        } catch (_) {
          // Not a decodable object at this start — keep scanning.
        }
        break; // Braces balanced for this start; try the next '{'.
      }
    }
    return last;
  }
}

String _str(Object? value) => value == null ? '' : value.toString().trim();

/// The branch's commit-policy report (directive item 5: the policy applies to
/// the COMMITS, not only the PR) — how many of the bead branch's own commits
/// carry a compliant conventional subject, how many carry the bead trailer, and
/// up to [kMaxLintExamples] off-policy examples. Rendered as receipt
/// provenance; never a gate (a lint that blocks a land at the very end would
/// park a DONE, approved bead over prose).
class CommitLintReport {
  /// Creates the report.
  const CommitLintReport({
    this.total = 0,
    this.compliant = 0,
    this.trailered = 0,
    this.violations = const [],
  });

  /// Commits on `origin/<base>..HEAD`.
  final int total;

  /// How many carry a compliant conventional subject.
  final int compliant;

  /// How many carry the bead-id git trailer.
  final int trailered;

  /// Up to [kMaxLintExamples] `` `<subject>` — <first violation> `` examples.
  final List<String> violations;

  /// True when no commits were read (an unreadable log, or the offline
  /// posture) — the receipt then says nothing about commits.
  bool get isEmpty => total == 0;
}

/// Lints the branch's own commit MESSAGES against the policy — the subject
/// through [lintConventionalSubject] (with the bead id as the forbidden
/// foreign reference) and the message through [hasTrailer].
CommitLintReport lintCommitSubjects(
  List<String> messages, {
  required String foreignRef,
  String trailerToken = kDefaultTrailerToken,
}) {
  if (messages.isEmpty) return const CommitLintReport();
  var compliant = 0;
  var trailered = 0;
  final violations = <String>[];
  for (final message in messages) {
    final subject = message.trim().split('\n').first.trim();
    final faults = lintConventionalSubject(subject, foreignRef: foreignRef);
    if (faults.isEmpty) {
      compliant++;
    } else if (violations.length < kMaxLintExamples) {
      violations.add('`$subject` — ${faults.first}');
    }
    if (hasTrailer(message, token: trailerToken)) trailered++;
  }
  return CommitLintReport(
    total: messages.length,
    compliant: compliant,
    trailered: trailered,
    violations: List.unmodifiable(violations),
  );
}

/// The data the title/body composition renders over — gathered by the land step
/// at its run edge and threaded in as VALUES (the renderers stay pure).
class PrCompositionContext {
  /// Creates the context.
  const PrCompositionContext({
    required this.beadId,
    required this.bead,
    this.siblings = const SiblingView(),
    this.description,
    this.commits = const CommitLintReport(),
    this.titleSource = 'fallback',
  });

  /// The node-path root the sibling results key under (`StepArgs.beadId`) AND
  /// the foreign reference the subject/body must never carry.
  final String beadId;

  /// The work definition — the FALLBACK title's source and the describe
  /// prompt's why-context (never a template for the emitted title).
  final Bead bead;

  /// The ambient sibling results (review-route grades, rebase/revalidate).
  final SiblingView siblings;

  /// What the describe pass inferred; null ⇒ the deterministic fallback.
  final PrDescription? description;

  /// The branch's commit-policy report (receipt provenance).
  final CommitLintReport commits;

  /// `inference` | `fallback` — which channel produced the title (receipt
  /// provenance, so a reader never has to guess).
  final String titleSource;
}

/// The PR title/body composition knob (bead `pow-8dx`) — a config VALUE a
/// station/substation mounts (`GitHubGridAssets(composition: …)`) to shape the
/// landing asset's PRs; `LandCapability` reads it at its run edge and falls back
/// to `const PrComposition()` when none is mounted. A plain const class (the
/// A10(3) carrier posture): the TITLE GRAMMAR is policy (not a knob — a station
/// cannot opt out of v1.0.0), while the trailer TOKEN, the body SECTIONS, and
/// the describe MODEL are.
class PrComposition {
  /// Creates the composition; the defaults are the better-by-default shape.
  const PrComposition({
    this.trailerToken = kDefaultTrailerToken,
    this.sections = kDefaultPrSections,
    this.model = kDefaultDescribeModel,
  });

  /// The git-trailer token the bead id rides (`Refs: <bead>`).
  final String trailerToken;

  /// The body sections, rendered in order; empty renders are omitted.
  final List<PrSection> sections;

  /// The model the one-shot describe pass runs on (merged over the AMBIENT
  /// `AgentConfig`'s params at the land step's run edge).
  final String model;

  /// The PR title over [context] — the inferred subject, sanitized to strict
  /// v1.0.0; absent inference ⇒ [fallbackSubjectFor].
  String titleOf(PrCompositionContext context) => subjectOf(context).format();

  /// The title as PARTS (exposed so the tests can assert type/scope/breaking
  /// without re-parsing the rendered line).
  ConventionalSubject subjectOf(PrCompositionContext context) {
    final described = context.description;
    if (described == null) {
      return fallbackSubjectFor(context.bead, foreignRef: context.beadId);
    }
    return sanitizeConventionalSubject(
      type: described.type,
      scope: described.scope,
      // `!` and the `BREAKING CHANGE:` footer imply each other (Nico's rule) —
      // one predicate drives both, so neither can be emitted alone.
      breaking: _isBreaking(described),
      description: described.description,
      foreignRef: context.beadId,
      fallbackType: conventionalTypeFor(context.bead.issueType),
      fallbackDescription:
          fallbackDescriptionFor(context.bead, foreignRef: context.beadId),
    );
  }

  /// The PR body over [context]: each section rendered via [renderPrSection],
  /// empties dropped, joined by a blank line.
  String bodyOf(PrCompositionContext context) => sections
      .map((section) =>
          renderPrSection(section, context, trailerToken: trailerToken))
      .where((rendered) => rendered.trim().isNotEmpty)
      .map((rendered) => rendered.trimRight())
      .join('\n\n');
}

/// Renders ONE section over [context] — '' when its data is absent (an empty
/// render is OMITTED from the composed body, never a bare heading).
String renderPrSection(
  PrSection section,
  PrCompositionContext context, {
  String trailerToken = kDefaultTrailerToken,
}) =>
    switch (section) {
      PrSection.summary => context.description?.body.trim() ?? '',
      PrSection.circuitReceipt => _circuitReceipt(context),
      PrSection.committeeGrades => _committeeGrades(context),
      PrSection.validation => _validation(context),
      PrSection.trailers => _trailers(context, trailerToken),
    };

/// The conventional-commit TYPE a bead's `issueType` derives — the FALLBACK
/// title's type ONLY (the inference picks its own type from the DIFF, which is
/// the whole point of the directive). `IssueType` is an OPEN set (an extension
/// type over the wire string), so an unknown type falls back to `chore` rather
/// than throwing.
String conventionalTypeFor(IssueType issueType) => switch (issueType.wire) {
      'feature' || 'epic' || 'story' => 'feat',
      'bug' => 'fix',
      _ => 'chore',
    };

/// The DETERMINISTIC fallback subject when there is no inference (not wired,
/// offline, a failed run, or unparseable output): type from the bead's
/// `issueType`, scope from its substation (`metadata.rig`), description from
/// its TITLE with the bead id stripped out — id-free, compliant, and never the
/// old `grid: <id>`.
ConventionalSubject fallbackSubjectFor(Bead bead, {required String foreignRef}) =>
    sanitizeConventionalSubject(
      type: conventionalTypeFor(bead.issueType),
      scope: _rigOf(bead),
      description: fallbackDescriptionFor(bead, foreignRef: foreignRef),
      foreignRef: foreignRef,
      fallbackType: conventionalTypeFor(bead.issueType),
    );

/// The fallback description — the bead's title, id-stripped; [kFallbackDescription]
/// for a title-less bead.
String fallbackDescriptionFor(Bead bead, {required String foreignRef}) {
  final title = stripForeignRef(bead.title, foreignRef);
  return title.isEmpty ? kFallbackDescription : title;
}

/// The ONE-SHOT describe prompt (bead `pow-8dx`) — a pure text→JSON completion
/// with NO tool use: the branch's own delta is HANDED to the model (the land
/// step reads it with git and pins it here), so the call is cheap, fast, and
/// cannot wander outside the change under review. The bead's prose rides as
/// WHY-context ONLY, under an explicit never-cite-it rule — the title/body
/// describe the CODE, not the tracker (directive item 3).
String buildDescribePrompt({
  required Bead bead,
  required String beadId,
  required String baseBranch,
  required String commitLog,
  required String diffStat,
  required String diff,
  String trailerToken = kDefaultTrailerToken,
}) {
  final context = _truncate(
    [bead.title, bead.description].where((s) => s.trim().isNotEmpty).join('\n\n'),
    kMaxContextChars,
  );
  final b = StringBuffer()
    ..writeln('# Describe this change for its pull request')
    ..writeln()
    ..writeln(
      'You are writing the PULL REQUEST TITLE and DESCRIPTION for the branch '
      'below. Everything you need is already in this prompt — do NOT run a '
      'tool, do NOT read a file, do NOT ask a question. Reply with ONE JSON '
      'object and nothing else.',
    )
    ..writeln()
    ..writeln('## The rules (Conventional Commits v1.0.0 — non-negotiable)')
    ..writeln(
      '- The title is `<type>[(scope)][!]: <description>`, where type is one '
      'of ${kConventionalTypes.join(' | ')}.',
    )
    ..writeln(
      '- The description is IMPERATIVE MOOD ("add x", never "added x" / '
      '"adds x"), lowercase, with NO trailing period, and the WHOLE title line '
      'stays under $kMaxSubjectChars characters.',
    )
    ..writeln(
      '- The title says WHAT CHANGED, in this repository\'s own terms — a '
      'reader of `git log` must understand it without any other context.',
    )
    ..writeln(
      '- NEVER write the tracker id `$beadId` — or any other foreign reference '
      '(an issue number, a ticket, a bead) — in the title or in the body. It '
      'is attached separately, as a `$trailerToken:` git trailer. A reader '
      'must learn what changed and why WITHOUT leaving the repo.',
    )
    ..writeln(
      '- The body is prose (a short paragraph or two, or bullets): WHAT '
      'changed, and a HIGH-LEVEL WHY. Self-contained. No "this bead", no "per '
      'the spec", no ticket narrative.',
    )
    ..writeln(
      '- A BREAKING public-API change sets `"breaking": true` AND fills '
      '`"breakingChange"` with one sentence naming what breaks. Otherwise both '
      'stay false/empty.',
    )
    ..writeln()
    ..writeln('## The change under review (`origin/$baseBranch...HEAD`)')
    ..writeln()
    ..writeln('### Commits on the branch')
    ..writeln('```')
    ..writeln(commitLog.trim().isEmpty ? '(none)' : commitLog.trim())
    ..writeln('```')
    ..writeln()
    ..writeln('### Files changed')
    ..writeln('```')
    ..writeln(diffStat.trim().isEmpty ? '(none)' : diffStat.trim())
    ..writeln('```')
    ..writeln()
    ..writeln('### The diff')
    ..writeln('```diff')
    ..writeln(_truncate(diff, kMaxDiffChars))
    ..writeln('```');
  if (context.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Why this work exists (CONTEXT ONLY — never quote or cite it)')
      ..writeln(context);
  }
  b
    ..writeln()
    ..writeln('## Your answer')
    ..writeln(
      'Reply with EXACTLY this JSON object — no prose around it, no code fence:',
    )
    ..writeln(
      '{"type":"feat","scope":"landing","breaking":false,'
      '"description":"infer the pr title from the branch diff",'
      '"body":"What changed and why, in a sentence or three.",'
      '"breakingChange":""}',
    );
  return b.toString();
}

String _circuitReceipt(PrCompositionContext context) {
  final b = StringBuffer(
    buildCircuitReceipt(beadId: context.beadId, siblings: context.siblings)
        .trimRight(),
  )
    ..writeln()
    ..writeln('- description: ${context.titleSource}');
  final commits = context.commits;
  if (!commits.isEmpty) {
    b.writeln(
      '- commits: ${commits.total} (${commits.compliant} conventional, '
      '${commits.trailered} trailered)',
    );
    for (final violation in commits.violations) {
      b.writeln('  - off-policy: $violation');
    }
  }
  return b.toString();
}

String _committeeGrades(PrCompositionContext context) {
  final review = context.siblings.resultOf('${context.beadId}/review/route');
  if (review.isEmpty) return '';
  final b = StringBuffer()
    ..writeln('## Committee')
    ..writeln()
    ..writeln(
      '- review: grades=${review['grades'] ?? ''} '
      'spread=${review['spread'] ?? ''} rule=${review['rule'] ?? ''}',
    );
  return b.toString();
}

String _validation(PrCompositionContext context) {
  final plan = context.bead.metadata['validation_plan'];
  if (plan is! String || plan.trim().isEmpty) return '';
  final b = StringBuffer()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- plan: `${plan.trim()}`');
  return b.toString();
}

String _trailers(PrCompositionContext context, String token) {
  final described = context.description;
  final b = StringBuffer();
  if (described != null && _isBreaking(described)) {
    final what = described.breakingChange.trim().isEmpty
        ? described.description.trim()
        : described.breakingChange.trim();
    b.writeln('BREAKING CHANGE: $what');
  }
  b.writeln('$token: ${context.beadId}');
  return b.toString();
}

/// `!` and the `BREAKING CHANGE:` footer imply each other — either signal from
/// the model raises both.
bool _isBreaking(PrDescription described) =>
    described.breaking || described.breakingChange.trim().isNotEmpty;

String? _rigOf(Bead bead) {
  final rig = bead.metadata['rig'];
  return (rig is String && rig.trim().isNotEmpty) ? rig.trim() : null;
}

String _truncate(String text, int max) {
  final trimmed = text.trim();
  return trimmed.length <= max
      ? trimmed
      : '${trimmed.substring(0, max)}\n… (truncated)';
}

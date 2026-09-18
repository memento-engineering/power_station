/// The PURE bead-text scanners — one synchronous, side-effect-free surface
/// shared by discovery's anchor gather and the filing contract's viability
/// rows.
///
/// Everything here is a function of the bead's own TEXT: no store is read, no
/// process is spawned, no clock is consulted. That is what lets the filing
/// contract stay a pure evaluator while still refusing text that cannot work —
/// the evidence a scanner's finding is judged AGAINST (does this id exist? does
/// this plan parse?) is gathered elsewhere and handed in.
///
/// There is exactly ONE copy of each grammar. `discovery.dart` used to carry
/// the anchor span and the decision-citation grammar privately; both MOVED
/// here when filing grew a second reader, rather than being copied into a
/// scanner that could drift from the one discovery grades against.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:pub_semver/pub_semver.dart';

/// The bound on the anchors pulled out of one bead.
const int kMaxAnchors = 12;

/// One text-bearing field of a work bead.
///
/// The wire names match bd's own field spelling, so a refusal detail names the
/// field an author would edit.
enum BeadTextField {
  /// `bd update --title`.
  title('title'),

  /// `bd update --description` — the WHY.
  description('description'),

  /// `bd update --design` — the implementation plan.
  design('design'),

  /// `bd update --acceptance-criteria`.
  acceptanceCriteria('acceptance_criteria'),

  /// `bd update --notes`.
  notes('notes'),

  /// The `validation_plan` METADATA key, not a first-class bd field.
  validationPlan('validation_plan');

  const BeadTextField(this.wire);

  /// Stable name carried in refusal details and JSON.
  final String wire;
}

/// The five WORK fields a scanner reads, in the order they are joined.
///
/// `validation_plan` is deliberately out: it is a shell PROGRAM, so an absolute
/// path or a version token inside it is ordinary argument text rather than a
/// citation, and the plan has its own two requirements.
const List<BeadTextField> kBeadWorkFields = [
  BeadTextField.title,
  BeadTextField.description,
  BeadTextField.design,
  BeadTextField.acceptanceCriteria,
  BeadTextField.notes,
];

/// The prose fields a DECISION citation is READ from — description and design,
/// and nothing else.
///
/// Title and acceptance criteria are deliberately OUT: a title is a summary
/// whose words cite nothing, and acceptance criteria are the bead's own exit
/// tests, so admitting either would pad the named set with prose that names no
/// decision at all.
///
/// NOTES are out for a stronger reason, and it is a ruling rather than a taste:
/// `power_station#notes-are-receipts-and-a-phantom-legacy-token-is-reported-not-failed`
/// makes notes the operator's RECEIPT channel. A governor writing "reverted the
/// ADR-0000 amendment" or quoting a hold reason into a note is recording
/// history, not citing a decision — and every such receipt used to re-poison
/// the very bead it explained, because resolving the hold re-reads the same
/// prose. Notes still reach every lens WHOLE; they simply make no requests. A
/// citation genuinely meant is restated in description or design.
const List<BeadTextField> kDecisionCitationFields = [
  BeadTextField.description,
  BeadTextField.design,
];

/// [field]'s text on [bead] — the one place a field name resolves to a value.
String beadTextOf(Bead bead, BeadTextField field) => switch (field) {
  BeadTextField.title => bead.title,
  BeadTextField.description => bead.description,
  BeadTextField.design => bead.design,
  BeadTextField.acceptanceCriteria => bead.acceptanceCriteria,
  BeadTextField.notes => bead.notes,
  BeadTextField.validationPlan => switch (bead.metadata['validation_plan']) {
    final String plan => plan,
    _ => '',
  },
};

/// ONE exact substring a scanner found, and WHERE it found it.
///
/// [text] is case-preserving and byte-exact — a refusal that says "use a
/// repository-relative path" is actionable only when the operator can find the
/// offending text by searching for it.
final class BeadTextSlice {
  /// Binds [text] to the [field]-local [offset] it was found at.
  const BeadTextSlice({
    required this.field,
    required this.offset,
    required this.text,
  });

  /// The field the slice came out of.
  final BeadTextField field;

  /// The slice's start, in code units from the start of [field]'s own text.
  final int offset;

  /// The exact matched substring, as the bead spells it.
  final String text;

  /// `<field>:<offset>` — the deterministic sort/report key.
  String get location => '${field.wire}:$offset';

  @override
  String toString() => '$location "$text"';
}

/// ONE decision the bead cites EXPLICITLY, with the identity it resolves to.
///
/// Distinct from `DecisionReferenceCodec`, which is discovery's ORDINAL wire
/// encoding of gathered entry bodies. This is the CITATION as the bead wrote
/// it, before anything has looked it up.
final class DecisionReference {
  /// Creates a canonical `<register>#<slug>` citation.
  const DecisionReference.canonical({
    required this.slice,
    required this.excerpt,
    required this.identity,
  }) : alias = '';

  /// Creates a legacy `ADR-<nnnn>` citation.
  const DecisionReference.legacy({
    required this.slice,
    required this.excerpt,
    required this.alias,
  }) : identity = '';

  /// Where the citation was written.
  final BeadTextSlice slice;

  /// The citation plus at most [kDecisionCitationExcerptChars] code units of
  /// its own field either side, VERBATIM — never normalized, so an operator can
  /// find the quotation by searching the bead for it.
  final String excerpt;

  /// The canonical `<register>#<slug>` identity, lowercased — empty for a
  /// legacy citation.
  final String identity;

  /// The legacy `adr-<nnnn>` id, lowercased — empty for a canonical citation.
  final String alias;

  /// Whether this is a canonical `<register>#<slug>` citation.
  bool get isCanonical => identity.isNotEmpty;

  /// The deduplication key — the identity or the alias, never both.
  String get key => identity.isEmpty ? alias : identity;

  /// What a refusal CALLS this citation.
  String get label => identity.isEmpty ? alias : identity.split('#').last;

  /// The non-failing REPORT a LEGACY citation nothing answered leaves behind.
  ///
  /// This is the one wire the filing contract parses back
  /// ([reportedLegacyDecisionAliases]) — one producer, one consumer, ONE
  /// format, so a report a lens renders and an alias filing clears can never
  /// drift apart. Only [alias] is machine-read; the field and the quotation
  /// are for the human who has to go find the token.
  String get unresolvedReport =>
      '$kUnresolvedLegacyCitationPrefix$alias'
      '$kUnresolvedLegacyCitationFrom${slice.field.wire}: “$excerpt”';
}

// ── anchors (moved out of discovery.dart) ────────────────────────────────────

/// A backticked span (group 1) OR a bare repository-relative path token
/// (group 2) — alternated in ONE scan so both sources keep first-appearance
/// order and a backticked path is never re-matched as a bare one.
final RegExp _anchorSpan = RegExp(
  r'`([^`\n]+)`|([\w./-]+\.(?:dart|md|yaml|yml|json)(?::\d+)?)',
);

final RegExp _pathAnchor = RegExp(
  r'^[\w./-]+\.(?:dart|md|yaml|yml|json)(?::(\d+))?$',
);
final RegExp _symbolChars = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
final RegExp _capital = RegExp('[A-Z]');

bool _isPathAnchor(String span) =>
    span.contains('/') && _pathAnchor.hasMatch(span);

bool _isSymbolAnchor(String span) =>
    _symbolChars.hasMatch(span) &&
    span.length >= 4 &&
    (_capital.hasMatch(span[0]) || _capital.hasMatch(span.substring(1)));

/// The PATH + SYMBOL anchors [bead] names — the round's ONLY tree-intake pass.
/// Pure, deterministic (first-appearance order), bounded ([kMaxAnchors]), and
/// exposed for unit tests.
///
/// A PATH is a known-extension repository-relative token, found either inside
/// backticks OR as a plain path token in the prose (a bead that writes
/// lib/src/x.dart without backticks names the same surface). It may carry the
/// CITED LINE the bead named (`lib/src/x.dart:222`): the qualifier rides ON the
/// anchor so a resolver can window the file at that site instead of clipping
/// its head ([parseCodeAnchor]), and two sites in one file are two anchors. A
/// SYMBOL is a BACKTICKED identifier carrying an inner capital
/// (`buildSpecifyBrief`, `kSpecReviewCircuit`) or an initial one
/// (`Heartbeat`) — which is what keeps ordinary backticked prose (`bd`,
/// `main`, `haiku`) out of the set.
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
    for (final field in kBeadWorkFields) beadTextOf(bead, field),
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

/// The PATH half and the CITED LINE of one code anchor — `lib/src/x.dart:222`
/// answers both; an anchor with no `:NNN` qualifier answers itself and null.
///
/// The qualifier is stripped for every PHYSICAL use (a filesystem read, a
/// neighbour comparison, a `git log` pathspec) and kept everywhere the anchor
/// is QUOTED, so a lens is always told WHICH site the bead named. A qualifier
/// no [int] can hold is not a line: the token stays whole and resolves as the
/// stale path it is, rather than silently becoming an unqualified anchor.
({String path, int? line}) parseCodeAnchor(String anchor) {
  final qualifier = _pathAnchor.firstMatch(anchor)?.group(1);
  if (qualifier == null) return (path: anchor, line: null);
  final line = int.tryParse(qualifier);
  if (line == null) return (path: anchor, line: null);
  return (
    path: anchor.substring(0, anchor.length - qualifier.length - 1),
    line: line,
  );
}

// ── viability scanners ───────────────────────────────────────────────────────

/// A ROOTED file anchor: a POSIX `/…` or a drive-letter `C:\…` / `C:/…` path
/// ending in one of the anchor extensions.
///
/// The leading lookbehind is what keeps URI text out: in `https://x/y.dart` and
/// `file:///tmp/a.dart` every candidate `/` is preceded by `:` or `/`, so no
/// position opens a match. A rooted DIRECTORY (`/tmp/scratch`) carries no
/// known extension and is likewise never classified — a check that cannot name
/// a file is not precise enough to refuse on.
final RegExp _absolutePathAnchor = RegExp(
  r'(?<![A-Za-z0-9_:/\\.-])((?:[A-Za-z]:[\\/]|/)[A-Za-z0-9_./\\-]*'
  r'\.(?:dart|md|yaml|yml|json))(?![A-Za-z0-9_-])',
);

/// Every ABSOLUTE file anchor [bead]'s work fields carry, in field order then
/// field-local offset order.
///
/// An absolute path is a receipt of the machine it was written on: the anchor
/// extractor resolves it against the worktree, misses, and records a FAILED
/// surface — so a temp-directory path in bead text holds the round without ever
/// saying why. The repository-relative spelling of the same file resolves
/// everywhere.
List<BeadTextSlice> absolutePathReferences(Bead bead) => [
  for (final field in kBeadWorkFields)
    for (final match in _absolutePathAnchor.allMatches(beadTextOf(bead, field)))
      BeadTextSlice(field: field, offset: match.start, text: match.group(1)!),
];

/// Every BEAD-ID-shaped token [bead]'s work fields carry under one of
/// [prefixes], in field order then field-local offset order.
///
/// [prefixes] is the set of store prefixes the caller holds a catalog for —
/// the owning substation's and every attached one's. A token under a prefix
/// NOT in that set is prose by construction: nothing could resolve it, so
/// nothing may refuse it. That is also what excludes an `AC-3` acceptance
/// record and a foreign compound such as `ISO-8601`.
///
/// Prefixes are matched longest-first so a store named `pow2` can never be
/// claimed by `pow`, and a match continued by another hyphen is rejected
/// outright — `pow-usbw-follow-up` is prose about a bead, not an id.
List<BeadTextSlice> beadIdReferences(
  Bead bead, {
  required Set<String> prefixes,
}) {
  final pattern = _beadIdPattern(prefixes);
  if (pattern == null) return const [];
  return [
    for (final field in kBeadWorkFields)
      for (final match in pattern.allMatches(beadTextOf(bead, field)))
        BeadTextSlice(field: field, offset: match.start, text: match.group(0)!),
  ];
}

/// The store PREFIX of [id] — the text before its first hyphen.
String beadIdPrefixOf(String id) {
  final hyphen = id.indexOf('-');
  return hyphen <= 0 ? '' : id.substring(0, hyphen);
}

RegExp? _beadIdPattern(Set<String> prefixes) {
  final usable = prefixes.where((prefix) => prefix.trim().isNotEmpty).toList();
  if (usable.isEmpty) return null;
  // Longest first: alternation is ordered, so `pow2` must be offered before
  // `pow` or `pow2-x` matches as `pow` + a rejected tail.
  usable.sort((a, b) {
    final byLength = b.length.compareTo(a.length);
    return byLength != 0 ? byLength : a.compareTo(b);
  });
  final alternation = usable.map(RegExp.escape).join('|');
  return RegExp(
    '(?<![A-Za-z0-9_-])(?:$alternation)'
    r'-[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*(?![A-Za-z0-9_-])',
  );
}

/// A token-bounded three-component version. The trailing `(?!\.\d)` is what
/// keeps a four-segment build number out while still admitting a version that
/// ends a sentence.
final RegExp _exactVersion = RegExp(
  r'(?<![A-Za-z0-9_.-])(\d+\.\d+\.\d+(?:[-+][A-Za-z0-9_.+-]+)?)'
  r'(?![A-Za-z0-9_-])(?!\.\d)',
);

/// The constraint operators that make a version token a RANGE rather than a
/// pin. Whitespace between operator and version is allowed (`>= 1.2.3`).
const String _versionConstraintOperators = '^~<>=';

/// Every EXACT release version pinned in [bead]'s acceptance criteria, in
/// offset order.
///
/// Acceptance criteria ONLY: specify copies the acceptance list into a
/// validation-plan leg, so a version pinned there becomes a gating command that
/// goes stale on the next release wave — the bead then fails on the calendar
/// rather than on its own work. A version named in the design (which describes
/// what was built) or a RANGE anywhere (which is what a pubspec actually
/// carries) is not that hazard and is not refused.
List<BeadTextSlice> exactReleaseVersions(Bead bead) {
  final text = beadTextOf(bead, BeadTextField.acceptanceCriteria);
  final found = <BeadTextSlice>[];
  for (final match in _exactVersion.allMatches(text)) {
    if (_isConstrained(text, match.start)) continue;
    try {
      Version.parse(match.group(1)!);
    } on FormatException {
      continue;
    }
    found.add(
      BeadTextSlice(
        field: BeadTextField.acceptanceCriteria,
        offset: match.start,
        text: match.group(1)!,
      ),
    );
  }
  return found;
}

/// Whether the token at [start] is GOVERNED by a range operator, with or
/// without whitespace between.
bool _isConstrained(String text, int start) {
  for (var at = start - 1; at >= 0; at--) {
    final unit = text[at];
    if (unit == ' ' || unit == '\t') continue;
    return _versionConstraintOperators.contains(unit);
  }
  return false;
}

// ── decision citations (moved out of discovery.dart) ─────────────────────────

/// A canonical `<register>#<slug>` citation. The slug half must be HYPHENATED
/// and start with a letter — what every authored slug looks like, and what
/// keeps prose such as `pr#256` out of the explicit set, where a false citation
/// would refuse a bead that is perfectly answerable.
///
/// Matched CASE-INSENSITIVELY over the field's OWN text rather than over a
/// lowercased copy: a slice and an excerpt are only quotable when the match
/// offsets index the SOURCE, and lowercasing is not length-preserving for
/// every code point.
final RegExp _canonicalDecisionCitation = RegExp(
  r'(?<![a-z0-9_#-])([a-z0-9_]+)#([a-z][a-z0-9]*(?:-[a-z0-9]+)+)(?![a-z0-9_-])',
  caseSensitive: false,
);

/// An ADR id (`ADR-0008`) — the one NON-canonical shape explicit enough to
/// resolve a legacy entry by. A bare `A<n>` is deliberately out: organic bead
/// prose writes `A1`/`A2` as OPTION LABELS, so refusing on the absence of one
/// would hold every bead in the org over a sentence that cites nothing. `A<n>`
/// still ORDERS a returned entry ([citesDecisionToken]); it only never fails.
///
/// A legacy id nothing answers is REPORTED and never refused
/// ([DecisionReference.unresolvedReport]): the register's own log file is
/// spelled `ADR-0000`, and no register can ever hold an entry for the log its
/// amendments live in, so refusing on absence holds the round forever.
///
/// Case-insensitive over source text, for the reason
/// [_canonicalDecisionCitation] states.
final RegExp _explicitAdrCitation = RegExp(
  r'(?<![a-z0-9_#-])(adr-\d{4})(?![a-z0-9_-])',
  caseSensitive: false,
);

/// The leading legacy id of [slug], or `''` when it carries none.
///
/// Promoting an ADR-0000 amendment into the register keeps its id as the slug's
/// leading segment, and a bead goes on citing the ID long after the slug
/// exists.
String legacyDecisionAlias(String slug) =>
    RegExp(
      r'^(a\d+|adr-\d{4})(?:-|$)',
    ).firstMatch(slug.toLowerCase())?.group(1) ??
    '';

/// [kDecisionCitationFields] joined and lowercased — the haystack a
/// WHOLE-TOKEN name check ([citesDecisionToken]) runs over.
///
/// This is the NAMING text, not the citation text: it answers "did the bead
/// mention this returned entry?", which is what ORDERS a gather. Extraction of
/// the citations themselves reads each field separately, because only a
/// field-local offset can be quoted back ([decisionReferences]).
String decisionCitationText(Bead bead) => [
  for (final field in kDecisionCitationFields) beadTextOf(bead, field),
].join('\n').toLowerCase();

/// How much of a citation's OWN field a report quotes either side of it.
const int kDecisionCitationExcerptChars = 80;

/// How the non-failing report of an unresolved LEGACY citation OPENS.
///
/// Read by [reportedLegacyDecisionAliases]; written by
/// [DecisionReference.unresolvedReport]. A detail that does not open with this
/// is not a report.
const String kUnresolvedLegacyCitationPrefix =
    'unresolved legacy decision citation ';

/// What separates the reported ALIAS from its provenance in that same line.
const String kUnresolvedLegacyCitationFrom = ' reported from ';

/// Every legacy alias [detail] REPORTS as unresolved, lowercased.
///
/// Reports arrive one per line, on the same member a FAILURE would use, told
/// apart by the record's state — so the parse is deliberately strict: a line
/// that does not open with [kUnresolvedLegacyCitationPrefix], or that carries
/// no [kUnresolvedLegacyCitationFrom] after it, yields nothing. A malformed
/// detail must never be read as permission to clear a citation.
Set<String> reportedLegacyDecisionAliases(String detail) {
  final found = <String>{};
  for (final line in detail.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(kUnresolvedLegacyCitationPrefix)) continue;
    final rest = trimmed.substring(kUnresolvedLegacyCitationPrefix.length);
    final at = rest.indexOf(kUnresolvedLegacyCitationFrom);
    if (at <= 0) continue;
    found.add(rest.substring(0, at).trim().toLowerCase());
  }
  return found;
}

/// Every decision [bead] cites EXPLICITLY, deduplicated, in field order then
/// field-local offset order.
///
/// A canonical token counts only when [knownRegisters] — the registers the
/// caller's index actually ANSWERED with — holds its register half.
/// `id#some-value` under a register nobody indexed is PROSE, and refusing on
/// it would hold a bead over a hash in a sentence.
///
/// The FIELD a citation came from is part of the answer, not a detail of the
/// scan: a request nothing resolves is reported by WHERE it was read, which is
/// the whole difference between a report an operator can act on and a name
/// they have to go hunt for.
List<DecisionReference> decisionReferences(
  Bead bead, {
  required Set<String> knownRegisters,
}) {
  final registers = {
    for (final register in knownRegisters) register.toLowerCase(),
  };
  final found = <DecisionReference>[];
  final seen = <String>{};
  for (final field in kDecisionCitationFields) {
    final text = beadTextOf(bead, field);
    final hits = <(int, DecisionReference)>[];
    for (final match in _canonicalDecisionCitation.allMatches(text)) {
      if (!registers.contains(match.group(1)!.toLowerCase())) continue;
      hits.add((
        match.start,
        DecisionReference.canonical(
          slice: _slice(field, match, text),
          excerpt: _excerpt(text, match),
          identity: match.group(0)!.toLowerCase(),
        ),
      ));
    }
    for (final match in _explicitAdrCitation.allMatches(text)) {
      hits.add((
        match.start,
        DecisionReference.legacy(
          slice: _slice(field, match, text),
          excerpt: _excerpt(text, match),
          alias: match.group(0)!.toLowerCase(),
        ),
      ));
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, reference) in hits) {
      if (seen.add(reference.key)) found.add(reference);
    }
  }
  return found;
}

/// Every REGISTER half a canonical citation in [bead]'s prose names,
/// lowercased — asked BEFORE any index has answered, so a caller can tell
/// whether it must widen its lookup to a register this surface never mentioned.
Set<String> citedDecisionRegisters(Bead bead) => {
  for (final field in kDecisionCitationFields)
    for (final match in _canonicalDecisionCitation.allMatches(
      beadTextOf(bead, field),
    ))
      match.group(1)!.toLowerCase(),
};

/// Slices [source] at [match]'s span, exactly as the bead spelled it — the
/// match ran over [source] ITSELF, so the offsets need no adjustment.
BeadTextSlice _slice(BeadTextField field, RegExpMatch match, String source) =>
    BeadTextSlice(
      field: field,
      offset: match.start,
      text: source.substring(match.start, match.end),
    );

/// [match]'s own text plus at most [kDecisionCitationExcerptChars] code units
/// of [source] either side of it, VERBATIM.
String _excerpt(String source, RegExpMatch match) {
  final from = match.start - kDecisionCitationExcerptChars;
  final to = match.end + kDecisionCitationExcerptChars;
  return source.substring(
    from < 0 ? 0 : from,
    to > source.length ? source.length : to,
  );
}

/// Whether [needle] occurs in [haystack] as a WHOLE token — never as the head
/// or the tail of a longer one, so `A2` can never claim the entry a bead cited
/// as `A25`.
///
/// `-` and `_` count as token characters precisely BECAUSE a slug is
/// hyphenated: without them `a21-bead-pow` would claim a hit inside
/// `a21-bead-pow-96y-…`. [haystack] is expected already lowercased, so only
/// lowercase letters need to continue a token.
bool citesDecisionToken(String haystack, String needle) {
  if (needle.isEmpty) return false;
  for (
    var at = haystack.indexOf(needle);
    at >= 0;
    at = haystack.indexOf(needle, at + 1)
  ) {
    final before = at == 0 ? null : haystack.codeUnitAt(at - 1);
    final end = at + needle.length;
    final after = end == haystack.length ? null : haystack.codeUnitAt(end);
    if (!_isTokenChar(before) && !_isTokenChar(after)) return true;
  }
  return false;
}

/// Whether [unit] CONTINUES a token (lowercase ASCII letter, digit, `-`, `_`).
bool _isTokenChar(int? unit) =>
    unit != null &&
    ((unit >= 0x61 && unit <= 0x7a) ||
        (unit >= 0x30 && unit <= 0x39) ||
        unit == 0x2d ||
        unit == 0x5f);

// ── validation-plan slicing ──────────────────────────────────────────────────

/// The EXACT text of [plan] a shell refused, given that shell's [diagnostic].
///
/// A parse refusal that only says "invalid" moves the guessing instead of
/// removing it, and a shell's own diagnostic names a LINE and a token, not a
/// span an author can search for. This resolves one, in a fixed precedence so
/// the same plan always names the same text:
///
///  1. a balanced, complete `$(…)` substitution containing `#` — inside a
///     command substitution a `#` opens a comment that swallows the closing
///     paren, which parse-kills the whole gating line;
///  2. a balanced, complete `<(…)`/`>(…)` process substitution — Bash-only, and
///     it dies at PARSE under dash rather than at run time, so it surfaces as a
///     harness throttle rather than as a bad plan;
///  3. the smallest INTERIOR-apostrophe word (`lane's`) when the plan's single
///     quotes do not pair — design prose carried into a single-quoted program
///     is the field case, and the boundary quotes of the program itself are not
///     the offender;
///  4. the first normalized token of [diagnostic] that occurs verbatim in the
///     plan;
///  5. the complete trimmed plan — never an empty string.
String validationPlanOffendingSlice(String plan, String diagnostic) {
  final trimmed = plan.trim();
  if (trimmed.isEmpty) return trimmed;
  for (final span in _balancedSpans(trimmed, const [r'$('])) {
    if (span.contains('#')) return span;
  }
  for (final span in _balancedSpans(trimmed, const ['<(', '>('])) {
    return span;
  }
  if (_hasUnpairedSingleQuote(trimmed)) {
    final word = _smallestInteriorApostropheWord(trimmed);
    if (word.isNotEmpty) return word;
  }
  for (final token in _diagnosticTokens(diagnostic)) {
    if (trimmed.contains(token)) return token;
  }
  return trimmed;
}

/// Every COMPLETE balanced span of [source] opening with one of [openers], in
/// order. An unbalanced opener yields nothing: a span whose close was never
/// found is not text anyone can be pointed at.
List<String> _balancedSpans(String source, List<String> openers) {
  final spans = <String>[];
  for (var at = 0; at < source.length; at++) {
    final opener = openers.firstWhere(
      (candidate) => source.startsWith(candidate, at),
      orElse: () => '',
    );
    if (opener.isEmpty) continue;
    var depth = 0;
    for (var scan = at + opener.length - 1; scan < source.length; scan++) {
      if (source[scan] == '(') depth++;
      if (source[scan] == ')') {
        depth--;
        if (depth == 0) {
          spans.add(source.substring(at, scan + 1));
          at = scan;
          break;
        }
      }
    }
  }
  return spans;
}

bool _hasUnpairedSingleQuote(String source) =>
    "'".allMatches(source).length.isOdd;

/// The shortest whitespace-delimited word of [source] whose apostrophe is
/// INTERIOR — neither the first nor the last character.
///
/// A leading or trailing quote is the single-quoted program's own boundary, so
/// naming it would point at the syntax rather than at the typo. Ties go to the
/// first occurrence, so the answer is deterministic.
String _smallestInteriorApostropheWord(String source) {
  var best = '';
  for (final word in source.split(RegExp(r'\s+'))) {
    final at = word.indexOf("'");
    if (at <= 0 || at >= word.length - 1) continue;
    if (best.isEmpty || word.length < best.length) best = word;
  }
  return best;
}

/// [diagnostic]'s tokens, QUOTED ones first — a shell names the construct it
/// choked on inside quotes or backticks, so those are the highest-signal
/// candidates — then its bare whitespace-delimited words, stripped of
/// surrounding punctuation. Single characters are dropped: a lone `(` occurs in
/// almost every plan and names nothing.
Iterable<String> _diagnosticTokens(String diagnostic) sync* {
  final quoted = RegExp('[`\'"]([^`\'"\n]+)[`\'"]');
  for (final match in quoted.allMatches(diagnostic)) {
    final token = match.group(1)!.trim();
    if (token.length > 1) yield token;
  }
  for (final raw in diagnostic.split(RegExp(r'\s+'))) {
    final token = raw.replaceAll(
      RegExp('''^[`'"(,:;.]+|[`'")\\,:;.]+\$'''),
      '',
    );
    if (token.length > 1) yield token;
  }
}

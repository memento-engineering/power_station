import 'package:beads_dart/beads_dart.dart';
import 'package:pub_semver/pub_semver.dart';

/// The per-kind bound on how many anchors ONE bead contributes to a round.
///
/// A bead naming more surfaces than this carries the head of the list plus a
/// truncation flag, so a short list is never silent.
const int kMaxAnchors = 12;

/// One AUTHORED text field of a bead — the unit every scanner in this library
/// reports a slice against, so a refusal can say WHERE the offending text is
/// as well as what it says.
enum BeadTextField {
  /// `title`.
  title('title'),

  /// `description` — the bead's task prose.
  description('description'),

  /// `design`.
  design('design'),

  /// `acceptance_criteria`.
  acceptanceCriteria('acceptance_criteria'),

  /// `notes`.
  notes('notes'),

  /// The `validation_plan` metadata value — NOT a work field (see
  /// [kBeadWorkFields]); it is the gating shell program.
  validationPlan('validation_plan');

  const BeadTextField(this.wire);

  /// Stable name used in wire values and refusal details.
  final String wire;

  /// This field's text in [bead].
  ///
  /// Never null: an absent or non-String `validation_plan` metadata value
  /// reads as the empty string, so a scanner never has to re-decide what a
  /// missing field means.
  String read(Bead bead) => switch (this) {
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
}

/// The five WORK fields, in the order a scan reads them — which is what makes
/// "first appearance" a property of the BEAD rather than of a scanner.
const List<BeadTextField> kBeadWorkFields = [
  BeadTextField.title,
  BeadTextField.description,
  BeadTextField.design,
  BeadTextField.acceptanceCriteria,
  BeadTextField.notes,
];

/// The fields a DECISION citation can live in.
///
/// Title and acceptance criteria are deliberately OUT: a title is a summary
/// whose words cite nothing, and acceptance criteria are the bead's own exit
/// tests, so admitting either would pad the cited set with prose that names no
/// decision at all.
const List<BeadTextField> kDecisionCitationFields = [
  BeadTextField.description,
  BeadTextField.design,
  BeadTextField.notes,
];

/// ONE offending (or merely interesting) run of authored bead text, carried
/// with the field it was read from and the EXACT, case-preserving substring.
///
/// A check that only says "invalid" moves the guessing rather than removing
/// it; this is the type that makes naming the offending text structural.
final class BeadTextSlice {
  /// Creates a slice.
  const BeadTextSlice({required this.field, required this.text});

  /// The field [text] was read from.
  final BeadTextField field;

  /// The exact authored substring, case preserved.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is BeadTextSlice && other.field == field && other.text == text;

  @override
  int get hashCode => Object.hash(field, text);

  @override
  String toString() => '${field.wire}: $text';
}

/// ONE decision a bead cites EXPLICITLY: the authored slice plus the
/// normalized identity a catalog comparison is made against.
///
/// Exactly one of [identity] and [alias] is non-empty — a canonical
/// `<register>#<slug>` citation carries the former, a legacy `ADR-<nnnn>` one
/// the latter.
final class DecisionReference {
  /// Creates a reference.
  const DecisionReference({
    required this.slice,
    required this.identity,
    required this.alias,
  });

  /// The authored citation, case preserved.
  final BeadTextSlice slice;

  /// The lowercased canonical `<register>#<slug>` identity, or `''` for a
  /// legacy citation.
  final String identity;

  /// The lowercased legacy `adr-<nnnn>` id, or `''` for a canonical citation.
  final String alias;

  /// The register half of [identity], or `''` for a legacy citation.
  String get register =>
      identity.isEmpty ? '' : identity.substring(0, identity.indexOf('#'));

  /// What a refusal CALLS this citation — the exact authored text.
  String get citation => slice.text;

  @override
  bool operator ==(Object other) =>
      other is DecisionReference &&
      other.slice == slice &&
      other.identity == identity &&
      other.alias == alias;

  @override
  int get hashCode => Object.hash(slice, identity, alias);

  @override
  String toString() => citation;
}

// ── anchors ──────────────────────────────────────────────────────────────────

/// A backticked span (group 1), a DRIVE-LETTER Windows file token (group 2),
/// OR a bare repository-relative/POSIX-rooted path token (group 3) —
/// alternated in ONE scan so every source keeps first-appearance order and a
/// backticked path is never re-matched as a bare one.
///
/// The Windows alternative is deliberately narrow: it demands a literal drive
/// letter, so a backslash in ordinary prose or in a regex never reads as a
/// path.
final RegExp kAnchorSpan = RegExp(
  r'`([^`\n]+)`'
  r'|([A-Za-z]:[\\/][\w.\\ -]*(?:[\\/][\w.\\ -]*)*\.(?:dart|md|yaml|yml|json))'
  r'|([\w./-]+\.(?:dart|md|yaml|yml|json))',
);

final RegExp _posixPathAnchor = RegExp(r'^[\w./-]+\.(dart|md|yaml|yml|json)$');

final RegExp _windowsPathAnchor = RegExp(
  r'^[A-Za-z]:[\\/][\w.\\/ -]*\.(dart|md|yaml|yml|json)$',
);

final RegExp _windowsRoot = RegExp(r'^[A-Za-z]:[\\/]');

final RegExp _symbolChars = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

final RegExp _capital = RegExp('[A-Z]');

/// Whether [span] reads as a FILE anchor — a known-extension path, either
/// repository-relative, POSIX-rooted, or drive-letter Windows.
///
/// An extensionless directory is deliberately NOT one: a composing grid home
/// is an absolute directory a bead legitimately names, and classifying it here
/// would refuse the bead over the one absolute path that is not a citation.
bool isPathAnchor(String span) =>
    (span.contains('/') && _posixPathAnchor.hasMatch(span)) ||
    _windowsPathAnchor.hasMatch(span);

/// Whether [anchor] is ROOTED — POSIX `/…` or a Windows drive letter.
bool isAbsolutePathAnchor(String anchor) =>
    anchor.startsWith('/') || _windowsRoot.hasMatch(anchor);

bool _isSymbolAnchor(String span) =>
    _symbolChars.hasMatch(span) &&
    span.length >= 4 &&
    (_capital.hasMatch(span[0]) || _capital.hasMatch(span.substring(1)));

/// Every PATH and SYMBOL anchor [bead] names, as SLICES — deduplicated by
/// text, in first-appearance order over [kBeadWorkFields], unbounded.
///
/// [beadAnchors] is the bounded, text-only projection of this; the slices are
/// what a refusal needs, since it must say which field carried the offence.
({List<BeadTextSlice> paths, List<BeadTextSlice> symbols}) beadAnchorSlices(
  Bead bead,
) {
  final paths = <String, BeadTextSlice>{};
  final symbols = <String, BeadTextSlice>{};
  for (final field in kBeadWorkFields) {
    for (final match in kAnchorSpan.allMatches(field.read(bead))) {
      final backticked = match.group(1);
      final span = (backticked ?? match.group(2) ?? match.group(3)!).trim();
      if (isPathAnchor(span)) {
        paths.putIfAbsent(span, () => BeadTextSlice(field: field, text: span));
      } else if (backticked != null && _isSymbolAnchor(span)) {
        symbols.putIfAbsent(
          span,
          () => BeadTextSlice(field: field, text: span),
        );
      }
    }
  }
  return (paths: paths.values.toList(), symbols: symbols.values.toList());
}

/// The PATH + SYMBOL anchors [bead] names — the round's ONLY tree-intake pass.
/// Pure, deterministic (first-appearance order), bounded ([kMaxAnchors]), and
/// exposed for unit tests.
///
/// A PATH is a known-extension token — repository-relative, POSIX-rooted, or
/// drive-letter Windows — found either inside backticks OR as a plain path
/// token in the prose (a bead that writes lib/src/x.dart without backticks
/// names the same surface). A SYMBOL is a BACKTICKED identifier carrying an
/// inner capital (`buildSpecifyBrief`, `kSpecReviewCircuit`) or an initial one
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
  final slices = beadAnchorSlices(bead);
  return (
    paths: [
      for (final slice in slices.paths) slice.text,
    ].take(kMaxAnchors).toList(),
    symbols: [
      for (final slice in slices.symbols) slice.text,
    ].take(kMaxAnchors).toList(),
    pathsTruncated: slices.paths.length > kMaxAnchors,
    symbolsTruncated: slices.symbols.length > kMaxAnchors,
  );
}

/// Every ABSOLUTE file anchor [bead] names across [kBeadWorkFields], in
/// first-appearance order and bounded by [kMaxAnchors].
///
/// Only known-extension FILE anchors are returned, so an absolute grid-home
/// DIRECTORY — which a bead names legitimately — is never classified here.
List<BeadTextSlice> absolutePathReferences(Bead bead) => [
  for (final slice in beadAnchorSlices(bead).paths)
    if (isAbsolutePathAnchor(slice.text)) slice,
].take(kMaxAnchors).toList();

// ── bead ids ─────────────────────────────────────────────────────────────────

/// Every token in [bead]'s work fields that is a bead id UNDER one of
/// [prefixes] — in first-appearance order, deduplicated by text.
///
/// [prefixes] is the fence, and it is the whole fence: the boundary is built
/// from the supplied store prefixes sorted longest-first, so `pow-x` under a
/// roster carrying both `pow` and `pow_station` resolves to the longer store.
/// A token under no supplied prefix is PROSE by construction — which is what
/// keeps `AC-1` records and digit-bearing English compounds (`utf-8`,
/// `sha-256`) out of the set without a second heuristic to disagree with.
List<BeadTextSlice> beadIdReferences(
  Bead bead, {
  required Iterable<String> prefixes,
}) {
  final ordered =
      prefixes
          .map((prefix) => prefix.trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) {
          final byLength = b.length.compareTo(a.length);
          return byLength != 0 ? byLength : a.compareTo(b);
        });
  if (ordered.isEmpty) return const [];
  final pattern = RegExp(
    '(?<![A-Za-z0-9_-])(?:${ordered.map(RegExp.escape).join('|')})'
    r'-[a-z0-9_](?:[a-z0-9_.]*[a-z0-9_])?(?![A-Za-z0-9_-])',
  );
  final found = <String, BeadTextSlice>{};
  for (final field in kBeadWorkFields) {
    for (final match in pattern.allMatches(field.read(bead))) {
      final id = match.group(0)!;
      found.putIfAbsent(id, () => BeadTextSlice(field: field, text: id));
    }
  }
  return found.values.toList();
}

// ── release versions ─────────────────────────────────────────────────────────

/// A token-bounded three-component version, with optional prerelease and build
/// suffixes. The trailing bound keeps `1.2.3.4` — which is not a version —
/// out.
final RegExp _semverToken = RegExp(
  r'(?<![0-9A-Za-z_.+-])'
  r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?'
  r'(?![0-9A-Za-z_.])',
);

/// The characters that GOVERN a version token into a range. A token they
/// introduce is a constraint, not a pin, and is deliberately admitted.
const String _rangeOperators = '^~<>=';

/// Every EXACT release version pinned in [bead]'s acceptance criteria, in
/// first-appearance order, deduplicated by text.
///
/// Acceptance criteria only: Specify copies the acceptance list into a plan
/// leg, so a pin there goes stale on the next release wave. A pin anywhere
/// else is the bead's own prose and is none of this scanner's business.
///
/// A token immediately governed by `^`, `~`, `<`, `>` or `=` is a RANGE and is
/// not returned; a date (`2026-09-13`) never matches the grammar at all.
List<BeadTextSlice> exactReleaseVersions(Bead bead) {
  const field = BeadTextField.acceptanceCriteria;
  final text = field.read(bead);
  final found = <String, BeadTextSlice>{};
  for (final match in _semverToken.allMatches(text)) {
    if (match.start > 0 && _rangeOperators.contains(text[match.start - 1])) {
      continue;
    }
    final token = match.group(0)!;
    try {
      Version.parse(token);
    } on FormatException {
      continue;
    }
    found.putIfAbsent(token, () => BeadTextSlice(field: field, text: token));
  }
  return found.values.toList();
}

// ── decision citations ───────────────────────────────────────────────────────

/// A canonical `<register>#<slug>` citation. The slug half must be HYPHENATED
/// and start with a letter — what every authored slug looks like, and what
/// keeps prose such as `pr#256` out of the explicit set, where a false citation
/// would fail a surface that is perfectly answerable.
final RegExp kCanonicalDecisionCitation = RegExp(
  r'(?<![a-z0-9_#-])([a-z0-9_]+)#([a-z][a-z0-9]*(?:-[a-z0-9]+)+)(?![a-z0-9_-])',
  caseSensitive: false,
);

/// An ADR id (`ADR-0008`) — the one NON-canonical shape unambiguous enough to
/// fail a surface on absence.
///
/// A bare legacy `A<n>` token is NEVER one: organic bead prose writes `A1`/`A2`
/// as OPTION LABELS, so failing on the absence of one would hold every bead in
/// the org over a sentence that cites nothing.
final RegExp kExplicitAdrCitation = RegExp(
  r'(?<![a-z0-9_#-])(adr-\d{4})(?![a-z0-9_-])',
  caseSensitive: false,
);

final RegExp _legacyAliasHead = RegExp(r'^(a\d+|adr-\d{4})(?:-|$)');

/// The leading legacy id of [slug], or `''` when it carries none.
///
/// Promoting an ADR-0000 amendment into the register keeps its id as the
/// slug's leading segment, and a bead goes on citing the ID long after the slug
/// exists.
String legacyDecisionAlias(String slug) =>
    _legacyAliasHead.firstMatch(slug.toLowerCase())?.group(1) ?? '';

/// The bead prose a decision citation can live in — [kDecisionCitationFields],
/// lowercased so every match is case-insensitive.
String decisionCitationText(Bead bead) => [
  for (final field in kDecisionCitationFields) field.read(bead),
].join('\n').toLowerCase();

/// Every decision [bead] cites EXPLICITLY, deduplicated by normalized
/// identity, in first-appearance order over [kDecisionCitationFields].
///
/// Each reference keeps the EXACT authored substring alongside the normalized
/// identity, so a refusal names what the bead actually wrote.
///
/// This is the SHAPE of a citation only. Whether a register is one anybody
/// indexed, and whether the entry exists, are questions for the catalog the
/// caller supplies — a canonical token under an unknown register is prose, and
/// concluding otherwise would hold a bead over a hash in a sentence.
List<DecisionReference> decisionReferences(Bead bead) {
  final found = <String, DecisionReference>{};
  for (final field in kDecisionCitationFields) {
    final text = field.read(bead);
    final ordered = <(int, DecisionReference)>[];
    for (final match in kCanonicalDecisionCitation.allMatches(text)) {
      final cited = match.group(0)!;
      ordered.add((
        match.start,
        DecisionReference(
          slice: BeadTextSlice(field: field, text: cited),
          identity: cited.toLowerCase(),
          alias: '',
        ),
      ));
    }
    for (final match in kExplicitAdrCitation.allMatches(text)) {
      final cited = match.group(0)!;
      ordered.add((
        match.start,
        DecisionReference(
          slice: BeadTextSlice(field: field, text: cited),
          identity: '',
          alias: cited.toLowerCase(),
        ),
      ));
    }
    ordered.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, reference) in ordered) {
      final key = reference.identity.isEmpty
          ? reference.alias
          : reference.identity;
      found.putIfAbsent(key, () => reference);
    }
  }
  return found.values.toList();
}

// ── validation-plan slices ───────────────────────────────────────────────────

/// One balanced substitution span found in a plan program.
typedef _Substitution = ({String marker, String text});

/// Every balanced `$(…)`, `<(…)` and `>(…)` span in [plan], in first-appearance
/// order. An unbalanced opener contributes nothing — there is no complete span
/// to name.
List<_Substitution> _substitutions(String plan) {
  final spans = <_Substitution>[];
  for (var open = 0; open + 1 < plan.length; open++) {
    final marker = plan.substring(open, open + 2);
    if (marker != r'$(' && marker != '<(' && marker != '>(') continue;
    var depth = 0;
    for (var scan = open + 1; scan < plan.length; scan++) {
      if (plan[scan] == '(') depth++;
      if (plan[scan] != ')') continue;
      depth--;
      if (depth != 0) continue;
      spans.add((marker: marker, text: plan.substring(open, scan + 1)));
      break;
    }
  }
  return spans;
}

/// A word carrying an apostrophe BETWEEN word characters — `lane's`, the shape
/// that walks out of design prose and into a single-quoted plan program.
final RegExp _apostropheWord = RegExp(r"[A-Za-z0-9_]'[A-Za-z0-9_]");

/// The tokens a shell quotes in its own diagnostic, in the three spellings the
/// lane shells use.
final RegExp _diagnosticToken = RegExp(
  '"([^"]+)"'
  "|`([^`']+)'"
  "|'([^']+)'",
);

/// The SMALLEST exact substring of [plan] a parse refusal is about.
///
/// Deterministic precedence, most specific first:
///  1. the complete `$(…)` command substitution containing a `#` — the
///     incident that reads as a harness throttle rather than a bad plan;
///  2. the complete `<(…)` or `>(…)` process substitution — the Bash-only
///     construct Dash dies on;
///  3. the smallest apostrophe-bearing word responsible for an unterminated
///     single-quoted program (`lane's`);
///  4. the first token the shell's own [diagnostic] quotes that occurs
///     verbatim in the plan;
///  5. the complete trimmed plan, when nothing above yields a smaller exact
///     substring.
///
/// It never returns text the plan does not contain: naming a construct the
/// author cannot find would move the guessing rather than remove it.
String validationPlanOffendingSlice(String plan, {String diagnostic = ''}) {
  final trimmed = plan.trim();
  final spans = _substitutions(trimmed);
  for (final span in spans) {
    if (span.marker == r'$(' && span.text.contains('#')) return span.text;
  }
  for (final span in spans) {
    if (span.marker != r'$(') return span.text;
  }
  if (trimmed.split("'").length.isEven) {
    // An ODD number of single quotes (an EVEN split arity) leaves the program
    // unterminated; the word carrying an inner apostrophe is why.
    String? smallest;
    for (final word in trimmed.split(RegExp(r'\s+'))) {
      if (!_apostropheWord.hasMatch(word)) continue;
      if (smallest == null || word.length < smallest.length) smallest = word;
    }
    if (smallest != null) return smallest;
  }
  for (final match in _diagnosticToken.allMatches(diagnostic)) {
    final token = (match.group(1) ?? match.group(2) ?? match.group(3)!).trim();
    if (token.isNotEmpty && trimmed.contains(token)) return token;
  }
  return trimmed;
}

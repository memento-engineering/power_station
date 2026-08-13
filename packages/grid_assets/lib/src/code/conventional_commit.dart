/// **Conventional Commits v1.0.0** — the grammar, the sanitizer, the lint, and
/// the trailer footer (bead `pow-8dx`; https://www.conventionalcommits.org/en/v1.0.0/).
///
/// **The policy (Nico, 2026-07-12)**: a commit/PR subject is
/// `<type>[(scope)][!]: <description>` — imperative, lowercase, no trailing
/// period — and it describes WHAT CHANGED IN THIS REPO, in the repo's own
/// terms. A FOREIGN REFERENCE (the bead id) never rides the subject or the body
/// prose; it rides ONE git TRAILER at the very bottom (`Refs: <bead>`, the
/// token configurable), so a reader of `git log` learns what changed and why
/// WITHOUT leaving the repo, while INVERTED tracking (bead ← commit) still
/// works. What the landing asset emitted before this bead — `grid: <bead>` —
/// is neither: `grid` is not a type, and the bead id WAS the whole subject.
///
/// Everything here is PURE (no I/O, no tree, no bead — it imports nothing) and
/// is consumed by `pr_composition.dart` (the PR title/body), `pr_describe.dart`
/// (the commit lint) and `code_capabilities.dart` (the land commit + the
/// build-agent brief).
library;

/// The Conventional Commits v1.0.0 type set (the `feat`/`fix` pair the spec
/// itself names, plus the Angular convention's set the spec approves). An
/// out-of-set type is NOT emitted: [sanitizeConventionalSubject] falls it back,
/// and [lintConventionalSubject] reports it.
const List<String> kConventionalTypes = [
  'build',
  'chore',
  'ci',
  'docs',
  'feat',
  'fix',
  'perf',
  'refactor',
  'revert',
  'style',
  'test',
];

/// The default git-trailer token the bead id rides (`Refs: <bead>`) — the ONLY
/// place a foreign reference may appear. Configurable per station via
/// `PrComposition.trailerToken`.
const String kDefaultTrailerToken = 'Refs';

/// The subject-line budget — the whole `<type>[(scope)][!]: <description>` line
/// stays within it (git's own convention; a longer subject is truncated at a
/// word boundary by [sanitizeConventionalSubject] and reported by
/// [lintConventionalSubject]).
const int kMaxSubjectChars = 72;

/// The description a sanitizer falls back to when it is handed nothing usable
/// (a blank bead title AND no inference) — deliberately id-free.
const String kFallbackDescription = 'apply the reviewed change';

/// The v1.0.0 subject grammar: `<type>[(scope)][!]: <description>`.
final RegExp _subjectGrammar = RegExp(
  r'^([a-z]+)(?:\(([^()\n]+)\))?(!)?: (\S.*)$',
);

/// A conventional-commit SUBJECT as PARTS — the shape the asset always composes
/// from (never a free-form string), so what it emits is compliant BY
/// CONSTRUCTION rather than by hope.
class ConventionalSubject {
  /// Creates the subject.
  const ConventionalSubject({
    required this.type,
    this.scope,
    this.breaking = false,
    required this.description,
  });

  /// The v1.0.0 type (`feat`/`fix`/...).
  final String type;

  /// The optional scope (the changed area of the code); null/empty ⇒ omitted.
  final String? scope;

  /// Whether this is a BREAKING change (`!` after the type/scope) — always
  /// paired with a `BREAKING CHANGE:` footer by [composeCommitMessage]'s
  /// callers (Nico's rule: `!` AND the footer, never one alone).
  final bool breaking;

  /// The imperative, lowercase, period-less description.
  final String description;

  /// `<type>[(scope)][!]: <description>`.
  String format() {
    final s = scope;
    final scopePart = (s == null || s.isEmpty) ? '' : '($s)';
    return '$type$scopePart${breaking ? '!' : ''}: $description';
  }

  @override
  String toString() => format();
}

/// Normalizes a (possibly model-authored) subject into one that is COMPLIANT BY
/// CONSTRUCTION — this is what makes the emitted title spec-valid without
/// trusting the model: an unknown [type] falls back to [fallbackType]; the
/// scope is lower-cased and paren-stripped; the description loses every
/// occurrence of [foreignRef] (the bead id — the anti-pattern this bead
/// exists to kill), collapses its whitespace, drops trailing periods,
/// lower-cases its FIRST letter (only the first — an acronym or an identifier
/// mid-description keeps its case: `infer the PR title`, never
/// `infer the pr title`), and is truncated at a WORD boundary so the whole
/// subject fits [kMaxSubjectChars]; an empty result becomes
/// [fallbackDescription].
ConventionalSubject sanitizeConventionalSubject({
  required String type,
  String? scope,
  bool breaking = false,
  required String description,
  required String foreignRef,
  String fallbackType = 'chore',
  String fallbackDescription = kFallbackDescription,
}) {
  final candidate = type.trim().toLowerCase();
  final cleanType = kConventionalTypes.contains(candidate)
      ? candidate
      : (kConventionalTypes.contains(fallbackType) ? fallbackType : 'chore');
  final rawScope = (scope ?? '')
      .replaceAll(RegExp(r'[()\n]'), ' ')
      .trim()
      .toLowerCase();
  final cleanScope = rawScope.isEmpty ? null : rawScope;

  var text = stripForeignRef(description, foreignRef);
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceAll(RegExp(r'[.\s]+$'), '');
  if (text.isNotEmpty) text = text[0].toLowerCase() + text.substring(1);
  if (text.isEmpty) text = fallbackDescription;

  // The budget the description gets: the whole subject line minus the rendered
  // `type(scope)!: ` prefix.
  final prefix = ConventionalSubject(
    type: cleanType,
    scope: cleanScope,
    breaking: breaking,
    description: '',
  ).format().length;
  final budget = kMaxSubjectChars - prefix;
  return ConventionalSubject(
    type: cleanType,
    scope: cleanScope,
    breaking: breaking,
    description: _truncateAtWord(text, budget < 10 ? 10 : budget),
  );
}

/// Removes every occurrence of [foreignRef] — and its `#rN` rework form — from
/// [text], then the separator it orphans (`pow-8dx — do a thing` ⇒
/// `do a thing`). The belt behind the prompt's "never write the tracker id"
/// rule: a model that writes it anyway still cannot land it in a subject.
String stripForeignRef(String text, String foreignRef) {
  final ref = foreignRef.trim();
  if (ref.isEmpty) return text.trim();
  var out = text.replaceAll(
    RegExp('${RegExp.escape(ref)}(#r\\d+)?', caseSensitive: false),
    '',
  );
  out = out.replaceAll(RegExp(r'^[\s\-—:,\.]+'), '');
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The v1.0.0 violations in [subject] — EMPTY when compliant. The shared
/// checker: [sanitizeConventionalSubject] guarantees the asset's OWN output
/// passes it, the build-agent commit lint (`lintCommitSubjects`) runs it over
/// the branch's commits, and the tests assert the emitted title against it.
/// A non-empty [foreignRef] (the bead id) in the subject is itself a violation —
/// the exact anti-pattern the policy fixes.
List<String> lintConventionalSubject(String subject, {String foreignRef = ''}) {
  final line = subject.trim();
  final match = _subjectGrammar.firstMatch(line);
  if (match == null) {
    return const [
      'not a conventional-commit subject '
          '(`<type>[(scope)][!]: <description>`)',
    ];
  }
  final type = match.group(1)!;
  final description = match.group(4)!;
  final violations = <String>[];
  if (!kConventionalTypes.contains(type)) {
    violations.add('unknown type "$type" (${kConventionalTypes.join('|')})');
  }
  if (description.endsWith('.')) {
    violations.add('the description ends with a period');
  }
  final first = description[0];
  if (first.toUpperCase() == first && first.toLowerCase() != first) {
    violations.add('the description is not lowercase (imperative, lowercase)');
  }
  if (line.length > kMaxSubjectChars) {
    violations.add(
      'the subject is ${line.length} chars (max $kMaxSubjectChars)',
    );
  }
  final ref = foreignRef.trim();
  if (ref.isNotEmpty && line.toLowerCase().contains(ref.toLowerCase())) {
    violations.add(
      'the subject carries the foreign reference "$ref" — it belongs in a '
      'trailer, never the subject',
    );
  }
  return violations;
}

/// Whether [message] carries the git trailer [token] (`Refs: <value>`) with a
/// non-blank value — the INVERTED-tracking half of the policy.
bool hasTrailer(String message, {String token = kDefaultTrailerToken}) =>
    RegExp(
      '^${RegExp.escape(token)}:[ \\t]*\\S',
      multiLine: true,
    ).hasMatch(message);

/// A full commit/PR MESSAGE: the [subject], an optional [body], then the
/// FOOTERS — the `BREAKING CHANGE:` entry (when [breakingChange] is non-blank)
/// and the git [trailers] (`Token: value`) — each block separated by ONE blank
/// line, footers LAST. This is the only shape the asset emits, and the shape
/// the build-agent brief teaches.
String composeCommitMessage({
  required ConventionalSubject subject,
  String body = '',
  String breakingChange = '',
  Map<String, String> trailers = const {},
}) {
  final blocks = <String>[subject.format()];
  if (body.trim().isNotEmpty) blocks.add(body.trim());
  final footers = <String>[
    if (breakingChange.trim().isNotEmpty)
      'BREAKING CHANGE: ${breakingChange.trim()}',
    for (final entry in trailers.entries)
      if (entry.value.trim().isNotEmpty) '${entry.key}: ${entry.value.trim()}',
  ];
  if (footers.isNotEmpty) blocks.add(footers.join('\n'));
  return blocks.join('\n\n');
}

/// [text] cut to at most [max] chars at a WORD boundary (never mid-word), with
/// any trailing punctuation removed.
String _truncateAtWord(String text, int max) {
  if (text.length <= max) return text;
  final cut = text.substring(0, max);
  final space = cut.lastIndexOf(' ');
  final kept = space > max ~/ 2 ? cut.substring(0, space) : cut;
  return kept.replaceAll(RegExp(r'[.,;:\s\-—]+$'), '');
}

/// The DECISION-LOOKUP contract every spec-path agent is handed.
///
/// Lookup is ROSTER-MODE, never a local register grep: the composing station's
/// `decisions index` verb resolves the live mounted-substation roster and
/// returns the UNION of every mounted register. A local-only read is exactly
/// how a spec that contradicted a SIBLING substation's recorded decision
/// carried a PASSING decision grade — a file-watcher approach graded clean
/// against `the_grid#a50-the-dev-mode-reload-tool-extending-adr-0001-d6-s-tool-en`,
/// whose register the lens structurally could not reach.
///
/// This library renders SHELL TEXT for a prompt; it runs nothing. The verb it
/// names is vended by the composing station (`decisions_grid_assets`), which is
/// not a dependency of this pack — the seam is the runner's argv, not a Dart
/// call.
library;

import '../assets/overlay_materializer.dart' show kDefaultOverlayRunner;

/// The substation prefix used when a bead names no substation
/// (`metadata['rig']` absent) — the literal placeholder the agent substitutes
/// with its own repository name.
const String kUnknownSubstationPrefix = '<repo>';

/// The path placeholder a PRE-SPECIFY brief shows: the architect has not
/// written `## Touches` yet, so there is no real surface to qualify.
const String kRosterSurfacePlaceholder = '<path>';

/// One POSIX single-quoted shell token — the apostrophe inside is closed,
/// escaped and reopened (`'"'"'`), so a grid home carrying one still renders
/// as ONE argument.
///
/// `agent_harness.dart`'s private `_sq` is deliberately NOT reused: its
/// contract takes already-sanitized telemetry paths and does not escape an
/// embedded apostrophe, so borrowing it here would widen its input class
/// silently.
String _shellQuoted(String value) {
  const quote = '\'';
  const escapedQuote = '\'"\'"\'';
  return '$quote${value.replaceAll(quote, escapedQuote)}$quote';
}

/// The composing station's ROSTER-MODE decision lookup, as shell text.
///
/// [surface] is a ROSTER-QUALIFIED path (`<repo>/<path>`); absent ⇒ the whole
/// union. NO register-directory argument is ever passed, and that omission is
/// LOAD-BEARING: it is what makes the grid adapter resolve the live
/// mounted-substation roster and return the union rather than only the current
/// repo's register. [runner] is the composing station's verb
/// ([kDefaultOverlayRunner] by default).
///
/// [gridHome] is the COMPOSING STATION's grid home, and a non-blank one renders
/// the verb CWD-QUALIFIED (`cd '<gridHome>' && …`). A station's verb is its own
/// JIT invocation (`dart run lunar:lunar …`) and resolves only where that
/// station's package is, so the bare form handed to an agent standing in a
/// per-bead worktree exits `Could not find package`. Surfaces are
/// roster-qualified, so the cwd carries no path meaning of its own.
///
/// Absent or blank ⇒ the BARE verb, unchanged. That is what
/// [commandDecisionIndexSource] renders: the EXECUTING path already binds the
/// same grid home as its [ShellRunner]'s `workingDirectory`, so a textual `cd`
/// there would be a second, divergent cwd. A blank grid home never means "run
/// it here" for a PROMPT — [rosterDecisionLookupBlock] renders nothing at all.
String rosterDecisionIndexCommand({
  String? surface,
  String runner = kDefaultOverlayRunner,
  String? gridHome,
}) {
  final home = gridHome?.trim() ?? '';
  final verb = surface == null
      ? '$runner decisions index'
      : '$runner decisions index --surface $surface';
  return home.isEmpty ? verb : 'cd ${_shellQuoted(home)} && $verb';
}

/// A backticked span in a spec's `## Touches` section.
final RegExp _backticked = RegExp(r'`([^`]+)`');

/// A token that could be a repository-relative path (no spaces, no prose).
final RegExp _pathToken = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_./+-]*$');

/// The body of [design]'s `## Touches` section, or `''` when it has none.
String _touchesSection(String design) {
  final lines = design.split('\n');
  final start = lines.indexWhere((line) => line.trimRight() == '## Touches');
  if (start < 0) return '';
  final body = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ')) break;
    body.add(line);
  }
  return body.join('\n');
}

/// The ROSTER-QUALIFIED surfaces [rosterDecisionIndexCommand] is run over for
/// the spec carried in [design], each prefixed with [substation].
///
/// Reads the `## Touches` section ONLY — that section is the spec's own
/// statement of what it touches, so the lane cannot mis-derive its own scope.
/// A `lib/src/x.dart:Symbol` token contributes its PATH half; a backticked
/// token that is not a path (a bare symbol, a shell line) is skipped;
/// duplicates collapse in document order. An empty [substation] falls back to
/// [kUnknownSubstationPrefix]. Returns an empty list for a spec with no
/// `## Touches` section — the pre-specify state.
List<String> rosterQualifiedSurfaces({
  required String design,
  required String substation,
}) => rosterQualifiedPaths(
  paths: [
    for (final match in _backticked.allMatches(_touchesSection(design)))
      match.group(1)!,
  ],
  substation: substation,
);

/// The ONE path qualifier — `<substation>/<path>` for every token in [paths]
/// that could be a repository-relative path, deduplicated in first-appearance
/// order, with [kUnknownSubstationPrefix] as the fallback prefix.
///
/// A `lib/src/x.dart:Symbol` token contributes its PATH half; a token that is
/// not a path (a bare symbol, a shell line, prose) is skipped. Shared by the
/// deterministic PRE-specify gather ([AnchorsCapability], which qualifies the
/// bead's code anchors) and the POST-specify [rosterQualifiedSurfaces] (which
/// qualifies the spec's `## Touches`), so the two lookups cannot drift.
List<String> rosterQualifiedPaths({
  required Iterable<String> paths,
  required String substation,
}) {
  final prefix = substation.trim().isEmpty
      ? kUnknownSubstationPrefix
      : substation.trim();
  final seen = <String>{};
  final surfaces = <String>[];
  for (final raw in paths) {
    final token = raw.split(':').first.trim();
    if (!_pathToken.hasMatch(token)) continue;
    if (!token.contains('/') && !token.contains('.')) continue;
    final surface = '$prefix/$token';
    if (seen.add(surface)) surfaces.add(surface);
  }
  return surfaces;
}

/// The per-surface roster lookup an agent must run, one command per line, each
/// CWD-QUALIFIED by [gridHome].
///
/// Empty [surfaces] renders the TEMPLATE form, so a pre-specify brief still
/// names the exact verb the architect will run once it has written
/// `## Touches`.
///
/// A null or blank [gridHome] renders NOTHING — an empty block, and the caller
/// drops its shell fence. This is the PROMPT-facing counterpart of
/// [rosterDecisionIndexCommand]'s bare form: an agent handed a lookup line it
/// cannot run from where it stands falls back to a local register grep, which
/// is the roster blindness this whole contract exists to remove. Say the index
/// is unavailable ([decisionLookupRule] does) rather than name a command that
/// dies `Could not find package`.
String rosterDecisionLookupBlock(
  List<String> surfaces, {
  String runner = kDefaultOverlayRunner,
  String? gridHome,
}) {
  final home = gridHome?.trim() ?? '';
  if (home.isEmpty) return '';
  return (surfaces.isEmpty
          ? [
              rosterDecisionIndexCommand(
                surface: '$kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
                runner: runner,
                gridHome: home,
              ),
            ]
          : [
              for (final surface in surfaces)
                rosterDecisionIndexCommand(
                  surface: surface,
                  runner: runner,
                  gridHome: home,
                ),
            ])
      .join('\n');
}

/// The register's READ rule when NO composing grid home is bound — the honest
/// form, which names no invocation at all.
///
/// The lane reads the registers by hand instead, and every clause the bound
/// rule carries about FORCE survives: the sibling register keeps equal weight,
/// the citation identity stays canonical, an empty result is still real, and an
/// unreadable register is still refused as a clean grade. What is dropped is
/// the COMMAND — a station verb resolves only from its own grid home, so a
/// lookup line rendered without one exits `Could not find package` in the
/// lane's worktree. An agent handed that line falls back to a local grep and
/// reports the tool unavailable, which is the roster blindness this contract
/// exists to remove, wearing a passing grade.
const String _unavailableDecisionLookupRule =
    'The composing station\'s ROSTER-MODE `decisions index` is UNAVAILABLE '
    'here: no composing grid home is bound, and that verb resolves only where '
    'the station\'s own package is, so naming it for this worktree would name '
    'a command that cannot run (`Could not find package`). Read the registers '
    'DIRECTLY instead: inspect `docs/decisions/` in EVERY mounted register — '
    'this substation\'s and every sibling substation\'s — for entries whose '
    'recorded surfaces match the repository-relative paths under review (for '
    'a spec, every literal path in its `## Touches` section). Keep what every '
    'register holds: a SIBLING substation\'s entry has exactly the same force '
    'as a local one, and reading only this repo\'s register is the blindness '
    'the roster UNION exists to remove. Quote the LOAD-BEARING clause of each '
    'entry that governs and cite it by its canonical `<repo>#<slug>` identity '
    '— for example `the_grid#admission-authority-boundary` (a migrated entry '
    'may also carry `register.legacy-id`, whose old citation still resolves). '
    'Finding no governing entry after reading every register is a real '
    'result, not an error: say so and name the paths and the registers that '
    'verified it. A register you could NOT read is NOT "no decision applies": '
    'report the failure verbatim and never grade an unread register clean.';

/// The register's READ rule — stated to every agent on the spec path.
///
/// The omission of a register-directory argument is named as LOAD-BEARING, the
/// sibling register is given equal force, the citation identity is the
/// canonical `<repo>#<slug>`, an empty union is declared a real result, and a
/// FAILED lookup is explicitly refused as a clean grade (`decisions index` in
/// roster mode throws on a malformed sibling entry, and a crashed lookup read
/// as "no decision applies" would ship the very blindness this rule removes).
///
/// [gridHome] is the composing station's grid home ([rosterDecisionIndexCommand]
/// renders the `cd`). A null or blank one yields
/// [_unavailableDecisionLookupRule]: the rule REFUSES to name a verb the lane
/// cannot run, and directs the direct register read instead.
String decisionLookupRule({
  String runner = kDefaultOverlayRunner,
  String? gridHome,
}) {
  final home = gridHome?.trim() ?? '';
  if (home.isEmpty) return _unavailableDecisionLookupRule;
  final command = rosterDecisionIndexCommand(
    surface: '$kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
    runner: runner,
    gridHome: home,
  );
  return 'Look decisions up through the composing station\'s ROSTER-MODE '
      'index, '
      'never a local register grep. Read every literal path in the spec\'s '
      '`## Touches` section, prefix each repository-relative path with its '
      'substation repository name, and run '
      '`$command` once per '
      'unique roster-qualified path. Run it FROM the composing station\'s grid '
      'home exactly as shown — that verb resolves only where the station\'s '
      'own package is, and the same command run from this worktree exits '
      'non-zero with `Could not find package`. '
      'Pass NO register-directory argument: that '
      'omission is LOAD-BEARING — the grid adapter resolves the live '
      'mounted-substation roster and the command returns the UNION of every '
      'mounted register rather than only this repo\'s. Read the structured '
      'JSON '
      '`decisions` array and KEEP results from every `originRegister`: a '
      'SIBLING '
      'substation\'s entry has exactly the same force as a local one. Resolve '
      'each returned record by its `slug` under its `originPath`, quote the '
      'load-bearing clause, and cite it by its canonical `<repo>#<slug>` '
      'identity — for example `the_grid#admission-authority-boundary` (a '
      'migrated entry may also carry `register.legacy-id`, whose old citation '
      'still resolves). An EMPTY `decisions` array for every queried '
      'surface means no recorded decision governs these surfaces: say so and '
      'name the roster-qualified paths that verified it — an empty union is a '
      'real result, not an error. A lookup that FAILS or exits non-zero is '
      'NOT '
      '"no decision applies": report the failure verbatim and never grade a '
      'crashed index clean.';
}

/// The register's WRITE rule — stated to every agent that could RECORD a
/// decision (the specify architect writes one; the spec critic grades it).
///
/// `docs/decisions/` is the write target and an entry BINDS ON WRITE, so there
/// is no advisory tier and no `A<n>` serial for concurrent worktrees to collide
/// on. The vended `decide` skill owns the entry SHAPE; this rule POINTS at that
/// contract rather than restating a second schema beside it.
const String kDecisionWriteRule =
    'A decision the design MAKES — or DEPARTS FROM — is RECORDED as a new '
    'slug entry under `docs/decisions/`, following the vended `decide` '
    'skill\'s contract (`.claude/skills/decide/SKILL.md`: front matter with '
    '`status`, `date`, `decision-makers`, and a `register` block carrying '
    '`spec: 1`, `surfaces`, and its edges). That skill is authoritative for '
    'the entry shape — follow it, never restate it. An entry BINDS ON WRITE: '
    'there is no advisory tier and no `A<n>` serial to collide on. '
    '`docs/adr/ADR-0000-ai-decision-register.md` is READ-ONLY LEGACY — cite '
    'it, NEVER append to it. When `docs/decisions/` does not exist in the '
    'substation, CREATE it with the entry; a missing directory is not a '
    'reason to fall back to ADR-0000.';

/// The prefix a spec's `## ADR Alignment` section is recognized by when the
/// roster union was EMPTY for every queried surface.
const String kNoGoverningDecisionPrefix =
    'No recorded decision governs these surfaces';

/// The prefix a spec's `## ADR Alignment` section is recognized by when the
/// roster lookup FAILED.
const String kFailedDecisionLookupPrefix = 'The roster lookup FAILED';

/// The sentence a spec writes when the roster union is EMPTY for every queried
/// surface — the FORM of [kDecisionLookupRule]'s "an empty union is a real
/// result" clause.
///
/// Homed HERE, beside the rule whose clause it renders, rather than minted a
/// second time on the spec path:
/// `power_station#the-spec-decision-lane-queries-the-roster-union` (1) makes
/// `kDecisionLookupRule` "the single string all of [the rendered lookup
/// surfaces] embed", and a duplicate carrying the same load-bearing clause is
/// exactly the drift that decision closed. `buildSpecifyBrief` renders this
/// sentence and [parseSpecContract] recognizes it by
/// [kNoGoverningDecisionPrefix], so the form the brief DICTATES is the one the
/// gate ACCEPTS.
String noGoverningDecisionSentence({
  String runner = kDefaultOverlayRunner,
  String? gridHome,
}) {
  final home = gridHome?.trim() ?? '';
  if (home.isEmpty) {
    // NOT the literal `docs/decisions/` path the READ rule names: a
    // backticked register path inside `## ADR Alignment` parses as a
    // resolvable CITATION ([isResolvableDecisionReference]), so a sentence
    // that declares an empty union would smuggle one in.
    return '$kNoGoverningDecisionPrefix — verified by direct inspection of '
        'every mounted decision register over '
        '`<the roster-qualified paths>`, the composing station\'s roster '
        'index being unavailable here.';
  }
  return '$kNoGoverningDecisionPrefix — verified via '
      '`${rosterDecisionIndexCommand(runner: runner, gridHome: home)} '
      '--surface` over '
      '`<the roster-qualified paths>`.';
}

/// The sentence a spec writes when the roster lookup FAILED — the FORM of
/// [kDecisionLookupRule]'s "a lookup that FAILS or exits non-zero is NOT 'no
/// decision applies'" clause.
///
/// The companion of [kNoGoverningDecisionSentence], and the reason the two are
/// separate FORMS rather than one:
/// `power_station#the-spec-decision-lane-queries-the-roster-union` (3) —
/// "An empty union is a real result; a CRASHED lookup is not. A lookup that
/// fails or exits non-zero must be reported verbatim and never graded clean."
/// A crashed lookup leaves the union UNKNOWN, so the section cannot be read as
/// citing nothing; it must SAY the lookup crashed and show its output. Naming
/// that form is what lets [parseSpecContract] distinguish the two rather than
/// collapsing a crash into a vacuous empty section.
String failedDecisionLookupSentence({
  String runner = kDefaultOverlayRunner,
  String? gridHome,
}) {
  final home = gridHome?.trim() ?? '';
  if (home.isEmpty) {
    // Same reason as above: no backticked register path in a section whose
    // every backticked token is read as a citation.
    return '$kFailedDecisionLookupPrefix — reported verbatim, never read as '
        'an empty union: reading every mounted decision register '
        'over `<the roster-qualified paths>` failed with '
        '`<the exact output>`.';
  }
  return '$kFailedDecisionLookupPrefix — reported verbatim, never read as an '
      'empty union: '
      '`${rosterDecisionIndexCommand(runner: runner, gridHome: home)} '
      '--surface` over '
      '`<the roster-qualified paths>` exited non-zero with '
      '`<the exact output>`.';
}

/// The DEFAULT-runner rendering of [decisionLookupRule] — the form a caller
/// that composes no station verb (a fence, a parse test) reads.
final String kDecisionLookupRule = decisionLookupRule();

/// The DEFAULT-runner rendering of [noGoverningDecisionSentence].
final String kNoGoverningDecisionSentence = noGoverningDecisionSentence();

/// The DEFAULT-runner rendering of [failedDecisionLookupSentence].
final String kFailedDecisionLookupSentence = failedDecisionLookupSentence();

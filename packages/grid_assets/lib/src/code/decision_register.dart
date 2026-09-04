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

/// The composing station's ROSTER-MODE decision lookup, as shell text.
///
/// [surface] is a ROSTER-QUALIFIED path (`<repo>/<path>`); absent ⇒ the whole
/// union. NO register-directory argument is ever passed, and that omission is
/// LOAD-BEARING: it is what makes the grid adapter resolve the live
/// mounted-substation roster and return the union rather than only the current
/// repo's register. [runner] is the composing station's verb
/// ([kDefaultOverlayRunner] by default).
String rosterDecisionIndexCommand({
  String? surface,
  String runner = kDefaultOverlayRunner,
}) => surface == null
    ? '$runner decisions index'
    : '$runner decisions index --surface $surface';

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

/// The per-surface roster lookup an agent must run, one command per line.
///
/// Empty [surfaces] renders the TEMPLATE form, so a pre-specify brief still
/// names the exact verb the architect will run once it has written
/// `## Touches`.
String rosterDecisionLookupBlock(
  List<String> surfaces, {
  String runner = kDefaultOverlayRunner,
}) =>
    (surfaces.isEmpty
            ? [
                rosterDecisionIndexCommand(
                  surface:
                      '$kUnknownSubstationPrefix/$kRosterSurfacePlaceholder',
                  runner: runner,
                ),
              ]
            : [
                for (final surface in surfaces)
                  rosterDecisionIndexCommand(surface: surface, runner: runner),
              ])
        .join('\n');

/// The register's READ rule — stated to every agent on the spec path.
///
/// The omission of a register-directory argument is named as LOAD-BEARING, the
/// sibling register is given equal force, the citation identity is the
/// canonical `<repo>#<slug>`, an empty union is declared a real result, and a
/// FAILED lookup is explicitly refused as a clean grade (`decisions index` in
/// roster mode throws on a malformed sibling entry, and a crashed lookup read
/// as "no decision applies" would ship the very blindness this rule removes).
String decisionLookupRule({String runner = kDefaultOverlayRunner}) =>
    'Look decisions up through the composing station\'s ROSTER-MODE index, '
    'never a local register grep. Read every literal path in the spec\'s '
    '`## Touches` section, prefix each repository-relative path with its '
    'substation repository name, and run '
    '`$runner decisions index --surface <repo>/<path>` once per '
    'unique roster-qualified path. Pass NO register-directory argument: that '
    'omission is LOAD-BEARING — the grid adapter resolves the live '
    'mounted-substation roster and the command returns the UNION of every '
    'mounted register rather than only this repo\'s. Read the structured JSON '
    '`decisions` array and KEEP results from every `originRegister`: a SIBLING '
    'substation\'s entry has exactly the same force as a local one. Resolve '
    'each returned record by its `slug` under its `originPath`, quote the '
    'load-bearing clause, and cite it by its canonical `<repo>#<slug>` '
    'identity — for example `the_grid#admission-authority-boundary` (a '
    'migrated entry may also carry `register.legacy-id`, whose old citation '
    'still resolves). An EMPTY `decisions` array for every queried '
    'surface means no recorded decision governs these surfaces: say so and '
    'name the roster-qualified paths that verified it — an empty union is a '
    'real result, not an error. A lookup that FAILS or exits non-zero is NOT '
    '"no decision applies": report the failure verbatim and never grade a '
    'crashed index clean.';

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
String noGoverningDecisionSentence({String runner = kDefaultOverlayRunner}) =>
    '$kNoGoverningDecisionPrefix — verified via '
    '`$runner decisions index --surface` over '
    '`<the roster-qualified paths>`.';

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
String failedDecisionLookupSentence({String runner = kDefaultOverlayRunner}) =>
    '$kFailedDecisionLookupPrefix — reported verbatim, never read as an empty '
    'union: `$runner decisions index --surface` over '
    '`<the roster-qualified paths>` exited non-zero with `<the exact output>`.';

/// The DEFAULT-runner rendering of [decisionLookupRule] — the form a caller
/// that composes no station verb (a fence, a parse test) reads.
final String kDecisionLookupRule = decisionLookupRule();

/// The DEFAULT-runner rendering of [noGoverningDecisionSentence].
final String kNoGoverningDecisionSentence = noGoverningDecisionSentence();

/// The DEFAULT-runner rendering of [failedDecisionLookupSentence].
final String kFailedDecisionLookupSentence = failedDecisionLookupSentence();

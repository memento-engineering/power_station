/// The DOCS-CHANGE committee — the third review type, a sibling of the code
/// committee (`committee.dart`) and the spec-readiness committee
/// (`specify.dart`) over the SAME machine: a [Circuit] of rubric-id lanes, the
/// shared `RubricSource` fed by Packaged AI Assets, and the ONE shared
/// [CodeRouteCapability] matrix. No committee machinery is added — a new review
/// type IS a new rubric pack plus its circuit.
///
/// **Why it exists.** A docs-only bead (acceptance "Docs only, no code") drew
/// `test-coverage` = F ("no tests for the change") — unsatisfiable BY DESIGN on
/// a prose diff, so the A/A/F spread tripped the human-ultimatum arm and every
/// ADR/doc bead false-gated. The critic's own rationale named the REAL gap, and
/// it is MECHANICAL rather than judgemental: nothing fails automatically when a
/// doc edit breaks a cited file path, drops a required section, or reintroduces
/// banned terminology. So the docs committee's GATING lanes are three
/// DETERMINISTIC checks — [kCitationPathsRubric], [kTerminologyBanRubric],
/// [kSectionStructureRubric] — beside the standard `spec-adherence` critic, and
/// `test-coverage` is never mounted.
///
/// **SELECTION, and the constraint that shapes it.** The engine's circuit graph
/// is STATIC: a [SubCircuitStep] names its `circuitId` as a const, and
/// `eligibleSteps` has no conditional-mount arm. The only asset-side seam that
/// picks a circuit per bead is the [SessionResolver], which is handed
/// `(Bead, SessionProjection?)` — and `SessionProjection.cursor` is documented
/// as ALWAYS EMPTY since the_grid's tg-eli phase 2 (the live cursor is computed
/// inside `SessionScope`, below this seam). So the resolver cannot read a git
/// diff, and it cannot read a prior step's result. Selection therefore reads the
/// bead's DECLARED change surface — the paths its spec cites in `## Touches`
/// ([changeShapeOf]) — and the docs committee VERIFIES the real diff itself:
/// every docs lane refuses LOUDLY (grade F, source files named) when the
/// pinned diff touches a path [isMetadataPath] does not admit (`docs/**` and
/// `*.md`, plus the non-code configuration surfaces — `CHANGELOG.md`,
/// `pubspec.yaml`, `*.json`, `*.toml`, `LICENSE`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;

import 'circuit_migration.dart';
import 'committee.dart';
import 'committee_selection.dart';
import 'specify.dart';

/// The lane whose every CITED file path must resolve in the tree.
const String kCitationPathsRubric = 'citation-paths-resolve';

/// The lane that refuses the banned seam word (the org rule: the seam word is
/// `extension`, and the other one is reserved for third-party proper nouns).
const String kTerminologyBanRubric = 'terminology-ban';

/// The lane that requires the sections the bead NAMES ([kDocsSectionsKey]).
const String kSectionStructureRubric = 'section-structure';

/// The three DETERMINISTIC gating lanes — the docs diff's answer to
/// `code-validation`. Any F is a hard block, decided by the route's matrix.
const List<String> kDocsGatingRubrics = [
  kCitationPathsRubric,
  kTerminologyBanRubric,
  kSectionStructureRubric,
];

/// The docs committee's LLM lane — the standard `spec-adherence` critic, shared
/// verbatim with the code committee (one rubric, two committees).
const List<String> kDocsLlmRubrics = ['spec-adherence'];

/// Every docs-committee rubric id, gating lanes first.
const List<String> kDocsCommitteeRubrics = [
  ...kDocsGatingRubrics,
  ...kDocsLlmRubrics,
];

/// The capability id the three mechanical lanes share (`params['rubric']`
/// selects the check — the same one-capability-many-lanes shape `critic` uses).
const String kDocsCheckCapabilityId = 'docs-check';

/// The docs review circuit's registry id.
const String kDocsReviewCircuitId = 'docs_review';

/// The root circuit's review step id — the [SubCircuitStep] whose `circuitId`
/// [withReviewCircuitId] re-points. A LITERAL: it is a persisted cursor key.
const String kReviewStepId = 'review';

/// The bead-metadata key naming the sections a changed doc must carry (CSV).
const String kDocsSectionsKey = 'docs_sections';

/// Which committee a bead's change belongs to.
enum ChangeShape {
  /// Prose only — `docs/**` and `*.md`.
  docs,

  /// Non-code, but not prose either — a `CHANGELOG.md` beside a
  /// `pubspec.yaml`, a `*.yaml` / `*.json` / `*.toml` config, a `LICENSE`
  /// ([isMetadataPath]). It meets the SAME committee as [docs]: a release
  /// bump has no test to cover either, so `test-coverage` must never grade it.
  metadata,

  /// Anything else (the DEFAULT: an undeclared bead gets the code committee).
  code,
}

/// Whether [path] is a DOCS path — any `.md` file anywhere, or any path with a
/// segment that is exactly `docs`.
bool isDocsPath(String path) {
  final normalized = p.posix.normalize(path.trim());
  if (normalized.isEmpty || normalized == '.') return false;
  if (normalized.toLowerCase().endsWith('.md')) return true;
  return p.posix.split(normalized).contains('docs');
}

/// The file extensions a METADATA path may carry — prose and configuration,
/// never source.
const Set<String> kMetadataPathExtensions = {
  '.md',
  '.yaml',
  '.yml',
  '.json',
  '.toml',
};

/// The extension-less file NAMES a metadata path may carry.
const Set<String> kMetadataPathFilenames = {'LICENSE'};

/// Whether [path] is a METADATA path — prose or configuration, never source.
///
/// A strict SUPERSET of [isDocsPath]: every docs path is metadata, plus any
/// file whose extension is in [kMetadataPathExtensions] (`CHANGELOG.md`,
/// `pubspec.yaml`, `example-config.json`, `Cargo.toml`) and any file whose
/// name is in [kMetadataPathFilenames] (`LICENSE`).
///
/// An ALLOW-list, never a deny-list of source extensions: a `.dart` / `.swift`
/// / `.kt` / `.go` / `.py` / `.js` / `.ts` file is not metadata because it is
/// not LISTED — and neither is an unlisted surface nobody thought of (a
/// `tool/release.sh`, a template, an extension-less script). That keeps
/// [changeShapeOf]'s fail-to-code posture: an unknown surface meets the CODE
/// committee rather than sneaking past a prose one.
bool isMetadataPath(String path) {
  if (isDocsPath(path)) return true;
  final normalized = p.posix.normalize(path.trim());
  if (normalized.isEmpty || normalized == '.') return false;
  final name = p.posix.basename(normalized);
  if (kMetadataPathFilenames.contains(name)) return true;
  final extension = p.posix.extension(name).toLowerCase();
  return extension.isNotEmpty && kMetadataPathExtensions.contains(extension);
}

/// [raw] as a citable repo-relative path, or null when it is not one.
///
/// A citation is a backticked span or a markdown-link target that NAMES a path:
/// no whitespace, no URL scheme, at least one `/`, and either a trailing `/`
/// (a directory) or a file extension. A trailing `#anchor` and a trailing
/// `:Symbol` / `:42` locator are stripped first (`## Touches` writes
/// `lib/src/x.dart:Symbol`). A git range (`origin/main...HEAD`) and a glob are
/// rejected outright — they are not paths and must never be probed.
String? normalizeCitedPath(String raw) {
  var candidate = raw.trim();
  final anchor = candidate.indexOf('#');
  if (anchor == 0) return null;
  if (anchor > 0) candidate = candidate.substring(0, anchor);
  if (!candidate.contains('://')) {
    final locator = candidate.indexOf(':');
    if (locator > 0) candidate = candidate.substring(0, locator);
  }
  candidate = candidate.trim();
  if (candidate.isEmpty) return null;
  if (candidate.contains(RegExp(r'\s'))) return null;
  if (candidate.contains('://')) return null;
  if (candidate.contains('...')) return null;
  if (candidate.contains('*') || candidate.contains('?')) return null;
  if (!candidate.contains('/')) return null;
  if (!candidate.endsWith('/') && !_fileExtension.hasMatch(candidate)) {
    return null;
  }
  return candidate;
}

final RegExp _backtickSpan = RegExp(r'`([^`\n]+)`');
final RegExp _linkTarget = RegExp(r'\]\(([^)\s]+)\)');
final RegExp _fileExtension = RegExp(r'\.[A-Za-z0-9]{1,8}$');

/// Every repo-relative path CITED in [markdown], sorted and de-duplicated.
List<String> citedPaths(String markdown) {
  final paths = <String>{};
  for (final matches in [
    _backtickSpan.allMatches(markdown),
    _linkTarget.allMatches(markdown),
  ]) {
    for (final match in matches) {
      final candidate = normalizeCitedPath(match.group(1)!);
      if (candidate != null) paths.add(candidate);
    }
  }
  return paths.toList()..sort();
}

/// The bead's DECLARED change shape — [ChangeShape.docs] iff its `## Touches`
/// section cites at least one path and EVERY cited path is a docs path;
/// [ChangeShape.metadata] iff every cited path is a METADATA path
/// ([isMetadataPath]) but not every one is prose (a `CHANGELOG.md` beside a
/// `pubspec.yaml` — the pow-x6k receipt).
///
/// Fail-to-code by construction: a bead with no `## Touches` section, one that
/// cites nothing, or one citing a single unlisted surface gets the CODE
/// committee. The docs committee is the narrow, opt-in lane; the code
/// committee stays the default.
ChangeShape changeShapeOf(Bead bead) {
  final touchesAt = bead.design.indexOf('## Touches');
  if (touchesAt < 0) return ChangeShape.code;
  final cited = citedPaths(sectionBodyAt(bead.design, touchesAt));
  if (cited.isEmpty) return ChangeShape.code;
  if (cited.every(isDocsPath)) return ChangeShape.docs;
  if (cited.every(isMetadataPath)) return ChangeShape.metadata;
  return ChangeShape.code;
}

/// The ADDED lines of each file in a unified [diff], keyed by repo-relative
/// path — the ONLY text the mechanical lanes grade. This is the scope-pinning
/// doctrine one level down (ADR-0000 A9): grade the bead's OWN delta, never the
/// ambient worktree, so a pre-existing offence in an untouched paragraph is not
/// this bead's finding.
Map<String, List<String>> addedLinesByFile(String diff) {
  final added = <String, List<String>>{};
  String? current;
  for (final line in const LineSplitter().convert(diff)) {
    if (line.startsWith('diff --git ')) {
      current = null;
      continue;
    }
    if (line.startsWith('+++ ')) {
      final target = line.substring(4).trim().split(RegExp(r'\s')).first;
      current = target == '/dev/null'
          ? null
          : (target.startsWith('b/') ? target.substring(2) : target);
      continue;
    }
    if (line.startsWith('---') || line.startsWith('@@')) continue;
    if (current != null && line.startsWith('+')) {
      added.putIfAbsent(current, () => <String>[]).add(line.substring(1));
    }
  }
  return added;
}

/// Findings for [kCitationPathsRubric]: every path an ADDED doc line cites must
/// resolve — relative to the repo root, or to the citing doc's own directory (a
/// markdown link is doc-relative). [exists] is the injected probe (tests pass a
/// pure set membership — Fakes, not mocks).
List<String> citationFindings({
  required Map<String, List<String>> addedLines,
  required bool Function(String repoRelativePath) exists,
}) {
  final findings = <String>[];
  for (final entry in addedLines.entries) {
    final docDir = p.posix.dirname(entry.key);
    for (final cited in citedPaths(entry.value.join('\n'))) {
      final docRelative = p.posix.normalize(p.posix.join(docDir, cited));
      if (exists(cited) || exists(docRelative)) continue;
      findings.add(
        '${entry.key}: cited path `$cited` does not exist in the tree',
      );
    }
  }
  return findings;
}

/// [line] with every markdown QUOTATION / EMPHASIS span blanked to spaces of
/// the SAME length (so match offsets stay honest), and a `>` blockquote line
/// blanked whole. A quoted word is a MENTION — the org rule itself is written
/// as `never "plugin"` in two shipped rubrics, and stating a ban must never
/// trip it. A word used BARE in prose is a USE, and that is the offence.
String maskQuotations(String line) {
  if (line.trimLeft().startsWith('>')) return ' ' * line.length;
  return line.replaceAllMapped(
    _quotationSpan,
    (match) => ' ' * match.group(0)!.length,
  );
}

final RegExp _quotationSpan = RegExp(
  r'`[^`]*`' // an inline code span
  r'|"[^"]*"' // a double-quoted mention
  r"|'[^']*'" // a single-quoted mention
  r'|\*\*[^*]+\*\*' // bold
  r'|\*[^*]+\*', // italic
);

final RegExp _bannedTerm = RegExp(r'\bplugins?\b', caseSensitive: false);

/// A Capitalized token — optionally followed by up to two lowercase modifier
/// words — sitting immediately before the banned term (`Flutter platform ` in
/// `Flutter platform plugins`). Group 1 is the capitalized token itself.
final RegExp _properNounLead = RegExp(
  r'([A-Z][A-Za-z0-9_.+-]*)'
  r'(?:[ \t]+[a-z][A-Za-z0-9_.+-]*){0,2}'
  r'[ \t]+$',
);

/// The closed class of English words whose capital is GRAMMAR, not a name — a
/// determiner or quantifier capitalized only because it opens a sentence.
/// Without it the exemption would swallow `The plugin model is wrong.`, the
/// most ordinary shape of the offence. A short, closed, LANGUAGE-level list —
/// never a vendor list, which is exactly what this lane refuses to maintain.
const Set<String> _grammaticalCapitals = {
  'a',
  'an',
  'the',
  'this',
  'that',
  'these',
  'those',
  'each',
  'every',
  'any',
  'no',
  'some',
  'one',
  'its',
  'their',
  'our',
  'your',
  'his',
  'her',
  'my',
  'it',
};

/// Whether the text [before] the banned term ends in a third-party PROPER NOUN
/// — the org rule's own carve-out ("reserved for third-party artifacts named
/// that way by their own ecosystems", e.g. `Flutter platform plugins`). The
/// CAPITAL is the signal, so no vendor list is maintained; a capital that is
/// merely grammatical ([_grammaticalCapitals]) is not a name and never exempts.
bool _hasProperNounLead(String before) {
  final match = _properNounLead.firstMatch(before);
  if (match == null) return false;
  return !_grammaticalCapitals.contains(match.group(1)!.toLowerCase());
}

/// Findings for [kTerminologyBanRubric] over the ADDED doc lines.
List<String> terminologyFindings(Map<String, List<String>> addedLines) {
  final findings = <String>[];
  for (final entry in addedLines.entries) {
    for (final line in entry.value) {
      final masked = maskQuotations(line);
      for (final match in _bannedTerm.allMatches(masked)) {
        if (_hasProperNounLead(masked.substring(0, match.start))) continue;
        findings.add(
          '${entry.key}: banned term "${match.group(0)}" used bare in prose — '
          'the seam word is `extension`; the banned word is reserved for a '
          'third-party artifact named that way by its own ecosystem '
          '(`Flutter platform plugins`). Offending line: ${line.trim()}',
        );
      }
    }
  }
  return findings;
}

/// Every markdown heading TEXT in [markdown], read from PROSE — a heading that
/// exists only inside a fenced block is evidence, not a section (the same rule
/// the spec gate holds, ADR-0000 A19).
Set<String> headingsOf(String markdown) => {
  for (final match in _headingLine.allMatches(proseOnly(markdown)))
    match.group(1)!.trim(),
};

final RegExp _headingLine = RegExp(r'^#{1,6}[ \t]+(.+)$', multiLine: true);

/// The sections the bead REQUIRES of the docs it changes — the CSV
/// [kDocsSectionsKey] metadata. Absent or blank ⇒ no requirement, so this lane
/// is vacuously A. That is deliberate: the ruling says "required sections
/// present WHEN THE BEAD NAMES THEM", and a lane that invented its own
/// requirement would gate on taste.
List<String> requiredDocSections(Bead bead) {
  final raw = bead.metadata[kDocsSectionsKey];
  if (raw is! String) return const [];
  return raw
      .split(',')
      .map((section) => section.replaceFirst(RegExp(r'^#+\s*'), '').trim())
      .where((section) => section.isNotEmpty)
      .toList();
}

/// Findings for [kSectionStructureRubric]: when [requiredSections] is non-empty,
/// every changed doc in [docBodies] must carry each one as a heading.
List<String> sectionFindings({
  required Map<String, String> docBodies,
  required List<String> requiredSections,
}) {
  if (requiredSections.isEmpty) return const [];
  final findings = <String>[];
  for (final entry in docBodies.entries) {
    final headings = headingsOf(entry.value);
    for (final section in requiredSections) {
      if (headings.contains(section)) continue;
      findings.add('${entry.key}: required section `$section` is missing');
    }
  }
  return findings;
}

/// One deterministic docs lane, selected by `params['rubric']` — the same
/// one-capability-many-lanes shape [CriticCapability] uses, and the same
/// runner-not-agent posture as `code-validation` / `spec-validation`
/// (ADR-0000 A13(2)): it ALWAYS completes, with the grade in its [Ok] payload,
/// leaving the route as the single decision point.
///
/// It reads the round's PINNED DIFF ([pinnedDiffPath], written by
/// [PinDiffCapability], which every lane `dependsOn`) rather than shelling out
/// to git again — one git call per round, one review scope for every lane.
///
/// Three fail-closed refusals, each LOUD and each naming what it refused:
///  - no ambient [Bead]/[Workspace] ⇒ F;
///  - no pinned diff on disk ⇒ F (the lane cannot see what it must grade);
///  - a pinned diff touching a SOURCE path (anything [isMetadataPath] does
///    not admit) ⇒ F, naming the files — the docs committee was selected from
///    the bead's DECLARED surface, and this is the verification of the REAL
///    one. A mis-declared bead hard-blocks; it never gets code reviewed by a
///    prose committee.
class DocsCheckCapability extends ServiceCapability {
  /// Creates the lane.
  const DocsCheckCapability();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); everything below is
    // pure over the captured values plus the workspace's own files.
    final rubric = args.params['rubric'] ?? '';
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      return const Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale': 'no ambient work Bead / Workspace to check — fail-closed',
      });
    }
    final workspaceDir = workspace.workspaceDir;
    final pinned = File(pinnedDiffPath(workspaceDir));
    if (!pinned.existsSync()) {
      return Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale':
            'no pinned diff at ${pinned.path} — the `$rubric` lane cannot see '
            'the change it grades; fail-closed',
      });
    }
    final diff = pinned.readAsStringSync();
    final changed = changedFilesIn(diff);
    final source = changed.where((path) => !isMetadataPath(path)).toList()
      ..sort();
    if (source.isNotEmpty) {
      return Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale':
            'the docs committee was selected but the pinned diff touches '
            '${source.length} source file(s): ${source.join(', ')} — a code '
            'change belongs to the code committee',
      });
    }
    final added = addedLinesByFile(diff);
    final findings = switch (rubric) {
      kCitationPathsRubric => citationFindings(
        addedLines: added,
        exists: (path) => _existsUnder(workspaceDir, path),
      ),
      kTerminologyBanRubric => terminologyFindings(added),
      kSectionStructureRubric => sectionFindings(
        docBodies: _readDocs(workspaceDir, changed),
        requiredSections: requiredDocSections(bead),
      ),
      _ => ['unknown docs rubric "$rubric" — the lane is misconfigured'],
    };
    return findings.isEmpty
        ? const Ok({'grade': 'A', 'transport': 'structural'})
        : Ok({
            'grade': 'F',
            'transport': 'structural',
            'rationale': findings.join('; '),
          });
  }

  /// Whether [path] resolves under [root] as a file OR a directory.
  static bool _existsUnder(String root, String path) {
    final full = p.join(root, path);
    return File(full).existsSync() || Directory(full).existsSync();
  }

  /// The on-disk body of each changed doc that still EXISTS (a deleted doc has
  /// no sections to carry, so it is not held to them).
  static Map<String, String> _readDocs(String root, Iterable<String> paths) {
    final bodies = <String, String>{};
    for (final path in paths) {
      final file = File(p.join(root, path));
      if (file.existsSync()) bodies[path] = file.readAsStringSync();
    }
    return bodies;
  }
}

/// The DOCS review circuit (id [kDocsReviewCircuitId]) — the code committee's
/// shape with its lane set replaced: the same hygiene step, the same diff pin,
/// the same route. Four lanes: THREE deterministic gating checks + the
/// `spec-adherence` critic. `test-coverage` and `regression-risk` are absent by
/// construction — there is no test to cover and no runtime behaviour to regress
/// on a prose diff, and the F they must otherwise return is the defect this
/// circuit fixes.
const Circuit kDocsReviewCircuit = Circuit(
  id: kDocsReviewCircuitId,
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
      stepId: kCitationPathsRubric,
      capabilityId: kDocsCheckCapabilityId,
      params: {'rubric': kCitationPathsRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kTerminologyBanRubric,
      capabilityId: kDocsCheckCapabilityId,
      params: {'rubric': kTerminologyBanRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kSectionStructureRubric,
      capabilityId: kDocsCheckCapabilityId,
      params: {'rubric': kSectionStructureRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: 'spec-adherence',
      capabilityId: 'critic',
      params: {'rubric': 'spec-adherence'},
      dependsOn: {kPinDiffStep},
    ),
    // The SHADOW committee selector (bead `pow-1nl.1.1`) — the CODE stage (a
    // docs diff is still a diff), a non-authoritative sibling of the four
    // lanes, and a dependency of nothing.
    CapabilityStep(
      stepId: kCommitteeSelectionStep,
      capabilityId: kCommitteeSelectionStep,
      dependsOn: {kPinDiffStep},
      params: {
        kCommitteeSelectionStageParam: 'code_review',
        kCommitteeFullRubricsParam:
            'citation-paths-resolve,terminology-ban,section-structure,'
            'spec-adherence',
        kCommitteeGatingRubricsParam:
            'citation-paths-resolve,terminology-ban,section-structure',
      },
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {
        kCitationPathsRubric,
        kTerminologyBanRubric,
        kSectionStructureRubric,
        'spec-adherence',
      },
      // LITERAL CSVs (a const context cannot join a list); a test asserts they
      // equal `kDocsCommitteeRubrics.join(',')` / `kDocsGatingRubrics.join(',')`
      // so the two can never drift.
      params: {
        'critics':
            'citation-paths-resolve,terminology-ban,section-structure,'
            'spec-adherence',
        'gating': 'citation-paths-resolve,terminology-ban,section-structure',
        // The stage the SHADOW receipt is filed under (bead `pow-1nl.1.1`);
        // this route's matrix never reads it.
        kCommitteeSelectionStageParam: 'code_review',
      },
    ),
  ],
);

/// [base] with its [kReviewStepId] [SubCircuitStep] re-pointed at [circuitId] —
/// the ONE difference between the code root shape and the docs root shape.
///
/// DERIVED rather than duplicated: unlike `circuit_migration.dart`'s FROZEN
/// shapes (which must never follow a future rename), the docs root shape must
/// track `kCodeCircuit` step for step. It takes [base] as a VALUE so this
/// library imports nothing from `code_capabilities.dart` (config = values,
/// ADR-0008 D-H — the same anti-cycle posture [CodeCircuitResolver] holds).
///
/// LOUD or gone: a [base] with no `review` sub-circuit step means the root shape
/// moved and the docs committee would silently never mount, so it throws.
Circuit withReviewCircuitId(Circuit base, String circuitId) {
  final steps = <CircuitStep>[];
  var replaced = false;
  for (final step in base.steps) {
    if (step is SubCircuitStep && step.stepId == kReviewStepId) {
      steps.add(
        SubCircuitStep(
          stepId: step.stepId,
          circuitId: circuitId,
          params: step.params,
          dependsOn: step.dependsOn,
        ),
      );
      replaced = true;
    } else {
      steps.add(step);
    }
  }
  if (!replaced) {
    throw StateError(
      'withReviewCircuitId: circuit "${base.id}" carries no `$kReviewStepId` '
      'SubCircuitStep to re-point at "$circuitId" — the root shape moved and '
      'the docs committee would silently never mount',
    );
  }
  return base.copyWith(steps: steps);
}

/// The bead → root-circuit policy that picks the REVIEW COMMITTEE by the bead's
/// declared change shape — the production replacement for
/// `CodeCircuitResolver(kCodeCircuit)`.
///
/// It WRAPS [CodeCircuitResolver] rather than replacing it: the migration guard
/// still classifies an old-shape survivor and freezes it (such a session keeps
/// the code committee, which is correct — its cursor was minted under it), and
/// this class only chooses which CURRENT shape the guard is handed.
///
/// [code] arrives as a VALUE (production passes `kCodeCircuit`) so this library
/// stays free of `code_capabilities.dart`, exactly as [CodeCircuitResolver]
/// does. Stateless and const: it caches nothing, and the classification is
/// recomputed on every `WorkBead.build` (D-H: never snapshot reactive state).
///
/// ARMING NOTE (out of this repo's diff): the live station composes the resolver
/// in space_station `lib/src/up_command.dart`. The docs committee is armed only
/// when that line becomes `const ChangeShapeCircuitResolver(kCodeCircuit)`.
class ChangeShapeCircuitResolver implements SessionResolver {
  /// Creates the resolver over the CURRENT code root circuit [code], mounting
  /// [selectionPolicy] as the ambient shadow-selection policy value.
  const ChangeShapeCircuitResolver(
    this.code, {
    this.selectionPolicy = kCommitteeSelectionPolicy,
  });

  /// The CURRENT code root circuit — `kCodeCircuit` in production.
  final Circuit code;

  /// The shadow committee-selection policy this session's selector reads
  /// (bead `pow-1nl.1.1`). Config = VALUES in the tree (ADR-0008 D-H): it is
  /// mounted as an `InheritedSeed` above the session and re-read at every
  /// capability entry, never cached in a field the selector consults.
  final CommitteeSelectionPolicy selectionPolicy;

  /// The root circuit for [shape] — [ChangeShape.docs] and
  /// [ChangeShape.metadata] share the docs committee (neither carries a test
  /// to cover), and [ChangeShape.code] keeps the default.
  Circuit circuitFor(ChangeShape shape) => switch (shape) {
    ChangeShape.docs ||
    ChangeShape.metadata => withReviewCircuitId(code, kDocsReviewCircuitId),
    ChangeShape.code => code,
  };

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      InheritedSeed<CommitteeSelectionPolicy>(
        value: selectionPolicy,
        child: CodeCircuitResolver(
          // Recomputed on EVERY build — the classification is never cached, so
          // a bead whose Touches change moves committees on the next build.
          circuitFor(changeShapeOf(bead)),
        ).sessionFor(bead: bead, session: session),
      );
}

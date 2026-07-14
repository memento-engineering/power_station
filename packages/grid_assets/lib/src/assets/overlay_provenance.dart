/// The PROVENANCE stamp every materialized overlay file carries.
///
/// An installed asset is COMMITTED, not gitignored — the operator seat IS the
/// station's manual, so a fresh clone must hold it without a build step. The
/// stamp is what makes that safe: it tells a GENERATED file from a hand-authored
/// one. Two invariants ride it:
///
/// - **Never clobber what we did not generate.** A target file with no stamp is
///   BLOCKED, never overwritten (`OverlayFileBlocked`).
/// - **Drift is detectable.** `assets install --check` re-renders the source and
///   compares it to [stripProvenance] of the installed file, so only the BODY
///   decides drift. A ref-only difference is NOT drift — re-stamping every file
///   on every grid_assets commit would churn the operator's tree for nothing.
///
/// The stamp is FORMAT-AWARE, because a comment ABOVE the content would break
/// both file shapes the overlay vends: a SKILL.md's YAML frontmatter must open
/// on line 1 (the harness's skill discovery parses it there), and JSON has no
/// comments at all. So the stamp goes INSIDE each format — and a file type with
/// no provenance syntax is REFUSED (guards LOUD or GONE: an unstampable file
/// could never be told from a hand-authored one, so the overlay may not vend it).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The substring every stamped file carries — the detection AND strip key.
const String kProvenanceMarker = 'generated from grid_assets@';

/// The source ref recorded when the overlay's checkout cannot be probed (the
/// package came from pub, or git is absent). Never a throw: an un-probable ref
/// is not a packaging bug.
const String kUnknownSourceRef = 'unknown';

/// How a vended file carries its stamp — sealed, so every vended file type is
/// faced with an exhaustive `switch`.
sealed class ProvenanceSyntax {
  /// Creates the syntax.
  const ProvenanceSyntax();
}

/// A `.md` whose first line opens a YAML frontmatter block (`---`): the stamp is
/// a YAML COMMENT on line 2, so the frontmatter still OPENS on line 1 and the
/// harness's skill discovery still parses it.
final class YamlFrontmatterProvenance extends ProvenanceSyntax {
  /// Creates the frontmatter syntax.
  const YamlFrontmatterProvenance();
}

/// A `.json` object: the stamp is a top-level `"$generated"` string field,
/// inserted textually right after the opening brace — the rest of the file is
/// preserved byte-for-byte (no re-encode, so an install never reformats the
/// operator's settings).
final class JsonObjectProvenance extends ProvenanceSyntax {
  /// Creates the JSON syntax.
  const JsonObjectProvenance();
}

/// The provenance syntax for [relativePath] carrying [body].
///
/// THROWS a [StateError] naming the path when the file type has no provenance
/// syntax — LOUD, because an unstampable file could never be told apart from a
/// hand-authored one, so the overlay refuses to vend it.
ProvenanceSyntax provenanceSyntaxFor(String relativePath, String body) {
  final lines = const LineSplitter().convert(body);
  final extension = p.extension(relativePath);
  if (extension == '.md' && lines.isNotEmpty && lines.first.trim() == '---') {
    return const YamlFrontmatterProvenance();
  }
  if (extension == '.json' && _openingBraceLine(lines) >= 0) {
    return const JsonObjectProvenance();
  }
  throw StateError(
    'no provenance syntax for "$relativePath" — a vended overlay file is a '
    'frontmatter-led .md or a JSON object (.json); an unstampable file could '
    'never be told from a hand-authored one, so it is never installed',
  );
}

/// [body] with its provenance stamp inserted. [sourceRef] is the grid_assets ref
/// it was generated from; [runner] is the composing station's verb, so the stamp
/// names the exact command that regenerates the file.
///
/// THROWS a [StateError] when the file type is unstampable (via
/// [provenanceSyntaxFor]), or when stamping a `.json` would not leave valid JSON
/// — a stamped settings file the harness cannot parse is worse than none.
String stampProvenance(
  String body, {
  required String relativePath,
  required String sourceRef,
  required String runner,
}) {
  final syntax = provenanceSyntaxFor(relativePath, body);
  final lines = const LineSplitter().convert(body);
  final note = switch (syntax) {
    YamlFrontmatterProvenance() =>
      '# $kProvenanceMarker$sourceRef — do not edit; run '
          '`$runner assets install`',
    JsonObjectProvenance() =>
      '  "\$generated": "$kProvenanceMarker$sourceRef — do not edit; run '
          '`$runner assets install`",',
  };
  final at = switch (syntax) {
    YamlFrontmatterProvenance() => 1,
    JsonObjectProvenance() => _openingBraceLine(lines) + 1,
  };
  lines.insert(at, note);
  final out = lines.join('\n');
  final stamped = body.endsWith('\n') ? '$out\n' : out;
  if (syntax is JsonObjectProvenance) _assertStillJson(stamped, relativePath);
  return stamped;
}

/// Whether [contents] was generated by this tooling (it carries the stamp).
bool hasProvenance(String contents) => contents.contains(kProvenanceMarker);

/// [contents] with its stamp line removed — the BODY, which is what a drift
/// check compares. Identity for an unstamped file, and the exact inverse of
/// [stampProvenance].
String stripProvenance(String contents) {
  final kept = const LineSplitter()
      .convert(contents)
      .where((line) => !line.contains(kProvenanceMarker));
  final out = kept.join('\n');
  return contents.endsWith('\n') ? '$out\n' : out;
}

/// The grid_assets source ref [overlayRoot] was vended from — the short commit
/// sha of its checkout, or [kUnknownSourceRef] when it is not in one.
///
/// SYNCHRONOUS by necessity, and deliberately NOT the house `GitRunner` seam:
/// that interface is async-only, and the provision wire cannot await
/// (`OverlayMaterializer.materializeSync` runs inside `ProcessCapability.spawn`,
/// which returns a `RuntimeConfig` directly — ADR-0000 A1/A23(3)).
///
/// READ-ONLY (`rev-parse`) and the ONLY git call in the asset-install legs: it
/// writes nothing, commits nothing, and creates no git artifact, so the
/// "commits nothing" invariant of the operator leg is intact. A caller holding
/// its own ref (a tagged dep, once git-tag deps land) passes it instead.
String resolveOverlaySourceRefSync(String overlayRoot) {
  try {
    final result = Process.runSync(
      'git',
      const ['rev-parse', '--short', 'HEAD'],
      workingDirectory: overlayRoot,
      runInShell: false,
    );
    if (result.exitCode != 0) return kUnknownSourceRef;
    final ref = (result.stdout as String).trim();
    return ref.isEmpty ? kUnknownSourceRef : ref;
  } on ProcessException {
    return kUnknownSourceRef;
  } on ArgumentError {
    // A workingDirectory that does not exist — the empty-overlay posture, not a
    // violated invariant.
    return kUnknownSourceRef;
  }
}

/// The index of the line opening the JSON object, or -1.
int _openingBraceLine(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim().startsWith('{')) return i;
  }
  return -1;
}

/// Guards the named invariant "a stamped JSON file is still valid JSON" —
/// textual insertion is what preserves the operator's formatting byte-for-byte,
/// so this is the check that keeps it honest on a shape the insertion cannot
/// handle (a minified or empty object).
void _assertStillJson(String stamped, String relativePath) {
  try {
    jsonDecode(stamped);
  } on FormatException catch (error) {
    throw StateError(
      'stamping "$relativePath" would not leave valid JSON ($error) — a vended '
      'JSON asset must open its object on its own line so the provenance field '
      'can be inserted after it',
    );
  }
}

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
///
/// The ROOT instruction file is the ONE bounded departure from that refusal
/// (declared by the operator against
/// `power_station#a26-bead-pow-hhs-the-station-overlay-becomes-a-root-relative`):
/// a repository's `AGENTS.md` is plain prose, so it is neither frontmatter-led
/// nor JSON, AND it is a file the repository already owns — `bd setup codex`
/// writes its own block there. [MarkedBlockProvenance] carries the same two
/// invariants at BLOCK granularity instead of file granularity: this tooling
/// owns exactly the bytes between its own boundary lines, whose first interior
/// line is the [kProvenanceMarker] stamp, and it never clobbers a byte outside
/// them. Every other plain-Markdown path still THROWS.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'overlay_manifest.dart';

/// The substring every stamped file carries — the detection AND strip key.
const String kProvenanceMarker = 'generated from grid_assets@';

/// The line opening the block this tooling owns inside a composed instruction
/// file — the exact bytes, on their own line, and nothing else.
const String kGeneratedBlockBegin = '<!-- BEGIN GRID ASSETS AGENTS -->';

/// The line closing the block this tooling owns. See [kGeneratedBlockBegin].
const String kGeneratedBlockEnd = '<!-- END GRID ASSETS AGENTS -->';

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

/// A plain-Markdown file the repository ALSO owns (the root
/// [kAgentsRootRelativePath]): the stamp cannot go anywhere in the file at
/// large, so this tooling claims one BLOCK of it, bounded by
/// [kGeneratedBlockBegin] and [kGeneratedBlockEnd], and stamps the block's first
/// interior line.
///
/// Ownership is the whole point. [bodyOf] answers "is there exactly one
/// well-formed block of MINE here, and what did it vend?" — and answers null for
/// every malformed, duplicated or unstamped shape, so a caller can refuse rather
/// than guess. [merge] replaces that one span and preserves every byte outside
/// it. [containsAnyMarker] is deliberately LOOSER than [bodyOf]: any trace of
/// these markers means the file has been through this tooling, so a trace with
/// no well-formed block is a file to REFUSE, never one to append to.
final class MarkedBlockProvenance extends ProvenanceSyntax {
  /// Creates the marked-block syntax.
  const MarkedBlockProvenance();

  /// The line opening the owned block.
  String get beginMarker => kGeneratedBlockBegin;

  /// The line closing the owned block.
  String get endMarker => kGeneratedBlockEnd;

  /// [body] as the complete owned block: the boundary lines, [note] as the first
  /// interior line, then [body]. Always newline-terminated, so a composed file
  /// never grows a block that runs into its neighbour.
  String wrapped(String body, {required String note}) => <String>[
    beginMarker,
    note,
    ...const LineSplitter().convert(body),
    endMarker,
    '',
  ].join('\n');

  /// Whether [contents] carries ANY trace of this tooling's boundary markers.
  bool containsAnyMarker(String contents) =>
      contents.contains(beginMarker) || contents.contains(endMarker);

  /// The un-stamped body the ONE well-formed owned block in [contents] vended,
  /// or null when there is no such block.
  ///
  /// Null covers every shape a caller must not touch: no markers, a marker that
  /// is not alone on its line, markers out of order, a DUPLICATED pair, an empty
  /// block, and a block whose first interior line carries no [kProvenanceMarker]
  /// (which is a hand-typed imitation, not something this tooling wrote).
  String? bodyOf(String contents) {
    final begins = _markerLineOffsets(contents, beginMarker);
    final ends = _markerLineOffsets(contents, endMarker);
    if (begins.length != 1 || ends.length != 1) return null;
    final begin = begins.single;
    final end = ends.single;
    if (end <= begin) return null;
    final interior = contents.substring(
      _lineAfter(contents, begin + beginMarker.length),
      end,
    );
    final lines = const LineSplitter().convert(interior);
    if (lines.isEmpty || !lines.first.contains(kProvenanceMarker)) return null;
    final body = lines.skip(1).join('\n');
    return body.isEmpty ? '' : '$body\n';
  }

  /// [contents] with [block] in place of the one owned block it carries, or with
  /// [block] APPENDED when it carries none.
  ///
  /// Pure surgery on character offsets, never a line re-join: every byte outside
  /// the replaced span — a repository's own prose, another tool's generated block
  /// — survives exactly as it was, line endings included.
  String merge(String contents, {required String block}) {
    final begins = _markerLineOffsets(contents, beginMarker);
    final ends = _markerLineOffsets(contents, endMarker);
    if (begins.length == 1 && ends.length == 1 && ends.single > begins.single) {
      final after = _lineAfter(contents, ends.single + endMarker.length);
      return contents.substring(0, begins.single) +
          block +
          contents.substring(after);
    }
    if (contents.isEmpty) return block;
    final separator = contents.endsWith('\n\n')
        ? ''
        : contents.endsWith('\n')
        ? '\n'
        : '\n\n';
    return '$contents$separator$block';
  }
}

/// The provenance syntax for [relativePath] carrying [body].
///
/// THROWS a [StateError] naming the path when the file type has no provenance
/// syntax — LOUD, because an unstampable file could never be told apart from a
/// hand-authored one, so the overlay refuses to vend it.
ProvenanceSyntax provenanceSyntaxFor(String relativePath, String body) {
  final lines = const LineSplitter().convert(body);
  final extension = p.extension(relativePath);
  // The ROOT instruction file, whatever its body opens on: it is prose the
  // repository co-owns, so the stamp rides inside the block this tooling claims
  // rather than anywhere in the file at large.
  if (p.normalize(relativePath) == kAgentsRootRelativePath) {
    return const MarkedBlockProvenance();
  }
  if (extension == '.md' && lines.isNotEmpty && lines.first.trim() == '---') {
    return const YamlFrontmatterProvenance();
  }
  if (extension == '.json' && _openingBraceLine(lines) >= 0) {
    return const JsonObjectProvenance();
  }
  throw StateError(
    'no provenance syntax for "$relativePath" — a vended overlay file is a '
    'frontmatter-led .md, a JSON object (.json), or the root '
    '$kAgentsRootRelativePath; an unstampable file could never be told from a '
    'hand-authored one, so it is never installed',
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
  final note =
      '$kProvenanceMarker$sourceRef — do not edit; run '
      '`$runner assets install`';
  switch (syntax) {
    case YamlFrontmatterProvenance():
      return _stampInserted(body, note: '# $note', at: 1);
    case JsonObjectProvenance():
      final stamped = _stampInserted(
        body,
        note: '  "\$generated": "$note",',
        at: _openingBraceLine(const LineSplitter().convert(body)) + 1,
      );
      _assertStillJson(stamped, relativePath);
      return stamped;
    case MarkedBlockProvenance():
      // The block WRAPS its body rather than inserting a line into it: the
      // marked syntax owns boundaries, not a position.
      return syntax.wrapped(body, note: '<!-- $note -->');
  }
}

/// [body] with [note] inserted as line [at] — the in-file syntaxes' shape, where
/// the stamp is one line the format already tolerates.
String _stampInserted(String body, {required String note, required int at}) {
  final lines = const LineSplitter().convert(body)..insert(at, note);
  final out = lines.join('\n');
  return body.endsWith('\n') ? '$out\n' : out;
}

/// Whether [contents] was generated by this tooling (it carries the stamp).
bool hasProvenance(String contents) => contents.contains(kProvenanceMarker);

/// [contents] with its stamp line removed — the BODY, which is what a drift
/// check compares. Identity for an unstamped file, and the exact inverse of
/// [stampProvenance].
///
/// A [MarkedBlockProvenance] stamp rides between boundary lines this tooling
/// wrote, so those lines come out too — otherwise the inverse would leak the
/// block's own scaffolding into the body it is compared against. (A caller that
/// needs the body of one owned block INSIDE a larger composed file asks
/// [MarkedBlockProvenance.bodyOf], which validates ownership first.)
String stripProvenance(String contents) {
  final kept = const LineSplitter()
      .convert(contents)
      .where(
        (line) =>
            !line.contains(kProvenanceMarker) &&
            line != kGeneratedBlockBegin &&
            line != kGeneratedBlockEnd,
      );
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

/// Every character offset in [contents] where [marker] stands ALONE on its own
/// line — the only form this tooling writes, and so the only form it OWNS.
List<int> _markerLineOffsets(String contents, String marker) {
  final offsets = <int>[];
  var from = 0;
  while (true) {
    final at = contents.indexOf(marker, from);
    if (at < 0) return offsets;
    final after = at + marker.length;
    from = after;
    final opensLine = at == 0 || contents[at - 1] == '\n';
    final closesLine = after == contents.length || contents[after] == '\n';
    if (opensLine && closesLine) offsets.add(at);
  }
}

/// [at], advanced past the newline that terminates its line (if any) — so a
/// replaced span consumes its own line ending and no more.
int _lineAfter(String contents, int at) =>
    at < contents.length && contents[at] == '\n' ? at + 1 : at;

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

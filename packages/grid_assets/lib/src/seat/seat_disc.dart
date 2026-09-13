/// The Agent DISC — one OPERATOR SEAT's memory home under the station grid
/// home, and the HANDOFF note the `prime` verb consumes.
///
/// The shape is not this pack's invention: `the_grid#agent-disc-file-shape-and-home`
/// fixes it — one file per fact at `<gridHome>/.grid/seats/<seat>/<name>.md`,
/// front matter then prose, with `kind: handoff` naming "the one note that is
/// CONSUMED rather than kept ... the successor DELETES it in the turn that reads
/// it". Nothing here WRITES a note: the occupant writes and deletes its own.
///
/// It does own the disc's INDEX INVARIANT, because the occupant demonstrably
/// does not: `MEMORY.md` is the only thing that makes a note findable, and
/// [SeatDisc.verifyIndexIntegrity] is the read-only check that it still covers
/// the notes beside it.
///
/// Not to be confused with the four TYPED ENVIRONMENT seats of
/// `agent/seat_environments.dart` (ADR-0006 D2 spawn sites); this is the
/// human-occupiable operator seat of `the_grid#agent-seat-and-agent-disc`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The grid-home-relative home of every operator seat's disc.
const String kSeatsSubdirectory = '.grid/seats';

/// The front-matter `kind` of the one note consumed on read.
const String kHandoffKind = 'handoff';

/// The disc's INDEX — the one file loaded wholesale at session start, and the
/// only thing that makes any other note on the disc findable
/// (`the_grid#agent-disc-file-shape-and-home`: "one pointer line per file").
const String kSeatMemoryFileName = 'MEMORY.md';

/// The process env var naming the seat a session occupies. Set by the launcher;
/// ABSENT means a bare harness session, which is NOT a seat and writes no disc.
const String kSeatEnvironmentVariable = 'GRID_SEAT';

/// The process env var naming the station grid home. Set by the launcher.
const String kGridHomeEnvironmentVariable = 'GRID_HOME';

/// The ABSOLUTE disc directory of [seat] under [gridHome].
String seatDiscPath(String gridHome, String seat) =>
    p.normalize(p.join(gridHome, kSeatsSubdirectory, seat));

/// One `kind: handoff` note read off a seat's disc — a pure VALUE.
class SeatHandoff {
  /// Creates the handoff.
  const SeatHandoff({
    required this.path,
    required this.relativePath,
    required this.body,
  });

  /// The note's ABSOLUTE path.
  final String path;

  /// Its path relative to the grid home — what the injected naming line says.
  final String relativePath;

  /// The BODY: the prose after the front matter, trimmed. The front matter is
  /// never injected.
  final String body;

  @override
  bool operator ==(Object other) =>
      other is SeatHandoff &&
      other.path == path &&
      other.relativePath == relativePath &&
      other.body == body;

  @override
  int get hashCode => Object.hash(path, relativePath, body);

  @override
  String toString() => 'SeatHandoff($relativePath)';
}

final RegExp _kindLine = RegExp(r'^\s*kind:\s*(\S+)\s*$');

/// Parses [contents] as a disc note, returning a [SeatHandoff] when its front
/// matter declares `kind: handoff` and `null` otherwise — a lesson, a receipt,
/// an observation, `MEMORY.md`, or a file with no front matter at all. PURE:
/// the whole handoff decision is testable without a disk.
SeatHandoff? parseSeatHandoff({
  required String path,
  required String relativePath,
  required String contents,
}) {
  final lines = const LineSplitter().convert(contents);
  if (lines.isEmpty || lines.first.trim() != '---') return null;
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      end = i;
      break;
    }
  }
  if (end == -1) return null;
  final isHandoff = lines
      .sublist(1, end)
      .any((line) => _kindLine.firstMatch(line)?.group(1) == kHandoffKind);
  if (!isHandoff) return null;
  return SeatHandoff(
    path: path,
    relativePath: relativePath,
    body: lines.sublist(end + 1).join('\n').trim(),
  );
}

/// [text] split into lines that KEEP their `\n`, so a line can be removed from
/// a file without disturbing one other byte. A trailing fragment with no
/// terminator is its own last entry. PURE.
List<String> _linesKeepingTerminators(String text) {
  final lines = <String>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0a) {
      lines.add(text.substring(start, i + 1));
      start = i + 1;
    }
  }
  if (start < text.length) lines.add(text.substring(start));
  return lines;
}

/// A Markdown inline link's target: the `x` of `](x)`.
final RegExp _inlineLinkTarget = RegExp(r'\]\(([^()]*)\)');

/// The indices of the lines in [memory] carrying a Markdown link whose target
/// is EXACTLY [target] — the disc index's pointer at one note.
///
/// Exact, never a substring: `](handoff-a.md)` is a pointer at `handoff-a.md`
/// and `](old-handoff-a.md)` is not. Indices are into
/// [_linesKeepingTerminators], so [removeMemoryLine] consumes them directly.
/// PURE.
List<int> memoryPointerLines({required String memory, required String target}) {
  final lines = _linesKeepingTerminators(memory);
  final found = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final hit = _inlineLinkTarget
        .allMatches(lines[i])
        .any((m) => m.group(1) == target);
    if (hit) found.add(i);
  }
  return found;
}

/// [memory] with line [index] removed and EVERY remaining byte preserved —
/// the removed line takes its own `\n` and nothing else. PURE.
String removeMemoryLine({required String memory, required int index}) {
  final lines = _linesKeepingTerminators(memory);
  if (index < 0 || index >= lines.length) return memory;
  lines.removeAt(index);
  return lines.join();
}

/// Every DISTINCT Markdown inline-link target in [memory], in first-appearance
/// order — every note the index CLAIMS to point at. PURE.
Set<String> _inlineLinkTargets(String memory) => <String>{
  for (final line in _linesKeepingTerminators(memory))
    for (final match in _inlineLinkTarget.allMatches(line)) match.group(1)!,
};

/// [names] sorted and frozen, so a report reads the same twice and cannot be
/// edited by whoever catches it. PURE.
List<String> _sortedNames(Iterable<String> names) =>
    List<String>.unmodifiable(names.toList()..sort());

/// The disc's INDEX does not cover the notes beside it — what
/// [SeatDisc.verifyIndexIntegrity] throws.
///
/// Three ways the cover can break, each reported in its own field so a caller
/// can act on the shape rather than on prose, and ALL of them collected in one
/// scan: naming only the first offender is how seventy-six of seventy-seven
/// lost pointer lines stay invisible.
final class SeatDiscIntegrityException implements Exception {
  /// Creates the exception over one scan's offenders.
  SeatDiscIntegrityException({
    required this.directory,
    Iterable<String> unindexedFiles = const <String>[],
    Iterable<String> missingTargets = const <String>[],
    Iterable<String> multiplyIndexedFiles = const <String>[],
  }) : unindexedFiles = _sortedNames(unindexedFiles),
       missingTargets = _sortedNames(missingTargets),
       multiplyIndexedFiles = _sortedNames(multiplyIndexedFiles);

  /// The ABSOLUTE disc directory that was scanned.
  final String directory;

  /// Disc-local names of notes NO pointer line names — banked, on disk, and
  /// unreachable, because the index is the only thing that finds a note.
  final List<String> unindexedFiles;

  /// Pointer targets, EXACTLY as the index writes them, that resolve to no
  /// file on this disc — a line that points at nothing.
  final List<String> missingTargets;

  /// Disc-local names of notes more than one pointer line names — the index
  /// has drifted, and the succession verb refuses a note it cannot consume
  /// down to one line.
  final List<String> multiplyIndexedFiles;

  @override
  String toString() {
    final faults = <String>[
      if (unindexedFiles.isNotEmpty)
        '${unindexedFiles.length} note(s) NOT INDEXED, so nothing can find '
            'them: ${unindexedFiles.join(', ')}',
      if (missingTargets.isNotEmpty)
        '${missingTargets.length} pointer target(s) MISSING from the disc: '
            '${missingTargets.join(', ')}',
      if (multiplyIndexedFiles.isNotEmpty)
        '${multiplyIndexedFiles.length} note(s) INDEXED MORE THAN ONCE: '
            '${multiplyIndexedFiles.join(', ')}',
    ];
    return 'SeatDiscIntegrityException: $kSeatMemoryFileName does not cover '
        '$directory — ${faults.join('; ')}';
  }
}

/// One operator seat's disc directory — the thin IO seam over
/// [parseSeatHandoff]. Read-only except for [ensure].
class SeatDisc {
  /// Creates the disc over its ABSOLUTE [directory], under [gridHome].
  const SeatDisc({required this.directory, required this.gridHome});

  /// The ABSOLUTE disc directory (`<gridHome>/.grid/seats/<seat>/`).
  final String directory;

  /// The station grid home the disc sits under.
  final String gridHome;

  /// Creates the disc directory when absent — a seat's disc exists before it is
  /// occupied, and it is TRACKED (`the_grid#agent-disc-file-shape-and-home`).
  void ensure() => Directory(directory).createSync(recursive: true);

  /// Every `kind: handoff` note on the disc, with its modification time.
  ///
  /// That time is the file's mtime, which this platform reports at WHOLE-SECOND
  /// resolution, so two notes written in the same second TIE. The tie is broken
  /// by the greater relative path, which makes [newestHandoff] deterministic
  /// rather than merely usually-right.
  List<({SeatHandoff handoff, DateTime at})> handoffs() {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    final found = <({SeatHandoff handoff, DateTime at})>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (p.extension(file.path) != '.md') continue;
      final handoff = parseSeatHandoff(
        path: file.path,
        relativePath: p.relative(file.path, from: gridHome),
        contents: file.readAsStringSync(),
      );
      if (handoff != null) {
        found.add((handoff: handoff, at: file.lastModifiedSync()));
      }
    }
    found.sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0
          ? byTime
          : a.handoff.relativePath.compareTo(b.handoff.relativePath);
    });
    return found;
  }

  /// The NEWEST handoff, or `null` when the disc holds none. Newest is by file
  /// modification time, ties broken by the greater relative path so the answer
  /// is deterministic on a same-instant tie.
  SeatHandoff? newestHandoff() {
    final all = handoffs();
    return all.isEmpty ? null : all.last.handoff;
  }

  /// Whether a handoff NEWER than [instant] sits on the disc — the launcher's
  /// harness-neutral RELAUNCH predicate.
  ///
  /// Because mtimes land on whole seconds (see [handoffs]) while [instant] is
  /// a full-precision clock reading, a handoff written in the SAME second as
  /// the launch reads as not-newer. That direction is deliberate: missing one
  /// relaunch is recoverable, while treating a pre-existing handoff as fresh
  /// would relaunch forever.
  bool hasHandoffNewerThan(DateTime instant) =>
      handoffs().any((entry) => entry.at.isAfter(instant));

  /// Verifies that [kSeatMemoryFileName] COVERS this disc: every persistent
  /// note is named by exactly one pointer line, and every pointer line names a
  /// file that is here. Returns normally when it does; throws one
  /// [SeatDiscIntegrityException] naming EVERY offender when it does not.
  ///
  /// **Why this exists.** A disc note is findable only through the index — it
  /// is the one file loaded wholesale, and the notes load on relevance — so an
  /// index that stops naming a note retires it in silence. Observed 2026-09-12
  /// on the live governor disc: a seat banking ONE lesson rewrote its own index
  /// wholesale instead of appending, and the file went from seventy-seven
  /// pointer lines to one. Eighty-one markdown files stayed on the disc; the
  /// index named two. Nothing failed, nothing warned, and it was found by
  /// accident four hours later.
  ///
  /// This is a CHECK and never a writer
  /// (`power_station#seat-disc-index-integrity-is-checked-not-written`): it
  /// reports after the fact, which is why it catches a wholesale rewrite, a
  /// hand edit and a bad merge alike, and it never repairs the index. It
  /// creates, appends to, renames and deletes NOTHING.
  ///
  /// A `kind: handoff` note is exempt from the coverage count: a handoff is
  /// consumed rather than kept, so it is indexed for exactly one succession and
  /// `SeatSuccessionService` is what holds it to one pointer line at the moment
  /// it consumes it. An absent index is EMPTY, not an error — a disc that holds
  /// only a handoff, or nothing at all, verifies.
  void verifyIndexIntegrity() {
    final memoryFile = File(p.join(directory, kSeatMemoryFileName));
    final memory = memoryFile.existsSync() ? memoryFile.readAsStringSync() : '';

    final unindexed = <String>[];
    final multiplyIndexed = <String>[];
    final dir = Directory(directory);
    if (dir.existsSync()) {
      for (final file in dir.listSync().whereType<File>()) {
        final name = p.basename(file.path);
        if (p.extension(name) != '.md' || name == kSeatMemoryFileName) continue;
        final handoff = parseSeatHandoff(
          path: file.path,
          relativePath: p.relative(file.path, from: gridHome),
          contents: file.readAsStringSync(),
        );
        if (handoff != null) continue;
        final pointers = memoryPointerLines(memory: memory, target: name);
        if (pointers.isEmpty) unindexed.add(name);
        if (pointers.length > 1) multiplyIndexed.add(name);
      }
    }

    final missing = <String>[
      for (final target in _inlineLinkTargets(memory))
        if (!_pointsAtANoteHere(target)) target,
    ];

    if (unindexed.isEmpty && missing.isEmpty && multiplyIndexed.isEmpty) return;
    throw SeatDiscIntegrityException(
      directory: directory,
      unindexedFiles: unindexed,
      missingTargets: missing,
      multiplyIndexedFiles: multiplyIndexed,
    );
  }

  /// Whether [target] is a pointer this disc can FOLLOW: one disc-local file
  /// name — no directory part, no scheme, no traversal — that exists.
  ///
  /// The index's grammar is `- [Title](file.md) — hook`, one line per file on
  /// this disc, so anything else is a line a reader cannot follow to a note and
  /// is reported rather than tolerated.
  bool _pointsAtANoteHere(String target) {
    if (target.isEmpty || target == '.' || target == '..') return false;
    if (p.basename(target) != target) return false;
    return File(p.join(directory, target)).existsSync();
  }
}

/// The Agent DISC — one OPERATOR SEAT's memory home under the station grid
/// home, and the HANDOFF note the `prime` verb consumes.
///
/// The shape is not this pack's invention: `the_grid#agent-disc-file-shape-and-home`
/// fixes it — one file per fact at `<gridHome>/.grid/seats/<seat>/<name>.md`,
/// front matter then prose, with `kind: handoff` naming "the one note that is
/// CONSUMED rather than kept ... the successor DELETES it in the turn that reads
/// it". Nothing here AUTHORS a note: the occupant composes its own prose.
///
/// It does own two things the occupant demonstrably does not hold on its own.
///
/// The disc's INDEX INVARIANT: `MEMORY.md` is the only thing that makes a note
/// findable, and [SeatDisc.verifyIndexIntegrity] is the read-only check that it
/// still covers the notes beside it.
///
/// And the handoff's WRITE-ONCE lifetime
/// (`memento-engineering#handoffs-are-working-memory-and-long-term-memory-stays-thin`):
/// [SeatDisc.writeHandoffOnce] is the one mechanical writer, it refuses a
/// second live handoff, and [seatHandoffAgeDiagnostic] renders how long an
/// unconsumed one has sat there. Both are mechanism only — WHAT a handoff says
/// and WHEN a boundary is reached stay with the vended `handoff` skill.
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

/// The disc-local directory a LOCAL archive is written under — the sink for a
/// disc git IGNORES.
///
/// `power_station#handoff-succession-commits-before-consume` licensed the
/// destruction of a consumed handoff on one premise: "the disc is tracked, so
/// git history is the archive". A station may deliberately ignore its seats
/// tree — lunar_station did, at 7b225e8, for the PII a disc accretes — and on
/// such a disc the premise is not merely unheld, it is UNHOLDABLE: the only way
/// to reach git history from there is `git add -f`, which would commit exactly
/// the material the ignore exists to keep out. The archive moves under the disc
/// instead, where that same ignore already covers it (Nico, 2026-09-13, fork
/// option (a)).
const String kSeatArchiveSubdirectory = '.archive';

/// The UTC stamp one local archive directory is named by — the
/// `<YYYYMMDD>t<HHMMSS>z` shape the handoff file name already carries, so an
/// archive sorts beside the notes it holds. PURE.
String seatArchiveStamp(DateTime at) {
  final utc = at.toUtc();
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  return '${pad(utc.year, 4)}${pad(utc.month, 2)}${pad(utc.day, 2)}t'
      '${pad(utc.hour, 2)}${pad(utc.minute, 2)}${pad(utc.second, 2)}z';
}

/// How many `.archive/<stamp>/` directories one disc KEEPS. Every succession
/// prunes what falls outside it (Nico, 2026-09-13).
///
/// The local archive exists to make ONE destruction safe, not to become a
/// second history. The note it holds was working memory; its durable half was
/// already banked as disc notes, beads and decisions before the handoff was
/// written. An unbounded pile of it is worse than useless on the disc that
/// earns this sink in the first place — the one a station gitignored for the
/// PII it accretes. Ten is the depth an operator can still walk back by hand.
const int kSeatArchiveRetention = 10;

/// The `<YYYYMMDD>t<HHMMSS>z(-<n>)?` shape a local archive directory is named
/// by — the stamp alone at [ordinal] 1, `<stamp>-2` at 2, and so on. PURE.
///
/// The stamp has SECOND resolution and the launcher's relaunch loop is not
/// paced by a human, so two successions inside one second are a real case.
/// Refusing the second one was the wrong half of that trade (Nico,
/// 2026-09-13): the run that hands a seat over is not the place to lose on a
/// clock tick, and an ordinal keeps BOTH archives whole.
String seatArchiveDirectoryName(String stamp, int ordinal) =>
    ordinal <= 1 ? stamp : '$stamp-$ordinal';

final RegExp _archiveDirectoryName = RegExp(r'^(\d{8}t\d{6}z)(?:-(\d+))?$');

/// [name] split back into the stamp and ordinal
/// [seatArchiveDirectoryName] composed, or null when it is not a name this
/// station wrote. PURE.
///
/// Null is load-bearing: retention DELETES, and a directory whose name it
/// cannot parse is one it did not create, so it is never a prune candidate.
({String stamp, int ordinal})? parseSeatArchiveDirectoryName(String name) {
  final match = _archiveDirectoryName.firstMatch(name);
  if (match == null) return null;
  final ordinal = match.group(2);
  if (ordinal == null) return (stamp: match.group(1)!, ordinal: 1);
  final parsed = int.tryParse(ordinal);
  // `-0` and `-1` are names this station never writes, and a leading zero
  // would make two names for one archive — neither is ours to delete.
  if (parsed == null || parsed < 2) return null;
  if (seatArchiveDirectoryName(match.group(1)!, parsed) != name) return null;
  return (stamp: match.group(1)!, ordinal: parsed);
}

/// The archive directory names in [names] that fall OUTSIDE the newest [keep],
/// OLDEST first — exactly what one succession prunes. PURE.
///
/// Ordering is by the parsed (stamp, ordinal) pair rather than by the string:
/// `<stamp>-10` sorts before `<stamp>-2` lexicographically, and retention that
/// deletes the newest archive because of a string compare is worse than no
/// retention at all. Unparseable names are dropped, never returned.
List<String> seatArchivesToPrune(
  Iterable<String> names, {
  int keep = kSeatArchiveRetention,
}) {
  final parsed =
      <({String name, String stamp, int ordinal})>[
        for (final name in names)
          if (parseSeatArchiveDirectoryName(name) case final at?)
            (name: name, stamp: at.stamp, ordinal: at.ordinal),
      ]..sort((a, b) {
        final byStamp = a.stamp.compareTo(b.stamp);
        return byStamp != 0 ? byStamp : a.ordinal.compareTo(b.ordinal);
      });
  if (keep < 0 || parsed.length <= keep) return const <String>[];
  return <String>[for (final at in parsed.take(parsed.length - keep)) at.name];
}

/// The process env var naming the seat a session occupies. Set by the launcher;
/// ABSENT means a bare harness session, which is NOT a seat and writes no disc.
const String kSeatEnvironmentVariable = 'GRID_SEAT';

/// The process env var naming the station grid home. Set by the launcher.
const String kGridHomeEnvironmentVariable = 'GRID_HOME';

/// The process env var carrying the handoff body the launcher CONSUMED for this
/// occupancy — the delivery path of a `SeatPrimeMode.hook` harness, whose
/// priming is a SessionStart hook rather than a prompt.
///
/// The launcher is the only writer (`pow-d5ol`, Nico 2026-09-13: "a successor
/// cannot start unprimed"). A hook-primed child takes no prompt segment, and
/// the note it would otherwise have read off the disc is gone by the time it
/// starts — the launcher archived and deleted it — so the body travels in the
/// process environment instead and `prime` injects it from there. ABSENT means
/// this occupancy consumed nothing.
const String kConsumedHandoffEnvironmentVariable = 'GRID_SEAT_HANDOFF';

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

/// The one REMEDY a write refused for an occupied disc names: the live handoff
/// is CONSUMED, and the next note is authored fresh at the next boundary.
///
/// Never "edit the existing one" and never "delete it by hand" — the succession
/// verb is what archives the disc and proves the note reached `HEAD` before
/// removing it (`power_station#handoff-succession-commits-before-consume`).
const String kHandoffWriteRemedy =
    'consume the existing handoff with succession, then write a new handoff';

/// A handoff write REFUSED — what [SeatDisc.writeHandoffOnce] throws instead of
/// amending, appending to, or overwriting a note that is already there.
///
/// **Why a refusal and not a warning.** A handoff is WORKING memory:
/// `memento-engineering#handoffs-are-working-memory-and-long-term-memory-stays-thin`
/// rules that it is "written once at a boundary, picked up, and deleted — a
/// lifetime measured in minutes. It is never amended." CONSUMING one was
/// already a verb and already enforced; WRITING one was a skill — prose an
/// agent may follow or not — and nothing refused a second write. Measured
/// 2026-09-12 on the live governor disc: one note was rewritten across THIRTY
/// commits between 23:25 and 08:45, so the UTC stamp in its own file name was
/// false by the time a successor read it, and its Resume section described a
/// board nine hours younger than the sections above it.
///
/// Every refusal names the disc, the disc-local name it refused to write, and —
/// when the disc already carries handoffs — every one of them, so a caller acts
/// on the shape rather than on prose.
final class SeatHandoffWriteException implements Exception {
  /// Creates the refusal over the disc that refused it.
  SeatHandoffWriteException({
    required this.directory,
    required this.fileName,
    required this.detail,
    Iterable<String> existingHandoffs = const <String>[],
  }) : existingHandoffs = _sortedNames(existingHandoffs);

  /// The ABSOLUTE disc directory the write was aimed at.
  final String directory;

  /// The disc-local name the write was aimed at — never a path, because
  /// [SeatDisc.writeHandoffOnce] takes only a basename.
  final String fileName;

  /// Why the write was refused, in one sentence.
  final String detail;

  /// Grid-home-relative paths of every `kind: handoff` note ALREADY on the
  /// disc, sorted and frozen so a report reads the same twice.
  ///
  /// Empty when the refusal was about the candidate itself — a name that is not
  /// one disc-local `.md` basename, or prose the disc's own parser does not
  /// recognize as a handoff.
  final List<String> existingHandoffs;

  @override
  String toString() {
    final live = existingHandoffs.isEmpty
        ? ''
        : ' Live handoff(s): ${existingHandoffs.join(', ')}.';
    return 'SeatHandoffWriteException: refused to write "$fileName" onto '
        '$directory — $detail$live';
  }
}

/// The ONE line every seat reader renders beside an unconsumed handoff: which
/// Agent Seat, which note on its Agent Disc, and how OLD it is. PURE.
///
/// **What it is for.** With the write-once constraint above, a handoff that is
/// still on the disc hours after it was authored is not an amended handoff — it
/// is a seat that never handed off, and the ruling calls that out as the shape
/// to make visible: "an aging unconsumed note is visible evidence that a seat
/// is not handing off". The vocabulary is `the_grid#agent-seat-and-agent-disc`'s
/// — the standing position is an Agent Seat, what accretes on it is an Agent
/// Disc — because a diagnostic that invents its own nouns cannot be searched
/// for alongside the doctrine it reports on.
///
/// **It DEFINES NO THRESHOLD.** There is no expiry, no refusal and no deletion
/// anywhere behind this string: nine hours is a defect a human recognizes, not
/// a number this pack gets to pick, and a diagnostic that started refusing
/// would destroy the very note it exists to surface.
///
/// The age is rendered `<d>d <h>h <m>m`, dropping the day component when it is
/// zero and KEEPING hours and minutes always, so `age 9h 0m` reads the same
/// whether it was reached from nine hours or from thirty-three.
///
/// [authoredAt] AFTER [now] is not silently clamped to zero: a disc mtime in
/// the future means the clock is wrong somewhere, and an age of `0h 0m` would
/// present that as a fresh handoff. It renders the skew instead. Sub-minute
/// skew rounds to `0m in the future`, which still says "unavailable" rather
/// than reporting an age.
String seatHandoffAgeDiagnostic({
  required String seat,
  required SeatHandoff handoff,
  required DateTime authoredAt,
  required DateTime now,
}) {
  final head =
      'Agent Seat "$seat" has unconsumed handoff ${handoff.relativePath} on '
      'its Agent Disc — ';
  final age = now.difference(authoredAt);
  if (age.isNegative) {
    return '${head}age unavailable: authored time is ${-age.inMinutes}m in '
        'the future.';
  }
  final days = age.inDays == 0 ? '' : '${age.inDays}d ';
  return '${head}age $days${age.inHours % 24}h ${age.inMinutes % 60}m.';
}

/// One operator seat's disc directory — the thin IO seam over
/// [parseSeatHandoff]. Read-only except for [ensure] and
/// [writeHandoffOnce].
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

  /// The NEWEST handoff WITH the instant it was written, or `null` when the
  /// disc holds none. Newest is by file modification time, ties broken by the
  /// greater relative path so the answer is deterministic on a same-instant
  /// tie.
  ///
  /// The instant is what [seatHandoffAgeDiagnostic] ages against, and it is the
  /// same mtime [handoffs] orders by — one read, one truth, so a reader cannot
  /// name one note and age another.
  ({SeatHandoff handoff, DateTime at})? newestHandoffState() {
    final all = handoffs();
    return all.isEmpty ? null : all.last;
  }

  /// The NEWEST handoff, or `null` when the disc holds none — the note half of
  /// [newestHandoffState], for the callers that need no age.
  SeatHandoff? newestHandoff() => newestHandoffState()?.handoff;

  /// Writes [contents] as this disc's ONE live handoff, at disc-local
  /// [fileName], and returns the note it parsed back.
  ///
  /// **Write-once, by refusal.** The disc is resolved through [handoffs] FIRST,
  /// so the constraint keys on front matter `kind: handoff`
  /// (`the_grid#agent-disc-file-shape-and-home`) and never on a file-name
  /// pattern: a note that declares the kind is a handoff whatever it is called,
  /// and a lesson called `handoff-notes.md` is not one. When the disc already
  /// carries one or more, this throws a [SeatHandoffWriteException] naming every
  /// one of them and the [kHandoffWriteRemedy] — BEFORE parsing the candidate
  /// and before touching the filesystem. That refusal is the whole point:
  /// consuming a handoff was already an enforced verb while writing one was
  /// prose, which is how one note came to be rewritten thirty times across nine
  /// hours.
  ///
  /// The candidate must be one disc-local `.md` basename that is not the index,
  /// and [parseSeatHandoff] must recognize the COMPLETE [contents] as a
  /// handoff — so a `kind: journal` note, a half-written note and an empty one
  /// are all refused without a file being created. No fifth note kind is
  /// admitted here: the ruling is explicit that the checkpoint IS a handoff,
  /// cycled fast.
  ///
  /// The target is created with `exclusive: true`, so an existing file at that
  /// exact name loses the race loudly rather than being truncated — the one
  /// window [handoffs] cannot close, because a note with no `kind: handoff` in
  /// it is invisible to that scan.
  ///
  /// **It owns the NOTE and nothing else.** It never writes
  /// [kSeatMemoryFileName]: the index append stays one explicit step in the
  /// vended ritual, because the index is CHECKED here and never rewritten
  /// (`power_station#seat-disc-index-integrity-is-checked-not-written`). It
  /// deletes nothing, renames nothing, and decides nothing about what the note
  /// should say.
  SeatHandoff writeHandoffOnce({
    required String fileName,
    required String contents,
  }) {
    Never refuse(
      String detail, {
      Iterable<String> existing = const <String>[],
    }) {
      throw SeatHandoffWriteException(
        directory: directory,
        fileName: fileName,
        detail: detail,
        existingHandoffs: existing,
      );
    }

    final live = handoffs();
    if (live.isNotEmpty) {
      refuse(
        'the disc already carries ${live.length} live '
        'handoff${live.length == 1 ? '' : 's'}, and a handoff is WORKING '
        'memory written ONCE at a boundary, never amended — '
        '$kHandoffWriteRemedy.',
        existing: [for (final entry in live) entry.handoff.relativePath],
      );
    }

    if (fileName.trim().isEmpty || p.basename(fileName) != fileName) {
      refuse(
        'a handoff name is ONE disc-local file name — no directory part, no '
        'traversal.',
      );
    }
    if (p.extension(fileName) != '.md') {
      refuse('a disc note is Markdown, so the name ends in ".md".');
    }
    if (fileName == kSeatMemoryFileName) {
      refuse(
        '$kSeatMemoryFileName is the disc INDEX, not a note — it is never '
        'written as a handoff.',
      );
    }

    final target = p.join(directory, fileName);
    final parsed = parseSeatHandoff(
      path: target,
      relativePath: p.relative(target, from: gridHome),
      contents: contents,
    );
    if (parsed == null) {
      refuse(
        'the candidate is not a handoff: its front matter must declare '
        '"kind: $kHandoffKind" between two "---" fences, and no other note '
        'kind is written here.',
      );
    }

    // Nothing above this line WRITES, so EVERY refusal leaves the disc exactly
    // as it was — not even a directory created for a note that never landed.
    ensure();
    final file = File(target);
    try {
      file.createSync(exclusive: true);
    } on FileSystemException catch (error) {
      refuse(
        'the target already exists on the disc, so writing would overwrite '
        'it — $kHandoffWriteRemedy (${error.osError?.message ?? error.message}).',
      );
    }
    final handle = file.openSync(mode: FileMode.writeOnly);
    try {
      handle.writeStringSync(contents);
      handle.flushSync();
    } finally {
      handle.closeSync();
    }
    return parsed;
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

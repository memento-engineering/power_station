/// The Agent DISC — one OPERATOR SEAT's memory home under the station grid
/// home, and the HANDOFF note the `prime` verb consumes.
///
/// The shape is not this pack's invention: `the_grid#agent-disc-file-shape-and-home`
/// fixes it — one file per fact at `<gridHome>/.grid/seats/<seat>/<name>.md`,
/// front matter then prose, with `kind: handoff` naming "the one note that is
/// CONSUMED rather than kept ... the successor DELETES it in the turn that reads
/// it". Nothing here WRITES a note: the occupant writes and deletes its own.
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
}

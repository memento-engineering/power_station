/// The REFINEMENT FLAG (bead `pow-bhm`; policy Nico-ratified 2026-07-18,
/// interactive session) — the NON-GRADING channel for a committee lane's
/// bead-graph findings.
///
/// The ratified clause: "the bead-graph axis (duplicates, dep edges, tracker
/// hygiene) stops GRADING the spec. Its findings become a structured refinement
/// flag (surfaced to the operator via the gate/notes machinery). Only the
/// codebase axis (does the spec cohere with the live tree) grades. Tracker state
/// is never the spec author's defect."
///
/// The receipt: `tg-h4u` round 3 gated on a coherence `F` whose whole finding
/// was tracker state (a duplicate bead plus a dep edge keyed to it) — a real
/// integrity problem, not a defect of the spec under review, and fixable by two
/// bd commands at refinement.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'respec_ledger.dart';

/// The absolute path of the refinement flag under [workspaceDir] — a sibling of
/// the respec ledger and the fix-in-flight carry, under the same session-scoped
/// [kRespecSpecDir].
String refinementFlagPath(String workspaceDir) =>
    p.join(workspaceDir, kRespecSpecDir, 'refinement.json');

/// ONE lane's non-grading observation about the BEAD GRAPH.
class RefinementNote {
  /// Creates a note [finding] from lane [rubric].
  const RefinementNote({required this.rubric, required this.finding});

  /// The lane that observed it (`coherence` today).
  final String rubric;

  /// The observation VERBATIM — the operator's working material.
  final String finding;

  /// The wire shape.
  Map<String, Object?> toJson() => {'rubric': rubric, 'finding': finding};

  /// Decodes one note; null for a non-map / field-less entry (best-effort).
  static RefinementNote? fromJson(Object? json) {
    if (json is! Map) return null;
    final rubric = (json['rubric'] as String?)?.trim() ?? '';
    final finding = (json['finding'] as String?)?.trim() ?? '';
    if (rubric.isEmpty || finding.isEmpty) return null;
    return RefinementNote(rubric: rubric, finding: finding);
  }
}

/// A round's refinement flag — every lane's bead-graph findings, none of which
/// moved a letter.
class RefinementFlag {
  /// Creates the flag for [round] over [notes].
  const RefinementFlag({
    required this.sessionRoot,
    required this.round,
    required this.notes,
  });

  /// The round-zero work-bead root that owns this session (provenance).
  final String sessionRoot;

  /// The circuit round the notes were observed in (provenance).
  final int round;

  /// Every note, in committee (`critics` param) order.
  final List<RefinementNote> notes;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 1,
    'sessionRoot': sessionRoot,
    'round': round,
    'notes': [for (final note in notes) note.toJson()],
  };

  /// Decodes a flag; null for anything unreadable or note-less.
  static RefinementFlag? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionRoot = (json['sessionRoot'] as String?)?.trim() ?? '';
    final round = json['round'];
    final raw = json['notes'];
    if (sessionRoot.isEmpty || round is! int || round < 0 || raw is! List) {
      return null;
    }
    final notes = [
      for (final entry in raw)
        if (RefinementNote.fromJson(entry) case final note?) note,
    ];
    if (notes.isEmpty) return null;
    return RefinementFlag(sessionRoot: sessionRoot, round: round, notes: notes);
  }
}

/// The flag at [workspaceDir], or null when there is none / it is unreadable.
RefinementFlag? readRefinementFlag(String workspaceDir) {
  final file = File(refinementFlagPath(workspaceDir));
  if (!file.existsSync()) return null;
  try {
    return RefinementFlag.fromJson(jsonDecode(file.readAsStringSync()));
  } catch (_) {
    return null;
  }
}

/// Writes [flag] into [workspaceDir]. BEST-EFFORT, deliberately — and the guard
/// is GONE rather than silent (guards LOUD or GONE): the route ALSO carries
/// every note on its own verdict (the `refinement` result key, and the gate
/// reason on an escalate), so a note can never be lost by a failed file write.
/// Failing a ROUND over a tracker-hygiene note would invert the very policy this
/// flag implements ("never round-fail").
void writeRefinementFlag(String workspaceDir, RefinementFlag flag) {
  try {
    File(refinementFlagPath(workspaceDir))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(flag.toJson()));
  } catch (_) {
    // The verdict payload is the durable channel; the file is the convenience.
  }
}

/// Deletes the flag at [workspaceDir] — a round with no notes, plus
/// `IntakeCapability`'s session-head hygiene. Best-effort.
void clearRefinementFlag(String workspaceDir) {
  try {
    final file = File(refinementFlagPath(workspaceDir));
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Hygiene only — the next round with notes overwrites it.
  }
}

/// The OPERATOR-facing block: what refinement owes the tracker, verbatim. Rides
/// the parked gate's reason on an escalate, so a governor reads it where they
/// already read the ruling.
String renderRefinementFlag(RefinementFlag flag) {
  final b = StringBuffer()
    ..writeln('## Refinement flag — BEAD GRAPH, not a spec defect')
    ..writeln(
      'These findings are TRACKER STATE (duplicates, dep edges, hygiene). They '
      'did NOT grade the spec and never will: they are refinement work, fixable '
      'with the bd CLI, and the spec author owns none of them.',
    );
  for (final note in flag.notes) {
    b
      ..writeln()
      ..writeln('### `${note.rubric}`')
      ..writeln(note.finding);
  }
  return b.toString();
}

/// `succession <seat>` — the SUCCESSOR's half of the handoff ritual: ARCHIVE
/// the seat's disc, then consume its one live handoff.
///
/// `the_grid#agent-disc-file-shape-and-home` rules that a handoff is working
/// memory the successor "DELETES in the turn that reads it", and justifies the
/// destruction with "the disc is tracked, so git history is the archive".
/// Nothing enforced the tracked half. A seat whose disc has never been `git
/// add`ed deletes its handoff into NOTHING, and the ritual is written to be
/// performed in the same turn that read it, so the successor has no natural
/// moment to notice. Observed 2026-09-09 on a live grid home: one seat's disc
/// was twelve UNTRACKED files, the handoff about to be consumed among them,
/// while the disc beside it carried forty-six tracked ones.
///
/// This verb makes the archive a PRECONDITION of the destruction, in this
/// order (Nico, 2026-09-09: "commit the disc and delete … we can have a
/// --no-destructive flag or something"):
///
/// 1. resolve exactly ONE live handoff off the disc ([SeatDisc.handoffs]);
/// 2. resolve exactly ONE `MEMORY.md` pointer line at it;
/// 3. COMMIT the seat disc — and only the seat disc — when the tree is dirty;
/// 4. PROVE both files are archived at `HEAD` and byte-identical to the
///    working copy;
/// 5. re-resolve the disc and refuse a sibling that appeared in the commit
///    window;
/// 6. delete the handoff and its one pointer line — or, under
///    `--no-destructive`, stop here and name what it WOULD have deleted.
///
/// Every refusal is LOUD: it names what it refused on, whether the index was
/// touched, and it deletes nothing.
///
/// **Scope.** The verb owns the MECHANICS only. What a handoff says, when one
/// is written, and the one line handed to the outer harness stay with the
/// `/handoff` skill; no judgement moves into code here.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show GateOutcome, GitOps, GitRunner, SystemGitRunner;
import 'package:path/path.dart' as p;

import 'seat_disc.dart';

/// The disc's index — the file whose ONE pointer line is consumed with the
/// handoff it names (the `/handoff` skill's INDEX step).
const String kSeatMemoryFileName = 'MEMORY.md';

String _currentDirectory() => Directory.current.path;

/// The message the scoped archive commit carries. PURE.
String seatArchiveCommitMessage(String seat) =>
    'chore(seat): archive $seat disc';

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

/// What one succession run DID — the four outcomes, sealed by an enum so the
/// CLI consumes them with an exhaustive `switch`.
enum SeatSuccessionDisposition {
  /// The disc carries no `kind: handoff` note. A named no-op: no git ran and
  /// nothing changed.
  noHandoff,

  /// The run REFUSED. Nothing was deleted; the report names why.
  refused,

  /// `--no-destructive`: archived and verified, then stopped. The handoff and
  /// its pointer line are byte-identical to before.
  preserved,

  /// Archived, verified, and consumed: the handoff file and its one pointer
  /// line are gone.
  consumed,
}

/// What one [SeatSuccessionService.succeed] run did — a plain immutable value,
/// UI-drivable: [SuccessionCommand] renders it, and so could anything else.
class SeatSuccessionReport {
  /// Creates the report.
  const SeatSuccessionReport({
    required this.seat,
    required this.disposition,
    this.handoffs = const <String>[],
    this.staged = false,
    this.committed = false,
    this.refusal,
  });

  /// The seat this run addressed.
  final String seat;

  /// What the run did.
  final SeatSuccessionDisposition disposition;

  /// Every handoff the run resolved, oldest first, as grid-home-relative
  /// paths. Exactly one on [SeatSuccessionDisposition.preserved] and
  /// [SeatSuccessionDisposition.consumed]; a refusal on two live handoffs
  /// names them BOTH here.
  final List<String> handoffs;

  /// Whether the scoped `git add` ran and succeeded — i.e. whether the index
  /// may now carry the disc. Reported on a refusal so a staged-but-uncommitted
  /// failure is never mistaken for an archived one.
  final bool staged;

  /// Whether the scoped archive commit was WRITTEN. False when the disc was
  /// already archived — which is why the CLI renders those two states as
  /// different words.
  final bool committed;

  /// Why the run refused, or null when it did not.
  final String? refusal;

  /// The ONE handoff this run resolved, or null when it resolved zero or more
  /// than one.
  String? get candidate => handoffs.length == 1 ? handoffs.single : null;

  @override
  String toString() => 'SeatSuccessionReport(${disposition.name}, $seat)';
}

/// The reusable succession LOGIC — the whole verb minus argv and sinks.
///
/// **Why it composes [GitOps] rather than driving `git` itself.** The safety
/// this verb needs is already owned one layer up and already used three times
/// in this package: [GitOps.hasUncommittedWork] runs the
/// `rev-parse --show-toplevel --show-prefix` WORK-TREE-ROOT guard (a `git`
/// command run from a non-checkout walks UP and would commit to the enclosing
/// repository) and fails CLOSED on a `git status` that exits 0 while warning on
/// stderr — a degraded scan is "couldn't tell", never an invented answer. Both
/// rules are scope-independent, so re-deriving either here would be a second,
/// diverging copy of a solved problem.
///
/// [GitOps] has no PATHSPEC-scoped public method, and scoping is load-bearing
/// here: a grid home is a live checkout, and `git add -A` would sweep the
/// operator's unrelated work into an archive commit. So the two scoped
/// mutations and the two archive proofs go through the SAME injected
/// [GitRunner] the [GitOps] instance wraps — the established pattern for a
/// [GitOps] gap in this package (`code_capabilities.dart`'s `worktree prune`).
/// They run only AFTER the gate above has cleared the root guard on this exact
/// working directory.
class SeatSuccessionService {
  /// Creates the service over its ONE IO seam beyond the disc itself: the
  /// [runner] every `git` call rides (Fakes, not mocks). Absent ⇒ the real
  /// [SystemGitRunner].
  const SeatSuccessionService({GitRunner? runner}) : _runner = runner;

  final GitRunner? _runner;

  /// Archives [seat]'s disc under [gridHome] and consumes its one live
  /// handoff. With [destructive] false, everything happens EXCEPT the
  /// deletion.
  ///
  /// Never throws for a git or disc condition — every one of them is a
  /// [SeatSuccessionDisposition.refused] report naming what went wrong.
  Future<SeatSuccessionReport> succeed({
    required String gridHome,
    required String seat,
    required bool destructive,
  }) async {
    final home = p.normalize(gridHome);
    final disc = SeatDisc(directory: seatDiscPath(home, seat), gridHome: home);

    SeatSuccessionReport refuse(
      String detail, {
      List<String> handoffs = const <String>[],
      bool staged = false,
      bool committed = false,
    }) => SeatSuccessionReport(
      seat: seat,
      disposition: SeatSuccessionDisposition.refused,
      handoffs: handoffs,
      staged: staged,
      committed: committed,
      refusal: detail,
    );

    // 1. Exactly one live handoff — resolved BEFORE any git call, so the two
    //    conditions a human must see cost nothing to reach.
    final found = disc.handoffs();
    if (found.isEmpty) {
      return SeatSuccessionReport(
        seat: seat,
        disposition: SeatSuccessionDisposition.noHandoff,
      );
    }
    final resolved = [for (final entry in found) entry.handoff.relativePath];
    if (found.length > 1) {
      return refuse(
        'the disc carries ${found.length} live handoffs — two mean a '
        'succession was SKIPPED, and only a human can say which board is '
        'real. Read them, delete the stale one by hand, then run this again.',
        handoffs: resolved,
      );
    }
    final candidate = found.single.handoff;
    final candidateName = p.basename(candidate.path);
    final memoryFile = File(p.join(disc.directory, kSeatMemoryFileName));

    // 2. Exactly one pointer line at it. Checked in BOTH modes: `--no-destructive`
    //    is documented as the safe first run on an unfamiliar disc, and a
    //    preview that green-lights a run which would then refuse is worse than
    //    no preview at all.
    final pointer = _resolvePointer(memoryFile, candidateName);
    if (pointer.refusal != null) return refuse(pointer.refusal!);

    final runner = _runner ?? SystemGitRunner();
    final ops = GitOps(runner);
    final seatPathspec = p.join(kSeatsSubdirectory, seat);

    // 3. Archive the disc — and only the disc — when the tree is dirty. The
    //    gate carries the work-tree-root guard and the fail-closed degraded
    //    scan; a `clear` tree cannot hold an unarchived disc.
    var staged = false;
    var committed = false;
    switch (await ops.hasUncommittedWork(home)) {
      case GateOutcome.probeError:
        return refuse(
          'the git work-tree gate would not clear "$home" — a seat disc is '
          'archived only from a repository ROOT whose `git status` reads '
          'cleanly. Nothing was staged, committed or deleted.',
          handoffs: resolved,
        );
      case GateOutcome.clear:
        break;
      case GateOutcome.present:
        final add = await runner.run(
          workingDirectory: home,
          args: <String>['add', '-A', '--', seatPathspec],
        );
        if (!add.ok) {
          return refuse(
            'could not stage the disc — `git add -A -- $seatPathspec` failed: '
            '${_oneLine(add.output)}',
            handoffs: resolved,
          );
        }
        staged = true;
        // A FAILING scoped commit is not fatal on its own: the tree is dirty
        // somewhere, but that dirt may be entirely outside this disc, and
        // `git commit --only` refuses an empty scope. The archive PROOF below
        // is the guard — it is what decides whether anything may be deleted.
        final commit = await runner.run(
          workingDirectory: home,
          args: <String>[
            'commit',
            '--only',
            '-m',
            seatArchiveCommitMessage(seat),
            '--',
            seatPathspec,
          ],
        );
        committed = commit.ok;
    }

    // 4. Prove BOTH consumed files are in HEAD and byte-identical to the
    //    working copy. `cat-file` proves presence; `diff --quiet` proves the
    //    committed copy is the one about to be destroyed — a commit that
    //    failed on a hook or a signature would otherwise pass presence alone.
    for (final relative in <String>[
      candidate.relativePath,
      p.relative(memoryFile.path, from: home),
    ]) {
      final missing = await _proveArchived(runner, home, relative);
      if (missing != null) {
        return refuse(
          missing,
          handoffs: resolved,
          staged: staged,
          committed: committed,
        );
      }
    }

    // 5. Re-resolve: a sibling written during the commit window is the same
    //    skipped succession as an initial two, and it must not be consumed
    //    unseen.
    final after = disc.handoffs();
    final afterPaths = [for (final entry in after) entry.handoff.relativePath];
    if (after.length != 1 || after.single.handoff.path != candidate.path) {
      return refuse(
        'the disc changed while it was being archived — this run resolved '
        '"${candidate.relativePath}", and the disc now carries '
        '${afterPaths.isEmpty ? 'none' : afterPaths.join(', ')}. Nothing was '
        'deleted.',
        handoffs: afterPaths.isEmpty ? resolved : afterPaths,
        staged: staged,
        committed: committed,
      );
    }

    if (!destructive) {
      return SeatSuccessionReport(
        seat: seat,
        disposition: SeatSuccessionDisposition.preserved,
        handoffs: resolved,
        staged: staged,
        committed: committed,
      );
    }

    // 6. Consume. The pointer is resolved AGAIN, against the bytes on disk
    //    now, so the line removed is the line proved — never one read before
    //    the archive.
    final live = _resolvePointer(memoryFile, candidateName);
    if (live.refusal != null) {
      return refuse(
        live.refusal!,
        handoffs: resolved,
        staged: staged,
        committed: committed,
      );
    }
    memoryFile.writeAsStringSync(
      removeMemoryLine(memory: live.memory!, index: live.line!),
    );
    File(candidate.path).deleteSync();
    return SeatSuccessionReport(
      seat: seat,
      disposition: SeatSuccessionDisposition.consumed,
      handoffs: resolved,
      staged: staged,
      committed: committed,
    );
  }

  /// The disc index's single pointer at [target], read fresh off [memoryFile]:
  /// its bytes and the line index, or the refusal that stops the run.
  ({String? memory, int? line, String? refusal}) _resolvePointer(
    File memoryFile,
    String target,
  ) {
    if (!memoryFile.existsSync()) {
      return (
        memory: null,
        line: null,
        refusal:
            'the disc has no $kSeatMemoryFileName, so the handoff was never '
            'indexed — index it, or delete it by hand.',
      );
    }
    final memory = memoryFile.readAsStringSync();
    final lines = memoryPointerLines(memory: memory, target: target);
    if (lines.length != 1) {
      return (
        memory: null,
        line: null,
        refusal:
            '$kSeatMemoryFileName carries ${lines.length} pointer lines at '
            '"$target" — exactly one is consumable, so this run would either '
            'orphan an index line or guess which to remove.',
      );
    }
    return (memory: memory, line: lines.single, refusal: null);
  }

  /// Null when [relative] is present at `HEAD` AND identical to the working
  /// copy, or the refusal naming which half failed.
  Future<String?> _proveArchived(
    GitRunner runner,
    String home,
    String relative,
  ) async {
    final atHead = await runner.run(
      workingDirectory: home,
      args: <String>['cat-file', '-e', 'HEAD:$relative'],
    );
    if (!atHead.ok) {
      return '"$relative" is not in HEAD — there is no archive to delete it '
          'into (${_oneLine(atHead.output)}).';
    }
    final same = await runner.run(
      workingDirectory: home,
      args: <String>['diff', '--quiet', 'HEAD', '--', relative],
    );
    if (!same.ok) {
      return 'the copy of "$relative" in HEAD is NOT the copy on disk — the '
          'archive would lose the working bytes '
          '(${_oneLine(same.output)}).';
    }
    return null;
  }
}

/// Collapses [text] to one trimmed line so a refusal stays greppable.
String _oneLine(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// `succession <seat> [--grid-home <abs>] [--no-destructive]` — the THIN argv
/// and sink adapter over [SeatSuccessionService].
class SuccessionCommand extends Command<int> {
  /// Creates the verb over its injectable seams: the [service] that does the
  /// work, the [gridHomeDefault] a bare invocation falls back to, and the
  /// [out]/[err] report sinks.
  SuccessionCommand({
    SeatSuccessionService service = const SeatSuccessionService(),
    String Function() gridHomeDefault = _currentDirectory,
    StringSink? out,
    StringSink? err,
  }) : _service = service,
       _gridHomeDefault = gridHomeDefault,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addOption(
        'grid-home',
        abbr: 'g',
        help:
            'The station grid home (ABSOLUTE): the git work-tree ROOT that '
            'holds .grid/seats/<name>/. Defaults to the current directory.',
      )
      ..addFlag(
        'destructive',
        defaultsTo: true,
        help:
            'Delete the consumed handoff and its MEMORY.md pointer line. '
            '--no-destructive still archives and verifies, then names the '
            'file it WOULD have deleted — the safe first run on an '
            'unfamiliar disc.',
      );
  }

  final SeatSuccessionService _service;
  final String Function() _gridHomeDefault;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'succession';

  @override
  final String description =
      "Consume a seat's newest handoff: archive its disc, verify the archive, "
      'then delete the note and its index line.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape = 'succession <seat> [--grid-home <abs>] [--no-destructive]';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln(
        'succession: exactly one seat name is required — $invocation',
      );
      return 64;
    }
    final seat = rest.single.trim();
    final flag = argResults!.option('grid-home')?.trim();
    final unresolved = (flag == null || flag.isEmpty)
        ? _gridHomeDefault()
        : flag;
    if (!p.isAbsolute(unresolved)) {
      usageException(
        'succession: --grid-home must be an ABSOLUTE path '
        '(got "$unresolved").',
      );
    }
    return _render(
      await _service.succeed(
        gridHome: p.normalize(unresolved),
        seat: seat,
        destructive: argResults!.flag('destructive'),
      ),
    );
  }

  /// Writes exactly what the run did and returns its exit code.
  int _render(SeatSuccessionReport report) {
    final head = 'succession: ${report.seat}';
    final archive = report.committed ? 'COMMITTED' : 'ALREADY ARCHIVED';
    switch (report.disposition) {
      case SeatSuccessionDisposition.noHandoff:
        _out.writeln('$head — NO HANDOFF');
        return 0;
      case SeatSuccessionDisposition.refused:
        _err.writeln(
          '$head — REFUSED: ${report.refusal} '
          '(staged: ${report.staged ? 'yes' : 'no'}, '
          'committed: ${report.committed ? 'yes' : 'no'})',
        );
        for (final path in report.handoffs) {
          _err.writeln('$head — handoff $path');
        }
        return 1;
      case SeatSuccessionDisposition.preserved:
        _out
          ..writeln('$head — $archive')
          ..writeln('$head — WOULD DELETE ${report.candidate}');
        return 0;
      case SeatSuccessionDisposition.consumed:
        _out
          ..writeln('$head — $archive')
          ..writeln(
            '$head — DELETED ${report.candidate} AND '
            '$kSeatMemoryFileName POINTER',
          );
        return 0;
    }
  }
}

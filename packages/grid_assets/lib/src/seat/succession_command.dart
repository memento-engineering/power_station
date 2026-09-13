/// `succession <seat>` — the handoff's two mechanical edges: WRITE one onto the
/// seat's disc (once), and CONSUME one by archiving the disc first.
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
/// 3. resolve the archive SINK from the disc's own tracked state, and archive
///    into it — a scoped commit of the seat disc when it is tracked, a local
///    `.archive/<utc-stamp>/` directory under the disc when git IGNORES it;
/// 4. PROVE both files reached that archive byte-identical to the working copy;
/// 5. re-resolve the disc and refuse a sibling that appeared in the archive
///    window;
/// 6. delete the handoff and its one pointer line — or, under
///    `--no-destructive`, stop here and name what it WOULD have deleted.
///
/// **Two sinks, one precondition** (Nico, 2026-09-13, fork option (a)). A
/// station may ignore its seats tree for the PII a disc accretes —
/// lunar_station did, at 7b225e8 — and from 2026-09-13 that refused every
/// succession on the station: `could not stage the disc — git add -A --
/// .grid/seats/governor failed: The following paths are ignored`. `git add -f`
/// is NEVER the answer: it would commit the material the ignore exists to keep
/// out. So an ignored disc archives LOCALLY, under the same ignore, and the
/// proof is a byte comparison of the copies instead of a `HEAD` comparison. The
/// precondition itself is unchanged — nothing is destroyed until it is proved
/// archived somewhere.
///
/// **The launcher is the caller** (Nico, 2026-09-13). `seat` performs this
/// succession itself before it primes a successor, so a successor can neither
/// start unprimed nor skip the consumption; this verb stays as the by-hand
/// RECOVERY path for a disc no launcher touched.
///
/// Every refusal is LOUD: it names what it refused on, whether the index was
/// touched, and it deletes nothing.
///
/// **The other edge: `--write-handoff <file>`.** Consuming a handoff was an
/// enforced verb while WRITING one was prose, and the asymmetry showed: one
/// governor note was rewritten across thirty commits over nine hours, so its
/// own file-name stamp lied. That mode reads the complete note on stdin and
/// puts it through [SeatDisc.writeHandoffOnce], which refuses a second live
/// handoff instead of amending the first
/// (`memento-engineering#handoffs-are-working-memory-and-long-term-memory-stays-thin`:
/// a handoff is "written once at a boundary, picked up, and deleted"). It writes
/// the NOTE only — the one `MEMORY.md` pointer line stays an explicit step in
/// the vended ritual, because the index is checked here and never rewritten.
///
/// Both modes render [seatHandoffAgeDiagnostic] for every handoff already on the
/// disc, first, before they act. No threshold, no expiry: with amendment
/// refused, an aging unconsumed note is simply a seat that has not handed off,
/// and the age is how a reader sees that.
///
/// **Scope.** The verb owns the MECHANICS only. What a handoff says, when one
/// is written, and the one line handed to the outer harness stay with the
/// `/handoff` skill; no judgement moves into code here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show GateOutcome, GitOps, GitRunner, SystemGitRunner;
import 'package:path/path.dart' as p;

import 'seat_disc.dart';

String _currentDirectory() => Directory.current.path;

/// The whole note, off stdin, decoded as UTF-8.
///
/// DELIBERATELY unbounded in time: a truncated handoff is worse than a slow one,
/// and this mode is invoked by a caller that has already composed the complete
/// note and pipes it in one operation.
Future<String> _readStdinNote() => stdin.transform(utf8.decoder).join();

/// The message the scoped archive commit carries. PURE.
String seatArchiveCommitMessage(String seat) =>
    'chore(seat): archive $seat disc';

/// WHERE a run archived the disc before it consumed the note — the fork is the
/// disc's OWN tracked state, and the two sinks are exclusive. Sealed by an enum
/// so every reader faces both with an exhaustive `switch`.
enum SeatArchiveSink {
  /// The disc is tracked: the archive is a pathspec-scoped commit, and the
  /// proof is `HEAD` (`power_station#handoff-succession-commits-before-consume`
  /// unchanged).
  git,

  /// The disc is gitignored: the archive is `.archive/<utc-stamp>/` under the
  /// disc — covered by the same ignore, so nothing re-enters history — and the
  /// proof is a byte comparison of the copies.
  local,
}

/// The ONE phrase naming where a run archived the disc, rendered identically by
/// every reader of a [SeatSuccessionReport]. PURE.
String seatArchiveDisposition(SeatSuccessionReport report) =>
    switch (report.sink) {
      null => 'NOT ARCHIVED',
      SeatArchiveSink.git =>
        report.committed ? 'COMMITTED' : 'ALREADY ARCHIVED',
      SeatArchiveSink.local => 'ARCHIVED-LOCAL ${report.archive}',
    };

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
    this.sink,
    this.archive,
    this.body,
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

  /// WHERE the disc was archived, or null when the run never reached an
  /// archive (no handoff, or a refusal before the sink was resolved).
  final SeatArchiveSink? sink;

  /// The grid-home-relative local archive directory, on
  /// [SeatArchiveSink.local] only — null for the git sink, whose archive is a
  /// commit rather than a path.
  final String? archive;

  /// The BODY of the one handoff this run archived — what a launcher primes
  /// its successor with, read BEFORE the note was destroyed. Null on every
  /// disposition that resolved no single candidate.
  final String? body;

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
/// **Only one of the two sinks rides git at all.** An IGNORED disc is archived
/// by copying its two consumed files into `.archive/<utc-stamp>/` under the
/// disc, and proved by reading the copies back — no `git` command runs on that
/// path, and `git add -f` runs on NO path.
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
  /// Creates the service over its two seams beyond the disc itself: the
  /// [runner] every `git` call rides (Fakes, not mocks; absent ⇒ the real
  /// [SystemGitRunner]), and the [now] clock a LOCAL archive directory is
  /// stamped from.
  const SeatSuccessionService({
    GitRunner? runner,
    DateTime Function() now = DateTime.now,
  }) : _runner = runner,
       _now = now;

  final GitRunner? _runner;
  final DateTime Function() _now;

  /// Archives [seat]'s disc under [gridHome] — into git history, or into the
  /// disc's own `.archive/` when git ignores it — and consumes its one live
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

    // 3. The SINK is the disc's own tracked state, resolved before any
    //    mutation: an ignored disc has no history to archive into, and the one
    //    git verb that would force it there is the one that must never run.
    final sink = await _resolveSink(
      runner: runner,
      home: home,
      discDirectory: disc.directory,
    );
    if (sink.refusal != null) {
      return refuse(sink.refusal!, handoffs: resolved);
    }

    // 4. Archive, and PROVE it, before anything can be destroyed.
    final memoryRelative = p.relative(memoryFile.path, from: home);
    var staged = false;
    var committed = false;
    String? archive;
    switch (sink.sink!) {
      case SeatArchiveSink.git:
        final done = await _archiveIntoGit(
          runner: runner,
          home: home,
          seat: seat,
          relatives: <String>[candidate.relativePath, memoryRelative],
        );
        staged = done.staged;
        committed = done.committed;
        if (done.refusal != null) {
          return refuse(
            done.refusal!,
            handoffs: resolved,
            staged: staged,
            committed: committed,
          );
        }
      case SeatArchiveSink.local:
        final done = _archiveLocally(
          home: home,
          discDirectory: disc.directory,
          sources: <File>[File(candidate.path), memoryFile],
        );
        archive = done.archive;
        if (done.refusal != null) {
          return refuse(done.refusal!, handoffs: resolved);
        }
    }

    // 5. Re-resolve: a sibling written during the archive window is the same
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
        sink: sink.sink,
        archive: archive,
        body: candidate.body,
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
      sink: sink.sink,
      archive: archive,
      body: candidate.body,
    );
  }

  /// The archive sink for the disc at [discDirectory], or the refusal that
  /// stops the run.
  ///
  /// `git check-ignore` answers the ONE question that decides it: 0 when the
  /// path is ignored, 1 when it is not. Anything else — a non-launch, a grid
  /// home that is no repository at all — is "couldn't tell", and a run that
  /// cannot tell which archive it would be deleting into must not delete.
  Future<({SeatArchiveSink? sink, String? refusal})> _resolveSink({
    required GitRunner runner,
    required String home,
    required String discDirectory,
  }) async {
    final relative = p.relative(discDirectory, from: home);
    final probe = await runner.run(
      workingDirectory: home,
      args: <String>['check-ignore', '-q', '--', relative],
    );
    if (!probe.launched) {
      return (
        sink: null,
        refusal:
            'git would not run in "$home", so the archive sink cannot be '
            'resolved (${_oneLine(probe.output)}). Nothing was staged, '
            'committed or deleted.',
      );
    }
    return switch (probe.exitCode) {
      0 => (sink: SeatArchiveSink.local, refusal: null),
      1 => (sink: SeatArchiveSink.git, refusal: null),
      final code => (
        sink: null,
        refusal:
            '`git check-ignore -q -- $relative` exited $code in "$home", so '
            'whether this disc is tracked is UNKNOWN — and the two archive '
            'sinks are git history and the disc\'s own .archive/, which is not '
            'a choice to make blind (${_oneLine(probe.output)}).',
      ),
    };
  }

  /// Archives a TRACKED disc into git history: the pathspec-scoped commit of
  /// `power_station#handoff-succession-commits-before-consume`, then the proof
  /// that every path in [relatives] is at `HEAD` and byte-identical to the
  /// working copy.
  ///
  /// The gate carries the work-tree-root guard and the fail-closed degraded
  /// scan; a `clear` tree cannot hold an unarchived disc. `git add -f` is never
  /// used here or anywhere: this sink is reached only when the disc is NOT
  /// ignored, so no force is needed, and on an ignored disc a force would
  /// commit the material the ignore exists to keep out.
  Future<({String? refusal, bool staged, bool committed})> _archiveIntoGit({
    required GitRunner runner,
    required String home,
    required String seat,
    required List<String> relatives,
  }) async {
    final ops = GitOps(runner);
    final seatPathspec = p.join(kSeatsSubdirectory, seat);
    var staged = false;
    var committed = false;
    switch (await ops.hasUncommittedWork(home)) {
      case GateOutcome.probeError:
        return (
          refusal:
              'the git work-tree gate would not clear "$home" — a seat disc is '
              'archived only from a repository ROOT whose `git status` reads '
              'cleanly. Nothing was staged, committed or deleted.',
          staged: staged,
          committed: committed,
        );
      case GateOutcome.clear:
        break;
      case GateOutcome.present:
        final add = await runner.run(
          workingDirectory: home,
          args: <String>['add', '-A', '--', seatPathspec],
        );
        if (!add.ok) {
          return (
            refusal:
                'could not stage the disc — `git add -A -- $seatPathspec` '
                'failed: ${_oneLine(add.output)}',
            staged: staged,
            committed: committed,
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
    for (final relative in relatives) {
      final missing = await _proveArchived(runner, home, relative);
      if (missing != null) {
        return (refusal: missing, staged: staged, committed: committed);
      }
    }
    return (refusal: null, staged: staged, committed: committed);
  }

  /// Archives an IGNORED disc into `.archive/<utc-stamp>/` beside its notes,
  /// and returns that directory grid-home-relative.
  ///
  /// The copies are PROVED the way the git sink proves `HEAD`: every source is
  /// read, written, and read back, and the run refuses on the first byte that
  /// differs. The stamp directory is never reused — an archive that already
  /// exists at this second is a second succession inside one second, and
  /// overwriting it would destroy the very copy it is supposed to be.
  ///
  /// No `git` runs here at all. `git add -f` is what the git sink would need
  /// for an ignored path, and forcing the disc back into history is exactly
  /// what the ignore exists to prevent.
  ({String? refusal, String? archive}) _archiveLocally({
    required String home,
    required String discDirectory,
    required List<File> sources,
  }) {
    final stamp = seatArchiveStamp(_now());
    final directory = Directory(
      p.join(discDirectory, kSeatArchiveSubdirectory, stamp),
    );
    final relative = p.relative(directory.path, from: home);
    if (directory.existsSync()) {
      return (
        refusal:
            'the local archive "$relative" already exists — a second '
            'succession inside one second would overwrite the copy it is '
            'archiving into. Nothing was deleted.',
        archive: null,
      );
    }
    try {
      directory.createSync(recursive: true);
      for (final source in sources) {
        final target = File(p.join(directory.path, p.basename(source.path)));
        final bytes = source.readAsBytesSync();
        target.writeAsBytesSync(bytes, flush: true);
        if (!_sameBytes(target.readAsBytesSync(), bytes)) {
          return (
            refusal:
                'the local archive of "${p.relative(source.path, from: home)}" '
                'is NOT byte-identical to the copy on disk, so the archive '
                'would lose the working bytes. Nothing was deleted.',
            archive: relative,
          );
        }
      }
    } on FileSystemException catch (error) {
      return (
        refusal:
            'the local archive "$relative" could not be written — '
            '${_oneLine(error.osError?.message ?? error.message)}. Nothing '
            'was deleted.',
        archive: relative,
      );
    }
    return (refusal: null, archive: relative);
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

/// Whether [left] and [right] are the same bytes — the local archive's proof.
/// PURE.
bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// The THIN argv and sink adapter over [SeatSuccessionService] and
/// [SeatDisc.writeHandoffOnce] — see [invocation] for the shape.
class SuccessionCommand extends Command<int> {
  /// Creates the verb over its injectable seams: the [service] that does the
  /// consume work, the [gridHomeDefault] a bare invocation falls back to, the
  /// [readStdin] the write mode takes its note from, the [now] clock the age
  /// diagnostic is measured against, and the [out]/[err] report sinks.
  SuccessionCommand({
    SeatSuccessionService service = const SeatSuccessionService(),
    String Function() gridHomeDefault = _currentDirectory,
    Future<String> Function() readStdin = _readStdinNote,
    DateTime Function() now = DateTime.now,
    StringSink? out,
    StringSink? err,
  }) : _service = service,
       _gridHomeDefault = gridHomeDefault,
       _readStdin = readStdin,
       _now = now,
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
      )
      ..addOption(
        'write-handoff',
        valueHelp: 'file',
        help:
            "WRITE the complete note on stdin to the seat's disc under this "
            'disc-local name, ONCE: a disc that already carries a live '
            'handoff is refused, never amended. Writes the note only — the '
            'MEMORY.md pointer line stays the caller\'s one explicit step.',
      );
  }

  final SeatSuccessionService _service;
  final String Function() _gridHomeDefault;
  final Future<String> Function() _readStdin;
  final DateTime Function() _now;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'succession';

  @override
  final String description =
      "Consume a seat's newest handoff: archive its disc, verify the archive, "
      'then delete the note and its index line. With --write-handoff, write '
      'one instead — once.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape =
        'succession <seat> [--grid-home <abs>] [--no-destructive] '
        '[--write-handoff <file>]';
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
    final gridHome = p.normalize(unresolved);
    final destructive = argResults!.flag('destructive');
    final write = argResults!.option('write-handoff')?.trim();
    // The two modes are OPPOSITE edges of one lifetime, and --no-destructive is
    // a preview of the CONSUME path; asking for both names no coherent run.
    if (write != null && write.isNotEmpty && !destructive) {
      usageException(
        'succession: --write-handoff writes a note and --no-destructive '
        'previews a consume — ask for one run, not both.',
      );
    }

    // Observational, and FIRST: what the disc already carries, and how long it
    // has carried it. Reported in both modes and behind neither one's outcome.
    _reportAge(gridHome: gridHome, seat: seat);

    if (write != null && write.isNotEmpty) {
      return _write(gridHome: gridHome, seat: seat, fileName: write);
    }
    return _render(
      await _service.succeed(
        gridHome: gridHome,
        seat: seat,
        destructive: destructive,
      ),
    );
  }

  /// Writes one [seatHandoffAgeDiagnostic] per handoff already on the disc.
  ///
  /// Every dependency is isolated: an unreadable disc costs a diagnostic, never
  /// the run that was asked for.
  void _reportAge({required String gridHome, required String seat}) {
    try {
      final observed = SeatDisc(
        directory: seatDiscPath(gridHome, seat),
        gridHome: gridHome,
      ).handoffs();
      if (observed.isEmpty) return;
      final at = _now();
      for (final entry in observed) {
        _out.writeln(
          seatHandoffAgeDiagnostic(
            seat: seat,
            handoff: entry.handoff,
            authoredAt: entry.at,
            now: at,
          ),
        );
      }
    } on Object {
      return;
    }
  }

  /// The write mode: the complete note off stdin, through the write-once gate.
  Future<int> _write({
    required String gridHome,
    required String seat,
    required String fileName,
  }) async {
    final head = 'succession: $seat';
    final disc = SeatDisc(
      directory: seatDiscPath(gridHome, seat),
      gridHome: gridHome,
    );
    try {
      final written = disc.writeHandoffOnce(
        fileName: fileName,
        contents: await _readStdin(),
      );
      _out.writeln('$head — HANDOFF WRITTEN ${written.relativePath}');
      return 0;
    } on SeatHandoffWriteException catch (refusal) {
      _err.writeln('$head — REFUSED: ${refusal.detail}');
      for (final path in refusal.existingHandoffs) {
        _err.writeln('$head — handoff $path');
      }
      return 1;
    }
  }

  /// Writes exactly what the run did and returns its exit code.
  int _render(SeatSuccessionReport report) {
    final head = 'succession: ${report.seat}';
    final archive = seatArchiveDisposition(report);
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

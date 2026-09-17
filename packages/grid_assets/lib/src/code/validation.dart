/// The VALIDATION-PLAN seam: the shell-exec runner every lane that runs a
/// bead's own Validation Plan rides, and the MERGE-BASE COMPARISON that decides
/// which of a run's failures are the bead's.
///
/// **Why a delta and not an exit code**
/// (`power_station#code-validation-hard-blocks-only-branch-regressions`). The
/// lane used to hard-block on ANY non-zero plan, so a failure identical on the
/// merge-base — a host-only flake, another bead's leak, a pre-existing red —
/// gated the round. Measured over one trajectory log the operator then
/// overrode 70 of 73 blocks by hand. The lane now runs the SAME plan on the
/// branch and at the merge-base, on the SAME host, and only a named test that
/// PASSES on the base and FAILS on the branch is the bead's regression. A test
/// failing identically on both is pre-existing EVIDENCE: named in the artifact,
/// carried into the PR receipt, and never a gate.
///
/// **Why the lane owns its own deadline**
/// (`power_station#code-validation-enforces-its-own-deadline-as-a-service-capability`).
/// The comparison's base run happens in a detached scratch worktree OUTSIDE any
/// per-bead `RuntimeProvider`, so the provider's watchdog cannot bound it.
/// [SystemShellRunner] bounds BOTH runs itself: the plan gets its own process
/// group, and a run that outlives [kValidationDeadline] has that whole group
/// terminated and is reported as [ShellRunResult.timedOut] — the same
/// ten-minute bound the retired watchdog arm enforced.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

/// The Validation Plan's absolute-from-start deadline (the_grid audit §4,
/// `tg-uad` follow-through): a plan is `sh` running a deterministic script,
/// minutes-scale by definition — never the multi-hour agentic build/critic
/// lanes — so it must NOT ride a runtime provider's 2-hour default watchdog.
/// Ten minutes bounds every validation-latched variant of the lane without
/// crowding a legitimately slow (but still deterministic) plan.
const Duration kValidationDeadline = Duration(minutes: 10);

/// The injectable shell-exec seam a Validation Plan runs through — mirrors
/// [GitRunner]'s shape (Fakes, not mocks), but for an arbitrary shell command
/// rather than `git`.
abstract interface class ShellRunner {
  /// Runs [command] via `sh -c` with [workingDirectory] as the cwd. Never
  /// throws — a launch failure is reported as a non-zero [ShellRunResult].
  ///
  /// A non-null [deadline] BOUNDS the run: an implementation that exceeds it
  /// terminates the command (and everything it spawned) and answers
  /// [ShellRunResult.timedOut].
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
    Duration? deadline,
  });
}

/// The result of one [ShellRunner.run] — the exit code and combined
/// stdout+stderr.
class ShellRunResult {
  /// Creates the result. [timedOut] defaults to false so every existing
  /// construction (a Fake's canned answer, a bounded-less run) is unchanged.
  const ShellRunResult({
    required this.exitCode,
    required this.output,
    this.timedOut = false,
  });

  /// The process exit code.
  final int exitCode;

  /// stdout and stderr combined.
  final String output;

  /// Whether the run was terminated for exceeding its deadline.
  final bool timedOut;

  /// Whether the command succeeded (exit 0).
  bool get ok => exitCode == 0;
}

/// The real [ShellRunner]: execs `sh -c <command>` via `dart:io`.
///
/// **The process group.** A bounded run must be able to kill what the plan
/// SPAWNED, not just the shell that spawned it: `dart test` reaped at the top
/// leaves its own child test runners alive, and those are what hold the
/// worktree. A plain `Process.start` child inherits THIS process's group, so
/// there is no group to signal. The bounded path therefore runs the plan as a
/// JOB of a wrapper shell under job control (`set -m`), which makes the job a
/// process-group LEADER; the wrapper records the job's pid — its pgid — and on
/// the deadline the whole group is signalled through it.
///
/// The plan itself is NEVER spliced into the wrapper: it rides as an argv
/// element the wrapper hands to a child `sh -c "$1"`, so a plan that merely
/// fails to PARSE is an ordinary non-zero exit of the child rather than a
/// syntax error that takes the wrapper (and its receipts) down with it.
class SystemShellRunner implements ShellRunner {
  /// Creates the runner.
  const SystemShellRunner();

  /// The wrapper script, a FIXED string — no plan text is ever interpolated.
  ///
  /// `$1` is the plan, `$2` the file the job's pgid is recorded in. Monitor
  /// mode is enabled only long enough to put the job in its own group, then
  /// disabled again so no `[1]+ Done` job notification can leak into the
  /// captured output.
  static const String _groupedWrapper =
      'set -m\n'
      '{ set +m; sh -c "\$1"; } &\n'
      '__grid_plan=\$!\n'
      'set +m\n'
      'printf \'%s\\n\' "\$__grid_plan" > "\$2"\n'
      'wait \$__grid_plan\n';

  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
    Duration? deadline,
  }) async {
    if (deadline == null) {
      final result = await Process.run('sh', [
        '-c',
        command,
      ], workingDirectory: workingDirectory);
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      return ShellRunResult(
        exitCode: result.exitCode,
        output: stderr.isEmpty ? stdout : '$stdout$stderr',
      );
    }

    final scratch = Directory.systemTemp.createTempSync('grid-plan-group-');
    final pgidFile = p.join(scratch.path, 'pgid');
    try {
      final process = await Process.start('sh', [
        '-c',
        _groupedWrapper,
        'grid-validation',
        command,
        pgidFile,
      ], workingDirectory: workingDirectory);
      final out = StringBuffer();
      final err = StringBuffer();
      final drained = Future.wait([
        process.stdout
            .transform(const SystemEncoding().decoder)
            .forEach(out.write),
        process.stderr
            .transform(const SystemEncoding().decoder)
            .forEach(err.write),
      ]);
      var timedOut = false;
      final timer = Timer(deadline, () {
        timedOut = true;
        _terminateGroup(pgidFile: pgidFile, wrapperPid: process.pid);
      });
      final exitCode = await process.exitCode;
      timer.cancel();
      // The captured output is COMPLETE before the result is assembled: a
      // deadline that killed the group still yields everything the plan managed
      // to emit, which is the only diagnosis a timeout leaves behind.
      await drained;
      return ShellRunResult(
        exitCode: exitCode,
        output: err.isEmpty ? out.toString() : '$out$err',
        timedOut: timedOut,
      );
    } finally {
      try {
        scratch.deleteSync(recursive: true);
      } on Object {
        // Best-effort: a scratch dir that outlives one bounded run costs
        // nothing, and the run's own result is what the lane grades on.
      }
    }
  }

  /// Signals the plan's whole process group, falling back to the wrapper alone
  /// when the job never recorded its pgid (a write that could not land).
  static void _terminateGroup({
    required String pgidFile,
    required int wrapperPid,
  }) {
    int? pgid;
    try {
      final recorded = File(pgidFile);
      if (recorded.existsSync()) {
        pgid = int.tryParse(recorded.readAsStringSync().trim());
      }
    } on Object {
      pgid = null;
    }
    if (pgid != null && pgid > 0) {
      Process.killPid(-pgid, ProcessSignal.sigkill);
    }
    Process.killPid(wrapperPid, ProcessSignal.sigkill);
  }
}

/// A comparison that could not produce comparable named-test outcomes — a LANE
/// failure with a named cause, never a bead block.
///
/// The ruling is explicit: "A plan that fails on the base for a reason other
/// than a named test (compile error, exit 64, missing tool) is a lane failure
/// with a named cause, not a bead block." The same holds for the branch side —
/// a branch plan that exits non-zero with nothing the parser recognises as a
/// failing test has no delta to compute, so the lane refuses rather than
/// inventing a regression.
class ValidationLaneFailure implements Exception {
  /// Creates the failure.
  const ValidationLaneFailure({
    required this.side,
    required this.cause,
    this.baseSha,
    this.exitCode,
    this.timedOut = false,
    this.outputTail = '',
    this.logPath,
  });

  /// Which run could not be compared — `base`, `branch`, or `worktree` (the
  /// scratch checkout the base run needs).
  final String side;

  /// The named cause, in the lane's own words.
  final String cause;

  /// The merge-base commit the comparison resolved, when it got that far.
  final String? baseSha;

  /// The implicated run's exit code, when one exists.
  final int? exitCode;

  /// Whether the implicated run was terminated on its deadline.
  final bool timedOut;

  /// A bounded tail of the implicated run's captured output.
  final String outputTail;

  /// The durable log the implicated run's FULL output was written to.
  final String? logPath;

  /// The operator-facing message — the side and its cause lead, then the base
  /// commit, the exit class, the durable log, and the captured tail.
  String get message {
    final b = StringBuffer('validation $side: $cause');
    if (baseSha != null) b.write(' (merge-base $baseSha)');
    if (exitCode != null) {
      b.write(timedOut ? '; timed out (exit $exitCode)' : '; exit $exitCode');
    } else if (timedOut) {
      b.write('; timed out');
    }
    if (logPath != null) b.write('; full log: $logPath');
    if (outputTail.trim().isNotEmpty) b.write(': ${outputTail.trim()}');
    return b.toString();
  }

  @override
  String toString() => message;
}

/// The answer one comparison produced: which named test failures are the
/// BRANCH'S (a gate) and which the base already had (a note).
class ValidationDelta {
  /// Creates the delta.
  ValidationDelta({
    required this.baseSha,
    required this.baseCacheHit,
    required this.branchExitCode,
    required this.branchTimedOut,
    required List<String> regressions,
    required List<String> preexisting,
  }) : regressions = List.unmodifiable(regressions),
       preexisting = List.unmodifiable(preexisting);

  /// The merge-base commit both runs were compared across.
  final String baseSha;

  /// Whether the base run was answered from the (base sha, plan digest, host)
  /// cache rather than re-run.
  final bool baseCacheHit;

  /// The BRANCH plan's RAW exit code — preserved even when the delta is empty,
  /// because "the plan exited 1 with only pre-existing failures" is a different
  /// fact from "the plan passed".
  final int branchExitCode;

  /// Whether the branch run was terminated on its deadline.
  final bool branchTimedOut;

  /// Sorted named tests that FAIL on the branch and PASS at the merge-base —
  /// the only failures that gate.
  final List<String> regressions;

  /// Sorted named tests that fail IDENTICALLY on both sides — evidence, never
  /// a gate.
  final List<String> preexisting;

  /// The EFFECTIVE exit code: zero unless the branch regressed.
  int get effectiveExitCode =>
      regressions.isEmpty ? 0 : (branchExitCode == 0 ? 1 : branchExitCode);
}

/// Runs one Validation Plan on the branch AND at its merge-base, on the same
/// host, and answers the [ValidationDelta] between them.
///
/// The base side is CACHED per (base sha, plan digest, host identity), so a
/// wave of rounds over one main commit pays for the base exactly once. A lane
/// failure is never cached: an uncomparable base must be re-attempted, not
/// remembered.
class ValidationDeltaRunner {
  /// Creates the runner over the composing registry's EXISTING seams — no
  /// second git or process seam is introduced ([gitRunner] is the `code`
  /// registry's one git seam, A9(5); [shellRunner] the one shell seam).
  ///
  /// [cacheHome] is the composing grid home the base-run cache lives under;
  /// null falls back to the branch workspace itself. [hostIdentity] overrides
  /// `Platform.localHostname` — the third cache key, because a base result is
  /// only reusable on the host that produced it.
  const ValidationDeltaRunner({
    GitRunner? gitRunner,
    ShellRunner? shellRunner,
    String? cacheHome,
    String? hostIdentity,
    this.deadline = kValidationDeadline,
  }) : _gitRunner = gitRunner,
       _shellRunner = shellRunner,
       _cacheHome = cacheHome,
       _hostIdentity = hostIdentity;

  final GitRunner? _gitRunner;
  final ShellRunner? _shellRunner;
  final String? _cacheHome;
  final String? _hostIdentity;

  /// The bound BOTH runs are given.
  final Duration deadline;

  /// The cache's schema version — a stored entry written by any other version
  /// is a MISS, never a misread.
  static const int _cacheSchemaVersion = 1;

  /// Compares [plan] on [workspace]'s branch against its merge-base with
  /// [baseRef].
  ///
  /// [baseRef] is ALREADY RESOLVED by the caller through the committee's own
  /// `reviewBaseRef` — this runner never re-derives the review base, so the
  /// recorded-provisioner-SHA rule that helper owns has exactly one home.
  ///
  /// [branchLogPath] receives the branch run's FULL combined output;
  /// [effectiveRcPath], when given, receives the EFFECTIVE exit code (zero
  /// unless the branch regressed).
  Future<ValidationDelta> compare({
    required String plan,
    required Workspace workspace,
    required String baseRef,
    required String branchLogPath,
    String? effectiveRcPath,
  }) async {
    final git = _gitRunner ?? SystemGitRunner();
    final shell = _shellRunner ?? const SystemShellRunner();
    final workDir = workspace.workspaceDir;

    final merged = await git.run(
      workingDirectory: workDir,
      args: ['merge-base', 'HEAD', baseRef],
    );
    final baseSha = merged.output.trim();
    if (!merged.ok || baseSha.isEmpty) {
      throw ValidationLaneFailure(
        side: 'base',
        cause: 'could not resolve the merge base with $baseRef',
        exitCode: merged.exitCode,
        outputTail: merged.output,
      );
    }

    final planDigest = sha256.convert(utf8.encode(plan)).toString();
    final host = _hostIdentity ?? Platform.localHostname;
    final cacheFile = File(
      p.join(
        _cacheHome ?? workDir,
        '.grid',
        'critique-cache',
        'code-validation',
        baseSha,
        planDigest,
        '${sha256.convert(utf8.encode(host)).toString()}.json',
      ),
    );

    var cacheHit = true;
    var base = _readCache(
      cacheFile,
      baseSha: baseSha,
      planDigest: planDigest,
      host: host,
    );
    base ??= await _underCacheLock(cacheFile, () async {
      final second = _readCache(
        cacheFile,
        baseSha: baseSha,
        planDigest: planDigest,
        host: host,
      );
      if (second != null) return second;
      cacheHit = false;
      final fresh = await _runBase(
        git: git,
        shell: shell,
        workDir: workDir,
        baseSha: baseSha,
        plan: plan,
      );
      _publishCache(
        cacheFile,
        baseSha: baseSha,
        planDigest: planDigest,
        host: host,
        result: fresh,
      );
      return fresh;
    });

    final branch = await shell.run(
      workingDirectory: workDir,
      command: plan,
      deadline: deadline,
    );
    _writeAtomically(branchLogPath, branch.output);
    final branchFailures = failingTestNames(branch.output);
    if (branchFailures.isEmpty && (!branch.ok || branch.timedOut)) {
      throw ValidationLaneFailure(
        side: 'branch',
        cause: branch.timedOut
            ? 'the plan exceeded its ${deadline.inMinutes}-minute deadline'
            : 'the plan failed without naming a failing test',
        baseSha: baseSha,
        exitCode: branch.exitCode,
        timedOut: branch.timedOut,
        outputTail: _tail(branch.output),
        logPath: branchLogPath,
      );
    }

    final baseFailures = base.failures.toSet();
    final delta = ValidationDelta(
      baseSha: baseSha,
      baseCacheHit: cacheHit,
      branchExitCode: branch.exitCode,
      branchTimedOut: branch.timedOut,
      regressions:
          branchFailures.where((name) => !baseFailures.contains(name)).toList()
            ..sort(),
      preexisting: branchFailures.where(baseFailures.contains).toList()..sort(),
    );
    if (effectiveRcPath != null) {
      _writeAtomically(effectiveRcPath, '${delta.effectiveExitCode}\n');
    }
    return delta;
  }

  /// Runs [plan] at [baseSha] in a DETACHED scratch worktree, then removes it.
  ///
  /// The scratch checkout lives under a system-temporary parent that is deleted
  /// in a LOUD `finally`: a comparison that leaks a worktree would poison the
  /// repository's worktree list for every later round.
  Future<_BaseRun> _runBase({
    required GitRunner git,
    required ShellRunner shell,
    required String workDir,
    required String baseSha,
    required String plan,
  }) async {
    final parent = Directory.systemTemp.createTempSync('grid-validation-base-');
    final checkout = p.join(parent.path, 'base');
    try {
      final added = await git.run(
        workingDirectory: workDir,
        args: ['worktree', 'add', '--detach', checkout, baseSha],
      );
      if (!added.ok) {
        throw ValidationLaneFailure(
          side: 'worktree',
          cause: 'could not check the merge base out into a scratch worktree',
          baseSha: baseSha,
          exitCode: added.exitCode,
          outputTail: _tail(added.output),
        );
      }
      final result = await shell.run(
        workingDirectory: checkout,
        command: plan,
        deadline: deadline,
      );
      final removed = await git.run(
        workingDirectory: workDir,
        args: ['worktree', 'remove', '--force', checkout],
      );
      if (!removed.ok) {
        throw ValidationLaneFailure(
          side: 'worktree',
          cause: 'could not remove the scratch merge-base worktree',
          baseSha: baseSha,
          exitCode: removed.exitCode,
          outputTail: _tail(removed.output),
        );
      }
      final failures = failingTestNames(result.output);
      if (failures.isEmpty && (!result.ok || result.timedOut)) {
        throw ValidationLaneFailure(
          side: 'base',
          cause: result.timedOut
              ? 'the plan exceeded its ${deadline.inMinutes}-minute deadline'
              : 'the plan failed without naming a failing test',
          baseSha: baseSha,
          exitCode: result.exitCode,
          timedOut: result.timedOut,
          outputTail: _tail(result.output),
        );
      }
      return _BaseRun(exitCode: result.exitCode, failures: failures);
    } finally {
      try {
        if (parent.existsSync()) parent.deleteSync(recursive: true);
      } on Object catch (error) {
        throw ValidationLaneFailure(
          side: 'worktree',
          cause: 'could not clean up the scratch worktree parent: $error',
          baseSha: baseSha,
        );
      }
    }
  }

  /// Runs [body] holding an exclusive lock beside [cacheFile], so two rounds
  /// racing the same tuple run the base once.
  Future<_BaseRun> _underCacheLock(
    File cacheFile,
    Future<_BaseRun> Function() body,
  ) async {
    RandomAccessFile? opened;
    try {
      cacheFile.parent.createSync(recursive: true);
      opened = File('${cacheFile.path}.lock').openSync(mode: FileMode.write);
      await opened.lock(FileLock.blockingExclusive);
    } on Object {
      // A lock we cannot take degrades to an UNLOCKED run: a duplicated base
      // run costs time, where refusing the comparison would cost the round.
      try {
        await opened?.close();
      } on Object {
        // nothing to unwind
      }
      return body();
    }
    final handle = opened;
    try {
      return await body();
    } finally {
      try {
        await handle.unlock();
      } on Object {
        // the close below releases it anyway
      }
      await handle.close();
    }
  }

  /// The cached base result for this tuple, or null on ANY miss — absent,
  /// unreadable, malformed, a foreign schema version, or a key that does not
  /// match the tuple the file was looked up under.
  _BaseRun? _readCache(
    File cacheFile, {
    required String baseSha,
    required String planDigest,
    required String host,
  }) {
    try {
      if (!cacheFile.existsSync()) return null;
      final decoded = jsonDecode(cacheFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['schemaVersion'] != _cacheSchemaVersion) return null;
      if (decoded['baseSha'] != baseSha) return null;
      if (decoded['planDigest'] != planDigest) return null;
      if (decoded['host'] != host) return null;
      final failures = decoded['failures'];
      final exitCode = decoded['exitCode'];
      if (failures is! List || exitCode is! int) return null;
      if (failures.any((name) => name is! String)) return null;
      return _BaseRun(
        exitCode: exitCode,
        failures: failures.cast<String>().toList(growable: false),
      );
    } on Object {
      return null;
    }
  }

  /// Publishes [result] for this tuple through a temporary-file rename, so a
  /// reader can never observe a half-written entry.
  void _publishCache(
    File cacheFile, {
    required String baseSha,
    required String planDigest,
    required String host,
    required _BaseRun result,
  }) {
    try {
      cacheFile.parent.createSync(recursive: true);
      final staged = File('${cacheFile.path}.$pid.tmp')
        ..writeAsStringSync(
          jsonEncode({
            'schemaVersion': _cacheSchemaVersion,
            'baseSha': baseSha,
            'planDigest': planDigest,
            'host': host,
            'exitCode': result.exitCode,
            'failures': result.failures,
          }),
        );
      staged.renameSync(cacheFile.path);
    } on Object {
      // Best-effort: an unpublished entry costs the NEXT round one base run,
      // and the comparison in hand is already decided.
    }
  }
}

/// The named tests Dart's test runner reported as failing in [output].
///
/// Parses the runner's exact `Failing tests:` block: the heading line, then its
/// following INDENTED non-blank lines, each one test. Only the list indentation
/// (and a leading `-` marker) is removed; the name is otherwise verbatim,
/// trimmed. Names are deduplicated and sorted, so two runs of the same suite
/// compare as SETS and a re-ordered report is not a delta.
///
/// An [output] with no such block yields the EMPTY set — which, paired with a
/// zero exit, is the legitimate "everything passed" answer, and paired with a
/// non-zero exit is what makes a run UNCOMPARABLE (see [ValidationLaneFailure]).
List<String> failingTestNames(String output) {
  final names = <String>{};
  final lines = output.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() != 'Failing tests:') continue;
    for (var j = i + 1; j < lines.length; j++) {
      final line = lines[j];
      if (line.trim().isEmpty) break;
      // A non-indented line ENDS the block: the runner's summary line follows
      // it flush-left, and swallowing that would invent a test name.
      if (!line.startsWith(' ') && !line.startsWith('\t')) break;
      var name = line.trim();
      if (name.startsWith('- ')) name = name.substring(2).trim();
      if (name.isNotEmpty) names.add(name);
    }
  }
  return names.toList()..sort();
}

/// One base run's comparable outcome.
class _BaseRun {
  const _BaseRun({required this.exitCode, required this.failures});

  final int exitCode;
  final List<String> failures;
}

/// The last [max] characters of [output] — a bounded receipt for a lane
/// failure's message, where the FULL output is on disk.
String _tail(String output, {int max = 600}) {
  final trimmed = output.trimRight();
  return trimmed.length <= max
      ? trimmed
      : trimmed.substring(trimmed.length - max);
}

/// Writes [contents] to [path] through a temporary-file rename, creating the
/// parent directory — so a reader never observes a partial artifact.
void _writeAtomically(String path, String contents) {
  final target = File(path);
  target.parent.createSync(recursive: true);
  File('$path.$pid.tmp')
    ..writeAsStringSync(contents)
    ..renameSync(path);
}

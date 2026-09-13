// The shared `git` Fake for the SEAT suites — records every argv and answers
// from canned outcomes (Fakes, not mocks).
//
// Shared rather than copied because two suites now assert on the SAME argv
// stream: the succession verb's sink fork and the launcher's consumption both
// key on `git check-ignore`, and a second copy of this fake would let the two
// answers drift.
import 'package:grid_runtime/grid_runtime.dart' show GitRunResult, GitRunner;

/// A [GitRunner] that RECORDS every argv and answers from canned outcomes,
/// with an optional side effect fired on a chosen subcommand — how the
/// commit-window race is staged deterministically.
class RecordingGitRunner implements GitRunner {
  /// Creates the fake.
  RecordingGitRunner({
    this.fail = const <String>{},
    this.duringCommit,
    this.statusOutput = '',
    this.statusStderr = '',
    this.ignored = false,
    this.checkIgnoreExitCode,
  });

  /// The first argv token of every call that must answer NOT ok.
  final Set<String> fail;

  /// Fired immediately before `git commit` answers — the commit window.
  final void Function()? duringCommit;

  /// What `git status --porcelain` reports (empty ⇒ a clean tree).
  final String statusOutput;

  /// What `git status --porcelain` writes on stderr (non-empty ⇒ a degraded
  /// scan, which `GitOps.hasUncommittedWork` fails closed on).
  final String statusStderr;

  /// Whether `git check-ignore` reports the probed path as IGNORED — the fork
  /// that selects the LOCAL archive sink. Exit 0 ignored, exit 1 not.
  final bool ignored;

  /// An explicit `git check-ignore` exit code, for the third answer: neither 0
  /// nor 1 (no repository here, a bad pathspec) means "couldn't tell".
  final int? checkIgnoreExitCode;

  /// Every argv, in call order.
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    if (args.first == 'commit') duringCommit?.call();
    if (fail.contains(args.first)) {
      return GitRunResult(exitCode: 1, output: 'refused: ${args.join(' ')}');
    }
    return switch (args.first) {
      'check-ignore' => GitRunResult(
        exitCode: checkIgnoreExitCode ?? (ignored ? 0 : 1),
        output: '',
      ),
      'rev-parse' => GitRunResult(exitCode: 0, output: '$workingDirectory\n\n'),
      'status' => GitRunResult(
        exitCode: 0,
        output: statusOutput,
        stderr: statusStderr,
      ),
      _ => const GitRunResult(exitCode: 0, output: ''),
    };
  }
}

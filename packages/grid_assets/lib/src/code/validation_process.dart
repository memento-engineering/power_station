/// The bounded Validation Plan's LAUNCHER — the small executable
/// [SystemShellRunner] starts in place of the plan's shell, so the plan runs
/// inside a process group this launcher LEADS and a deadline can terminate
/// that whole group with one signal.
///
/// **Why not shell job control.** A `set -m` wrapper also yields a group, but
/// dash (CI's `sh`) with no controlling terminal answers it with `can't access
/// tty; job control turned off` on stderr — a line that corrupts the plan's
/// captured output, which the lane logs verbatim and parses for failing tests.
/// A `setsid()` here needs no terminal and prints nothing.
///
/// **Why an ATTACHED child.** `ProcessStartMode.detachedWithStdio` would also
/// start the plan in a new group, but Dart exposes no exit code for a detached
/// process — and the plan's exit code is the lane's contract. This launcher
/// instead leads the group ITSELF, then starts the plan as an ordinary child
/// that inherits both the group and this process's stdio, and awaits it.
///
/// The plan rides as an argv element, never spliced into a script, so a plan
/// that fails to PARSE is the shell's ordinary non-zero exit.
library;

import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show establishStationProcessGroup;

/// Runs `<shell> -c <plan>` as a member of a fresh process group led by this
/// process, and exits with the plan's exit code.
///
/// [arguments] is exactly `[shell, plan]`; any other arity is refused with
/// exit 64 (`EX_USAGE`). Failing to lead a process group or to start the
/// shell exits 70 (`EX_SOFTWARE`). Every refusal is loud on stderr under the
/// `grid-validation:` prefix. A plan killed by signal N exits 128 + N — the
/// shell's own convention, since a signal is not an exit code.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    await _refuse(
      64,
      'usage: validation_process <shell> <plan> '
      '(got ${arguments.length} arguments)',
    );
  }
  final [shell, plan] = arguments;

  // The group comes FIRST: a child started before it would sit in the
  // station's own group, out of reach of the deadline's group signal.
  try {
    await establishStationProcessGroup(stationPid: pid);
  } on Object catch (error) {
    await _refuse(70, 'could not lead a process group: $error');
  }

  final Process child;
  try {
    child = await Process.start(
      shell,
      ['-c', plan],
      runInShell: false,
      mode: ProcessStartMode.inheritStdio,
    );
  } on Object catch (error) {
    await _refuse(70, 'could not start $shell: $error');
  }

  final code = await child.exitCode;
  exit(code < 0 ? 128 - code : code);
}

/// Reports [message] on stderr and exits with [code], after the report has
/// reached the pipe.
Future<Never> _refuse(int code, String message) async {
  stderr.writeln('grid-validation: $message');
  await stderr.flush();
  exit(code);
}

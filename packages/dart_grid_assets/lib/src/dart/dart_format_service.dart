/// The DART-domain FORMAT probe — a reusable, UI-drivable service that answers
/// "would `dart format` change these files?" WITHOUT changing them.
///
/// The Dart-specific formatter command belongs with the DART domain (this pack
/// vends the `dart` verbs); a consumer composes it by id and asks only the
/// deterministic question. It never requests formatter OUTPUT
/// (`--output=none`), so it can never rewrite a worktree it is only inspecting.
///
/// One process PER FILE (`--set-exit-if-changed`): the exit code alone
/// identifies the exact dirty paths, so no caller ever has to parse formatter
/// prose to learn WHICH file is unformatted.
library;

import 'dart:io';

import 'release_service.dart' show ProcessRunner;

/// The deterministic result of checking Dart source formatting — the closed
/// vocabulary a caller consumes with an exhaustive `switch`.
sealed class DartFormatOutcome {
  /// Const base constructor.
  const DartFormatOutcome();
}

/// Every checked file is already formatted.
final class DartFormatClean extends DartFormatOutcome {
  /// Wraps the sorted, unique [files] that were checked (possibly empty).
  const DartFormatClean(this.files);

  /// Every file the probe checked, sorted and deduplicated.
  final List<String> files;
}

/// The formatter would change [files] — an UNFORMATTED diff.
final class DartFormatDirty extends DartFormatOutcome {
  /// Wraps the sorted [files] the formatter would rewrite.
  const DartFormatDirty(this.files);

  /// The files `dart format` would change, in checked order.
  final List<String> files;
}

/// The formatter could not decide cleanliness for [file] — an OPERATIONAL
/// failure (a `dart` that would not launch, a syntax error, a vanished path),
/// never a verdict about formatting.
final class DartFormatProbeFailed extends DartFormatOutcome {
  /// Wraps the [file] whose probe failed, its [exitCode] (null ⇒ the process
  /// never ran), and the captured [output].
  const DartFormatProbeFailed({
    required this.file,
    required this.exitCode,
    required this.output,
  });

  /// The file whose probe failed.
  final String file;

  /// The formatter's exit code, or null when the process never launched.
  final int? exitCode;

  /// The formatter's combined stdout/stderr (empty when it never launched).
  final String output;
}

/// Checks Dart formatting without changing source files.
class DartFormatService {
  /// Creates the probe, optionally over an injected [runProcess] seam (tests
  /// inject a recording Fake — Fakes, not mocks); absent ⇒ the real
  /// [Process.run].
  const DartFormatService({ProcessRunner? runProcess})
    : _runProcess = runProcess;

  final ProcessRunner? _runProcess;

  /// Runs `dart format --output=none --set-exit-if-changed <file>` in
  /// [workspaceDir] once per sorted, unique entry of [files].
  ///
  /// Exit 0 ⇒ that file is clean; exit 1 ⇒ the formatter would change it (it is
  /// accumulated and the sweep continues, so ONE call names EVERY dirty file);
  /// anything else — or a process that would not launch — short-circuits to
  /// [DartFormatProbeFailed], because an undecidable probe must never be read
  /// as a clean bill. An empty [files] spawns no process and is [DartFormatClean].
  Future<DartFormatOutcome> check({
    required String workspaceDir,
    required Iterable<String> files,
  }) async {
    final ordered = files.toSet().toList()..sort();
    final dirty = <String>[];
    final runProcess = _runProcess ?? Process.run;
    for (final file in ordered) {
      final ProcessResult result;
      try {
        result = await runProcess('dart', [
          'format',
          '--output=none',
          '--set-exit-if-changed',
          file,
        ], workingDirectory: workspaceDir);
      } on Object catch (error) {
        return DartFormatProbeFailed(
          file: file,
          exitCode: null,
          output: '$error',
        );
      }
      if (result.exitCode == 0) continue;
      if (result.exitCode == 1) {
        dirty.add(file);
        continue;
      }
      return DartFormatProbeFailed(
        file: file,
        exitCode: result.exitCode,
        output: '${result.stdout}${result.stderr}',
      );
    }
    return dirty.isEmpty ? DartFormatClean(ordered) : DartFormatDirty(dirty);
  }
}

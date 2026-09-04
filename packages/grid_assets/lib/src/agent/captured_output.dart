/// The CAPTURED-PROCESS-OUTPUT mechanism — tail-first, advice-stripped,
/// exit-code-led (`power_station#captured-process-output-escalates-tail-first`).
///
/// A small shared leaf on purpose: the landing circuit (in the grid process),
/// the code committee's gating lane, and the ACP bridge (a standalone child
/// script) all assemble failure reasons this way, and none of them may pay for
/// another's dependency graph to do it. Its sole import is `dart:io`, for the
/// shared full-log writer/reader the two validation lanes share.
library;

import 'dart:io';

/// The TAIL of captured process output — what a failure reason stamps so an
/// operator sees WHY without forensics. The useful line is at the END (a tool
/// prints progress first, the fatal message last) and the engine truncates a
/// `failureReason` to its FIRST `kMaxReasonChars`; taking the tail keeps the
/// diagnosis, not the noise. A leading `…` marks a cut.
String landReasonTail(String output, [int max = 400]) {
  final trimmed = output.trim();
  return trimmed.length <= max
      ? trimmed
      : '…${trimmed.substring(trimmed.length - max)}';
}

/// The tail budget for a captured harness/tool log a failure reason carries
/// (bead `pow-gy41`). Wide enough to hold a whole `dart test` failure block —
/// the failing test's name, its expected/actual, and the `Some tests failed.`
/// trailer — and well inside the gate bead's metadata budget.
const int kRevalidateReasonTailChars = 1500;

/// The character budget the leading VALIDATION DIAGNOSTICS may take out of
/// [kRevalidateReasonTailChars]. Wide enough for the two-line
/// `Failed to load` + `file:line:col: Error: <symbol>` pair the Dart front end
/// prints, narrow enough that the exit-class and log-path line still lands
/// inside the engine's 500-char persisted prefix.
const int kValidationDiagnosticHeadChars = 320;

/// Every recognized validation diagnostic line in [output], deduplicated in
/// encounter order — the Dart front end repeats the SAME `Error:` once per test
/// file it failed to load, so an undeduplicated lead would spend the whole
/// budget on one cause.
///
/// The front end carries `Error:` or `Failed to load`; the analyzer and the
/// other line-oriented validation tools carry `[E]`. Every other output shape
/// is served by the retained tail, which is where its fatal line lives.
List<String> validationDiagnosticLines(String output) {
  final diagnostics = <String>{};
  for (final line in output.split('\n')) {
    final diagnostic = line.trim();
    if (diagnostic.contains('Error:') ||
        diagnostic.contains('Failed to load') ||
        diagnostic.contains('[E]')) {
      diagnostics.add(diagnostic);
    }
  }
  return diagnostics.toList(growable: false);
}

/// [diagnostics] joined and cut to [max], marked with a trailing … when cut —
/// the unabridged lines stay in the log on disk.
String boundedValidationDiagnosticHead(
  List<String> diagnostics, [
  int max = kValidationDiagnosticHeadChars,
]) {
  final joined = diagnostics.join('\n');
  if (joined.length <= max) return joined;
  return '${joined.substring(0, max - 1)}…';
}

/// Writes [output] unchanged to [path], creating its parent directories.
///
/// LOUD by design: a failure to persist throws rather than letting a caller
/// hand an operator a reason that names a full log which does not exist.
void writeCapturedOutputLog({required String path, required String output}) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(output);
}

/// The full captured-output log at [path], or `''` when it is not readable.
///
/// Tolerant on purpose, and it is the READER that is tolerant rather than the
/// writer: these logs live in the round-swept `.grid/critique/`, which the
/// committee's round-start sweep can empty while a lane is still in flight (the
/// tg-60t derived-wave race). A missing log must therefore degrade to
/// `<no output captured>` inside the failure reason — which still names the
/// exit class and the log path — and must NEVER throw out of a result hook,
/// because that would turn a diagnosable gate failure back into the opaque
/// hold this whole mechanism exists to prevent.
String readCapturedOutputLogOrEmpty(String path) {
  try {
    return File(path).readAsStringSync();
  } on Object {
    return '';
  }
}

/// One `dart pub get` line of pure UPGRADE ADVICE — `analyzer 10.2.0 (14.3.0
/// available)`. Anchored at both ends: a line that merely MENTIONS an
/// available version mid-sentence is not advice and survives.
final RegExp _pubVersionAdvice = RegExp(
  r'^\s*[a-z_][a-z0-9_]*\s+\S+\s+\(\S+\s+available\)\s*$',
);

/// The two trailers pub prints after that block — the `N packages have newer
/// versions incompatible with dependency constraints.` count and the
/// ``Try `dart pub outdated` for more information.`` nudge.
final RegExp _pubOutdatedSummary = RegExp(
  r'^\s*(\d+\s+packages?\s+(have|has)\s+newer\s+versions\s+incompatible\s+'
  r'with\s+dependency\s+constraints\.'
  r'|Try\s+`(dart|flutter)\s+pub\s+outdated`.*)\s*$',
);

/// [output] with pub's upgrade-ADVICE lines dropped (bead `pow-gy41`).
///
/// A Dart Validation Plan opens with `dart pub get`, and on a seat with an
/// outdated lockfile its advisory block runs past 2000 characters on its own —
/// burying the fatal line, which comes LAST. This is never the failure, so it
/// is never the diagnosis.
///
/// Pure and line-wise: every line that is not advice is returned
/// BYTE-IDENTICAL, in order; advice-free input is returned unchanged. Applied
/// BEFORE [landReasonTail] so the tail budget is spent on signal.
String planOutputWithoutPubAdvice(String output) => output
    .split('\n')
    .where(
      (line) =>
          !_pubVersionAdvice.hasMatch(line) &&
          !_pubOutdatedSummary.hasMatch(line),
    )
    .join('\n');

/// One failure reason in the station's captured-output SHAPE:
/// `'<verb> failed (exit N) [<adapter>]: <diagnostic — ><tail>'`.
///
/// The exit code LEADS because an operator reads the CLASS of failure before
/// the log; the BRACKET holds the [adapter] and nothing else, because it names
/// WHICH transport produced the failure (the claude argv path and the ACP
/// channel path fail differently and an operator must not have to guess which
/// one ran); the optional [diagnostic] is the short cause and opens the
/// message, ahead of the log it explains. The tail is [landReasonTail] over
/// [output] at [max] — never a head slice.
///
/// A null [exitCode] renders `exit unknown` rather than inventing a 0: a
/// protocol failure with no reaped child is honest about not knowing. Empty
/// captured output renders `<no output captured>`, which is itself the
/// diagnosis (bead `pow-39tl`: four codex specify runs left nothing anywhere).
String capturedOutputReason({
  required String verb,
  required String adapter,
  required String output,
  int? exitCode,
  String? diagnostic,
  int max = kRevalidateReasonTailChars,
}) {
  final code = exitCode == null ? 'exit unknown' : 'exit $exitCode';
  final tail = landReasonTail(output, max);
  final log = tail.isEmpty ? '<no output captured>' : tail;
  final cause = diagnostic == null ? '' : '$diagnostic — ';
  return '$verb failed ($code) [$adapter]: $cause$log';
}

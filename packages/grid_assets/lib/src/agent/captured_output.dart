/// The CAPTURED-PROCESS-OUTPUT mechanism — tail-first, advice-stripped,
/// exit-code-led (`power_station#captured-process-output-escalates-tail-first`).
///
/// A zero-import leaf on purpose: both the landing circuit (in the grid
/// process) and the ACP bridge (a standalone child script) assemble failure
/// reasons this way, and the bridge must not pay for `landing.dart`'s
/// dependency graph to do it.
library;

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

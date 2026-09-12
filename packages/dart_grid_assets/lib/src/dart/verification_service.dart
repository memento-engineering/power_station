/// The DART-domain VERIFICATION service — a reusable, UI-drivable service that
/// runs one `dart` verification command and bounds its output ASYMMETRICALLY:
/// a GREEN run answers in one fixed-schema JSON line, a RED run keeps the whole
/// transcript.
///
/// The asymmetry is the whole point. On a failing run the transcript IS the
/// answer — the failing test name, the expectation, the stack — so nothing is
/// withheld. On a passing run almost none of it is read: `dart analyze` green
/// is `No issues found!` and `dart format` green is `Formatted 761 files (0
/// changed)`, yet a caller pays the full dump to learn it. This service makes
/// the green side cost one bounded line that names what it withheld and how to
/// ask for it.
///
/// Result CACHING is deliberately absent: every call spawns. A cached green can
/// mask a live red — flaky lanes, environment-dependent tests and ordering
/// effects all make "the tree looks unchanged" the wrong key — which is why the
/// org's bounded-output entry left slow-command caching unruled.
///
/// THIN-by-rule layering (the CLI-SDK redline): all logic lives HERE (a Flutter
/// UI could drive the same service); the Commands only parse argv and render.
/// The one IO edge rides the injected [ProcessRunner] seam, so the whole
/// surface tests offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'release_service.dart' show ProcessRunner;

/// The hard cap on a GREEN verification summary, in characters.
///
/// A summary that cannot be encoded under this cap is replaced WHOLE by a
/// fixed under-cap warning rather than truncated: a silently clipped JSON line
/// is unparseable, and a confident partial answer is worse than none.
const int kMaxGreenVerificationOutputChars = 512;

/// The `dart` verifications this service bounds — the four measured as the
/// largest green-transcript spend in the agent pool.
enum DartVerificationKind {
  /// `dart test` — always run through the machine (JSON) reporter.
  test,

  /// `dart analyze`.
  analyze,

  /// `dart format`.
  format,

  /// `dart pub get`.
  pub;

  /// The argv this kind spawns, before any caller-forwarded arguments.
  List<String> get argv => switch (this) {
    DartVerificationKind.test => const ['test', '--reporter=json'],
    DartVerificationKind.analyze => const ['analyze'],
    DartVerificationKind.format => const ['format'],
    DartVerificationKind.pub => const ['pub', 'get'],
  };
}

/// One verification run: the child's exact exit code and raw channels, plus —
/// on GREEN only — the bounded [greenSummary] a caller renders instead of the
/// transcript.
@immutable
class DartVerificationReport {
  /// Wraps one completed run.
  const DartVerificationReport({
    required this.kind,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.greenSummary,
  });

  /// The verification that ran.
  final DartVerificationKind kind;

  /// The child's exit code, passed through unchanged.
  final int exitCode;

  /// The child's raw stdout, retained in full whatever the verdict.
  final String stdout;

  /// The child's raw stderr, retained in full whatever the verdict.
  final String stderr;

  /// The bounded green summary — non-null EXACTLY when [exitCode] is 0, and
  /// never longer than [kMaxGreenVerificationOutputChars] once encoded.
  final Map<String, Object?>? greenSummary;

  /// Whether the child exited 0.
  bool get isGreen => exitCode == 0;
}

/// The verdict every green summary carries.
const String _kGreenVerdict = 'green';

/// What a green summary withheld — the field that makes the cap non-silent.
const String _kWithheld = 'full transcript';

/// How to get the withheld transcript back.
const String _kShow = 'rerun this command with --full';

/// The fixed warning a green `dart test` carries when its reporter stream could
/// not be read as the machine protocol.
const String _kTestSummaryWarning =
    'the JSON reporter stream was unreadable; counts unavailable';

/// The fixed warning a green `dart format` carries when the formatter printed
/// no `Formatted N files (M changed)` line.
const String _kFormatSummaryWarning =
    'the formatter printed no summary line; changed count unavailable';

/// The fixed warning that REPLACES a green summary too large to encode under
/// [kMaxGreenVerificationOutputChars].
const String _kOversizeSummaryWarning =
    'the summary exceeded the output cap and was replaced';

/// The formatter's summary line — `Formatted 761 files (0 changed) in 1.2s`
/// (the count is singular for one file).
final RegExp _formattedLine = RegExp(r'Formatted \d+ files? \((\d+) changed\)');

/// Runs one `dart` verification and bounds its GREEN output.
class DartVerificationService {
  /// Creates the service, optionally over an injected [runProcess] seam (tests
  /// inject a recording Fake — Fakes, not mocks); absent ⇒ the real
  /// [Process.run].
  const DartVerificationService({ProcessRunner? runProcess})
    : _runProcess = runProcess;

  final ProcessRunner? _runProcess;

  /// Runs [kind] in [workspaceDir] with [arguments] forwarded after the kind's
  /// own argv, and yields the run's [DartVerificationReport].
  ///
  /// Spawns EXACTLY ONCE per call — there is no cache and no prior-result
  /// lookup, so a repeated call re-measures the tree. A non-zero exit yields a
  /// null summary and both raw channels in full; exit 0 yields the bounded
  /// fixed-schema summary.
  ///
  /// Throws an [ArgumentError] — before spawning — when [arguments] would
  /// displace the test reporter: `dart test` answers through the machine
  /// protocol or not at all.
  Future<DartVerificationReport> run({
    required DartVerificationKind kind,
    required String workspaceDir,
    List<String> arguments = const [],
  }) async {
    if (kind == DartVerificationKind.test) _refuseReporterOverride(arguments);
    final argv = [...kind.argv, ...arguments];
    final runProcess = _runProcess ?? Process.run;
    final result = await runProcess(
      'dart',
      argv,
      workingDirectory: workspaceDir,
    );
    final out = '${result.stdout}';
    final err = '${result.stderr}';
    return DartVerificationReport(
      kind: kind,
      exitCode: result.exitCode,
      stdout: out,
      stderr: err,
      greenSummary: result.exitCode == 0
          ? _greenSummary(kind: kind, argv: argv, stdout: out)
          : null,
    );
  }

  /// Refuses a forwarded `-r`/`--reporter` LOUDLY: the green `dart test`
  /// summary is derived from reporter EVENTS, so a caller-chosen reporter would
  /// silently turn every count into a guess.
  void _refuseReporterOverride(List<String> arguments) {
    for (final argument in arguments) {
      final isOverride =
          argument == '-r' ||
          argument == '--reporter' ||
          argument.startsWith('--reporter=') ||
          (argument.startsWith('-r') && argument.length > 2);
      if (isOverride) {
        throw ArgumentError.value(
          argument,
          'arguments',
          'the test reporter is the machine protocol this summary is derived '
              'from and cannot be overridden',
        );
      }
    }
  }

  /// Builds the bounded green summary for [kind]: the fixed fields every kind
  /// carries plus that kind's own counts, capped WHOLE.
  Map<String, Object?> _greenSummary({
    required DartVerificationKind kind,
    required List<String> argv,
    required String stdout,
  }) {
    final summary = <String, Object?>{
      'command': 'dart ${argv.join(' ')}',
      'verdict': _kGreenVerdict,
      'exitCode': 0,
      ...switch (kind) {
        DartVerificationKind.test => _testFields(stdout),
        DartVerificationKind.analyze => const {'issues': 0},
        DartVerificationKind.format => _formatFields(stdout),
        DartVerificationKind.pub => const {'resolution': 'succeeded'},
      },
      'withheld': _kWithheld,
      'show': _kShow,
    };
    if (jsonEncode(summary).length <= kMaxGreenVerificationOutputChars) {
      return summary;
    }
    return {
      'command': 'dart ${kind.argv.join(' ')}',
      'verdict': _kGreenVerdict,
      'exitCode': 0,
      'summaryWarning': _kOversizeSummaryWarning,
      'withheld': _kWithheld,
      'show': _kShow,
    };
  }

  /// The `dart test` counts, read from the JSON reporter events and NEVER from
  /// human reporter prose: non-hidden `testDone` events split into skipped and
  /// successful, and the `done` event's `time` as elapsed milliseconds.
  ///
  /// A stream carrying no decodable event, or no `done` event, yields nulls for
  /// what it could not answer plus the fixed [_kTestSummaryWarning] — an
  /// unreadable stream is never reported as zero tests.
  Map<String, Object?> _testFields(String stdout) {
    final events = <Map<String, Object?>>[];
    for (final line in const LineSplitter().convert(stdout)) {
      if (line.trim().isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue; // Prose on the machine channel is noise, never a count.
      }
      if (decoded is Map<String, Object?>) events.add(decoded);
    }
    if (events.isEmpty) {
      return {
        'passed': null,
        'skipped': null,
        'elapsedMilliseconds': null,
        'summaryWarning': _kTestSummaryWarning,
      };
    }
    var passed = 0;
    var skipped = 0;
    int? elapsed;
    for (final event in events) {
      switch (event['type']) {
        case 'testDone' when event['hidden'] != true:
          if (event['skipped'] == true) {
            skipped++;
          } else if (event['result'] == 'success') {
            passed++;
          }
        case 'done':
          elapsed = event['time'] is int ? event['time'] as int : null;
      }
    }
    return {
      'passed': passed,
      'skipped': skipped,
      'elapsedMilliseconds': elapsed,
      if (elapsed == null) 'summaryWarning': _kTestSummaryWarning,
    };
  }

  /// The `dart format` changed-file count, read from the LAST `Formatted N
  /// files (M changed)` line; a transcript without one yields a null count plus
  /// the fixed [_kFormatSummaryWarning].
  Map<String, Object?> _formatFields(String stdout) {
    final matches = _formattedLine.allMatches(stdout);
    if (matches.isEmpty) {
      return {'changedFiles': null, 'summaryWarning': _kFormatSummaryWarning};
    }
    return {'changedFiles': int.parse(matches.last.group(1)!)};
  }
}

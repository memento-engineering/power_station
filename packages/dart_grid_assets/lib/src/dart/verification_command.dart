/// The DART domain's exported VERIFICATION Commands — `dart verify <kind>`,
/// the bounded-output front for `dart test`, `dart analyze`, `dart format` and
/// `dart pub get`.
///
/// One rule, applied asymmetrically: a GREEN run prints ONE structured JSON
/// line naming what it withheld and how to replay it; a RED run prints the
/// child's stdout and stderr byte-for-byte, uncapped, because the failure
/// payload is the answer. `--full` opts back into the whole transcript on a
/// green run, and the child's exit code always passes through unchanged so
/// these Commands drop into a gate where the bare `dart` verb stood.
///
/// THIN by rule (the CLI-SDK redline): every decision lives in
/// [DartVerificationService] (a Flutter UI could drive the same service); these
/// Commands only parse argv and render.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'verification_service.dart';

/// `dart verify` — the verification group (subcommands carry the kinds).
class DartVerifyCommand extends Command<int> {
  /// Creates the group over [service] (injectable for tests). [out]/[err]
  /// default to the real stdout/stderr; tests capture them.
  DartVerifyCommand({
    DartVerificationService service = const DartVerificationService(),
    StringSink? out,
    StringSink? err,
  }) {
    final o = out ?? stdout;
    final e = err ?? stderr;
    for (final kind in DartVerificationKind.values) {
      addSubcommand(_VerifyLeaf(kind: kind, service: service, out: o, err: e));
    }
  }

  @override
  final String name = 'verify';

  @override
  final String description =
      'Run a dart verification with an asymmetric output contract: one bounded '
      'JSON summary when it passes, the whole uncapped transcript when it '
      'fails. The child exit code passes through unchanged.';
}

/// One verification leaf (`dart verify test|analyze|format|pub`) — parses
/// `--dir`/`--full`, forwards everything after `--` to the service, and renders
/// either the bounded green summary or the raw transcript.
class _VerifyLeaf extends Command<int> {
  _VerifyLeaf({
    required DartVerificationKind kind,
    required DartVerificationService service,
    required StringSink out,
    required StringSink err,
  }) : _kind = kind,
       _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption(
        'dir',
        help:
            'The directory to run the verification in. Defaults to the '
            'current directory.',
      )
      ..addFlag(
        'full',
        negatable: false,
        help:
            'Print the whole child transcript even when it passes (the green '
            'run is bounded to one JSON summary by default).',
      );
  }

  final DartVerificationKind _kind;
  final DartVerificationService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  String get name => _kind.name;

  @override
  String get description =>
      'Run `dart ${_kind.argv.join(' ')}`: one bounded JSON summary when it '
      'passes, the whole uncapped transcript when it fails. Arguments after '
      '`--` are forwarded to the child.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final DartVerificationReport report;
    try {
      report = await _service.run(
        kind: _kind,
        workspaceDir: args.option('dir') ?? Directory.current.path,
        arguments: args.rest,
      );
    } on ArgumentError catch (error) {
      _err.writeln('dart verify $name: ${error.message}');
      return 64;
    }

    final summary = report.greenSummary;
    if (summary != null && !args.flag('full')) {
      _out.writeln(jsonEncode(summary));
      return report.exitCode;
    }
    _out.write(report.stdout);
    _err.write(report.stderr);
    return report.exitCode;
  }
}

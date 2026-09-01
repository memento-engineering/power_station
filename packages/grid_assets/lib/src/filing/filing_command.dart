import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'filing_contract.dart';

String _currentDirectory() => Directory.current.path;

/// `filing <bead-id>` — deterministic enforcement of front-door completeness.
class FilingCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  FilingCommand({
    FilingService service = const FilingService(),
    String Function() storeRoot = _currentDirectory,
    StringSink? out,
    StringSink? err,
  }) : _service = service,
       _storeRoot = storeRoot,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit {id, passed, requirements, error?} as one JSON object.',
    );
  }

  final FilingService _service;
  final String Function() _storeRoot;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'filing';

  @override
  final String description =
      'Check one bead against the four mechanical filing requirements.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    return executable == null
        ? 'filing [--json] <bead-id>'
        : '$executable filing [--json] <bead-id>';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln('filing: exactly one bead id is required — $invocation');
      return 64;
    }
    final beadId = rest.single.trim();
    final FilingReport report;
    try {
      report = await _service.check(
        storeRoot: p.normalize(_storeRoot()),
        beadId: beadId,
      );
    } on Object catch (error) {
      _err.writeln('filing: failed to read $beadId: $error');
      return 1;
    }
    if (argResults!.flag('json')) {
      _out.writeln(jsonEncode(report.toJson()));
    } else if (report.error case final error?) {
      _out.writeln('FAIL filing: $error');
    } else {
      for (final row in report.requirements) {
        _out.writeln(
          '${row.passed ? 'PASS' : 'FAIL'} '
          '${row.requirement.wire}: ${row.detail}',
        );
      }
    }
    return report.passed ? 0 : 1;
  }
}

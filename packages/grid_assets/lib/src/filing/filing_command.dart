import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'filing_contract.dart';

String _currentDirectory() => Directory.current.path;

/// The default roster seam: NONE. Until a station threads its coded roster in,
/// an `external:<project>:<capability>` dependency row cannot be resolved to an
/// armed substation, and the dependencies row refuses fail-closed saying so.
Set<String>? noArmedSubstations() => null;

/// `filing <bead-id>` — deterministic enforcement of front-door completeness.
class FilingCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  ///
  /// [armedSubstations] is the station-injected roster by NAME — the SAME
  /// injected default the `approve` verb takes, so the two verbs answer one
  /// contract one way. It is what an `external:<project>:<capability>` row's
  /// project resolves against, and its default refuses fail-closed
  /// ([noArmedSubstations]).
  ///
  /// This verb takes NO `--state-root`. The option existed for ONE reader —
  /// the grid state store's cross-store link beads — and the dependencies row
  /// is now a projection of the WORK store's own bd rows, so there is no
  /// second store to name. `park` and `show` keep it; they reach the state
  /// store's session-lifecycle beads.
  FilingCommand({
    FilingService service = const FilingService(),
    String Function() storeRoot = _currentDirectory,
    Set<String>? Function() armedSubstations = noArmedSubstations,
    StringSink? out,
    StringSink? err,
  }) : _service = service,
       _storeRoot = storeRoot,
       _armedSubstations = armedSubstations,
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
  final Set<String>? Function() _armedSubstations;
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
    const shape = 'filing [--json] <bead-id>';
    return executable == null ? shape : '$executable $shape';
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
        armedSubstations: _armedSubstations(),
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

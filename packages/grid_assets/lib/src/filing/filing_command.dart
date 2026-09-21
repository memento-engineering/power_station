import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdRunner, ProcessBdRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../code/discovery.dart' show commandDecisionIndexSource;
import '../code/landing.dart' show ShellRunner, SystemShellRunner;
import '../search/station_search.dart';
import 'filing_contract.dart';

String _currentDirectory() => Directory.current.path;
BdRunner _processBdRunnerFor(String storeRoot) =>
    ProcessBdRunner(workspaceRoot: storeRoot);

/// The DEFAULT filing service: the exact read, plus the LIVE viability
/// evidence the six content rows are judged against.
///
/// It binds the real syntax probes ([SystemValidationPlanProbe] against the
/// lane shell and dash), a COMPLETE current-plus-attached all-status id
/// catalog ([BdListAllStatusBeadSource] — one scoped list read per core issue
/// type, never `bd export`), and the station's roster-mode decision index
/// ([commandDecisionIndexSource]). Each leg is asked only when the bead
/// carries a token that needs it, and a leg that cannot answer is recorded
/// UNAVAILABLE — never as an empty catalog. The scoped read is the ratified
/// per-store mechanism, recorded as
/// `power_station#the-per-store-bead-read-is-scoped-never-the-export-surface`.
///
/// A test or an alternate station overrides the whole thing by injecting its
/// own `FilingService`, or just the gather by injecting a
/// [FilingEvidenceSource].
FilingService defaultFilingService({
  required BdRunner Function(String storeRoot) runnerFor,
  sdk.SubstationScope? owningScope,
  List<sdk.SubstationScope> attachedScopes = const [],
  ValidationPlanProbe validationPlanProbe = const SystemValidationPlanProbe(),
  ShellRunner decisionShell = const SystemShellRunner(),
  String? decisionInvocation,
  String? decisionGridHome,
  FilingEvidenceSource? evidence,
}) => FilingService(
  source: ExactSubstationBeadSource(runnerFor: runnerFor),
  evidence:
      evidence ??
      SystemFilingEvidenceSource(
        probe: validationPlanProbe,
        catalog: BdListAllStatusBeadSource(runnerFor: runnerFor),
        owning: owningScope,
        attached: attachedScopes,
        decisions: commandDecisionIndexSource(
          decisionShell,
          runnerInvocation: decisionInvocation,
          gridHome: decisionGridHome,
        ),
      ),
);

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
    FilingService? service,
    String Function() storeRoot = _currentDirectory,
    Set<String>? Function() armedSubstations = noArmedSubstations,
    BdRunner Function(String storeRoot) runnerFor = _processBdRunnerFor,
    sdk.SubstationScope? owningScope,
    List<sdk.SubstationScope> attachedScopes = const [],
    ValidationPlanProbe validationPlanProbe = const SystemValidationPlanProbe(),
    ShellRunner decisionShell = const SystemShellRunner(),
    String? decisionInvocation,
    String? decisionGridHome,
    FilingEvidenceSource? evidence,
    StringSink? out,
    StringSink? err,
  }) : _service =
           service ??
           defaultFilingService(
             runnerFor: runnerFor,
             owningScope: owningScope,
             attachedScopes: attachedScopes,
             validationPlanProbe: validationPlanProbe,
             decisionShell: decisionShell,
             decisionInvocation: decisionInvocation,
             decisionGridHome: decisionGridHome,
             evidence: evidence,
           ),
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
      'Check one bead against the eleven mechanical filing requirements.';

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

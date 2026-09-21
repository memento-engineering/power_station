import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart' show ArgParser, ArgResults;
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdRunner, ProcessBdRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../code/discovery.dart'
    show DecisionIndexSource, commandDecisionIndexSource;
import '../code/landing.dart' show ShellRunner, SystemShellRunner;
import '../assets/overlay_materializer.dart' show kDefaultOverlayRunner;
import '../code/pr_describe.dart' show InferenceRunner;
import '../search/station_search.dart';
import 'filing_contract.dart';
import 'pre_stamp_advisory.dart';

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
/// It also composes the PRE-STAMP ADVISORY over that SAME decision index. One
/// `DecisionIndexSource` is built here and handed to both halves, so the
/// mechanical `decision_references` row and the discovery lens the advisory
/// runs ask the register one way — two index compositions in one verb would be
/// two answers about the same citation.
///
/// A test or an alternate station overrides the whole thing by injecting its
/// own `FilingService`, or just one collaborator by injecting a
/// [FilingEvidenceSource] or a [FilingAdvisory].
FilingService defaultFilingService({
  required BdRunner Function(String storeRoot) runnerFor,
  sdk.SubstationScope? owningScope,
  List<sdk.SubstationScope> attachedScopes = const [],
  ValidationPlanProbe validationPlanProbe = const SystemValidationPlanProbe(),
  ShellRunner decisionShell = const SystemShellRunner(),
  String? decisionInvocation,
  String? decisionGridHome,
  FilingEvidenceSource? evidence,
  FilingAdvisory? advisory,
  InferenceRunner? inference,
}) {
  final DecisionIndexSource decisions = commandDecisionIndexSource(
    decisionShell,
    runnerInvocation: decisionInvocation,
    gridHome: decisionGridHome,
  );
  return FilingService(
    source: ExactSubstationBeadSource(runnerFor: runnerFor),
    evidence:
        evidence ??
        SystemFilingEvidenceSource(
          probe: validationPlanProbe,
          catalog: BdListAllStatusBeadSource(runnerFor: runnerFor),
          owning: owningScope,
          attached: attachedScopes,
          decisions: decisions,
        ),
    advisory:
        advisory ??
        PreStampAdvisory(
          inference: inference,
          decisions: decisions,
          decisionRunner: decisionInvocation ?? kDefaultOverlayRunner,
          decisionGridHome: decisionGridHome,
          substation: owningScope?.name ?? '',
        ),
  );
}

/// The `--readiness` option every filing verb carries, and its stable wire
/// values.
///
/// `run` is the default and `skip` is the deliberate waiver; there is no
/// spelling for [FilingAdvisoryMode.off] on the command line, because a verb
/// silently not judging is exactly what this option exists to make visible.
const String kReadinessOption = 'readiness';

/// The `--readiness` wire value that RUNS the advisory.
const String kReadinessRun = 'run';

/// The `--readiness` wire value that WAIVES it.
const String kReadinessSkip = 'skip';

/// Declares `--readiness=run|skip` on [parser] — one declaration, so `filing`,
/// `approve` and `unpark` cannot offer three spellings of one waiver.
void addReadinessOption(ArgParser parser) => parser.addOption(
  kReadinessOption,
  allowed: const [kReadinessRun, kReadinessSkip],
  defaultsTo: kReadinessRun,
  help:
      'Run the pre-stamp advisory (the same bead-readiness lens and discovery '
      'evidence gather the spec_review route runs), or waive it. A waiver is '
      'recorded on the stamp.',
);

/// The mode [results] selected. Absent or blank ⇒ [FilingAdvisoryMode.run].
FilingAdvisoryMode readinessModeOf(ArgResults results) =>
    results.option(kReadinessOption) == kReadinessSkip
    ? FilingAdvisoryMode.skip
    : FilingAdvisoryMode.run;

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
    FilingAdvisory? advisory,
    InferenceRunner? inference,
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
             advisory: advisory,
             inference: inference,
           ),
       _storeRoot = storeRoot,
       _armedSubstations = armedSubstations,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser.addFlag(
      'json',
      negatable: false,
      help:
          'Emit {id, passed, requirements, advisory?, error?} as one JSON '
          'object.',
    );
    addReadinessOption(argParser);
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
      'Check one bead against the ten mechanical filing requirements, then '
      'the pre-stamp advisory.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape = 'filing [--json] [--readiness=run|skip] <bead-id>';
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
        advisoryMode: readinessModeOf(argResults!),
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
      // AFTER the ten rows, in the same report: the advisory runs last and
      // reads last. Its refusal carries the owning lens's own fix text.
      switch (report.advisory) {
        case null:
          break;
        case FilingAdvisoryPassed(:final readinessGrade):
          _out.writeln('PASS advisory: bead-readiness $readinessGrade');
        case FilingAdvisorySkipped():
          _out.writeln('SKIP advisory: waived by --readiness=skip');
        case FilingAdvisoryRefused(:final rule, :final reason):
          _out.writeln('FAIL advisory ($rule):');
          _out.writeln(reason);
      }
    }
    return report.passed ? 0 : 1;
  }
}

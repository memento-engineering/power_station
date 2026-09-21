import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdRunner, ProcessBdRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../code/landing.dart' show ShellRunner, SystemShellRunner;
import 'approval_stamp.dart';
import 'filing_command.dart' show defaultFilingService, noArmedSubstations;
import 'filing_contract.dart';

String _currentDirectory() => Directory.current.path;
BdRunner _processRunnerFor(String storeRoot) =>
    ProcessBdRunner(workspaceRoot: storeRoot);

/// The outcome of one approve run — a sealed union so every consumer faces both
/// arms.
sealed class ApprovalOutcome {
  /// Creates an outcome for [beadId], carrying the preflight [report] when one
  /// was computed.
  const ApprovalOutcome({required this.beadId, this.report});

  /// The bead the verb was run against.
  final String beadId;

  /// The filing preflight, or null when the bead could not be read.
  final FilingReport? report;

  /// Structured command/UI representation.
  Map<String, Object?> toJson();
}

/// The verb WROTE the `grid.approved_*` stamp in one `bd update`.
final class ApprovalStamped extends ApprovalOutcome {
  /// Creates the stamped outcome.
  const ApprovalStamped({
    required super.beadId,
    required super.report,
    required this.stamp,
  });

  /// The receipt written.
  final ApprovalStamp stamp;

  @override
  Map<String, Object?> toJson() => {
    'id': beadId,
    'approved': true,
    ...stamp.toJson(),
    if (report case final report?) 'filing': report.toJson(),
  };
}

/// The verb WROTE NOTHING and says why.
final class ApprovalRefused extends ApprovalOutcome {
  /// Creates the refusal.
  const ApprovalRefused({
    required super.beadId,
    required this.reason,
    super.report,
  });

  /// The LOUD reason, printed on both the plain and the JSON path.
  final String reason;

  @override
  Map<String, Object?> toJson() => {
    'id': beadId,
    'approved': false,
    'reason': reason,
    if (report case final report?) 'filing': report.toJson(),
  };
}

/// UI-drivable approval: the eleven-row filing preflight, then ONE stamped
/// `bd update`. Nothing is written unless every row passes.
///
/// The receipt is bound to the preflight that earned it: the stamped revision
/// is the passing report's [FilingReport.approvalRevision], so it names WHAT
/// was approved rather than which commit the store happened to sit on. Git is
/// not consulted at all — a store HEAD moves for reasons that have nothing to
/// do with the bead, and never moves when the bead alone is edited.
final class ApproveService {
  /// Creates the service over the filing preflight and its injectable seams.
  ///
  /// With no [filing] or [evidence] override the preflight is the SAME live
  /// composition the `filing` verb binds ([defaultFilingService]): both verbs
  /// answer one contract one way, including the six viability rows and the
  /// content row. `unpark`
  /// reuses this service, so it gains the same preflight and introduces no
  /// second one.
  ///
  /// FAIL-CLOSED on composition, never on faith: with no `owningScope` — or no
  /// `decisionInvocation`/`decisionGridHome` to execute the index with — a bead
  /// that CITES a decision has UNAVAILABLE evidence for that citation and is
  /// REFUSED, naming the token and the source that did not answer. It is never
  /// passed as though the register had been asked and had answered nothing. A
  /// bead citing no decision needs no lookup and is unaffected.
  ApproveService({
    FilingService? filing,
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
    DateTime Function() now = DateTime.now,
    sdk.SubstationScope? owningScope,
    List<sdk.SubstationScope> attachedScopes = const [],
    ValidationPlanProbe validationPlanProbe = const SystemValidationPlanProbe(),
    ShellRunner decisionShell = const SystemShellRunner(),
    String? decisionInvocation,
    String? decisionGridHome,
    FilingEvidenceSource? evidence,
  }) : filing =
           filing ??
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
       _runnerFor = runnerFor,
       _now = now;

  /// The preflight this verb GATES on.
  final FilingService filing;

  final BdRunner Function(String storeRoot) _runnerFor;
  final DateTime Function() _now;

  /// Approves [beadId] in [storeRoot] on behalf of [actor].
  ///
  /// [armedSubstations] is the station's roster by NAME, which is what an
  /// `external:<project>:<capability>` dependency row's project resolves
  /// against; null means no roster was supplied and such a row refuses
  /// fail-closed, so the bead is never stamped over a blocker nothing
  /// resolved.
  Future<ApprovalOutcome> approve({
    required String storeRoot,
    required String beadId,
    required String actor,
    Set<String>? armedSubstations,
  }) async {
    final report = await filing.check(
      storeRoot: storeRoot,
      beadId: beadId,
      armedSubstations: armedSubstations,
    );
    if (!report.passed) {
      return ApprovalRefused(
        beadId: beadId,
        reason:
            report.error ??
            'the filing preflight has failing rows — correct the bead and '
                'rerun approve',
        report: report,
      );
    }
    final stamp = ApprovalStamp(
      by: actor,
      at: _now().toUtc().toIso8601String(),
      rev: report.approvalRevision,
    );
    final written = await _runnerFor(storeRoot).run([
      'update',
      beadId,
      '--json',
      '--actor',
      actor,
      for (final entry in stamp.metadata.entries) ...[
        '--set-metadata',
        '${entry.key}=${entry.value}',
      ],
    ]);
    if (written.ok) {
      return ApprovalStamped(beadId: beadId, report: report, stamp: stamp);
    }
    final detail = written.stderr.trim().isEmpty
        ? written.stdout.trim()
        : written.stderr.trim();
    return ApprovalRefused(
      beadId: beadId,
      reason: 'bd update refused the stamp: $detail',
      report: report,
    );
  }
}

/// `approve --actor <name> [--json] <bead-id>` — the approval VERB: the filing
/// preflight, then the `grid.approved_*` stamp.
class ApproveCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  ///
  /// This verb takes NO `--state-root`, for the same reason `filing` does not:
  /// the preflight it runs projects the WORK store's own bd rows and reaches
  /// no second store.
  ///
  /// It FORWARDS its composition values to the default service, so the verb a
  /// station composes and the verb an operator runs bind the same live
  /// viability evidence.
  ApproveCommand({
    ApproveService? service,
    String Function() storeRoot = _currentDirectory,
    Set<String>? Function() armedSubstations = noArmedSubstations,
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
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
           ApproveService(
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
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit {id, approved, by, at, rev, filing, reason?} as one JSON '
            'object.',
      )
      ..addOption(
        'actor',
        help: 'The approver, recorded as grid.approved_by. Required.',
      );
  }

  final ApproveService _service;
  final String Function() _storeRoot;
  final Set<String>? Function() _armedSubstations;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'approve';

  @override
  final String description =
      'Stamp one bead approved once the ten filing requirements pass.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape = 'approve --actor <name> [--json] <bead-id>';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln('approve: exactly one bead id is required — $invocation');
      return 64;
    }
    final beadId = rest.single.trim();
    final actor = argResults!.option('actor')?.trim() ?? '';
    if (actor.isEmpty) {
      _err.writeln(
        'approve: --actor <name> is required — the stamp records WHO approved.',
      );
      return 64;
    }
    final ApprovalOutcome outcome;
    try {
      outcome = await _service.approve(
        storeRoot: p.normalize(_storeRoot()),
        beadId: beadId,
        actor: actor,
        armedSubstations: _armedSubstations(),
      );
    } on Object catch (error) {
      _err.writeln('approve: failed to approve $beadId: $error');
      return 1;
    }
    if (argResults!.flag('json')) {
      _out.writeln(jsonEncode(outcome.toJson()));
    } else {
      switch (outcome) {
        case ApprovalStamped(:final stamp):
          _out.writeln(
            'APPROVED $beadId by ${stamp.by} at ${stamp.at} rev ${stamp.rev}',
          );
        case ApprovalRefused(:final reason, :final report):
          _out.writeln('REFUSED $beadId: $reason');
          for (final row
              in report?.requirements ?? const <FilingRequirementRow>[]) {
            if (!row.passed) {
              _out.writeln('FAIL ${row.requirement.wire}: ${row.detail}');
            }
          }
      }
    }
    return switch (outcome) {
      ApprovalStamped() => 0,
      ApprovalRefused() => 1,
    };
  }
}

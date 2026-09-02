import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdRunner, ProcessBdRunner;
import 'package:grid_runtime/grid_runtime.dart' show GitRunner, SystemGitRunner;
import 'package:path/path.dart' as p;

import '../search/station_search.dart';
import 'approval_stamp.dart';
import 'filing_contract.dart';

String _currentDirectory() => Directory.current.path;
String? _noStateRoot() => null;
BdRunner _processRunnerFor(String storeRoot) =>
    ProcessBdRunner(workspaceRoot: storeRoot);
final RegExp _sha = RegExp(r'^[0-9a-f]{7,40}$');

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

/// The verb WROTE the label and the stamp in one `bd update`.
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

/// UI-drivable approval: the four-row filing preflight, then ONE stamped
/// `bd update`. Nothing is written unless every row passes.
final class ApproveService {
  /// Creates the service over the filing preflight and three injectable seams.
  ApproveService({
    FilingService? filing,
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
    GitRunner? git,
    DateTime Function() now = DateTime.now,
  }) : filing =
           filing ??
           FilingService(
             source: ExactSubstationBeadSource(runnerFor: runnerFor),
             links: CrossLinkBlockerSource(runnerFor: runnerFor),
           ),
       _runnerFor = runnerFor,
       _git = git,
       _now = now;

  /// The preflight this verb GATES on.
  final FilingService filing;

  final BdRunner Function(String storeRoot) _runnerFor;
  final GitRunner? _git;
  final DateTime Function() _now;

  /// Approves [beadId] in [storeRoot] on behalf of [actor].
  ///
  /// [stateRoot] is the grid home whose state store holds the cross-store link
  /// beads; null means only local `blocks` edges count as wiring.
  Future<ApprovalOutcome> approve({
    required String storeRoot,
    required String beadId,
    required String actor,
    String? stateRoot,
  }) async {
    final report = await filing.check(
      storeRoot: storeRoot,
      beadId: beadId,
      stateRoot: stateRoot,
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
    final head = await (_git ?? SystemGitRunner()).run(
      workingDirectory: storeRoot,
      args: const ['rev-parse', 'HEAD'],
    );
    final rev = head.output.trim();
    if (!head.ok || !_sha.hasMatch(rev)) {
      return ApprovalRefused(
        beadId: beadId,
        reason:
            'could not read the approval revision of $storeRoot '
            '(git rev-parse HEAD: $rev)',
        report: report,
      );
    }
    final stamp = ApprovalStamp(
      by: actor,
      at: _now().toUtc().toIso8601String(),
      rev: rev,
    );
    final written = await _runnerFor(storeRoot).run([
      'update',
      beadId,
      '--json',
      '--actor',
      actor,
      '--add-label',
      kApprovedLabel,
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

/// `approve --actor <name> [--json] [--state-root <path>] <bead-id>` — the
/// approval VERB: the filing preflight, then the label plus its receipt.
class ApproveCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  ApproveCommand({
    ApproveService? service,
    String Function() storeRoot = _currentDirectory,
    String? Function() stateRoot = _noStateRoot,
    StringSink? out,
    StringSink? err,
  }) : _service = service ?? ApproveService(),
       _storeRoot = storeRoot,
       _stateRoot = stateRoot,
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
      )
      ..addOption(
        'state-root',
        help:
            'The grid home whose .grid/.beads holds the cross-store link '
            'beads.',
      );
  }

  final ApproveService _service;
  final String Function() _storeRoot;
  final String? Function() _stateRoot;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'approve';

  @override
  final String description =
      'Stamp one bead approved once the four filing requirements pass.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape =
        'approve --actor <name> [--json] [--state-root <path>] <bead-id>';
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
    final option = argResults!.option('state-root')?.trim();
    final stateRoot = option == null || option.isEmpty
        ? _stateRoot()
        : p.normalize(option);
    final ApprovalOutcome outcome;
    try {
      outcome = await _service.approve(
        storeRoot: p.normalize(_storeRoot()),
        beadId: beadId,
        actor: actor,
        stateRoot: stateRoot,
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

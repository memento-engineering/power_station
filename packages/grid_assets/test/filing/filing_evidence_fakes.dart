// The shared FAKES for the filing viability seams (Fakes, not mocks — the
// house rule). One copy, composed by every suite that needs a plan parse or a
// prepared evidence gather: the viability suite, the seams fences, the approve
// preflight, the park/unpark ritual and the Specify stage.
import 'dart:io' show ProcessException;

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:grid_assets/grid_assets.dart';

/// A Fake [ValidationPlanProbe] answering from a scripted per-shell table.
///
/// It spawns nothing. [calls] records every ask in order, so a suite can prove
/// that filing and Specify consume the SAME outcome rather than each probing.
final class FakeValidationPlanProbe implements ValidationPlanProbe {
  /// Answers [shell] from [answers]; an unlisted shell parses clean.
  FakeValidationPlanProbe({
    this.answers = const {},
    this.throwsFor = const {},
    this.missingShells = const {},
  });

  /// The scripted answer per shell.
  final Map<String, ValidationPlanParseResult> answers;

  /// Shells whose probe THROWS, and the message it throws with.
  final Map<String, String> throwsFor;

  /// Shells this machine does NOT have installed — the probe raises the named
  /// [ValidationPlanShellMissing] for them, exactly as the real one does on an
  /// ENOENT spawn.
  final Set<String> missingShells;

  /// Every ask, in order.
  final List<({String shell, String plan, String workingDirectory})> calls = [];

  @override
  Future<ValidationPlanParseResult> parse({
    required String shell,
    required String plan,
    required String workingDirectory,
  }) async {
    calls.add((shell: shell, plan: plan, workingDirectory: workingDirectory));
    if (missingShells.contains(shell)) {
      throw ValidationPlanShellMissing(
        shell,
        const ProcessException('', [], 'No such file or directory', 2),
      );
    }
    if (throwsFor[shell] case final message?) throw StateError(message);
    return answers[shell] ??
        ValidationPlanParseResult(shell: shell, exitCode: 0);
  }
}

/// A Fake [FilingEvidenceSource] handing back one prepared gather.
final class FakeFilingEvidenceSource implements FilingEvidenceSource {
  /// Always answers [evidence].
  const FakeFilingEvidenceSource(this.evidence);

  /// What every gather answers with.
  final FilingEvidence evidence;

  @override
  Future<FilingEvidence> gather({
    required String storeRoot,
    required Bead bead,
  }) async => evidence;
}

/// Evidence whose two plan probes PARSED, with every other leg left as the
/// caller sets it — the baseline a suite that is not testing the plan rows
/// composes so those rows never mask the row under test.
FilingEvidence parsedPlanEvidence({
  Map<String, Set<String>> beadCatalogs = const {},
  Map<String, String> beadCatalogFailures = const {},
  Set<String>? decisionRegisters,
  Set<String> decisionIdentities = const {},
  Set<String> decisionAliases = const {},
  Set<String> absentDecisions = const {},
  Set<String> reportedDecisionAliases = const {},
  String decisionIndexFailure = '',
}) => FilingEvidence(
  lanePlanParse: const ValidationPlanParseResult(
    shell: kFilingLaneShell,
    exitCode: 0,
  ),
  portablePlanParse: const ValidationPlanParseResult(
    shell: kFilingPortabilityShell,
    exitCode: 0,
  ),
  beadCatalogs: beadCatalogs,
  beadCatalogFailures: beadCatalogFailures,
  decisionRegisters: decisionRegisters,
  decisionIdentities: decisionIdentities,
  decisionAliases: decisionAliases,
  absentDecisions: absentDecisions,
  reportedDecisionAliases: reportedDecisionAliases,
  decisionIndexFailure: decisionIndexFailure,
);

/// The complete-evidence gather for a bead that cites nothing: both plans
/// parse, and both catalogs answered EMPTY rather than not at all.
FilingEvidence get completeEmptyEvidence =>
    parsedPlanEvidence(decisionRegisters: const {});

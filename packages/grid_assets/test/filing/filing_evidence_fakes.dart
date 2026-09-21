// The shared FAKES for the filing viability seams (Fakes, not mocks — the
// house rule). One copy, composed by every suite that needs a plan parse or a
// prepared evidence gather: the viability suite, the seams fences, the approve
// preflight, the park/unpark ritual and the Specify stage.
import 'dart:convert' show jsonEncode;
import 'dart:io' show ProcessException;

import 'package:beads_dart/beads_dart.dart' show Bead, BdResult, BdRunner;
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart' show RuntimeConfig;

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

/// A Fake [FilingAdvisory] answering with one scripted verdict.
///
/// It runs NO inference, so a suite composing it proves the verb's ORDER and
/// its rendering without ever reaching a model. [calls] records every ask in
/// order, which is what lets a suite prove the negative the advisory's cost
/// rests on: a mechanically failing bead never reaches it, and a waiver never
/// does either.
final class FakeFilingAdvisory implements FilingAdvisory {
  /// Answers every ask with [verdict].
  FakeFilingAdvisory([
    this.verdict = const FilingAdvisoryPassed(readinessGrade: 'B'),
  ]);

  /// What every evaluation answers with.
  final FilingAdvisoryVerdict verdict;

  /// Every ask, in order.
  final List<({String storeRoot, String beadId})> calls = [];

  @override
  Future<FilingAdvisoryVerdict> evaluate({
    required String storeRoot,
    required Bead bead,
  }) async {
    calls.add((storeRoot: storeRoot, beadId: bead.id));
    return verdict;
  }
}

/// A Fake [InferenceRunner] answering each call from a scripted queue, in
/// order, and recording the whole argv it was handed.
///
/// The queue is drained front to back; an exhausted queue answers not-ok with
/// empty output, which is exactly what the advisory must treat as a lens that
/// did not complete.
final class ScriptedInferenceRunner implements InferenceRunner {
  /// Creates the runner over its scripted [replies].
  ScriptedInferenceRunner([List<InferenceResult> replies = const []])
    : _replies = [...replies];

  final List<InferenceResult> _replies;

  /// Every config this runner was handed, in call order.
  final List<RuntimeConfig> calls = [];

  /// The rendered prompt of each call, in call order.
  List<String> get prompts => [
    for (final config in calls) config.args.join('\n'),
  ];

  @override
  Future<InferenceResult> run(RuntimeConfig config) async {
    calls.add(config);
    if (_replies.isEmpty) {
      return const InferenceResult(ok: false, output: '');
    }
    return _replies.removeAt(0);
  }
}

/// One `bead-readiness` verdict, as a lens on the fileless arm replies with it.
InferenceResult readinessReply(String grade, {String rationale = 'because'}) =>
    InferenceResult(
      ok: true,
      output:
          '{"rubric":"$kReadinessRubric","version":1,"grade":"$grade",'
          '"rationale":"$rationale","nodePath":"$kPreStampAdvisoryNodePath",'
          '"round":0}',
    );

/// One CLEAN discovery lens report, as a lens on the fileless arm replies.
InferenceResult cleanLensReply(String lens) => InferenceResult(
  ok: true,
  output:
      '{"outcome":"report","lens":"$lens","version":2,"context":[],'
      '"violations":[]}',
);

/// Three clean lens replies, in [kDiscoveryLenses] order — the fan-out's
/// answer for a bead that offends nothing.
List<InferenceResult> get cleanDiscoveryReplies => [
  for (final lens in kDiscoveryLenses) cleanLensReply(lens),
];

/// A [BdRunner] answering the RECORD read (`query`) with one bead and every
/// other read with an EMPTY envelope — bd's own shapes, so the dependency
/// projection reads no rows rather than mis-decoding the bead as one.
final class FakeExactBeadRunner implements BdRunner {
  /// Answers every record read with [bead].
  FakeExactBeadRunner(this.bead, {this.validationPlan = 'dart test'});

  /// The one bead this store holds.
  final Bead bead;

  /// The plan its metadata carries, so the two plan rows have something to
  /// judge.
  final String validationPlan;

  /// Every argv, in order.
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    return BdResult(
      exitCode: 0,
      stdout: args.first == 'query'
          ? jsonEncode({
              'schema_version': 1,
              'data': [
                {
                  ...bead.toJson(),
                  'metadata': {'validation_plan': validationPlan},
                  'dependencies': <Object?>[],
                },
              ],
            })
          : '{"schema_version":1,"data":[]}',
      stderr: '',
    );
  }
}

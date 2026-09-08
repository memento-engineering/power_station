/// The DESIGN-ROUND committee — the docs committee (`docs_committee.dart`) with
/// its judgemental half replaced, and the one step the docs circuit lacks.
///
/// **Why it exists** (Nico, 2026-09-07): "This should be harness agnostic … the
/// station is the harness." A design round — a document argued to convergence
/// by adversarial readers — ran as a Claude Code Workflow because the station
/// had no circuit of that shape: a design seat, judges with DISTINCT lenses,
/// and a verifier that reconciles their claims and applies the fixes, looped
/// until nothing is left open. That run was the last one. The shape lives here
/// now, so a design round is a station bead whose receipts land in the
/// trajectory and whose grades land in the state store.
///
/// **What is new, and what is emphatically not.** Nothing about committee
/// machinery changes: the three DETERMINISTIC docs gates
/// ([kCitationPathsRubric], [kTerminologyBanRubric], [kSectionStructureRubric])
/// are mounted VERBATIM — same step ids, same [kDocsCheckCapabilityId], same
/// rubric params, same [kPinDiffStep] dependency — and the route is the shared
/// [CodeRouteCapability] over the shared rework loop. Two things are new:
///
///  1. **The judges are ADVERSARIAL LENSES, not one adherence critic.** The
///     docs committee's single `spec-adherence` lane is replaced by
///     [kDesignJudgeRubrics] — four ordinary rubric-parametrized `critic` lanes
///     ([CriticCapability], the same verdict transport, the same round-fresh
///     `.grid/critique/<lane>.json`), each commanded to REFUTE with receipts
///     and to grade its findings BLOCKER / MAJOR / MINOR. A new lens is a new
///     rubric asset, exactly as the docs committee's own header promises.
///  2. **A VERIFY step sits between the judges and the route**
///     ([DesignVerifyCapability]). A judge's rationale is EVIDENCE, never fact:
///     the verifier confirms or refutes each finding against the tree and the
///     rulings the bead names, applies the confirmed fixes to the document, and
///     appends an adjudication log to it (finding → `CONFIRMED-FIXED` /
///     `REFUTED` / `CONFIRMED-OPEN`). Only a CONFIRMED-OPEN finding reaches the
///     route, as the single lane it joins on. This is the step whose absence is
///     the whole reason design rounds were hand-rolled.
///
/// **The loop is the existing loop.** An open blocker grades the verify lane
/// `F`; the route is handed `critics` = `gating` = [kDesignVerifyStep], so its
/// unchanged matrix hard-blocks, the bead reworks, and the next round's design
/// seat is the ordinary `agent` step reading the bead plus the verifier's note.
/// No new loop machinery, no second matrix, no workflow engine.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/model_tier.dart';
import '../agent/seat_environments.dart';
import '../agent/site_binding.dart';
import '../agent/typed_environment.dart';
import '../agent/usage_report.dart';
import '../assets/asset_loader.dart';
import '../io/recorded_artifact.dart';
import 'committee.dart';
import 'committee_selection.dart';
import 'docs_committee.dart';
import 'pr_describe.dart';

/// The judge lane that holds the document to every RULING the bead names —
/// each one honoured, each one cited by its entry sentence.
const String kRulingAdherenceRubric = 'ruling-adherence';

/// The judge lane that reads the document as a MECHANISM: causal ordering,
/// interlocks, restore order, breaker semantics, partial-failure rollback.
const String kOrderingAndRollbackRubric = 'ordering-and-rollback';

/// The judge lane that follows every decision-bearing fact through the
/// document's folds and asks whether the result is OPERABLE.
const String kFoldFidelityAndOpsRubric = 'fold-fidelity-and-ops';

/// The judge lane that RESOLVES every citation — the deterministic half of an
/// otherwise judgemental committee.
const String kCiteVerificationRubric = 'cite-verification';

/// The four ADVERSARIAL judge lenses, in the order the r6 round ran them.
/// Each is a distinct rubric asset; the pack IS the committee (`docs_committee`
/// header: "a new document type IS a new rubric pack plus its circuit").
const List<String> kDesignJudgeRubrics = [
  kRulingAdherenceRubric,
  kOrderingAndRollbackRubric,
  kFoldFidelityAndOpsRubric,
  kCiteVerificationRubric,
];

/// Every design-committee rubric id — the docs committee's three deterministic
/// gates first, then the four judges.
const List<String> kDesignCommitteeRubrics = [
  ...kDocsGatingRubrics,
  ...kDesignJudgeRubrics,
];

/// The verify step's id — also the rubric id its critique artifact is filed
/// under, and the ONE lane the route joins. A LITERAL: it is a persisted
/// cursor key.
const String kDesignVerifyStep = 'design-verify';

/// The three severities a judge may attach to a finding, worst first.
const List<String> kDesignSeverities = ['BLOCKER', 'MAJOR', 'MINOR'];

/// The three verdicts the verifier may return for a finding.
const List<String> kDesignVerdicts = [
  'CONFIRMED-FIXED',
  'REFUTED',
  'CONFIRMED-OPEN',
];

/// The verdict a finding carries when it survived verification — the ONLY one
/// that reaches the route.
const String kDesignVerdictOpen = 'CONFIRMED-OPEN';

/// The heading the verifier appends its per-round record under. ONE section per
/// document, one `### Round <n>` subsection per round.
const String kAdjudicationLogHeading = '## Adjudication Log';

/// The total character budget for the design documents a single verify pass
/// embeds in its brief.
///
/// A BOUND, not a truncation: a round whose documents exceed it REFUSES (grade
/// `F`, naming the size), because a truncated document handed to the verifier
/// comes back as a truncated REVISED body — and this step WRITES that body.
/// Silently losing half a design document is the one failure mode a verifier
/// must never have.
const int kDesignDocumentBudget = 200000;

/// The exact line grammar every judge rationale line must follow, so the
/// verifier can read a judgment as DATA rather than as prose. Stated in each
/// judge rubric and enforced here by [parseDesignFindings].
final RegExp _findingLine = RegExp(
  r'^-\s*\[(BLOCKER|MAJOR|MINOR)\]\s+(\S+)\s+—\s+(.+);\s*receipt:\s*(\S.*)$',
);

/// One finding a judge lane raised — the parsed form of one rationale line.
class DesignFinding {
  /// Creates the finding.
  const DesignFinding({
    required this.lane,
    required this.id,
    required this.severity,
    required this.claim,
    required this.receipt,
  });

  /// The judge lane (rubric id) that raised it.
  final String lane;

  /// The judge's own id for the finding, unique WITHIN its lane.
  final String id;

  /// One of [kDesignSeverities].
  final String severity;

  /// What the judge claims is wrong.
  final String claim;

  /// The receipt backing the claim — a `path:line` or a quoted ruling
  /// sentence. A claim with no receipt is not a finding (see the rubrics).
  final String receipt;

  /// The `(lane, id)` identity the verifier's answer must reproduce exactly.
  String get key => '$lane/$id';

  @override
  String toString() => '[$severity] $key — $claim; receipt: $receipt';
}

/// The letter grade a lane must report for [findings] — the SHARED verdict
/// envelope's A–F alphabet, mapped from the worst severity present.
///
/// The mapping is stated in every judge rubric and VERIFIED here, so a judge
/// whose letter contradicts its own findings is a transport defect the round
/// catches rather than an opinion the route silently acts on.
String designGradeFor(Iterable<DesignFinding> findings) {
  if (findings.any((f) => f.severity == 'BLOCKER')) return 'F';
  if (findings.any((f) => f.severity == 'MAJOR')) return 'D';
  if (findings.any((f) => f.severity == 'MINOR')) return 'C';
  return 'A';
}

/// Parses one judge lane's [rationale] into its findings.
///
/// EVERY non-blank line must match the grammar, ids must be unique within the
/// lane, and [grade] must be the letter [designGradeFor] computes. Anything
/// else throws a [FormatException] naming the offence — the verifier fails
/// closed on it BEFORE spending an inference call, because a judgment it cannot
/// read is a judgment it cannot verify.
List<DesignFinding> parseDesignFindings({
  required String lane,
  required String grade,
  required String rationale,
}) {
  final findings = <DesignFinding>[];
  final seen = <String>{};
  for (final line in const LineSplitter().convert(rationale)) {
    if (line.trim().isEmpty) continue;
    final match = _findingLine.firstMatch(line.trim());
    if (match == null) {
      throw FormatException(
        'judge lane `$lane` wrote a rationale line that is not a finding: '
        '"${line.trim()}"',
      );
    }
    final id = match.group(2)!;
    if (!seen.add(id)) {
      throw FormatException(
        'judge lane `$lane` raised finding id `$id` twice — a finding id is '
        'unique within its lane',
      );
    }
    findings.add(
      DesignFinding(
        lane: lane,
        id: id,
        severity: match.group(1)!,
        claim: match.group(3)!.trim(),
        receipt: match.group(4)!.trim(),
      ),
    );
  }
  final expected = designGradeFor(findings);
  if (grade != expected) {
    throw FormatException(
      'judge lane `$lane` graded `$grade` but its ${findings.length} '
      'finding(s) map to `$expected` — the letter and the findings disagree',
    );
  }
  return findings;
}

/// One adjudicated finding — the verifier's answer to one judge claim.
class DesignAdjudication {
  /// Creates the adjudication.
  const DesignAdjudication({
    required this.lane,
    required this.findingId,
    required this.finding,
    required this.severity,
    required this.verdict,
    required this.why,
  });

  /// The judge lane the finding came from.
  final String lane;

  /// The judge's finding id.
  final String findingId;

  /// The finding restated by the verifier.
  final String finding;

  /// The judge's severity, carried through unchanged.
  final String severity;

  /// One of [kDesignVerdicts].
  final String verdict;

  /// Why — the receipt for the verdict itself.
  final String why;

  /// Whether this finding SURVIVED verification and must block the round.
  bool get isOpen => verdict == kDesignVerdictOpen;

  /// The `(lane, findingId)` identity, matched against the judges' own.
  String get key => '$lane/$findingId';

  /// The artifact/JSON form.
  Map<String, Object?> toJson() => {
    'lane': lane,
    'findingId': findingId,
    'finding': finding,
    'severity': severity,
    'verdict': verdict,
    'why': why,
  };

  /// The one-record markdown form the adjudication log carries.
  String toLogRecord() =>
      '- **$lane/$findingId** ($severity) — $finding\n'
      '  - **$verdict** — $why';
}

/// The verifier's whole answer: the revised documents plus one adjudication per
/// judge finding.
class DesignVerificationReport {
  /// Creates the report.
  const DesignVerificationReport({
    required this.documents,
    required this.adjudications,
  });

  /// Repo-relative design-document path → its COMPLETE revised body.
  final Map<String, String> documents;

  /// One entry per judge finding, in the response's own order.
  final List<DesignAdjudication> adjudications;

  /// Every finding that survived verification.
  List<DesignAdjudication> get open =>
      adjudications.where((a) => a.isOpen).toList();

  /// Parses the verifier's raw answer, refusing anything that is not the exact
  /// contract.
  ///
  /// STRICT by construction, and validated WHOLE before any caller writes a
  /// byte: [documentPaths] fixes the document key set exactly (an extra key is
  /// an out-of-scope write, a missing one is a lost document), and [findings]
  /// fixes the `(lane, findingId)` multiset exactly (so no judge finding can be
  /// dropped, duplicated, or invented). Every violation throws a
  /// [FormatException] naming it.
  static DesignVerificationReport parse(
    String raw, {
    required Set<String> documentPaths,
    required List<DesignFinding> findings,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(_unfenced(raw));
    } on Object catch (e) {
      throw FormatException('the answer is not readable JSON ($e)');
    }
    if (decoded is! Map) {
      throw const FormatException('the verifier answer is not a JSON object');
    }
    final rawDocuments = decoded['documents'];
    if (rawDocuments is! Map) {
      throw const FormatException('"documents" must be an object');
    }
    final documents = <String, String>{};
    for (final entry in rawDocuments.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !documentPaths.contains(key)) {
        throw FormatException(
          'the verifier named an OUT-OF-SCOPE document "$key" — this round\'s '
          'documents are ${documentPaths.join(', ')}',
        );
      }
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('"documents"["$key"] is not a complete body');
      }
      documents[key] = value;
    }
    final missing = documentPaths.difference(documents.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        'the verifier returned no body for ${missing.join(', ')}',
      );
    }
    final rawAdjudications = decoded['adjudications'];
    if (rawAdjudications is! List) {
      throw const FormatException('"adjudications" must be a list');
    }
    final adjudications = <DesignAdjudication>[];
    for (final entry in rawAdjudications) {
      if (entry is! Map) {
        throw const FormatException('an adjudication is not an object');
      }
      String field(String name) {
        final value = entry[name];
        if (value is! String || value.trim().isEmpty) {
          throw FormatException('an adjudication has no "$name"');
        }
        return value.trim();
      }

      final severity = field('severity');
      if (!kDesignSeverities.contains(severity)) {
        throw FormatException('unknown severity "$severity"');
      }
      final verdict = field('verdict');
      if (!kDesignVerdicts.contains(verdict)) {
        throw FormatException('unknown verdict "$verdict"');
      }
      adjudications.add(
        DesignAdjudication(
          lane: field('lane'),
          findingId: field('findingId'),
          finding: field('finding'),
          severity: severity,
          verdict: verdict,
          why: field('why'),
        ),
      );
    }
    final answered = adjudications.map((a) => a.key).toList()..sort();
    final asked = findings.map((f) => f.key).toList()..sort();
    if (answered.join(' ') != asked.join(' ')) {
      throw FormatException(
        'the verifier answered ${answered.length} finding(s) '
        '(${answered.join(', ')}) but the judges raised ${asked.length} '
        '(${asked.join(', ')}) — every finding is adjudicated exactly once',
      );
    }
    return DesignVerificationReport(
      documents: documents,
      adjudications: adjudications,
    );
  }

  /// [raw] with a single wrapping markdown code fence removed — the one
  /// concession to a model that answers correctly inside a fence. The PAYLOAD
  /// is still parsed strictly.
  static String _unfenced(String raw) {
    final text = raw.trim();
    if (!text.startsWith('```')) return text;
    final lines = const LineSplitter().convert(text);
    final body = lines.sublist(1);
    while (body.isNotEmpty && body.last.trim().isEmpty) {
      body.removeLast();
    }
    if (body.isNotEmpty && body.last.trim() == '```') body.removeLast();
    return body.join('\n').trim();
  }
}

/// The VERIFY step — the design committee's one new capability, and the reason
/// a design round is a station circuit rather than a hand-rolled workflow.
///
/// It reads the judges' verdicts, CONFIRMS or REFUTES each finding against the
/// tree and the bead's rulings, applies the confirmed fixes to the design
/// document, appends the round's adjudication log to it, and grades: `F` when a
/// finding is `CONFIRMED-OPEN` (the route hard-blocks and the existing rework
/// loop turns), `A` otherwise. A REFUTED finding is recorded and costs the
/// round nothing — which is exactly the property a committee of adversarial
/// judges needs, because a judge's rationale is evidence, not fact.
///
/// **Fail-closed everywhere, and never silently.** Every refusal grades `F`,
/// NAMES what it refused, and writes the same artifact shape a graded round
/// writes: no ambient bead/workspace; no pinned diff; a gate or judge lane with
/// no grade; a docs gate already at `F` (its lane and rationale carried through
/// verbatim, and no inference spent on a document the mechanical checks already
/// rejected); no changed design document on disk; a judgment whose lines or
/// letter it cannot read ([parseDesignFindings]); documents past
/// [kDesignDocumentBudget]; an unresolvable agent environment; an inference
/// that did not run or whose answer breaks the contract
/// ([DesignVerificationReport.parse]); a failed write.
///
/// **The one short-circuit, and why it is not a hole**: four judges at `A` have
/// raised nothing to confirm, nothing to refute and nothing to fix, so the step
/// grades `A` and writes its artifact WITHOUT an inference call. Spending a
/// frontier call to adjudicate an empty finding list would buy nothing and
/// would hand the model a licence to rewrite a document no judge objected to.
class DesignVerifyCapability extends ServiceCapability {
  /// Creates the verifier over its ONE-SHOT inference seam. Null — a bare
  /// `const DesignVerifyCapability()` — is the UNWIRED posture and refuses
  /// LOUDLY at `run`: this is a gate, so an unwired verifier must never pass a
  /// round the way an unwired PR description falls back.
  const DesignVerifyCapability({InferenceRunner? inference})
    : _inference = inference;

  final InferenceRunner? _inference;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Every ambient read happens HERE, at entry, while the branch is mounted;
    // everything below is pure over the captured values plus the worktree's
    // own files (ADR-0008 D3 — the effect verb at an effect edge).
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    if (bead == null || workspace == null) {
      return const Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale':
            'no ambient work Bead / Workspace to verify against — fail-closed',
      });
    }
    final workspaceDir = workspace.workspaceDir;
    final round = verdictRound(args);
    final parent = parentPath(args.nodePath);

    Future<StepOutcome> refuse(String reason) =>
        _record(workspaceDir, args.nodePath, round, 'F', reason, const []);

    // 1. Every lane this step joins must have REPORTED. A missing grade is the
    // fail-closed miss the whole committee is built on.
    final grades = <String, String>{};
    final rationales = <String, String>{};
    final silent = <String>[];
    for (final lane in kDesignCommitteeRubrics) {
      final result = siblings.resultOf('$parent/$lane');
      final grade = result['grade']?.trim() ?? '';
      if (grade.isEmpty) {
        silent.add(lane);
        continue;
      }
      grades[lane] = grade;
      rationales[lane] = result['rationale']?.trim() ?? '';
    }
    if (silent.isNotEmpty) {
      return refuse(
        'no grade from ${silent.join(', ')} — the verifier cannot adjudicate a '
        'lane that did not report; fail-closed',
      );
    }

    // 2. A deterministic docs gate at F is already a hard block; carrying it
    // through unchanged is both the honest answer and the cheap one.
    final failedGates = kDocsGatingRubrics
        .where((lane) => grades[lane] == 'F')
        .toList();
    if (failedGates.isNotEmpty) {
      return refuse(
        'the deterministic docs gate(s) ${failedGates.join(', ')} failed: '
        '${[for (final lane in failedGates) rationales[lane]!].where((r) => r.isNotEmpty).join('; ')}',
      );
    }

    // 3. The round's scope — the pinned diff the judges reviewed, narrowed to
    // the design documents it actually changed (A9's one review scope, read
    // once and shared).
    final pinned = File(pinnedDiffPath(workspaceDir));
    if (!pinned.existsSync()) {
      return refuse(
        'no pinned diff at ${pinned.path} — the verifier cannot see the round '
        'it adjudicates; fail-closed',
      );
    }
    final changed = changedFilesIn(pinned.readAsStringSync());
    final documents = <String, String>{};
    for (final path in changed.where(isDesignPath).toList()..sort()) {
      final file = File(p.join(workspaceDir, path));
      if (file.existsSync()) documents[path] = file.readAsStringSync();
    }
    if (documents.isEmpty) {
      return refuse(
        'the pinned diff changed no `$kDesignPathPrefix/**` document that '
        'exists in the worktree — there is nothing to verify; fail-closed',
      );
    }
    final budget = documents.values.fold(0, (sum, body) => sum + body.length);
    if (budget > kDesignDocumentBudget) {
      return refuse(
        'this round\'s documents are $budget characters, past the '
        '$kDesignDocumentBudget-character verify budget — split the round '
        'rather than verify a truncated document',
      );
    }

    // 4. The judgments, read as DATA. A judgment the verifier cannot read is
    // refused BEFORE an inference call is spent on it.
    final findings = <DesignFinding>[];
    try {
      for (final lane in kDesignJudgeRubrics) {
        findings.addAll(
          parseDesignFindings(
            lane: lane,
            grade: grades[lane]!,
            rationale: rationales[lane]!,
          ),
        );
      }
    } on FormatException catch (e) {
      return refuse('unreadable judgment — ${e.message}');
    }
    if (findings.isEmpty) {
      return _record(
        workspaceDir,
        args.nodePath,
        round,
        'A',
        'every judge lane returned A — no finding to confirm, refute or fix',
        const [],
      );
    }

    // 5. The adjudication itself — ONE bounded call on the FRONTIER tier: this
    // is repair work over a design document, not a grading lane, so it rides
    // the build's tier while the judges ride `critic`'s cheaper mid tier.
    final inference = _inference;
    if (inference == null) {
      return refuse(
        'no InferenceRunner is wired into `$kDesignVerifyStep` — the verifier '
        'is a GATE and refuses rather than passing an unverified round',
      );
    }
    final RuntimeConfig spawn;
    try {
      spawn = _spawnFor(
        context: context,
        bead: bead,
        workspace: workspace,
        args: args,
        brief: buildDesignVerifyPrompt(
          bead: bead,
          documents: documents,
          findings: findings,
          round: round,
        ),
      );
    } on Object catch (e) {
      return refuse('the verifier could not resolve an agent environment: $e');
    }
    final run = await inference.run(spawn);
    // With FT-2 capture armed the harness redirects its whole envelope to the
    // telemetry file, so the answer is that envelope's `result` text; a harness
    // with no usage surface still answers on stdout.
    final answer =
        readEnvelopeResultText(workspaceDir, args.nodePath) ?? run.output;
    if (!run.ok) {
      return refuse(
        'the verify inference did not complete — no adjudication was produced',
      );
    }
    final DesignVerificationReport report;
    try {
      report = DesignVerificationReport.parse(
        answer,
        documentPaths: documents.keys.toSet(),
        findings: findings,
      );
    } on FormatException catch (e) {
      return refuse('the verifier answer breaks the contract — ${e.message}');
    } on Object catch (e) {
      return refuse('the verifier answer is not readable JSON: $e');
    }

    // 6. The writes — the whole response was validated above, so a document is
    // only ever replaced by a complete body, and the log only ever grows.
    try {
      for (final entry in report.documents.entries) {
        await recordArtifact(
          File(p.join(workspaceDir, entry.key)),
          withAdjudicationLog(
            revised: entry.value,
            onDisk: documents[entry.key]!,
            round: round,
            adjudications: report.adjudications,
          ),
        );
      }
    } on Object catch (e) {
      return refuse('the verifier could not write its revised document: $e');
    }

    final open = report.open;
    return _record(
      workspaceDir,
      args.nodePath,
      round,
      open.isEmpty ? 'A' : 'F',
      open.isEmpty
          ? 'every finding was fixed or refuted '
                '(${report.adjudications.length} adjudicated)'
          : '${open.length} finding(s) survived verification: '
                '${open.map((a) => '${a.key} — ${a.finding} (${a.why})').join('; ')}',
      report.adjudications,
    );
  }

  /// Renders the ONE spawn this step makes. Separated so every ambient read
  /// stays at [run]'s entry and this is pure over its arguments plus the
  /// context's own effect-edge lookups.
  RuntimeConfig _spawnFor({
    required TreeContext context,
    required Bead bead,
    required Workspace workspace,
    required StepArgs args,
    required String brief,
  }) {
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final config = resolveAgentConfig(
      // The FRONTIER tier (beads `pow-2c9` / `pow-n6n.4`): this lane REPAIRS a
      // design document, which is build-class work — the judges above it grade
      // and ride `CriticCapability`'s mid tier, unchanged.
      tier: AgentTier.frontier,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
      typedEnvironment: resolveEnvironment<BuildAgentEnvironment>(context),
    );
    final environment = registry.resolve(config.harness);
    return spawnFor(
      environment: environment,
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(
        name: config.harness,
        environment: environment,
      ),
      brief: AgentBrief(task: brief),
      workspace: workspace,
      usageOut: usageReportPath(args.nodePath),
    );
  }

  /// Writes the round's verify artifact and returns the lane's payload — the
  /// ONE exit every arm above takes, so a refusal and a graded round are
  /// indistinguishable in shape to every reader downstream.
  ///
  /// The artifact write is best-effort in exactly the way the critique dir's
  /// other artifacts are: the route decides on the RESULT payload, so a
  /// worktree that cannot be written still grades.
  Future<StepOutcome> _record(
    String workspaceDir,
    String nodePath,
    int round,
    String grade,
    String rationale,
    List<DesignAdjudication> adjudications,
  ) async {
    try {
      await recordArtifact(
        File(p.join(critiqueDirPath(workspaceDir), '$kDesignVerifyStep.json')),
        jsonEncode({
          'rubric': kDesignVerifyStep,
          'version': 1,
          'grade': grade,
          'rationale': rationale,
          'nodePath': nodePath,
          kVerdictRoundKey: round,
          'adjudications': [for (final a in adjudications) a.toJson()],
        }),
      );
    } on Object {
      // The receipt is evidence, never the decision — see above.
    }
    return Ok({
      'grade': grade,
      'transport': 'structural',
      'rationale': rationale,
    });
  }
}

/// [revised] with this round's adjudication record appended under the ONE
/// [kAdjudicationLogHeading] section, keeping every EARLIER round's subsection.
///
/// The prior log is taken from the [onDisk] body, never from [revised]: the
/// verifier rewrites the document's prose, and the log is the round's own
/// receipt — a model that dropped or rewrote history cannot erase it. Re-running
/// the SAME round replaces that round's subsection rather than appending a
/// second copy, so a retry is idempotent.
String withAdjudicationLog({
  required String revised,
  required String onDisk,
  required int round,
  required List<DesignAdjudication> adjudications,
}) {
  final body = _withoutAdjudicationLog(revised).trimRight();
  final prior = _adjudicationLogOf(onDisk)
      .where((subsection) => !subsection.startsWith('### Round $round\n'))
      .toList();
  final entry = StringBuffer('### Round $round\n');
  for (final adjudication in adjudications) {
    entry.writeln(adjudication.toLogRecord());
  }
  if (adjudications.isEmpty) entry.writeln('- no finding was raised.');
  return '$body\n\n$kAdjudicationLogHeading\n\n'
      '${[...prior, entry.toString().trimRight()].join('\n\n')}\n';
}

/// Every `### Round <n>` subsection already recorded in [body], in order.
List<String> _adjudicationLogOf(String body) {
  final lines = const LineSplitter().convert(body);
  final start = lines.indexOf(kAdjudicationLogHeading);
  if (start < 0) return const [];
  final subsections = <List<String>>[];
  for (final line in lines.sublist(start + 1)) {
    // The log is the document's LAST section by construction; a fresh `## `
    // heading ends it regardless.
    if (line.startsWith('## ')) break;
    if (line.startsWith('### ')) {
      subsections.add([line]);
    } else if (subsections.isNotEmpty) {
      subsections.last.add(line);
    }
  }
  return [
    for (final subsection in subsections)
      if (subsection.join('\n').trimRight().isNotEmpty)
        subsection.join('\n').trimRight(),
  ];
}

/// [body] with its [kAdjudicationLogHeading] section removed.
String _withoutAdjudicationLog(String body) {
  final lines = const LineSplitter().convert(body);
  final start = lines.indexOf(kAdjudicationLogHeading);
  if (start < 0) return body;
  final tail = lines
      .sublist(start + 1)
      .skipWhile((line) => !line.startsWith('## '))
      .toList();
  return [...lines.sublist(0, start), ...tail].join('\n');
}

/// The verifier's brief — bounded, self-contained, and explicit that a judgment
/// is EVIDENCE and never fact.
///
/// Exposed so a test reads the exact prose the station sends (the A19 trap: a
/// contract the prompt never states is a contract nobody is held to).
String buildDesignVerifyPrompt({
  required Bead bead,
  required Map<String, String> documents,
  required List<DesignFinding> findings,
  required int round,
}) {
  final b = StringBuffer()
    ..writeln('# Design round $round — VERIFY')
    ..writeln()
    ..writeln(
      'You are the VERIFIER of an adversarial design round. Four judges read '
      'the document below through four different lenses and raised the '
      'findings listed after it. Each judgment is EVIDENCE, NEVER FACT: a '
      'judge argues, it does not rule. Your job is to CONFIRM or REFUTE every '
      'finding against the document, the tree and the rulings the bead names — '
      'and to FIX the ones you confirm.',
    )
    ..writeln()
    ..writeln('## The work bead — the rulings this round is held to')
    ..writeln(PackagedAssetLoader.beadBlock(bead))
    ..writeln()
    ..writeln('## The document(s) under review');
  for (final entry in documents.entries) {
    b
      ..writeln()
      ..writeln('### `${entry.key}`')
      ..writeln('<<<DOCUMENT ${entry.key}')
      ..writeln(entry.value.trimRight())
      ..writeln('DOCUMENT>>>');
  }
  b
    ..writeln()
    ..writeln('## The judges\' findings — ${findings.length} to adjudicate')
    ..writeln();
  for (final finding in findings) {
    b.writeln(
      '- `${finding.key}` [${finding.severity}] — ${finding.claim}\n'
      '  - the judge\'s receipt: ${finding.receipt}',
    );
  }
  b
    ..writeln()
    ..writeln('## How to adjudicate')
    ..writeln(
      '- `CONFIRMED-FIXED` — the finding is real AND your revised document '
      'fixes it. Say what you changed.\n'
      '- `REFUTED` — the finding is wrong. Say WHY, with your own receipt: the '
      'judge\'s rationale does not make it true.\n'
      '- `$kDesignVerdictOpen` — the finding is real and you cannot fix it '
      'here (it needs a decision the bead does not make, or work outside this '
      'document). Only these block the round, so use it deliberately.',
    )
    ..writeln(
      'Adjudicate EVERY finding exactly once, keeping its lane, id and '
      'severity. Do not invent findings, and do not merge two into one.',
    )
    ..writeln()
    ..writeln('## Your answer')
    ..writeln(
      'Answer with STRICT JSON and nothing else — no prose before or after:',
    )
    ..writeln(
      '{"documents":{${documents.keys.map((path) => '"$path":"<the COMPLETE revised body>"').join(',')}},'
      '"adjudications":[{"lane":"<judge lane>","findingId":"<id>",'
      '"finding":"<the finding restated>","severity":"<BLOCKER|MAJOR|MINOR>",'
      '"verdict":"<${kDesignVerdicts.join('|')}>","why":"<your receipt>"}]}',
    )
    ..writeln(
      'Each `documents` value is the WHOLE file after your fixes, not a patch '
      'and not an excerpt — it REPLACES the file on disk. Name no other file. '
      'Do NOT write an adjudication log into the document: the station appends '
      'it from your `adjudications`.',
    );
  return b.toString();
}

/// The DESIGN review circuit (id [kDesignReviewCircuitId]) — the docs
/// committee's shape with the judges and the verifier in place of its single
/// critic:
///
///     clear-critique → pin-diff → { 3 deterministic gates + 4 judges }
///                    → design-verify → route
///
/// The three gates are the docs committee's own, copied step id for step id so
/// the two circuits cannot drift; the four judges are ordinary `critic` lanes
/// selected by `params['rubric']`, so they write the same round-fresh verdicts
/// through the same transport. [kDesignVerifyStep] joins ALL SEVEN — a
/// mechanical gate's F short-circuits it, and a judge that did not report fails
/// it closed — and `route` joins the verifier ALONE: `critics` and `gating` are
/// both [kDesignVerifyStep], so the shared matrix hard-blocks on exactly one
/// thing, a finding that survived verification.
const Circuit kDesignReviewCircuit = Circuit(
  id: kDesignReviewCircuitId,
  terminalStepId: 'route',
  steps: [
    CapabilityStep(
      stepId: kClearCritiqueStep,
      capabilityId: kClearCritiqueStep,
    ),
    CapabilityStep(
      stepId: kPinDiffStep,
      capabilityId: kPinDiffStep,
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: kCitationPathsRubric,
      capabilityId: kDocsCheckCapabilityId,
      params: {'rubric': kCitationPathsRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kTerminologyBanRubric,
      capabilityId: kDocsCheckCapabilityId,
      params: {'rubric': kTerminologyBanRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kSectionStructureRubric,
      capabilityId: kDocsCheckCapabilityId,
      params: {'rubric': kSectionStructureRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kRulingAdherenceRubric,
      capabilityId: 'critic',
      params: {'rubric': kRulingAdherenceRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kOrderingAndRollbackRubric,
      capabilityId: 'critic',
      params: {'rubric': kOrderingAndRollbackRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kFoldFidelityAndOpsRubric,
      capabilityId: 'critic',
      params: {'rubric': kFoldFidelityAndOpsRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kCiteVerificationRubric,
      capabilityId: 'critic',
      params: {'rubric': kCiteVerificationRubric},
      dependsOn: {kPinDiffStep},
    ),
    CapabilityStep(
      stepId: kDesignVerifyStep,
      capabilityId: kDesignVerifyStep,
      // LITERAL set (a const context cannot splat a list into a set literal);
      // a test asserts it equals `kDesignCommitteeRubrics.toSet()` so the two
      // can never drift.
      dependsOn: {
        kCitationPathsRubric,
        kTerminologyBanRubric,
        kSectionStructureRubric,
        kRulingAdherenceRubric,
        kOrderingAndRollbackRubric,
        kFoldFidelityAndOpsRubric,
        kCiteVerificationRubric,
      },
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {kDesignVerifyStep},
      params: {
        // The verifier is the committee's ONE voice to the route: it has
        // already adjudicated every judge finding, so a judge's letter must
        // never reach the matrix a second time.
        'critics': kDesignVerifyStep,
        'gating': kDesignVerifyStep,
        // The stage the SHADOW receipt is filed under (bead `pow-1nl.1.1`); a
        // design diff is still a diff, and this route's matrix never reads it.
        kCommitteeSelectionStageParam: 'code_review',
      },
    ),
  ],
);

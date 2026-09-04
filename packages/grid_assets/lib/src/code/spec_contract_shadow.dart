/// The SHADOW measurement of the spec's record grammar.
///
/// Runs [parseSpecContract] over a corpus of specs that ALREADY SHIPPED through
/// the four spec critics under the PRE-CHANGE contract, and renders what the
/// stronger parser would have said about them. Every finding on a corpus entry
/// is, by construction, a would-have-blocked case the old gate did not raise —
/// the honest measure of what the contract COSTS, not of what the critics miss.
///
/// Nothing here ROUTES: no critic is removed, skipped or made conditional by
/// this library, and any later lane selection composes through the tree's step
/// surface, never through a parser. Measurement first, selection never on this
/// evidence alone.
///
/// ## Beside `search/search_recall.dart` — what is shared, and what is not
///
/// This pack already owns a retained-corpus measurement: `search_recall.dart`
/// scores semantic search against a versioned fixture set. That library and
/// this one are deliberately the same SHAPE — a retained corpus, a pure
/// evaluate/render step, and a runner behind a thin `tool/` CLI that is
/// read-only by default and writes only under an explicit record flag. That
/// shape is how this pack keeps a measurement honest and reviewable; neither
/// library invented it, and a third measurement should adopt it too.
///
/// The one MECHANISM that shape needs is shared outright rather than rewritten:
/// both record through [recordArtifact], the pack's single owner of the
/// temp-file-plus-rename discipline, and `spec_contract_shadow_test.dart`
/// fences that ownership against a second rename site in `lib/`.
///
/// The rest is NOT shared, because each half differs in kind and merging them
/// would buy a parameter for every caller and clarity for none:
///
/// - **The corpus.** `RecallSet.fromJsonString` decodes one versioned JSON
///   document of query/expected-id ROWS and validates it field by field. This
///   corpus is a manifest plus, per bead, two retained Markdown fields kept
///   VERBATIM, because the input under measurement IS prose — a row decoder
///   has nothing to say about it, and normalising it would destroy the very
///   bytes the parser is being measured on.
/// - **The measurement.** `evaluateRecall` needs a live subprocess seam
///   (`ProcessRunner`), because a search score does not exist until the vended
///   command has run. [renderSpecContractShadowReport] is PURE: the parser it
///   measures is a function in this same package, so the report is a total
///   function of the retained bytes and never shells out. There is no seam to
///   share when one side has no process to inject.
/// - **What the record flag MEANS.** `--record-baseline` rewrites the recall
///   corpus's OWN baseline, and only after a green run, so a red run can never
///   bless itself. `--record` here rewrites a DERIVED report that no later run
///   reads back as input, so it needs no green-run guard and its read-only mode
///   is a plain equality check against the rendered report rather than a
///   pass/fail judgement about the thing measured.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../io/recorded_artifact.dart';
import 'specify.dart';

/// The directory, relative to the package root, holding the retained corpus.
const String kSpecCorpusDir = 'test/fixtures/spec_corpus';

/// The generated report's path, relative to the package root.
const String kSpecContractShadowReport = 'doc/spec-contract-shadow.md';

/// One retained spec and its recorded outcome.
class SpecCorpusEntry {
  /// Creates a corpus entry.
  const SpecCorpusEntry({
    required this.bead,
    required this.title,
    required this.closedAt,
    required this.outcome,
    required this.acceptance,
    required this.design,
  });

  /// The bead the spec was written into.
  final String bead;

  /// The bead's title, for provenance.
  final String title;

  /// When the bead closed — the proof the spec predates this grammar.
  final String closedAt;

  /// What became of the bead under the PRE-CHANGE contract (`shipped`).
  final String outcome;

  /// The retained acceptance field, verbatim.
  final String acceptance;

  /// The retained design field, verbatim.
  final String design;
}

/// Which judgement lane's rubric already asks for a rule — the DECLARED
/// overlap, anchored by a clause quoted verbatim from that rubric.
class LaneOverlap {
  /// Creates an overlap claim.
  const LaneOverlap({
    required this.rule,
    required this.rubric,
    required this.clause,
  });

  /// The deterministic rule.
  final SpecContractRule rule;

  /// The rubric id that already asks for it, or `''` when none does.
  final String rubric;

  /// The clause, VERBATIM from that rubric — proven a substring in test.
  final String clause;
}

/// The overlap table: for every [SpecContractRule], the judgement lane that
/// already asks for the same thing in prose, or `''` where the rule is
/// structure NO lane states.
///
/// Every non-empty [LaneOverlap.clause] is asserted to be a literal substring
/// of the packaged rubric in `spec_contract_shadow_test.dart`, so "this lane
/// already asks for it" can never be invented.
const List<LaneOverlap> kSpecContractLaneOverlap = [
  LaneOverlap(
    rule: SpecContractRule.acceptanceRecord,
    rubric: '',
    clause: '',
  ),
  LaneOverlap(
    rule: SpecContractRule.acceptanceIdDuplicate,
    rubric: '',
    clause: '',
  ),
  LaneOverlap(
    rule: SpecContractRule.acceptanceIdNotContiguous,
    rubric: '',
    clause: '',
  ),
  LaneOverlap(rule: SpecContractRule.stepTitle, rubric: '', clause: ''),
  LaneOverlap(
    rule: SpecContractRule.stepField,
    rubric: 'plan-completeness',
    clause: 'the exact test command with expected output',
  ),
  LaneOverlap(
    rule: SpecContractRule.stepPath,
    rubric: 'plan-completeness',
    clause: 'an exact file path from the repo root',
  ),
  LaneOverlap(
    rule: SpecContractRule.stepCommit,
    rubric: 'plan-completeness',
    clause: 'a conventional-commit message',
  ),
  LaneOverlap(rule: SpecContractRule.touchRecord, rubric: '', clause: ''),
  LaneOverlap(
    rule: SpecContractRule.decisionRecord,
    rubric: 'decision-alignment',
    clause: 'the canonical `<repo>#<slug>` identity',
  ),
  LaneOverlap(
    rule: SpecContractRule.decisionSectionSilent,
    rubric: 'decision-alignment',
    clause: 'never grade the lane clean on a crashed lookup',
  ),
  LaneOverlap(
    rule: SpecContractRule.validationRecord,
    rubric: 'acceptance-testability',
    clause: 'the exact command and its expected result',
  ),
  LaneOverlap(
    rule: SpecContractRule.validationUnknownCriterion,
    rubric: 'acceptance-testability',
    clause: 'item mapped to no criterion',
  ),
  LaneOverlap(
    rule: SpecContractRule.validationCoverage,
    rubric: 'acceptance-testability',
    clause: 'an unmapped criterion caps at C',
  ),
];

/// One claim the parser CANNOT decide, anchored by a clause quoted verbatim
/// from the judgement lane that owns it.
class SemanticResidue {
  /// Creates a residue claim.
  const SemanticResidue({
    required this.rubric,
    required this.claim,
    required this.clause,
  });

  /// The rubric id that owns the judgement.
  final String rubric;

  /// What that lane uniquely catches, in one line.
  final String claim;

  /// The clause, VERBATIM from that rubric — proven a substring in test.
  final String clause;
}

/// What stays INFERENCE after the record grammar lands.
///
/// Each clause is asserted verbatim in test, so the residue is QUOTED from the
/// lanes rather than asserted about them.
const List<SemanticResidue> kSpecContractSemanticResidue = [
  SemanticResidue(
    rubric: 'acceptance-testability',
    claim: 'a mapped command can still be vacuous — the parser sees that a '
        'command IS there, never whether it can fail',
    clause: 'a validation item that passes even',
  ),
  SemanticResidue(
    rubric: 'plan-completeness',
    claim: 'a step can carry all five labeled fields and still leave a '
        'judgment call to the builder',
    clause: 'A judgment call is any step where the builder must',
  ),
  SemanticResidue(
    rubric: 'decision-alignment',
    claim: 'a citation can RESOLVE and still be applied backwards',
    clause: 'the spec cites a constraint it then applies',
  ),
  SemanticResidue(
    rubric: 'coherence',
    claim: 'a well-formed plan can parallel-build beside a concept the packs '
        'already own — no record form can see a duplicate abstraction',
    clause: 'A coherent spec extends what is there',
  ),
];

/// Reads the retained corpus rooted at [root] (the package root).
///
/// Throws when the manifest or any retained field is missing: the corpus is
/// EVIDENCE, and a silently short corpus would understate the cost it measures.
List<SpecCorpusEntry> readSpecCorpus(String root) {
  final dir = p.join(root, kSpecCorpusDir);
  final manifest =
      jsonDecode(File(p.join(dir, 'corpus.json')).readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final entry in manifest['entries']! as List)
      if (entry as Map<String, dynamic> case final row)
        SpecCorpusEntry(
          bead: row['bead']! as String,
          title: row['title']! as String,
          closedAt: row['closedAt']! as String,
          outcome: row['outcome']! as String,
          acceptance: File(
            p.join(dir, '${row['bead']}.acceptance.md'),
          ).readAsStringSync(),
          design: File(
            p.join(dir, '${row['bead']}.design.md'),
          ).readAsStringSync(),
        ),
  ];
}

/// The report, rendered from [corpus] plus the declared tables. PURE — the
/// only thing that writes it is [runSpecContractShadow].
String renderSpecContractShadowReport(List<SpecCorpusEntry> corpus) {
  final out = StringBuffer();
  final totals = <SpecContractRule, int>{
    for (final rule in SpecContractRule.values) rule: 0,
  };
  final rows =
      <
        ({
          SpecCorpusEntry entry,
          List<SpecContractFinding> findings,
          List<String> phantomSteps,
        })
      >[
        for (final entry in corpus)
          if (parseSpecContract(
                acceptance: entry.acceptance,
                design: entry.design,
              )
              case final parsed)
            (
              entry: entry,
              findings: parsed.findings,
              phantomSteps: _phantomStepOpeners(entry, parsed.contract),
            ),
      ];
  for (final row in rows) {
    for (final finding in row.findings) {
      totals[finding.rule] = totals[finding.rule]! + 1;
    }
  }

  out
    ..writeln('# The spec record grammar, measured in shadow')
    ..writeln()
    ..writeln(
      'GENERATED — `dart run tool/spec_contract_shadow.dart --record` is the '
      'only writer, and `test/spec_contract_shadow_test.dart` pins this file '
      'to its regeneration. Do not edit by hand.',
    )
    ..writeln()
    ..writeln(
      'This runs the record grammar (`parseSpecContract`) over '
      '${corpus.length} specs that ALREADY SHIPPED through the four spec '
      'critics under the PRE-CHANGE contract, and reports what the stronger '
      'parser would have said. Nothing here routes: the committee lane set is '
      'unchanged, and no critic is removed, skipped or made conditional on '
      'this evidence.',
    )
    ..writeln()
    ..writeln('## The corpus')
    ..writeln()
    ..writeln('| bead | closed | outcome | findings | rules tripped |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final row in rows) {
    final tripped =
        (row.findings.map((finding) => finding.rule.name).toSet().toList()
          ..sort());
    out.writeln(
      '| `${row.entry.bead}` | ${row.entry.closedAt} | ${row.entry.outcome} '
      '| ${row.findings.length} | ${tripped.isEmpty ? '—' : tripped.join(', ')} |',
    );
  }
  final total = rows.fold(0, (sum, row) => sum + row.findings.length);
  final clean = rows.where((row) => row.findings.isEmpty).length;
  out
    ..writeln()
    ..writeln(
      '$total findings across ${corpus.length} shipped specs; $clean parse '
      'clean under the new grammar.',
    )
    ..writeln()
    ..writeln('## Findings per rule, and the lane that already asks for it')
    ..writeln()
    ..writeln('| rule | corpus findings | lane that already asks | clause quoted from that rubric |')
    ..writeln('| --- | --- | --- | --- |');
  for (final overlap in kSpecContractLaneOverlap) {
    out.writeln(
      '| `${overlap.rule.name}` | ${totals[overlap.rule]} '
      '| ${overlap.rubric.isEmpty ? '— (no lane states it)' : '`${overlap.rubric}`'} '
      '| ${overlap.clause.isEmpty ? '—' : '"${overlap.clause}"'} |',
    );
  }
  out
    ..writeln()
    ..writeln(
      'Every quoted clause above is asserted to be a literal substring of the '
      'packaged rubric in test, so an overlap claim can never be invented.',
    );

  final phantoms = rows.where((row) => row.phantomSteps.isNotEmpty).toList();
  out
    ..writeln()
    ..writeln('## Deterministic false positives, measured')
    ..writeln()
    ..writeln(
      'One class is real, and it is reported rather than fixed. The '
      'step-opener language is RATIFIED and deliberately unchanged by this '
      'work — the new strictness lands on what a step CONTAINS, never on '
      'which openers count — and that language matches `<digits>.` or '
      '`<digits>)` at the start of ANY line, including an INDENTED prose '
      'continuation such as "(line / 107) and before `kSpecReviewCircuit`:". '
      'Before the record grammar that only answered a boolean ("does this '
      'plan have any ordinal-led step at all"), so an indented prose ordinal '
      'cost nothing. The record parser turns every match into a STEP, so such '
      'a line becomes a phantom step and then reports the five labeled fields '
      'it was never going to carry.',
    )
    ..writeln();
  if (phantoms.isEmpty) {
    out.writeln('No phantom step openers in this corpus.');
  } else {
    out
      ..writeln('| bead | phantom steps | first phantom opener |')
      ..writeln('| --- | --- | --- |');
    for (final row in phantoms) {
      out.writeln(
        '| `${row.entry.bead}` | ${row.phantomSteps.length} '
        '| `${row.phantomSteps.first.trim()}` |',
      );
    }
    out
      ..writeln()
      ..writeln(
        'Every phantom opener above is INDENTED, which is the mechanical '
        'signature of a continuation line — a real step opens at column 0. '
        'That is the shape a follow-up would narrow on, and narrowing it '
        'changes a ratified rule, so it is measured here and left alone.',
      );
  }

  out
    ..writeln()
    ..writeln('## The semantic residue — what no record form can decide')
    ..writeln()
    ..writeln('| lane | what it uniquely catches | clause quoted from that rubric |')
    ..writeln('| --- | --- | --- |');
  for (final residue in kSpecContractSemanticResidue) {
    out.writeln(
      '| `${residue.rubric}` | ${residue.claim} | "${residue.clause}" |',
    );
  }
  out
    ..writeln()
    ..writeln('## What this corpus does and does NOT establish')
    ..writeln()
    ..writeln(
      'Every entry PREDATES the grammar. Its architect was never told the '
      'record forms, so each finding above measures MIGRATION COST — the '
      'distance between what the old brief asked for and what the new one '
      'does — and not critic redundancy. A high count on a rule says the old '
      'brief was silent about it, not that a lane was failing to catch it. '
      'Some counts are contract FRICTION rather than sloppiness — a gate-only '
      'final step writing `Commit: none` is a deliberate, readable choice the '
      'new grammar refuses — and those are exactly the calls a follow-up '
      'should revisit with the numbers above in hand.',
    )
    ..writeln()
    ..writeln(
      'The overlap column is therefore the weaker claim it looks like: it '
      'says a lane ASKS for the same property in prose, not that the lane '
      'RELIABLY caught it — these specs passed those lanes carrying the '
      'deviations counted above. Establishing redundancy needs a corpus '
      'written UNDER the new brief, where a deterministic finding and a lane '
      'verdict are answering the same question about the same document.',
    )
    ..writeln()
    ..writeln(
      'So: no critic may be removed, skipped or made conditional on this '
      'evidence. Structure and referential integrity move to code; whether a '
      'test PROVES behaviour, whether a plan is COHERENT, and whether a '
      'decision is INTERPRETED correctly stay inference, and the residue '
      'table above is quoted from the lanes that own them.',
    );
  return out.toString();
}

/// The opener LINES of [contract]'s steps that are INDENTED in [entry]'s
/// design — the phantom-step class, whose mechanical signature is that a real
/// step opener starts at column 0 and a prose continuation does not.
List<String> _phantomStepOpeners(SpecCorpusEntry entry, SpecContract contract) {
  final lines = entry.design.split('\n');
  return [
    for (final step in contract.steps)
      if (step.line - 1 < lines.length &&
          lines[step.line - 1].startsWith(RegExp(r'[ \t]')))
        lines[step.line - 1],
  ];
}

/// Regenerates or CHECKS [kSpecContractShadowReport] under [root].
///
/// Read-only by default — it returns 0 exactly when the checked-in report
/// already equals the rendered one, and 1 otherwise. [record] writes the
/// rendered report through a `.tmp` rename.
Future<int> runSpecContractShadow({
  required String root,
  required bool record,
}) async {
  try {
    final rendered = renderSpecContractShadowReport(readSpecCorpus(root));
    final file = File(p.join(root, kSpecContractShadowReport));
    if (record) {
      await recordArtifact(file, rendered);
      stdout.writeln('recorded ${file.path}');
      return 0;
    }
    if (file.existsSync() && await file.readAsString() == rendered) return 0;
    stderr.writeln(
      'spec-contract-shadow: ${file.path} is stale — rerun with --record',
    );
    return 1;
  } on Object catch (error) {
    stderr.writeln('spec-contract-shadow: $error');
    return 1;
  }
}

// The six VIABILITY rows of the filing contract (AC-1 … AC-8).
//
// Filing used to check that a field was PRESENT, never that it was VIABLE: a
// bead passed with a validation_plan that could not parse, acceptance criteria
// that went stale on the next release wave, and prose that broke the anchor
// extractor. Each of these probes pins one of those rounds.
//
// Offline by construction. Every seam is a Fake — no shell is spawned, no
// store is read, no register is indexed.
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' show SubstationScope;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/filing_evidence.dart';
import '../support/package_root.dart';

/// A bead that passes the four PRESENCE rows, so a probe below is only ever
/// about the viability row it perturbs.
Bead _filed({
  String id = 'pow-filed',
  String title = 'A filed bead',
  String description = 'A concrete brief',
  String design = '',
  String acceptanceCriteria = '- [ ] checked',
  String notes = '',
  String plan = 'dart test',
}) => Bead(
  id: id,
  title: title,
  issueType: IssueType.task,
  description: description,
  design: design,
  acceptanceCriteria: acceptanceCriteria,
  notes: notes,
  metadata: {'validation_plan': plan},
);

/// The row [requirement] of [bead]'s report under [evidence].
FilingRequirementRow _row(
  FilingRequirement requirement,
  Bead bead,
  FilingEvidence evidence,
) => const FilingContract()
    .evaluate(bead, const [], evidence: evidence)
    .requirements
    .singleWhere((row) => row.requirement == requirement);

/// The evidence a [SystemFilingEvidenceSource] composed over Fakes collects
/// for [bead].
Future<FilingEvidence> _collected(
  Bead bead, {
  required SystemFilingEvidenceSource source,
  String storeRoot = '/work/power_station',
}) => source.collect(bead: bead, storeRoot: storeRoot);

/// A [DecisionIndexSource] answering with [entries] over one complete surface.
DecisionIndexSource _decisionIndex(
  List<({String identity, String slug})> entries, {
  EvidenceState state = EvidenceState.complete,
  String error = '',
  List<String>? surfacesSeen,
}) => (workspaceDir, surfaces, workBead) async {
  surfacesSeen?.addAll(surfaces);
  return DecisionGatherEvidence(
    decisionEntries: {
      for (final (index, entry) in entries.indexed)
        'entry:$index': DecisionEntryEvidence(
          identity: entry.identity,
          originRegister: entry.identity.split('#').first,
          originPath: 'docs/decisions',
          slug: entry.slug,
          status: 'accepted',
          surfaces: const ['packages/**'],
          entryPath: 'docs/decisions/${entry.slug}.md',
          body: BoundedEvidence(
            id: 'decision:${entry.slug}',
            source: 'docs/decisions/${entry.slug}.md',
            snippet: 'the entry body',
            digest: 'deadbeef',
            state: EvidenceState.complete,
          ),
        ),
    },
    decisionLookups: [
      for (final surface in surfaces)
        DecisionSurfaceEvidence(
          id: 'lookup:$surface',
          surface: surface,
          command: 'decisions index --surface $surface',
          state: state,
          error: error,
          decisions: [
            for (var index = 0; index < entries.length; index++) 'entry:$index',
          ],
        ),
    ],
  );
};

/// The captured corpus, as beads.
///
/// It is the COMPATIBILITY control: a bead that filed fine before the six
/// viability rows must go on filing fine after them, or the rows are refusing
/// real work rather than bad work.
List<Bead> _compatibilityCorpus() {
  final raw =
      jsonDecode(
            File(
              p.join(
                packageRoot(),
                'test',
                'fixtures',
                'filing_compatibility.json',
              ),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final provenance = raw['provenance']! as Map<String, dynamic>;
  expect(provenance['captured'], '2026-09-13');
  expect(provenance['commands'], [
    "BD_JSON_ENVELOPE=1 bd query 'id=pow-p8il' --all --json",
    "BD_JSON_ENVELOPE=1 bd query 'id=pow-wtyb' --all --json",
    "BD_JSON_ENVELOPE=1 bd query 'id=pow-q6bq' --all --json",
  ]);
  return [
    for (final record in (raw['beads']! as List).cast<Map<String, dynamic>>())
      Bead(
        id: record['id']! as String,
        title: record['title']! as String,
        issueType: IssueType.task,
        description: record['description']! as String,
        design: record['design']! as String,
        acceptanceCriteria: record['acceptance_criteria']! as String,
        notes: record['notes']! as String,
        metadata: {'validation_plan': record['validation_plan']! as String},
      ),
  ];
}

/// The prefixes the corpus's own org mints ids under.
const Set<String> _orgPrefixes = {'pow', 'tg', 'tgdog', 'space', 'lunar'};

/// Dash is the PORTABILITY reference shell. It ships at `/bin/dash` on Linux
/// and on current macOS, but a host without it has not checked portability —
/// which is a fact about the host, not about the plan, so the leg that needs
/// it says so rather than failing.
final bool _dashAvailable = () {
  try {
    return Process.runSync(kPortabilityShell, ['-n', '-c', 'true']).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}();

/// The REAL non-executing parse of [bead]'s plan under [shell], run from the
/// package root. `-n` parses and never executes.
PlanParse _realParse(Bead bead, String shell) {
  final plan = BeadTextField.validationPlan.read(bead).trim();
  final parsed = Process.runSync(shell, [
    '-n',
    '-c',
    '( $plan )',
  ], workingDirectory: packageRoot());
  return parsed.exitCode == 0
      ? const PlanParsed()
      : PlanRefused(
          exitCode: parsed.exitCode,
          diagnostic: '${parsed.stderr}'.trim(),
        );
}

void main() {
  test('filing viability refuses lane shell syntax with exact constructs', () {
    // AC-1, incident one: a `#` inside a quoted command substitution. Under
    // the lane shell the `#` opens a comment that swallows the closing paren,
    // so the whole gating line parse-dies and the round reads as a harness
    // throttle rather than as a bad plan.
    const hashed =
        r'''test "$(bd show pow-x --json | grep -c '# heading')" -gt 0''';
    final hashRow = _row(
      FilingRequirement.validationPlanSyntax,
      _filed(plan: hashed),
      const FilingEvidence(
        laneParse: PlanRefused(
          exitCode: 2,
          diagnostic:
              'sh: -c: line 1: unexpected EOF while looking for '
              'matching `)\'',
        ),
      ),
    );
    expect(hashRow.passed, isFalse);
    expect(
      hashRow.detail,
      contains(r'''$(bd show pow-x --json | grep -c '# heading')'''),
    );
    expect(hashRow.detail, contains(kSyntaxCorrection));

    // AC-1, incident two: an apostrophe carried in from design prose into a
    // single-quoted program. The reason is invisible in the bead unless the
    // refusal names the WORD.
    final apostropheRow = _row(
      FilingRequirement.validationPlanSyntax,
      _filed(plan: "echo 'station lane's SDK'"),
      const FilingEvidence(
        laneParse: PlanRefused(
          exitCode: 2,
          diagnostic: 'sh: -c: line 1: unexpected EOF',
        ),
      ),
    );
    expect(apostropheRow.passed, isFalse);
    expect(apostropheRow.detail, contains("lane's"));
    expect(apostropheRow.detail, contains(kSyntaxCorrection));

    // A plan the lane shell accepts passes, and a BLANK plan is the presence
    // row's to own — this contract mints no second completeness predicate.
    expect(
      _row(
        FilingRequirement.validationPlanSyntax,
        _filed(),
        const FilingEvidence(laneParse: PlanParsed()),
      ).passed,
      isTrue,
    );
    expect(
      _row(
        FilingRequirement.validationPlanSyntax,
        _filed(plan: '  '),
        const FilingEvidence.unconsulted(),
      ).passed,
      isTrue,
    );

    // An unspawnable shell is UNCHECKED, not a verdict about the plan.
    final unavailable = _row(
      FilingRequirement.validationPlanSyntax,
      _filed(),
      const FilingEvidence(laneParse: PlanUnavailable('sh is not on PATH')),
    );
    expect(unavailable.passed, isFalse);
    expect(unavailable.detail, contains('sh is not on PATH'));
    expect(unavailable.detail, contains(kRestoreEvidenceDetail));
  });

  test('filing viability refuses dash-only incompatibility', () async {
    // AC-2: the lane shell (bash on a mac) parses process substitution; CI's
    // sh is dash and dies at PARSE, with no log and no return code.
    const plan = 'cat <(printf x)';
    final probe = FakeValidationPlanProbe(
      outcomes: const {
        kLaneShell: PlanParsed(),
        kPortabilityShell: PlanRefused(
          exitCode: 2,
          diagnostic: 'dash: 1: Syntax error: "(" unexpected',
        ),
      },
    );

    final evidence = await _collected(
      _filed(plan: plan),
      source: SystemFilingEvidenceSource(probe: probe),
    );

    final row = _row(
      FilingRequirement.validationPlanPortability,
      _filed(plan: plan),
      evidence,
    );
    expect(row.passed, isFalse);
    expect(row.detail, contains('<(printf x)'));
    expect(row.detail, contains(kPortabilityCorrection));
    // Syntax is silent: the lane shell accepted it, and naming one defect
    // twice tells a refiner nothing new.
    expect(
      _row(
        FilingRequirement.validationPlanSyntax,
        _filed(plan: plan),
        evidence,
      ).passed,
      isTrue,
    );
    expect(
      [for (final call in probe.calls) call.shell],
      [kLaneShell, kLaneShell, kPortabilityShell],
    );

    // Dash is never asked about a plan the lane shell already refused.
    final refusedLane = await _collected(
      _filed(plan: plan),
      source: SystemFilingEvidenceSource(
        probe: FakeValidationPlanProbe(
          outcomes: const {
            kLaneShell: PlanRefused(exitCode: 2, diagnostic: 'unexpected EOF'),
          },
        ),
      ),
    );
    expect(refusedLane.portabilityParse, isNull);
    expect(
      _row(
        FilingRequirement.validationPlanPortability,
        _filed(plan: plan),
        refusedLane,
      ).passed,
      isTrue,
    );
  });

  test('filing viability refuses absolute anchors', () {
    const windows = r'C:\work\power_station\lib\src\x.dart';
    final bead = _filed(
      description:
          'The receipt landed at /tmp/round/receipt.md and the mirror at '
          '$windows.',
      // The composing grid home is an absolute DIRECTORY a bead names
      // legitimately — the negative control that keeps this row from refusing
      // the one rooted path that is not a citation.
      design:
          'Run from /Users/nico/development/engineering.memento/power_station '
          'against `lib/src/filing/filing_contract.dart`.',
    );

    final row = _row(
      FilingRequirement.repoRelativePaths,
      bead,
      const FilingEvidence.unconsulted(),
    );

    expect(row.passed, isFalse);
    expect(row.detail, contains('/tmp/round/receipt.md'));
    expect(row.detail, contains(windows));
    expect(row.detail, isNot(contains('engineering.memento/power_station ')));
    expect(row.detail, isNot(contains('lib/src/filing/filing_contract.dart')));
    expect(row.detail, contains(kRepoRelativeCorrection));

    expect(
      _row(
        FilingRequirement.repoRelativePaths,
        _filed(description: 'Touch `lib/src/filing/filing_text.dart`.'),
        const FilingEvidence.unconsulted(),
      ).passed,
      isTrue,
    );
  });

  test('filing viability resolves attached-store bead ids', () async {
    const tg = SubstationScope(
      name: 'the_grid',
      root: '/work/the_grid',
      prefix: 'tg',
    );
    const tgdog = SubstationScope(
      name: 'tgdog',
      root: '/work/tgdog',
      prefix: 'tgdog',
    );
    final bead = _filed(
      description:
          'Blocked by: tg-89y8. Read-only across stores; the AC-2 record '
          'stands. Also tgdog-s1 and tg-gone.',
      notes: 'A utf-8 payload is not an id.',
    );
    final store = FakeSubstationBeadSource(
      beadsByRoot: {
        '/work/power_station': const [Bead(id: 'pow-filed')],
        '/work/the_grid': const [Bead(id: 'tg-89y8')],
        // tgdog-s1 lives ONLY in the second attached store: a union that
        // stopped at the first would call it unminted.
        '/work/tgdog': const [Bead(id: 'tgdog-s1')],
      },
    );

    final evidence = await _collected(
      bead,
      source: SystemFilingEvidenceSource(
        probe: FakeValidationPlanProbe(),
        beads: store,
        attached: const [tg, tgdog],
      ),
    );

    // The longest-prefix rule: `tgdog-s1` is a tgdog id, never `tg` + `dog-s1`.
    expect(evidence.attachedPrefixes, {'pow', 'tg', 'tgdog'});
    expect(store.reads, [
      '/work/power_station',
      '/work/the_grid',
      '/work/tgdog',
    ]);

    final row = _row(FilingRequirement.beadReferences, bead, evidence);
    expect(row.passed, isFalse);
    expect(row.detail, contains('tg-gone'));
    expect(row.detail, isNot(contains('tg-89y8')));
    expect(row.detail, isNot(contains('tgdog-s1')));
    // Hyphenated prose and acceptance records are not ids under any prefix.
    expect(row.detail, isNot(contains('AC-2')));
    expect(row.detail, isNot(contains('utf-8')));
    expect(row.detail, contains(kBeadReferenceCorrection));

    // A bead citing nobody costs no read at all.
    final quiet = FakeSubstationBeadSource();
    expect(
      (await _collected(
        _filed(),
        source: SystemFilingEvidenceSource(
          probe: FakeValidationPlanProbe(),
          beads: quiet,
        ),
      )).beads,
      isNull,
    );
    expect(quiet.reads, isEmpty);

    // An INCOMPLETE union is unavailable evidence, never proof of absence.
    final broken = await _collected(
      bead,
      source: SystemFilingEvidenceSource(
        probe: FakeValidationPlanProbe(),
        beads: FakeSubstationBeadSource(
          beadsByRoot: const {},
          failFor: '/work/tgdog',
        ),
        attached: const [tg, tgdog],
      ),
    );
    final unchecked = _row(FilingRequirement.beadReferences, bead, broken);
    expect(unchecked.passed, isFalse);
    expect(unchecked.detail, contains('refused the read'));
    expect(unchecked.detail, contains(kRestoreEvidenceDetail));
    expect(unchecked.detail, isNot(contains(kBeadReferenceCorrection)));
  });

  test('filing viability refuses exact acceptance release versions', () {
    final row = _row(
      FilingRequirement.releaseVersions,
      _filed(
        acceptanceCriteria:
            '- [ ] AC-1 — grid_engine 0.3.2 is consumed by 2026-09-13',
      ),
      const FilingEvidence.unconsulted(),
    );
    expect(row.passed, isFalse);
    expect(row.detail, contains('0.3.2'));
    expect(row.detail, isNot(contains('2026')));
    expect(row.detail, contains(kReleaseVersionCorrection));

    // Ranges, dates and versions outside acceptance all pass.
    expect(
      _row(
        FilingRequirement.releaseVersions,
        _filed(
          description: 'Pin grid_engine 0.3.2 in the pubspec.',
          acceptanceCriteria:
              '- [ ] AC-1 — the floor is ^0.3.0 and the sdk is >=3.11.0 '
              '<4.0.0, checked on 2026-09-13',
        ),
        const FilingEvidence.unconsulted(),
      ).passed,
      isTrue,
    );
  });

  test('filing viability resolves recorded decisions', () async {
    final surfaces = <String>[];
    final bead = _filed(
      description:
          'Extends `power_station#approval-is-the-stamp-the-grid-approved-'
          'label-retires` and ADR-0008.',
      design: 'Touch `lib/src/filing/filing_contract.dart`.',
      notes: 'Option A1 is not a citation; neither is issue pr#256.',
    );
    final recorded = _decisionIndex([
      (
        identity:
            'power_station#approval-is-the-stamp-the-grid-approved-'
            'label-retires',
        slug: 'approval-is-the-stamp-the-grid-approved-label-retires',
      ),
      (
        identity: 'power_station#adr-0008-the-d-h-genesis-tree-doctrine',
        slug: 'adr-0008-the-d-h-genesis-tree-doctrine',
      ),
    ], surfacesSeen: surfaces);

    final evidence = await _collected(
      bead,
      source: SystemFilingEvidenceSource(
        probe: FakeValidationPlanProbe(),
        decisions: recorded,
      ),
    );

    // The bead's own file anchors are what the index is asked about, roster
    // qualified by the owning substation's name.
    expect(surfaces, ['power_station/lib/src/filing/filing_contract.dart']);
    final row = _row(FilingRequirement.decisionReferences, bead, evidence);
    expect(row.passed, isTrue, reason: row.detail);

    // A citation the register does not answer FAILS, naming it.
    final selfCiting = _filed(
      description:
          'This round records `power_station#filing-checks-viability`.',
    );
    final selfRow = _row(
      FilingRequirement.decisionReferences,
      selfCiting,
      await _collected(
        selfCiting,
        source: SystemFilingEvidenceSource(
          probe: FakeValidationPlanProbe(),
          decisions: recorded,
        ),
      ),
    );
    expect(selfRow.passed, isFalse);
    expect(selfRow.detail, contains('power_station#filing-checks-viability'));
    expect(selfRow.detail, contains(kDecisionReferenceCorrection));

    // With no file anchor the owning scope's README is the existence surface.
    final anchorless = <String>[];
    await _collected(
      _filed(description: 'Extends ADR-0008.'),
      source: SystemFilingEvidenceSource(
        probe: FakeValidationPlanProbe(),
        decisions: _decisionIndex(const [], surfacesSeen: anchorless),
      ),
    );
    expect(anchorless, ['power_station/README.md']);

    // A CRASHED index is unavailable evidence, never an empty union.
    final crashed = _row(
      FilingRequirement.decisionReferences,
      bead,
      await _collected(
        bead,
        source: SystemFilingEvidenceSource(
          probe: FakeValidationPlanProbe(),
          decisions: _decisionIndex(
            const [],
            state: EvidenceState.failed,
            error: 'exit 127: space: command not found',
          ),
        ),
      ),
    );
    expect(crashed.passed, isFalse);
    expect(crashed.detail, contains('command not found'));
    expect(crashed.detail, contains(kRestoreEvidenceDetail));
    expect(crashed.detail, isNot(contains(kDecisionReferenceCorrection)));

    // An UNWIRED index is the same posture: nobody looked.
    final unwired = _row(
      FilingRequirement.decisionReferences,
      bead,
      await _collected(
        bead,
        source: SystemFilingEvidenceSource(probe: FakeValidationPlanProbe()),
      ),
    );
    expect(unwired.passed, isFalse);
    expect(unwired.detail, contains(kRestoreEvidenceDetail));
  });

  test('filing report keeps one ten-row JSON schema', () {
    final report = const FilingContract().evaluate(
      _filed(),
      const [],
      evidence: viableEvidence(prefixes: const {'pow'}),
    );
    final json = report.toJson();
    final rows = (json['requirements']! as List).cast<Map<String, Object>>();

    expect(rows, hasLength(10));
    expect(
      [for (final row in rows) row['requirement']],
      [for (final requirement in FilingRequirement.values) requirement.wire],
    );
    for (final row in rows) {
      expect(row.keys.toSet(), {'requirement', 'passed', 'detail'});
      expect(row['detail'], isA<String>());
    }
    expect(report.passed, isTrue);
    expect(json['passed'], isTrue);

    // ONE failing viability row fails the whole report — the four presence
    // rows do not carry it alone.
    final refused = const FilingContract().evaluate(
      _filed(description: 'See /tmp/round/receipt.md.'),
      const [],
      evidence: viableEvidence(prefixes: const {'pow'}),
    );
    expect(refused.passed, isFalse);
    expect(
      refused.requirements
          .where((row) => !row.passed)
          .map((row) => row.requirement),
      [FilingRequirement.repoRelativePaths],
    );
  });

  test('filing compatibility corpus keeps three live beads passing', () {
    for (final bead in _compatibilityCorpus()) {
      // The plan is parsed by the REAL lane shell — an assumed parse would
      // prove nothing about whether these rows accept live plans. COMPLETE
      // fake catalogs stand in for the id and decision lookups: the live
      // database is never read here.
      final report = const FilingContract().evaluate(
        bead,
        const [],
        linkedBlockers: const {},
        evidence: FilingEvidence(
          attachedPrefixes: _orgPrefixes,
          laneParse: _realParse(bead, kLaneShell),
          portabilityParse: const PlanParsed(),
          beads: BeadIdsRead({
            for (final slice in beadIdReferences(bead, prefixes: _orgPrefixes))
              slice.text,
          }),
          decisions: DecisionsRead(
            identities: {
              for (final reference in decisionReferences(bead))
                if (reference.identity.isNotEmpty) reference.identity,
            },
            aliases: {
              for (final reference in decisionReferences(bead))
                if (reference.alias.isNotEmpty) reference.alias,
            },
          ),
        ),
      );

      expect(
        [
          for (final row in report.requirements)
            if (!row.passed) '${row.requirement.wire}: ${row.detail}',
        ],
        isEmpty,
        reason: bead.id,
      );
      expect(report.passed, isTrue, reason: bead.id);
    }
  });

  test(
    'filing compatibility corpus parses under the portability shell',
    skip: _dashAvailable
        ? null
        : 'requires $kPortabilityShell on PATH (absent on this host)',
    () {
      for (final bead in _compatibilityCorpus()) {
        expect(
          _realParse(bead, kPortabilityShell),
          isA<PlanParsed>(),
          reason: bead.id,
        );
      }
    },
  );
}

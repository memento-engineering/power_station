// The six VIABILITY rows of the filing contract, and the schema the CONTENT
// row joins them in: a bead passes filing only if what its fields HOLD can
// actually work, not merely because the field is there.
//
// Each row here retires one remembered rule that cost a round — a plan the
// gating lane cannot parse, a Bash-only plan that dies under CI's dash, an
// absolute path the anchor extractor turns into a FAILED record, an id nobody
// minted, an acceptance version that goes stale on the next release wave, and
// a citation of a decision the round itself creates.
//
// Offline by construction: every probe, catalog and index is a Fake, and the
// compatibility corpus is CHECKED IN bead text. No shell, no store, no clock.
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' show SubstationScope;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';
import 'filing_evidence_fakes.dart';

/// A filed bead whose four PRESENCE rows all pass, so any failure a test sees
/// is the viability row it is about.
Bead _bead({
  String title = 'a filed bead',
  String description = 'the work',
  String design = 'the chosen approach',
  String acceptanceCriteria = '- [ ] dart test passes',
  String notes = '',
  String validationPlan = 'dart test',
}) => Bead(
  id: 'pow-filed',
  title: title,
  issueType: IssueType.task,
  priority: 2,
  description: description,
  design: design,
  acceptanceCriteria: acceptanceCriteria,
  notes: notes,
  metadata: {'validation_plan': validationPlan},
);

FilingReport _report(Bead bead, FilingEvidence evidence) =>
    const FilingContract().evaluate(
      bead,
      const <BeadDependency>[],
      evidence: evidence,
    );

FilingRequirementRow _row(FilingReport report, FilingRequirement requirement) =>
    report.requirements.singleWhere((row) => row.requirement == requirement);

ValidationPlanParseResult _refused(String shell, String diagnostic) =>
    ValidationPlanParseResult(
      shell: shell,
      exitCode: 2,
      diagnostic: diagnostic,
    );

/// The evidence a live gather would produce for [plan] under a fake probe —
/// the seam proof, so these tests exercise the real gather and not only the
/// pure contract.
Future<FilingEvidence> _gathered(
  Bead bead, {
  required FakeValidationPlanProbe probe,
}) => SystemFilingEvidenceSource(
  probe: probe,
  // No scopes and no index: the plan rows are what this gather is for.
  catalog: const BdListAllStatusBeadSource(),
).gather(storeRoot: '/work/power_station', bead: bead);

void main() {
  test(
    'filing viability refuses lane shell syntax with exact constructs',
    () async {
      // The field case: a `#` inside a quoted command substitution opens a
      // comment that swallows the closing paren, and the whole gating line dies
      // at PARSE — no log, no return code, a gate only after the third throttle.
      const substitution = r'''echo "$(grep -c '#' lib/src/filing/x.dart)"''';
      final quoted = _report(
        _bead(validationPlan: substitution),
        FilingEvidence(
          lanePlanParse: _refused(
            kFilingLaneShell,
            'sh: -c: line 1: unexpected EOF while looking for matching `)\'',
          ),
        ),
      );
      final quotedRow = _row(quoted, FilingRequirement.validationPlanSyntax);
      expect(quotedRow.passed, isFalse);
      expect(
        quotedRow.detail,
        contains(r"""$(grep -c '#' lib/src/filing/x.dart)"""),
      );
      expect(
        quotedRow.detail,
        contains('rewrite as one parseable POSIX-shell command'),
      );

      // The second incident: an apostrophe carried out of design prose into a
      // single-quoted program. The offender is the WORD, never the program's own
      // boundary quotes.
      const apostrophe = "echo 'station lane's SDK'";
      final probe = FakeValidationPlanProbe(
        answers: {
          kFilingLaneShell: _refused(
            kFilingLaneShell,
            'sh: -c: line 1: unexpected EOF while looking for matching `\'\'',
          ),
        },
      );
      final carried = _report(
        _bead(validationPlan: apostrophe),
        await _gathered(_bead(validationPlan: apostrophe), probe: probe),
      );
      final carriedRow = _row(carried, FilingRequirement.validationPlanSyntax);
      expect(carriedRow.passed, isFalse);
      expect(carriedRow.detail, contains('"lane\'s"'));
      expect(
        carriedRow.detail,
        contains('rewrite as one parseable POSIX-shell command'),
      );
      // The seam ran once, against the lane shell, and never reached dash: a
      // plan no shell parses must not refuse twice over the same text.
      expect(probe.calls.map((call) => call.shell), [kFilingLaneShell]);
      expect(
        _row(carried, FilingRequirement.validationPlanPortability).passed,
        isTrue,
      );

      // A blank plan is the PRESENCE row's business and probes nothing.
      final blank = FakeValidationPlanProbe();
      final empty = _bead(validationPlan: '   ');
      final blankReport = _report(empty, await _gathered(empty, probe: blank));
      expect(blank.calls, isEmpty);
      expect(
        _row(blankReport, FilingRequirement.validationPlanSyntax).passed,
        isTrue,
      );
      expect(
        _row(blankReport, FilingRequirement.validationPlan).passed,
        isFalse,
      );
    },
  );

  test('filing viability refuses dash-only incompatibility', () async {
    // `sh` is bash 3.2 on a mac and dash on CI. Process substitution parses
    // under one and dies under the other, which surfaces as a HARNESS THROTTLE
    // rather than as a bad plan.
    const plan = 'cat <(printf x)';
    final probe = FakeValidationPlanProbe(
      answers: {
        kFilingPortabilityShell: _refused(
          kFilingPortabilityShell,
          'dash: 1: Syntax error: "(" unexpected',
        ),
      },
    );
    final bead = _bead(validationPlan: plan);
    final report = _report(bead, await _gathered(bead, probe: probe));

    expect(_row(report, FilingRequirement.validationPlanSyntax).passed, isTrue);
    final row = _row(report, FilingRequirement.validationPlanPortability);
    expect(row.passed, isFalse);
    expect(row.detail, contains('"<(printf x)"'));
    expect(
      row.detail,
      contains('replace the Bash-only construct with POSIX sh syntax'),
    );
    // Portability is only ever probed AFTER syntax passes.
    expect(probe.calls.map((call) => call.shell), [
      kFilingLaneShell,
      kFilingPortabilityShell,
    ]);

    // A probe that CRASHED is unavailable evidence, never a pass.
    final crashed = FakeValidationPlanProbe(
      throwsFor: const {kFilingPortabilityShell: 'dash died mid-parse'},
    );
    final unavailable = _report(bead, await _gathered(bead, probe: crashed));
    final unavailableRow = _row(
      unavailable,
      FilingRequirement.validationPlanPortability,
    );
    expect(unavailableRow.passed, isFalse);
    expect(unavailableRow.detail, contains('dash died mid-parse'));
    expect(
      unavailableRow.detail,
      contains('restore complete evidence and rerun'),
    );

    // A shell nobody INSTALLED is the same absence of an answer, and refuses
    // for the same reason: CI's shell was never asked about this plan, so
    // nothing here says it is portable. The row NAMES which absence it was.
    final missing = FakeValidationPlanProbe(
      missingShells: const {kFilingPortabilityShell},
    );
    final absentRow = _row(
      _report(bead, await _gathered(bead, probe: missing)),
      FilingRequirement.validationPlanPortability,
    );
    expect(absentRow.passed, isFalse);
    expect(absentRow.detail, contains('dash is not installed on this machine'));
    expect(absentRow.detail, contains('restore complete evidence and rerun'));
  });

  test('filing viability refuses absolute anchors', () {
    final refused = _report(
      _bead(
        description: 'The receipt landed at /tmp/round-7/receipt.md.',
        notes: r'Compare C:\Users\nico\work\notes.md from the windows run.',
      ),
      completeEmptyEvidence,
    );
    final row = _row(refused, FilingRequirement.repoRelativePaths);
    expect(row.passed, isFalse);
    expect(row.detail, contains('"/tmp/round-7/receipt.md" (description:'));
    expect(row.detail, contains(r'"C:\Users\nico\work\notes.md" (notes:'));
    expect(row.detail, contains('use a repository-relative path'));

    // Negative controls: a repository-relative anchor, a ROOTED DIRECTORY with
    // no known file extension (nothing precise enough to refuse on), and URI
    // text whose slashes are never a path.
    final clean = _report(
      _bead(
        description:
            'Edit lib/src/filing/filing_text.dart under /tmp/round-7 and read '
            'https://example.com/docs/a.md.',
      ),
      completeEmptyEvidence,
    );
    final cleanRow = _row(clean, FilingRequirement.repoRelativePaths);
    expect(cleanRow.passed, isTrue, reason: cleanRow.detail);
  });

  test('filing viability resolves attached-store bead ids', () {
    // `pow` is the current store, `tg` an attached one. `AC-3` and `ISO-8601`
    // are compounds under prefixes NOBODY holds a catalog for, so nothing can
    // resolve them and nothing may refuse them.
    final resolved = _report(
      _bead(
        description:
            'Follows pow-usbw and tg-0b64. AC-3 covers it; dates are ISO-8601, '
            'and pow-usbw-follow-up is prose about a bead, not an id.',
      ),
      parsedPlanEvidence(
        beadCatalogs: const {
          'pow': {'pow-usbw'},
          'tg': {'tg-0b64'},
        },
        decisionRegisters: const {},
      ),
    );
    final row = _row(resolved, FilingRequirement.beadReferences);
    expect(row.passed, isTrue, reason: row.detail);
    expect(row.detail, contains('pow-usbw'));
    expect(row.detail, contains('tg-0b64'));

    // Longest prefix first: `pow2-abc` belongs to `pow2`, never to `pow`.
    final longest = _report(
      _bead(description: 'Follows pow2-abc.'),
      parsedPlanEvidence(
        beadCatalogs: const {
          'pow': <String>{},
          'pow2': {'pow2-abc'},
        },
        decisionRegisters: const {},
      ),
    );
    expect(_row(longest, FilingRequirement.beadReferences).passed, isTrue);

    // An id nobody minted. Guessed ids have shipped three times.
    final guessed = _report(
      _bead(description: 'Follows pow-zzzz.'),
      parsedPlanEvidence(
        beadCatalogs: const {
          'pow': {'pow-usbw'},
        },
        decisionRegisters: const {},
      ),
    );
    final guessedRow = _row(guessed, FilingRequirement.beadReferences);
    expect(guessedRow.passed, isFalse);
    expect(guessedRow.detail, contains('"pow-zzzz"'));
    expect(
      guessedRow.detail,
      contains(
        'mint it before citing it or cite an existing attached-store id',
      ),
    );

    // A store that could not answer is UNAVAILABLE, never proof of absence.
    final unavailable = _report(
      _bead(description: 'Follows tg-0b64.'),
      parsedPlanEvidence(
        beadCatalogs: const {'pow': <String>{}},
        beadCatalogFailures: const {
          'tg': 'all-status read of the_grid (/w/the_grid) failed: exit 1',
        },
        decisionRegisters: const {},
      ),
    );
    final unavailableRow = _row(unavailable, FilingRequirement.beadReferences);
    expect(unavailableRow.passed, isFalse);
    expect(unavailableRow.detail, contains('"tg-0b64"'));
    expect(unavailableRow.detail, contains('all-status read of the_grid'));
    expect(
      unavailableRow.detail,
      contains('restore complete evidence and rerun'),
    );
    expect(unavailableRow.detail, isNot(contains('mint it before citing it')));

    // NO catalog at all — the station composed no scope. An id is only
    // tellable from prose against a prefix set, so this row has no question to
    // ask: it may not refuse (every hyphenated word would go red), but it may
    // not claim the text cites nothing either. It reports NOT CHECKED.
    final uncomposed = _report(
      _bead(description: 'Follows filing-nosuch, which is fail-closed.'),
      parsedPlanEvidence(decisionRegisters: const {}),
    );
    final uncomposedRow = _row(uncomposed, FilingRequirement.beadReferences);
    expect(uncomposedRow.passed, isTrue, reason: uncomposedRow.detail);
    expect(uncomposedRow.detail, contains('not checked'));
    expect(uncomposedRow.detail, contains('no store catalog was composed'));
    expect(
      uncomposedRow.detail,
      isNot(contains('cites no bead id')),
      reason: 'an unasked row never reports a finding nobody made',
    );
  });

  test('filing viability refuses exact acceptance release versions', () {
    // Specify copies the acceptance list into a gating plan leg, so a pinned
    // version there fails on the next release wave rather than on the work.
    final pinned = _report(
      _bead(acceptanceCriteria: '- [ ] grid_engine 0.4.0-dev.3 resolves'),
      completeEmptyEvidence,
    );
    final row = _row(pinned, FilingRequirement.releaseVersions);
    expect(row.passed, isFalse);
    expect(row.detail, contains('"0.4.0-dev.3" (acceptance_criteria:'));
    expect(
      row.detail,
      contains('use release-relative language or a version range'),
    );

    // Ranges, dates and a version outside acceptance are all fine: a pubspec
    // carries ranges, and the design DESCRIBES what was built.
    final clean = _report(
      _bead(
        acceptanceCriteria:
            '- [ ] grid_engine ^0.4.0 and >= 1.2.3 <2.0.0 resolve on '
            '2026-09-13',
        design: 'Built against grid_engine 0.4.0-dev.3.',
      ),
      completeEmptyEvidence,
    );
    final cleanRow = _row(clean, FilingRequirement.releaseVersions);
    expect(cleanRow.passed, isTrue, reason: cleanRow.detail);
  });

  test('filing viability resolves recorded decisions', () async {
    const canonical =
        'power_station#the-refiner-exit-oracle-is-the-filing-verb';
    final recorded = _report(
      _bead(description: 'Extends $canonical and ADR-0008.'),
      parsedPlanEvidence(
        decisionRegisters: const {'power_station'},
        decisionIdentities: const {canonical},
        decisionAliases: const {'adr-0008'},
      ),
    );
    final row = _row(recorded, FilingRequirement.decisionReferences);
    expect(row.passed, isTrue, reason: row.detail);

    // A round may not cite the decision it is about to write: discovery holds
    // every round, because the entry cannot exist until the work lands.
    final creates = _report(
      _bead(description: 'Records power_station#a-rule-this-round-creates.'),
      parsedPlanEvidence(
        decisionRegisters: const {'power_station'},
        absentDecisions: const {'a-rule-this-round-creates'},
      ),
    );
    final createsRow = _row(creates, FilingRequirement.decisionReferences);
    expect(createsRow.passed, isFalse);
    expect(
      createsRow.detail,
      contains('"power_station#a-rule-this-round-creates"'),
    );
    expect(
      createsRow.detail,
      contains(
        'a round may not cite a decision it creates; cite an existing entry '
        'or describe the proposed entry without a citation',
      ),
    );

    // A LEGACY id a COMPLETED lookup could not answer is REPORTED, not
    // refused: the register's own log file is spelled `ADR-0000`, so a refusal
    // over an unresolvable legacy token is a hold nothing can clear
    // (`power_station#notes-are-receipts-and-a-phantom-legacy-token-is-
    // reported-not-failed`). The row PASSES and still names the exact slice,
    // which is what keeps a genuine misspelling visible.
    final phantom = _report(
      _bead(design: 'This holds ADR-0042 exactly.'),
      parsedPlanEvidence(
        decisionRegisters: const {'power_station'},
        reportedDecisionAliases: const {'adr-0042'},
      ),
    );
    final phantomRow = _row(phantom, FilingRequirement.decisionReferences);
    expect(phantomRow.passed, isTrue, reason: phantomRow.detail);
    expect(phantomRow.detail, contains('"ADR-0042" (design:'));
    expect(phantomRow.detail, contains('REPORTED, never refused'));

    // The SAME token with no report is unresolved evidence and still refuses:
    // a pass is earned by an answer, never by the absence of one.
    final unreported = _report(
      _bead(design: 'This holds ADR-0042 exactly.'),
      parsedPlanEvidence(decisionRegisters: const {'power_station'}),
    );
    expect(
      _row(unreported, FilingRequirement.decisionReferences).passed,
      isFalse,
    );

    // NOTES are the operator's RECEIPT channel and make NO decision request —
    // a governor quoting a hold reason must not re-poison the bead it
    // explains. Citation-shaped notes leave the row with nothing to check.
    final receipts = _report(
      _bead(
        notes:
            'RECEIPT: reverted power_station#a-note-cites-nothing, quoted '
            'ADR-0000 explaining the hold.',
      ),
      parsedPlanEvidence(
        decisionRegisters: const {'power_station'},
        absentDecisions: const {'a-note-cites-nothing'},
      ),
    );
    final receiptsRow = _row(receipts, FilingRequirement.decisionReferences);
    expect(receiptsRow.passed, isTrue, reason: receiptsRow.detail);
    expect(receiptsRow.detail, 'the bead text cites no decision');

    // A CRASHED index is unavailable evidence, never an empty register.
    final crashed = _report(
      _bead(description: 'Extends $canonical.'),
      parsedPlanEvidence(
        decisionIndexFailure: 'decision index failed: exit 127',
      ),
    );
    final crashedRow = _row(crashed, FilingRequirement.decisionReferences);
    expect(crashedRow.passed, isFalse);
    expect(crashedRow.detail, contains('exit 127'));
    expect(crashedRow.detail, contains('restore complete evidence and rerun'));

    // With NO file anchor the owning scope's README is the existence surface:
    // citation existence is register-wide, so the lookup still has to run.
    final surfaces = <List<String>>[];
    final anchored = SystemFilingEvidenceSource(
      probe: FakeValidationPlanProbe(),
      owning: const SubstationScope(
        name: 'power_station',
        root: '/w/power_station',
        prefix: 'pow',
      ),
      decisions: (workspaceDir, rosterQualifiedSurfaces, workBead) async {
        surfaces.add(rosterQualifiedSurfaces);
        return const DecisionGatherEvidence();
      },
    );
    await anchored.gather(
      storeRoot: '/w/power_station',
      bead: _bead(description: 'Extends $canonical, no file named.'),
    );
    expect(surfaces, [
      ['power_station/README.md'],
    ]);
    await anchored.gather(
      storeRoot: '/w/power_station',
      bead: _bead(description: 'Edits lib/src/filing/filing_text.dart.'),
    );
    expect(surfaces.last, ['power_station/lib/src/filing/filing_text.dart']);
  });

  test('filing report keeps one eleven-row JSON schema', () {
    final report = _report(
      _bead(description: 'The receipt landed at /tmp/round-7/receipt.md.'),
      completeEmptyEvidence,
    );
    final json = report.toJson();
    final rows = (json['requirements']! as List).cast<Map<String, Object>>();

    // The landed ten, in their order, and the appended CONTENT row last.
    expect(rows.map((row) => row['requirement']), const [
      'driveable_type',
      'validation_plan',
      'acceptance_criteria',
      'dependencies',
      'validation_plan_syntax',
      'validation_plan_portability',
      'repo_relative_paths',
      'bead_references',
      'release_versions',
      'decision_references',
      'no_corrupting_text',
    ]);
    expect(rows.map((row) => row['requirement']), [
      for (final requirement in FilingRequirement.values) requirement.wire,
    ]);
    expect(rows, hasLength(11));
    for (final row in rows) {
      expect(row.keys, ['requirement', 'passed', 'detail']);
    }
    // ONE failing viability row fails the whole report.
    expect(
      rows
          .where((row) => row['passed'] == false)
          .map((row) => row['requirement']),
      ['repo_relative_paths'],
    );
    expect(json['passed'], isFalse);
    expect(report.passed, isFalse);
  });

  test('filing compatibility corpus keeps the landed ten rows passing on '
      'three live beads', () {
    final corpus =
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

    // Provenance: WHEN the text was captured and the EXACT read that captured
    // it, so a later reader can re-capture rather than guess.
    expect(corpus['captured'], '2026-09-13');
    final beads = (corpus['beads']! as List).cast<Map<String, dynamic>>();
    expect(beads.map((bead) => bead['command']), [
      "BD_JSON_ENVELOPE=1 bd query 'id=pow-p8il' --all --json",
      "BD_JSON_ENVELOPE=1 bd query 'id=pow-wtyb' --all --json",
      "BD_JSON_ENVELOPE=1 bd query 'id=pow-q6bq' --all --json",
    ]);

    // COMPLETE fake catalogs: every id and decision these live beads cite.
    // Nothing here reads a live store — only the TEXT is real.
    final evidence = parsedPlanEvidence(
      beadCatalogs: const {
        'pow': {
          'pow-07zx',
          'pow-5zpe',
          'pow-99g',
          'pow-h72x',
          'pow-p8il',
          'pow-q6bq',
          'pow-tpsl',
          'pow-wtyb',
        },
        'tg': {'tg-0b64', 'tg-hnhw', 'tg-pwpy'},
      },
      decisionRegisters: const {'power_station', 'the_grid'},
      decisionIdentities: const {
        'power_station#a-harness-may-carry-its-own-instructions',
        'power_station#a8-bead-tg-kx1-the-d-h-doctrine-rides-the-coding-agent-worki',
        'power_station#a9-bead-pow-6wo-re-homed-from-the-grid-tg-fc6-the-committee',
        'power_station#adr-0004-station-throughput-outranks-staging-ceremony',
        'power_station#approval-is-the-stamp-the-grid-approved-label-retires',
        'power_station#seat-priming-and-declaration-driven-launch',
        'power_station#test-tree-package-root-is-source-located',
        'power_station#the-governor-carries-a-cost-posture-ranked-under-throughput',
        'power_station#the-handoff-ritual-vends-as-an-operator-audience-skill',
        'power_station#the-refiner-exit-oracle-is-the-filing-verb',
        'power_station#the-worktree-overlay-scope-widens-to-every-skill-tree',
        'the_grid#a38-first-live-arm-proven-the-oneturn-quarantine-fix-three-f',
        'the_grid#a49-no-complete-on-faith-an-inferred-one-shot-exit-is-proven',
      },
    );

    // Two of the three snapshots write ordinary markdown code spans, so the
    // CONTENT row refuses them — which is the point of the row and not a
    // regression of the corpus. No fixture text is rewritten to manufacture a
    // pass: the live text is the evidence.
    const carriesBacktick = {'pow-p8il', 'pow-wtyb'};

    for (final record in beads) {
      final bead = Bead(
        id: record['id']! as String,
        title: record['title']! as String,
        issueType: IssueType.task,
        priority: 2,
        description: record['description']! as String,
        design: record['design']! as String,
        acceptanceCriteria: record['acceptance_criteria']! as String,
        notes: record['notes']! as String,
        metadata: {'validation_plan': record['validation_plan']! as String},
      );
      final report = _report(bead, evidence);

      // The ten LANDED rows still pass on every snapshot: this bead APPENDS a
      // row, it does not move one.
      expect(
        report.requirements
            .where(
              (row) => row.requirement != FilingRequirement.noCorruptingText,
            )
            .where((row) => !row.passed)
            .map((row) => '${row.requirement.wire}: ${row.detail}'),
        isEmpty,
        reason: bead.id,
      );

      final content = report.requirements.singleWhere(
        (row) => row.requirement == FilingRequirement.noCorruptingText,
      );
      if (carriesBacktick.contains(bead.id)) {
        expect(content.passed, isFalse, reason: bead.id);
        expect(content.detail, startsWith('corrupting bead text:'));
        expect(content.detail, contains('backtick'));
        expect(
          content.detail,
          endsWith('remove NUL bytes and backticks before filing'),
        );
        // BOUNDED. These snapshots carry over two hundred code spans each, and
        // a refusal that named every one ran to tens of kilobytes — which made
        // no correction clearer and overran the mount explainer's own byte
        // budget, so the report the row rides out on could not be rendered at
        // all. The refusal names the first sites and COUNTS the rest.
        expect(
          RegExp(r'\(\w+:\d+\)').allMatches(content.detail),
          hasLength(12),
          reason: bead.id,
        );
        expect(content.detail, contains(' more — '), reason: bead.id);
        expect(content.detail.length, lessThan(800), reason: bead.id);
        expect(report.passed, isFalse, reason: bead.id);
      } else {
        expect(content.passed, isTrue, reason: '${bead.id}: ${content.detail}');
        expect(report.requirements, hasLength(11), reason: bead.id);
        expect(report.passed, isTrue, reason: bead.id);
      }
    }
  });
}

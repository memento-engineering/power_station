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
      expect(quotedRow.status, FilingRequirementStatus.failed);
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
      expect(carriedRow.status, FilingRequirementStatus.failed);
      expect(carriedRow.detail, contains('"lane\'s"'));
      expect(
        carriedRow.detail,
        contains('rewrite as one parseable POSIX-shell command'),
      );
      // The seam ran once, against the lane shell, and never reached dash: a
      // plan no shell parses must not refuse twice over the same text.
      expect(probe.calls.map((call) => call.shell), [kFilingLaneShell]);
      expect(
        _row(carried, FilingRequirement.validationPlanPortability).status,
        FilingRequirementStatus.passed,
      );

      // A blank plan is the PRESENCE row's business and probes nothing.
      final blank = FakeValidationPlanProbe();
      final empty = _bead(validationPlan: '   ');
      final blankReport = _report(empty, await _gathered(empty, probe: blank));
      expect(blank.calls, isEmpty);
      expect(
        _row(blankReport, FilingRequirement.validationPlanSyntax).status,
        FilingRequirementStatus.passed,
      );
      expect(
        _row(blankReport, FilingRequirement.validationPlan).status,
        FilingRequirementStatus.failed,
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

    expect(
      _row(report, FilingRequirement.validationPlanSyntax).status,
      FilingRequirementStatus.passed,
    );
    final row = _row(report, FilingRequirement.validationPlanPortability);
    expect(row.status, FilingRequirementStatus.failed);
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

    // A probe that CRASHED is unavailable evidence, never a pass — and never
    // a filing failure either. It is the CHECKER that did not answer, so the
    // row reports that and the report carries it separately from a bead a row
    // actually refused.
    final crashed = FakeValidationPlanProbe(
      throwsFor: const {kFilingPortabilityShell: 'dash died mid-parse'},
    );
    final unavailable = _report(bead, await _gathered(bead, probe: crashed));
    final unavailableRow = _row(
      unavailable,
      FilingRequirement.validationPlanPortability,
    );
    expect(unavailableRow.status, FilingRequirementStatus.couldNotEvaluate);
    expect(unavailable.passed, isFalse);
    expect(unavailable.couldNotEvaluate, isTrue);
    expect(unavailableRow.detail, contains('dash died mid-parse'));
    expect(
      unavailableRow.detail,
      contains('restore complete evidence and rerun'),
    );

    // A shell nobody INSTALLED is a DIFFERENT absence, and the one that still
    // decides something: CI's shell is a declared floor, so a plan this
    // machine cannot check against it is not cleared for the lane that will
    // run it. That refusal is pre-existing and deliberate, and it stays one.
    final missing = FakeValidationPlanProbe(
      missingShells: const {kFilingPortabilityShell},
    );
    final absent = _report(bead, await _gathered(bead, probe: missing));
    final absentRow = _row(absent, FilingRequirement.validationPlanPortability);
    expect(absentRow.status, FilingRequirementStatus.failed);
    expect(absent.couldNotEvaluate, isFalse);
    expect(absentRow.detail, contains('dash is not installed on this machine'));
    expect(absentRow.detail, contains('restore complete evidence and rerun'));
  });

  // ── the CHECKER's own three states ────────────────────────────────────────
  //
  // A row that cannot gather its evidence says nothing about the bead. The
  // field incident these tests fence: over one window on the resident every
  // bead checked came back with `validation_plan_syntax` refusing, held across
  // three reruns minutes apart, across two stores and two plan shapes, and
  // across a bead that had passed every row earlier the same day and had not
  // been edited since. `/bin/sh` was installed and parsed those exact strings.
  // The plans were never the variable; the GATHER was.

  test(
    'syntax probe failure is could-not-evaluate, never a filing failure',
    () async {
      // The installed lane shell was ASKED and threw before answering.
      const plan = 'dart test';
      final bead = _bead(validationPlan: plan);
      final crashed = FakeValidationPlanProbe(
        throwsFor: const {kFilingLaneShell: 'spawn failed under station load'},
      );
      final report = _report(bead, await _gathered(bead, probe: crashed));
      final row = _row(report, FilingRequirement.validationPlanSyntax);

      expect(row.status, FilingRequirementStatus.couldNotEvaluate);
      expect(row.status, isNot(FilingRequirementStatus.failed));
      // The underlying spawn error rides the row, so an operator reads WHAT
      // failed instead of a bare "was not gathered".
      expect(row.detail, contains('spawn failed under station load'));
      expect(row.detail, contains('nothing here says the plan is wrong'));
      expect(row.detail, contains('restore complete evidence and rerun'));
      expect(report.passed, isFalse);
      expect(report.couldNotEvaluate, isTrue);

      // The gather does NOT retry: the report is the evidence SNAPSHOT, and a
      // second spawn that happened to succeed would erase the checker failure
      // the receipt has to carry. One ask, one answer, one row.
      expect(crashed.calls.map((call) => call.shell), [kFilingLaneShell]);

      // The other absence: nobody composed an evidence source at all. That is
      // the shape the resident reported — a refusal with no reason attached —
      // and the row now NAMES the composition gap rather than implying a plan
      // defect.
      final uncomposed = _row(
        _report(bead, FilingEvidence.unavailable),
        FilingRequirement.validationPlanSyntax,
      );
      expect(uncomposed.status, FilingRequirementStatus.couldNotEvaluate);
      expect(
        uncomposed.detail,
        contains('composed with no filing evidence source'),
      );
    },
  );

  test(
    'portability probe failure is could-not-evaluate after syntax passes',
    () async {
      // Syntax ANSWERED clean, so portability reached its own gather — and the
      // installed dash threw there. The twin of the syntax defect, fixed with it.
      const plan = 'dart test';
      final bead = _bead(validationPlan: plan);
      final crashed = FakeValidationPlanProbe(
        throwsFor: const {kFilingPortabilityShell: 'dash died mid-spawn'},
      );
      final report = _report(bead, await _gathered(bead, probe: crashed));

      expect(
        _row(report, FilingRequirement.validationPlanSyntax).status,
        FilingRequirementStatus.passed,
      );
      final row = _row(report, FilingRequirement.validationPlanPortability);
      expect(row.status, FilingRequirementStatus.couldNotEvaluate);
      expect(row.detail, contains('dash died mid-spawn'));
      expect(row.detail, contains('nothing here says the plan is unportable'));
      expect(report.passed, isFalse);
      expect(report.couldNotEvaluate, isTrue);
      expect(crashed.calls.map((call) => call.shell), [
        kFilingLaneShell,
        kFilingPortabilityShell,
      ]);
    },
  );

  test('portability stays not probed while syntax is unanswered', () async {
    // The short-circuit is PRESERVED. Until syntax has a successful parse
    // there is nothing portability can add, and a second gather failure over
    // the same text would name one absence twice.
    const plan = 'dart test';
    final bead = _bead(validationPlan: plan);
    final crashed = FakeValidationPlanProbe(
      throwsFor: const {kFilingLaneShell: 'sh never answered'},
    );
    final report = _report(bead, await _gathered(bead, probe: crashed));
    final row = _row(report, FilingRequirement.validationPlanPortability);

    expect(row.status, FilingRequirementStatus.passed);
    expect(
      row.detail,
      'not probed — the validation_plan_syntax row is answered first and '
      'carries this plan',
    );
    expect(row.detail, isNot(contains('sh never answered')));
    // Dash was never asked, so the report's ONE unevaluated row is syntax.
    expect(crashed.calls.map((call) => call.shell), [kFilingLaneShell]);
    expect(
      report.requirements
          .where(
            (each) => each.status == FilingRequirementStatus.couldNotEvaluate,
          )
          .map((each) => each.requirement),
      [FilingRequirement.validationPlanSyntax],
    );
  });

  test('broken shell syntax remains failed for each shell', () async {
    // The row EVALUATED and the bead lost. Nothing about the third state
    // softens a plan a shell actually refused — that answer is about the bead.
    const plan = 'echo "\$(grep -c \'#\' x.dart)"';
    final bead = _bead(validationPlan: plan);
    final laneRefused = FakeValidationPlanProbe(
      answers: {
        kFilingLaneShell: _refused(
          kFilingLaneShell,
          'sh: -c: line 1: unexpected EOF while looking for matching `)\'',
        ),
      },
    );
    final syntax = _row(
      _report(bead, await _gathered(bead, probe: laneRefused)),
      FilingRequirement.validationPlanSyntax,
    );
    expect(syntax.status, FilingRequirementStatus.failed);
    expect(syntax.detail, contains('rewrite as one parseable POSIX-shell'));

    final portableRefused = FakeValidationPlanProbe(
      answers: {
        kFilingPortabilityShell: _refused(
          kFilingPortabilityShell,
          'dash: 1: Syntax error: "(" unexpected',
        ),
      },
    );
    final refusedReport = _report(
      bead,
      await _gathered(bead, probe: portableRefused),
    );
    final portability = _row(
      refusedReport,
      FilingRequirement.validationPlanPortability,
    );
    expect(portability.status, FilingRequirementStatus.failed);
    expect(portability.detail, contains('replace the Bash-only construct'));
    // An evaluated refusal is NOT checker incompleteness: the report says the
    // bead is wrong, and says nothing went unanswered.
    expect(refusedReport.couldNotEvaluate, isFalse);
    expect(
      refusedReport.refusalReason,
      contains('correct the bead and rerun approve'),
    );
  });

  test('missing portability shell remains failed', () async {
    // A dash nobody INSTALLED keeps its own named refusal: CI's shell is a
    // declared floor, so a plan nothing here can check against it is not
    // cleared for the lane that will run it. That is a decided outcome, and
    // it stays apart from a dash that was asked and did not answer.
    const plan = 'dart test';
    final bead = _bead(validationPlan: plan);
    final missing = FakeValidationPlanProbe(
      missingShells: const {kFilingPortabilityShell},
    );
    final report = _report(bead, await _gathered(bead, probe: missing));
    final row = _row(report, FilingRequirement.validationPlanPortability);

    expect(row.status, FilingRequirementStatus.failed);
    expect(row.detail, contains('dash is not installed on this machine'));
    expect(report.passed, isFalse);
    expect(report.couldNotEvaluate, isFalse);
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
    expect(row.status, FilingRequirementStatus.failed);
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
    expect(
      cleanRow.status,
      FilingRequirementStatus.passed,
      reason: cleanRow.detail,
    );
  });

  test('filing viability resolves only attached-store bead-id grammar', () {
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
    expect(row.status, FilingRequirementStatus.passed, reason: row.detail);
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
    expect(
      _row(longest, FilingRequirement.beadReferences).status,
      FilingRequirementStatus.passed,
    );

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
    expect(guessedRow.status, FilingRequirementStatus.failed);
    expect(guessedRow.detail, contains('"pow-zzzz" (description:8)'));
    expect(
      guessedRow.detail,
      contains(
        'mint it before citing it or cite an existing attached-store id',
      ),
    );

    // The STORE's own grammar, not "prefix + any word". A lunar re-stamp
    // sweep refused three beads over text that cites nothing: the `genesis`
    // prefix in front of an English word, a fixture node path inside a code
    // span, and a placeholder standing for "each child". Each refusal named
    // its field and offset correctly, so the operator could reword — but
    // rewording prose to dodge a scanner is the wrong cost. A store minting
    // three-character roots never minted `genesis-derived`.
    final prose = _report(
      _bead(
        description:
            'The genesis prefix + genesis-derived downstream objects; the '
            'fixture node path is `tg-1/agent`; tg-ersi.x is each child and '
            'tg-ersi.4..9 is the range of them.',
      ),
      parsedPlanEvidence(
        beadCatalogs: const {
          'genesis': {'genesis-0p5'},
          'tg': {'tg-ersi', 'tg-ersi.4'},
        },
        decisionRegisters: const {},
      ),
    );
    final proseRow = _row(prose, FilingRequirement.beadReferences);
    expect(
      proseRow.status,
      FilingRequirementStatus.passed,
      reason: proseRow.detail,
    );
    expect(proseRow.detail, contains('cites no bead id'));

    // The same catalogs still RESOLVE what the store actually mints: a root at
    // a length that store uses, and bd's decimal child of one.
    final children = _report(
      _bead(description: 'Follows tg-ersi and tg-ersi.4.'),
      parsedPlanEvidence(
        beadCatalogs: const {
          'genesis': {'genesis-0p5'},
          'tg': {'tg-ersi', 'tg-ersi.4'},
        },
        decisionRegisters: const {},
      ),
    );
    final childrenRow = _row(children, FilingRequirement.beadReferences);
    expect(
      childrenRow.status,
      FilingRequirementStatus.passed,
      reason: childrenRow.detail,
    );
    expect(childrenRow.detail, contains('tg-ersi.4'));

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
    expect(unavailableRow.status, FilingRequirementStatus.failed);
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
    expect(
      uncomposedRow.status,
      FilingRequirementStatus.passed,
      reason: uncomposedRow.detail,
    );
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
    expect(row.status, FilingRequirementStatus.failed);
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
    expect(
      cleanRow.status,
      FilingRequirementStatus.passed,
      reason: cleanRow.detail,
    );
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
    expect(row.status, FilingRequirementStatus.passed, reason: row.detail);

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
    expect(createsRow.status, FilingRequirementStatus.failed);
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
    expect(
      phantomRow.status,
      FilingRequirementStatus.passed,
      reason: phantomRow.detail,
    );
    expect(phantomRow.detail, contains('"ADR-0042" (design:'));
    expect(phantomRow.detail, contains('REPORTED, never refused'));

    // The SAME token with no report is unresolved evidence and still refuses:
    // a pass is earned by an answer, never by the absence of one.
    final unreported = _report(
      _bead(design: 'This holds ADR-0042 exactly.'),
      parsedPlanEvidence(decisionRegisters: const {'power_station'}),
    );
    expect(
      _row(unreported, FilingRequirement.decisionReferences).status,
      FilingRequirementStatus.failed,
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
    expect(
      receiptsRow.status,
      FilingRequirementStatus.passed,
      reason: receiptsRow.detail,
    );
    expect(receiptsRow.detail, 'the bead text cites no decision');

    // A CRASHED index is unavailable evidence, never an empty register.
    final crashed = _report(
      _bead(description: 'Extends $canonical.'),
      parsedPlanEvidence(
        decisionIndexFailure: 'decision index failed: exit 127',
      ),
    );
    final crashedRow = _row(crashed, FilingRequirement.decisionReferences);
    expect(crashedRow.status, FilingRequirementStatus.failed);
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
      // The row wire is THREE fields, and the verdict one is `status`: a
      // boolean `passed` key cannot carry a third state, which is why it is
      // gone rather than kept beside the enum.
      expect(row.keys, ['requirement', 'status', 'detail']);
      expect(
        row['status'],
        isIn(const ['passed', 'failed', 'could_not_evaluate']),
      );
    }
    // ONE failing viability row fails the whole report.
    expect(
      rows
          .where((row) => row['status'] == 'failed')
          .map((row) => row['requirement']),
      ['repo_relative_paths'],
    );
    expect(json['passed'], isFalse);
    // The bead FAILED a check; no checker went unanswered, and the report says
    // so in its own field rather than leaving a caller to infer it.
    expect(json['could_not_evaluate'], isFalse);
    expect(report.passed, isFalse);
    expect(report.couldNotEvaluate, isFalse);
  });

  test('filing compatibility corpus keeps live beads and lunar non-citations '
      'passing', () {
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

      // All ELEVEN rows pass on every snapshot. Two of the three write
      // ordinary markdown code spans, and they stay clean: the CONTENT row
      // refuses the NUL byte only, so this bead APPENDS a row without moving
      // one. No fixture text is rewritten to manufacture a pass — the live
      // text is the evidence.
      expect(
        report.requirements
            .where((row) => row.status != FilingRequirementStatus.passed)
            .map((row) => '${row.requirement.wire}: ${row.detail}'),
        isEmpty,
        reason: bead.id,
      );
      expect(report.requirements, hasLength(11), reason: bead.id);
      expect(report.passed, isTrue, reason: bead.id);
    }

    // The NEGATIVE half of the corpus: three tokens a lunar v2 re-stamp sweep
    // refused as bead citations while the row read "prefix + any word" as an
    // id. Each is prose — an English word behind a store prefix, a fixture
    // node path inside a code span, and a placeholder standing for "each
    // child" — and each refusal named its field and offset correctly, so the
    // operator reworded a bead to get past a scanner. They are kept beside the
    // live beads so a future grammar cannot re-acquire them quietly.
    final nonCitations = (corpus['bead_reference_non_citations']! as List)
        .cast<Map<String, dynamic>>();
    expect(nonCitations, [
      {
        'source_bead': 'genesis-0p5',
        'field': 'description',
        'token': 'genesis-derived',
        'captured': '2026-09-22',
      },
      {
        'source_bead': 'tg-xtnf',
        'field': 'design',
        'token': '`tg-1/agent`',
        'captured': '2026-09-22',
      },
      {
        'source_bead': 'tg-ersi.4..9',
        'field': 'notes',
        'token': 'tg-ersi.x',
        'captured': '2026-09-22',
      },
    ]);

    // COMPLETE catalogs whose REAL ids establish each store's root length:
    // `genesis` mints three-character roots, `tg` four-character ones with
    // decimal children. Nothing here reads a live store either.
    final proseEvidence = parsedPlanEvidence(
      beadCatalogs: const {
        'genesis': {'genesis-0p5'},
        'tg': {'tg-ersi', 'tg-ersi.4', 'tg-xtnf'},
      },
      decisionRegisters: const {},
    );
    for (final record in nonCitations) {
      final token = record['token']! as String;
      final field = record['field']! as String;
      final bead = switch (field) {
        'description' => _bead(description: token),
        'design' => _bead(design: token),
        'notes' => _bead(notes: token),
        _ => fail('no bead field is spelled "$field"'),
      };
      final report = _report(bead, proseEvidence);

      expect(
        report.requirements
            .where((row) => row.status != FilingRequirementStatus.passed)
            .map((row) => '${row.requirement.wire}: ${row.detail}'),
        isEmpty,
        reason: '${record['source_bead']}: $token',
      );
      expect(report.requirements, hasLength(11), reason: token);
      expect(report.passed, isTrue, reason: token);
    }
  });
}

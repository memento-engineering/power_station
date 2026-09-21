// The PRE-STAMP ADVISORY — the spec-review readiness lens and the discovery
// evidence gather, run by the filing verbs BEFORE the stamp.
//
// Proves: the advisory is a CALL SITE, not a second judgement. Every refusal it
// emits is the owning lens's own fix text, compared here against the very
// matrix the `spec_review` route calls (`decideReadiness` / `decideDiscovery`)
// over the same inputs. It runs the deterministic intake contract first and
// spends nothing on a bead that fails it; it stops at the readiness hold and
// never fans out; it regathers exactly once; and it publishes NOTHING — no
// critique file, no discovery report, no dossier, no node path, no usage
// capture.
//
// Offline only: the ONE process seam is a scripted Fake InferenceRunner, so no
// model, no git and no shell is ever reached. The gather runs against a real
// `Directory.systemTemp` store root — torn down per test, never the process
// working directory — because the no-artifact probe has to look at a real
// filesystem to mean anything.
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart' show SystemGitRunner;
import 'package:test/test.dart';

import '../support/package_root.dart';
import 'filing_evidence_fakes.dart';

/// A driveable bead carrying a real brief — the shape that reaches the lens.
Bead _work({String description = 'Extend the filing preflight.'}) =>
    const Bead(
      id: 'pow-child',
      title: 'the pre-stamp advisory',
      issueType: IssueType.task,
    ).copyWith(
      description: description,
      acceptanceCriteria: '- [ ] dart test passes',
    );

/// A store root that EXISTS — the gather probes the filesystem, and the
/// no-artifact probe needs somewhere real to find nothing in.
String _storeRoot() {
  final dir = Directory.systemTemp.createTempSync('pre-stamp-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir.path;
}

/// The advisory over a scripted inference queue, with every optional
/// deterministic seam left UNWIRED (the gather records those unavailable, which
/// is the honest offline posture) and the rubric source inline so no packaged
/// asset is read.
PreStampAdvisory _advisory(ScriptedInferenceRunner runner) => PreStampAdvisory(
  inference: runner,
  rubrics: (id) => '($id bands)',
  anchorResolver: (_, paths) => [
    for (final path in paths) unresolvedAnchor(path, source: 'test'),
  ],
);

/// A lens reply carrying ONE gating decision violation.
InferenceResult _offendingLensReply(String lens, DiscoveryFinding finding) =>
    InferenceResult(
      ok: true,
      output: jsonEncode({
        'outcome': 'report',
        'lens': lens,
        'version': 2,
        'context': <Object?>[],
        'violations': [finding.toJson()],
      }),
    );

/// The ONE offence these probes cite — recorded, contradicted, undeclared.
const DiscoveryFinding _offence = DiscoveryFinding(
  kind: ViolationKind.decision,
  standard: 'power_station#the-refiner-exit-oracle-is-the-filing-verb',
  quote:
      'The refiner\'s exit criterion is a CALL to the already-shipped '
      '`filing` Command',
  contradiction: 'this bead mints a second completeness predicate',
  contradicts: true,
  ratified: true,
);

void main() {
  group('the ladder stops at the first refusal', () {
    test('AC-1 — a D grade refuses with the route matrix\'s OWN fix text, and '
        'no lens fans out', () async {
      final reply = readinessReply(
        'D',
        rationale: 'names no surface and no decision',
      );
      final runner = ScriptedInferenceRunner([reply, ...cleanDiscoveryReplies]);

      final verdict = await _advisory(
        runner,
      ).evaluate(storeRoot: _storeRoot(), bead: _work());

      // The PIN: the advisory's reason is what the SHARED decoder plus the
      // SHARED matrix produce over the very same reply — the identical text a
      // `spec_review` gate would have parked with, a whole circuit earlier.
      final candidate = verdictFromResultText(reply.output);
      final route = decideReadiness(
        grade: candidate?['grade'],
        rationale: candidate?['rationale'] ?? '',
      );
      expect(route, isA<ReadinessHold>());
      expect(
        verdict,
        isA<FilingAdvisoryRefused>()
            .having((v) => v.rule, 'rule', 'readiness')
            .having((v) => v.reason, 'reason', (route as ReadinessHold).reason),
      );
      expect(verdict.passed, isFalse);
      // ONE call: the readiness hold withholds the three-lens fan-out exactly
      // as the circuit's route withholds the architect.
      expect(runner.calls, hasLength(1));
    });

    test('AC-1 — an A–C grade passes carrying the letter, and the fan-out is '
        'exactly three lenses', () async {
      for (final grade in const ['A', 'B', 'C']) {
        final runner = ScriptedInferenceRunner([
          readinessReply(grade),
          ...cleanDiscoveryReplies,
        ]);
        expect(
          await _advisory(
            runner,
          ).evaluate(storeRoot: _storeRoot(), bead: _work()),
          isA<FilingAdvisoryPassed>().having(
            (v) => v.readinessGrade,
            'grade',
            grade,
          ),
          reason: 'grade $grade drives',
        );
        expect(runner.calls, hasLength(1 + kDiscoveryLenses.length));
      }
    });

    test('the deterministic intake contract refuses FIRST and spends no '
        'inference at all', () async {
      final runner = ScriptedInferenceRunner([readinessReply('A')]);
      final bead = _work().copyWith(issueType: IssueType.epic);

      final verdict = await _advisory(
        runner,
      ).evaluate(storeRoot: _storeRoot(), bead: bead);

      expect(
        verdict,
        isA<FilingAdvisoryRefused>()
            .having((v) => v.rule, 'rule', 'intake')
            .having(
              (v) => v.reason,
              'reason',
              renderIntakeHold(bead, intakeFindings(bead)),
            ),
      );
      expect(runner.calls, isEmpty);
    });
  });

  group('AC-2 — the discovery matrix decides, verbatim', () {
    test('a cited, unacknowledged contradiction refuses with the route\'s own '
        'hold text', () async {
      final runner = ScriptedInferenceRunner([
        readinessReply('B'),
        cleanLensReply(kCodeLens),
        _offendingLensReply(kDecisionLens, _offence),
        cleanLensReply(kPriorArtLens),
      ]);

      final verdict = await _advisory(
        runner,
      ).evaluate(storeRoot: _storeRoot(), bead: _work());

      expect(
        verdict,
        isA<FilingAdvisoryRefused>()
            .having((v) => v.rule, 'rule', 'discovery')
            .having(
              (v) => v.reason,
              'reason',
              renderDiscoveryHold(offenses: const [_offence], flags: const []),
            ),
      );
      expect(verdict.passed, isFalse);
      // It names the decision it offends, which is the whole point of
      // cite-the-offence: a refiner reads WHICH entry and its two exits.
      expect(
        (verdict as FilingAdvisoryRefused).reason,
        allOf(contains(_offence.standard), contains('DECLARE the departure')),
      );
    });

    test(
      'a DECLARED departure is not an offence — the same finding passes',
      () async {
        final runner = ScriptedInferenceRunner([
          readinessReply('B'),
          cleanLensReply(kCodeLens),
          _offendingLensReply(
            kDecisionLens,
            const DiscoveryFinding(
              kind: ViolationKind.decision,
              standard:
                  'power_station#the-refiner-exit-oracle-is-the-filing-verb',
              quote: 'a CALL to the already-shipped `filing` Command',
              contradiction: 'this bead adds a call site',
              contradicts: true,
              ratified: true,
              acknowledged: true,
            ),
          ),
          cleanLensReply(kPriorArtLens),
        ]);

        expect(
          await _advisory(
            runner,
          ).evaluate(storeRoot: _storeRoot(), bead: _work()),
          isA<FilingAdvisoryPassed>(),
        );
      },
    );

    test('a STATED evidence hole regathers ONCE and then holds with the '
        'gather\'s own reason', () async {
      const gaps = [
        EvidenceGap(evidenceId: 'decision-surface:x', reason: 'TRUNCATED'),
      ];
      InferenceResult insufficient(String lens) => InferenceResult(
        ok: true,
        output: jsonEncode({
          'outcome': 'insufficient-evidence',
          'lens': lens,
          'version': 2,
          'gaps': [for (final gap in gaps) gap.toJson()],
        }),
      );
      final runner = ScriptedInferenceRunner([
        readinessReply('B'),
        // Round 0 — the decision lane states a hole.
        cleanLensReply(kCodeLens),
        insufficient(kDecisionLens),
        cleanLensReply(kPriorArtLens),
        // Round 1 — it states it again; the re-gather budget is spent.
        cleanLensReply(kCodeLens),
        insufficient(kDecisionLens),
        cleanLensReply(kPriorArtLens),
      ]);

      final verdict = await _advisory(
        runner,
      ).evaluate(storeRoot: _storeRoot(), bead: _work());

      expect(
        verdict,
        isA<FilingAdvisoryRefused>()
            .having((v) => v.rule, 'rule', 'discovery-evidence')
            .having(
              (v) => v.reason,
              'reason',
              renderDiscoveryEvidenceHold(const {kDecisionLens: gaps}),
            ),
      );
      // ONE readiness call plus TWO full fan-outs — `kMaxRegatherRounds` is 1,
      // and the advisory spends the circuit's budget, not its own.
      expect(
        runner.calls,
        hasLength(1 + (kMaxRegatherRounds + 1) * kDiscoveryLenses.length),
      );
    });

    test('an ABSENT lens report regathers once and then ADVANCES — the gate '
        'never fires on absence', () async {
      final runner = ScriptedInferenceRunner([
        readinessReply('B'),
        cleanLensReply(kCodeLens),
        const InferenceResult(ok: true, output: 'I could not read that.'),
        cleanLensReply(kPriorArtLens),
        cleanLensReply(kCodeLens),
        const InferenceResult(ok: true, output: 'Still nothing.'),
        cleanLensReply(kPriorArtLens),
      ]);

      expect(
        await _advisory(
          runner,
        ).evaluate(storeRoot: _storeRoot(), bead: _work()),
        isA<FilingAdvisoryPassed>(),
        reason: 'a false HOLD is strictly worse than a wasted round',
      );
      expect(
        runner.calls,
        hasLength(1 + (kMaxRegatherRounds + 1) * kDiscoveryLenses.length),
      );
    });
  });

  group('a lens that never answered is LOUD, never a verdict', () {
    test(
      'a readiness lens that did not COMPLETE refuses under `transport`',
      () async {
        final verdict = await _advisory(
          ScriptedInferenceRunner(const [
            InferenceResult(ok: false, output: ''),
          ]),
        ).evaluate(storeRoot: _storeRoot(), bead: _work());

        expect(
          verdict,
          isA<FilingAdvisoryRefused>().having(
            (v) => v.rule,
            'rule',
            'transport',
          ),
        );
        expect(
          (verdict as FilingAdvisoryRefused).reason,
          allOf(contains('did not complete'), contains('NOT judged')),
        );
      },
    );

    test('a readiness lens that completed and published NOTHING readable '
        'refuses under `transport` — never a hold, never a pass', () async {
      final verdict = await _advisory(
        ScriptedInferenceRunner(const [
          InferenceResult(ok: true, output: 'I had a lovely time reading.'),
        ]),
      ).evaluate(storeRoot: _storeRoot(), bead: _work());

      expect(
        verdict,
        isA<FilingAdvisoryRefused>().having((v) => v.rule, 'rule', 'transport'),
      );
      // Absence is neither verdict: it does not carry the refinement ask a
      // graded hold carries, and it does not pass.
      expect(
        (verdict as FilingAdvisoryRefused).reason,
        isNot(contains('SPEC-READINESS HOLD')),
      );
      expect(verdict.passed, isFalse);
    });
  });

  group('AC-3 — one lens, one prompt, and NOTHING published', () {
    test(
      'the spawned prompts are the SHARED bodies on the fileless arm',
      () async {
        final runner = ScriptedInferenceRunner([
          readinessReply('B'),
          ...cleanDiscoveryReplies,
        ]);
        final bead = _work();
        final root = _storeRoot();

        await _advisory(runner).evaluate(storeRoot: root, bead: bead);

        // The readiness call carries the shared body byte-for-byte — the same
        // rubric, the same verdict schema version, the same judgement.
        expect(
          runner.prompts.first,
          contains(
            readinessLensPromptBody(
              bead: bead,
              rubric: kReadinessRubric,
              nodePath: kPreStampAdvisoryNodePath,
              round: kPreStampAdvisoryRound,
              rubrics: (id) => '($id bands)',
            ),
          ),
        );
        // And every call rides the FILELESS arm: no write path is named, and
        // nothing is asked to touch disk.
        for (final prompt in runner.prompts) {
          expect(prompt, contains(kInProcessResultInstruction));
          expect(prompt, isNot(contains('.grid/critique')));
          expect(prompt, isNot(contains('.grid/discovery')));
          expect(prompt, isNot(contains('mktemp')));
        }
        // The three lens prompts are the shared discovery assembly, one per lens.
        for (final lens in kDiscoveryLenses) {
          expect(
            runner.prompts.where(
              (p) => p.contains('# Discovery — lens: `$lens`'),
            ),
            hasLength(1),
          );
        }
      },
    );

    test(
      'no usage capture is armed — the whole answer comes back on stdout',
      () async {
        final runner = ScriptedInferenceRunner([
          readinessReply('B'),
          ...cleanDiscoveryReplies,
        ]);
        await _advisory(
          runner,
        ).evaluate(storeRoot: _storeRoot(), bead: _work());

        // The FT-2 capture wrapper is an `sh -c` with a redirect; the fileless
        // arm passes no `usageOut`, so every spawn is a plain harness argv.
        for (final config in runner.calls) {
          expect(config.command, isNot('sh'));
          expect(config.args.join(' '), isNot(contains('usage')));
        }
      },
    );

    test('the run creates NO artifact under the store root — not a critique, '
        'not a discovery report, not a dossier', () async {
      final root = _storeRoot();
      final runner = ScriptedInferenceRunner([
        readinessReply('B'),
        ...cleanDiscoveryReplies,
      ]);

      await _advisory(runner).evaluate(storeRoot: root, bead: _work());

      // The whole point of the fileless arm: a pre-stamp run can neither
      // satisfy nor collide with a spec-review route's published verdict,
      // because it publishes nothing for one to read.
      expect(
        Directory(root).listSync(recursive: true),
        isEmpty,
        reason: 'the advisory writes nothing, anywhere',
      );
      expect(Directory(discoveryDirPath(root)).existsSync(), isFalse);
      expect(Directory(critiqueDirPath(root)).existsSync(), isFalse);
      expect(File(anchorsPath(root)).existsSync(), isFalse);
      expect(File(discoveryDossierPath(root)).existsSync(), isFalse);
    });

    test(
      'the gather is the SAME deterministic one, at the same bounds',
      () async {
        final bead = _work(
          description: 'Extend `lib/src/filing/filing_contract.dart`.',
        );
        final root = _storeRoot();
        final runner = ScriptedInferenceRunner([
          readinessReply('B'),
          ...cleanDiscoveryReplies,
        ]);
        await _advisory(runner).evaluate(storeRoot: root, bead: bead);

        // What the lens was handed is exactly `projectDiscoveryEvidence` over
        // `gatherDiscoveryAnchors` — recomputed here and compared as text, so a
        // bound that moved on one side would be visible on the other.
        final anchors = await gatherDiscoveryAnchors(
          bead: bead,
          workspaceDir: root,
          round: kPreStampAdvisoryRound,
          substation: '',
          live: true,
          rubricIds: kSpecCommitteeRubrics,
          rubrics: (id) => '($id bands)',
          resolver: (_, paths) => [
            for (final path in paths) unresolvedAnchor(path, source: 'test'),
          ],
          history: gitHistorySource(SystemGitRunner()),
        );
        expect(anchors, isNotNull);
        final decisionPrompt = runner.prompts.singleWhere(
          (p) => p.contains('# Discovery — lens: `$kDecisionLens`'),
        );
        expect(
          decisionPrompt,
          contains(
            projectDiscoveryEvidence(
              anchors!,
              lens: kDecisionLens,
              round: kPreStampAdvisoryRound,
              workBeadId: bead.id,
            ).renderedEvidence,
          ),
        );
      },
    );
  });

  group('the verb composes the advisory LAST', () {
    test(
      'a mechanically failing row refuses BEFORE the advisory is asked',
      () async {
        final advisory = FakeFilingAdvisory();
        final service = FilingService(
          source: ExactSubstationBeadSource(
            runnerFor: (_) => FakeExactBeadRunner(
              _work().copyWith(issueType: IssueType.epic),
            ),
          ),
          evidence: FakeFilingEvidenceSource(completeEmptyEvidence),
          advisory: advisory,
        );

        final report = await service.check(
          storeRoot: '/w/pow',
          beadId: 'pow-child',
          advisoryMode: FilingAdvisoryMode.run,
        );

        expect(report.passed, isFalse);
        expect(report.advisory, isNull);
        expect(
          advisory.calls,
          isEmpty,
          reason: 'the ten rows are free; the advisory is not',
        );
      },
    );

    test(
      'off asks nothing, skip waives without asking, run asks once',
      () async {
        Future<FilingReport> reportFor(
          FilingAdvisoryMode mode,
          FakeFilingAdvisory advisory,
        ) => FilingService(
          source: ExactSubstationBeadSource(
            runnerFor: (_) => FakeExactBeadRunner(_work()),
          ),
          evidence: FakeFilingEvidenceSource(completeEmptyEvidence),
          advisory: advisory,
        ).check(storeRoot: '/w/pow', beadId: 'pow-child', advisoryMode: mode);

        final off = FakeFilingAdvisory();
        expect((await reportFor(FilingAdvisoryMode.off, off)).advisory, isNull);
        expect(off.calls, isEmpty);

        final skipped = FakeFilingAdvisory();
        final skipReport = await reportFor(FilingAdvisoryMode.skip, skipped);
        expect(skipReport.advisory, isA<FilingAdvisorySkipped>());
        expect(skipReport.passed, isTrue);
        expect(skipped.calls, isEmpty);

        final ran = FakeFilingAdvisory();
        final runReport = await reportFor(FilingAdvisoryMode.run, ran);
        expect(runReport.advisory, isA<FilingAdvisoryPassed>());
        expect(runReport.passed, isTrue);
        expect(ran.calls, [(storeRoot: '/w/pow', beadId: 'pow-child')]);
      },
    );

    test('asking to RUN an advisory nobody composed is a LOUD refusal, never '
        'a pass', () async {
      final report =
          await FilingService(
            source: ExactSubstationBeadSource(
              runnerFor: (_) => FakeExactBeadRunner(_work()),
            ),
            evidence: FakeFilingEvidenceSource(completeEmptyEvidence),
          ).check(
            storeRoot: '/w/pow',
            beadId: 'pow-child',
            advisoryMode: FilingAdvisoryMode.run,
          );

      expect(report.passed, isFalse);
      expect(
        report.advisory,
        isA<FilingAdvisoryRefused>().having(
          (v) => v.rule,
          'rule',
          'composition',
        ),
      );
      expect(report.refusalReason, contains('composed with no advisory'));
    });

    test(
      'an advisory refusal IS the report\'s refusal reason, verbatim',
      () async {
        const hold = 'SPEC-READINESS HOLD (grade D) — fix the brief.';
        final report =
            await FilingService(
              source: ExactSubstationBeadSource(
                runnerFor: (_) => FakeExactBeadRunner(_work()),
              ),
              evidence: FakeFilingEvidenceSource(completeEmptyEvidence),
              advisory: FakeFilingAdvisory(
                const FilingAdvisoryRefused(rule: 'readiness', reason: hold),
              ),
            ).check(
              storeRoot: '/w/pow',
              beadId: 'pow-child',
              advisoryMode: FilingAdvisoryMode.run,
            );

        expect(report.passed, isFalse);
        expect(report.refusalReason, hold);
        // The ten rows all PASSED — the refusal is the advisory's alone, and the
        // completeness lane is untouched.
        expect(report.requirements, hasLength(FilingRequirement.values.length));
        expect(report.requirements.every((row) => row.passed), isTrue);
        expect(
          (report.toJson()['advisory']! as Map<String, Object?>)['reason'],
          hold,
        );
      },
    );
  });

  group('the seam is RECORDED, and the record names what it extends', () {
    /// The entry authored for this work, found by its slug rather than by a
    /// guessed filename.
    String entry() {
      final register = Directory(
        p.join(packageRoot(), '..', '..', 'docs', 'decisions'),
      );
      final matches = register
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .where(
            (file) => file.readAsStringSync().contains(
              'slug: pre-stamp-advisory-reuses-readiness-and-discovery',
            ),
          )
          .toList();
      expect(matches, hasLength(1), reason: 'exactly one entry owns the slug');
      return matches.single.readAsStringSync();
    }

    test('it BINDS, and it is the accepted schema this register uses', () {
      final text = entry();
      expect(text, startsWith('---\n'));
      expect(text, contains('status: accepted'));
      expect(text, contains('date: 2026-09-21'));
      expect(text, contains('spec: 1'));
      expect(text, contains('bead: pow-v4xh'));
      expect(text, contains('legacy-id: null'));
      // The cached reciprocal fields are written by the verb that earns them,
      // never by the entry that declares an edge.
      expect(text, contains('obsoleted-by: null'));
      expect(text, contains('updated-by: []'));
    });

    test('it names every decision it extends — including the one that owns '
        'the signatures it edits', () {
      final text = entry();
      for (final slug in const [
        'approval-is-the-stamp-the-grid-approved-label-retires',
        'the-refiner-exit-oracle-is-the-filing-verb',
        'readiness-route-joins-on-a-published-verdict-never-on-absence',
        'discovery-evidence-is-gathered-once-and-projected',
        // The currently-binding ruling on `FilingService.inspect`/`check` and
        // `ApproveService.approve` — it authored `armedSubstations` and it
        // reaffirmed the completeness-lane boundary, and this work extends
        // exactly those signatures.
        'the-dependencies-row-is-a-projection-of-bd-dependency-rows',
      ]) {
        expect(text, contains(slug), reason: 'cites $slug');
      }
    });

    test('it records the three decided seams as outcomes', () {
      final text = entry();
      // (a) a call site, never a fourth predicate.
      expect(text, contains('never a fourth predicate'));
      // (b) nothing published, no node path.
      expect(text, contains('No on-disk artifact and no node path'));
      // (c) the fixed order, advisory last before the stamp.
      expect(text, contains('the advisory is LAST before the stamp'));
      // And the boundary the signatures' owning decision reaffirmed.
      expect(text, contains('No fifth requirement and no second predicate'));
      expect(text, contains('`armedSubstations` is UNTOUCHED'));
      // The receipt tuple stays three keys.
      expect(text, contains('sole required validity'));
    });

    test('the recorded claims are TRUE of the live tree', () {
      // A record is only worth the invariant it names, so each one is checked
      // against the code rather than trusted.
      expect(
        FilingRequirement.values.map((value) => value.wire),
        const [
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
        ],
        reason: 'no eleventh requirement is minted',
      );
      const stamp = ApprovalStamp(
        by: 'nico',
        at: '2026-09-02T14:30:00.000Z',
        rev: 'abcdef1',
        readinessGrade: 'A',
        advisorySkipped: true,
      );
      expect(
        stamp.metadata.keys.take(3),
        [kApprovedByKey, kApprovedAtKey, kApprovedRevKey],
        reason: 'the receipt tuple is first and whole',
      );
    });
  });
}

// The DESIGN-ROUND committee — the docs committee's adversarial extension.
//
// Proves: the path-only admission (`docs/design/**`, evaluated BEFORE the docs
// arm, leaving every ordinary docs bead where it was); the circuit's lane set
// (the three unchanged deterministic gates + four rubric-selected judges); the
// verify join and the route's single dependency; and the verifier's own
// behaviour over FAKE judgments — one refuted, one confirmed-and-fixed, one
// confirmed-open — down to the document it rewrites, the adjudication log it
// appends, the critique artifact it writes, and the ONE finding that reaches
// the route. Plus every fail-closed refusal, each one LOUD.
// Offline only: the inference seam is a Fake, and every path is a temp dir.
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// The design document this round argues over.
const String _documentPath = 'docs/design/w2d-soak-gate.md';

/// A bead whose `## Touches` cites design paths only.
Bead _designBead() => bead('pow-d1').copyWith(
  title: 'the W2-D soak gate',
  design: '## Touches\n- `$_documentPath` — the round document\n',
);

/// The round's document before the verifier touches it.
const String _documentBody =
    '# W2-D soak gate\n'
    '\n'
    '## Ordering\n'
    '\n'
    'The breaker trips after the restore begins.\n';

/// The same document after the verifier applied the one confirmed fix.
const String _revisedBody =
    '# W2-D soak gate\n'
    '\n'
    '## Ordering\n'
    '\n'
    'The breaker trips BEFORE the restore begins.\n';

/// A unified diff that changes only [_documentPath].
const String _pinnedDiff =
    'diff --git a/$_documentPath b/$_documentPath\n'
    '--- a/$_documentPath\n'
    '+++ b/$_documentPath\n'
    '@@ -0,0 +1,1 @@\n'
    '+# W2-D soak gate\n';

/// One judge rationale line in the grammar every judge rubric commands.
String _finding(String severity, String id, String claim, String receipt) =>
    '- [$severity] $id — $claim; receipt: $receipt';

/// A temp worktree carrying the pinned diff plus [files] (path → body).
Directory _worktree({
  Map<String, String> files = const {_documentPath: _documentBody},
  bool pin = true,
}) {
  final dir = Directory.systemTemp.createTempSync('design-committee');
  addTearDown(() => dir.deleteSync(recursive: true));
  if (pin) {
    File(pinnedDiffPath(dir.path))
      ..createSync(recursive: true)
      ..writeAsStringSync(_pinnedDiff);
  }
  files.forEach((path, body) {
    File(p.join(dir.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
  });
  return dir;
}

/// The seven lane results a complete frontier hands the verifier: the docs
/// gates and the judges at A unless [judgments] / [gates] say otherwise.
Map<String, Map<String, String>> _lanes({
  Map<String, (String, String)> judgments = const {},
  Map<String, (String, String)> gates = const {},
  Set<String> silent = const {},
}) => {
  for (final lane in kDesignCommitteeRubrics)
    if (!silent.contains(lane))
      'pow-d1/review/$lane': {
        'grade': (gates[lane] ?? judgments[lane])?.$1 ?? 'A',
        'rationale': (gates[lane] ?? judgments[lane])?.$2 ?? '',
      },
};

/// One verifier run over [dir] with [results] as its sibling frontier.
Future<({Map<String, String> payload, FakeInferenceRunner inference})> _verify(
  Directory dir,
  Map<String, Map<String, String>> results, {
  String answer = '',
  bool ok = true,
  bool wired = true,
}) async {
  final inference = FakeInferenceRunner(output: answer, ok: ok);
  final outcome =
      await DesignVerifyCapability(inference: wired ? inference : null).run(
        FakeTreeContext(
          values: {
            Bead: _designBead(),
            Workspace: testWorkspace('pow-d1', workspaceDir: dir.path),
            SiblingView: SiblingView(results: results),
          },
        ),
        stepArgs(
          'pow-d1/review/$kDesignVerifyStep',
          params: {'grid.round': '2'},
        ),
      );
  return (payload: (outcome as Ok).payload!, inference: inference);
}

/// The verify artifact this round wrote.
Map<String, Object?> _artifact(Directory dir) =>
    jsonDecode(
          File(
            p.join(dir.path, '.grid', 'critique', '$kDesignVerifyStep.json'),
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  group('design path admission', () {
    test('isDesignPath admits the docs/design tree at any depth', () {
      for (final path in const [
        'docs/design/w2d-soak-gate.md',
        'docs/design/r7/cut-wiring.md',
        'docs/design/r7/appendix/ordering.md',
      ]) {
        expect(isDesignPath(path), isTrue, reason: path);
      }
    });

    test('isDesignPath refuses everything outside that ONE prefix', () {
      for (final path in const [
        // The directory itself is not a document.
        'docs/design',
        'docs/design/',
        // A string prefix is not a path prefix — the match is by SEGMENT.
        'docs/design.md',
        'docs/designs/x.md',
        // The tree is the REPO's, never a package's.
        'packages/grid_assets/docs/design/a.md',
        // A cited path is repo-relative, or it is not admitted.
        '/tmp/docs/design/a.md',
        '../docs/design/a.md',
        'docs/design/../../lib/src/code/committee.dart',
        // Ordinary docs, and ordinary source.
        'docs/adr/ADR-0000-ai-decision-register.md',
        'README.md',
        'lib/src/code/docs_committee.dart',
        '',
      ]) {
        expect(isDesignPath(path), isFalse, reason: path);
      }
    });

    test('a design-only bead classifies as design, ahead of the docs arm', () {
      expect(changeShapeOf(_designBead()), ChangeShape.design);
      // Every design path is ALSO a docs path — the ordering is what makes the
      // narrower arm reachable at all.
      expect(isDocsPath(_documentPath), isTrue);
    });

    test('an ordinary docs bead is UNCHANGED by the new arm', () {
      final docs = bead(
        'pow-d2',
      ).copyWith(design: '## Touches\n- `docs/adr/ADR-0009-x.md` — created\n');
      expect(changeShapeOf(docs), ChangeShape.docs);
    });

    test('a design doc MIXED with anything else falls through the ladder', () {
      final withDocs = bead('pow-d3').copyWith(
        design:
            '## Touches\n'
            '- `docs/design/r7.md`\n'
            '- `docs/adr/ADR-0009-x.md`\n',
      );
      expect(changeShapeOf(withDocs), ChangeShape.docs);
      final withSource = bead('pow-d4').copyWith(
        design:
            '## Touches\n'
            '- `docs/design/r7.md`\n'
            '- `lib/src/code/committee.dart`\n',
      );
      expect(changeShapeOf(withSource), ChangeShape.code);
    });

    test('a design bead roots a circuit whose review is design_review', () {
      const resolver = ChangeShapeCircuitResolver(kCodeCircuit);
      final review =
          resolver.circuitFor(ChangeShape.design).stepById(kReviewStepId)!
              as SubCircuitStep;
      expect(review.circuitId, kDesignReviewCircuitId);
      // The other three shapes are byte-unchanged.
      for (final pair in const [
        (ChangeShape.docs, kDocsReviewCircuitId),
        (ChangeShape.metadata, kDocsReviewCircuitId),
        (ChangeShape.code, 'code_review'),
      ]) {
        expect(
          (resolver.circuitFor(pair.$1).stepById(kReviewStepId)!
                  as SubCircuitStep)
              .circuitId,
          pair.$2,
        );
      }
    });
  });

  group('design circuit composition', () {
    test('its step ids are the gates, the judges, verify and route', () {
      expect(kDesignReviewCircuit.steps.map((s) => s.stepId), [
        kClearCritiqueStep,
        kPinDiffStep,
        ...kDocsGatingRubrics,
        ...kDesignJudgeRubrics,
        kDesignVerifyStep,
        'route',
      ]);
      expect(kDesignJudgeRubrics, [
        'ruling-adherence',
        'ordering-and-rollback',
        'fold-fidelity-and-ops',
        'cite-verification',
      ]);
      // The docs committee's judgemental lane is GONE, and so is every code
      // lane a prose diff cannot satisfy.
      for (final absent in const [
        'spec-adherence',
        'test-coverage',
        'regression-risk',
      ]) {
        expect(
          kDesignReviewCircuit.steps.map((s) => s.stepId),
          isNot(contains(absent)),
        );
      }
      expect(kDesignReviewCircuit.id, kDesignReviewCircuitId);
      expect(kDesignReviewCircuit.terminalStepId, 'route');
    });

    test('the three docs gates are copied from the docs circuit', () {
      for (final rubric in kDocsGatingRubrics) {
        final design = kDesignReviewCircuit.stepById(rubric)! as CapabilityStep;
        final docs = kDocsReviewCircuit.stepById(rubric)! as CapabilityStep;
        expect(design.capabilityId, docs.capabilityId);
        expect(design.capabilityId, kDocsCheckCapabilityId);
        expect(design.params, docs.params);
        expect(design.dependsOn, docs.dependsOn);
        expect(design.dependsOn, {kPinDiffStep});
      }
    });

    test('each judge is a rubric-selected critic on the pinned diff', () {
      for (final rubric in kDesignJudgeRubrics) {
        final judge = kDesignReviewCircuit.stepById(rubric)! as CapabilityStep;
        expect(judge.capabilityId, 'critic');
        expect(judge.params['rubric'], rubric);
        expect(judge.dependsOn, {kPinDiffStep});
      }
      expect(kDesignCommitteeRubrics, [
        ...kDocsGatingRubrics,
        ...kDesignJudgeRubrics,
      ]);
    });

    test('buildCodeRegistry registers the design_review circuit', () {
      final registry = buildCodeRegistry(overlaySourceRef: 'test');
      expect(
        identical(
          registry.circuit(kDesignReviewCircuitId),
          kDesignReviewCircuit,
        ),
        isTrue,
      );
      // Every capability the circuit names is one the docs/code committees
      // already register, plus the verifier this bead adds.
      expect(
        kDesignReviewCircuit.steps
            .whereType<CapabilityStep>()
            .map((s) => s.capabilityId)
            .toSet(),
        {
          kClearCritiqueStep,
          kPinDiffStep,
          kDocsCheckCapabilityId,
          'critic',
          kDesignVerifyStep,
          'route',
        },
      );
    });
  });

  group('design verify dependencies', () {
    test('design-verify joins EVERY gate and judge', () {
      final verify =
          kDesignReviewCircuit.stepById(kDesignVerifyStep)! as CapabilityStep;
      expect(verify.capabilityId, kDesignVerifyStep);
      expect(verify.dependsOn, kDesignCommitteeRubrics.toSet());
      expect(verify.dependsOn, hasLength(7));
    });

    test('route joins design-verify ALONE, and gates on it', () {
      final route = kDesignReviewCircuit.stepById('route')! as CapabilityStep;
      expect(route.capabilityId, 'route');
      expect(route.dependsOn, {kDesignVerifyStep});
      expect(route.params['critics'], kDesignVerifyStep);
      expect(route.params['gating'], kDesignVerifyStep);
      expect(
        route.params[kCommitteeSelectionStageParam],
        CommitteeStage.codeReview.wire,
      );
    });

    test('the frontier fans out seven lanes, then verify, then route', () {
      const parent = 'pow-d1/review';
      CircuitCursor done(List<String> ids) => {
        for (final id in ids)
          '$parent/$id': const NodeCursor(state: StepState.complete),
      };
      List<String> frontier(CircuitCursor cursor) => eligibleSteps(
        kDesignReviewCircuit,
        cursor,
        parent,
        circuitById: (_) => null,
        now: DateTime(2026),
      ).map((s) => s.stepId).toList();

      expect(
        frontier(done([kClearCritiqueStep, kPinDiffStep])),
        kDesignCommitteeRubrics,
      );
      expect(
        frontier(
          done([kClearCritiqueStep, kPinDiffStep, ...kDesignCommitteeRubrics]),
        ),
        [kDesignVerifyStep],
        reason: 'the route never sees a judge letter, only the verifier\'s',
      );
      expect(
        frontier(
          done([
            kClearCritiqueStep,
            kPinDiffStep,
            ...kDesignCommitteeRubrics,
            kDesignVerifyStep,
          ]),
        ),
        ['route'],
      );
    });
  });

  group('verifier adjudicates fake judgments', () {
    // One refutable, one confirmable-and-fixable, one confirmable-open.
    Map<String, Map<String, String>> threeFindings() => _lanes(
      judgments: {
        'ruling-adherence': (
          'F',
          [
            _finding(
              'BLOCKER',
              'R1',
              'the round ignores the harness-agnostic ruling',
              '"the station is the harness"',
            ),
            _finding(
              'MINOR',
              'R2',
              'the ruling date is unstated',
              'docs/design/w2d-soak-gate.md:1',
            ),
          ].join('\n'),
        ),
        'ordering-and-rollback': (
          'F',
          _finding(
            'BLOCKER',
            'O1',
            'the breaker trips AFTER the restore begins',
            'docs/design/w2d-soak-gate.md:5',
          ),
        ),
      },
    );

    // The verifier's answer to those three findings.
    String answer() => jsonEncode({
      'documents': {_documentPath: _revisedBody},
      'adjudications': [
        {
          'lane': 'ruling-adherence',
          'findingId': 'R1',
          'finding': 'the round ignores the harness-agnostic ruling',
          'severity': 'BLOCKER',
          'verdict': 'REFUTED',
          'why': 'the ruling is honoured in the Ordering section, line 5',
        },
        {
          'lane': 'ruling-adherence',
          'findingId': 'R2',
          'finding': 'the ruling date is unstated',
          'severity': 'MINOR',
          'verdict': 'CONFIRMED-OPEN',
          'why': 'the date is not in the bead; the author must supply it',
        },
        {
          'lane': 'ordering-and-rollback',
          'findingId': 'O1',
          'finding': 'the breaker trips AFTER the restore begins',
          'severity': 'BLOCKER',
          'verdict': 'CONFIRMED-FIXED',
          'why': 'the ordering sentence now trips the breaker first',
        },
      ],
    });

    test('it fixes the document and logs one verdict per finding', () async {
      final dir = _worktree();
      final run = await _verify(dir, threeFindings(), answer: answer());

      final document = File(p.join(dir.path, _documentPath)).readAsStringSync();
      expect(document, contains('trips BEFORE the restore begins'));
      expect(document, contains(kAdjudicationLogHeading));
      expect(document, contains('### Round 2'));
      for (final verdict in kDesignVerdicts) {
        expect(
          document,
          contains('**$verdict**'),
          reason: '$verdict is missing from the adjudication log',
        );
      }
      expect(document, contains('ruling-adherence/R1'));
      expect(document, contains('ordering-and-rollback/O1'));
      // The prompt named every finding and said a judgment is EVIDENCE.
      final brief = run.inference.calls.single.args.last;
      expect(brief, contains('EVIDENCE, NEVER FACT'));
      expect(brief, contains('ruling-adherence/R1'));
      expect(brief, contains(_documentBody.trim()));
    });

    test('only the CONFIRMED-OPEN finding reaches the route', () async {
      final dir = _worktree();
      final run = await _verify(dir, threeFindings(), answer: answer());
      expect(run.payload['grade'], 'F');
      final rationale = run.payload['rationale']!;
      expect(rationale, contains('ruling-adherence/R2'));
      expect(rationale, isNot(contains('ruling-adherence/R1')));
      expect(rationale, isNot(contains('ordering-and-rollback/O1')));
    });

    test('it writes the round-stamped verify artifact', () async {
      final dir = _worktree();
      await _verify(dir, threeFindings(), answer: answer());
      final artifact = _artifact(dir);
      expect(artifact['rubric'], kDesignVerifyStep);
      expect(artifact['version'], 1);
      expect(artifact['grade'], 'F');
      expect(artifact['nodePath'], 'pow-d1/review/$kDesignVerifyStep');
      expect(artifact['round'], 2);
      final adjudications = artifact['adjudications']! as List;
      expect(adjudications, hasLength(3));
      expect(adjudications.map((a) => (a! as Map)['verdict']), [
        'REFUTED',
        'CONFIRMED-OPEN',
        'CONFIRMED-FIXED',
      ]);
    });

    test(
      'fixed-and-refuted only means grade A and the round advances',
      () async {
        final dir = _worktree();
        final run = await _verify(
          dir,
          _lanes(
            judgments: {
              'ordering-and-rollback': (
                'F',
                _finding(
                  'BLOCKER',
                  'O1',
                  'the breaker trips AFTER the restore begins',
                  'docs/design/w2d-soak-gate.md:5',
                ),
              ),
            },
          ),
          answer: jsonEncode({
            'documents': {_documentPath: _revisedBody},
            'adjudications': [
              {
                'lane': 'ordering-and-rollback',
                'findingId': 'O1',
                'finding': 'the breaker trips AFTER the restore begins',
                'severity': 'BLOCKER',
                'verdict': 'CONFIRMED-FIXED',
                'why': 'the ordering sentence now trips the breaker first',
              },
            ],
          }),
        );
        expect(run.payload['grade'], 'A');
        expect(run.payload['rationale'], contains('fixed or refuted'));
        expect(_artifact(dir)['grade'], 'A');
      },
    );

    test('an earlier round log survives the next round', () async {
      final dir = _worktree(
        files: {
          _documentPath:
              '$_documentBody\n'
              '$kAdjudicationLogHeading\n'
              '\n'
              '### Round 1\n'
              '- **ordering-and-rollback/O9** (MINOR) — an earlier finding\n'
              '  - **REFUTED** — it was wrong then too\n',
        },
      );
      await _verify(dir, threeFindings(), answer: answer());
      final document = File(p.join(dir.path, _documentPath)).readAsStringSync();
      expect(document, contains('### Round 1'));
      expect(document, contains('ordering-and-rollback/O9'));
      expect(document, contains('### Round 2'));
      expect(kAdjudicationLogHeading.allMatches(document), hasLength(1));
    });

    test('four A lanes need no inference call at all', () async {
      final dir = _worktree();
      final run = await _verify(dir, _lanes());
      expect(run.inference.calls, isEmpty);
      expect(run.payload['grade'], 'A');
      expect(_artifact(dir)['adjudications'], isEmpty);
      // The document is UNTOUCHED — nothing was adjudicated, so nothing is
      // rewritten and no log is appended.
      expect(
        File(p.join(dir.path, _documentPath)).readAsStringSync(),
        _documentBody,
      );
    });
  });

  group('the verifier refuses LOUDLY', () {
    Future<void> expectRefusal(
      Future<({Map<String, String> payload, FakeInferenceRunner inference})>
      run,
      Matcher rationale,
    ) async {
      final outcome = await run;
      expect(outcome.payload['grade'], 'F');
      expect(outcome.payload['rationale'], rationale);
      expect(outcome.inference.calls, isEmpty);
    }

    test('a lane that did not report is a fail-closed miss', () async {
      await expectRefusal(
        _verify(_worktree(), _lanes(silent: {'cite-verification'})),
        contains('no grade from cite-verification'),
      );
    });

    test('a failed docs gate short-circuits, carrying its rationale', () async {
      await expectRefusal(
        _verify(
          _worktree(),
          _lanes(
            gates: {'citation-paths-resolve': ('F', 'cited path is gone')},
          ),
        ),
        allOf(
          contains('citation-paths-resolve'),
          contains('cited path is gone'),
        ),
      );
    });

    test('a missing pinned diff refuses', () async {
      await expectRefusal(
        _verify(_worktree(pin: false), _lanes()),
        contains('no pinned diff'),
      );
    });

    test('a diff with no design document refuses', () async {
      await expectRefusal(
        _verify(_worktree(files: const {}), _lanes()),
        contains('no `docs/design/**` document'),
      );
    });

    test('an unreadable judgment refuses BEFORE any inference', () async {
      await expectRefusal(
        _verify(
          _worktree(),
          _lanes(
            judgments: {
              'cite-verification': ('F', 'the citations are all broken'),
            },
          ),
        ),
        allOf(contains('unreadable judgment'), contains('not a finding')),
      );
    });

    test('a letter that contradicts its own findings refuses', () async {
      await expectRefusal(
        _verify(
          _worktree(),
          _lanes(
            judgments: {
              'cite-verification': (
                'A',
                _finding('MINOR', 'C1', 'a stale line number', 'x.md:2'),
              ),
            },
          ),
        ),
        contains('graded `A` but its 1 finding(s) map to `C`'),
      );
    });

    test('a duplicate finding id within a lane refuses', () async {
      await expectRefusal(
        _verify(
          _worktree(),
          _lanes(
            judgments: {
              'cite-verification': (
                'C',
                [
                  _finding('MINOR', 'C1', 'a stale line', 'x.md:2'),
                  _finding('MINOR', 'C1', 'another stale line', 'x.md:3'),
                ].join('\n'),
              ),
            },
          ),
        ),
        contains('raised finding id `C1` twice'),
      );
    });

    test('an unwired inference runner refuses rather than passing', () async {
      final dir = _worktree();
      final run = await _verify(
        dir,
        _lanes(
          judgments: {
            'cite-verification': (
              'C',
              _finding('MINOR', 'C1', 'a stale line', 'x.md:2'),
            ),
          },
        ),
        wired: false,
      );
      expect(run.payload['grade'], 'F');
      expect(run.payload['rationale'], contains('no InferenceRunner is wired'));
    });

    test('no ambient bead or workspace refuses without an artifact', () async {
      final outcome = await const DesignVerifyCapability().run(
        FakeTreeContext(),
        stepArgs(
          'pow-d1/review/$kDesignVerifyStep',
          params: {'grid.round': '2'},
        ),
      );
      final payload = (outcome as Ok).payload!;
      expect(payload['grade'], 'F');
      expect(payload['rationale'], contains('no ambient work Bead'));
    });
  });

  group('the verifier answer is validated WHOLE before a byte is written', () {
    Map<String, Map<String, String>> oneFinding() => _lanes(
      judgments: {
        'cite-verification': (
          'C',
          _finding('MINOR', 'C1', 'a stale line number', 'x.md:2'),
        ),
      },
    );

    Future<void> expectContractRefusal(String answer, Matcher rationale) async {
      final dir = _worktree();
      final run = await _verify(dir, oneFinding(), answer: answer);
      expect(run.payload['grade'], 'F');
      expect(run.payload['rationale'], rationale);
      // The document is untouched: validation precedes every write.
      expect(
        File(p.join(dir.path, _documentPath)).readAsStringSync(),
        _documentBody,
      );
    }

    test('an out-of-scope document key refuses', () async {
      await expectContractRefusal(
        jsonEncode({
          'documents': {
            _documentPath: _revisedBody,
            'lib/src/code/committee.dart': 'pwned',
          },
          'adjudications': const <Object>[],
        }),
        contains('OUT-OF-SCOPE document "lib/src/code/committee.dart"'),
      );
    });

    test('a dropped finding refuses', () async {
      await expectContractRefusal(
        jsonEncode({
          'documents': {_documentPath: _revisedBody},
          'adjudications': const <Object>[],
        }),
        contains('every finding is adjudicated exactly once'),
      );
    });

    test('an invented verdict refuses', () async {
      await expectContractRefusal(
        jsonEncode({
          'documents': {_documentPath: _revisedBody},
          'adjudications': [
            {
              'lane': 'cite-verification',
              'findingId': 'C1',
              'finding': 'a stale line number',
              'severity': 'MINOR',
              'verdict': 'PROBABLY-FINE',
              'why': 'it looked alright',
            },
          ],
        }),
        contains('unknown verdict "PROBABLY-FINE"'),
      );
    });

    test('a non-JSON answer refuses', () async {
      await expectContractRefusal(
        'I had a look and it seems fine to me.',
        contains('not readable JSON'),
      );
    });

    test('a run that did not complete refuses', () async {
      final dir = _worktree();
      final run = await _verify(dir, oneFinding(), ok: false);
      expect(run.payload['grade'], 'F');
      expect(
        run.payload['rationale'],
        contains('the verify inference did not complete'),
      );
    });

    test('a FENCED but otherwise strict answer is accepted', () async {
      final dir = _worktree();
      final run = await _verify(
        dir,
        oneFinding(),
        answer:
            '```json\n'
            '${jsonEncode({
              'documents': {_documentPath: _revisedBody},
              'adjudications': [
                {'lane': 'cite-verification', 'findingId': 'C1', 'finding': 'a stale line number', 'severity': 'MINOR', 'verdict': 'REFUTED', 'why': 'the line resolves at the round base commit'},
              ],
            })}\n'
            '```',
      );
      expect(run.payload['grade'], 'A');
    });
  });
}

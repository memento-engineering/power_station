// The DOCS-CHANGE committee — the third review type.
//
// Proves: the circuit's lane set (three deterministic gating lanes +
// spec-adherence, and NO test-coverage) and its frontier; the change-shape
// selection (a docs-only bead's root circuit points `review` at `docs_review`,
// a code bead's at `code_review`); each mechanical check's FAILING case and its
// passing case; and the three LOUD fail-closed refusals.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

/// A bead whose `## Touches` declares a DOCS-only surface.
Bead _docsBead({String? sections}) => bead('pow-1').copyWith(
  design: '## Touches\n- `docs/adr/ADR-0009-x.md` — created\n',
  metadata: sections == null ? const {} : {'docs_sections': sections},
);

/// A unified diff adding [lines] to [path].
String _diff(String path, List<String> lines) =>
    'diff --git a/$path b/$path\n'
    '--- a/$path\n'
    '+++ b/$path\n'
    '@@ -0,0 +1,${lines.length} @@\n'
    '${lines.map((l) => '+$l').join('\n')}\n';

/// A temp worktree carrying [diff] at the canonical pinned-diff path, plus any
/// [files] (path → body) the lanes must find on disk.
Directory _worktree(String diff, {Map<String, String> files = const {}}) {
  final dir = Directory.systemTemp.createTempSync('docs-committee');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(pinnedDiffPath(dir.path))
    ..createSync(recursive: true)
    ..writeAsStringSync(diff);
  files.forEach((path, body) {
    File('${dir.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
  });
  return dir;
}

/// Runs one docs lane over [dir] for [beadOverride] (the docs bead by default).
Future<Map<String, String>> _lane(
  String rubric,
  Directory dir, {
  Bead? beadOverride,
}) async {
  final out = await const DocsCheckCapability().run(
    FakeTreeContext(
      values: {
        Bead: beadOverride ?? _docsBead(),
        Workspace: testWorkspace('pow-1', workspaceDir: dir.path),
      },
    ),
    stepArgs('pow-1/review/$rubric', params: {'rubric': rubric}),
  );
  return (out as Ok).payload!;
}

void main() {
  group(
    'the docs circuit mounts the mechanical lanes and NOT test-coverage',
    () {
      test('its step ids are exactly the docs lane set', () {
        expect(kDocsReviewCircuit.steps.map((s) => s.stepId), [
          kClearCritiqueStep,
          kPinDiffStep,
          kCitationPathsRubric,
          kTerminologyBanRubric,
          kSectionStructureRubric,
          'spec-adherence',
          'route',
        ]);
        expect(
          kDocsReviewCircuit.steps.map((s) => s.stepId),
          isNot(contains('test-coverage')),
        );
        // The code committee is UNCHANGED — it still carries the lane.
        expect(
          kCodeReviewCircuit.steps.map((s) => s.stepId),
          contains('test-coverage'),
        );
      });

      test('the route params match the declared rubric lists', () {
        final route = kDocsReviewCircuit.stepById('route')! as CapabilityStep;
        expect(route.params['critics'], kDocsCommitteeRubrics.join(','));
        expect(route.params['gating'], kDocsGatingRubrics.join(','));
        expect(route.dependsOn, kDocsCommitteeRubrics.toSet());
      });

      test('the frontier fans the four lanes out, then joins on the route', () {
        const parent = 'pow-1/review';
        CircuitCursor done(List<String> ids) => {
          for (final id in ids)
            '$parent/$id': const NodeCursor(state: StepState.complete),
        };
        List<String> frontier(CircuitCursor cursor) => eligibleSteps(
          kDocsReviewCircuit,
          cursor,
          parent,
          circuitById: (_) => null,
          now: DateTime(2026),
        ).map((s) => s.stepId).toList();

        expect(frontier(done([kClearCritiqueStep, kPinDiffStep])), [
          kCitationPathsRubric,
          kTerminologyBanRubric,
          kSectionStructureRubric,
          'spec-adherence',
        ]);
        expect(
          frontier(
            done([kClearCritiqueStep, kPinDiffStep, ...kDocsCommitteeRubrics]),
          ),
          ['route'],
        );
      });
    },
  );

  group('change-shape selection picks the committee', () {
    test('a docs-only bead roots a circuit whose review is docs_review', () {
      const resolver = ChangeShapeCircuitResolver(kCodeCircuit);
      expect(changeShapeOf(_docsBead()), ChangeShape.docs);
      final review =
          resolver.circuitFor(ChangeShape.docs).stepById(kReviewStepId)!
              as SubCircuitStep;
      expect(review.circuitId, kDocsReviewCircuitId);
    });

    test('a code-touching bead still roots the code committee', () {
      final mixed = bead('pow-2').copyWith(
        design: '## Touches\n- `docs/x.md`\n- `lib/src/code/committee.dart`\n',
      );
      expect(changeShapeOf(mixed), ChangeShape.code);
      const resolver = ChangeShapeCircuitResolver(kCodeCircuit);
      final review =
          resolver.circuitFor(ChangeShape.code).stepById(kReviewStepId)!
              as SubCircuitStep;
      expect(review.circuitId, 'code_review');
    });

    test('an undeclared bead falls to the CODE committee', () {
      expect(changeShapeOf(bead('pow-3')), ChangeShape.code);
    });

    test('a root shape with no review step refuses LOUDLY', () {
      const bare = Circuit(
        id: 'code',
        terminalStepId: 'agent',
        steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
      );
      expect(
        () => withReviewCircuitId(bare, kDocsReviewCircuitId),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('citation-paths-resolve', () {
    test('F names a cited path that does not exist', () async {
      final dir = _worktree(
        _diff('docs/a.md', ['See `docs/nope/missing.md` for details.']),
        files: const {'docs/a.md': '# A'},
      );
      final payload = await _lane(kCitationPathsRubric, dir);
      expect(payload['grade'], 'F');
      expect(payload['rationale'], contains('docs/nope/missing.md'));
    });

    test('A when every cited path resolves', () async {
      final dir = _worktree(
        _diff('docs/a.md', ['See `docs/b.md` and `docs/`.']),
        files: const {'docs/a.md': '# A', 'docs/b.md': '# B'},
      );
      expect((await _lane(kCitationPathsRubric, dir))['grade'], 'A');
    });

    test('a commit range and a bare word are not paths', () {
      expect(normalizeCitedPath('origin/main...HEAD'), isNull);
      expect(normalizeCitedPath('dart'), isNull);
      expect(normalizeCitedPath('https://x.dev/a.md'), isNull);
      expect(normalizeCitedPath('lib/src/x.dart:Symbol'), 'lib/src/x.dart');
    });
  });

  group('terminology-ban', () {
    test('F on a bare use of the banned seam word', () async {
      final dir = _worktree(
        _diff('docs/a.md', ['Each extension ships as a plugin under lib/.']),
      );
      final payload = await _lane(kTerminologyBanRubric, dir);
      expect(payload['grade'], 'F');
      expect(payload['rationale'], contains('docs/a.md'));
    });

    test(
      'A when the word is QUOTED (a mention) or third-party qualified',
      () async {
        final dir = _worktree(
          _diff('docs/a.md', [
            'The seam word is extension, never "plugin".',
            'A `plugin` is not the seam word here.',
            'Flutter platform plugins keep their own name.',
          ]),
        );
        expect((await _lane(kTerminologyBanRubric, dir))['grade'], 'A');
      },
    );

    test('a GRAMMATICAL capital is not a proper noun — the ordinary offence '
        'still fails', () {
      expect(
        terminologyFindings(const {
          'docs/x.md': ['The plugin model is the wrong seam word.'],
        }),
        hasLength(1),
      );
    });

    test('maskQuotations blanks a quotation span in place', () {
      expect(maskQuotations('a "b" c').length, 'a "b" c'.length);
      expect(maskQuotations('> quoted plugin').trim(), isEmpty);
    });
  });

  group('section-structure', () {
    test('F when a declared section is missing from a changed doc', () async {
      final dir = _worktree(
        _diff('docs/a.md', ['# A', 'body']),
        files: const {'docs/a.md': '# A\n\n## Context\n\nbody\n'},
      );
      final payload = await _lane(
        kSectionStructureRubric,
        dir,
        beadOverride: _docsBead(sections: 'Context, Decision'),
      );
      expect(payload['grade'], 'F');
      expect(payload['rationale'], contains('Decision'));
    });

    test('A when the bead declares no sections', () async {
      final dir = _worktree(
        _diff('docs/a.md', ['# A']),
        files: const {'docs/a.md': '# A\n'},
      );
      expect((await _lane(kSectionStructureRubric, dir))['grade'], 'A');
    });

    test('a heading inside a fenced block is evidence, not a section', () {
      const fence = '```';
      expect(headingsOf('$fence\n## Decision\n$fence\n## Context\n'), {
        'Context',
      });
    });
  });

  group('the lanes refuse LOUDLY', () {
    test('a missing pinned diff is a fail-closed F', () async {
      final dir = Directory.systemTemp.createTempSync('docs-committee-empty');
      addTearDown(() => dir.deleteSync(recursive: true));
      final payload = await _lane(kTerminologyBanRubric, dir);
      expect(payload['grade'], 'F');
      expect(payload['rationale'], contains('no pinned diff'));
    });

    test('a missing ambient Bead/Workspace is a fail-closed F', () async {
      final out = await const DocsCheckCapability().run(
        FakeTreeContext(),
        stepArgs('pow-1/review/$kTerminologyBanRubric'),
      );
      expect(((out as Ok).payload)!['grade'], 'F');
    });

    test(
      'a diff touching a NON-docs file refuses the whole committee',
      () async {
        final dir = _worktree(
          _diff('lib/src/code/committee.dart', ['// changed']),
        );
        final payload = await _lane(kTerminologyBanRubric, dir);
        expect(payload['grade'], 'F');
        expect(payload['rationale'], contains('non-docs file'));
        expect(payload['rationale'], contains('lib/src/code/committee.dart'));
      },
    );

    test(
      'an unknown rubric id is a fail-closed F, not a silent pass',
      () async {
        final dir = _worktree(_diff('docs/a.md', ['ordinary prose']));
        final payload = await _lane('not-a-docs-lane', dir);
        expect(payload['grade'], 'F');
        expect(payload['rationale'], contains('misconfigured'));
      },
    );
  });

  group('the registry composes the pack', () {
    test('buildCodeRegistry registers the docs_review circuit', () {
      final registry = buildCodeRegistry(overlaySourceRef: 'test');
      expect(
        identical(registry.circuit(kDocsReviewCircuitId), kDocsReviewCircuit),
        isTrue,
      );
    });
  });
}

// The SPECIFY stage (bead `pow-6ao`) — the architect-equivalent harness ride
// that writes the implementation-ready spec INTO the bead, upstream of the
// build.
//
// Proves: the spawn rides the resolved harness exactly like the build agent
// (sh-wrapped claude, FT-2 usage capture, cwd at the activation); the brief
// carries the full bead + the spec contract (the bd CLI writes — testable
// `--acceptance` checkboxes, the four-section `--design`, the
// `validation_plan` metadata — the mandatory ADR-alignment grep of the
// substation's docs/adr register, and the pre-convene re-validation); the
// working agreement is the ARCHITECT's (read-only tree, no commit/push/PR);
// and the Q3′ fence holds (no bead-stamped path reaches the brief). Zero I/O —
// no real claude/bd/git.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

({FakeTreeContext context, StepArgs args}) _ctx({
  Bead? beadOverride,
  String workspaceDir = '/w/tg-1',
}) => (
  context: FakeTreeContext(
    values: {
      Bead: beadOverride ?? bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
    },
  ),
  args: stepArgs('tg-1/spec_review/specify'),
);

Bead _fullBead() => bead('tg-1').copyWith(
  title: 'Wire the federation bus',
  description: 'Connect The Studio to The Dashboard.',
  design: 'A lossy inter-station gossip bus.',
  acceptanceCriteria: 'A peer heartbeat surfaces within 1s.',
  notes: 'Coexistence-safe; do not touch live convergence traffic.',
  metadata: const {'rig': 'tgdog'},
);

void main() {
  group('CarriedSpec', () {
    for (final entry in <String, String?>{
      'null': null,
      'non-JSON': 'not json',
      'a JSON list': '[]',
      'missing fields': '{}',
      'blank acceptance': '{"acceptance":" ","design":"design"}',
      'blank design': '{"acceptance":"acceptance","design":" "}',
      'acceptance only': '{"acceptance":"acceptance"}',
      'design only': '{"design":"design"}',
    }.entries) {
      test('${entry.key} returns null', () {
        expect(CarriedSpec.tryParse(entry.value), isNull);
      });
    }

    test('preserves exact multiline acceptance and design', () {
      const acceptance = '- [ ] first\n- [ ] second';
      const design = '## Implementation Plan\n\n### Step 1 — change\n';
      final carried = CarriedSpec.tryParse(
        jsonEncode({'acceptance': acceptance, 'design': design}),
      );
      expect(carried?.acceptance, acceptance);
      expect(carried?.design, design);
      expect(carried?.toResultFields(), {
        kCarriedSpecAcceptanceKey: acceptance,
        kCarriedSpecDesignKey: design,
      });
    });
  });

  group('SpecifyCapability.spawn — the architect harness ride', () {
    test('spawns claude WRAPPED for usage capture, cwd at the activation '
        '(FT-2, ADR-0008 Decision 10)', () {
      final c = _ctx();
      final cfg = const SpecifyCapability().spawn(c.context, c.args);
      expect(cfg.command, 'sh');
      expect(cfg.args[0], '-c');
      expect(
        cfg.args[1],
        contains('.grid/telemetry/tg-1_spec_review_specify.usage.json'),
      );
      expect(cfg.args, contains('claude'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
      // The rendered brief rides the argv and carries the spec contract.
      expect(cfg.args.last, contains('bd update tg-1'));
    });

    test('a missing ambient Bead/Workspace throws (fail-closed, per-work '
        'Failed via the allocation)', () {
      final noBead = FakeTreeContext(
        values: {Workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1')},
      );
      expect(
        () => const SpecifyCapability().spawn(
          noBead,
          stepArgs('tg-1/spec_review/specify'),
        ),
        throwsStateError,
      );
    });

    test('a clean exit completes; a non-zero exit / death fails', () {
      const cap = SpecifyCapability();
      const name = 'tgdog-s/tg-1/spec_review/specify';
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 0)),
        StepSignal.complete,
      );
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 3)),
        StepSignal.failed,
      );
      expect(cap.interpretEvent(const Died(name: name)), StepSignal.failed);
    });
  });

  group('buildSpecifyBrief — the spec contract', () {
    final brief = buildSpecifyBrief(
      _fullBead(),
      testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1'),
    );
    final rendered = brief.render();

    test('renders the FULL bead (A36) + the substation reference', () {
      expect(rendered, contains('Wire the federation bus'));
      expect(rendered, contains('Connect The Studio to The Dashboard.'));
      expect(rendered, contains('A lossy inter-station gossip bus.'));
      expect(rendered, contains('A peer heartbeat surfaces within 1s.'));
      expect(rendered, contains('substation `tgdog`'));
    });

    test('names the bd CLI writes: --acceptance checkboxes, the four-section '
        '--design, the validation_plan metadata — always --actor specify', () {
      expect(rendered, contains('bd update tg-1 --actor specify --acceptance'));
      expect(rendered, contains('bd update tg-1 --actor specify --design'));
      expect(rendered, contains('--set-metadata validation_plan='));
      expect(rendered, contains('- [ ]'));
      expect(rendered, contains('## Implementation Plan'));
      expect(rendered, contains('## Touches'));
      expect(rendered, contains('## ADR Alignment'));
      expect(rendered, contains('## Validation Plan'));
    });

    test('the plan contract is the station\'s: Dart code, exact paths, exact '
        'dart test commands, conventional commits, the house set + D-H', () {
      expect(rendered, contains('dart test'));
      expect(rendered, contains('conventional-commit'));
      expect(rendered, contains('freezed'));
      expect(rendered, contains('exhaustive'));
      expect(rendered, contains('Fakes not mocks'));
      expect(rendered, contains('D-H doctrine'));
    });

    test('the ADR Alignment section is MANDATORY and greps the SUBSTATION\'s '
        'docs/adr register (ADR-0000 amendments included)', () {
      expect(rendered, contains('MANDATORY'));
      expect(rendered, contains('docs/adr/*.md'));
      expect(rendered, contains('ADR-0000'));
      expect(rendered, contains('No ADR applies — verified via grep on'));
    });

    test('carries the pre-convene re-validation: grep callers/tests of every '
        'touched symbol + the sibling cross-check', () {
      expect(rendered, contains('Pre-convene re-validation'));
      expect(rendered, contains('grep -rn "<symbol>"'));
      expect(rendered, contains("--include='*.dart'"));
      expect(rendered, contains('bd dep list tg-1'));
      expect(rendered, contains('Re-validated against the live tree'));
      expect(rendered, contains('exactly one JSON object'));
      expect(
        rendered,
        contains(
          '{"acceptance":"<the exact value passed to --acceptance>",'
          '"design":"<the exact value passed to --design>"}',
        ),
      );
      expect(rendered, contains('no Markdown fence and no surrounding prose'));
    });

    test('the working agreement is the ARCHITECT\'s: read-only tree, no '
        'commit/push/PR, spec into the bead, no status transitions', () {
      final agreement = brief.workingAgreement;
      expect(agreement, contains('READ-ONLY'));
      expect(agreement, contains('do NOT edit, commit, or push'));
      expect(agreement, contains('do NOT open a pull request'));
      expect(agreement, contains('--actor specify'));
      expect(agreement, contains('Do NOT transition'));
      expect(agreement, contains('/w/tg-1'));
      expect(agreement, contains('grid/tg-1'));
      expect(agreement, contains('exactly one JSON object'));
      expect(agreement, contains('no Markdown fence and no surrounding prose'));
    });

    test('Q3′ (Track E): a bead-stamped path never reaches the brief — the '
        'only paths are the ambient Workspace\'s', () {
      const poison = 'POISON';
      final poisoned = _fullBead().copyWith(
        metadata: const {
          'rig': 'tgdog',
          'grid.root': '$poison/grid-root-from-bead',
          'worktree': '$poison/worktree-from-bead',
          'branch': '$poison-branch-from-bead',
        },
      );
      final b = buildSpecifyBrief(
        poisoned,
        testWorkspace(
          'tg-1',
          workspaceDir: '/real/activation/worktree/tg-1',
          branch: 'grid/tg-1',
        ),
      );
      final r = b.render();
      expect(r, isNot(contains(poison)));
      expect(r, contains('/real/activation/worktree/tg-1'));
    });

    test('renders the DETERMINISTIC structural contract + the round-tripped '
        'exemplar, so the gate\'s rules and the architect\'s brief are one '
        'string (`pow-77g`)', () {
      expect(rendered, contains(kSpecStructuralContract));
      expect(rendered, contains(kSpecExemplarDesign));
      expect(rendered, contains('DETERMINISTIC'));
      // Both accepted ordinal shapes are NAMED — the format-only F this bead
      // closes was an agent writing the heading form the brief never mentioned.
      expect(rendered, contains('1. …'));
      expect(rendered, contains('### Step 1 — …'));
    });
  });

  group('SpecifyCapability.result — FT-2 usage merge (capture-only)', () {
    test('an absent envelope yields null (fail-safe, never a throw)', () async {
      final c = _ctx(workspaceDir: '/nonexistent/w/tg-1');
      expect(await const SpecifyCapability().result(c.context, c.args), isNull);
    });

    test(
      'a captured envelope merges usage and the exact carried spec',
      () async {
        final dir = Directory.systemTemp.createTempSync('specify-usage-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const acceptance = '- [ ] exact acceptance\n- [ ] second line';
        const design = '## Implementation Plan\n\n### Step 1 — exact design\n';
        File('${dir.path}/${usageReportPath('tg-1/spec_review/specify')}')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'type': 'result',
              'duration_ms': 100,
              'num_turns': 2,
              'total_cost_usd': 0.01,
              'usage': {'input_tokens': 10, 'output_tokens': 5},
              'result': jsonEncode({
                'acceptance': acceptance,
                'design': design,
              }),
            }),
          );
        final c = _ctx(workspaceDir: dir.path);
        final fields = await const SpecifyCapability().result(
          c.context,
          c.args,
        );
        expect(fields, isNotNull);
        expect(fields!['tokensIn'], '10');
        expect(fields['tokensOut'], '5');
        expect(fields['numTurns'], '2');
        expect(fields[kCarriedSpecAcceptanceKey], acceptance);
        expect(fields[kCarriedSpecDesignKey], design);
      },
    );
  });

  group(
    'buildSpecifyBrief — the AUTO-RESPEC correction guidance (`pow-7nm`)',
    () {
      const ledger = RespecLedger(
        round: 2,
        lanes: [
          RespecLane(
            rubric: 'acceptance-testability',
            grade: 'D',
            rationale: 'criterion 2 names no command that proves it',
          ),
        ],
      );

      test(
        'with a ledger: the failing lane\'s rationale rides the brief VERBATIM, '
        'ahead of the job contract',
        () {
          final rendered = buildSpecifyBrief(
            _fullBead(),
            testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1'),
            guidance: ledger,
          ).render();
          expect(rendered, contains('RESPEC round 2 of 2'));
          expect(rendered, contains('`acceptance-testability` — grade D'));
          expect(
            rendered,
            contains('criterion 2 names no command that proves it'),
          );
          expect(
            rendered.indexOf('Correction guidance'),
            lessThan(rendered.indexOf('## Your job')),
            reason: 'the correction guidance is read BEFORE the job contract',
          );
        },
      );

      test('without a ledger: no correction-guidance section at all (a first '
          'round is byte-identical to the pre-pow-7nm brief)', () {
        final rendered = buildSpecifyBrief(
          _fullBead(),
          testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1'),
        ).render();
        expect(rendered, isNot(contains('Correction guidance')));
        expect(rendered, isNot(contains('RESPEC')));
      });
    },
  );

  // The SEAM (the bead's load-bearing criterion, proven end-of-wire): the ledger
  // the spec route left in the WORKTREE reaches the re-specify agent's ARGV.
  // This spawns over a REAL temp worktree, so `SpecifyCapability.spawn`'s ledger
  // read is LIVE — delete it and the first test here goes red.
  group('SpecifyCapability.spawn — the respec ledger reaches the ARGV '
      '(`pow-7nm`)', () {
    late Directory ws;
    setUp(() => ws = Directory.systemTemp.createTempSync('pow7nm-spawn'));
    tearDown(() => ws.deleteSync(recursive: true));

    RuntimeConfig spawnIn(Directory dir) {
      final c = _ctx(workspaceDir: dir.path);
      return const SpecifyCapability().spawn(c.context, c.args);
    }

    test('a ledger in the LIVE worktree rides the spawned brief VERBATIM — the '
        'critic\'s recommendation reaches the re-specify agent', () {
      writeRespecLedger(
        ws.path,
        const RespecLedger(
          round: 1,
          lanes: [
            RespecLane(
              rubric: 'plan-completeness',
              grade: 'D',
              rationale: 'step 3 names no test command',
            ),
          ],
        ),
      );
      final cfg = spawnIn(ws);
      expect(cfg.args.last, contains('Correction guidance'));
      expect(cfg.args.last, contains('RESPEC round 1 of 2'));
      expect(cfg.args.last, contains('step 3 names no test command'));
      expect(cfg.args.last, contains('`plan-completeness` — grade D'));
    });

    test('the SAME live worktree with NO ledger ⇒ no guidance on the argv (a '
        'first round spawns the unchanged brief)', () {
      final cfg = spawnIn(ws);
      expect(cfg.args.last, isNot(contains('Correction guidance')));
      expect(cfg.args.last, isNot(contains('RESPEC')));
      expect(cfg.args.last, contains('bd update tg-1'));
    });
  });
}

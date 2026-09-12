// The SPECIFY stage (bead `pow-6ao`) — the architect-equivalent harness ride
// that writes the implementation-ready spec INTO the bead, upstream of the
// build.
//
// Proves: the spawn rides the resolved harness exactly like the build agent
// (sh-wrapped claude, FT-2 usage capture, cwd at the activation); the brief
// carries the full bead + the spec contract (the bd CLI writes — testable
// `--acceptance` checkboxes, the four-section `--design`, the
// `validation_plan` metadata — the mandatory ADR-alignment grep of both local
// decision-register directories, and the pre-convene re-validation); the
// working agreement is the ARCHITECT's (read-only tree, no commit/push/PR);
// and the Q3′ fence holds (no bead-stamped path reaches the brief). Zero I/O —
// no real claude/bd/git.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' show SpecifyAuthoredSpecWriter;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

({FakeTreeContext context, StepArgs args}) _ctx({
  Bead? beadOverride,
  String workspaceDir = '/w/tg-1',
  AgentConfig? agentConfig,
  Map<Type, Object> seat = const {},
}) => (
  context: FakeTreeContext(
    values: {
      Bead: beadOverride ?? bead('tg-1'),
      Workspace: testWorkspace(
        'tg-1',
        workspaceDir: workspaceDir,
        branch: 'grid/tg-1',
      ),
      if (agentConfig != null) AgentConfig: agentConfig,
      ...seat,
    },
  ),
  args: stepArgs('tg-1/spec_review/specify'),
);

/// The SPECIFY step exactly as [kSpecReviewCircuit] declares it — so a probe
/// resolves the capability the STATION composes, never a hand-wired pair the
/// wire never mounts.
StepMount _specifyMount() => StepMount(
  step: kSpecReviewCircuit.steps.whereType<CapabilityStep>().singleWhere(
    (step) => step.stepId == kSpecifyStep,
  ),
  nodePath: 'tg-1/spec_review/specify',
  circuit: kSpecReviewCircuit,
  circuitPath: 'tg-1/spec_review',
  session: const SessionHandle('tgdog-sess1'),
  node: const NodeCursor(),
  key: const ValueKey('tg-1/spec_review/specify#0.0'),
);

/// The specify capability as the REAL registry composes it, over the owned-work
/// writer extension [writeSpecifyAuthoredSpec].
SpecifyCapability _composedSpecify({
  SpecifyAuthoredSpecWriter? writeSpecifyAuthoredSpec,
  BdRunner Function(String workspaceRoot)? specifyBdRunnerFor,
}) {
  final host =
      buildCodeRegistry(
            overlaySourceRef: 'test',
            specifyBdRunnerFor: specifyBdRunnerFor,
            writeSpecifyAuthoredSpec: writeSpecifyAuthoredSpec,
          ).host(_specifyMount())
          as CapabilityHost;
  return host.capability as SpecifyCapability;
}

/// A recording [SpecifyAuthoredSpecWriter] — Fakes, not mocks. Pass [record]
/// as the tear-off; the capability sees a plain closure.
final class _RecordingSpecWriter {
  final List<({String beadId, String design, String acceptanceCriteria})>
  calls = [];

  Future<void> record(
    String beadId, {
    required String design,
    required String acceptanceCriteria,
  }) async => calls.add((
    beadId: beadId,
    design: design,
    acceptanceCriteria: acceptanceCriteria,
  ));
}

/// Writes ONE harness result envelope at [nodePath] under a fresh temp
/// workspace, carrying [result] as the agent's final response text.
Directory _envelopeWorkspace(
  String? result, {
  String nodePath = 'tg-1/spec_review/specify',
}) {
  final dir = Directory.systemTemp.createTempSync('specify-stamp-');
  if (result != null) {
    File('${dir.path}/${usageReportPath(nodePath)}')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'type': 'result',
          'duration_ms': 100,
          'num_turns': 2,
          'usage': {'input_tokens': 10, 'output_tokens': 5},
          'result': result,
        }),
      );
  }
  return dir;
}

/// The station chokepoint over a recording runner — ONE writer instance, the
/// per-id serialization intact (never a second writer built in a capability).
StationBeadWriter _chokepoint(RecordingBdRunner runner) => StationBeadWriter(
  bd: BdCliService(runner),
  reader: runner,
  ownership: BeadOwnershipPredicate(const {'tg'}),
);

/// The recorded MUTATIONS — `bd update --help` is `BdCliService`'s one-shot
/// guarded-write CAPABILITY PROBE, not a write, so it never counts as one.
List<List<String>> _mutations(RecordingBdRunner runner) => runner.calls
    .where((call) => !(call.length == 2 && call[1] == '--help'))
    .toList(growable: false);

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

  group('SpecifyCapability.spawn — the spec seat\'s harness ride', () {
    test(
      'rides its SpecAgentEnvironment seat through the ACP CHANNEL, not argv',
      () {
        final c = _ctx(
          seat: {
            SpecAgentEnvironment: SpecAgentEnvironment([
              kBuiltinEnvironments['codex']!,
            ]),
          },
        );
        final cfg = const SpecifyCapability().spawn(c.context, c.args);
        // codex declares `sessionAdapter: 'acp'`, so the launch is the BRIDGE
        // and the codex identity rides the bridge spec — never argv. This test
        // used to pass on `argv contains 'codex'`, which was true only because
        // the string sits inside the npx PACKAGE NAME: the very argv that
        // proved the bug. Before this the seat rendered
        // `npx … codex-acp --model …` as a ONE-TURN process with no brief.
        expect(cfg.lifecycle, Lifecycle.longLived);
        expect(cfg.command, Platform.resolvedExecutable);
        expect(cfg.args.join(' '), isNot(contains('codex')));
        expect(cfg.args.join(' '), isNot(contains('claude')));
        final spec = AcpBridgeSpec.fromJson(
          (jsonDecode(cfg.env[kAcpBridgeSpecEnvironment]!)
                  as Map<String, dynamic>)
              .cast<String, Object?>(),
        );
        expect(spec.command, 'npx');
        expect(spec.args, contains('@agentclientprotocol/codex-acp@1.6.2'));
        expect(spec.model, 'gpt-5.6-sol');
        expect(
          spec.usageOut,
          '.grid/telemetry/tg-1_spec_review_specify.usage.json',
        );
      },
    );

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

  group('SpecifyCapability completion artifact durability', () {
    test(
      'declares durability and clears only on a fresh non-empty bead',
      () async {
        final runner = SpecifyReadbackBdRunner(
          beads: [durableSpecifiedBead('tg-1')],
        );
        final cap = SpecifyCapability(runnerFor: (_) => runner);
        final c = _ctx();
        expect(cap.completionContract, CompletionContract.artifactDurability);
        expect(
          await cap.probeCompletionArtifact(c.context, c.args),
          GateOutcome.clear,
        );
        expect(runner.calls, [
          ['query', 'id=tg-1', '--json', '--limit', '0'],
        ]);
        expect(runner.stdins, [isNull]);
      },
    );

    for (final entry in <String, Bead?>{
      'absent': null,
      'non-matching': durableSpecifiedBead('tg-2'),
      'blank acceptance': durableSpecifiedBead(
        'tg-1',
      ).copyWith(acceptanceCriteria: ' '),
      'blank design': durableSpecifiedBead('tg-1').copyWith(design: '\n'),
    }.entries) {
      test('${entry.key} durable state is present/not-durable', () async {
        final bead = entry.value;
        final runner = SpecifyReadbackBdRunner(beads: [if (bead != null) bead]);
        final c = _ctx();
        expect(
          await SpecifyCapability(
            runnerFor: (_) => runner,
          ).probeCompletionArtifact(c.context, c.args),
          GateOutcome.present,
        );
      });
    }

    test('duplicate exact-id rows are a probe error', () async {
      final bead = durableSpecifiedBead('tg-1');
      final runner = SpecifyReadbackBdRunner(beads: [bead, bead]);
      final c = _ctx();
      expect(
        await SpecifyCapability(
          runnerFor: (_) => runner,
        ).probeCompletionArtifact(c.context, c.args),
        GateOutcome.probeError,
      );
    });

    for (final entry in <String, SpecifyReadbackBdRunner>{
      'bd failure': SpecifyReadbackBdRunner(
        result: const BdResult(
          exitCode: 1,
          stdout: '',
          stderr: 'forced bd failure',
        ),
      ),
      'malformed envelope': SpecifyReadbackBdRunner(
        result: const BdResult(
          exitCode: 0,
          stdout: 'not an envelope',
          stderr: '',
        ),
      ),
      'timeout': SpecifyReadbackBdRunner(
        error: const BdTimeoutException(
          command: ['bd', 'query', 'id=tg-1'],
          timeout: Duration(seconds: 15),
        ),
      ),
    }.entries) {
      test('${entry.key} is a probe error', () async {
        final c = _ctx();
        expect(
          await SpecifyCapability(
            runnerFor: (_) => entry.value,
          ).probeCompletionArtifact(c.context, c.args),
          GateOutcome.probeError,
        );
      });
    }

    test('a missing workspace is a probe error', () async {
      final runner = SpecifyReadbackBdRunner(
        beads: [durableSpecifiedBead('tg-1')],
      );
      final context = FakeTreeContext(values: {Bead: bead('tg-1')});
      expect(
        await SpecifyCapability(
          runnerFor: (_) => runner,
        ).probeCompletionArtifact(
          context,
          stepArgs('tg-1/spec_review/specify'),
        ),
        GateOutcome.probeError,
      );
      expect(runner.calls, isEmpty);
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

    test('brief teaches the POSIX shell authoring rule', () {
      // The plan the architect writes here is executed, a build later, as
      // `sh -c '( <plan> )'`. Refusing an unparseable one at the specify
      // boundary only helps if the brief said how to write a parseable one
      // first — so the rule rides the machine-gate paragraph VERBATIM.
      expect(
        rendered,
        contains(
          'The plan runs under POSIX `sh -c` as a single line; use double '
          'quotes around any text containing an apostrophe, never paste bead '
          'prose into a single-quoted program, and check the line with `sh -n` '
          'before writing it.',
        ),
      );
    });

    test('a BOUND grid home makes every lookup the brief names RUNNABLE — the '
        'cwd the station\'s verb resolves from rides the command', () {
      final bound = buildSpecifyBrief(
        _fullBead(),
        testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1'),
        runner: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      ).render();
      const qualified =
          "cd '/grid/lunar' && dart run lunar:lunar decisions index --surface";
      expect(bound, contains('$qualified <repo>/<path>'));
      expect(
        bound,
        contains(
          decisionLookupRule(
            runner: 'dart run lunar:lunar',
            gridHome: '/grid/lunar',
          ),
        ),
      );
      // The exemplar and the structural contract render the SAME binding —
      // the architect is never shown a form it is then told not to write.
      expect(
        bound,
        contains(
          noGoverningDecisionSentence(
            runner: 'dart run lunar:lunar',
            gridHome: '/grid/lunar',
          ),
        ),
      );
      expect(
        bound,
        contains(
          failedDecisionLookupSentence(
            runner: 'dart run lunar:lunar',
            gridHome: '/grid/lunar',
          ),
        ),
      );
      expect(bound, isNot(contains('space decisions index')));
      // No unqualified survivor: strip the qualified form and nothing that
      // invokes lunar is left.
      expect(
        bound.replaceAll(qualified, '').contains('lunar:lunar decisions'),
        isFalse,
      );
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

    test('the ADR Alignment section is MANDATORY and queries the ROSTER union, '
        'never a local register', () {
      expect(rendered, contains('MANDATORY'));
      // This brief composes NO grid home, so the rule is the honest form: it
      // names no invocation the architect could not run from its worktree.
      expect(rendered, contains(kDecisionLookupRule));
      expect(rendered, contains('EVERY mounted register'));
      expect(rendered, isNot(contains('decisions index --surface')));
      expect(rendered, isNot(contains('```sh\n```')));
      for (final token in kLocalOnlyTokens) {
        expect(rendered, isNot(contains(token)));
      }
      expect(rendered, contains('ADR-0000'));
      expect(rendered, contains(kDecisionWriteRule));
      expect(rendered, isNot(contains('living AI-decision register')));
      expect(rendered, contains('the_grid#admission-authority-boundary'));
      expect(rendered, contains('No recorded decision governs these surfaces'));
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
        // A carried result re-reads the bead for its authored machine gate, so
        // even a usage-only assertion needs the read-back seam injected.
        final fields = await SpecifyCapability(
          runnerFor: (_) => SpecifyReadbackBdRunner(),
        ).result(c.context, c.args);
        expect(fields, isNotNull);
        expect(fields!['tokensIn'], '10');
        expect(fields['tokensOut'], '5');
        expect(fields['numTurns'], '2');
        expect(fields[kCarriedSpecAcceptanceKey], acceptance);
        expect(fields[kCarriedSpecDesignKey], design);
      },
    );
  });

  // The SPECIFY PROVENANCE stamp: the agent authored the prose with its own raw
  // `bd update --actor specify`, which carries NO metadata, and `--actor` is an
  // audit-trail string bd never replays — so nothing the agent runs can mark the
  // prose as specify-authored, and a rework that preserves unmarked prose would
  // preserve STALE specify text forever. The station stamps instead, through the
  // one chokepoint, off the envelope the step already parses.
  group('SpecifyCapability.result — the SPECIFY provenance stamp', () {
    const acceptance =
        '- [ ] AC-1 — the stamp carries the exact acceptance\n'
        '- [ ] AC-2 — verbatim, both lines';
    const design =
        '## Implementation Plan\n\n### Step 1 — stamp the provenance\n';

    setUp(BdCliService.resetGuardedWriteCapabilityForTesting);

    test('well-formed envelope calls the registry writer seam with exact '
        'carried spec', () async {
      // The registry threads the extension into the seat it composes. Driven
      // over an INJECTED read-back runner: a carried result also parse-checks
      // the authored machine gate, which re-reads the bead, and the
      // `specifyBdRunnerFor == null` arm composes the production
      // `ProcessBdRunner` — a real `bd` this offline suite must never launch.
      // That arm still runs in the invalid-envelope cases below, where an
      // unusable envelope means no read-back at all.
      final dir = _envelopeWorkspace(
        jsonEncode({'acceptance': acceptance, 'design': design}),
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final recorder = _RecordingSpecWriter();
      final c = _ctx(workspaceDir: dir.path);
      final fields = await _composedSpecify(
        writeSpecifyAuthoredSpec: recorder.record,
        specifyBdRunnerFor: (_) => SpecifyReadbackBdRunner(),
      ).result(c.context, c.args);

      expect(recorder.calls, hasLength(1));
      expect(recorder.calls.single.beadId, 'tg-1');
      expect(recorder.calls.single.design, design);
      expect(recorder.calls.single.acceptanceCriteria, acceptance);
      // The step's own carried result is the SAME pair — one read, one parse.
      expect(fields?[kCarriedSpecAcceptanceKey], acceptance);
      expect(fields?[kCarriedSpecDesignKey], design);
      expect(fields?['tokensIn'], '10');

      // The brief's audit trail is untouched: the agent still runs both raw
      // `--actor specify` writes; the stamp is the station's SECOND write over
      // them, never a change to what the architect was told to run.
      final brief = buildSpecifyBrief(
        _fullBead(),
        testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1'),
      ).render();
      expect(
        brief,
        contains("`bd update tg-1 --actor specify --acceptance '<criteria>'`"),
      );
      expect(
        brief,
        contains("`bd update tg-1 --actor specify --design '<spec>'`"),
      );
    });

    test('an absent extension leaves today\'s behaviour exactly as it was '
        '(no write, carried fields intact)', () async {
      final dir = _envelopeWorkspace(
        jsonEncode({'acceptance': acceptance, 'design': design}),
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = _ctx(workspaceDir: dir.path);
      final fields = await _composedSpecify(
        specifyBdRunnerFor: (_) => SpecifyReadbackBdRunner(),
      ).result(c.context, c.args);
      expect(fields?[kCarriedSpecAcceptanceKey], acceptance);
      expect(fields?[kCarriedSpecDesignKey], design);
    });

    test('writeSpecifyAuthoredSpec emits one guarded provenance update', () async {
      final runner = RecordingBdRunner()..exportBeads = [workBead('tg-1')];
      await _chokepoint(runner).writeSpecifyAuthoredSpec(
        'tg-1',
        design: design,
        acceptanceCriteria: acceptance,
      );

      // ONE bd call, the FULL argv: the design rides stdin (`--design-file -`),
      // the acceptance rides argv, and the provenance merges in the SAME update
      // — never a second, separately-failable metadata write.
      expect(_mutations(runner), [
        [
          'update',
          'tg-1',
          '--json',
          '--actor',
          BdCliService.actor,
          '--design-file',
          '-',
          '--acceptance',
          acceptance,
          '--set-metadata',
          '${StationBeadWriter.specAuthorKey}='
              '${StationBeadWriter.specifyAuthor}',
        ],
      ]);
      expect(runner.stdins.last, design);
      expect(BdCliService.actor, 'grid-controller');
      // Invariant 2 at the writer: bd CLI only, never a `show` read-back and
      // never raw `sql`.
      expect(
        runner.calls.map((call) => call.first),
        everyElement(isNot(anyOf('show', 'sql'))),
      );
    });

    test(
      'clearRoundAuthoredSpec clears only specify-authored fields',
      () async {
        final staged = workBead(
          'tg-1',
        ).copyWith(design: design, acceptanceCriteria: acceptance);
        // Only SPECIFY provenance is this station's to clear. Unmarked prose is
        // pre-marker or hand-authored; `operator` is explicitly the human's.
        for (final provenance in <String, String?>{
          'unmarked': null,
          StationBeadWriter.operatorAuthor: StationBeadWriter.operatorAuthor,
        }.entries) {
          BdCliService.resetGuardedWriteCapabilityForTesting();
          final preserved = provenance.value == null
              ? staged
              : staged.copyWith(
                  metadata: {StationBeadWriter.specAuthorKey: provenance.value},
                );
          final runner = RecordingBdRunner()..exportBeads = [preserved];
          await _chokepoint(runner).clearRoundAuthoredSpec('tg-1');
          expect(_mutations(runner), isEmpty, reason: provenance.key);
          expect(runner.exportBeads.single.design, design);
          expect(runner.exportBeads.single.acceptanceCriteria, acceptance);
        }

        BdCliService.resetGuardedWriteCapabilityForTesting();
        final runner = RecordingBdRunner()
          ..exportBeads = [
            staged.copyWith(
              metadata: const {
                StationBeadWriter.specAuthorKey:
                    StationBeadWriter.specifyAuthor,
              },
            ),
          ];
        await _chokepoint(runner).clearRoundAuthoredSpec('tg-1');
        expect(_mutations(runner), [
          [
            'update',
            'tg-1',
            '--json',
            '--actor',
            BdCliService.actor,
            '--if-assignee',
            '',
            '--if-status',
            BeadStatus.open.wire,
            '--design-file',
            '-',
            '--acceptance',
            '',
            '--unset-metadata',
            StationBeadWriter.specAuthorKey,
          ],
        ]);
        expect(runner.stdins.last, '');
      },
    );

    for (final envelope in <String, String?>{
      'no envelope at all': null,
      'malformed JSON': 'not json',
      'an empty object': '{}',
      'a blank acceptance': '{"acceptance":" ","design":"d"}',
      'a blank design': '{"acceptance":"a","design":"\\n"}',
    }.entries) {
      test('invalid envelopes never call the injected writer — '
          '${envelope.key}', () async {
        final dir = _envelopeWorkspace(envelope.value);
        addTearDown(() => dir.deleteSync(recursive: true));
        final recorder = _RecordingSpecWriter();
        final c = _ctx(workspaceDir: dir.path);
        // Capture-only posture: an unusable envelope is never a throw, and
        // never an unstamped-but-written spec either.
        await _composedSpecify(
          writeSpecifyAuthoredSpec: recorder.record,
        ).result(c.context, c.args);
        expect(recorder.calls, isEmpty);
      });
    }
  });

  // The MACHINE GATE's syntactic floor. specify authors `validation_plan` and
  // the code committee's gating lane runs it, a whole build later, as
  // `sh -c '( <plan> )'`. On 2026-09-12 specify wrote a plan whose
  // single-quoted `ruby -e` program carried an apostrophe lifted out of the
  // design prose; the lane aborted at PARSE, the round read as infra, and the
  // session stranded. Parsing the plan in the step that WROTE it turns that
  // burnt build round into a re-specify with the shell's own diagnostic.
  group('SpecifyCapability.result — the authored machine gate parses', () {
    const acceptance = '- [ ] AC-1 — the gate is parseable';
    const design = '## Implementation Plan\n\n### Step 1 — parse the gate\n';

    setUp(BdCliService.resetGuardedWriteCapabilityForTesting);

    /// The composed seat over a read-back that returns the authored bead
    /// carrying [plan] (absent when null) — the FRESH bd row `result` reads.
    SpecifyCapability specifyOverPlan(
      String? plan, {
      SpecifyAuthoredSpecWriter? writeSpecifyAuthoredSpec,
    }) => _composedSpecify(
      writeSpecifyAuthoredSpec: writeSpecifyAuthoredSpec,
      specifyBdRunnerFor: (_) => SpecifyReadbackBdRunner(
        beads: [
          durableSpecifiedBead(
            'tg-1',
          ).copyWith(metadata: {if (plan != null) 'validation_plan': plan}),
        ],
      ),
    );

    Directory carriedEnvelope() {
      final dir = _envelopeWorkspace(
        jsonEncode({'acceptance': acceptance, 'design': design}),
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      return dir;
    }

    test('rejects an unparseable validation_plan with the first shell '
        'diagnostic', () async {
      // The INCIDENT's shape: an apostrophe copied out of the bead's prose
      // ("station lane's SDK") into a single-quoted program — THREE apostrophes,
      // so the third opens a quote nothing closes. The shorthand
      // `echo 'it's broken` carries only two and PARSES clean, which is why it
      // cannot stand in for this.
      const plan = "echo 'station lane's SDK'";
      // The reason quotes `sh` itself, so the expectation asks `sh` too rather
      // than hard-coding one shell's wording.
      final probe = await Process.run('sh', ['-n', '-c', '( $plan )']);
      final diagnostic = '${probe.stderr}'.trim().split('\n').first.trim();
      expect(probe.exitCode, isNot(0));
      expect(diagnostic, isNotEmpty);

      final dir = carriedEnvelope();
      final recorder = _RecordingSpecWriter();
      final c = _ctx(workspaceDir: dir.path);
      await expectLater(
        specifyOverPlan(
          plan,
          writeSpecifyAuthoredSpec: recorder.record,
        ).result(c.context, c.args),
        throwsA(
          isA<CapabilityFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                CapabilityFailureKind.invalidResult,
              )
              .having(
                (failure) => failure.reason,
                'reason',
                'validation_plan does not parse: $diagnostic',
              ),
        ),
      );
      // The provenance stamp is UPSTREAM of the refusal: the prose the
      // architect did write stays marked as its own, so the next ride's
      // clear-and-rewrite still knows which text is specify's.
      expect(recorder.calls, hasLength(1));
      expect(recorder.calls.single.design, design);
    });

    test('a parseable validation_plan is syntax-checked without execution and '
        'preserves fields', () async {
      // `exit 27` PARSES. Were `-n` ever to RUN it, the checking shell would
      // exit 27 and the plan would be refused — so a returned result map IS the
      // proof the check is parse-only.
      final dir = carriedEnvelope();
      final c = _ctx(workspaceDir: dir.path);
      expect(await specifyOverPlan('exit 27').result(c.context, c.args), {
        'tokensIn': '10',
        'tokensOut': '5',
        'numTurns': '2',
        'harnessDurationMs': '100',
        kCarriedSpecAcceptanceKey: acceptance,
        kCarriedSpecDesignKey: design,
      });
    });

    // PRESENCE is not this hook's to judge: `FilingContract.evaluate` and
    // `mountEligibilityFindings` already own it, and a third completeness
    // predicate is exactly what the two-contract boundary forbids.
    for (final absent in <String, String?>{
      'a missing validation_plan': null,
      'a blank validation_plan': '   \n',
    }.entries) {
      test('${absent.key} is not this step\'s refusal', () async {
        final dir = carriedEnvelope();
        final c = _ctx(workspaceDir: dir.path);
        expect(await specifyOverPlan(absent.value).result(c.context, c.args), {
          'tokensIn': '10',
          'tokensOut': '5',
          'numTurns': '2',
          'harnessDurationMs': '100',
          kCarriedSpecAcceptanceKey: acceptance,
          kCarriedSpecDesignKey: design,
        });
      });
    }

    test('an unparseable gate buys ONE repair ride, then a visible gate', () {
      final policy = const SpecifyCapability().supervisionPolicy(_ctx().args);
      expect(
        policy.policyFor(CapabilityFailureKind.invalidResult),
        const RetryPolicy(
          maxRestarts: 2,
          backoff: Backoff.standard,
          onExhaustion: ExhaustionBehavior.parkAtGate,
        ),
      );
      // A failed agent and a missing envelope keep the circuit's own budget —
      // only the broken authored ARTIFACT is narrowed here.
      expect(policy.policyFor(CapabilityFailureKind.work), const RetryPolicy());
      expect(
        policy.policyFor(CapabilityFailureKind.noResult),
        const RetryPolicy(),
      );
    });
  });

  group(
    'buildSpecifyBrief — the AUTO-RESPEC correction guidance (`pow-7nm`)',
    () {
      const ledger = RespecLedger(
        sessionRoot: 'tg-1',
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
          sessionRoot: 'tg-1',
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

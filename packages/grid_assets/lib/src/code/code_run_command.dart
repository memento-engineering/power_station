/// The `code` asset's run command — the first real ASSET RUNNER over the
/// station-runner library pieces (ADR-0008 Decision 2, amended 2026-07-02 —
/// the composition inversion: consumers compose, never subclass).
///
/// The command body IS the asset's `main()`: it validates arming, discovers
/// workspaces, builds the controllers + the generic machine wiring, constructs
/// its OWN `ServiceBundle` (the git `SourceControl` — provisioning + land are
/// THIS asset's opinion), mounts its station-default agent scope
/// (`InheritedSeed<AgentConfig>` + `InheritedSeed<AgentHarnessRegistry>`) via
/// `wrapRoot`, and drives the composed station. The framework calls nothing
/// back.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_controller/grid_controller.dart' show Bead;
import 'package:grid_engine/grid_engine.dart';

import '../agent/agent_harness.dart';
import 'code_capabilities.dart';

/// The bead→circuit policy for the `code` asset — all coding work roots the
/// `code` circuit (agent → review → land). A top-level tear-off so
/// [CircuitResolver] stays const.
Circuit _codeCircuit(Bead bead) => kCodeCircuit;

/// `grid run` for the `code` asset: the reentrant tree engine spawning a coding
/// agent per ready bead, wired with the `code` circuit + [buildCodeRegistry] +
/// the git `SourceControl`, parameterized over the agent scope (ADR-0008
/// Decision 10): `--harness claude|copilot|pi|opencode` picks the tool,
/// `--openai-base`/`--swift-base` point endpoint harnesses at llama.cpp /
/// swift-infer. Boot-eager validation (OQ-c moment 1) refuses an illegal
/// harness × target combo before any work mounts.
class CodeRunCommand extends Command<int> {
  /// Creates the code run command (the standard station flags + the agent
  /// scope's).
  CodeRunCommand() {
    addStationFlags(argParser);
    argParser
      ..addOption(
        'harness',
        defaultsTo: 'claude',
        allowed: ['claude', 'copilot', 'pi', 'opencode'],
        help:
            'The agentic harness coding work runs on (the station default; a '
            'bead may override via its grid.agent envelope, a step via params).',
      )
      ..addOption(
        'model',
        help:
            'The model a managed tool selects (claude/copilot) or an endpoint '
            'harness requests — rides AgentConfig.params, not the target.',
      )
      ..addOption(
        'openai-base',
        help:
            'An OpenAI-compatible inference endpoint (e.g. a llama.cpp '
            'server) — sets the model target for pi/opencode.',
      )
      ..addOption(
        'swift-base',
        help: 'A swift-infer server endpoint — sets the model target for pi.',
      );
  }

  @override
  final String name = 'run';

  @override
  final String description =
      'Run the CODE asset on the tree engine (tree-as-default): the reactive '
      'controller + the reentrant engine that spawns a coding agent per ready '
      'bead, over one shared ownership allow-set. Defaults to --dry-run '
      '(observe-only). Run under `dart run --enable-vm-service` so leonard can '
      'attach.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final args = StationArgs.from(results);
    final out = _out;
    final err = _err;

    // --- the station-default agent scope (D-C rung 1) + boot-eager validation
    // (OQ-c moment 1: a misconfigured MACHINE fails loud before any work
    // mounts; a misconfigured BEAD fails per-work at resolution).
    final openaiBase = results.option('openai-base');
    final swiftBase = results.option('swift-base');
    if (openaiBase != null && swiftBase != null) {
      err('code run: pass --openai-base OR --swift-base, not both.');
      return 64;
    }
    final ModelTarget target;
    try {
      target = openaiBase != null
          ? OpenAiCompatible(_parseBase(openaiBase, '--openai-base'))
          : swiftBase != null
          ? SwiftInfer(_parseBase(swiftBase, '--swift-base'))
          : const ProviderManaged();
    } on FormatException catch (e) {
      err('code run: ${e.message}');
      return 64;
    }
    final model = results.option('model');
    final agentConfig = AgentConfig(
      harness: results.option('harness') ?? 'claude',
      target: target,
      params: {if (model != null) 'model': model},
    );
    final harnesses = buildAgentHarnessRegistry();
    final invalid = harnesses.validate(agentConfig);
    if (invalid != null) {
      err('code run: $invalid');
      return 64;
    }

    // Held outside the try so a refusal AFTER the controllers exist still
    // releases them (the Dolt pool would otherwise keep the process alive —
    // review finding 2026-07-02).
    StationSources? sources;
    try {
      // --- the station-runner pieces, in order (the inversion) ---
      validateArming(args);
      final ws = discoverWorkspaces(
        workspacePath: args.workspacePath,
        stateWorkspacePath: args.stateWorkspacePath,
      );
      sources = await buildControllers(
        work: ws.work,
        state: ws.state,
        noSql: args.noSql,
      );
      final live = await buildLiveWiring(args: args, sources: sources, onRefusal: out);

      // The asset's OWN per-substation services: the git SourceControl over
      // the leased execution machinery + registered root (provisioning works
      // even when LAND is off — gitOps/prOpener are non-null only when --land
      // armed a live run; null ⇒ canLand false ⇒ commit-only posture).
      final services = ServiceBundle(
        sourceControl: GitSourceControl(
          gitOps: live.gitOps,
          prOpener: live.prOpener,
          provisioner: live.git,
          root: live.workRoot,
        ),
      );

      final wiring = composeStation(
        work: sources.work,
        state: sources.state,
        stationServices: live.stationServices,
        substations: [
          SubstationConfig(
            substationId: args.substations.first,
            ownedSubstations: args.substations,
            driveList: args.targetBeads,
          ),
        ],
        git: live.git,
        workRoot: live.workRoot,
        groups: live.groups,
        freshnessBarrier: live.freshnessBarrier,
        resolver: const CircuitResolver(_codeCircuit),
        registry: buildCodeRegistry(devRoot: live.workRoot.path),
        services: services,
        // D-C rung 1: the asset mounts its station-default config VALUES as
        // ancestors of everything (Theme-of-context; the effect boundary
        // resolves the ladder per work).
        wrapRoot: (root) => InheritedSeed<AgentConfig>(
          value: agentConfig,
          child: InheritedSeed<AgentHarnessRegistry>(
            value: harnesses,
            child: root,
          ),
        ),
      );

      out(
        'agent scope: harness ${agentConfig.harness} → ${agentConfig.target}'
        '${model != null ? '  ·  model $model' : ''}',
      );
      return await driveStation(wiring: wiring, sources: sources, args: args, out: out);
    } on StationRefusal catch (refusal) {
      await sources?.shutdown();
      err(refusal.message);
      return refusal.code;
    }
  }

  void _out(String message) => stdout.writeln(message);
  void _err(String message) => stderr.writeln(message);
}

Uri _parseBase(String raw, String flag) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) {
    throw FormatException('$flag is not an absolute url: "$raw"');
  }
  return uri;
}

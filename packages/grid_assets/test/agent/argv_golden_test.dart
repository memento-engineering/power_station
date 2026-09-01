// The argv GOLDEN pins — the acceptance clause "pin the four classes' emitted
// RuntimeConfig BEFORE any deletion" (a silent argv change is a live-station
// regression). This file first asserts the CURRENT four harness CLASSES emit
// exact literal RuntimeConfigs; a later pass re-points these SAME literals at
// the single `spawnFor` over declared environments (byte-identity is the whole
// proof of the collapse). Pure Dart, offline.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

void main() {
  final ws = testWorkspace(
    'tg-1',
    workspaceDir: '/w/tg-1',
    branch: 'grid/tg-1',
  );
  const brief = AgentBrief(task: 'BODY');
  final rendered = brief.render();

  group('the single spawnFor matches the collapsed classes byte-for-byte', () {
    RuntimeConfig render(
      String name, {
      String? model,
      String? usageOut,
      Uri? endpoint,
    }) => spawnFor(
      environment: kBuiltinEnvironments[name]!,
      brief: brief,
      workspace: ws,
      model: model,
      usageOut: usageOut,
      endpoint: endpoint,
    );

    test('claude with model == the class output', () {
      expect(
        render('claude', model: 'opus'),
        RuntimeConfig(
          workDir: '/w/tg-1',
          command: 'claude',
          args: [
            '--dangerously-skip-permissions',
            '--model',
            'opus',
            '-p',
            rendered,
          ],
          lifecycle: Lifecycle.oneTurn,
        ),
      );
    });
    test('claude usage-wrapped == the class output', () {
      final cfg = render(
        'claude',
        model: 'opus',
        usageOut: '.grid/telemetry/tg-1_agent.usage.json',
      );
      expect(cfg.command, 'sh');
      expect(cfg.args.sublist(2), [
        'grid-claude',
        'claude',
        '--dangerously-skip-permissions',
        '--model',
        'opus',
        '--output-format',
        'json',
        '-p',
        rendered,
      ]);
    });
    test('pi injects the endpoint env from the site binding', () {
      expect(
        render(
          'pi',
          model: 'qwen',
          endpoint: Uri.parse('http://127.0.0.1:8080'),
        ),
        RuntimeConfig(
          workDir: '/w/tg-1',
          command: 'pi',
          args: ['--model', 'qwen', '-p', rendered],
          env: {'OPENAI_BASE_URL': 'http://127.0.0.1:8080'},
          lifecycle: Lifecycle.oneTurn,
        ),
      );
    });
    test('opencode takes the prompt as a positional (arg mode)', () {
      expect(
        render('opencode', model: 'opus'),
        RuntimeConfig(
          workDir: '/w/tg-1',
          command: 'opencode',
          args: ['run', '--model', 'opus', rendered],
          lifecycle: Lifecycle.oneTurn,
        ),
      );
    });
    test('ACP-backed builtins are channel values', () {
      expect(
        kBuiltinEnvironments['copilot'],
        const AgentEnvironment(
          command: 'copilot',
          args: ['--acp', '--allow-all-tools'],
          promptMode: PromptMode.none,
          target: InferenceTarget.providerManaged,
          sessionAdapter: kAcpSessionAdapterId,
        ),
      );
      expect(
        kBuiltinEnvironments['codex'],
        const AgentEnvironment(
          command: 'npx',
          args: ['-y', '@agentclientprotocol/codex-acp@1.6.2'],
          env: {'INITIAL_AGENT_MODE': 'agent-full-access'},
          promptMode: PromptMode.none,
          target: InferenceTarget.providerManaged,
          model: 'gpt-5.6-sol',
          sessionAdapter: kAcpSessionAdapterId,
        ),
      );
    });
    test('the builtin roster is exactly the five', () {
      expect(buildBuiltinEnvironmentRegistry().names.toSet(), {
        'claude',
        'copilot',
        'pi',
        'opencode',
        'codex',
      });
    });

    test('the other three builtins remain on the one-turn argv path', () {
      for (final name in <String>['claude', 'pi', 'opencode']) {
        expect(kBuiltinEnvironments[name]!.sessionAdapter, isNull);
      }
    });
  });
}

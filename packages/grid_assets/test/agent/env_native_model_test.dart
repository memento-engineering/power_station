// Bead `pow-a9o` — the model ladder is environment-aware: codex carries an
// EXPLICIT codex-native pin (gpt-5.6-sol) so its asset-default rung never
// borrows claude's names (opus/sonnet/haiku), which 400 on a ChatGPT account;
// and a non-claude, model-less environment armed to a role fails LOUD at boot,
// not at 400-per-spawn. An operator's explicit bead pin still passes through.
// Pure-Dart, offline.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// A `grid.agent` envelope metadata map carrying [payload].
Map<String, dynamic> _envelope(Map<String, Object?> payload) => {
  'grid.agent': {'assets_version': kAgentAssetsVersion, 'payload': payload},
};

void main() {
  final ws = testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1');
  const brief = AgentBrief(task: 'BODY');

  group('pow-a9o — codex carries a native asset default', () {
    test('the codex builtin pins gpt-5.6-sol, not null', () {
      expect(kBuiltinEnvironments['codex']!.model, 'gpt-5.6-sol');
    });

    test('the asset-default rung resolves codex-native, never opus', () {
      final config = resolveAgentConfig(
        role: AgentRole.build,
        ambient: const AgentConfig(
          roleEnvironments: {AgentRole.build: 'codex'},
        ),
        beadMetadata: const {},
        stepParams: const {},
        registry: buildBuiltinEnvironmentRegistry(),
      );
      expect(config.harness, 'codex');
      expect(config.params['model'], 'gpt-5.6-sol');
      expect(config.params['model'], isNot('opus'));
    });

    test('the codex spawn argv carries --model gpt-5.6-sol from the default', () {
      final cfg = spawnFor(
        environment: kBuiltinEnvironments['codex']!,
        brief: brief,
        workspace: ws,
      );
      final i = cfg.args.indexOf('--model');
      expect(i, greaterThanOrEqualTo(0), reason: 'no --model: ${cfg.args}');
      expect(cfg.args[i + 1], 'gpt-5.6-sol');
    });

    test('an operator bead pin passes through into codex verbatim', () {
      final config = resolveAgentConfig(
        role: AgentRole.build,
        ambient: const AgentConfig(
          roleEnvironments: {AgentRole.build: 'codex'},
        ),
        beadMetadata: _envelope({
          'params': {'model': 'opus'},
        }),
        stepParams: const {},
        registry: buildBuiltinEnvironmentRegistry(),
      );
      expect(config.harness, 'codex');
      expect(config.params['model'], 'opus'); // operator owns the risk
    });
  });

  group('pow-a9o — the boot-eager cross-environment guard', () {
    test('a model-less non-claude env armed to a role is REFUSED LOUD', () {
      const registry = EnvironmentRegistry(
        custom: {'rogue': AgentEnvironment(command: 'codex', args: ['exec'])},
      );
      final refusal = registry.validate(roleEnvironments: {'build': 'rogue'});
      expect(
        refusal,
        allOf(
          contains('role "build"'),
          contains('"rogue"'),
          contains('codex'),
          contains('pins no model'),
        ),
      );
    });

    test('the pinned codex builtin armed to a role PASSES', () {
      // Just the codex builtin, so the guard is exercised in isolation (the full
      // builtin registry drags in `pi`, whose unbound endpoint trips a separate
      // site-binding check unrelated to this guard).
      final registry = EnvironmentRegistry(
        custom: {'codex': kBuiltinEnvironments['codex']!},
      );
      expect(registry.validate(roleEnvironments: {'build': 'codex'}), isNull);
    });

    test('claude (the tier-defaults owner, model-less) armed to a role PASSES', () {
      const registry = EnvironmentRegistry(
        custom: {'frontier': AgentEnvironment(command: 'claude')},
      );
      expect(registry.validate(roleEnvironments: {'build': 'frontier'}), isNull);
    });
  });
}

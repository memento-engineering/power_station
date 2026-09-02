// Bead `pow-a9o` — the model ladder is environment-aware: codex carries an
// EXPLICIT codex-native pin (gpt-5.6-sol) so its asset-default rung never
// borrows claude's names (opus/sonnet/haiku), which 400 on a ChatGPT account;
// and a non-claude, model-less environment armed by name fails LOUD at boot,
// not at 400-per-spawn. An operator's explicit bead pin still passes through.
// Pure-Dart, offline.
import 'dart:convert';

import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// A `grid.agent` envelope metadata map carrying [payload].
Map<String, dynamic> _envelope(Map<String, Object?> payload) => {
  'grid.agent': {'assets_version': kAgentAssetsVersion, 'payload': payload},
};

void main() {
  final ws = testWorkspace(
    'tg-1',
    workspaceDir: '/w/tg-1',
    branch: 'grid/tg-1',
  );

  group('pow-a9o — codex carries a native asset default', () {
    test('the codex builtin pins gpt-5.6-sol, not null', () {
      expect(kBuiltinEnvironments['codex']!.model, 'gpt-5.6-sol');
    });

    test('the asset-default rung resolves codex-native, never opus', () {
      final config = resolveAgentConfig(
        tier: AgentTier.frontier,
        ambient: const AgentConfig(),
        beadMetadata: const {},
        stepParams: const {},
        registry: buildBuiltinEnvironmentRegistry(),
        typedEnvironment: kBuiltinEnvironments['codex'],
      );
      expect(config.harness, 'codex');
      expect(config.params['model'], 'gpt-5.6-sol');
      expect(config.params['model'], isNot('opus'));
    });

    test('the ACP bridge spec retains the bare codex pin', () {
      final cfg = const AcpSessionAdapter().launch(
        environment: kBuiltinEnvironments['codex']!,
        workspace: ws,
      );
      final spec = AcpBridgeSpec.fromJson(
        (jsonDecode(cfg.env[kAcpBridgeSpecEnvironment]!)
                as Map<String, dynamic>)
            .cast<String, Object?>(),
      );
      expect(spec.command, 'npx');
      expect(spec.args, ['-y', '@agentclientprotocol/codex-acp@1.6.2']);
      expect(spec.model, 'gpt-5.6-sol');
      expect(cfg.args, isNot(contains('--model')));
    });

    test('an operator bead pin passes through into codex verbatim', () {
      final config = resolveAgentConfig(
        tier: AgentTier.frontier,
        ambient: const AgentConfig(),
        beadMetadata: _envelope({
          'params': {'model': 'opus'},
        }),
        stepParams: const {},
        registry: buildBuiltinEnvironmentRegistry(),
        typedEnvironment: kBuiltinEnvironments['codex'],
      );
      expect(config.harness, 'codex');
      expect(config.params['model'], 'opus'); // operator owns the risk
    });
  });

  group('pow-a9o — the boot-eager cross-environment guard', () {
    test('a non-claude env pinning a claude-native model is REFUSED LOUD', () {
      const registry = EnvironmentRegistry(
        custom: {
          'rogue': AgentEnvironment(
            command: 'codex',
            args: ['exec'],
            model: 'opus', // a claude-tier name crossing into a codex argv
          ),
        },
      );
      final refusal = registry.validate(armedNames: {'build': 'rogue'});
      expect(
        refusal,
        allOf(
          contains('arming "build"'),
          contains('"rogue"'),
          contains('codex'),
          contains('opus'),
          contains('claude-native'),
        ),
      );
    });

    test('a model-less copilot builtin armed by name PASSES', () {
      final registry = EnvironmentRegistry(
        custom: {'copilot': kBuiltinEnvironments['copilot']!},
      );
      expect(registry.validate(armedNames: {'build': 'copilot'}), isNull);
    });

    test('a model-less opencode builtin armed by name PASSES', () {
      final registry = EnvironmentRegistry(
        custom: {'opencode': kBuiltinEnvironments['opencode']!},
      );
      expect(
        registry.validate(armedNames: {'build': 'opencode'}),
        isNull,
      );
    });

    test('a model-less pi builtin (endpoint bound) armed by name PASSES', () {
      // pi is openAiCompatible, so it needs a bound endpoint; the MODEL guard
      // never fires on it (model-less non-claude is grandfathered). Bind the
      // endpoint so the whole boot validates clean.
      final registry = EnvironmentRegistry(
        custom: {'pi': kBuiltinEnvironments['pi']!},
      );
      final binding = SiteBinding({'pi': Uri.parse('http://localhost:8080')});
      expect(
        registry.validate(
          armedNames: {'build': 'pi'},
          siteBinding: binding,
        ),
        isNull,
      );
    });

    test('the pinned codex builtin armed by name PASSES', () {
      // Isolated so only the guard is exercised (the full builtin registry
      // drags in `pi`, whose unbound endpoint trips a separate site-binding
      // check unrelated to this guard).
      final registry = EnvironmentRegistry(
        custom: {'codex': kBuiltinEnvironments['codex']!},
      );
      expect(registry.validate(armedNames: {'build': 'codex'}), isNull);
    });

    test(
      'claude (the tier-defaults owner, model-less) armed by name PASSES',
      () {
        const registry = EnvironmentRegistry(
          custom: {'frontier': AgentEnvironment(command: 'claude')},
        );
        expect(
          registry.validate(armedNames: {'build': 'frontier'}),
          isNull,
        );
      },
    );
  });
}

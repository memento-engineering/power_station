// Bead `pow-k7l` — env at the bead + step rungs; role → env (the codex-first-class
// selection mechanism). A NAMED environment resolves through the registry to the
// full {harness, target, model}; the legacy harness/model rungs still function.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// The station registry: the five builtins plus one CUSTOM env whose resolved
/// value carries its own model — the env a NAME resolves to a FULL config.
EnvironmentRegistry _registry() => const EnvironmentRegistry(
  builtins: kBuiltinEnvironments,
  custom: {
    'codex-frontier': AgentEnvironment(
      command: 'codex',
      args: ['exec'],
      target: InferenceTarget.providerManaged,
      model: 'gpt-5-codex',
    ),
  },
);

/// A `grid.agent` envelope metadata map carrying [payload].
Map<String, dynamic> _envelope(Map<String, Object?> payload) => {
  'grid.agent': {'assets_version': kAgentAssetsVersion, 'payload': payload},
};

void main() {
  group('pow-k7l — a NAMED env at the rungs resolves the full config', () {
    test('a bead env resolves the environment: harness + its own model', () {
      final config = resolveAgentConfig(
        role: AgentRole.build,
        ambient: const AgentConfig(),
        beadMetadata: _envelope({'env': 'codex-frontier'}),
        stepParams: const {},
        registry: _registry(),
      );
      expect(config.harness, 'codex-frontier');
      expect(config.params['model'], 'gpt-5-codex');
      final env = _registry().resolve(config.harness);
      expect(env.command, 'codex');
      expect(env.target, InferenceTarget.providerManaged);
    });

    test('a step env resolves the environment and OUTRANKS a bead harness', () {
      final config = resolveAgentConfig(
        role: AgentRole.build,
        ambient: const AgentConfig(),
        beadMetadata: _envelope({'harness': 'claude'}),
        stepParams: const {'env': 'codex-frontier'},
        registry: _registry(),
      );
      expect(config.harness, 'codex-frontier');
      expect(config.params['model'], 'gpt-5-codex');
    });

    test('role → env resolves the role to an environment → full config', () {
      final config = resolveAgentConfig(
        role: AgentRole.build,
        ambient: const AgentConfig(
          roleEnvironments: {AgentRole.build: 'codex-frontier'},
        ),
        beadMetadata: const {},
        stepParams: const {},
        registry: _registry(),
      );
      expect(config.harness, 'codex-frontier');
      expect(config.params['model'], 'gpt-5-codex');
    });

    test('an unknown env NAME fails closed at per-work resolution', () {
      expect(
        () => resolveAgentConfig(
          role: AgentRole.build,
          ambient: const AgentConfig(),
          beadMetadata: _envelope({'env': 'no-such-env'}),
          stepParams: const {},
          registry: _registry(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('unknown environment'), contains('no-such-env')),
          ),
        ),
      );
    });
  });

  group(
    'pow-k7l — the legacy rungs still function (coexistence, shims UNTOUCHED)',
    () {
      test(
        'a bead harness names only the tool; the model rides role → tier',
        () {
          final config = resolveAgentConfig(
            role: AgentRole.grade,
            ambient: const AgentConfig(graderModel: 'sonnet-legacy'),
            beadMetadata: _envelope({'harness': 'copilot'}),
            stepParams: const {},
            registry: _registry(),
          );
          expect(config.harness, 'copilot');
          // graderModel projects onto the MID tier — the pre-env path is intact.
          expect(config.params['model'], 'sonnet-legacy');
        },
      );

      test('a bead-pinned params.model still tops every rung', () {
        final config = resolveAgentConfig(
          role: AgentRole.build,
          ambient: const AgentConfig(
            roleEnvironments: {AgentRole.build: 'codex-frontier'},
          ),
          beadMetadata: _envelope({
            'params': {'model': 'Z'},
          }),
          stepParams: const {},
          registry: _registry(),
        );
        expect(
          config.harness,
          'codex-frontier',
        ); // role → env still picks the env
        expect(
          config.params['model'],
          'Z',
        ); // ...but the bead pin wins the model
      });
    },
  );
}

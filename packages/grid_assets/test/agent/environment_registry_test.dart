// Bead `pow-ebf.3` — the EnvironmentRegistry: name → AgentEnvironment across the
// builtin/custom base grammar, its base-chain resolve fold, and the two-moment
// validation (boot-eager refusals + per-work fail-closed throw). Pure Dart,
// offline.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('EnvironmentRegistry.resolve — base-chain folding', () {
    test('provider: chain folds root → leaf (args REPLACE, append ACCUMULATE)', () {
      const registry = EnvironmentRegistry(
        custom: {
          'root': AgentEnvironment(
            command: 'claude',
            args: ['--root'],
            argsAppend: ['a-root'],
            model: 'opus',
          ),
          'leaf': AgentEnvironment(
            base: EnvBaseRef('root', scope: BaseScope.provider),
            args: ['--leaf'],
            argsAppend: ['a-leaf'],
          ),
        },
      );
      final env = registry.resolve('leaf');
      expect(env.command, 'claude'); // inherited
      expect(env.args, ['--leaf']); // REPLACE — last declaring layer wins
      expect(env.argsAppend, ['a-root', 'a-leaf']); // ACCUMULATE root→leaf
      expect(env.model, 'opus'); // inherited
    });

    test('bare auto base resolves custom first, then builtin', () {
      const registry = EnvironmentRegistry(
        builtins: {'claude': AgentEnvironment(command: 'claude-builtin')},
        custom: {'fast': AgentEnvironment(base: EnvBaseRef('claude'))},
      );
      expect(registry.resolve('fast').command, 'claude-builtin');
    });

    test('undeclared base layers a same-named builtin UNDER a custom env', () {
      const registry = EnvironmentRegistry(
        builtins: {'claude': AgentEnvironment(command: 'claude', model: 'opus')},
        custom: {'claude': AgentEnvironment(model: 'sonnet')}, // base undeclared
      );
      final env = registry.resolve('claude');
      expect(env.command, 'claude'); // from the builtin, layered under
      expect(env.model, 'sonnet'); // the custom leaf wins
    });

    test('standalone base opts out of a same-named builtin', () {
      const registry = EnvironmentRegistry(
        builtins: {'claude': AgentEnvironment(command: 'claude', model: 'opus')},
        custom: {
          'claude': AgentEnvironment(base: EnvBaseStandalone(), command: 'c2'),
        },
      );
      final env = registry.resolve('claude');
      expect(env.command, 'c2');
      expect(env.model, isNull); // builtin NOT layered — standalone barrier
    });
  });

  group('EnvironmentRegistry.resolve — moment 2 (per-work, fail-closed)', () {
    test('unknown name THROWS, naming the armed set', () {
      const registry = EnvironmentRegistry(
        custom: {
          'a': AgentEnvironment(command: 'x'),
          'b': AgentEnvironment(command: 'y'),
        },
      );
      expect(
        () => registry.resolve('nope'),
        throwsA(
          isA<EnvironmentRegistryError>().having(
            (e) => e.message,
            'message',
            allOf(contains('unknown environment "nope"'), contains('a, b')),
          ),
        ),
      );
    });
  });

  group('EnvironmentRegistry.validate — moment 1 (boot-eager refusals)', () {
    test('a fully legal set returns null', () {
      const registry = EnvironmentRegistry(
        custom: {'frontier': AgentEnvironment(command: 'claude')},
      );
      expect(registry.validate(), isNull);
    });

    test('illegal harness×target: no command', () {
      const registry = EnvironmentRegistry(
        custom: {'broken': AgentEnvironment(promptMode: PromptMode.arg)},
      );
      expect(
        registry.validate(),
        allOf(contains('"broken"'), contains('no command')),
      );
    });

    test('illegal harness×target: promptMode flag without promptFlag', () {
      const registry = EnvironmentRegistry(
        custom: {
          'flagless': AgentEnvironment(
            command: 'claude',
            promptMode: PromptMode.flag,
          ),
        },
      );
      expect(
        registry.validate(),
        allOf(contains('"flagless"'), contains('promptFlag')),
      );
    });

    test('a base cycle is refused with the cycle path', () {
      const registry = EnvironmentRegistry(
        custom: {
          'a': AgentEnvironment(
            base: EnvBaseRef('b', scope: BaseScope.provider),
            command: 'x',
          ),
          'b': AgentEnvironment(
            base: EnvBaseRef('a', scope: BaseScope.provider),
            command: 'x',
          ),
        },
      );
      expect(
        registry.validate(),
        allOf(contains('base cycle'), contains('a'), contains('b')),
      );
    });

    test('a dangling base is refused, naming the missing parent', () {
      const registry = EnvironmentRegistry(
        custom: {
          'orphan': AgentEnvironment(
            base: EnvBaseRef('ghost', scope: BaseScope.provider),
            command: 'x',
          ),
        },
      );
      expect(
        registry.validate(),
        allOf(contains('bases on "ghost"'), contains('orphan')),
      );
    });

    test('an unarmed role environment is refused, naming role and name', () {
      const registry = EnvironmentRegistry(
        custom: {'frontier': AgentEnvironment(command: 'claude')},
      );
      final refusal = registry.validate(
        roleEnvironments: {'build': 'missing-env'},
      );
      expect(
        refusal,
        allOf(
          contains('role "build"'),
          contains('"missing-env"'),
          contains('not armed'),
        ),
      );
    });

    test('an unbound machine fact is refused via SiteBinding.validate', () {
      const registry = EnvironmentRegistry(
        custom: {
          'local-cheap': AgentEnvironment(
            command: 'pi',
            target: InferenceTarget.swiftInfer,
          ),
        },
      );
      final refusal = registry.validate(siteBinding: SiteBinding.none);
      expect(refusal, allOf(contains('"local-cheap"'), contains('endpoint')));
    });

    test('a bound machine fact passes', () {
      const registry = EnvironmentRegistry(
        custom: {
          'local-cheap': AgentEnvironment(
            command: 'pi',
            target: InferenceTarget.swiftInfer,
          ),
        },
      );
      final binding = SiteBinding({
        'local-cheap': Uri.parse('http://localhost:8080'),
      });
      expect(registry.validate(siteBinding: binding), isNull);
    });
  });
}

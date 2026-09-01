// Bead `pow-ebf.2` — the AgentEnvironment value type: gc ProviderSpec field
// set, the base tri-state, and the pure resolve fold (args REPLACE, argsAppend
// ACCUMULATE, standalone barrier). Pure Dart, offline.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('EnvBase.parse — gc base tri-state grammar', () {
    test('null is undeclared (absent), not standalone', () {
      expect(EnvBase.parse(null), const EnvBaseUndeclared());
      expect(EnvBase.parse(null), isNot(const EnvBaseStandalone()));
    });

    test('empty string is standalone (explicit opt-out)', () {
      expect(EnvBase.parse(''), const EnvBaseStandalone());
    });

    test('absent != empty — the load-bearing distinction', () {
      expect(EnvBase.parse(null), isNot(EnvBase.parse('')));
    });

    test('bare name is an auto ref', () {
      expect(EnvBase.parse('claude'), const EnvBaseRef('claude'));
      expect((EnvBase.parse('claude') as EnvBaseRef).scope, BaseScope.auto);
    });

    test('builtin: / provider: prefixes select the scope', () {
      expect(
        EnvBase.parse('builtin:claude'),
        const EnvBaseRef('claude', scope: BaseScope.builtin),
      );
      expect(
        EnvBase.parse('provider:fast'),
        const EnvBaseRef('fast', scope: BaseScope.provider),
      );
    });
  });

  group('AgentEnvironment.resolve — a 3-layer chain', () {
    // root -> mid -> leaf (index 0 is the root).
    AgentEnvironment root() => const AgentEnvironment(
      command: 'claude',
      args: ['--root'],
      argsAppend: ['a-root'],
      promptMode: PromptMode.arg,
      env: {'ROOT': '1', 'SHARED': 'root'},
      model: 'opus',
    );
    AgentEnvironment mid() => const AgentEnvironment(
      argsAppend: ['a-mid'],
      env: {'MID': '1', 'SHARED': 'mid'},
      model: 'sonnet',
    );
    const leaf = AgentEnvironment(
      args: ['--leaf'],
      argsAppend: ['a-leaf'],
      env: {'LEAF': '1'},
    );

    test('args REPLACE — the last declaring layer wins', () {
      final r = AgentEnvironment.resolve([root(), mid(), leaf]);
      expect(r.args, ['--leaf']); // leaf replaced root; mid declared none
    });

    test('argsAppend ACCUMULATE — root->leaf concatenation', () {
      final r = AgentEnvironment.resolve([root(), mid(), leaf]);
      expect(r.argsAppend, ['a-root', 'a-mid', 'a-leaf']);
    });

    test('scalars fold last-non-null-wins', () {
      final r = AgentEnvironment.resolve([root(), mid(), leaf]);
      expect(r.command, 'claude'); // only root declared it
      expect(r.model, 'sonnet'); // mid overrode root; leaf declared none
      expect(r.promptMode, PromptMode.arg); // only root declared it
    });

    test('env merges key-wise, the leaf winning per key', () {
      final r = AgentEnvironment.resolve([root(), mid(), leaf]);
      expect(r.env, {'ROOT': '1', 'SHARED': 'mid', 'MID': '1', 'LEAF': '1'});
    });

    test('usageJsonArgs REPLACE across the fold (last non-null wins)', () {
      final r = AgentEnvironment.resolve(const [
        AgentEnvironment(usageJsonArgs: ['--output-format', 'json']),
        AgentEnvironment(),
        AgentEnvironment(usageJsonArgs: ['--json']),
      ]);
      expect(r.usageJsonArgs, ['--json']);
    });

    test('sessionAdapter folds last-non-null-wins', () {
      final r = AgentEnvironment.resolve(const [
        AgentEnvironment(sessionAdapter: 'root-channel'),
        AgentEnvironment(),
        AgentEnvironment(sessionAdapter: 'leaf-channel'),
      ]);
      expect(r.sessionAdapter, 'leaf-channel');
    });

    test('the resolved env is flattened (standalone base)', () {
      final r = AgentEnvironment.resolve([root(), mid(), leaf]);
      expect(r.base, const EnvBaseStandalone());
    });
  });

  group(
    'AgentEnvironment.resolve — the standalone barrier (tri-state honored)',
    () {
      const root = AgentEnvironment(
        command: 'root-cmd',
        argsAppend: ['a-root'],
      );
      const leaf = AgentEnvironment(argsAppend: ['a-leaf']);

      test('undeclared mid keeps the root ancestor', () {
        const mid = AgentEnvironment(
          base: EnvBaseUndeclared(),
          argsAppend: ['a-mid'],
        );
        final r = AgentEnvironment.resolve([root, mid, leaf]);
        expect(r.command, 'root-cmd'); // root flows through
        expect(r.argsAppend, ['a-root', 'a-mid', 'a-leaf']);
      });

      test('standalone mid DROPS every more-root ancestor', () {
        const mid = AgentEnvironment(
          base: EnvBaseStandalone(),
          argsAppend: ['a-mid'],
        );
        final r = AgentEnvironment.resolve([root, mid, leaf]);
        expect(r.command, isNull); // root was dropped
        expect(r.argsAppend, ['a-mid', 'a-leaf']); // root's append dropped too
      });

      test('absent vs empty base produce different resolved envs', () {
        const midAbsent = AgentEnvironment(
          base: EnvBaseUndeclared(),
          argsAppend: ['a-mid'],
        );
        const midEmpty = AgentEnvironment(
          base: EnvBaseStandalone(),
          argsAppend: ['a-mid'],
        );
        final a = AgentEnvironment.resolve([root, midAbsent, leaf]);
        final e = AgentEnvironment.resolve([root, midEmpty, leaf]);
        expect(a, isNot(e));
      });
    },
  );

  group('guards + target', () {
    test('validate refuses flag prompt mode with no prompt flag', () {
      expect(
        const AgentEnvironment(promptMode: PromptMode.flag).validate(),
        isNotNull,
      );
      expect(
        const AgentEnvironment(
          promptMode: PromptMode.flag,
          promptFlag: '--prompt',
        ).validate(),
        isNull,
      );
    });

    test('validate refuses a resume style with no resume flag', () {
      expect(
        const AgentEnvironment(resumeStyle: ResumeStyle.subcommand).validate(),
        isNotNull,
      );
      expect(
        const AgentEnvironment(
          resumeStyle: ResumeStyle.subcommand,
          resumeFlag: 'resume',
        ).validate(),
        isNull,
      );
    });

    test('arg/none prompt modes need no flag', () {
      expect(
        const AgentEnvironment(promptMode: PromptMode.arg).validate(),
        isNull,
      );
      expect(
        const AgentEnvironment(promptMode: PromptMode.none).validate(),
        isNull,
      );
    });

    test('channel adapters require an explicit none prompt mode', () {
      expect(
        const AgentEnvironment(sessionAdapter: '').validate(),
        'sessionAdapter must be non-empty',
      );
      expect(
        const AgentEnvironment(
          sessionAdapter: 'probe',
          promptMode: PromptMode.arg,
        ).validate(),
        'sessionAdapter requires promptMode none',
      );
      expect(
        const AgentEnvironment(
          sessionAdapter: 'probe',
          promptMode: PromptMode.none,
        ).validate(),
        isNull,
      );
    });

    test('needsSiteEndpoint tracks the target kind (D3)', () {
      expect(
        const AgentEnvironment(
          target: InferenceTarget.providerManaged,
        ).needsSiteEndpoint,
        isFalse,
      );
      expect(
        const AgentEnvironment(
          target: InferenceTarget.openAiCompatible,
        ).needsSiteEndpoint,
        isTrue,
      );
      expect(
        const AgentEnvironment(
          target: InferenceTarget.swiftInfer,
        ).needsSiteEndpoint,
        isTrue,
      );
      expect(const AgentEnvironment().needsSiteEndpoint, isFalse); // default
    });
  });

  group('value equality', () {
    test('== and hashCode are structural', () {
      const a = AgentEnvironment(
        command: 'claude',
        args: ['-p'],
        env: {'K': 'v'},
      );
      const b = AgentEnvironment(
        command: 'claude',
        args: ['-p'],
        env: {'K': 'v'},
      );
      const c = AgentEnvironment(
        command: 'claude',
        args: ['-q'],
        env: {'K': 'v'},
      );
      const channel = AgentEnvironment(
        command: 'claude',
        args: ['-p'],
        env: {'K': 'v'},
        sessionAdapter: 'channel',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(channel));
    });
  });
}

// Bead `pow-n6n.1` (epic `pow-n6n`) - the typed environment VALUES
// (ModelPreference, AvailableEnvironments), the effective lookup
// (resolveEnvironment) and the typed rung in resolveAgentConfig.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// Ends every probe tree (the `track_f_composition_assets_test.dart` idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Runs [read] once, at build, over the mounted context.
class _Probe extends StatelessSeed {
  const _Probe(this.read);
  final void Function(TreeContext) read;

  @override
  Seed build(TreeContext context) {
    read(context);
    return const _Leaf();
  }
}

/// The bead `pow-n6n.2` shape, PRIVATE here so nothing collides with the public
/// types that bead declares: a trivial subclass - the TYPE is the scope.
class _SpecPreference extends ModelPreference {
  const _SpecPreference(super.entries);
}

const AgentEnvironment _fast = AgentEnvironment(
  command: 'claude',
  model: 'haiku',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _strong = AgentEnvironment(
  command: 'claude',
  model: 'opus',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _unarmed = AgentEnvironment(
  command: 'nowhere',
  model: 'ghost',
);
const AgentEnvironment _noCommand = AgentEnvironment(model: 'unspawnable');

const EnvironmentRegistry _registry = EnvironmentRegistry(
  custom: {'fast': _fast, 'strong': _strong},
);

/// Mounts [wrap]'s seed chain over a probe and returns what
/// `resolveEnvironment<_SpecPreference>` saw there.
AgentEnvironment? _resolveUnder(Seed Function(Seed child) wrap) {
  AgentEnvironment? observed;
  final owner = TreeOwner();
  owner.mountRoot(
    wrap(
      _Probe(
        (context) => observed = resolveEnvironment<_SpecPreference>(context),
      ),
    ),
  );
  owner.flush();
  return observed;
}

void main() {
  group('pow-n6n.1 - the typed VALUE types', () {
    test('ModelPreference is const, ordered and value-equal', () {
      const a = ModelPreference([_fast, _strong]);
      const b = ModelPreference([_fast, _strong]);
      const reordered = ModelPreference([_strong, _fast]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(reordered));
      expect(a.entries, [_fast, _strong]);
    });

    test('a specific subclass never equals the generic with equal entries', () {
      const specific = _SpecPreference([_fast]);
      const generic = ModelPreference([_fast]);
      expect(specific, isNot(generic));
      expect(specific, const _SpecPreference([_fast]));
      expect(specific.hashCode, const _SpecPreference([_fast]).hashCode);
    });

    test('AvailableEnvironments is an order-independent value set', () {
      final one = AvailableEnvironments({_fast, _strong});
      final two = AvailableEnvironments({_strong, _fast});
      expect(one, two);
      expect(one.hashCode, two.hashCode);
      expect(one.contains(_fast), isTrue);
      expect(one.contains(_unarmed), isFalse);
      expect(AvailableEnvironments.none.contains(_fast), isFalse);
    });

    test('contains matches in the flattened normal form', () {
      final available = AvailableEnvironments.fromRegistry(_registry);
      // The registry hands back FLATTENED values; the canned layer is raw.
      expect(available.values.contains(_fast), isFalse);
      expect(available.contains(_fast), isTrue);
      expect(_fast.flattened.flattened, _fast.flattened);
    });

    test('the default set is exactly what validated at boot', () {
      const registry = EnvironmentRegistry(
        custom: {'fast': _fast, 'broken': _noCommand},
      );
      final available = AvailableEnvironments.fromRegistry(registry);
      expect(available.contains(_fast), isTrue);
      expect(available.contains(_noCommand), isFalse);
      expect(registry.validate(), contains('not spawnable'));
    });
  });

  group('pow-n6n.1 - resolveEnvironment', () {
    test('the preference walk picks the FIRST present entry', () {
      final chosen = _resolveUnder(
        (child) => InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments({_strong}),
          child: InheritedSeed<_SpecPreference>(
            value: const _SpecPreference([_fast, _strong]),
            child: child,
          ),
        ),
      );
      expect(chosen, _strong);
    });

    test('an absent specific type falls back to the generic', () {
      final chosen = _resolveUnder(
        (child) => InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments({_fast, _strong}),
          child: InheritedSeed<ModelPreference>(
            value: const ModelPreference([_strong]),
            child: child,
          ),
        ),
      );
      expect(chosen, _strong);
    });

    test('the specific type WINS over a mounted generic', () {
      final chosen = _resolveUnder(
        (child) => InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments({_fast, _strong}),
          child: InheritedSeed<ModelPreference>(
            value: const ModelPreference([_strong]),
            child: InheritedSeed<_SpecPreference>(
              value: const _SpecPreference([_fast]),
              child: child,
            ),
          ),
        ),
      );
      expect(chosen, _fast);
    });

    test('no preference mounted yields null', () {
      final chosen = _resolveUnder(
        (child) => InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments({_fast}),
          child: child,
        ),
      );
      expect(chosen, isNull);
    });

    test('a preference with nothing present yields null', () {
      final chosen = _resolveUnder(
        (child) => InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments.none,
          child: InheritedSeed<_SpecPreference>(
            value: const _SpecPreference([_fast, _strong]),
            child: child,
          ),
        ),
      );
      expect(chosen, isNull);
    });

    test('an absent presence set defaults to the boot-validated registry', () {
      final chosen = _resolveUnder(
        (child) => InheritedSeed<EnvironmentRegistry>(
          value: _registry,
          child: InheritedSeed<_SpecPreference>(
            value: const _SpecPreference([_unarmed, _strong]),
            child: child,
          ),
        ),
      );
      expect(chosen, _strong);
    });
  });

  group('pow-n6n.1 - EnvironmentRegistry.nameOf', () {
    test('it reverses name to environment in the normal form', () {
      expect(_registry.nameOf(_fast), 'fast');
      expect(_registry.nameOf(_fast.flattened), 'fast');
      expect(_registry.nameOf(_strong), 'strong');
    });

    test('a value no armed name resolves to fails CLOSED', () {
      expect(
        () => _registry.nameOf(_unarmed),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('nowhere'), contains('fast, strong')),
          ),
        ),
      );
    });
  });

  group('pow-n6n.1 - the typed rung in resolveAgentConfig', () {
    AgentConfig resolve({
      AgentConfig ambient = const AgentConfig(),
      Map<String, dynamic> beadMetadata = const {},
      Map<String, String> stepParams = const {},
      AgentEnvironment? typedEnvironment,
    }) => resolveAgentConfig(
      tier: AgentTier.frontier,
      ambient: ambient,
      beadMetadata: beadMetadata,
      stepParams: stepParams,
      registry: _registry,
      typedEnvironment: typedEnvironment,
    );

    test('a typed win stamps the registry NAME into config.harness', () {
      final config = resolve(typedEnvironment: _strong);
      expect(config.harness, 'strong');
      expect(config.params['model'], 'opus');
    });

    test('the typed rung OUTRANKS the ambient harness', () {
      final config = resolve(
        ambient: const AgentConfig(harness: 'fast'),
        typedEnvironment: _strong,
      );
      expect(config.harness, 'strong');
      expect(config.params['model'], 'opus');
    });

    test('a step env still OUTRANKS the typed rung', () {
      final config = resolve(
        stepParams: const {'env': 'fast'},
        typedEnvironment: _strong,
      );
      expect(config.harness, 'fast');
      expect(config.params['model'], 'haiku');
    });

    test('a bead env still OUTRANKS the typed rung', () {
      final config = resolve(
        beadMetadata: const {
          'grid.agent': {
            'assets_version': kAgentAssetsVersion,
            'payload': {'env': 'fast'},
          },
        },
        typedEnvironment: _strong,
      );
      expect(config.harness, 'fast');
      expect(config.params['model'], 'haiku');
    });

    test('a LOSING typed rung is never evaluated, so it never throws', () {
      final config = resolve(
        stepParams: const {'env': 'fast'},
        typedEnvironment: _unarmed,
      );
      expect(config.harness, 'fast');
    });

    test('a winning typed value with no registry name fails CLOSED', () {
      expect(
        () => resolve(typedEnvironment: _unarmed),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('nowhere'),
          ),
        ),
      );
    });

    test('omitting the typed rung falls through to the ambient harness', () {
      final config = resolve(ambient: const AgentConfig(harness: 'fast'));
      expect(config.harness, 'fast');
      expect(config.params['model'], 'haiku');
    });
  });
}

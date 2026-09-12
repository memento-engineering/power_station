// The site-binding MOUNT — `HarnessProvider` holds the box's machine facts
// (ADR-0002 D3), mounts them as an `InheritedSeed<SiteBinding>` above the
// availability seed, and routes its ONE boot-eager refusal through
// `EnvironmentRegistry.validate`. Fakes only; the only I/O is a temp-dir
// site file. Pure Dart, offline.
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_fakes.dart';
import '../support/package_root.dart';

/// Ends every probe tree (the `availability_seed_test.dart` idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// WATCHES the ambient machine facts (the D-H build verb), recording what the
/// subtree actually sees on every build.
class _Reader extends StatelessSeed {
  const _Reader(this.seen);
  final List<SiteBinding?> seen;

  @override
  Seed build(TreeContext context) {
    seen.add(context.dependOnInheritedSeedOfExactType<SiteBinding>());
    return const _Leaf();
  }
}

/// Runs [read] once at build (the effect-boundary read).
class _Effect extends StatelessSeed {
  const _Effect(this.read);
  final void Function(TreeContext) read;

  @override
  Seed build(TreeContext context) {
    read(context);
    return const _Leaf();
  }
}

/// A recording registry: a Fake by SUBCLASS, so the gate it records is the real
/// [EnvironmentRegistry.validate] and never a parallel re-implementation.
class _RecordingRegistry extends EnvironmentRegistry {
  _RecordingRegistry({required super.custom});

  final List<({Map<String, String> armedNames, SiteBinding siteBinding})>
  calls = [];

  @override
  String? validate({
    Map<String, String> armedNames = const {},
    SiteBinding siteBinding = SiteBinding.none,
  }) {
    calls.add((armedNames: armedNames, siteBinding: siteBinding));
    return super.validate(armedNames: armedNames, siteBinding: siteBinding);
  }
}

const AgentEnvironment _swift = AgentEnvironment(
  command: 'pi',
  model: 'qwen',
  target: InferenceTarget.swiftInfer,
);
const AgentEnvironment _frontier = AgentEnvironment(
  command: 'claude',
  model: 'opus',
  target: InferenceTarget.providerManaged,
);

const EnvironmentRegistry _localRegistry = EnvironmentRegistry(
  custom: {'local': _swift, 'frontier': _frontier},
);
const AgentConfig _armedLocal = AgentConfig(harness: 'local');

final Uri _endpoint = Uri.parse('http://127.0.0.1:8080');
final SiteBinding _bound = SiteBinding({'local': _endpoint});

/// Mounts [provider] and returns what its subtree watched.
List<SiteBinding?> _mounted(HarnessProvider Function(Seed child) provider) {
  final seen = <SiteBinding?>[];
  final owner = TreeOwner();
  owner.mountRoot(provider(_Reader(seen)));
  owner.flush();
  owner.dispose();
  return seen;
}

/// `grid_assets/lib`, off the shared cwd-independent anchor (the
/// `site_binding_test.dart` `_libFile` idiom).
Directory _libDir() => Directory(p.join(packageRoot(), 'lib'));

/// Every `.dart` file under `grid_assets/lib`, as (path, source) pairs.
Iterable<({String path, String source})> _libSources() sync* {
  final lib = _libDir();
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    yield (
      path: p.relative(entity.path, from: lib.path),
      source: entity.readAsStringSync(),
    );
  }
}

void main() {
  group('AC-1 - the provider mounts the machine facts, exactly once', () {
    test('a child reads the IDENTICAL binding from the ambient tree', () {
      final seen = _mounted(
        (child) => HarnessProvider(
          registry: _localRegistry,
          config: _armedLocal,
          siteBinding: _bound,
          child: child,
        ),
      );
      expect(seen, isNotEmpty);
      expect(seen.last, same(_bound));
    });

    test('production carries exactly ONE InheritedSeed<SiteBinding> mount', () {
      final mounts = <String>[];
      for (final file in _libSources()) {
        final count = 'InheritedSeed<SiteBinding>('.allMatches(file.source);
        for (var i = 0; i < count.length; i++) {
          mounts.add(file.path);
        }
      }
      expect(
        mounts,
        [p.join('src', 'assets', 'composition_assets.dart')],
        reason:
            'the composition root is the ONE mount site; a second would make '
            'the machine facts ambiguous by tree position',
      );
    });
  });

  group('AC-2 - a bound endpoint reaches the spawn edge', () {
    test(
      'the mounted binding resolves swiftInfer into SWIFT_INFER_BASE_URL',
      () {
        late RuntimeConfig spawned;
        final owner = TreeOwner();
        owner.mountRoot(
          HarnessProvider(
            registry: _localRegistry,
            config: _armedLocal,
            siteBinding: _bound,
            child: _Effect((context) {
              // The EFFECT verb at a spawn edge (ADR-0008 D3): read the ambient
              // machine facts, resolve the endpoint, render the argv.
              final binding =
                  context.getInheritedSeedOfExactType<SiteBinding>() ??
                  SiteBinding.none;
              final environment = _localRegistry.resolve('local');
              spawned = spawnFor(
                environment: environment,
                brief: const AgentBrief(task: 'BODY'),
                workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1'),
                endpoint: binding.endpointFor(
                  name: 'local',
                  environment: environment,
                ),
              );
            }),
          ),
        );
        owner.flush();

        expect(spawned.env['SWIFT_INFER_BASE_URL'], 'http://127.0.0.1:8080');
        owner.dispose();
      },
    );
  });

  group('AC-3 - an unbound machine fact REFUSES at boot', () {
    test('SiteBindingError names the environment and the fix', () {
      expect(
        () => _mounted(
          (child) => HarnessProvider(
            registry: _localRegistry,
            config: _armedLocal,
            siteBinding: SiteBinding.none,
            child: child,
          ),
        ),
        throwsA(
          isA<SiteBindingError>().having(
            (e) => e.message,
            'message',
            allOf(contains('"local"'), contains(kSiteBindingFile)),
          ),
        ),
      );
    });
  });

  group('AC-4 - a bare provider-managed station boots', () {
    test('the default palette boots although builtin pi is unbound', () {
      // `pi` is openAiCompatible and nothing binds it; no arming REACHES it, so
      // the endpoint check never looks at it. Narrowing the check's SCOPE, not
      // its loudness.
      final seen = _mounted(
        (child) => HarnessProvider(siteBinding: SiteBinding.none, child: child),
      );
      expect(seen.last, same(SiteBinding.none));

      final registry = buildBuiltinEnvironmentRegistry();
      expect(registry.resolve('pi').needsSiteEndpoint, isTrue);
      expect(
        SiteBinding.none.endpointFor(
          name: 'claude',
          environment: registry.resolve('claude'),
        ),
        isNull,
      );
    });
  });

  group('AC-5 - the conventional file loads BEFORE the mount', () {
    test('the conventional file parses, and the mount carries it unchanged '
        'after the file is GONE', () {
      final tmp = Directory.systemTemp.createTempSync('site-binding-mount');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final site = File(p.join(tmp.path, kSiteBindingFile))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"version": $kSiteBindingVersion, '
          '"endpoints": {"local": "$_endpoint"}}',
        );

      // The conventional document, read at its conventional relative path under
      // a root this test owns — never by pointing the PROCESS cwd at that root.
      // That is a process property and `dart test` runs suites concurrently, so
      // moving it here raced every sibling suite's source read.
      final loaded = SiteBinding.loadJsonFile(site.path);
      expect(loaded.endpoints, {'local': _endpoint});

      final seen = <SiteBinding?>[];
      final provider = HarnessProvider(
        registry: _localRegistry,
        config: _armedLocal,
        siteBinding: loaded,
        child: _Reader(seen),
      );

      // Nothing re-reads the disc below construction: the document is DELETED
      // before the first build, and the mount still carries the loaded facts
      // with their identity intact.
      tmp.deleteSync(recursive: true);
      final owner = TreeOwner();
      owner.mountRoot(provider);
      owner.flush();
      expect(seen.last, same(loaded));
      expect(seen.last?.endpoints, {'local': _endpoint});
      owner.dispose();
    });

    test('the DEFAULT read of the conventional path is the constructor\'s, '
        'never the build\'s', () {
      // What the explicit-value test above cannot reach: that the null default
      // reads `kSiteBindingFile` once, at construction. Asserted structurally
      // rather than by chdir'ing the process into a fixture root — the read
      // sits lexically ABOVE `buildWithChild`, so it is in the initializer
      // list, and no second caller of it exists anywhere in the pack.
      final callers = [
        for (final file in _libSources())
          if (file.source.contains('loadJsonFile(kSiteBindingFile)')) file,
      ];
      expect(
        callers.map((file) => file.path),
        [p.join('src', 'assets', 'composition_assets.dart')],
        reason: 'one conventional-path read, in the provider that mounts it',
      );
      // The provider's OWN class body — the file declares several, so a
      // whole-file index would compare against a sibling's build method.
      final source = callers.single.source;
      final start = source.indexOf('class HarnessProvider');
      expect(start, greaterThanOrEqualTo(0), reason: 'HarnessProvider moved');
      final next = source.indexOf('\nclass ', start + 1);
      final body = source.substring(start, next < 0 ? source.length : next);
      final read = body.indexOf('loadJsonFile(kSiteBindingFile)');
      final build = body.indexOf('Seed buildWithChild(');
      expect(read, greaterThanOrEqualTo(0));
      expect(build, greaterThanOrEqualTo(0));
      expect(
        read,
        lessThan(build),
        reason:
            'a read below the constructor would re-run on every rebuild and '
            'hand the subtree a NEW value each time',
      );
    });
  });

  group('AC-8 - EnvironmentRegistry.validate IS the boot-eager gate', () {
    test('the provider calls it ONCE, with its own arming and binding', () {
      final registry = _RecordingRegistry(
        custom: {'local': _swift, 'frontier': _frontier},
      );
      _mounted(
        (child) => HarnessProvider(
          registry: registry,
          config: _armedLocal,
          siteBinding: _bound,
          child: child,
        ),
      );
      expect(registry.calls, hasLength(1));
      expect(registry.calls.single.armedNames, {'ambient': 'local'});
      expect(registry.calls.single.siteBinding, same(_bound));
    });

    test('a refusal the gate returns becomes the boot throw', () {
      final registry = _RecordingRegistry(custom: {'frontier': _frontier});
      expect(
        () => _mounted(
          (child) => HarnessProvider(
            registry: registry,
            // Names an environment the registry does not arm — check 3.
            config: const AgentConfig(harness: 'nope'),
            siteBinding: _bound,
            child: child,
          ),
        ),
        throwsA(
          isA<SiteBindingError>().having(
            (e) => e.message,
            'message',
            allOf(contains('arming "ambient"'), contains('not armed')),
          ),
        ),
      );
      expect(registry.calls, hasLength(1));
    });

    test('no asset runs a PARALLEL site-binding validator', () {
      final callers = [
        for (final file in _libSources())
          if (file.source.contains('siteBinding.validate(')) file.path,
      ];
      expect(
        callers,
        [p.join('src', 'agent', 'environment_registry.dart')],
        reason:
            'the registry tail is the ONLY caller of SiteBinding.validate — a '
            'second boot-eager path could refuse where the gate does not',
      );
      expect(
        callers.where((path) => path.startsWith(p.join('src', 'assets'))),
        isEmpty,
      );
    });
  });

  group('AC-9 - both halves of the endpoint scope, in one boot probe', () {
    test('an ARMED custom endpoint refuses; an UNARMED builtin does not', () {
      // Half one: the station arms an endpoint-needing environment and binds
      // nothing — LOUD at boot.
      expect(
        () => _mounted(
          (child) => HarnessProvider(
            registry: _localRegistry,
            config: _armedLocal,
            siteBinding: SiteBinding.none,
            child: child,
          ),
        ),
        throwsA(isA<SiteBindingError>()),
      );

      // Half two: the SAME unbound box, arming only provider-managed work —
      // builtin `pi` needs an endpoint, no arming reaches it, boot proceeds.
      final seen = _mounted(
        (child) => HarnessProvider(siteBinding: SiteBinding.none, child: child),
      );
      expect(seen.last, same(SiteBinding.none));
    });
  });
}

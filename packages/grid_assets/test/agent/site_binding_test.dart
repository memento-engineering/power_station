// Bead `pow-ebf.6` — the SiteBinding value type: a box's inference endpoints
// keyed by environment name, its LOUD parse/refusal, the boot-eager validate,
// and the no-url-in-source fence. Pure Dart + a temp-file loader; offline.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// `grid_assets/lib/<relative>`, off the shared cwd-independent package root.
/// Never a walk up from the process working
/// directory: that is a process property and `dart test` runs the suites
/// concurrently, so a walk from here could read a directory another file had
/// pointed somewhere else.
File _libFile(String relative) => File(p.join(packageRoot(), 'lib', relative));

void main() {
  // Resolved environments by target kind (pow-ebf.2 value type).
  const swiftEnv = AgentEnvironment(target: InferenceTarget.swiftInfer);
  const openAiEnv = AgentEnvironment(target: InferenceTarget.openAiCompatible);
  const providerEnv = AgentEnvironment(target: InferenceTarget.providerManaged);

  group('parse / fromJson — LOUD on malformed (A23 refuses whole)', () {
    test('parses a well-formed versioned document', () {
      final b = SiteBinding.parse({
        'version': kSiteBindingVersion,
        'endpoints': {'local-cheap': 'http://127.0.0.1:8080/v1'},
      });
      expect(b.endpoints['local-cheap'], Uri.parse('http://127.0.0.1:8080/v1'));
    });

    test('an unsupported version refuses whole', () {
      expect(
        () => SiteBinding.parse({
          'version': 99,
          'endpoints': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    test('a non-object endpoints refuses', () {
      expect(
        () =>
            SiteBinding.parse({'version': kSiteBindingVersion, 'endpoints': 7}),
        throwsFormatException,
      );
    });

    test('a non-absolute url refuses (no scheme/authority)', () {
      expect(
        () => SiteBinding.parse({
          'version': kSiteBindingVersion,
          'endpoints': {'x': 'not-a-url'},
        }),
        throwsFormatException,
      );
    });

    test('a blank url refuses', () {
      expect(
        () => SiteBinding.parse({
          'version': kSiteBindingVersion,
          'endpoints': {'x': '   '},
        }),
        throwsFormatException,
      );
    });

    test('a non-string endpoint name refuses', () {
      expect(
        () => SiteBinding.parse({
          'version': kSiteBindingVersion,
          'endpoints': {'': 'http://127.0.0.1:1/v1'},
        }),
        throwsFormatException,
      );
    });

    test('fromJson round-trips toJson (it is a Dart value)', () {
      final b = SiteBinding.parse({
        'version': kSiteBindingVersion,
        'endpoints': {'a': 'http://127.0.0.1:1/v1', 'b': 'swift://box:2'},
      });
      expect(SiteBinding.fromJson(jsonEncode(b.toJson())), b);
    });
  });

  group('endpointFor / refusalFor — bound supplies, unbound REFUSES loud', () {
    final binding = SiteBinding({
      'local-cheap': Uri.parse('http://127.0.0.1:8080/v1'),
    });

    test('a bound endpoint-needing environment gets its endpoint', () {
      expect(
        binding.endpointFor(name: 'local-cheap', environment: swiftEnv),
        Uri.parse('http://127.0.0.1:8080/v1'),
      );
    });

    test('a provider-managed environment needs no fact (null, no throw)', () {
      expect(
        binding.endpointFor(name: 'frontier', environment: providerEnv),
        isNull,
      );
      expect(
        binding.refusalFor(name: 'frontier', environment: providerEnv),
        isNull,
      );
    });

    test(
      'an UNBOUND endpoint-needing env refuses, naming env + fact + fix',
      () {
        expect(
          () =>
              binding.endpointFor(name: 'codex-local', environment: openAiEnv),
          throwsA(
            isA<SiteBindingError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('codex-local'),
                contains('OpenAI-compatible'),
                contains(kSiteBindingFile),
              ),
            ),
          ),
        );
      },
    );

    test('refusalFor returns the same message (boot-eager return form)', () {
      final msg = binding.refusalFor(
        name: 'codex-local',
        environment: openAiEnv,
      );
      expect(msg, isNotNull);
      expect(msg, contains('codex-local'));
    });

    test('NEVER a silent fallback default — the refusal says REFUSES and no '
        'default endpoint is bound', () {
      final msg = binding.refusalFor(name: 'unbound', environment: swiftEnv)!;
      expect(msg.toLowerCase(), contains('refuses'));
      expect(SiteBinding.none.endpoints, isEmpty);
    });
  });

  group('validate — boot-eager over the station arming (moment 1)', () {
    final binding = SiteBinding({
      'local-cheap': Uri.parse('http://127.0.0.1:8080/v1'),
    });

    test('every armed fact bound -> null', () {
      expect(
        binding.validate({'frontier': providerEnv, 'local-cheap': swiftEnv}),
        isNull,
      );
    });

    test('an unbound armed fact -> its refusal message', () {
      final msg = binding.validate({
        'frontier': providerEnv,
        'codex-local': openAiEnv,
      });
      expect(msg, isNotNull);
      expect(msg, contains('codex-local'));
    });
  });

  group('loadJsonFile — a machine-local file supplies the endpoint', () {
    test('an ABSENT file is legal -> SiteBinding.none', () {
      expect(
        SiteBinding.loadJsonFile('/no/such/dir/site.json'),
        SiteBinding.none,
      );
    });

    test('a present machine-local file supplies its endpoints', () {
      final dir = Directory.systemTemp.createTempSync('site_binding_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'site.json');
      File(path).writeAsStringSync(
        '{"version": $kSiteBindingVersion, '
        '"endpoints": {"local-cheap": "http://127.0.0.1:8080/v1"}}',
      );
      final b = SiteBinding.loadJsonFile(path);
      expect(
        b.endpointFor(name: 'local-cheap', environment: swiftEnv),
        Uri.parse('http://127.0.0.1:8080/v1'),
      );
    });

    test('a present-but-malformed file refuses (throws)', () {
      final dir = Directory.systemTemp.createTempSync('site_binding_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'site.json');
      File(path).writeAsStringSync('{"version": 99, "endpoints": {}}');
      expect(() => SiteBinding.loadJsonFile(path), throwsFormatException);
    });
  });

  group('committed source carries no endpoint url (ADR-0002 D3/D4)', () {
    test('site_binding.dart has no literal endpoint url or localhost', () {
      final src = _libFile(
        p.join('src', 'agent', 'site_binding.dart'),
      ).readAsStringSync();
      expect(
        RegExp(r'https?://|swift://|localhost|127\.0\.0\.1').hasMatch(src),
        isFalse,
        reason:
            'the endpoint url lives ONLY in the machine-local binding, '
            'never in committed source (ADR-0002 D3/D4)',
      );
    });
  });
}

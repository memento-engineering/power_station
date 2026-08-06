import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const fixtureProvider = EmbeddingProvider(
  id: 'fixture',
  bindingName: 'fixture-local',
  model: 'fixture-model',
  authEnvironmentVariable: 'FIXTURE_TOKEN',
  dimensions: 3,
  contextWindowTokens: 32,
  batchLimit: 7,
);
const fixtureRegistry = EmbeddingProviderRegistry(
  providers: {'fixture': fixtureProvider},
  defaultProviderId: 'fixture',
);
final fixtureBinding = EmbeddingSiteBinding({
  'fixture-local': Uri.parse('http://fixture.invalid:9999/base'),
});
const fixtureIdentity = EmbeddingIndexIdentity(
  providerId: 'fixture',
  model: 'fixture-model',
  dimensions: 3,
);

class _RecordingHttp {
  final requests = <EmbeddingHttpRequest>[];

  Future<EmbeddingHttpResponse> send(EmbeddingHttpRequest request) async {
    requests.add(request);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final input = body['input'] as List;
    return EmbeddingHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'data': [
          for (var index = input.length - 1; index >= 0; index--)
            {
              'index': index,
              'embedding': [index.toDouble(), 1.0, 2.0],
            },
        ],
      }),
    );
  }
}

File _libFile(String relative) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final base in ['lib', p.join('packages', 'grid_assets', 'lib')]) {
      final probe = File(p.join(dir.path, base, relative));
      if (probe.existsSync()) return probe;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate grid_assets/lib/$relative');
}

EmbeddingClient _mount(EmbeddingHttpSend send) => EmbeddingClient.mount(
  registry: fixtureRegistry,
  environment: const {'FIXTURE_TOKEN': 'secret'},
  indexIdentity: fixtureIdentity,
  siteBinding: fixtureBinding,
  send: send,
);

void main() {
  group('declared provider values', () {
    test('swift-infer is the exact semantic-only default', () {
      expect(kDefaultEmbeddingProviderId, 'swift-infer');
      final provider = kBuiltinEmbeddingProviders['swift-infer']!;
      expect(provider.id, 'swift-infer');
      expect(provider.bindingName, 'swift-infer');
      expect(provider.model, 'bge-small');
      expect(provider.authEnvironmentVariable, 'SWIFT_INFER_ADMIN_TOKEN');
      expect(provider.dimensions, 384);
      expect(provider.contextWindowTokens, 512);
      expect(provider.batchLimit, 128);
    });

    test('every invalid field refuses with provider context and a fix', () {
      final cases = <EmbeddingProvider>[
        const EmbeddingProvider(
          id: ' ',
          bindingName: 'b',
          model: 'm',
          authEnvironmentVariable: 'A',
          dimensions: 1,
          contextWindowTokens: 1,
          batchLimit: 1,
        ),
        const EmbeddingProvider(
          id: 'x',
          bindingName: ' ',
          model: 'm',
          authEnvironmentVariable: 'A',
          dimensions: 1,
          contextWindowTokens: 1,
          batchLimit: 1,
        ),
        const EmbeddingProvider(
          id: 'x',
          bindingName: 'b',
          model: '',
          authEnvironmentVariable: 'A',
          dimensions: 1,
          contextWindowTokens: 1,
          batchLimit: 1,
        ),
        const EmbeddingProvider(
          id: 'x',
          bindingName: 'b',
          model: 'm',
          authEnvironmentVariable: '',
          dimensions: 1,
          contextWindowTokens: 1,
          batchLimit: 1,
        ),
        const EmbeddingProvider(
          id: 'x',
          bindingName: 'b',
          model: 'm',
          authEnvironmentVariable: 'A',
          dimensions: 0,
          contextWindowTokens: 1,
          batchLimit: 1,
        ),
        const EmbeddingProvider(
          id: 'x',
          bindingName: 'b',
          model: 'm',
          authEnvironmentVariable: 'A',
          dimensions: 1,
          contextWindowTokens: 0,
          batchLimit: 1,
        ),
        const EmbeddingProvider(
          id: 'x',
          bindingName: 'b',
          model: 'm',
          authEnvironmentVariable: 'A',
          dimensions: 1,
          contextWindowTokens: 1,
          batchLimit: 0,
        ),
      ];
      for (final provider in cases) {
        expect(provider.validate(), allOf(isNotNull, contains('declare')));
      }
    });

    test('map key/id mismatch refuses', () {
      const registry = EmbeddingProviderRegistry(
        providers: {'wrong': fixtureProvider},
        defaultProviderId: 'wrong',
      );
      expect(
        registry.validate(
          environment: const {'FIXTURE_TOKEN': 'secret'},
          indexIdentity: fixtureIdentity,
          siteBinding: fixtureBinding,
        ),
        allOf(contains('wrong'), contains('fixture'), contains('exact id')),
      );
    });
  });

  group('embedding site binding', () {
    test('JSON parses and round-trips endpoint facts', () {
      final raw = {
        'version': kEmbeddingSiteBindingVersion,
        'endpoints': {'fixture-local': 'http://fixture.invalid:9999/base'},
      };
      final binding = EmbeddingSiteBinding.fromJson(jsonEncode(raw));
      expect(binding.endpoints, fixtureBinding.endpoints);
      expect(
        binding.endpointFor(fixtureProvider),
        fixtureBinding.endpoints.values.single,
      );
    });

    test('absent file returns none', () {
      expect(
        EmbeddingSiteBinding.loadJsonFile('/no/such/binding'),
        same(EmbeddingSiteBinding.none),
      );
    });

    test('malformed envelopes refuse whole', () {
      final bad = <Map<String, Object?>>[
        {'version': 2, 'endpoints': <String, String>{}},
        {'version': 1, 'endpoints': 4},
        {
          'version': 1,
          'endpoints': {'': 'http://fixture.invalid'},
        },
        {
          'version': 1,
          'endpoints': {'x': ' '},
        },
        {
          'version': 1,
          'endpoints': {'x': 'relative/path'},
        },
      ];
      for (final raw in bad) {
        expect(() => EmbeddingSiteBinding.parse(raw), throwsFormatException);
      }
      expect(() => EmbeddingSiteBinding.fromJson('[]'), throwsFormatException);
    });

    test('unbound lookup names provider, fact, and fix', () {
      final refusal = EmbeddingSiteBinding.none.refusalFor(fixtureProvider)!;
      expect(refusal, contains('fixture'));
      expect(refusal, contains('fixture-local'));
      expect(refusal, contains(kEmbeddingSiteBindingFile));
      expect(
        () => EmbeddingSiteBinding.none.endpointFor(fixtureProvider),
        throwsA(isA<EmbeddingSiteBindingError>()),
      );
    });
  });

  group('mount validation happens before HTTP', () {
    test('unknown id, missing/blank token, binding, and identity refuse', () {
      final recording = _RecordingHttp();
      final cases = <Map<String, Object?>>[
        {'providerId': 'missing'},
        {'environment': <String, String>{}},
        {
          'environment': <String, String>{'FIXTURE_TOKEN': ' '},
        },
        {'binding': EmbeddingSiteBinding.none},
        {
          'identity': const EmbeddingIndexIdentity(
            providerId: 'other',
            model: 'fixture-model',
            dimensions: 3,
          ),
        },
        {
          'identity': const EmbeddingIndexIdentity(
            providerId: 'fixture',
            model: 'other',
            dimensions: 3,
          ),
        },
        {
          'identity': const EmbeddingIndexIdentity(
            providerId: 'fixture',
            model: 'fixture-model',
            dimensions: 4,
          ),
        },
      ];
      for (final values in cases) {
        expect(
          () => EmbeddingClient.mount(
            registry: fixtureRegistry,
            providerId: values['providerId'] as String?,
            environment:
                values['environment'] as Map<String, String>? ??
                const {'FIXTURE_TOKEN': 'secret'},
            indexIdentity:
                values['identity'] as EmbeddingIndexIdentity? ??
                fixtureIdentity,
            siteBinding:
                values['binding'] as EmbeddingSiteBinding? ?? fixtureBinding,
            send: recording.send,
          ),
          throwsA(isA<EmbeddingProviderRegistryError>()),
        );
      }
      expect(recording.requests, isEmpty);
    });
  });

  group('one client renders every value', () {
    test('sends exact wire and restores index order with doubles', () async {
      final recording = _RecordingHttp();
      final vectors = await _mount(recording.send).embed(['a', 'b', 'c']);
      expect(recording.requests, hasLength(1));
      final request = recording.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri,
        Uri.parse('http://fixture.invalid:9999/base/v1/embeddings'),
      );
      expect(request.headers[HttpHeaders.authorizationHeader], 'Bearer secret');
      expect(
        request.headers[HttpHeaders.contentTypeHeader],
        'application/json',
      );
      expect(jsonDecode(request.body), {
        'model': 'fixture-model',
        'input': ['a', 'b', 'c'],
      });
      expect(vectors, [
        [0.0, 1.0, 2.0],
        [1.0, 1.0, 2.0],
        [2.0, 1.0, 2.0],
      ]);
      expect(vectors.expand((vector) => vector), everyElement(isA<double>()));
    });

    test('empty input performs no HTTP', () async {
      final recording = _RecordingHttp();
      expect(await _mount(recording.send).embed(const []), isEmpty);
      expect(recording.requests, isEmpty);
    });

    test(
      '2,001 inputs use 286 bounded requests and preserve global order',
      () async {
        final recording = _RecordingHttp();
        final inputs = List.generate(2001, (index) => 'chunk $index');
        final vectors = await _mount(recording.send).embed(inputs);
        expect(recording.requests, hasLength(286));
        for (final request in recording.requests) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect((body['input'] as List).length, lessThanOrEqualTo(7));
        }
        for (var index = 0; index < vectors.length; index++) {
          expect(vectors[index].first, (index % 7).toDouble());
        }
      },
    );
  });

  group('malformed responses refuse loudly', () {
    Future<void> fails(EmbeddingHttpResponse response, String message) async {
      final client = _mount((_) async => response);
      await expectLater(
        client.embed(['a', 'b']),
        throwsA(
          isA<EmbeddingClientError>()
              .having((error) => error.message, 'message', contains('fixture'))
              .having((error) => error.message, 'message', contains(message)),
        ),
      );
    }

    test('status and envelope failures', () async {
      await fails(
        const EmbeddingHttpResponse(statusCode: 401, body: ''),
        '401',
      );
      await fails(
        const EmbeddingHttpResponse(statusCode: 200, body: '{'),
        'invalid JSON',
      );
      await fails(
        const EmbeddingHttpResponse(statusCode: 200, body: '{}'),
        'data list',
      );
      await fails(
        const EmbeddingHttpResponse(statusCode: 200, body: '{"data":{}}'),
        'data list',
      );
      await fails(
        const EmbeddingHttpResponse(statusCode: 200, body: '{"data":[]}'),
        'expected 2',
      );
    });

    test('item, index, numeric, and width failures', () async {
      EmbeddingHttpResponse body(Object data) => EmbeddingHttpResponse(
        statusCode: 200,
        body: jsonEncode({'data': data}),
      );
      await fails(body(<Map<String, Object?>>[{}, {}]), 'malformed');
      await fails(
        body([
          {
            'index': 0,
            'embedding': [0, 1, 2],
          },
          {
            'index': 0,
            'embedding': [0, 1, 2],
          },
        ]),
        'index 0',
      );
      await fails(
        body([
          {
            'index': 0,
            'embedding': [0, 1, 2],
          },
          {
            'index': 2,
            'embedding': [0, 1, 2],
          },
        ]),
        'index 2',
      );
      await fails(
        body([
          {
            'index': 0,
            'embedding': [0, 'x', 2],
          },
          {
            'index': 1,
            'embedding': [0, 1, 2],
          },
        ]),
        'non-numeric',
      );
      for (final width in [2, 4]) {
        await fails(
          body([
            {'index': 0, 'embedding': List.filled(width, 1)},
            {'index': 1, 'embedding': List.filled(width, 1)},
          ]),
          'width $width',
        );
      }
    });
  });

  test('provider declarations contain no endpoint member or URL', () {
    final source = _libFile(
      p.join('src', 'search', 'embedding_provider.dart'),
    ).readAsStringSync();
    final declarations = source.substring(
      0,
      source.indexOf('class EmbeddingProviderRegistryError'),
    );
    expect(RegExp(r'final\s+Uri\s+endpoint\b').hasMatch(declarations), isFalse);
    final builtins = declarations.substring(
      declarations.indexOf('kBuiltinEmbeddingProviders'),
    );
    expect(builtins, isNot(contains('http://')));
    expect(builtins, isNot(contains('https://')));
  });
}

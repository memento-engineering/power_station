import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

const _provider = EmbeddingProvider(
  id: 'fixture',
  bindingName: 'fixture',
  model: 'fixture-model',
  authEnvironmentVariable: 'TOKEN',
  dimensions: 3,
  contextWindowTokens: 512,
  batchLimit: 8,
);
const _registry = EmbeddingProviderRegistry(
  providers: {'fixture': _provider},
  defaultProviderId: 'fixture',
);

class _Delegate extends sdk.GridDelegate {
  _Delegate(this.root);
  @override
  final String root;
  bool disposed = false;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.RawAssetGrid(
        root: root,
        assets: [
          sdk.Station(
            name: 'fixture',
            assets: [
              sdk.Substations(
                substations: [sdk.Substation('alpha', '/stores/alpha')],
              ),
            ],
          ),
        ],
      );

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Source implements SubstationBeadSource {
  @override
  Future<List<Bead>> read(sdk.SubstationScope scope) async => const [
    Bead(id: 'a-1', title: 'index me'),
  ];
}

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('index-command-'));
  tearDown(() => home.deleteSync(recursive: true));

  test(
    'incremental default and full JSON use the normalized home and dispose',
    () async {
      final out = StringBuffer();
      final requests = <List<String>>[];
      _Delegate? delegate;
      final runner = CommandRunner<int>('space', 'fixture')
        ..addCommand(
          IndexCommand(
            delegate: (root) => delegate = _Delegate(root),
            registry: _registry,
            environment: const {'TOKEN': 'secret'},
            gridHomeDefault: () => '${home.path}/nested/..',
            source: _Source(),
            changeKeyOf: (_) => 'key',
            dirExists: (_) => true,
            siteBindingLoad: (_) => EmbeddingSiteBinding({
              'fixture': Uri.parse('http://fixture.invalid'),
            }),
            send: (request) async {
              final inputs = (jsonDecode(request.body)['input'] as List)
                  .cast<String>();
              requests.add(inputs);
              return EmbeddingHttpResponse(
                statusCode: 200,
                body: jsonEncode({
                  'data': [
                    for (var i = 0; i < inputs.length; i++)
                      {
                        'index': i,
                        'embedding': [1.0, 0.0, 0.0],
                      },
                  ],
                }),
              );
            },
            out: out,
          ),
        );

      expect(await runner.run(['index', '--json']), 0);
      expect(delegate!.root, home.path);
      expect(delegate!.disposed, isTrue);
      expect(jsonDecode(out.toString())['full'], isFalse);
      expect(requests.length, 1);

      out.clear();
      expect(await runner.run(['index', '--json', '--full']), 0);
      expect(jsonDecode(out.toString())['full'], isTrue);
      expect(requests.length, 2);
    },
  );

  test('relative home is a usage refusal', () async {
    final runner = CommandRunner<int>('space', 'fixture')
      ..addCommand(
        IndexCommand(
          delegate: _Delegate.new,
          registry: _registry,
          gridHomeDefault: () => 'relative',
        ),
      );
    await expectLater(
      runner.run(['index']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('ABSOLUTE'),
        ),
      ),
    );
  });

  test('search source files retain the sole-writer fence', () {
    for (final path in [
      'lib/src/search/station_search.dart',
      'lib/src/search/search_command.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('EmbeddingClient')));
      expect(source, isNot(contains('replaceBead')));
      expect(source, isNot(contains('deleteBeads')));
    }
  });
}

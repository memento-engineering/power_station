import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:grid_assets/grid_assets.dart' hide embeddingChangeKey;
import 'package:grid_assets/src/search/embedding_change_key.dart';
import 'package:grid_sdk/grid_sdk.dart' show SubstationScope;
import 'package:test/test.dart';

const _provider = EmbeddingProvider(
  id: 'fixture',
  bindingName: 'fixture',
  model: 'fixture-model',
  authEnvironmentVariable: 'TOKEN',
  dimensions: 3,
  contextWindowTokens: 512,
  batchLimit: 2,
);
const _registry = EmbeddingProviderRegistry(
  providers: {'fixture': _provider},
  defaultProviderId: 'fixture',
);

class _Source implements SubstationBeadSource {
  _Source(this.values, {this.fail = const {}});
  final Map<String, List<Bead>> values;
  final Set<String> fail;
  final List<String> reads = [];

  @override
  Future<List<Bead>> read(SubstationScope scope) async {
    reads.add(scope.name);
    if (fail.contains(scope.name)) throw StateError('read ${scope.name}');
    return values[scope.name] ?? const [];
  }
}

void main() {
  // The same dolt-absent skip the embedding-index suite carries (PR #98's
  // first CI run failed exactly here): CI runners ship no dolt; skipping
  // keeps the suite honest where it can run instead of failing everywhere
  // it can't.
  final bool doltAvailable = Process.runSync('which', ['dolt']).exitCode == 0;
  if (!doltAvailable) {
    test('dolt binary is unavailable — suite skipped', () {
      markTestSkipped('dolt not on PATH; suite requires a real dolt.');
    });
    return;
  }

  group('ProseChunker', () {
    test('512 tokens derives 1228-rune windows with 245 overlap', () {
      const chunker = ProseChunker(contextWindowTokens: 512);
      final text = List.filled(2500, 'x').join();
      final chunks = chunker.chunkField('design', text);
      expect(chunks.map((chunk) => chunk.chunkIx), [0, 1, 2]);
      expect(chunks.first.text.runes.length, 1228);
      expect(chunks[1].text.runes.take(245), chunks.first.text.runes.skip(983));
      expect(chunks.last.text.runes.last, 'x'.runes.single);
    });

    test('all prose fields restart at zero and blank fields are omitted', () {
      const bead = Bead(
        id: 'a-1',
        title: 'title',
        description: 'description',
        design: 'design',
        acceptanceCriteria: 'acceptance',
        notes: 'notes',
        closeReason: 'close',
      );
      final chunks = const ProseChunker(
        contextWindowTokens: 512,
      ).chunkBead(bead);
      expect(chunks.map((chunk) => chunk.field), [
        'title',
        'description',
        'design',
        'acceptance_criteria',
        'notes',
        'close_reason',
      ]);
      expect(chunks.every((chunk) => chunk.chunkIx == 0), isTrue);
      expect(
        const ProseChunker(
          contextWindowTokens: 512,
        ).chunkField('notes', ' \n '),
        isEmpty,
      );
    });

    test('unicode scalars, provider geometry, tail, and invalid shapes', () {
      final unicode = List.filled(80, '😀').join();
      final chunks = const ProseChunker(
        contextWindowTokens: 32,
      ).chunkField('notes', unicode);
      expect(chunks.first.text.runes.length, 76);
      expect(chunks.last.text.runes.last, '😀'.runes.single);
      expect(
        () =>
            const ProseChunker(contextWindowTokens: 0).chunkField('notes', 'x'),
        throwsArgumentError,
      );
      expect(
        () => const ProseChunker(
          contextWindowTokens: 1,
          overlapFraction: 1,
        ).chunkField('notes', 'x'),
        throwsArgumentError,
      );
    });
  });

  group('StationIndexService', () {
    late Directory home;
    late DoltEmbeddingIndex index;
    late List<List<String>> requests;

    setUp(() async {
      home = Directory.systemTemp.createTempSync('station-index-');
      index = await DoltEmbeddingIndex.open(
        gridHome: home.path,
        identity: _provider.indexIdentity,
      );
      requests = [];
    });
    tearDown(() => home.deleteSync(recursive: true));

    EmbeddingClient client({bool fail = false}) => EmbeddingClient.mount(
      registry: _registry,
      environment: const {'TOKEN': 'secret'},
      indexIdentity: _provider.indexIdentity,
      siteBinding: EmbeddingSiteBinding({
        'fixture': Uri.parse('http://fixture.invalid'),
      }),
      send: (request) async {
        final input = (jsonDecode(request.body)['input'] as List)
            .cast<String>();
        requests.add(input);
        if (fail) {
          return const EmbeddingHttpResponse(statusCode: 503, body: '{}');
        }
        return EmbeddingHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'data': [
              for (var i = 0; i < input.length; i++)
                {
                  'index': i,
                  'embedding': [1.0, 0.0, 0.0],
                },
            ],
          }),
        );
      },
    );

    SubstationScope scope(String name) =>
        SubstationScope(name: name, root: '/stores/$name', prefix: name);

    test(
      'incremental keys skip fresh, update stale, and remove deleted',
      () async {
        const original = Bead(id: 'a-1', title: 'first');
        final source = _Source({
          'alpha': [original],
        });
        final service = StationIndexService(
          index: index,
          client: client(),
          provider: _provider,
          source: source,
          changeKeyOf: (_) => 'key-1',
          dirExists: (_) => true,
        );
        final first = await service.indexRoster(roster: [scope('alpha')]);
        expect((first.stores.single as StoreIndexed).embedded, 1);
        expect(requests, [
          ['first'],
        ]);

        requests.clear();
        final fresh = await service.indexRoster(roster: [scope('alpha')]);
        expect((fresh.stores.single as StoreIndexed).skippedFresh, 1);
        expect(requests, isEmpty);

        source.values['alpha'] = const [];
        final deleted = await service.indexRoster(roster: [scope('alpha')]);
        expect((deleted.stores.single as StoreIndexed).removed, 1);
        expect((await index.rowCount()).total, 0);
      },
    );

    test('canonical fallback is persisted and supplied keys win', () async {
      const bead = Bead(
        id: 'a-1',
        title: 'title',
        description: 'description',
        design: 'design',
        acceptanceCriteria: 'acceptance',
        notes: 'notes',
        closeReason: 'close',
      );
      final fallback = StationIndexService(
        index: index,
        client: client(),
        provider: _provider,
        source: _Source(const {
          'alpha': [bead],
        }),
        dirExists: (_) => true,
      );
      await fallback.indexRoster(roster: [scope('alpha')]);
      expect(await index.changeKeys(store: 'alpha'), {
        'a-1': embeddingChangeKey(bead),
      });

      final supplied = StationIndexService(
        index: index,
        client: client(),
        provider: _provider,
        source: _Source(const {
          'alpha': [bead],
        }),
        changeKeyOf: (_) => 'source-change-key',
        dirExists: (_) => true,
      );
      await supplied.indexRoster(roster: [scope('alpha')], full: true);
      expect(await index.changeKeys(store: 'alpha'), {
        'a-1': 'source-change-key',
      });
    });

    test('provider failure writes nothing and later stores continue', () async {
      final failing = StationIndexService(
        index: index,
        client: client(fail: true),
        provider: _provider,
        source: _Source({
          'alpha': const [Bead(id: 'a-1', title: 'alpha')],
          'beta': const [Bead(id: 'b-1', title: '')],
        }),
        dirExists: (_) => true,
      );
      final report = await failing.indexRoster(
        roster: [scope('alpha'), scope('beta')],
      );
      expect(report.stores.first, isA<IndexStoreFailed>());
      expect(report.stores.last, isA<StoreIndexed>());
      expect((await index.rowCount()).total, 0);
    });

    test('absent and read failures remain ordered and loud', () async {
      final source = _Source(const {}, fail: {'beta'});
      final report = await StationIndexService(
        index: index,
        client: client(),
        provider: _provider,
        source: source,
        dirExists: (path) => !path.contains('alpha'),
      ).indexRoster(roster: [scope('alpha'), scope('beta')]);
      expect(report.stores, [isA<IndexStoreAbsent>(), isA<IndexStoreFailed>()]);
      expect(report.succeeded, isFalse);
    });
  });

  test('search remains inference-free and write-free', () {
    final search = File(
      'lib/src/search/station_search.dart',
    ).readAsStringSync();
    final command = File(
      'lib/src/search/search_command.dart',
    ).readAsStringSync();
    for (final forbidden in ['EmbeddingClient', 'replaceBead', 'deleteBeads']) {
      expect(search, isNot(contains(forbidden)));
      expect(command, isNot(contains(forbidden)));
    }
  });
}

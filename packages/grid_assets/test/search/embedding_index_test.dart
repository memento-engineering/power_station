import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

const identity = EmbeddingIndexIdentity(
  providerId: 'fixture-provider',
  model: 'fixture-model',
  dimensions: 3,
);

EmbeddingIndexRow row(
  String store,
  String bead,
  String field,
  int chunk,
  String key,
  String text,
  List<double> vector,
) => EmbeddingIndexRow(
  store: store,
  beadId: bead,
  field: field,
  chunkIx: chunk,
  changeKey: key,
  chunkText: text,
  vector: vector,
);

Future<ProcessResult> dolt(String root, List<String> args) =>
    Process.run('dolt', args, workingDirectory: root);

void main() {
  // The suite exercises a REAL dolt working copy — vector schema, identity
  // metadata, top-k SQL — so it needs the binary. CI runners don't carry
  // dolt; skipping there keeps the suite honest where it can run instead of
  // failing everywhere it can't (measured: PR #98's first CI run).
  final bool doltAvailable = Process.runSync('which', ['dolt']).exitCode == 0;
  if (!doltAvailable) {
    test('dolt binary is unavailable — embedding index suite skipped', () {
      markTestSkipped('dolt not on PATH; suite requires a real dolt.');
    });
    return;
  }

  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('embedding-index-'));
  tearDown(() => home.deleteSync(recursive: true));

  test('open creates the dedicated configured schema and metadata', () async {
    final index = await DoltEmbeddingIndex.open(
      gridHome: home.path,
      identity: identity,
    );
    expect(index.root, '${home.path}/.grid/embeddings');
    final schema = await dolt(index.root, [
      'sql',
      '-r',
      'json',
      '-q',
      'SHOW CREATE TABLE bead_vectors;',
    ]);
    expect(schema.exitCode, 0);
    expect('${schema.stdout}'.toLowerCase(), contains('vector(3) not null'));
    expect(
      schema.stdout,
      contains('PRIMARY KEY (`store`,`bead_id`,`field`,`chunk_ix`)'),
    );
    expect(schema.stdout, contains('VECTOR KEY `bead_vectors_v_idx` (`v`)'));
    final metadata = await dolt(index.root, [
      'sql',
      '-r',
      'json',
      '-q',
      'SELECT provider_id, model, dimensions FROM embedding_index_metadata;',
    ]);
    expect(jsonDecode('${metadata.stdout}')['rows'], [
      {
        'provider_id': 'fixture-provider',
        'model': 'fixture-model',
        'dimensions': 3,
      },
    ]);
    final reopened = await DoltEmbeddingIndex.open(
      gridHome: home.path,
      identity: identity,
    );
    expect(reopened.identity, identity);
  });

  test(
    'identity mismatch is loud and deletion is a full safe rebuild',
    () async {
      final first = await DoltEmbeddingIndex.open(
        gridHome: home.path,
        identity: identity,
      );
      await first.replaceBead(
        store: 'alpha',
        beadId: 'al-1',
        rows: [
          row('alpha', 'al-1', 'title', 0, 'k1', 'old', [1, 0, 0]),
        ],
      );
      await expectLater(
        DoltEmbeddingIndex.open(
          gridHome: home.path,
          identity: const EmbeddingIndexIdentity(
            providerId: 'replacement',
            model: 'wide-model',
            dimensions: 4,
          ),
        ),
        throwsA(isA<EmbeddingIndexIdentityMismatch>()),
      );
      Directory(first.root).deleteSync(recursive: true);
      final rebuilt = await DoltEmbeddingIndex.open(
        gridHome: home.path,
        identity: const EmbeddingIndexIdentity(
          providerId: 'replacement',
          model: 'wide-model',
          dimensions: 4,
        ),
      );
      expect((await rebuilt.rowCount()).total, 0);
    },
  );

  test(
    'replace, top-k, dimensions, measured counts, and commit work',
    () async {
      final index = await DoltEmbeddingIndex.open(
        gridHome: home.path,
        identity: identity,
      );
      await index.replaceBead(
        store: 'alpha',
        beadId: 'al-1',
        rows: [
          row('alpha', 'al-1', 'title', 0, 'k2', 'nearest', [1, 0, 0]),
          row('alpha', 'al-1', 'design', 1, 'k2', 'farther', [0, 1, 0]),
        ],
      );
      await index.replaceBead(
        store: 'beta',
        beadId: 'be-1',
        rows: [
          row('beta', 'be-1', 'notes', 0, 'k3', 'other store', [1, 0, 0]),
        ],
      );
      await index.replaceBead(
        store: 'alpha',
        beadId: 'al-1',
        rows: [
          row('alpha', 'al-1', 'title', 0, 'k4', 'replacement', [1, 0, 0]),
        ],
      );
      final hits = await index.nearest(
        store: 'alpha',
        queryVector: const [1, 0, 0],
        limit: 5,
      );
      expect(hits.map((hit) => hit.row.chunkText), ['replacement']);
      expect(hits.single.row.changeKey, 'k4');
      expect(hits.single.distance, 0);
      final count = await index.rowCount();
      expect(count.total, 2);
      expect(count.byStore, {'alpha': 1, 'beta': 1});
      await expectLater(
        index.nearest(store: 'alpha', queryVector: const [1, 0], limit: 1),
        throwsArgumentError,
      );
      final log = await dolt(index.root, ['log', '--oneline']);
      expect('${log.stdout}', contains('index alpha/al-1'));
      expect(Directory('${home.path}/.beads').existsSync(), isFalse);
    },
  );

  test('nearest uses only sql commands on an existing index', () async {
    final root = Directory('${home.path}/.grid/embeddings')
      ..createSync(recursive: true);
    Directory('${root.path}/.dolt').createSync();
    final runner = _RecordingRunner();
    final index = await DoltEmbeddingIndex.open(
      gridHome: home.path,
      identity: identity,
      runner: runner,
    );
    runner.arguments.clear();

    final hits = await index.nearest(
      store: 'alpha',
      queryVector: const [1, 0, 0],
      limit: 1,
    );

    expect(hits.single.row.chunkText, 'result');
    expect(runner.arguments, isNotEmpty);
    expect(
      runner.arguments.every((arguments) => arguments.first == 'sql'),
      isTrue,
    );
  });
}

class _RecordingRunner implements DoltCommandRunner {
  final List<List<String>> arguments = [];

  @override
  Future<DoltCommandResult> run(
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    this.arguments.add(List.of(arguments));
    final query = arguments.last;
    final rows = query.contains('embedding_index_metadata')
        ? [
            {
              'provider_id': 'fixture-provider',
              'model': 'fixture-model',
              'dimensions': 3,
            },
          ]
        : [
            {
              'store': 'alpha',
              'bead_id': 'al-1',
              'field': 'title',
              'chunk_ix': 0,
              'change_key': 'k1',
              'chunk_text': 'result',
              'distance': 0,
            },
          ];
    return DoltCommandResult(
      exitCode: 0,
      stdout: jsonEncode({'rows': rows}),
      stderr: '',
    );
  }
}

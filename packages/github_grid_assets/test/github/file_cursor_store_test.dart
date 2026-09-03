import 'dart:convert';
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileGitHubCursorStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('github-cursor-');
    store = FileGitHubCursorStore(
      cursorPath: '${directory.path}/nested/cursor.v1.json',
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('absent file loads empty and save atomically round-trips', () async {
    expect((await store.load()).observationIds, isEmpty);
    final cursor = GitHubReconcilerCursor(
      since: DateTime.parse('2026-08-09T03:00:00-05:00'),
      etags: const <String, String>{'intake/issues': '"one"'},
      observationIds: const <String>['one'],
    );
    await store.save(cursor);
    final loaded = await store.load();
    expect(loaded.since, DateTime.parse('2026-08-09T08:00:00Z'));
    expect(loaded.etags, cursor.etags);
    expect(loaded.observationIds, cursor.observationIds);
    expect(File('${store.cursorPath}.tmp').existsSync(), isFalse);
  });

  test('duplicate is identical and ledger retains newest 512', () {
    final once = const GitHubReconcilerCursor().record('same');
    expect(once.record('same'), same(once));
    var cursor = const GitHubReconcilerCursor();
    for (var index = 0; index < 513; index++) {
      cursor = cursor.record('$index');
    }
    expect(cursor.observationIds, hasLength(512));
    expect(cursor.observationIds.first, '512');
    expect(cursor.observationIds, isNot(contains('0')));
  });

  test('malformed versions and collections fail loudly', () async {
    final file = File(store.cursorPath);
    await file.parent.create(recursive: true);
    for (final document in <String>[
      '{"version":2,"since":null,"etags":{},"observation_ids":[]}',
      '{"version":1,"since":null,"etags":[],"observation_ids":{}}',
      '{"version":1,"since":null,"etags":{},"observation_ids":[],'
          '"pending":{}}',
      '{"version":1,"since":null}',
    ]) {
      await file.writeAsString(document);
      await expectLater(store.load(), throwsFormatException);
    }
  });

  test(
    'a version-one document without pull_heads loads an empty cache',
    () async {
      final file = File(store.cursorPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"version":1,"since":null,"etags":{},"observation_ids":[]}',
      );
      expect((await store.load()).pullHeads, isEmpty);
    },
  );

  test('a cached pull head and its tag are retained and evicted together', () {
    var cursor = const GitHubReconcilerCursor();
    for (var index = 0; index < 513; index++) {
      cursor = cursor.recordPullHead(
        'PR_$index',
        'grid/$index',
        etag: '"$index"',
      );
    }
    expect(cursor.pullHeads, hasLength(512));
    expect(cursor.pullHeads.containsKey('PR_0'), isFalse);
    expect(cursor.etags.containsKey('intake/pull/PR_0'), isFalse);
    expect(cursor.etags['intake/pull/PR_512'], '"512"');
    expect(cursor.pullHeads['PR_512'], 'grid/512');
  });

  test('a version-one document without pending loads an empty queue', () async {
    final file = File(store.cursorPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '{"version":1,"since":"2026-08-09T08:00:00.000Z","etags":{},'
      '"observation_ids":["one"]}',
    );
    final loaded = await store.load();
    expect(loaded.pending, isEmpty);
    expect(loaded.observationIds, <String>['one']);
    expect(loaded.since, DateTime.parse('2026-08-09T08:00:00Z'));
  });

  test('the recorded pending document round-trips through the store', () async {
    final recorded =
        jsonDecode(
              await File('test/fixtures/pending_cursor.json').readAsString(),
            )
            as Map<String, Object?>;
    final cursor = GitHubReconcilerCursor.fromJson(recorded);
    const issueId = 'poll:issue:I_1:2026-08-09T00:00:00Z';
    const pullId = 'poll:issue:PR_2:2026-08-09T01:00:00Z';
    expect(cursor.pending, hasLength(2));
    expect(cursor.pendingFor(issueId)!.acked, <String>['sink']);
    expect(cursor.hasObserved(issueId), isTrue);
    expect(cursor.pendingFor(pullId)!.acked, isEmpty);
    expect(cursor.isPending(pullId), isTrue);
    await store.save(cursor);
    expect((await store.load()).toJson(), recorded);
    final drained = cursor.deliver(pullId);
    expect(drained.pending, hasLength(1));
    expect(drained.hasObserved(pullId), isTrue);
  });

  test('relative cursor paths are refused', () {
    expect(
      () => FileGitHubCursorStore(cursorPath: 'cursor.json'),
      throwsArgumentError,
    );
  });
}

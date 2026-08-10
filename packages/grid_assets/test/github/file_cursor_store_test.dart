import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
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
      '{"version":1,"since":null}',
    ]) {
      await file.writeAsString(document);
      await expectLater(store.load(), throwsFormatException);
    }
  });

  test('relative cursor paths are refused', () {
    expect(
      () => FileGitHubCursorStore(cursorPath: 'cursor.json'),
      throwsArgumentError,
    );
  });
}

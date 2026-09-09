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

  test(
    'a version-one document without workflow_runs_since loads null',
    () async {
      final file = File(store.cursorPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"version":1,"since":null,"etags":{},"observation_ids":[]}',
      );
      final loaded = await store.load();
      expect(loaded.workflowRunsSince, isNull);
      expect(
        loaded.toJson()['workflow_runs_since'],
        isNull,
        reason: 'the key is emitted and absent decodes as null, no bump',
      );
      expect(loaded.toJson()['version'], 1);
    },
  );

  test('a malformed workflow_runs_since fails loudly', () async {
    final file = File(store.cursorPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '{"version":1,"since":null,"etags":{},"observation_ids":[],'
      '"workflow_runs_since":7}',
    );
    await expectLater(store.load(), throwsFormatException);
  });

  test('the workflow-run window survives a save/load round trip', () async {
    final cursor = GitHubReconcilerCursor(
      workflowRunsSince: DateTime.parse('2026-09-07T06:00:00-05:00'),
    );
    await store.save(cursor);
    expect(
      (await store.load()).workflowRunsSince,
      DateTime.parse('2026-09-07T11:00:00Z'),
    );
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
    expect(
      cursor.workflowRunsSince,
      DateTime.parse('2026-08-09T02:00:00Z'),
      reason: 'the recorded document carries the additive window',
    );
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

  GitHubIssueWatchCursorRecord record({
    int lastCommentId = 11,
    int lastTimelineEventId = 91,
    String lastState = 'closed',
    String? lastStateReason = 'not_planned',
    bool locked = false,
    GitHubIssueWatchChange? lastChange =
        GitHubIssueWatchChange.closedNotPlanned,
  }) => GitHubIssueWatchCursorRecord(
    issueNodeId: 'I_kwDO',
    issueAuthor: 'nico',
    lastCommentId: lastCommentId,
    lastTimelineEventId: lastTimelineEventId,
    lastState: lastState,
    lastStateReason: lastStateReason,
    locked: locked,
    lastUpdatedAt: DateTime.utc(2026, 9, 9, 13),
    lastChange: lastChange,
  );

  test(
    'a version-one document without issue_watches loads an empty map',
    () async {
      final file = File(store.cursorPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"version":1,"since":null,"etags":{},"observation_ids":[]}',
      );
      final loaded = await store.load();
      expect(loaded.issueWatches, isEmpty);
      expect(loaded.toJson()['version'], 1, reason: 'no version bump');
      expect(loaded.toJson()['issue_watches'], isEmpty);
    },
  );

  test('a watch record and its two tags survive a round trip', () async {
    final cursor = const GitHubReconcilerCursor().recordIssueWatch(
      'ricardoboss/radioactive_dart#1',
      record(),
      issueEtag: '"issue"',
      timelineEtag: '"timeline"',
    );
    await store.save(cursor);
    final loaded = await store.load();

    expect(loaded.issueWatches['ricardoboss/radioactive_dart#1'], record());
    expect(
      loaded.etags['issue-watch/ricardoboss/radioactive_dart#1/issue'],
      '"issue"',
    );
    expect(
      loaded.etags['issue-watch/ricardoboss/radioactive_dart#1/timeline'],
      '"timeline"',
    );
    expect(loaded.toJson(), cursor.toJson());
  });

  test('a wrongly shaped issue_watches value fails loudly', () async {
    final file = File(store.cursorPath);
    await file.parent.create(recursive: true);
    const head = '{"version":1,"since":null,"etags":{},"observation_ids":[],';
    for (final document in <String>[
      // Not a map at all.
      '$head"issue_watches":[]}',
      // A key that is not a coordinate.
      '$head"issue_watches":{"nonsense":{"issue_node_id":"I","issue_author":'
          '"nico","last_comment_id":0,"last_timeline_event_id":0,"last_state":'
          '"open","last_state_reason":null,"locked":false,"last_updated_at":'
          '"2026-09-09T13:00:00.000Z","last_change":null}}}',
      // A record missing a required field.
      '$head"issue_watches":{"o/r#1":{"issue_node_id":"I"}}}',
      // A timestamp with no zone at all, which would parse as LOCAL time.
      '$head"issue_watches":{"o/r#1":{"issue_node_id":"I","issue_author":'
          '"nico","last_comment_id":0,"last_timeline_event_id":0,"last_state":'
          '"open","last_state_reason":null,"locked":false,"last_updated_at":'
          '"2026-09-09T13:00:00","last_change":null}}}',
      // An unsupported change spelling.
      '$head"issue_watches":{"o/r#1":{"issue_node_id":"I","issue_author":'
          '"nico","last_comment_id":0,"last_timeline_event_id":0,"last_state":'
          '"open","last_state_reason":null,"locked":false,"last_updated_at":'
          '"2026-09-09T13:00:00.000Z","last_change":"exploded"}}}',
      // A non-boolean lock.
      '$head"issue_watches":{"o/r#1":{"issue_node_id":"I","issue_author":'
          '"nico","last_comment_id":0,"last_timeline_event_id":0,"last_state":'
          '"open","last_state_reason":null,"locked":"yes","last_updated_at":'
          '"2026-09-09T13:00:00.000Z","last_change":null}}}',
    ]) {
      await file.writeAsString(document);
      await expectLater(store.load(), throwsFormatException);
    }
  });

  test('a watch record and both of its tags are evicted together', () {
    var cursor = const GitHubReconcilerCursor();
    for (var index = 0; index < 513; index++) {
      cursor = cursor.recordIssueWatch(
        'owner/repo#${index + 1}',
        record(),
        issueEtag: '"issue-$index"',
        timelineEtag: '"timeline-$index"',
      );
    }
    expect(cursor.issueWatches, hasLength(512));
    expect(cursor.issueWatches.containsKey('owner/repo#1'), isFalse);
    expect(cursor.etags.containsKey('issue-watch/owner/repo#1/issue'), isFalse);
    expect(
      cursor.etags.containsKey('issue-watch/owner/repo#1/timeline'),
      isFalse,
    );
    expect(cursor.etags['issue-watch/owner/repo#513/issue'], '"issue-512"');
  });

  test('a null final tag DROPS the tag it names', () {
    final cursor = const GitHubReconcilerCursor()
        .recordIssueWatch(
          'owner/repo#1',
          record(),
          issueEtag: '"issue"',
          timelineEtag: '"timeline"',
        )
        .recordIssueWatch('owner/repo#1', record(), issueEtag: '"issue-2"');
    expect(cursor.etags['issue-watch/owner/repo#1/issue'], '"issue-2"');
    expect(
      cursor.etags.containsKey('issue-watch/owner/repo#1/timeline'),
      isFalse,
      reason: 'a baseline and the tag that serves it never diverge',
    );
  });

  test('retaining an unchanged configuration is identical', () {
    const watch = GitHubIssueWatch(
      originatingBeadId: 'lunar_station-6p9',
      owner: 'ricardoboss',
      repository: 'radioactive_dart',
      issueNumber: 1,
    );
    final cursor = const GitHubReconcilerCursor().recordIssueWatch(
      watch.coordinateKey,
      record(),
      issueEtag: '"issue"',
    );
    expect(
      cursor.retainIssueWatches(const <GitHubIssueWatch>[watch]),
      same(cursor),
      reason: 'nothing changed, so nothing is saved',
    );
  });
}

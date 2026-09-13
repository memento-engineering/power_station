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
  GitHubPullFeedbackCursorRecord feedback({
    int number = 8,
    String headSha = 'abc123',
    PullRequestCheckState checkState = PullRequestCheckState.green,
    PullRequestMergeability mergeability = PullRequestMergeability.mergeable,
    DateTime? greenSince,
  }) => GitHubPullFeedbackCursorRecord(
    actor: 'nico',
    number: number,
    body: 'A human digest.\n\nRefs: pow-78jk\n',
    headBranch: 'org/lockfile-convention',
    headSha: headSha,
    checkState: checkState,
    mergeability: mergeability,
    openedAt: DateTime.utc(2026, 9, 12, 8),
    updatedAt: DateTime.utc(2026, 9, 12, 9),
    greenSince: greenSince ?? DateTime.utc(2026, 9, 12, 9, 30),
  );

  test('pull feedback cache is additive bounded and co-evicts etags', () async {
    final file = File(store.cursorPath);
    await file.parent.create(recursive: true);
    // ADDITIVE at version 1: a cursor written before this cache existed
    // still loads, and loads with an empty cache rather than being refused.
    await file.writeAsString(
      '{"version":1,"since":null,"etags":{},"observation_ids":[]}',
    );
    final legacy = await store.load();
    expect(legacy.pullFeedback, isEmpty);
    expect(legacy.toJson()['version'], 1, reason: 'no version bump');
    expect(legacy.toJson()['pull_feedback'], isEmpty);

    // A record and BOTH of its conditional tags survive one save/load.
    final saved = const GitHubReconcilerCursor().recordPullFeedback(
      'PR_kwDO',
      feedback(),
      detailEtag: '"detail"',
      checksEtag: '"checks"',
    );
    await store.save(saved);
    final loaded = await store.load();
    expect(loaded.pullFeedback['PR_kwDO'], feedback());
    expect(loaded.etags['feedback/pull/PR_kwDO'], '"detail"');
    expect(loaded.etags['feedback/checks/PR_kwDO'], '"checks"');
    expect(loaded.toJson(), saved.toJson());

    // The whole record is retained NEWEST-FIRST to 512, and the evicted
    // record takes BOTH of its tags with it — a tag with no record behind it
    // would earn a `304` nothing could answer.
    var bounded = const GitHubReconcilerCursor();
    for (var index = 0; index < 513; index++) {
      bounded = bounded.recordPullFeedback(
        'PR_$index',
        feedback(number: index),
        detailEtag: '"detail-$index"',
        checksEtag: '"checks-$index"',
      );
    }
    expect(bounded.pullFeedback, hasLength(512));
    expect(bounded.pullFeedback.containsKey('PR_0'), isFalse);
    expect(bounded.etags.containsKey('feedback/pull/PR_0'), isFalse);
    expect(bounded.etags.containsKey('feedback/checks/PR_0'), isFalse);
    expect(bounded.etags['feedback/pull/PR_512'], '"detail-512"');
    expect(bounded.etags['feedback/checks/PR_512'], '"checks-512"');

    // A null final tag DROPS the tag it names.
    final dropped = bounded.recordPullFeedback(
      'PR_512',
      feedback(),
      detailEtag: '"detail-again"',
    );
    expect(dropped.etags['feedback/pull/PR_512'], '"detail-again"');
    expect(dropped.etags.containsKey('feedback/checks/PR_512'), isFalse);

    // A CLOSED pull is dropped with both of its tags; retaining an unchanged
    // open set saves nothing at all.
    final two = const GitHubReconcilerCursor()
        .recordPullFeedback(
          'PR_open',
          feedback(),
          detailEtag: '"open-detail"',
          checksEtag: '"open-checks"',
        )
        .recordPullFeedback(
          'PR_closed',
          feedback(),
          detailEtag: '"closed-detail"',
          checksEtag: '"closed-checks"',
        );
    final retained = two.retainPullFeedback(const <String>['PR_open']);
    expect(retained.pullFeedback.keys, <String>['PR_open']);
    expect(retained.etags.containsKey('feedback/pull/PR_closed'), isFalse);
    expect(retained.etags.containsKey('feedback/checks/PR_closed'), isFalse);
    expect(retained.etags['feedback/pull/PR_open'], '"open-detail"');
    expect(retained.etags['feedback/checks/PR_open'], '"open-checks"');
    expect(
      retained.retainPullFeedback(const <String>['PR_open']),
      same(retained),
      reason: 'nothing changed, so nothing is saved',
    );
    expect(
      two.retainPullFeedback(const <String>[
        'PR_open',
        'PR_closed',
      ]).etags['feedback/pulls'],
      isNull,
      reason: 'the open-pulls PAGE key is not a per-pull tag',
    );
  });

  test('a wrongly shaped pull_feedback value fails loudly', () async {
    final file = File(store.cursorPath);
    await file.parent.create(recursive: true);
    const head = '{"version":1,"since":null,"etags":{},"observation_ids":[],';
    const good =
        '"actor":"nico","number":8,"body":"b","head_branch":"org/x",'
        '"head_sha":"abc","check_state":"green","mergeability":"mergeable",'
        '"opened_at":"2026-09-12T08:00:00.000Z",'
        '"updated_at":"2026-09-12T09:00:00.000Z",'
        '"green_since":"2026-09-12T09:30:00.000Z"';
    for (final document in <String>[
      // Not a map at all.
      '$head"pull_feedback":[]}',
      // A record missing a required field.
      '$head"pull_feedback":{"PR_1":{"actor":"nico"}}}',
      // An unsupported check-state spelling.
      '$head"pull_feedback":{"PR_1":{${good.replaceFirst('"green"', '"exploded"')}}}}',
      // An unsupported mergeability spelling.
      '$head"pull_feedback":{"PR_1":{${good.replaceFirst('"mergeable"', '"maybe"')}}}}',
      // A number that is not an integer.
      '$head"pull_feedback":{"PR_1":{${good.replaceFirst('"number":8', '"number":"8"')}}}}',
      // A body that is not a string.
      '$head"pull_feedback":{"PR_1":{${good.replaceFirst('"body":"b"', '"body":true')}}}}',
      // A timestamp with no zone at all, which would parse as LOCAL time.
      '$head"pull_feedback":{"PR_1":{${good.replaceFirst('"2026-09-12T09:30:00.000Z"', '"2026-09-12T09:30:00"')}}}}',
    ]) {
      await file.writeAsString(document);
      await expectLater(store.load(), throwsFormatException);
    }
    // The control: the same document, well-formed, loads.
    await file.writeAsString('$head"pull_feedback":{"PR_1":{$good}}}');
    final loaded = await store.load();
    expect(
      loaded.pullFeedback['PR_1']!.checkState,
      PullRequestCheckState.green,
    );
    expect(
      loaded.pullFeedback['PR_1']!.greenSince,
      DateTime.utc(2026, 9, 12, 9, 30),
    );
    expect(
      GitHubPullFeedbackCursorRecord.fromJson(
        (jsonDecode('{$good, "green_since":null}') as Map)
            .cast<String, Object?>(),
      ).greenSince,
      isNull,
      reason: 'a pull that was never green carries no green instant',
    );
  });
}

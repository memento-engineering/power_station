import 'dart:convert';
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  test('normalized polling and webhook fixtures round-trip all arms', () async {
    final polling =
        jsonDecode(
              await File('test/fixtures/poll_observation.json').readAsString(),
            )
            as List<Object?>;
    final webhook =
        jsonDecode(
              await File(
                'test/fixtures/webhook_observation.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final json = <Map<String, Object?>>[
      ...polling.cast<Map<String, Object?>>(),
      webhook,
    ];
    final events = json.map(NormalizedGitHubEvent.fromJson).toList();
    expect(events, <Matcher>[
      isA<IssueOpened>(),
      isA<PullRequestOpened>(),
      isA<WorkflowRunConcluded>(),
      isA<CheckConcluded>(),
    ]);
    // Normalized through the encoder because that is what the cursor document
    // actually persists: `toJson` leaves nested values as their own objects.
    expect(
      jsonDecode(jsonEncode(events.map((event) => event.toJson()).toList())),
      json,
    );
    final pull = events.whereType<PullRequestOpened>().single;
    expect(pull.headRef, 'grid/pow-40a4');
    expect(pull.toJson(), isNot(contains('headBranch')));
    final check = events.whereType<CheckConcluded>().single;
    expect(check.headBranch, 'grid/work');
    final run = events.whereType<WorkflowRunConcluded>().single;
    expect(run.workflowPath, '.github/workflows/ci.yaml');
    expect(run.runNumber, 128);
    expect(run.actor, 'memento/power', reason: 'a run has no human author');
    expect(run.failedJobs.map((job) => job.jobName), ['analyze', 'test']);
    expect(run.failedJobs.first.failedStepName, 'dart analyze');
    expect(
      run.failedJobs.last.failedStepName,
      isNull,
      reason: 'a job GitHub named no failed step for reports none',
    );
    final encoded = jsonEncode(events.map((event) => event.toJson()).toList());
    for (final rawKey in <String>[
      'pull_request',
      'check_runs',
      'sender',
      'head_repository',
      'workflow_runs',
    ]) {
      expect(encoded, isNot(contains(rawKey)));
    }
  });

  test('watch variants round-trip and carry no raw GitHub keys', () {
    final events = <NormalizedGitHubEvent>[
      NormalizedGitHubEvent.issueCommented(
        nodeId: 'IC_first',
        actor: 'ricardoboss',
        repository: 'ricardoboss/radioactive_dart',
        substation: 'power_station',
        observationId: 'poll:issue-comment:IC_first',
        originatingBeadId: 'lunar_station-6p9',
        issueNodeId: 'I_kwDO',
        issueAuthor: 'nico',
        issueNumber: 1,
        commentId: 11,
        body: 'A maintainer reply.',
        url: 'https://github.com/ricardoboss/radioactive_dart/issues/1',
        updatedAt: DateTime.utc(2026, 9, 9, 11),
      ),
      NormalizedGitHubEvent.watchedIssueStateChanged(
        nodeId: 'CE_closed',
        actor: 'ricardoboss',
        repository: 'ricardoboss/radioactive_dart',
        substation: 'power_station',
        observationId: 'poll:issue-state:CE_closed:closed_not_planned',
        originatingBeadId: 'lunar_station-6p9',
        issueNodeId: 'I_kwDO',
        issueAuthor: 'nico',
        issueNumber: 1,
        change: GitHubIssueWatchChange.closedNotPlanned,
        state: 'closed',
        stateReason: 'not_planned',
        locked: false,
        url: null,
        updatedAt: DateTime.utc(2026, 9, 9, 13),
      ),
    ];

    for (final event in events) {
      final encoded = jsonDecode(jsonEncode(event.toJson()));
      expect(
        NormalizedGitHubEvent.fromJson(encoded as Map<String, Object?>),
        event,
      );
      for (final rawKey in const <String>[
        'state_reason',
        'node_id',
        'html_url',
        'timeline',
        'user',
      ]) {
        expect(jsonEncode(event.toJson()), isNot(contains(rawKey)));
      }
    }
    expect(
      events.last.toJson()['change'],
      'closed_not_planned',
      reason: 'the enum has a stable snake wire spelling',
    );
    expect(events.first.toJson()['runtimeType'], 'issueCommented');
    expect(events.last.toJson()['runtimeType'], 'watchedIssueStateChanged');
  });

  test('pull feedback round-trips actionable fields', () {
    // Every check state and every mergeability, and BOTH shapes of
    // `greenSince`: the field is the whole stall observation, so a null that
    // decoded as an epoch — or a non-null that decoded as null — would silently
    // turn "green for an hour" into "never green".
    PullRequestFeedback feedback(
      PullRequestCheckState checkState,
      PullRequestMergeability mergeability, {
      DateTime? greenSince,
      bool stalled = false,
    }) =>
        NormalizedGitHubEvent.pullRequestFeedback(
              nodeId: 'PR_kwDO',
              actor: 'nico',
              repository: 'memento-engineering/power_station',
              substation: 'power_station',
              observationId:
                  'poll:pull-feedback:PR_kwDO:abc123:${checkState.name}',
              number: 8,
              body: 'A human digest.\n\nRefs: pow-78jk\n',
              headBranch: 'org/lockfile-convention',
              headSha: 'abc123',
              checkState: checkState,
              mergeability: mergeability,
              openedAt: DateTime.utc(2026, 9, 12, 8),
              updatedAt: DateTime.utc(2026, 9, 12, 9),
              greenSince: greenSince,
              observedAt: DateTime.utc(2026, 9, 12, 11),
              stalled: stalled,
            )
            as PullRequestFeedback;

    final cases = <PullRequestFeedback>[
      for (final state in PullRequestCheckState.values)
        for (final mergeability in PullRequestMergeability.values)
          feedback(state, mergeability),
      feedback(
        PullRequestCheckState.green,
        PullRequestMergeability.mergeable,
        greenSince: DateTime.utc(2026, 9, 12, 9, 30),
        stalled: true,
      ),
    ];

    for (final event in cases) {
      final encoded = jsonDecode(jsonEncode(event.toJson()));
      expect(
        NormalizedGitHubEvent.fromJson(encoded as Map<String, Object?>),
        event,
      );
    }

    final stalled = cases.last;
    final decoded =
        NormalizedGitHubEvent.fromJson(
              jsonDecode(jsonEncode(stalled.toJson())) as Map<String, Object?>,
            )
            as PullRequestFeedback;
    // The actionable set, field by field: the governor is informed through
    // exactly these, so a dropped one is a governor that cannot decide.
    expect(decoded.repository, 'memento-engineering/power_station');
    expect(decoded.number, 8);
    expect(decoded.body, contains('Refs: pow-78jk'));
    expect(decoded.headBranch, 'org/lockfile-convention');
    expect(decoded.headSha, 'abc123');
    expect(decoded.checkState, PullRequestCheckState.green);
    expect(decoded.mergeability, PullRequestMergeability.mergeable);
    expect(decoded.openedAt, DateTime.utc(2026, 9, 12, 8));
    expect(decoded.updatedAt, DateTime.utc(2026, 9, 12, 9));
    expect(decoded.greenSince, DateTime.utc(2026, 9, 12, 9, 30));
    expect(decoded.observedAt, DateTime.utc(2026, 9, 12, 11));
    expect(decoded.stalled, isTrue);
    expect(
      cases.first.greenSince,
      isNull,
      reason: 'a non-green head was never green',
    );
    expect(stalled.toJson()['runtimeType'], 'pullRequestFeedback');
    expect(stalled.toJson()['checkState'], 'green');
    expect(stalled.toJson()['mergeability'], 'mergeable');
    for (final rawKey in const <String>[
      'check_runs',
      'node_id',
      'head_sha',
      'created_at',
      'updated_at',
      'completed_at',
    ]) {
      expect(jsonEncode(stalled.toJson()), isNot(contains(rawKey)));
    }
  });

  test('every change value has a distinct, stable wire spelling', () {
    final wires = <String>{
      for (final change in GitHubIssueWatchChange.values) change.wire,
    };
    expect(wires, hasLength(GitHubIssueWatchChange.values.length));
    expect(wires, <String>{
      'closed_completed',
      'closed_not_planned',
      'reopened',
      'locked',
      'transferred',
      'deleted',
      'converted_to_discussion',
      'unreadable',
    });
    for (final change in GitHubIssueWatchChange.values) {
      expect(GitHubIssueWatchChange.fromWire(change.wire), change);
    }
    expect(
      () => GitHubIssueWatchChange.fromWire('exploded'),
      throwsFormatException,
    );
  });
}

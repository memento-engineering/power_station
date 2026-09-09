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

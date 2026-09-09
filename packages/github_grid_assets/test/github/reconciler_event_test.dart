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
}

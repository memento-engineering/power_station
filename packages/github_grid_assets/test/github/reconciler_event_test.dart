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
      isA<CheckConcluded>(),
    ]);
    expect(events.map((event) => event.toJson()).toList(), json);
    final encoded = jsonEncode(events.map((event) => event.toJson()).toList());
    for (final rawKey in <String>['pull_request', 'check_runs', 'sender']) {
      expect(encoded, isNot(contains(rawKey)));
    }
  });
}

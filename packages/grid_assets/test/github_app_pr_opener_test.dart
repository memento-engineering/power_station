import 'dart:convert';
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _FakeTransport implements GitHubHttpTransport {
  _FakeTransport(this.responses, {this.error});

  final List<GitHubHttpResponse> responses;
  final Object? error;
  final requests = <GitHubHttpRequest>[];

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    if (error case final value?) throw value;
    return responses.removeAt(0);
  }
}

void main() {
  test('posts the exact payload and returns html_url plus number', () async {
    final transport = _FakeTransport(_successResponses());
    var remoteReads = 0;
    final opener = await _opener(
      transport,
      owner: 'memento-engineering',
      repository: 'power_station',
      remoteReader: (_) async {
        remoteReads++;
        throw StateError('unused');
      },
    );
    final result = await opener.open(
      workDir: '/unused',
      branch: 'grid/pow-1rn.2',
      baseBranch: 'main',
      title: 'Bot PR',
      body: 'body',
    );
    expect(result.isOpened, isTrue);
    expect(
      result.ref?.url,
      'https://github.com/memento-engineering/power_station/pull/107',
    );
    expect(result.ref?.number, 107);
    expect(remoteReads, 0);
    final request = transport.requests.last;
    expect(request.uri.path, '/repos/memento-engineering/power_station/pulls');
    expect(jsonDecode(request.body!), <String, Object>{
      'title': 'Bot PR',
      'body': 'body',
      'head': 'grid/pow-1rn.2',
      'base': 'main',
    });
  });

  for (final remote in <String>[
    'git@github.com:memento-engineering/power_station.git',
    'https://github.com/memento-engineering/power_station.git',
  ]) {
    test('derives owner/repository from $remote', () async {
      final transport = _FakeTransport(_successResponses());
      final opener = await _opener(
        transport,
        remoteReader: (_) async => remote,
      );
      final result = await opener.open(
        workDir: '/checkout',
        branch: 'grid/x',
        baseBranch: 'main',
        title: 'x',
      );
      expect(result.isOpened, isTrue);
      expect(
        transport.requests.last.uri.path,
        '/repos/memento-engineering/power_station/pulls',
      );
    });
  }

  for (final entry in <(int, String)>[
    (401, 'credentials'),
    (403, 'permission'),
    (404, 'Install the App'),
    (422, 'already exist'),
    (429, 'rate-limit'),
  ]) {
    test('HTTP ${entry.$1} returns an actionable failure', () async {
      final transport = _FakeTransport(<GitHubHttpResponse>[
        ..._tokenResponse(),
        GitHubHttpResponse(statusCode: entry.$1, body: '{"message":"refused"}'),
      ]);
      final result = await (await _opener(
        transport,
        owner: 'o',
        repository: 'r',
      )).open(workDir: '/unused', branch: 'b', baseBranch: 'main', title: 't');
      expect(result.isOpened, isFalse);
      expect(_resultReason(result), contains('HTTP ${entry.$1}'));
      expect(_resultReason(result), contains(entry.$2));
    });
  }

  test('malformed success, unparseable remote, git error, and transport error '
      'never throw', () async {
    final cases = <Future<PullRequestResult> Function()>[
      () async => (await _opener(
        _FakeTransport(<GitHubHttpResponse>[
          ..._tokenResponse(),
          const GitHubHttpResponse(statusCode: 201, body: '{}'),
        ]),
        owner: 'o',
        repository: 'r',
      )).open(workDir: '/unused', branch: 'b', baseBranch: 'main', title: 't'),
      () async =>
          (await _opener(
            _FakeTransport(_successResponses()),
            remoteReader: (_) async => 'not-a-remote',
          )).open(
            workDir: '/checkout',
            branch: 'b',
            baseBranch: 'main',
            title: 't',
          ),
      () async =>
          (await _opener(
            _FakeTransport(_successResponses()),
            remoteReader: (_) async => throw StateError('git failed'),
          )).open(
            workDir: '/checkout',
            branch: 'b',
            baseBranch: 'main',
            title: 't',
          ),
      () async => (await _opener(
        _FakeTransport(
          const <GitHubHttpResponse>[],
          error: StateError('offline'),
        ),
        owner: 'o',
        repository: 'r',
      )).open(workDir: '/unused', branch: 'b', baseBranch: 'main', title: 't'),
    ];
    for (final invoke in cases) {
      final result = await invoke();
      expect(result.isOpened, isFalse);
      expect(_resultReason(result), isNotEmpty);
    }
  });

  test('parses an ssh URL into repository coordinates', () {
    expect(
      parseGitHubRemote(
        'ssh://git@github.com/memento-engineering/power_station.git',
      ),
      ('memento-engineering', 'power_station'),
    );
  });
}

List<GitHubHttpResponse> _successResponses() => <GitHubHttpResponse>[
  ..._tokenResponse(),
  const GitHubHttpResponse(
    statusCode: 201,
    body:
        '{"html_url":"https://github.com/memento-engineering/'
        'power_station/pull/107","number":107}',
  ),
];

List<GitHubHttpResponse> _tokenResponse() => const <GitHubHttpResponse>[
  GitHubHttpResponse(
    statusCode: 201,
    body: '{"token":"installation-token","expires_at":"2026-08-09T22:00:00Z"}',
  ),
];

Future<GitHubAppPrOpener> _opener(
  _FakeTransport transport, {
  String? owner,
  String? repository,
  GitRemoteReader? remoteReader,
}) async {
  final config = GitHubAppConfig(appId: '123', installationId: 456);
  final pem = await File(
    '../github_grid_assets/test/fixtures/github_app_test_private.pem',
  ).readAsString();
  final tokens = GitHubAppTokenProvider(
    config: config,
    privateKey: GitHubAppPrivateKey(path: '/test/key.pem', pem: pem),
    transport: transport,
    clock: () => DateTime.utc(2026, 8, 9, 20),
  );
  return GitHubAppPrOpener(
    client: GitHubAppClient(
      config: config,
      tokens: tokens,
      transport: transport,
    ),
    owner: owner,
    repository: repository,
    remoteReader: remoteReader ?? readOriginRemote,
  );
}

String _resultReason(PullRequestResult result) => result.failure!.reason;

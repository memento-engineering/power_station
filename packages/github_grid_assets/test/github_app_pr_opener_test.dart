import 'dart:convert';
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _FakeTransport implements GitHubHttpTransport {
  _FakeTransport(this.responses, {this.error, this.errorPathSuffix});

  final List<GitHubHttpResponse> responses;
  final Object? error;

  /// When set, [error] is thrown only for a request whose path ends with it —
  /// the incident's shape, where the installation-token exchange SUCCEEDS and
  /// the `/pulls` POST throws. When null, the FIRST send throws.
  final String? errorPathSuffix;
  final requests = <GitHubHttpRequest>[];

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    final suffix = errorPathSuffix;
    if (error case final value?
        when suffix == null || request.uri.path.endsWith(suffix)) {
      throw value;
    }
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

  test('a thrown latin1 encoding error escalates type-first and cause-last, '
      'without the request body', () async {
    // The REAL dart:convert shape: latin1 refuses the first code unit above
    // U+00FF and embeds the WHOLE json request as the invalid value, which
    // `Error.safeToString` then renders BACK-SLASH-ESCAPED and quoted.
    final requestJson = jsonEncode(<String, Object>{
      'title': 'Bot PR',
      'body': 'validation plan — ${'plan step. ' * 200}',
      'head': 'grid/pow-b14a',
      'base': 'main',
    });
    final transport = _FakeTransport(
      _successResponses(),
      errorPathSuffix: '/pulls',
      error: ArgumentError.value(
        requestJson,
        'string',
        'Contains invalid characters.',
      ),
    );
    final result =
        await (await _opener(
          transport,
          owner: 'memento-engineering',
          repository: 'power_station',
        )).open(
          workDir: '/unused',
          branch: 'grid/pow-b14a',
          baseBranch: 'main',
          title: 'Bot PR',
        );

    expect(result.isOpened, isFalse);
    final reason = _resultReason(result);
    expect(reason, contains('ArgumentError'));
    expect(reason, isNot(contains(r'\"base\":\"main\"')));
    expect(reason, isNot(contains('"base":"main"')));
    expect(reason.length, lessThanOrEqualTo(461));
    expect(reason.substring(reason.length - 200), isNot(contains('Verify')));
    // The incident itself: the tail-first capture must keep the CAUSE.
    expect(
      landReasonTail('pr open failed — $reason'),
      contains('ArgumentError'),
    );
  });

  test('the HTTP-status path renders owner/repo, status, detail, and action '
      'unchanged', () async {
    final transport = _FakeTransport(<GitHubHttpResponse>[
      ..._tokenResponse(),
      const GitHubHttpResponse(
        statusCode: 404,
        body: '{"message":"Not Found"}',
      ),
    ]);
    final result = await (await _opener(
      transport,
      owner: 'owner',
      repository: 'repo',
    )).open(workDir: '/unused', branch: 'b', baseBranch: 'main', title: 't');

    expect(
      _resultReason(result),
      'GitHub refused PR creation for owner/repo (HTTP 404: Not Found). '
      'Install the App for owner/repo and verify the repository coordinates.',
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
    'test/fixtures/github_app_test_private.pem',
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

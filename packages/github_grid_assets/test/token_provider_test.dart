import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

final _config = GitHubAppConfig(appId: '12345', installationId: 67890);
final _now = DateTime.utc(2026, 8, 8, 12);

class FakeGitHubHttpTransport implements GitHubHttpTransport {
  FakeGitHubHttpTransport(this.handler);
  final Future<GitHubHttpResponse> Function(GitHubHttpRequest) handler;
  final requests = <GitHubHttpRequest>[];

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) {
    requests.add(request);
    return handler(request);
  }
}

void main() {
  late String pem;
  setUpAll(() async {
    pem = await File(
      'test/fixtures/github_app_test_private.pem',
    ).readAsString();
  });

  GitHubAppTokenProvider provider(
    FakeGitHubHttpTransport transport, {
    DateTime Function()? clock,
  }) => GitHubAppTokenProvider(
    config: _config,
    privateKey: GitHubAppPrivateKey(path: '/test/key.pem', pem: pem),
    transport: transport,
    clock: clock ?? () => _now,
  );

  test(
    'signs exact app claims and exchanges at the installation endpoint',
    () async {
      final transport = FakeGitHubHttpTransport(
        (_) async =>
            _tokenResponse('install-token', _now.add(const Duration(hours: 1))),
      );
      expect(await provider(transport).accessToken(), 'install-token');

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri,
        Uri.parse(
          'https://api.github.com/app/installations/67890/access_tokens',
        ),
      );
      expect(request.body, '{}');
      expect(request.headers['Accept'], 'application/vnd.github+json');
      expect(request.headers['Content-Type'], 'application/json');
      expect(request.headers['X-GitHub-Api-Version'], '2022-11-28');
      final compact = request.headers['Authorization']!.substring(
        'Bearer '.length,
      );
      final jwt = _decodeCompact(compact);
      expect(jwt.header['alg'], 'RS256');
      expect(jwt.payload, <String, dynamic>{
        'iat':
            _now.subtract(const Duration(seconds: 60)).millisecondsSinceEpoch ~/
            1000,
        'exp':
            _now.add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
            1000,
        'iss': '12345',
      });
    },
  );

  test('non-201 response identifies token exchange', () async {
    final transport = FakeGitHubHttpTransport(
      (_) async => const GitHubHttpResponse(statusCode: 401, body: '{}'),
    );
    await expectLater(
      provider(transport).accessToken(),
      throwsA(
        isA<StateError>().having(
          (e) => '$e',
          'message',
          contains('token exchange'),
        ),
      ),
    );
  });

  for (final body in <String>[
    'not json',
    '{}',
    '{"token":"value"}',
    '{"token":7,"expires_at":"bad"}',
  ]) {
    test('malformed response is rejected: $body', () async {
      final transport = FakeGitHubHttpTransport(
        (_) async => GitHubHttpResponse(statusCode: 201, body: body),
      );
      await expectLater(
        provider(transport).accessToken(),
        throwsA(
          isA<StateError>().having(
            (e) => '$e',
            'message',
            contains('malformed'),
          ),
        ),
      );
    });
  }

  test('reuses a token outside the refresh window', () async {
    final transport = FakeGitHubHttpTransport(
      (_) async =>
          _tokenResponse('cached', _now.add(const Duration(minutes: 2))),
    );
    final tokens = provider(transport);
    expect(await tokens.accessToken(), 'cached');
    expect(await tokens.accessToken(), 'cached');
    expect(transport.requests, hasLength(1));
  });

  test('refreshes at the exact one-minute boundary', () async {
    var current = _now;
    var exchange = 0;
    final transport = FakeGitHubHttpTransport((_) async {
      exchange++;
      return _tokenResponse(
        'token-$exchange',
        _now.add(const Duration(minutes: 2)),
      );
    });
    final tokens = provider(transport, clock: () => current);
    expect(await tokens.accessToken(), 'token-1');
    current = _now.add(const Duration(minutes: 1));
    expect(await tokens.accessToken(), 'token-2');
    expect(transport.requests, hasLength(2));
  });

  test('coalesces two concurrent callers into one exchange', () async {
    final response = Completer<GitHubHttpResponse>();
    final transport = FakeGitHubHttpTransport((_) => response.future);
    final tokens = provider(transport);
    final first = tokens.accessToken();
    final second = tokens.accessToken();
    response.complete(
      _tokenResponse('shared', _now.add(const Duration(hours: 1))),
    );
    expect(await Future.wait(<Future<String>>[first, second]), <String>[
      'shared',
      'shared',
    ]);
    expect(transport.requests, hasLength(1));
  });
}

GitHubHttpResponse _tokenResponse(String token, DateTime expiresAt) =>
    GitHubHttpResponse(
      statusCode: 201,
      body: jsonEncode(<String, String>{
        'token': token,
        'expires_at': expiresAt.toIso8601String(),
      }),
    );

({Map<String, dynamic> header, Map<String, dynamic> payload}) _decodeCompact(
  String compact,
) {
  Map<String, dynamic> part(int index) =>
      jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(compact.split('.')[index])),
            ),
          )
          as Map<String, dynamic>;
  return (header: part(0), payload: part(1));
}

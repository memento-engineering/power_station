import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

final class _Transport implements GitHubHttpTransport {
  final List<GitHubHttpRequest> requests = <GitHubHttpRequest>[];
  Object? failure;

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    if (failure case final error?) throw error;
    return const GitHubHttpResponse(statusCode: 200, body: 'ok');
  }
}

/// A token provider that FAILS the test if it is ever consulted.
final class _RefusingTokens implements GitHubAppTokenProvider {
  @override
  Future<String> accessToken() =>
      throw StateError('the foreign lane has no installation to mint from');
}

GitHubReadClient _client(
  _Transport transport, {
  String? token,
  GitHubReadScheduler? schedule,
}) => GitHubReadClient(
  transport: transport,
  apiBaseUri: Uri.parse('https://api.github.test'),
  personalToken: token,
  schedule: schedule,
);

void main() {
  test('a token-less read omits Authorization entirely', () async {
    final transport = _Transport();
    final response = await _client(transport).get(
      path: '/repos/ricardoboss/radioactive_dart/issues/1',
      queryParameters: const <String, String>{'per_page': '100'},
      headers: const <String, String>{'If-None-Match': '"issue"'},
    );

    expect(response.statusCode, 200);
    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(
      request.uri,
      Uri.parse(
        'https://api.github.test/repos/ricardoboss/radioactive_dart/issues/1'
        '?per_page=100',
      ),
    );
    expect(request.headers, <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'If-None-Match': '"issue"',
    });
    expect(
      request.headers.containsKey('Authorization'),
      isFalse,
      reason:
          'an empty bearer is a MALFORMED credential to GitHub, not an absent '
          'one',
    );
    expect(request.body, isNull);
  });

  test('a blank token is treated as no token at all', () async {
    for (final token in <String?>[null, '', '   ']) {
      final transport = _Transport();
      final client = _client(transport, token: token);
      expect(client.isAuthenticated, isFalse);
      await client.get(path: '/rate_limit');
      expect(
        transport.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    }
  });

  test('a nonblank token rides the shared bearer header', () async {
    final transport = _Transport();
    final client = _client(transport, token: 'personal');
    expect(client.isAuthenticated, isTrue);
    await client.get(path: '/rate_limit');
    expect(
      transport.requests.single.headers['Authorization'],
      'Bearer personal',
    );
  });

  test('the client holds no token provider and exposes no write verb', () {
    // The seam itself is the proof: constructing a read client requires no
    // GitHubAppTokenProvider, and a refusing one cannot be reached from it.
    final transport = _Transport();
    final client = _client(transport);
    expect(client, isA<GitHubReadClient>());
    expect(client, isNot(isA<GitHubAppClient>()));
    expect(_RefusingTokens(), isA<GitHubAppTokenProvider>());
  });

  test('a relative API path is refused loudly', () {
    expect(
      () => _client(_Transport()).get(path: 'repos/owner/name/issues/1'),
      throwsArgumentError,
    );
  });

  test('every read passes through the injected scheduler', () async {
    final transport = _Transport();
    final order = <String>[];
    final client = _client(
      transport,
      schedule: (request) async {
        order.add('scheduled');
        final response = await request();
        order.add('completed');
        return response;
      },
    );

    await client.get(path: '/rate_limit');

    expect(order, <String>['scheduled', 'completed']);
    expect(transport.requests, hasLength(1));
  });

  test(
    'a transport failure escalates type-first with a bounded cause',
    () async {
      final transport = _Transport()
        ..failure = StateError('x' * (kMaxGitHubCauseChars + 200));

      await expectLater(
        _client(transport).get(path: '/rate_limit'),
        throwsA(
          isA<GitHubReadException>().having(
            (error) => error.toString(),
            'toString',
            allOf(
              startsWith('Could not read https://api.github.test/rate_limit'),
              contains('Cause (StateError): Bad state: '),
              endsWith('…'),
            ),
          ),
        ),
      );
    },
  );

  test('githubFailureCause renders the type first and caps the tail', () {
    final short = githubFailureCause(StateError('boom'));
    expect(short, 'Cause (StateError): Bad state: boom');

    final long = githubFailureCause(StateError('y' * 1000));
    expect(long, startsWith('Cause (StateError): Bad state: yyy'));
    expect(
      long.length,
      'Cause (StateError): '.length + kMaxGitHubCauseChars + 1,
      reason: 'the cap counts CHARACTERS and appends one ellipsis',
    );
  });
}

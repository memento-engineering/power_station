import 'dart:convert';
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

class FakeTokens implements GitHubAppTokenProvider {
  FakeTokens(this.values);
  final List<String> values;
  var calls = 0;

  @override
  Future<String> accessToken() async => values[calls++];
}

class FakeTransport implements GitHubHttpTransport {
  final requests = <GitHubHttpRequest>[];

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    return const GitHubHttpResponse(
      statusCode: 200,
      body: 'ok',
      headers: <String, String>{'etag': '"v1"'},
    );
  }
}

void main() {
  final config = GitHubAppConfig(
    appId: 'app',
    installationId: 1,
    apiBaseUri: Uri(scheme: 'https', host: 'github.example', path: '/api/v3'),
  );

  test(
    'requests a current token and applies exact REST request values',
    () async {
      final tokens = FakeTokens(<String>['first', 'second']);
      final transport = FakeTransport();
      final client = GitHubAppClient(
        config: config,
        tokens: tokens,
        transport: transport,
      );
      await client.send(
        method: 'POST',
        path: '/repos/org/repo/issues',
        headers: const <String, String>{'X-Custom': 'value'},
        jsonBody: <String, Object>{
          'title': 'hello',
          'labels': <String>['grid'],
        },
      );
      final response = await client.send(
        method: 'GET',
        path: '/user',
        queryParameters: const <String, String>{
          'since': '2026-08-09T12:00:00.000Z',
        },
      );

      expect(tokens.calls, 2);
      final request = transport.requests.first;
      expect(request.method, 'POST');
      expect(
        request.uri,
        Uri.parse('https://github.example/repos/org/repo/issues'),
      );
      expect(request.headers, <String, String>{
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer first',
        'X-GitHub-Api-Version': '2022-11-28',
        'X-Custom': 'value',
        'Content-Type': 'application/json; charset=utf-8',
      });
      expect(
        request.body,
        jsonEncode(<String, Object>{
          'title': 'hello',
          'labels': <String>['grid'],
        }),
      );
      expect(transport.requests.last.headers['Authorization'], 'Bearer second');
      expect(transport.requests.last.body, isNull);
      expect(
        transport.requests.last.uri.queryParameters['since'],
        '2026-08-09T12:00:00.000Z',
      );
      expect(response.header('ETag'), '"v1"');
    },
  );

  test(
    'relative path throws before requesting identity or transport',
    () async {
      final tokens = FakeTokens(<String>['unused']);
      final transport = FakeTransport();
      final client = GitHubAppClient(
        config: config,
        tokens: tokens,
        transport: transport,
      );
      await expectLater(
        client.send(method: 'GET', path: 'relative'),
        throwsArgumentError,
      );
      expect(tokens.calls, 0);
      expect(transport.requests, isEmpty);
    },
  );

  test('IoGitHubHttpTransport writes a non-Latin-1 body as UTF-8', () async {
    // Content-Type carries NO charset ON PURPOSE: that is the exact condition
    // under which dart:io resolves an HttpClientRequest's sink to iso-8859-1,
    // so this assertion FAILS on a `write`-based transport.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const body = '{"body":"a plan — with an em dash"}';
    late List<int> receivedBytes;
    late String receivedContentType;
    final serve = () async {
      final request = await server.first;
      receivedContentType = request.headers.value('content-type') ?? '';
      receivedBytes = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      request.response
        ..statusCode = HttpStatus.created
        ..write('{"ok":true}');
      await request.response.close();
    }();

    final response = await IoGitHubHttpTransport().send(
      GitHubHttpRequest(
        method: 'POST',
        uri: Uri.parse('http://${server.address.address}:${server.port}/pulls'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: body,
      ),
    );
    await serve;

    expect(receivedBytes, utf8.encode(body));
    expect(receivedContentType, 'application/json');
    expect(response.statusCode, HttpStatus.created);
  });
}

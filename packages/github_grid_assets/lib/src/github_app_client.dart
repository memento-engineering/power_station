import 'dart:convert';

import 'credentials.dart';
import 'http_transport.dart';
import 'token_provider.dart';

/// An authenticated GitHub REST client using installation identity.
class GitHubAppClient {
  /// Creates an authenticated client from injected identity components.
  const GitHubAppClient({
    required GitHubAppConfig config,
    required GitHubAppTokenProvider tokens,
    required GitHubHttpTransport transport,
  }) : _config = config,
       _tokens = tokens,
       _transport = transport;

  final GitHubAppConfig _config;
  final GitHubAppTokenProvider _tokens;
  final GitHubHttpTransport _transport;

  /// Sends an authenticated GitHub REST request to an absolute API [path].
  Future<GitHubHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
    Object? jsonBody,
  }) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'must start with /');
    }
    final token = await _tokens.accessToken();
    return _transport.send(
      GitHubHttpRequest(
        method: method,
        uri: _config.apiBaseUri.replace(
          path: path,
          queryParameters: queryParameters.isEmpty ? null : queryParameters,
        ),
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
          ...headers,
          if (jsonBody != null)
            'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonBody == null ? null : jsonEncode(jsonBody),
      ),
    );
  }
}

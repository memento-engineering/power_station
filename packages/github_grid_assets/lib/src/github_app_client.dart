import 'dart:convert';

import 'credentials.dart';
import 'http_transport.dart';
import 'token_provider.dart';

/// The REST headers EVERY GitHub request from this package carries.
///
/// One home for the contract so the installation lane and the token-less
/// foreign lane cannot drift: `Accept` selects the v3 JSON media type and
/// `X-GitHub-Api-Version` pins the REST version, and both are required of an
/// unauthenticated read exactly as they are of an installation one.
///
/// [token] is applied ONLY when it is nonblank. A foreign read has no
/// installation and usually no token at all, and an `Authorization: Bearer `
/// with nothing after it is not "no credential" to GitHub — it is a malformed
/// one, answered `401`. Omitting the header entirely is the honest request.
Map<String, String> githubRestHeaders({
  String? token,
  Map<String, String> headers = const <String, String>{},
  bool jsonBody = false,
}) => <String, String>{
  'Accept': 'application/vnd.github+json',
  if (token != null && token.trim().isNotEmpty)
    'Authorization': 'Bearer $token',
  'X-GitHub-Api-Version': '2022-11-28',
  ...headers,
  if (jsonBody) 'Content-Type': 'application/json; charset=utf-8',
};

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
        headers: githubRestHeaders(
          token: token,
          headers: headers,
          jsonBody: jsonBody != null,
        ),
        body: jsonBody == null ? null : jsonEncode(jsonBody),
      ),
    );
  }
}

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'credentials.dart';
import 'http_transport.dart';

/// Supplies the current time, allowing deterministic token lifecycle tests.
typedef GitHubClock = DateTime Function();

/// An installation access token and its GitHub-provided expiry.
class GitHubInstallationToken {
  /// Creates an installation access token.
  const GitHubInstallationToken({required this.value, required this.expiresAt});

  /// The bearer token value.
  final String value;

  /// The instant at which GitHub expires the token.
  final DateTime expiresAt;
}

/// Signs GitHub App JWTs and exchanges them for installation access tokens.
class GitHubAppTokenProvider {
  /// Creates a refreshing, in-memory installation token provider.
  GitHubAppTokenProvider({
    required GitHubAppConfig config,
    required GitHubAppPrivateKey privateKey,
    required GitHubHttpTransport transport,
    GitHubClock clock = utcNow,
  }) : _config = config,
       _privateKey = privateKey,
       _transport = transport,
       _clock = clock;

  static const _refreshSkew = Duration(minutes: 1);
  final GitHubAppConfig _config;
  final GitHubAppPrivateKey _privateKey;
  final GitHubHttpTransport _transport;
  final GitHubClock _clock;
  GitHubInstallationToken? _cached;
  Future<GitHubInstallationToken>? _refreshing;

  /// Returns a current token, coalescing and caching exchanges in memory.
  Future<String> accessToken() async {
    final cached = _cached;
    if (cached != null &&
        cached.expiresAt.isAfter(_clock().add(_refreshSkew))) {
      return cached.value;
    }
    final active = _refreshing;
    if (active != null) return (await active).value;
    final refresh = _exchange();
    _refreshing = refresh;
    try {
      final token = await refresh;
      _cached = token;
      return token.value;
    } finally {
      _refreshing = null;
    }
  }

  Future<GitHubInstallationToken> _exchange() async {
    final now = _clock().toUtc();
    int seconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;
    final jwt =
        JWT(<String, dynamic>{
          'iat': seconds(now.subtract(const Duration(seconds: 60))),
          'exp': seconds(now.add(const Duration(minutes: 10))),
          'iss': _config.appId,
        }).sign(
          RSAPrivateKey(_privateKey.pem),
          algorithm: JWTAlgorithm.RS256,
          noIssueAt: true,
        );
    final response = await _transport.send(
      GitHubHttpRequest(
        method: 'POST',
        uri: _config.apiBaseUri.replace(
          path: '/app/installations/${_config.installationId}/access_tokens',
        ),
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        body: '{}',
      ),
    );
    if (response.statusCode != 201) {
      throw StateError(
        'GitHub installation token exchange failed with status '
        '${response.statusCode}',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['token'] is! String) {
        throw const FormatException();
      }
      final expiresAt = DateTime.parse(decoded['expires_at'] as String).toUtc();
      return GitHubInstallationToken(
        value: decoded['token'] as String,
        expiresAt: expiresAt,
      );
    } on Object {
      throw StateError(
        'GitHub installation token exchange returned a malformed response',
      );
    }
  }
}

/// Returns the current UTC time.
DateTime utcNow() => DateTime.now().toUtc();

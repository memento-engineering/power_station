import 'http_transport.dart';
import 'github_app_client.dart';

/// The [GitHubPollCoordinator] key every FOREIGN read is scheduled under.
///
/// Its own key, never the installation's: the token-less allowance is 60
/// requests per hour and the installation's is thousands, so sharing a key
/// would let one lane spend the other's budget in either direction.
const String kForeignIssueWatchRateKey = 'foreign/issue-watch';

/// The floor between two TOKEN-LESS GitHub reads.
///
/// GitHub allows 60 unauthenticated requests per hour per source address.
/// Sixty seconds would spend exactly that allowance and leave nothing for a
/// retry, so the floor is 65 — about 55 requests an hour, a four-request
/// reserve. Any token raises the real allowance to 5000/hour, which is why the
/// floor is clamped ONLY for the token-less posture.
const Duration kUnauthenticatedGitHubMinimumSpacing = Duration(seconds: 65);

/// Schedules one foreign read and returns its response.
///
/// The seam the rate budget rides: the reconciler asks for a GET, and whatever
/// spaces starts decides WHEN it happens without the client knowing anything
/// about coordinators or keys.
typedef GitHubReadScheduler =
    Future<GitHubHttpResponse> Function(
      Future<GitHubHttpResponse> Function() request,
    );

/// A foreign read that could not be performed at all.
///
/// Distinct from a status: a `404` is an ANSWER the watch interprets, while
/// this is the transport failing to produce one. It escalates type-first with
/// its cause LAST through [githubFailureCause], exactly as App-authenticated
/// delivery does.
class GitHubReadException implements Exception {
  /// Creates a foreign-read failure for [uri] caused by [error].
  const GitHubReadException({required this.uri, required this.error});

  /// The request that could not be completed.
  final Uri uri;

  /// The underlying transport failure.
  final Object error;

  @override
  String toString() =>
      'Could not read $uri without a GitHub App installation. Verify network '
      'reachability and, if one is configured, the personal read token. '
      '${githubFailureCause(error)}';
}

/// A GET-only GitHub REST client that has NO installation.
///
/// A GitHub App — even acting on behalf of a user — is installation-scoped: it
/// can only reach resources in an account where it is installed, and we cannot
/// install ours on a third party's repository. So the outbound-issue watch's
/// foreign lane cannot use [GitHubAppClient] at all, whose `send` mints an
/// installation access token on EVERY request. This is its sibling: the same
/// [GitHubHttpTransport] seam, the same REST header contract, no token
/// provider, and no write verb to reach for — writing to a repository we do
/// not control is impossible for the App and out of scope by design.
class GitHubReadClient {
  /// Creates a read client over an injected transport.
  ///
  /// [personalToken] is an ALREADY-RESOLVED value, not a variable name: this
  /// class never reads the process environment. Blank or absent is the normal
  /// posture and sends no `Authorization` header at all.
  const GitHubReadClient({
    required GitHubHttpTransport transport,
    required Uri apiBaseUri,
    String? personalToken,
    GitHubReadScheduler? schedule,
  }) : _transport = transport,
       _apiBaseUri = apiBaseUri,
       _personalToken = personalToken,
       _schedule = schedule;

  final GitHubHttpTransport _transport;
  final Uri _apiBaseUri;
  final String? _personalToken;
  final GitHubReadScheduler? _schedule;

  /// Whether this client carries a personal token.
  ///
  /// The rate posture in one predicate: token-less reads live under a 60/hour
  /// allowance, a tokened read under 5000/hour.
  bool get isAuthenticated =>
      _personalToken != null && _personalToken.trim().isNotEmpty;

  /// GETs the absolute API [path], through the injected scheduler when there
  /// is one.
  ///
  /// A caller-supplied `If-None-Match` in [headers] is preserved: conditional
  /// reads are how a watch stays inside its allowance.
  Future<GitHubHttpResponse> get({
    required String path,
    Map<String, String> headers = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
  }) {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'must start with /');
    }
    final uri = _apiBaseUri.replace(
      path: path,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    Future<GitHubHttpResponse> send() async {
      try {
        return await _transport.send(
          GitHubHttpRequest(
            method: 'GET',
            uri: uri,
            headers: githubRestHeaders(token: _personalToken, headers: headers),
          ),
        );
      } on Object catch (error) {
        throw GitHubReadException(uri: uri, error: error);
      }
    }

    final schedule = _schedule;
    return schedule == null ? send() : schedule(send);
  }
}

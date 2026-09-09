import 'dart:convert';
import 'dart:io';

/// An HTTP request sent to the GitHub REST API.
class GitHubHttpRequest {
  /// Creates an HTTP request.
  const GitHubHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body,
  });

  /// The HTTP method.
  final String method;

  /// The complete request URI.
  final Uri uri;

  /// Request headers.
  final Map<String, String> headers;

  /// Optional request body.
  final String? body;
}

/// The relevant parts of an HTTP response from GitHub.
class GitHubHttpResponse {
  /// Creates an HTTP response.
  const GitHubHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  /// The HTTP response status code.
  final int statusCode;

  /// The UTF-8 decoded response body.
  final String body;

  /// Case-insensitive response headers, stored under lower-case names.
  final Map<String, String> headers;

  /// Returns the response header named [name], ignoring case.
  String? header(String name) => headers[name.toLowerCase()];
}

/// The character budget a rendered cause gets in [githubFailureCause].
///
/// A CHARACTER cap, never a first-line cap: an SDK error escapes newlines into
/// a literal backslash-n, so a `dart:convert` `ArgumentError` carrying a whole
/// JSON request renders as ONE multi-kilobyte line and a first-line cap would
/// be a no-op on exactly the failure that motivated this.
const int kMaxGitHubCauseChars = 300;

/// Renders [error] as the TYPE-LED, bounded cause every GitHub failure in this
/// package ends with.
///
/// Type FIRST and cause LAST because the reasons this renders into are passed
/// through tail-keeping truncators: rendering the raw error first meant the cut
/// kept whatever an SDK error had embedded — for an encoding failure, the whole
/// serialized request — and dropped the exception type and message.
///
/// The cause is `error.toString()` and deliberately NOT `Error.safeToString`,
/// which returns the DEFAULT `Object.toString` for anything that is not a
/// `num`, `bool`, `String` or null: every exception this renders would collapse
/// to `Instance of 'StateError'`, discarding the message that is the whole
/// payload — and making the cap meaningless.
String githubFailureCause(Object error) {
  final rendered = error.toString();
  final cause = rendered.length <= kMaxGitHubCauseChars
      ? rendered
      : '${rendered.substring(0, kMaxGitHubCauseChars)}…';
  return 'Cause (${error.runtimeType}): $cause';
}

/// Transport seam for GitHub REST API requests.
abstract interface class GitHubHttpTransport {
  /// Sends [request] and returns its response.
  Future<GitHubHttpResponse> send(GitHubHttpRequest request);
}

/// A `dart:io` implementation of [GitHubHttpTransport].
class IoGitHubHttpTransport implements GitHubHttpTransport {
  /// Sends one request using a short-lived [HttpClient].
  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    final client = HttpClient();
    try {
      final ioRequest = await client.openUrl(request.method, request.uri);
      request.headers.forEach(ioRequest.headers.set);
      // UTF-8 at the SINK, never `write`: an `HttpClientRequest`'s `IOSink`
      // encoding falls back to iso-8859-1 whenever `Content-Type` carries no
      // charset, and latin1 THROWS `ArgumentError.value(<the whole request>,
      // 'string', 'Contains invalid characters.')` on the first code unit
      // above U+00FF. Encoding HERE covers every caller — the `/pulls` POST
      // and the installation-token exchange alike; a header-side fix would
      // depend on each caller remembering the charset.
      if (request.body case final body?) ioRequest.add(utf8.encode(body));
      final response = await ioRequest.close();
      final headers = <String, String>{};
      response.headers.forEach(
        (name, values) => headers[name.toLowerCase()] = values.join(','),
      );
      return GitHubHttpResponse(
        statusCode: response.statusCode,
        body: await response.transform(utf8.decoder).join(),
        headers: Map.unmodifiable(headers),
      );
    } finally {
      client.close(force: true);
    }
  }
}

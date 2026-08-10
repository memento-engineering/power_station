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
      if (request.body case final body?) ioRequest.write(body);
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

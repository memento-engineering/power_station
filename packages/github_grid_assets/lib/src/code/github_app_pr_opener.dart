import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';

import '../github_app_client.dart';

/// Reads the origin URL for the checkout rooted at [workDir].
typedef GitRemoteReader = Future<String> Function(String workDir);

/// Opens — or REUSES — pull requests with a per-substation GitHub App identity.
///
/// [open] is the create-only [PrOpener] verb every opener implements.
/// [reuseOpen] is this opener's own, App-transport-only verb: it ASKS GitHub
/// for the branch's open pull request before anything is created, so a
/// reworked round delivers onto the PR round one left open instead of racing a
/// creation POST that GitHub refuses with HTTP 422.
class GitHubAppPrOpener implements PrOpener {
  /// Creates an opener. [owner] and [repository] are the preferred
  /// roster-supplied coordinates; when either is blank, [remoteReader]
  /// resolves both from the checkout's origin.
  GitHubAppPrOpener({
    required GitHubAppClient client,
    String? owner,
    String? repository,
    GitRemoteReader remoteReader = readOriginRemote,
  }) : _client = client,
       _owner = owner?.trim(),
       _repository = repository?.trim(),
       _remoteReader = remoteReader;

  final GitHubAppClient _client;
  final String? _owner;
  final String? _repository;
  final GitRemoteReader _remoteReader;

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    try {
      final (owner, repository) = await _repositoryCoordinates(workDir);
      final response = await _client.send(
        method: 'POST',
        path:
            '/repos/${Uri.encodeComponent(owner)}/'
            '${Uri.encodeComponent(repository)}/pulls',
        jsonBody: <String, Object>{
          'title': title,
          'body': body,
          'head': branch,
          'base': baseBranch,
        },
      );
      if (response.statusCode != HttpStatus.created) {
        return PullRequestResult.failed(
          PrOpenFailure(
            _failureReason(
              response.statusCode,
              response.body,
              owner,
              repository,
            ),
          ),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['html_url'] is! String ||
          decoded['number'] is! int) {
        return PullRequestResult.failed(
          const PrOpenFailure(
            'GitHub created the pull request but returned no usable '
            'html_url/number; inspect the repository on GitHub.',
          ),
        );
      }
      return PullRequestResult.opened(
        PullRequestRef(
          url: decoded['html_url'] as String,
          number: decoded['number'] as int,
        ),
      );
    } on Object catch (error) {
      return PullRequestResult.failed(
        PrOpenFailure(_thrownFailureReason(error)),
      );
    }
  }

  /// Finds the OPEN pull request for [branch] into [baseBranch] and refreshes
  /// its [title]/[body] from the fresh manifest, run from [workDir].
  ///
  /// Returns null ONLY when the filtered lookup came back empty — that is the
  /// single answer meaning "nothing to reuse, go create one". A non-null result
  /// is either the reusable pull request (opened) or a lookup/update refusal
  /// (failed), and a refusal must NEVER fall through to a creation POST: a GET
  /// or PATCH that GitHub refused says nothing about whether a PR exists.
  ///
  /// One GET (`?head=<owner>:<branch>&base=<base>`; the list endpoint defaults
  /// to open PRs) and, only when the title or body actually drifted, one PATCH.
  Future<PullRequestResult?> reuseOpen({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    required String body,
  }) async {
    try {
      final (owner, repository) = await _repositoryCoordinates(workDir);
      final path =
          '/repos/${Uri.encodeComponent(owner)}/'
          '${Uri.encodeComponent(repository)}/pulls';
      final listed = await _client.send(
        method: 'GET',
        path: path,
        queryParameters: <String, String>{
          'head': '$owner:$branch',
          'base': baseBranch,
        },
      );
      if (listed.statusCode != HttpStatus.ok) {
        return PullRequestResult.failed(
          PrOpenFailure(
            _reuseFailureReason(
              'open pull-request lookup',
              listed.statusCode,
              listed.body,
              owner,
              repository,
            ),
          ),
        );
      }
      final decoded = jsonDecode(listed.body);
      if (decoded is! List<dynamic>) {
        return PullRequestResult.failed(
          PrOpenFailure(
            'GitHub open-PR lookup for $owner/$repository returned a '
            'malformed response; inspect the repository on GitHub.',
          ),
        );
      }
      if (decoded.isEmpty) return null;
      final pull = decoded.first;
      if (pull is! Map<String, dynamic> ||
          pull['html_url'] is! String ||
          pull['number'] is! int ||
          pull['title'] is! String ||
          (pull['body'] != null && pull['body'] is! String)) {
        return PullRequestResult.failed(
          PrOpenFailure(
            'GitHub open-PR lookup for $owner/$repository returned no usable '
            'html_url/number/title/body; inspect the repository on GitHub.',
          ),
        );
      }
      final ref = PullRequestRef(
        url: pull['html_url'] as String,
        number: pull['number'] as int,
      );
      final existingBody = (pull['body'] as String?) ?? '';
      if (pull['title'] != title || existingBody != body) {
        final updated = await _client.send(
          method: 'PATCH',
          path: '$path/${ref.number}',
          jsonBody: <String, Object>{'title': title, 'body': body},
        );
        if (updated.statusCode != HttpStatus.ok) {
          return PullRequestResult.failed(
            PrOpenFailure(
              _reuseFailureReason(
                'pull-request update',
                updated.statusCode,
                updated.body,
                owner,
                repository,
              ),
            ),
          );
        }
      }
      return PullRequestResult.opened(ref);
    } on Object catch (error) {
      return PullRequestResult.failed(
        PrOpenFailure(_thrownFailureReason(error)),
      );
    }
  }

  /// The roster-supplied coordinates when both are configured, else the pair
  /// parsed from the checkout's origin — one resolver for GET, PATCH and POST.
  Future<(String, String)> _repositoryCoordinates(String workDir) async {
    final configuredOwner = _owner;
    final configuredRepository = _repository;
    return configuredOwner != null &&
            configuredOwner.isNotEmpty &&
            configuredRepository != null &&
            configuredRepository.isNotEmpty
        ? (configuredOwner, configuredRepository)
        : parseGitHubRemote(await _remoteReader(workDir));
  }
}

/// Reads `remote.origin.url` without consulting `gh` or its credentials.
Future<String> readOriginRemote(String workDir) async {
  final result = await Process.run('git', const <String>[
    'config',
    '--get',
    'remote.origin.url',
  ], workingDirectory: workDir);
  if (result.exitCode != 0) {
    throw StateError(
      'git could not read remote.origin.url in $workDir: '
      '${result.stderr.toString().trim()}',
    );
  }
  final value = result.stdout.toString().trim();
  if (value.isEmpty) {
    throw StateError('origin has no URL in $workDir');
  }
  return value;
}

/// Parses `git@host:owner/repo.git`, `ssh://git@host/owner/repo.git`, or
/// `https://host/owner/repo.git` into GitHub repository coordinates.
(String, String) parseGitHubRemote(String remote) {
  final value = remote.trim();
  final scp = RegExp(
    r'^[^@/]+@[^:]+:([^/]+)/(.+?)(?:\.git)?$',
  ).firstMatch(value);
  final segments = scp == null
      ? Uri.tryParse(
          value,
        )?.pathSegments.where((part) => part.isNotEmpty).toList()
      : <String>[scp.group(1)!, scp.group(2)!];
  if (segments == null || segments.length != 2) {
    throw FormatException(
      'cannot derive owner/repository from origin URL: $remote',
    );
  }
  final owner = segments[0];
  final repository = segments[1].replaceFirst(RegExp(r'\.git$'), '');
  if (owner.isEmpty || repository.isEmpty) {
    throw FormatException(
      'cannot derive owner/repository from origin URL: $remote',
    );
  }
  return (owner, repository);
}

/// GitHub's `message` field when the response body carries one, else the raw
/// response text — the detail every refusal reason quotes.
String _responseDetail(String body) {
  String detail = body.trim();
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded['message'] is String) {
      detail = decoded['message'] as String;
    }
  } on FormatException {
    // Retain the raw response text.
  }
  return detail;
}

/// The reason a REUSE leg — the open-PR lookup or the title/body update — was
/// refused by status. Named by [operation] so an operator reads WHICH call
/// GitHub turned down, never the creation POST this one preceded.
String _reuseFailureReason(
  String operation,
  int status,
  String body,
  String owner,
  String repository,
) {
  final detail = _responseDetail(body);
  return 'GitHub refused $operation for $owner/$repository '
      '(HTTP $status${detail.isEmpty ? '' : ': $detail'}). '
      'Inspect GitHub and retry after correcting the reported condition.';
}

String _failureReason(
  int status,
  String body,
  String owner,
  String repository,
) {
  final detail = _responseDetail(body);
  final action = switch (status) {
    401 =>
      'Check the App credentials: App ID, private key, and installation token.',
    403 => 'Check pull-request permission and the GitHub rate-limit headers.',
    404 =>
      'Install the App for $owner/$repository and verify the repository '
          'coordinates.',
    422 =>
      'A pull request may already exist for this branch; inspect open PRs and '
          'the head/base values.',
    429 => 'GitHub rate-limited the App; wait for the reset and retry.',
    _ => 'Inspect GitHub and retry after correcting the reported condition.',
  };
  return 'GitHub refused PR creation for $owner/$repository '
      '(HTTP $status${detail.isEmpty ? '' : ': $detail'}). $action';
}

/// The character budget a rendered cause gets in [_thrownFailureReason].
///
/// A CHARACTER cap, never a first-line cap: `Error.safeToString` escapes
/// newlines into a literal backslash-n, so a `dart:convert` `ArgumentError`
/// carrying a whole JSON request renders as ONE multi-kilobyte line and a
/// first-line cap would be a no-op on exactly the failure that motivated this.
const int _maxCauseChars = 300;

/// The reason a THROWN error — transport, git remote read, or remote parse —
/// escalates with: generic advice FIRST, cause LAST, type-led.
///
/// The delivery step passes this reason through `landReasonTail`, which keeps
/// the TAIL of a string. Rendering `$error` FIRST meant the cut kept whatever
/// an SDK error had embedded — for an encoding failure, the whole serialized
/// request — and dropped the exception type and message; putting the cause
/// last inverts that.
String _thrownFailureReason(Object error) {
  final rendered = error.toString();
  final cause = rendered.length <= _maxCauseChars
      ? rendered
      : '${rendered.substring(0, _maxCauseChars)}…';
  return 'Could not open the pull request with the GitHub App. Verify the '
      'checkout origin, App installation, credentials, and network, then '
      'retry. Cause (${error.runtimeType}): $cause';
}

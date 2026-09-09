import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';

/// The seat these fixtures speak for — the repository the App IS installed on.
const String kSeatOwner = 'memento';

/// The seat's repository name.
const String kSeatRepository = 'power_station';

/// The seat's substation identity.
const String kSubstation = 'power_station';

/// The one human login the seat's trust admits as SELF.
const String kSelfLogin = 'nico';

/// The live instance this feature was filed for: the pub-workspace containment
/// issue the refiner seat filed on Nico's ruling, in a repository we do NOT
/// control.
const GitHubIssueWatch kForeignWatch = GitHubIssueWatch(
  originatingBeadId: 'lunar_station-6p9',
  owner: 'ricardoboss',
  repository: 'radioactive_dart',
  issueNumber: 1,
);

/// The same shape, but on the seat's OWN repository — the installed lane.
const GitHubIssueWatch kInstalledWatch = GitHubIssueWatch(
  originatingBeadId: 'pow-1rn',
  owner: kSeatOwner,
  repository: kSeatRepository,
  issueNumber: 1,
);

/// A transport that answers by request PATH and records every request.
///
/// A Fake, not a mock: it holds queued responses and the requests it was asked
/// for, and a path with nothing queued THROWS rather than inventing an answer.
final class RouteTransport implements GitHubHttpTransport {
  /// Every request this transport was asked to send, in order.
  final List<GitHubHttpRequest> requests = <GitHubHttpRequest>[];
  final Map<String, List<GitHubHttpResponse>> _routes =
      <String, List<GitHubHttpResponse>>{};

  /// Queues [response] for [path]; the LAST queued response repeats.
  void on(String path, GitHubHttpResponse response) =>
      _routes.putIfAbsent(path, () => <GitHubHttpResponse>[]).add(response);

  /// The paths this transport was asked for, in order.
  List<String> get paths => <String>[
    for (final request in requests) request.uri.path,
  ];

  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    requests.add(request);
    final queued = _routes[request.uri.path];
    if (queued == null || queued.isEmpty) {
      throw StateError('no response queued for ${request.uri}');
    }
    return queued.length == 1 ? queued.first : queued.removeAt(0);
  }
}

/// An in-memory [GitHubCursorStore] that records every saved document.
final class MemoryCursorStore implements GitHubCursorStore {
  /// Creates a store seeded with [cursor].
  MemoryCursorStore([this.cursor = const GitHubReconcilerCursor()]);

  /// The current document.
  GitHubReconcilerCursor cursor;

  /// How many times [save] was called.
  int saves = 0;

  @override
  Future<GitHubReconcilerCursor> load() async => cursor;

  @override
  Future<void> save(GitHubReconcilerCursor value) async {
    saves++;
    cursor = value;
  }
}

/// A [BdRunner] that records argv and answers a well-formed envelope.
final class RecordingBdRunner implements BdRunner {
  /// Every argv this runner was asked to execute, in order.
  final List<List<String>> argvs = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    final data = args.first == 'list'
        ? <Object?>[]
        : <String, Object?>{'id': args.length > 1 ? args[1] : 'bead'};
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode(<String, Object?>{'schema_version': 1, 'data': data}),
      stderr: '',
    );
  }
}

/// An [GitHubIntakeStore] Fake that records the watch updates it is given.
final class RecordingIntakeStore implements GitHubIntakeStore {
  /// Every intake record upserted.
  final List<GitHubIntakeRecord> records = <GitHubIntakeRecord>[];

  /// Every watch update appended.
  final List<GitHubIssueWatchUpdate> watchUpdates = <GitHubIssueWatchUpdate>[];

  @override
  Future<void> upsert(GitHubIntakeRecord record) async => records.add(record);

  @override
  Future<void> appendIssueWatch(GitHubIssueWatchUpdate update) async =>
      watchUpdates.add(update);
}

/// One JSON response.
GitHubHttpResponse jsonResponse(
  Object body, {
  int status = 200,
  String? etag,
  String? link,
}) => GitHubHttpResponse(
  statusCode: status,
  body: body is String ? body : jsonEncode(body),
  headers: <String, String>{
    if (etag != null) 'etag': etag,
    if (link != null) 'link': link,
  },
);

/// One `/issues/{number}` resource.
Map<String, Object?> issueBody({
  String nodeId = 'I_kwDO',
  String author = kSelfLogin,
  String state = 'open',
  String? stateReason,
  bool locked = false,
  String updatedAt = '2026-09-09T10:00:00Z',
  String? closedBy,
  String url = 'https://github.com/ricardoboss/radioactive_dart/issues/1',
}) => <String, Object?>{
  'node_id': nodeId,
  'number': 1,
  'user': <String, Object?>{'login': author},
  'state': state,
  'state_reason': stateReason,
  'locked': locked,
  'updated_at': updatedAt,
  'html_url': url,
  'closed_by': closedBy == null ? null : <String, Object?>{'login': closedBy},
};

/// One `commented` timeline row.
Map<String, Object?> commentRow({
  required int id,
  required String nodeId,
  required String actor,
  required String body,
  String createdAt = '2026-09-09T11:00:00Z',
  String? updatedAt,
  String url =
      'https://github.com/ricardoboss/radioactive_dart/issues/1#issuecomment-1',
}) => <String, Object?>{
  'event': 'commented',
  'id': id,
  'node_id': nodeId,
  'user': <String, Object?>{'login': actor},
  'body': body,
  'created_at': createdAt,
  'updated_at': updatedAt ?? createdAt,
  'html_url': url,
};

/// One non-comment timeline row.
Map<String, Object?> eventRow({
  required String event,
  required int id,
  required String nodeId,
  String? actor = 'ricardoboss',
  String createdAt = '2026-09-09T12:00:00Z',
  String? stateReason,
}) => <String, Object?>{
  'event': event,
  'id': id,
  'node_id': nodeId,
  if (actor != null) 'actor': <String, Object?>{'login': actor},
  'created_at': createdAt,
  if (stateReason != null) 'state_reason': stateReason,
};

/// The `/repos/{owner}/{repository}/issues/{number}` path of [watch].
String issuePath(GitHubIssueWatch watch) =>
    '/repos/${watch.owner}/${watch.repository}/issues/${watch.issueNumber}';

/// The timeline path of [watch].
String timelinePath(GitHubIssueWatch watch) => '${issuePath(watch)}/timeline';

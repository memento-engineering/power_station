import 'dart:convert';

import 'package:github_grid_assets/github_grid_assets.dart';

import 'reconciler_cursor.dart';
import 'reconciler_event.dart';

/// Receives one normalized observation.
typedef GitHubEventSink = Future<void> Function(NormalizedGitHubEvent event);

/// A failed conditional GitHub polling request.
class GitHubPollException implements Exception {
  /// Creates a polling failure.
  const GitHubPollException({required this.endpoint, required this.statusCode});

  /// Stable cursor endpoint key.
  final String endpoint;

  /// Response status.
  final int statusCode;

  @override
  String toString() => 'GitHubPollException($endpoint, status $statusCode)';
}

/// Polls one repository for one substation and emits normalized observations.
///
/// This in-process implementation is transport-neutral at its output and owns
/// no bead projection. Trust/intake and feedback/landing remain sibling-owned;
/// a webhook transport can later feed the same normalized event seam.
class GitHubReconciler {
  /// Creates a per-seat reconciler.
  GitHubReconciler({
    required this.owner,
    required this.repository,
    required this.substation,
    required GitHubAppClient client,
    required GitHubCursorStore cursors,
    required GitHubEventSink emit,
    DateTime Function()? now,
  }) : _client = client,
       _cursors = cursors,
       _emit = emit,
       _now = now ?? DateTime.now;

  /// Repository owner.
  final String owner;

  /// Repository name.
  final String repository;

  /// Bound substation name.
  final String substation;
  final GitHubAppClient _client;
  final GitHubCursorStore _cursors;
  final GitHubEventSink _emit;
  final DateTime Function() _now;
  Future<void>? _inFlight;

  /// Runs one coalesced intake-then-feedback reconciliation.
  Future<void> reconcileOnce() =>
      _inFlight ??= _reconcile().whenComplete(() => _inFlight = null);

  Future<void> _reconcile() async {
    var cursor = await _cursors.load();
    cursor = await _intake(cursor);
    await _feedback(cursor);
  }

  Future<GitHubReconcilerCursor> _intake(GitHubReconcilerCursor cursor) async {
    const key = 'intake/issues';
    final pollStartedAt = _now().toUtc();
    final response = await _client.send(
      method: 'GET',
      path: '/repos/$owner/$repository/issues',
      queryParameters: <String, String>{
        'state': 'all',
        'sort': 'updated',
        'direction': 'asc',
        'per_page': '100',
        if (cursor.since case final since?)
          'since': since.toUtc().toIso8601String(),
      },
      headers: <String, String>{
        if (cursor.etags[key] case final etag?) 'If-None-Match': etag,
      },
    );
    if (response.statusCode == 304) return cursor;
    _requireSuccess(key, response.statusCode);
    final rows = _list(response.body, key);
    final events = <NormalizedGitHubEvent>[];
    var latest = cursor.since?.toUtc();
    for (final raw in rows) {
      final row = _map(raw, 'row');
      final nodeId = _string(row, 'node_id');
      final updatedText = _string(row, 'updated_at');
      final updated = _date(updatedText, 'updated_at');
      final number = _integer(row, 'number');
      final title = _string(row, 'title');
      final body = _nullableString(row, 'body') ?? '';
      final actor = _string(_nestedMap(row, 'user'), 'login', prefix: 'user');
      final observationId = 'poll:issue:$nodeId:$updatedText';
      if (row.containsKey('pull_request')) {
        final head = _nestedMap(row, 'head');
        events.add(
          NormalizedGitHubEvent.pullRequestOpened(
            nodeId: nodeId,
            actor: actor,
            repository: '$owner/$repository',
            substation: substation,
            observationId: observationId,
            number: number,
            title: title,
            body: body,
            headBranch: _string(head, 'ref', prefix: 'head'),
          ),
        );
      } else {
        events.add(
          NormalizedGitHubEvent.issueOpened(
            nodeId: nodeId,
            actor: actor,
            repository: '$owner/$repository',
            substation: substation,
            observationId: observationId,
            number: number,
            title: title,
            body: body,
          ),
        );
      }
      if (latest == null || updated.isAfter(latest)) latest = updated;
    }
    cursor = await _deliver(cursor, events);
    if (latest == null || pollStartedAt.isAfter(latest)) latest = pollStartedAt;
    final etag = response.header('etag');
    final etags = <String, String>{...cursor.etags};
    if (etag != null) etags[key] = etag;
    final next = cursor.copyWith(since: latest, etags: etags);
    await _cursors.save(next);
    return next;
  }

  Future<GitHubReconcilerCursor> _feedback(
    GitHubReconcilerCursor cursor,
  ) async {
    const pullsKey = 'feedback/pulls';
    final pullsResponse = await _client.send(
      method: 'GET',
      path: '/repos/$owner/$repository/pulls',
      queryParameters: const <String, String>{
        'state': 'open',
        'per_page': '100',
      },
      headers: <String, String>{
        if (cursor.etags[pullsKey] case final etag?) 'If-None-Match': etag,
      },
    );
    if (pullsResponse.statusCode == 304) return cursor;
    _requireSuccess(pullsKey, pullsResponse.statusCode);
    final pulls = _list(pullsResponse.body, pullsKey);
    var next = cursor;
    for (final raw in pulls) {
      final pull = _map(raw, 'pull');
      final pullNodeId = _string(pull, 'node_id');
      final head = _nestedMap(pull, 'head');
      final branch = _string(head, 'ref', prefix: 'head');
      final sha = _string(head, 'sha', prefix: 'head');
      if (!branch.startsWith('grid/')) continue;
      final checksKey = 'feedback/checks/$pullNodeId';
      final checksResponse = await _client.send(
        method: 'GET',
        path:
            '/repos/$owner/$repository/commits/${Uri.encodeComponent(sha)}/check-runs',
        queryParameters: const <String, String>{'per_page': '100'},
        headers: <String, String>{
          if (next.etags[checksKey] case final etag?) 'If-None-Match': etag,
        },
      );
      if (checksResponse.statusCode == 304) continue;
      _requireSuccess(checksKey, checksResponse.statusCode);
      final decoded = _decoded(checksResponse.body, checksKey);
      final checkMap = _map(decoded, checksKey);
      final checkRuns = checkMap['check_runs'];
      if (checkRuns is! List) {
        throw const FormatException('check_runs must be a list');
      }
      final events = <NormalizedGitHubEvent>[];
      for (final checkRaw in checkRuns) {
        final check = _map(checkRaw, 'check_run');
        final status = _string(check, 'status');
        if (status != 'completed') continue;
        final conclusion = _string(check, 'conclusion');
        final nodeId = _string(check, 'node_id');
        final completedAt = _string(check, 'completed_at');
        _date(completedAt, 'completed_at');
        events.add(
          NormalizedGitHubEvent.checkConcluded(
            nodeId: nodeId,
            actor: _string(_nestedMap(check, 'app'), 'slug', prefix: 'app'),
            repository: '$owner/$repository',
            substation: substation,
            observationId: 'poll:check:$nodeId:$completedAt:$conclusion',
            headBranch: branch,
            checkName: _string(check, 'name'),
            conclusion: conclusion,
          ),
        );
      }
      next = await _deliver(next, events);
      if (checksResponse.header('etag') case final etag?) {
        next = next.copyWith(
          etags: <String, String>{...next.etags, checksKey: etag},
        );
        await _cursors.save(next);
      }
    }
    if (pullsResponse.header('etag') case final etag?) {
      next = next.copyWith(
        etags: <String, String>{...next.etags, pullsKey: etag},
      );
      await _cursors.save(next);
    }
    return next;
  }

  Future<GitHubReconcilerCursor> _deliver(
    GitHubReconcilerCursor cursor,
    Iterable<NormalizedGitHubEvent> events,
  ) async {
    var next = cursor;
    for (final event in events) {
      final id = switch (event) {
        IssueOpened(:final observationId) => observationId,
        PullRequestOpened(:final observationId) => observationId,
        CheckConcluded(:final observationId) => observationId,
      };
      if (next.hasObserved(id)) continue;
      next = next.record(id);
      await _cursors.save(next);
      await _emit(event);
    }
    return next;
  }
}

void _requireSuccess(String endpoint, int status) {
  if (status != 200) {
    throw GitHubPollException(endpoint: endpoint, statusCode: status);
  }
}

Object? _decoded(String body, String endpoint) {
  try {
    return jsonDecode(body);
  } on FormatException catch (error) {
    throw FormatException('$endpoint contains malformed JSON', error);
  }
}

List<Object?> _list(String body, String endpoint) {
  final value = _decoded(body, endpoint);
  if (value is! List) throw FormatException('$endpoint must be a list');
  return value.cast<Object?>();
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be a map');
  try {
    return Map<String, Object?>.from(value);
  } catch (error) {
    throw FormatException('$field must have string keys', error);
  }
}

Map<String, Object?> _nestedMap(Map<String, Object?> map, String field) =>
    _map(map[field], field);

String _string(Map<String, Object?> map, String field, {String? prefix}) {
  final value = map[field];
  if (value is! String) {
    throw FormatException(
      '${prefix == null ? '' : '$prefix.'}$field must be a string',
    );
  }
  return value;
}

String? _nullableString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$field must be a string or null');
  }
  return value;
}

int _integer(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! int) throw FormatException('$field must be an integer');
  return value;
}

DateTime _date(String value, String field) {
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException catch (error) {
    throw FormatException('$field must be a timestamp', error);
  }
}

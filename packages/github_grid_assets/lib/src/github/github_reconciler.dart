import 'dart:convert';
import 'dart:developer' as developer;

import '../github_app_client.dart';

import 'link_header.dart';
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
    void Function(Object error, StackTrace stackTrace)? onIntakeRowError,
  }) : _client = client,
       _cursors = cursors,
       _emit = emit,
       _onIntakeRowError = onIntakeRowError;

  /// Repository owner.
  final String owner;

  /// Repository name.
  final String repository;

  /// Bound substation name.
  final String substation;
  final GitHubAppClient _client;
  final GitHubCursorStore _cursors;
  final GitHubEventSink _emit;
  final void Function(Object error, StackTrace stackTrace)? _onIntakeRowError;
  final List<GitHubEventSink> _observers = <GitHubEventSink>[];
  Future<void>? _inFlight;

  /// Adds a sibling projection to the normalized event seam.
  void addObserver(GitHubEventSink observer) => _observers.add(observer);

  /// Removes a previously added sibling projection.
  void removeObserver(GitHubEventSink observer) => _observers.remove(observer);

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
    var response = await _client.send(
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
    final firstPageEtag = response.header('etag');
    var latest = cursor.since?.toUtc();
    while (true) {
      final page = await _intakePage(cursor, _list(response.body, key), latest);
      cursor = page.cursor;
      latest = page.latest;
      final nextPage = nextGitHubPageUri(response.header('link'));
      if (nextPage == null) break;
      response = await _client.send(
        method: 'GET',
        path: nextPage.path,
        queryParameters: nextPage.queryParameters,
      );
      _requireSuccess(key, response.statusCode);
    }
    final etags = <String, String>{...cursor.etags};
    if (firstPageEtag != null) etags[key] = firstPageEtag;
    final next = cursor.copyWith(since: latest, etags: etags);
    await _cursors.save(next);
    return next;
  }

  /// Examines one page of issues rows, delivering its events and returning the
  /// cursor plus the newest `updated_at` seen so far.
  Future<({GitHubReconcilerCursor cursor, DateTime? latest})> _intakePage(
    GitHubReconcilerCursor cursor,
    List<Object?> rows,
    DateTime? latest,
  ) async {
    var next = cursor;
    var mark = latest;
    final events = <NormalizedGitHubEvent>[];
    for (final raw in rows) {
      try {
        final row = _map(raw, 'row');
        final nodeId = _string(row, 'node_id');
        final updatedText = _string(row, 'updated_at');
        final updated = _date(updatedText, 'updated_at');
        if (mark == null || updated.isAfter(mark)) mark = updated;
        final observationId = 'poll:issue:$nodeId:$updatedText';
        final state = _string(row, 'state');
        if (state != 'open') {
          next = next.record(observationId);
          continue;
        }
        final number = _integer(row, 'number');
        final title = _string(row, 'title');
        final body = _nullableString(row, 'body') ?? '';
        final actor = _string(_nestedMap(row, 'user'), 'login', prefix: 'user');
        if (row.containsKey('pull_request')) {
          final head = await _pullHead(next, nodeId, number);
          next = head.cursor;
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
              headRef: head.headRef,
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
      } on FormatException catch (error, stackTrace) {
        _reportIntakeRowError(error, stackTrace);
      }
    }
    return (cursor: await _deliver(next, events), latest: mark);
  }

  /// Resolves pull [number]'s head ref from its full resource.
  ///
  /// The issues row for a pull request carries no `head`, so the feedback path
  /// cannot get the branch from it. The request is conditional only when a ref
  /// is already cached, so an unchanged pull costs one `304` and reuses the
  /// cache; a `304` with no cache is therefore unreachable, and if the server
  /// produced one anyway it fails LOUDLY as a [GitHubPollException].
  Future<({GitHubReconcilerCursor cursor, String headRef})> _pullHead(
    GitHubReconcilerCursor cursor,
    String nodeId,
    int number,
  ) async {
    final key = GitHubReconcilerCursor.pullEtagKey(nodeId);
    final cached = cursor.pullHeads[nodeId];
    final conditional = cached == null ? null : cursor.etags[key];
    final response = await _client.send(
      method: 'GET',
      path: '/repos/$owner/$repository/pulls/$number',
      headers: <String, String>{
        if (conditional case final etag?) 'If-None-Match': etag,
      },
    );
    if (response.statusCode == 304 && cached != null) {
      return (cursor: cursor, headRef: cached);
    }
    _requireSuccess(key, response.statusCode);
    final pull = _map(_decoded(response.body, key), key);
    final headRef = _string(_nestedMap(pull, 'head'), 'ref', prefix: 'head');
    return (
      cursor: cursor.recordPullHead(
        nodeId,
        headRef,
        etag: response.header('etag'),
      ),
      headRef: headRef,
    );
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
      for (final observer in List<GitHubEventSink>.of(_observers)) {
        await observer(event);
      }
    }
    return next;
  }

  void _reportIntakeRowError(Object error, StackTrace stackTrace) {
    final observer = _onIntakeRowError;
    if (observer != null) {
      try {
        observer(error, stackTrace);
        return;
      } on Object catch (observerError, observerStackTrace) {
        developer.log(
          'GitHub reconciler intake-row reporter failed for '
          'seat=$substation repository=$owner/$repository; '
          'original error: $error',
          name: 'github_grid_assets.reconciler',
          error: observerError,
          stackTrace: observerStackTrace,
        );
        return;
      }
    }
    developer.log(
      'GitHub reconciler skipped malformed intake row for '
      'seat=$substation repository=$owner/$repository: $error',
      name: 'github_grid_assets.reconciler',
      error: error,
      stackTrace: stackTrace,
    );
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

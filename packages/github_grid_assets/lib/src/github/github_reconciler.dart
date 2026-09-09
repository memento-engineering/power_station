import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../code/workflow_run_intake_rule.dart';
import '../github_app_client.dart';
import '../github_read_client.dart';
import '../http_transport.dart';

import 'issue_watch.dart';
import 'link_header.dart';
import 'reconciler_cursor.dart';
import 'reconciler_event.dart';

/// Receives one normalized observation.
typedef GitHubEventSink = Future<void> Function(NormalizedGitHubEvent event);

/// The reserved delivery-leg name for the reconciler's own [GitHubEventSink].
const String kSinkDeliveryLeg = 'sink';

/// One named delivery leg: an observer plus its durable acknowledgement key.
class _DeliveryLeg {
  const _DeliveryLeg(this.leg, this.sink);

  final String leg;
  final GitHubEventSink sink;
}

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
    this.defaultBranch = 'main',
    this.workflowRuns = const <WorkflowRunIntakeRule>[],
    this.issueWatches = const <GitHubIssueWatch>[],
    GitHubReadClient? foreignClient,
    void Function(Object error, StackTrace stackTrace)? onIntakeRowError,
  }) : _client = client,
       _foreign = foreignClient,
       _cursors = cursors,
       _emit = emit,
       _onIntakeRowError = onIntakeRowError {
    for (final watch in issueWatches) {
      watch.validate();
      if (watch.isInstalledRepository(owner: owner, repository: repository)) {
        _installedWatches.add(watch);
      } else {
        _foreignWatches.add(watch);
      }
    }
    // A foreign watch with no read client is a WIRING bug: the App client
    // cannot serve it — its every request mints an installation token, and
    // there is no installation on a repository we do not control — so the
    // watch would silently never be polled.
    if (_foreignWatches.isNotEmpty && foreignClient == null) {
      throw ArgumentError.value(
        issueWatches,
        'issueWatches',
        'a watch outside $owner/$repository needs a foreignClient',
      );
    }
  }

  /// Repository owner.
  final String owner;

  /// Repository name.
  final String repository;

  /// Bound substation name.
  final String substation;

  /// The repository's default branch — what a rule that declares no branches
  /// resolves to.
  final String defaultBranch;

  /// The seat's declared workflow-run rules, in authoritative order.
  ///
  /// EMPTY is the feature-off value and the default: [_runs] returns before
  /// any transport, so a seat that has not opted in spends no request and no
  /// rate-limit unit on this leg.
  final List<WorkflowRunIntakeRule> workflowRuns;

  /// The seat's declared OUTBOUND issue watches, in authoritative order.
  ///
  /// EMPTY is the feature-off value and the default: both watch legs return
  /// before any transport, so a seat that has not opted in spends no request
  /// and no rate-limit unit on them.
  final List<GitHubIssueWatch> issueWatches;
  final GitHubAppClient _client;
  final GitHubReadClient? _foreign;
  final List<GitHubIssueWatch> _installedWatches = <GitHubIssueWatch>[];
  final List<GitHubIssueWatch> _foreignWatches = <GitHubIssueWatch>[];
  final GitHubCursorStore _cursors;
  final GitHubEventSink _emit;
  final void Function(Object error, StackTrace stackTrace)? _onIntakeRowError;
  final List<_DeliveryLeg> _observers = <_DeliveryLeg>[];
  Future<void>? _inFlight;
  Future<void> _cursorTail = Future<void>.value();

  /// Adds a sibling projection to the normalized event seam under [leg].
  ///
  /// [leg] is the DURABLE acknowledgement key for this observer: the outbox
  /// records it against the pending entry once the observer returns, so a replay
  /// never re-drives a leg that already succeeded. A duplicate name, or the
  /// reserved [kSinkDeliveryLeg], is refused LOUDLY — either would silently make
  /// two legs share one acknowledgement, which is exactly the lost effect this
  /// outbox exists to prevent.
  void addObserver(String leg, GitHubEventSink observer) {
    if (leg == kSinkDeliveryLeg) {
      throw ArgumentError.value(leg, 'leg', 'reserved for the reconciler sink');
    }
    if (_observers.any((entry) => entry.leg == leg)) {
      throw ArgumentError.value(leg, 'leg', 'delivery leg already registered');
    }
    _observers.add(_DeliveryLeg(leg, observer));
  }

  /// Removes the observer registered under [leg].
  void removeObserver(String leg) =>
      _observers.removeWhere((entry) => entry.leg == leg);

  /// Runs one coalesced intake-then-feedback reconciliation.
  Future<void> reconcileOnce() =>
      _inFlight ??= _serialize(_reconcile).whenComplete(() => _inFlight = null);

  /// Runs the FOREIGN issue-watch leg on its own, touching no App client.
  ///
  /// The lane split made observable: a caller that only wants the token-less
  /// half — because that is the half with its own 60-per-hour budget — gets it
  /// without spending an installation request. It shares the SAME cursor
  /// operation tail as [reconcileOnce], so the two entrypoints can never
  /// interleave two read-modify-write cycles over one cursor document.
  Future<void> reconcileForeignIssueWatchesOnce() =>
      _serialize(_reconcileForeignIssueWatches);

  /// Runs [body] behind every cursor operation already queued.
  ///
  /// The tail deliberately never carries a failure forward: a cycle that threw
  /// has already left the cursor at its last saved value, and poisoning the
  /// tail would stop every later cycle for a failure they had no part in.
  Future<void> _serialize(Future<void> Function() body) {
    final prior = _cursorTail;
    final released = Completer<void>();
    _cursorTail = released.future;
    return prior.then((_) => body()).whenComplete(released.complete);
  }

  Future<void> _reconcile() async {
    var cursor = await _cursors.load();
    cursor = await _replayPending(cursor);
    cursor = await _intake(cursor);
    cursor = await _feedback(cursor);
    cursor = await _runs(cursor);
    cursor = await _pruneIssueWatches(cursor);
    cursor = await _issueWatchLeg(cursor, _installedWatches, foreign: false);
    await _issueWatchLeg(cursor, _foreignWatches, foreign: true);
  }

  Future<void> _reconcileForeignIssueWatches() async {
    var cursor = await _cursors.load();
    cursor = await _replayPending(cursor);
    await _issueWatchLeg(cursor, _foreignWatches, foreign: true);
  }

  /// Re-delivers every PENDING observation, oldest first, before new polling.
  ///
  /// This runs INSIDE [reconcileOnce], so it shares the poll's coordinator
  /// installation quota slot instead of queueing a second one, and the first
  /// cycle after a process restart IS the startup replay. A throw propagates:
  /// the cycle fails loudly, the runtime's failure observer flares it, the poll
  /// does not advance, and the observation stays PENDING for the next cycle.
  /// That head-of-line block is deliberate — skipping a stuck leg would restore
  /// the silent loss this queue removes.
  Future<GitHubReconcilerCursor> _replayPending(
    GitHubReconcilerCursor cursor,
  ) async {
    var next = cursor;
    for (final entry in List<PendingObservation>.of(cursor.pending)) {
      next = await _dispatch(next, entry.event);
    }
    return next;
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

  /// The `failure`-shaped conclusions this leg treats as "did not succeed".
  static const Set<String> _failedConclusions = <String>{
    'failure',
    'timed_out',
  };

  /// Polls COMPLETED workflow runs and emits the ones a seat rule admits.
  ///
  /// The feedback leg above it enumerates OPEN PULLS and keeps only `grid/`
  /// heads, so a scheduled run on the default branch — the red nightly nobody
  /// notices — can never reach a projection through it. This leg is that
  /// missing half, and it is DECLARATION-GATED: with no rule it returns before
  /// the first request.
  ///
  /// A run that matches no rule is never followed up: the per-run jobs request
  /// happens only after [matchWorkflowRunRule] has already admitted the run.
  Future<GitHubReconcilerCursor> _runs(GitHubReconcilerCursor cursor) async {
    if (workflowRuns.isEmpty) return cursor;
    const key = 'intake/workflow-runs';
    var response = await _client.send(
      method: 'GET',
      path: '/repos/$owner/$repository/actions/runs',
      queryParameters: <String, String>{
        'status': 'completed',
        'per_page': '50',
        if (cursor.workflowRunsSince case final since?)
          'created': '>=${since.toUtc().toIso8601String()}',
      },
      headers: <String, String>{
        if (cursor.etags[key] case final etag?) 'If-None-Match': etag,
      },
    );
    if (response.statusCode == 304) return cursor;
    _requireSuccess(key, response.statusCode);
    final firstPageEtag = response.header('etag');
    var next = cursor;
    var mark = cursor.workflowRunsSince?.toUtc();
    while (true) {
      final page = await _runsPage(next, _runRows(response.body, key), mark);
      next = page.cursor;
      mark = page.latest;
      final nextPage = nextGitHubPageUri(response.header('link'));
      if (nextPage == null) break;
      response = await _client.send(
        method: 'GET',
        path: nextPage.path,
        queryParameters: nextPage.queryParameters,
      );
      _requireSuccess(key, response.statusCode);
    }
    final etags = <String, String>{...next.etags};
    if (firstPageEtag != null) etags[key] = firstPageEtag;
    final saved = next.copyWith(workflowRunsSince: mark, etags: etags);
    await _cursors.save(saved);
    return saved;
  }

  /// Examines one page of workflow-run rows, delivering its events and
  /// returning the cursor plus the greatest `created_at` seen so far.
  ///
  /// A malformed row rides the SAME reporter a malformed intake row does: one
  /// bad row is skipped and named, never allowed to wedge the leg.
  Future<({GitHubReconcilerCursor cursor, DateTime? latest})> _runsPage(
    GitHubReconcilerCursor cursor,
    List<Object?> rows,
    DateTime? latest,
  ) async {
    var next = cursor;
    var mark = latest;
    final events = <NormalizedGitHubEvent>[];
    for (final raw in rows) {
      try {
        final row = _map(raw, 'workflow_run');
        final created = _date(_string(row, 'created_at'), 'created_at');
        if (mark == null || created.isAfter(mark)) mark = created;
        final conclusion = _nullableString(row, 'conclusion');
        if (conclusion == null) continue;
        final nodeId = _string(row, 'node_id');
        final updatedText = _string(row, 'updated_at');
        final observationId = 'poll:run:$nodeId:$updatedText:$conclusion';
        // The `created>=` window is INCLUSIVE and a nightly stays inside it
        // all day, so a claimed run is dropped HERE — before its jobs request
        // — rather than by `_deliver` after one has been spent on it.
        if (next.hasObserved(observationId)) continue;
        // A fork's run executes contributor-authored workflow code, so it is
        // never the seat's own authority however well it matches.
        final head = _string(
          _nestedMap(row, 'head_repository'),
          'full_name',
          prefix: 'head_repository',
        );
        if (head != '$owner/$repository') continue;
        final workflowPath = _string(row, 'path');
        final event = _string(row, 'event');
        final headBranch = _string(row, 'head_branch');
        final rule = matchWorkflowRunRule(
          workflowRuns,
          workflowPath: workflowPath,
          event: event,
          headBranch: headBranch,
          conclusion: conclusion,
          defaultBranch: defaultBranch,
        );
        if (rule == null) continue;
        final runId = _integer(row, 'id');
        events.add(
          NormalizedGitHubEvent.workflowRunConcluded(
            nodeId: nodeId,
            actor: '$owner/$repository',
            repository: '$owner/$repository',
            substation: substation,
            observationId: observationId,
            runId: runId,
            runNumber: _integer(row, 'run_number'),
            workflowPath: workflowPath,
            workflowName: _string(row, 'name'),
            event: event,
            headBranch: headBranch,
            headSha: _string(row, 'head_sha'),
            conclusion: conclusion,
            htmlUrl: _string(row, 'html_url'),
            failedJobs: await _failedJobs(runId),
          ),
        );
      } on FormatException catch (error, stackTrace) {
        _reportIntakeRowError(error, stackTrace);
      }
    }
    return (cursor: await _deliver(next, events), latest: mark);
  }

  /// The jobs of run [runId] that did NOT succeed, with the first step each
  /// failed on.
  ///
  /// `filter=latest` keeps re-run history out: what the bead must name is the
  /// attempt that is red NOW.
  Future<List<WorkflowRunFailedJob>> _failedJobs(int runId) async {
    final key = 'intake/workflow-run-jobs/$runId';
    var response = await _client.send(
      method: 'GET',
      path: '/repos/$owner/$repository/actions/runs/$runId/jobs',
      queryParameters: const <String, String>{
        'filter': 'latest',
        'per_page': '100',
      },
    );
    _requireSuccess(key, response.statusCode);
    final failed = <WorkflowRunFailedJob>[];
    while (true) {
      final page = _map(_decoded(response.body, key), key);
      final jobs = page['jobs'];
      if (jobs is! List) throw const FormatException('jobs must be a list');
      for (final raw in jobs) {
        final job = _map(raw, 'job');
        if (!_failedConclusions.contains(_nullableString(job, 'conclusion'))) {
          continue;
        }
        failed.add(
          WorkflowRunFailedJob(
            jobName: _string(job, 'name'),
            failedStepName: _firstFailedStep(job),
          ),
        );
      }
      final nextPage = nextGitHubPageUri(response.header('link'));
      if (nextPage == null) return failed;
      response = await _client.send(
        method: 'GET',
        path: nextPage.path,
        queryParameters: nextPage.queryParameters,
      );
      _requireSuccess(key, response.statusCode);
    }
  }

  /// The first step of [job] that failed or timed out, or null when GitHub
  /// reported none — a job killed before a step ran has no step to name.
  String? _firstFailedStep(Map<String, Object?> job) {
    final steps = job['steps'];
    if (steps is! List) return null;
    for (final raw in steps) {
      final step = _map(raw, 'step');
      if (_failedConclusions.contains(_nullableString(step, 'conclusion'))) {
        return _string(step, 'name');
      }
    }
    return null;
  }

  /// Drops cursor baselines for issues this seat no longer watches.
  ///
  /// Saves only when something actually changed, so a feature-off seat — and a
  /// seat whose configuration is unchanged — writes nothing at all.
  Future<GitHubReconcilerCursor> _pruneIssueWatches(
    GitHubReconcilerCursor cursor,
  ) async {
    final pruned = cursor.retainIssueWatches(issueWatches);
    if (identical(pruned, cursor)) return cursor;
    await _cursors.save(pruned);
    return pruned;
  }

  /// Polls one lane's watched OUTBOUND issues, in declaration order.
  Future<GitHubReconcilerCursor> _issueWatchLeg(
    GitHubReconcilerCursor cursor,
    List<GitHubIssueWatch> watches, {
    required bool foreign,
  }) async {
    var next = cursor;
    for (final watch in watches) {
      next = await _pollIssueWatch(next, watch, foreign: foreign);
    }
    return next;
  }

  /// GETs [path] through the lane [foreign] selects.
  ///
  /// The ONE place the split is made: an installed repository rides the App
  /// client and its installation token, a foreign one the token-less sibling.
  /// Neither can reach the other's client.
  Future<GitHubHttpResponse> _watchGet(
    bool foreign, {
    required String path,
    Map<String, String> headers = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
  }) => foreign
      ? _foreign!.get(
          path: path,
          headers: headers,
          queryParameters: queryParameters,
        )
      : _client.send(
          method: 'GET',
          path: path,
          headers: headers,
          queryParameters: queryParameters,
        );

  /// Observes one watched issue: its authoritative resource, then its timeline.
  ///
  /// The FIRST successful poll is a BASELINE. It emits every comment already on
  /// the issue oldest-first — those are replies nobody has read yet — and one
  /// synthetic state event when the issue is already closed or locked, but it
  /// does NOT replay the transitions that produced that state; it simply
  /// records the timeline mark they sit behind. Every later poll emits only
  /// what is beyond the stored marks.
  Future<GitHubReconcilerCursor> _pollIssueWatch(
    GitHubReconcilerCursor cursor,
    GitHubIssueWatch watch, {
    required bool foreign,
  }) async {
    final key = watch.coordinateKey;
    final record = cursor.issueWatches[key];
    // Transferred, deleted and converted are TERMINAL: there is no resource
    // left at these coordinates, so every further request would be spent to
    // learn the same thing.
    if (record != null && record.isTerminal) return cursor;

    final issueKey = GitHubReconcilerCursor.issueWatchEtagKey(key);
    final timelineKey = GitHubReconcilerCursor.issueWatchTimelineEtagKey(key);
    final basePath =
        '/repos/${Uri.encodeComponent(watch.owner)}/'
        '${Uri.encodeComponent(watch.repository)}/issues/${watch.issueNumber}';

    final issueConditional = record == null ? null : cursor.etags[issueKey];
    final response = await _watchGet(
      foreign,
      path: basePath,
      headers: <String, String>{
        if (issueConditional case final etag?) 'If-None-Match': etag,
      },
    );
    final status = response.statusCode;
    if (_watchStatusChanges.containsKey(status)) {
      return _recordWatchStatus(cursor, watch, record, status);
    }
    if (status == 304) {
      // Unreachable unless a server answers a conditional we never sent: a
      // `304` with no baseline is a response we cannot interpret at all.
      if (record == null) {
        throw GitHubPollException(endpoint: issueKey, statusCode: status);
      }
    } else {
      _requireSuccess(issueKey, status);
    }

    final _IssueResource resource;
    final String? issueEtag;
    if (status == 304) {
      resource = _IssueResource.fromRecord(record!);
      issueEtag = issueConditional;
    } else {
      final body = _map(_decoded(response.body, issueKey), issueKey);
      // `/issues/{number}` answers for pull requests too, and a pull's
      // comments belong to the CI feedback rail, not to an outbound watch.
      if (body.containsKey('pull_request')) {
        throw FormatException(
          '$issueKey resolved a pull request, not an issue',
        );
      }
      final closedBy = body['closed_by'];
      resource = _IssueResource(
        nodeId: _string(body, 'node_id'),
        author: _string(_nestedMap(body, 'user'), 'login', prefix: 'user'),
        state: _string(body, 'state'),
        stateReason: _nullableString(body, 'state_reason'),
        locked: _boolean(body, 'locked'),
        updatedAt: _date(_string(body, 'updated_at'), 'updated_at'),
        url: _nullableString(body, 'html_url'),
        closedBy: closedBy == null
            ? null
            : _string(
                _map(closedBy, 'closed_by'),
                'login',
                prefix: 'closed_by',
              ),
      );
      issueEtag = response.header('etag');
    }

    final timeline = await _issueTimeline(
      cursor,
      basePath,
      timelineKey,
      hasBaseline: record != null,
      foreign: foreign,
    );

    final events = <NormalizedGitHubEvent>[];
    final baseline = record == null;
    var lastCommentId = record?.lastCommentId ?? 0;
    var lastTimelineEventId = record?.lastTimelineEventId ?? 0;
    // The state the timeline REPLAYS to, started from the durable baseline.
    // Each emitted transition carries the values as of ITSELF, so a close
    // followed by a reopen in one cycle does not report both as `open`.
    var state = record?.lastState ?? resource.state;
    var stateReason = record?.lastStateReason ?? resource.stateReason;
    var locked = record?.locked ?? resource.locked;

    for (final entry in timeline.entries) {
      if (entry.event == 'commented') {
        if (entry.id <= lastCommentId) continue;
        lastCommentId = entry.id;
        events.add(_commentEvent(watch, resource, entry));
        continue;
      }
      if (entry.id <= lastTimelineEventId) continue;
      lastTimelineEventId = entry.id;
      final change = _timelineChange(entry, resource);
      if (change == null) continue;
      switch (change) {
        case GitHubIssueWatchChange.closedCompleted:
        case GitHubIssueWatchChange.closedNotPlanned:
          state = 'closed';
          stateReason =
              _nullableString(entry.row, 'state_reason') ??
              resource.stateReason;
        case GitHubIssueWatchChange.reopened:
          state = 'open';
          stateReason = null;
        case GitHubIssueWatchChange.locked:
          locked = entry.event == 'locked';
        case GitHubIssueWatchChange.transferred:
        case GitHubIssueWatchChange.deleted:
        case GitHubIssueWatchChange.convertedToDiscussion:
        case GitHubIssueWatchChange.unreadable:
          break;
      }
      if (baseline) continue;
      events.add(
        _stateEvent(
          watch,
          resource,
          nodeId: _string(entry.row, 'node_id'),
          actor: _entryActor(entry.row) ?? kIssueWatchResourceActor,
          observationId:
              'poll:issue-state:${_string(entry.row, 'node_id')}:${change.wire}',
          change: change,
          state: state,
          stateReason: stateReason,
          locked: locked,
        ),
      );
    }

    if (baseline) {
      // A watch armed against an issue that is ALREADY closed or locked must
      // say so once: the reply that never came is exactly what this feature
      // exists to notice, and silence here would look like an open issue.
      final change = resource.state == 'open'
          ? (resource.locked ? GitHubIssueWatchChange.locked : null)
          : _closedChange(resource.stateReason);
      if (change != null) {
        events.add(_resourceStateEvent(watch, resource, change));
      }
    } else if (resource.state != state ||
        resource.stateReason != stateReason ||
        resource.locked != locked) {
      // The resource is AUTHORITATIVE. A transition the timeline did not
      // explain — a row GitHub has not published yet, or one this version does
      // not decode — still reaches the bead rather than going quiet.
      final change = _resourceChange(
        state: state,
        stateReason: stateReason,
        locked: locked,
        resource: resource,
      );
      if (change != null) {
        events.add(_resourceStateEvent(watch, resource, change));
      }
    }

    // DELIVER FIRST, advance SECOND. A crash between the two replays the poll
    // and the delivered-id ledger drops what already landed; the reverse order
    // would skip an observation for good.
    var next = await _deliver(cursor, events);
    final emitted = events.whereType<WatchedIssueStateChanged>().lastOrNull;
    next = next.recordIssueWatch(
      key,
      GitHubIssueWatchCursorRecord(
        issueNodeId: resource.nodeId,
        issueAuthor: resource.author,
        lastCommentId: lastCommentId,
        lastTimelineEventId: lastTimelineEventId,
        lastState: resource.state,
        lastStateReason: resource.stateReason,
        locked: resource.locked,
        lastUpdatedAt: resource.updatedAt,
        // A successful read CLEARS a stale `unreadable`: access came back.
        lastChange:
            emitted?.change ??
            (record?.lastChange == GitHubIssueWatchChange.unreadable
                ? null
                : record?.lastChange),
      ),
      issueEtag: issueEtag,
      timelineEtag: timeline.etag,
    );
    await _cursors.save(next);
    return next;
  }

  /// The statuses that ARE the transition — no body to read, no timeline left.
  static const Map<int, GitHubIssueWatchChange> _watchStatusChanges =
      <int, GitHubIssueWatchChange>{
        301: GitHubIssueWatchChange.transferred,
        410: GitHubIssueWatchChange.deleted,
        404: GitHubIssueWatchChange.unreadable,
      };

  /// Records a transition reported only by an HTTP status.
  ///
  /// With NO baseline this THROWS: a `404` on the very first poll says nothing
  /// about a watch — the coordinates may simply be wrong — and there is no
  /// issue node id or author to attribute an observation to. Guessing would
  /// file "your issue became unreadable" for an issue that never existed.
  Future<GitHubReconcilerCursor> _recordWatchStatus(
    GitHubReconcilerCursor cursor,
    GitHubIssueWatch watch,
    GitHubIssueWatchCursorRecord? record,
    int status,
  ) async {
    final key = watch.coordinateKey;
    if (record == null) {
      throw GitHubPollException(
        endpoint: GitHubReconcilerCursor.issueWatchEtagKey(key),
        statusCode: status,
      );
    }
    final change = _watchStatusChanges[status]!;
    if (record.lastChange == change) return cursor;
    var next = await _deliver(cursor, <NormalizedGitHubEvent>[
      NormalizedGitHubEvent.watchedIssueStateChanged(
        nodeId: record.issueNodeId,
        actor: kIssueWatchResourceActor,
        repository: '${watch.owner}/${watch.repository}',
        substation: substation,
        observationId:
            'poll:issue-state:${record.issueNodeId}:$status:${change.wire}',
        originatingBeadId: watch.originatingBeadId,
        issueNodeId: record.issueNodeId,
        issueAuthor: record.issueAuthor,
        issueNumber: watch.issueNumber,
        change: change,
        state: record.lastState,
        stateReason: record.lastStateReason,
        locked: record.locked,
        url: null,
        updatedAt: record.lastUpdatedAt,
      ),
    ]);
    // Both tags go with the record: whatever they were conditional on is gone.
    next = next.recordIssueWatch(key, record.copyWith(lastChange: change));
    await _cursors.save(next);
    return next;
  }

  /// Every Link-paginated timeline row for one watched issue, oldest first.
  ///
  /// A `304` on the first page is the cheap answer this leg is built for: no
  /// rows, and the tag it was conditional on is retained.
  Future<({List<_TimelineEntry> entries, String? etag})> _issueTimeline(
    GitHubReconcilerCursor cursor,
    String basePath,
    String timelineKey, {
    required bool hasBaseline,
    required bool foreign,
  }) async {
    final conditional = hasBaseline ? cursor.etags[timelineKey] : null;
    var response = await _watchGet(
      foreign,
      path: '$basePath/timeline',
      queryParameters: const <String, String>{'per_page': '100'},
      headers: <String, String>{
        if (conditional case final etag?) 'If-None-Match': etag,
      },
    );
    if (response.statusCode == 304) {
      return (entries: const <_TimelineEntry>[], etag: conditional);
    }
    _requireSuccess(timelineKey, response.statusCode);
    final firstPageEtag = response.header('etag');
    final entries = <_TimelineEntry>[];
    while (true) {
      for (final raw in _list(response.body, timelineKey)) {
        final row = _map(raw, 'timeline');
        final event = _nullableString(row, 'event');
        if (event == null || !_watchedTimelineEvents.contains(event)) continue;
        final id = row['id'];
        // A row GitHub gives no id cannot be ordered against the stored mark,
        // so it can only ever be re-emitted; skipping it is the honest choice.
        if (id is! int) continue;
        entries.add(
          _TimelineEntry(
            event: event,
            id: id,
            createdAt: _date(_string(row, 'created_at'), 'created_at'),
            row: row,
          ),
        );
      }
      final nextPage = nextGitHubPageUri(response.header('link'));
      if (nextPage == null) break;
      response = await _watchGet(
        foreign,
        path: nextPage.path,
        queryParameters: nextPage.queryParameters,
      );
      _requireSuccess(timelineKey, response.statusCode);
    }
    entries.sort((left, right) {
      final byTime = left.createdAt.compareTo(right.createdAt);
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });
    return (entries: entries, etag: firstPageEtag);
  }

  /// The timeline rows a watch decodes; everything else is noise it skips.
  static const Set<String> _watchedTimelineEvents = <String>{
    'commented',
    'closed',
    'reopened',
    'locked',
    'unlocked',
    'transferred',
    'converted_to_discussion',
  };

  GitHubIssueWatchChange? _timelineChange(
    _TimelineEntry entry,
    _IssueResource resource,
  ) => switch (entry.event) {
    'closed' => _closedChange(
      _nullableString(entry.row, 'state_reason') ?? resource.stateReason,
    ),
    'reopened' => GitHubIssueWatchChange.reopened,
    'locked' || 'unlocked' => GitHubIssueWatchChange.locked,
    'transferred' => GitHubIssueWatchChange.transferred,
    'converted_to_discussion' => GitHubIssueWatchChange.convertedToDiscussion,
    _ => null,
  };

  /// The change a `closed` observation carries; a missing reason is
  /// `completed`, which is what GitHub's own default means.
  GitHubIssueWatchChange _closedChange(String? reason) =>
      reason == 'not_planned'
      ? GitHubIssueWatchChange.closedNotPlanned
      : GitHubIssueWatchChange.closedCompleted;

  /// The change between the replayed state and the authoritative resource.
  GitHubIssueWatchChange? _resourceChange({
    required String state,
    required String? stateReason,
    required bool locked,
    required _IssueResource resource,
  }) {
    if (resource.state != state) {
      return resource.state == 'open'
          ? GitHubIssueWatchChange.reopened
          : _closedChange(resource.stateReason);
    }
    if (resource.state != 'open' && resource.stateReason != stateReason) {
      return _closedChange(resource.stateReason);
    }
    return resource.locked != locked ? GitHubIssueWatchChange.locked : null;
  }

  NormalizedGitHubEvent _commentEvent(
    GitHubIssueWatch watch,
    _IssueResource resource,
    _TimelineEntry entry,
  ) {
    final row = entry.row;
    final updated =
        _nullableString(row, 'updated_at') ?? _string(row, 'created_at');
    return NormalizedGitHubEvent.issueCommented(
      nodeId: _string(row, 'node_id'),
      actor: _entryActor(row) ?? kIssueWatchResourceActor,
      repository: '${watch.owner}/${watch.repository}',
      substation: substation,
      observationId: 'poll:issue-comment:${_string(row, 'node_id')}',
      originatingBeadId: watch.originatingBeadId,
      issueNodeId: resource.nodeId,
      issueAuthor: resource.author,
      issueNumber: watch.issueNumber,
      commentId: entry.id,
      body: _nullableString(row, 'body') ?? '',
      url: _nullableString(row, 'html_url') ?? '',
      updatedAt: _date(updated, 'updated_at'),
    );
  }

  NormalizedGitHubEvent _stateEvent(
    GitHubIssueWatch watch,
    _IssueResource resource, {
    required String nodeId,
    required String actor,
    required String observationId,
    required GitHubIssueWatchChange change,
    required String state,
    required String? stateReason,
    required bool locked,
  }) => NormalizedGitHubEvent.watchedIssueStateChanged(
    nodeId: nodeId,
    actor: actor,
    repository: '${watch.owner}/${watch.repository}',
    substation: substation,
    observationId: observationId,
    originatingBeadId: watch.originatingBeadId,
    issueNodeId: resource.nodeId,
    issueAuthor: resource.author,
    issueNumber: watch.issueNumber,
    change: change,
    state: state,
    stateReason: stateReason,
    locked: locked,
    url: resource.url,
    updatedAt: resource.updatedAt,
  );

  /// A transition attributed to the ISSUE RESOURCE rather than a timeline row.
  ///
  /// Its observation id carries the resource's `updated_at`, so a later
  /// transition of the same kind is a distinct observation while a re-read of
  /// the same one is not.
  NormalizedGitHubEvent _resourceStateEvent(
    GitHubIssueWatch watch,
    _IssueResource resource,
    GitHubIssueWatchChange change,
  ) => _stateEvent(
    watch,
    resource,
    nodeId: resource.nodeId,
    actor: resource.state == 'open'
        ? kIssueWatchResourceActor
        : resource.closedBy ?? kIssueWatchResourceActor,
    observationId:
        'poll:issue-state:${resource.nodeId}:'
        '${resource.updatedAt.toUtc().toIso8601String()}:${change.wire}',
    change: change,
    state: resource.state,
    stateReason: resource.stateReason,
    locked: resource.locked,
  );

  /// The login credited with one timeline row, or null when GitHub named none
  /// — a comment by a since-deleted account carries a null `user`.
  String? _entryActor(Map<String, Object?> row) {
    for (final field in const <String>['user', 'actor']) {
      final value = row[field];
      if (value is Map) {
        final login = Map<String, Object?>.from(value)['login'];
        if (login is String) return login;
      }
    }
    return null;
  }

  Future<GitHubReconcilerCursor> _deliver(
    GitHubReconcilerCursor cursor,
    Iterable<NormalizedGitHubEvent> events,
  ) async {
    var next = cursor;
    for (final event in events) {
      final id = GitHubReconcilerCursor.observationIdOf(event);
      if (next.hasObserved(id)) continue;
      if (!next.isPending(id)) {
        next = next.enqueue(event);
        await _cursors.save(next);
      }
      next = await _dispatch(next, event);
    }
    return next;
  }

  /// Drives every UNACKED delivery leg for one PENDING observation, then records
  /// it DELIVERED.
  ///
  /// Each leg's acknowledgement is persisted the moment that leg returns, so a
  /// throw from a LATER leg replays only the legs that have not acked. An id
  /// that is already DELIVERED is drained from the queue WITHOUT touching any
  /// leg; that is the idempotency of replay.
  Future<GitHubReconcilerCursor> _dispatch(
    GitHubReconcilerCursor cursor,
    NormalizedGitHubEvent event,
  ) async {
    final id = GitHubReconcilerCursor.observationIdOf(event);
    var next = cursor;
    if (!next.hasObserved(id)) {
      if (next.pendingFor(id)?.hasAcked(kSinkDeliveryLeg) != true) {
        await _emit(event);
        next = next.ack(id, kSinkDeliveryLeg);
        await _cursors.save(next);
      }
      for (final observer in List<_DeliveryLeg>.of(_observers)) {
        if (next.pendingFor(id)?.hasAcked(observer.leg) ?? false) continue;
        await observer.sink(event);
        next = next.ack(id, observer.leg);
        await _cursors.save(next);
      }
    }
    final delivered = next.deliver(id);
    await _cursors.save(delivered);
    return delivered;
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

/// The `workflow_runs` array of one `/actions/runs` page.
List<Object?> _runRows(String body, String endpoint) {
  final page = _map(_decoded(body, endpoint), endpoint);
  final rows = page['workflow_runs'];
  if (rows is! List) {
    throw const FormatException('workflow_runs must be a list');
  }
  return rows.cast<Object?>();
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

/// The AUTHORITATIVE values of one watched issue for one poll.
///
/// Built from `/issues/{number}` when GitHub answered `200`, and from the
/// durable record when it answered `304` — a conditional response has no body
/// to read, and the record is exactly what the tag was conditional on.
class _IssueResource {
  const _IssueResource({
    required this.nodeId,
    required this.author,
    required this.state,
    required this.stateReason,
    required this.locked,
    required this.updatedAt,
    required this.url,
    required this.closedBy,
  });

  factory _IssueResource.fromRecord(GitHubIssueWatchCursorRecord record) =>
      _IssueResource(
        nodeId: record.issueNodeId,
        author: record.issueAuthor,
        state: record.lastState,
        stateReason: record.lastStateReason,
        locked: record.locked,
        updatedAt: record.lastUpdatedAt,
        url: null,
        closedBy: null,
      );

  final String nodeId;
  final String author;
  final String state;
  final String? stateReason;
  final bool locked;
  final DateTime updatedAt;
  final String? url;
  final String? closedBy;
}

/// One decoded, orderable timeline row.
class _TimelineEntry {
  const _TimelineEntry({
    required this.event,
    required this.id,
    required this.createdAt,
    required this.row,
  });

  final String event;
  final int id;
  final DateTime createdAt;
  final Map<String, Object?> row;
}

bool _boolean(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! bool) throw FormatException('$field must be a boolean');
  return value;
}

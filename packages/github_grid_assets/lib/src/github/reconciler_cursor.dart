import 'issue_watch.dart';
import 'reconciler_event.dart';

/// One observation persisted PENDING, with the delivery legs that have acked.
///
/// An entry lives in [GitHubReconcilerCursor.pending] from the moment it is
/// persisted — BEFORE any leg runs — until every leg has acknowledged it, at
/// which point [GitHubReconcilerCursor.deliver] drains it and claims its id.
class PendingObservation {
  /// Creates a pending entry for [event] with the legs already acknowledged.
  const PendingObservation({
    required this.event,
    this.acked = const <String>[],
  });

  /// Decodes a pending entry; a malformed shape throws.
  factory PendingObservation.fromJson(Map<String, Object?> json) =>
      PendingObservation(
        event: NormalizedGitHubEvent.fromJson(
          Map<String, Object?>.from(json['event']! as Map),
        ),
        acked: List<String>.unmodifiable(
          (json['acked']! as List).cast<String>(),
        ),
      );

  /// The normalized observation awaiting acknowledgement.
  final NormalizedGitHubEvent event;

  /// Delivery legs that returned without throwing, in acknowledgement order.
  final List<String> acked;

  /// The observation identity carried by [event].
  String get observationId => GitHubReconcilerCursor.observationIdOf(event);

  /// Whether [leg] already acknowledged this observation.
  bool hasAcked(String leg) => acked.contains(leg);

  /// Records [leg] as acknowledged; a duplicate leg changes nothing.
  PendingObservation ack(String leg) => hasAcked(leg)
      ? this
      : PendingObservation(
          event: event,
          acked: List<String>.unmodifiable(<String>[...acked, leg]),
        );

  /// Encodes the pending entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'event': event.toJson(),
    'acked': acked,
  };
}

/// The durable state of ONE watched outbound issue.
///
/// It is the BASELINE a later poll is diffed against: without it every cycle
/// would re-emit every comment the issue has ever had, and a `304` would have
/// no state to answer from at all.
class GitHubIssueWatchCursorRecord {
  /// Creates one watched-issue record.
  const GitHubIssueWatchCursorRecord({
    required this.issueNodeId,
    required this.issueAuthor,
    required this.lastCommentId,
    required this.lastTimelineEventId,
    required this.lastState,
    required this.lastStateReason,
    required this.locked,
    required this.lastUpdatedAt,
    required this.lastChange,
  });

  /// Decodes one record; a malformed shape throws.
  factory GitHubIssueWatchCursorRecord.fromJson(Map<String, Object?> json) =>
      GitHubIssueWatchCursorRecord(
        issueNodeId: _requiredString(json, 'issue_node_id'),
        issueAuthor: _requiredString(json, 'issue_author'),
        lastCommentId: _requiredInt(json, 'last_comment_id'),
        lastTimelineEventId: _requiredInt(json, 'last_timeline_event_id'),
        lastState: _requiredString(json, 'last_state'),
        lastStateReason: _optionalString(json, 'last_state_reason'),
        locked: switch (json['locked']) {
          final bool value => value,
          _ => throw const FormatException(
            'issue watch locked must be a boolean',
          ),
        },
        lastUpdatedAt: _utcTimestamp(json, 'last_updated_at'),
        lastChange: switch (_optionalString(json, 'last_change')) {
          null => null,
          final String wire => GitHubIssueWatchChange.fromWire(wire),
        },
      );

  /// GitHub's stable node id for the watched ISSUE.
  ///
  /// The DURABLE identity of the watch: the coordinates it is keyed by can be
  /// reused by GitHub after a transfer, the node id cannot.
  final String issueNodeId;

  /// The login that opened the issue — the identity ownership is decided by.
  final String issueAuthor;

  /// The greatest comment id already observed; `0` before the first poll.
  final int lastCommentId;

  /// The greatest timeline-event id already observed; `0` before the first
  /// poll.
  final int lastTimelineEventId;

  /// The issue's last observed `state`.
  final String lastState;

  /// The issue's last observed `state_reason`, or null when it carried none.
  final String? lastStateReason;

  /// Whether the issue was locked when last observed.
  final bool locked;

  /// The issue's last observed `updated_at`, in UTC.
  final DateTime lastUpdatedAt;

  /// The last change emitted for this watch, or null when only comments have
  /// been seen.
  ///
  /// It is also the STOP flag: [transferred], [deleted] and
  /// [GitHubIssueWatchChange.convertedToDiscussion] are terminal, and a watch
  /// that reached one spends no further request.
  final GitHubIssueWatchChange? lastChange;

  /// Whether this watch has reached a state no further request can improve.
  bool get isTerminal => switch (lastChange) {
    GitHubIssueWatchChange.transferred ||
    GitHubIssueWatchChange.deleted ||
    GitHubIssueWatchChange.convertedToDiscussion => true,
    _ => false,
  };

  /// Returns an immutable copy with selected values replaced.
  GitHubIssueWatchCursorRecord copyWith({
    String? issueNodeId,
    String? issueAuthor,
    int? lastCommentId,
    int? lastTimelineEventId,
    String? lastState,
    String? lastStateReason,
    bool? locked,
    DateTime? lastUpdatedAt,
    GitHubIssueWatchChange? lastChange,
  }) => GitHubIssueWatchCursorRecord(
    issueNodeId: issueNodeId ?? this.issueNodeId,
    issueAuthor: issueAuthor ?? this.issueAuthor,
    lastCommentId: lastCommentId ?? this.lastCommentId,
    lastTimelineEventId: lastTimelineEventId ?? this.lastTimelineEventId,
    lastState: lastState ?? this.lastState,
    lastStateReason: lastStateReason ?? this.lastStateReason,
    locked: locked ?? this.locked,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    lastChange: lastChange ?? this.lastChange,
  );

  /// Encodes the record.
  Map<String, Object?> toJson() => <String, Object?>{
    'issue_node_id': issueNodeId,
    'issue_author': issueAuthor,
    'last_comment_id': lastCommentId,
    'last_timeline_event_id': lastTimelineEventId,
    'last_state': lastState,
    'last_state_reason': lastStateReason,
    'locked': locked,
    'last_updated_at': lastUpdatedAt.toUtc().toIso8601String(),
    'last_change': lastChange?.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is GitHubIssueWatchCursorRecord &&
      other.issueNodeId == issueNodeId &&
      other.issueAuthor == issueAuthor &&
      other.lastCommentId == lastCommentId &&
      other.lastTimelineEventId == lastTimelineEventId &&
      other.lastState == lastState &&
      other.lastStateReason == lastStateReason &&
      other.locked == locked &&
      other.lastUpdatedAt == lastUpdatedAt &&
      other.lastChange == lastChange;

  @override
  int get hashCode => Object.hash(
    issueNodeId,
    issueAuthor,
    lastCommentId,
    lastTimelineEventId,
    lastState,
    lastStateReason,
    locked,
    lastUpdatedAt,
    lastChange,
  );
}

String _requiredString(Map<String, Object?> json, String field) =>
    switch (json[field]) {
      final String value => value,
      _ => throw FormatException('issue watch $field must be a string'),
    };

String? _optionalString(Map<String, Object?> json, String field) =>
    switch (json[field]) {
      null => null,
      final String value => value,
      _ => throw FormatException('issue watch $field must be a string or null'),
    };

int _requiredInt(Map<String, Object?> json, String field) =>
    switch (json[field]) {
      final int value => value,
      _ => throw FormatException('issue watch $field must be an integer'),
    };

/// The UTC timestamp at [field]; a ZONE-LESS spelling is REFUSED.
///
/// `DateTime.parse` normalizes any explicit offset to UTC, but a spelling with
/// no zone at all parses as LOCAL time — which would make one cursor document
/// mean different instants on two machines, and silently re-emit observations
/// whenever the seat moved. GitHub always sends a zone, so a document without
/// one was written by hand and is refused loudly.
DateTime _utcTimestamp(Map<String, Object?> json, String field) {
  final raw = _requiredString(json, field);
  final parsed = DateTime.parse(raw);
  if (!parsed.isUtc) {
    throw FormatException('issue watch $field must be a UTC timestamp');
  }
  return parsed;
}

/// Durable per-substation GitHub polling state.
class GitHubReconcilerCursor {
  /// Creates polling state.
  const GitHubReconcilerCursor({
    this.since,
    this.workflowRunsSince,
    this.etags = const <String, String>{},
    this.observationIds = const <String>[],
    this.pullHeads = const <String, String>{},
    this.pending = const <PendingObservation>[],
    this.issueWatches = const <String, GitHubIssueWatchCursorRecord>{},
  });

  /// Intake high-water mark.
  final DateTime? since;

  /// Workflow-run high-water mark — the greatest `created_at` examined.
  ///
  /// Bounds the `created>=` window the workflow-run leg requests, so a seat
  /// with a long history does not re-read every run it has ever produced. The
  /// bound is INCLUSIVE: a run created in the same second as the mark is
  /// re-read and dropped by the observation ledger, which is cheaper than
  /// never seeing it at all.
  final DateTime? workflowRunsSince;

  /// Conditional response tags keyed by polling endpoint.
  final Map<String, String> etags;

  /// Newest-first bounded observation identity ledger.
  final List<String> observationIds;

  /// Head refs of fetched pull resources, keyed by pull node id.
  ///
  /// A pull's issues-schema row carries no `head`, so the poll fetches the full
  /// resource; the ref is cached here so a conditional re-fetch answered `304`
  /// still has a ref to emit. A head and its conditional tag in [etags] are
  /// written and dropped together — see [recordPullHead].
  final Map<String, String> pullHeads;

  /// OLDEST-FIRST queue of PENDING observations awaiting acknowledgement.
  ///
  /// Oldest-first — the opposite of [observationIds] — because replay must
  /// re-deliver in observation order. Deliberately UNBOUNDED: dropping an entry
  /// is precisely the silent loss this queue exists to prevent. It is bounded in
  /// practice by the number of DISTINCT undelivered observations, because
  /// [enqueue] is idempotent by observation id.
  final List<PendingObservation> pending;

  /// Watched OUTBOUND issue baselines, keyed by
  /// [GitHubIssueWatch.coordinateKey].
  ///
  /// The SAME document as every other cursor value on purpose: an observation
  /// and the delivery state that carries it must be one atomic save, and a
  /// sibling store would reintroduce exactly the torn write this cursor
  /// exists to prevent. A record and its two conditional tags in [etags] are
  /// written and dropped together — see [recordIssueWatch].
  final Map<String, GitHubIssueWatchCursorRecord> issueWatches;

  /// Whether [id] has already been durably claimed.
  bool hasObserved(String id) => observationIds.contains(id);

  /// Claims [id], retaining the newest 512 identities.
  GitHubReconcilerCursor record(String id) {
    if (hasObserved(id)) return this;
    return copyWith(
      observationIds: <String>[id, ...observationIds].take(512).toList(),
    );
  }

  /// The observation identity carried by [event].
  static String observationIdOf(NormalizedGitHubEvent event) => switch (event) {
    IssueOpened(:final observationId) => observationId,
    PullRequestOpened(:final observationId) => observationId,
    CheckConcluded(:final observationId) => observationId,
    WorkflowRunConcluded(:final observationId) => observationId,
    IssueCommented(:final observationId) => observationId,
    WatchedIssueStateChanged(:final observationId) => observationId,
  };

  /// The PENDING entry for [id], or null when [id] is not pending.
  PendingObservation? pendingFor(String id) {
    for (final entry in pending) {
      if (entry.observationId == id) return entry;
    }
    return null;
  }

  /// Whether [id] is PENDING — persisted, not yet fully acknowledged.
  bool isPending(String id) => pendingFor(id) != null;

  /// Appends [event] to the PENDING queue; a duplicate id changes nothing.
  GitHubReconcilerCursor enqueue(NormalizedGitHubEvent event) {
    if (isPending(observationIdOf(event))) return this;
    return copyWith(
      pending: <PendingObservation>[
        ...pending,
        PendingObservation(event: event),
      ],
    );
  }

  /// Records [leg] as acknowledged for the PENDING observation [id].
  GitHubReconcilerCursor ack(String id, String leg) => copyWith(
    pending: pending
        .map((entry) => entry.observationId == id ? entry.ack(leg) : entry)
        .toList(growable: false),
  );

  /// Moves [id] from PENDING to DELIVERED as one value.
  ///
  /// Saving the result is the single atomic write that acknowledges the
  /// observation. Nothing else on the delivery path calls [record].
  GitHubReconcilerCursor deliver(String id) => record(id).copyWith(
    pending: pending
        .where((entry) => entry.observationId != id)
        .toList(growable: false),
  );

  static const String _pullEtagPrefix = 'intake/pull/';

  /// The [etags] key under which pull [nodeId]'s resource tag is held.
  static String pullEtagKey(String nodeId) => '$_pullEtagPrefix$nodeId';

  /// Caches [headRef] for pull [nodeId] — and [etag] when the response carried
  /// one — retaining the newest 512 heads and dropping the conditional tag of
  /// every head evicted with them.
  ///
  /// A null [etag] DROPS any tag held for [nodeId]: a cached head and the tag
  /// that may serve it never diverge.
  GitHubReconcilerCursor recordPullHead(
    String nodeId,
    String headRef, {
    String? etag,
  }) {
    final heads = <String, String>{nodeId: headRef};
    for (final entry in pullHeads.entries) {
      if (heads.length >= 512) break;
      if (entry.key == nodeId) continue;
      heads[entry.key] = entry.value;
    }
    final tags = <String, String>{
      for (final entry in etags.entries)
        if (!entry.key.startsWith(_pullEtagPrefix) ||
            heads.containsKey(entry.key.substring(_pullEtagPrefix.length)))
          entry.key: entry.value,
    };
    if (etag == null) {
      tags.remove(pullEtagKey(nodeId));
    } else {
      tags[pullEtagKey(nodeId)] = etag;
    }
    return copyWith(pullHeads: heads, etags: tags);
  }

  static const String _watchEtagPrefix = 'issue-watch/';

  /// The [etags] key holding the ISSUE-resource tag for [coordinateKey].
  static String issueWatchEtagKey(String coordinateKey) =>
      '$_watchEtagPrefix$coordinateKey/issue';

  /// The [etags] key holding the TIMELINE first-page tag for [coordinateKey].
  static String issueWatchTimelineEtagKey(String coordinateKey) =>
      '$_watchEtagPrefix$coordinateKey/timeline';

  /// Writes [record] for [coordinateKey] together with the FINAL value of both
  /// conditional tags, retaining the newest 512 records and dropping the tags
  /// of every record evicted with them.
  ///
  /// A null [issueEtag] or [timelineEtag] DROPS the tag it names: a baseline
  /// and the conditional request that may be answered `304` against it never
  /// diverge, because a `304` we cannot answer from the record is exactly the
  /// unreachable state [GitHubReconcilerCursor] refuses loudly.
  GitHubReconcilerCursor recordIssueWatch(
    String coordinateKey,
    GitHubIssueWatchCursorRecord record, {
    String? issueEtag,
    String? timelineEtag,
  }) {
    final records = <String, GitHubIssueWatchCursorRecord>{
      coordinateKey: record,
    };
    for (final entry in issueWatches.entries) {
      if (records.length >= 512) break;
      if (entry.key == coordinateKey) continue;
      records[entry.key] = entry.value;
    }
    return copyWith(
      issueWatches: records,
      etags: _watchTags(
        records,
        overrides: <String, String?>{
          issueWatchEtagKey(coordinateKey): issueEtag,
          issueWatchTimelineEtagKey(coordinateKey): timelineEtag,
        },
      ),
    );
  }

  /// Drops every watch record — and both of its tags — whose coordinate is not
  /// named by [watches].
  ///
  /// A seat that stops watching an issue stops paying for it: the baseline is
  /// what makes the next poll cheap, and keeping one for an unwatched issue
  /// only crowds the 512-record budget.
  GitHubReconcilerCursor retainIssueWatches(
    Iterable<GitHubIssueWatch> watches,
  ) {
    final keep = <String>{for (final watch in watches) watch.coordinateKey};
    if (issueWatches.keys.every(keep.contains)) return this;
    final records = <String, GitHubIssueWatchCursorRecord>{
      for (final entry in issueWatches.entries)
        if (keep.contains(entry.key)) entry.key: entry.value,
    };
    return copyWith(issueWatches: records, etags: _watchTags(records));
  }

  /// [etags] with every watch tag not backed by a record in [records] removed
  /// and [overrides] applied — a null override REMOVES its key.
  Map<String, String> _watchTags(
    Map<String, GitHubIssueWatchCursorRecord> records, {
    Map<String, String?> overrides = const <String, String?>{},
  }) {
    final live = <String>{
      for (final key in records.keys) ...<String>[
        issueWatchEtagKey(key),
        issueWatchTimelineEtagKey(key),
      ],
    };
    final tags = <String, String>{
      for (final entry in etags.entries)
        if (!entry.key.startsWith(_watchEtagPrefix) || live.contains(entry.key))
          entry.key: entry.value,
    };
    for (final entry in overrides.entries) {
      if (entry.value == null) {
        tags.remove(entry.key);
      } else {
        tags[entry.key] = entry.value!;
      }
    }
    return tags;
  }

  /// Returns an immutable copy with selected values replaced.
  GitHubReconcilerCursor copyWith({
    DateTime? since,
    bool clearSince = false,
    DateTime? workflowRunsSince,
    Map<String, String>? etags,
    List<String>? observationIds,
    Map<String, String>? pullHeads,
    List<PendingObservation>? pending,
    Map<String, GitHubIssueWatchCursorRecord>? issueWatches,
  }) => GitHubReconcilerCursor(
    since: clearSince ? null : since ?? this.since,
    workflowRunsSince: workflowRunsSince ?? this.workflowRunsSince,
    etags: Map.unmodifiable(etags ?? this.etags),
    observationIds: List.unmodifiable(observationIds ?? this.observationIds),
    pullHeads: Map.unmodifiable(pullHeads ?? this.pullHeads),
    pending: List.unmodifiable(pending ?? this.pending),
    issueWatches: Map.unmodifiable(issueWatches ?? this.issueWatches),
  );

  /// Encodes the versioned cursor document.
  ///
  /// `pull_heads`, `pending`, `workflow_runs_since` and `issue_watches` are all
  /// ADDITIVE at version 1: a document written before any of them existed
  /// decodes with an empty value rather than being refused. The version is
  /// deliberately NOT bumped — [fromJson] throws on `version != 1`, so a bump
  /// would make every cursor already on disk at a live seat unloadable and stop
  /// that seat polling.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'since': since?.toUtc().toIso8601String(),
    'workflow_runs_since': workflowRunsSince?.toUtc().toIso8601String(),
    'etags': etags,
    'observation_ids': observationIds,
    'pull_heads': pullHeads,
    'pending': pending.map((entry) => entry.toJson()).toList(),
    'issue_watches': <String, Object?>{
      for (final entry in issueWatches.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Decodes a version-one cursor document.
  factory GitHubReconcilerCursor.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('unsupported GitHub cursor version');
    }
    try {
      return GitHubReconcilerCursor(
        since: switch (json['since']) {
          final String value => DateTime.parse(value).toUtc(),
          null => null,
          _ => throw const FormatException('cursor since must be a string'),
        },
        workflowRunsSince: switch (json['workflow_runs_since']) {
          final String value => DateTime.parse(value).toUtc(),
          null => null,
          _ => throw const FormatException(
            'cursor workflow_runs_since must be a string',
          ),
        },
        etags: Map.unmodifiable(
          Map<String, Object?>.from(
            json['etags']! as Map,
          ).map((key, value) => MapEntry(key, value as String)),
        ),
        observationIds: List.unmodifiable(
          (json['observation_ids']! as List).cast<String>(),
        ),
        pullHeads: Map.unmodifiable(switch (json['pull_heads']) {
          null => const <String, String>{},
          final Map<Object?, Object?> value => Map<String, Object?>.from(
            value,
          ).map((key, value) => MapEntry(key, value! as String)),
          _ => throw const FormatException('cursor pull_heads must be a map'),
        }),
        pending: List.unmodifiable(switch (json['pending']) {
          null => const <PendingObservation>[],
          final List<Object?> value =>
            value
                .map(
                  (entry) => PendingObservation.fromJson(
                    Map<String, Object?>.from(entry! as Map),
                  ),
                )
                .toList(growable: false),
          _ => throw const FormatException('cursor pending must be a list'),
        }),
        issueWatches: Map.unmodifiable(switch (json['issue_watches']) {
          null => const <String, GitHubIssueWatchCursorRecord>{},
          final Map<Object?, Object?> value =>
            <String, GitHubIssueWatchCursorRecord>{
              for (final entry in Map<String, Object?>.from(value).entries)
                _issueWatchKey(
                  entry.key,
                ): GitHubIssueWatchCursorRecord.fromJson(
                  Map<String, Object?>.from(entry.value! as Map),
                ),
            },
          _ => throw const FormatException(
            'cursor issue_watches must be a map',
          ),
        }),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('malformed GitHub cursor collections', error);
    }
  }
}

/// The lower-cased `owner/repository#number` coordinate at [key].
///
/// LOUD rather than lenient: a key that is not a coordinate would key a
/// baseline nothing can ever look up again, so the watch would silently
/// re-emit every comment on every cycle — the exact failure the record
/// prevents. It shares [GitHubIssueWatch.isCoordinateKey] with the AUTHORING
/// side, so nothing can be written that this then refuses to read back.
String _issueWatchKey(String key) {
  if (!GitHubIssueWatch.isCoordinateKey(key)) {
    throw FormatException('malformed issue watch coordinate "$key"');
  }
  return key;
}

/// Relocation seam for loading and atomically replacing one seat cursor.
///
/// A relocated polling process supplies a centralized implementation while
/// retaining the normalized event and projection API.
abstract interface class GitHubCursorStore {
  /// Loads the seat cursor.
  Future<GitHubReconcilerCursor> load();

  /// Atomically replaces the seat cursor.
  Future<void> save(GitHubReconcilerCursor cursor);
}

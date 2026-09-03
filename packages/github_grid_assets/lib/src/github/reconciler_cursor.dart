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

/// Durable per-substation GitHub polling state.
class GitHubReconcilerCursor {
  /// Creates polling state.
  const GitHubReconcilerCursor({
    this.since,
    this.etags = const <String, String>{},
    this.observationIds = const <String>[],
    this.pullHeads = const <String, String>{},
    this.pending = const <PendingObservation>[],
  });

  /// Intake high-water mark.
  final DateTime? since;

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

  /// Returns an immutable copy with selected values replaced.
  GitHubReconcilerCursor copyWith({
    DateTime? since,
    bool clearSince = false,
    Map<String, String>? etags,
    List<String>? observationIds,
    Map<String, String>? pullHeads,
    List<PendingObservation>? pending,
  }) => GitHubReconcilerCursor(
    since: clearSince ? null : since ?? this.since,
    etags: Map.unmodifiable(etags ?? this.etags),
    observationIds: List.unmodifiable(observationIds ?? this.observationIds),
    pullHeads: Map.unmodifiable(pullHeads ?? this.pullHeads),
    pending: List.unmodifiable(pending ?? this.pending),
  );

  /// Encodes the versioned cursor document.
  ///
  /// `pull_heads` and `pending` are both ADDITIVE at version 1: a document
  /// written before either existed decodes with an empty value rather than being
  /// refused. The version is deliberately NOT bumped — [fromJson] throws on
  /// `version != 1`, so a bump would make every cursor already on disk at a live
  /// seat unloadable and stop that seat polling.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'since': since?.toUtc().toIso8601String(),
    'etags': etags,
    'observation_ids': observationIds,
    'pull_heads': pullHeads,
    'pending': pending.map((entry) => entry.toJson()).toList(),
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
          final List<Object?> value => value
              .map(
                (entry) => PendingObservation.fromJson(
                  Map<String, Object?>.from(entry! as Map),
                ),
              )
              .toList(growable: false),
          _ => throw const FormatException('cursor pending must be a list'),
        }),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('malformed GitHub cursor collections', error);
    }
  }
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

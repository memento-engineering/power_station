/// Durable per-substation GitHub polling state.
class GitHubReconcilerCursor {
  /// Creates polling state.
  const GitHubReconcilerCursor({
    this.since,
    this.etags = const <String, String>{},
    this.observationIds = const <String>[],
    this.pullHeads = const <String, String>{},
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

  /// Whether [id] has already been durably claimed.
  bool hasObserved(String id) => observationIds.contains(id);

  /// Claims [id], retaining the newest 512 identities.
  GitHubReconcilerCursor record(String id) {
    if (hasObserved(id)) return this;
    return copyWith(
      observationIds: <String>[id, ...observationIds].take(512).toList(),
    );
  }

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
  }) => GitHubReconcilerCursor(
    since: clearSince ? null : since ?? this.since,
    etags: Map.unmodifiable(etags ?? this.etags),
    observationIds: List.unmodifiable(observationIds ?? this.observationIds),
    pullHeads: Map.unmodifiable(pullHeads ?? this.pullHeads),
  );

  /// Encodes the versioned cursor document.
  ///
  /// `pull_heads` is ADDITIVE at version 1: a document written before the head
  /// cache existed decodes with an empty cache rather than being refused.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'since': since?.toUtc().toIso8601String(),
    'etags': etags,
    'observation_ids': observationIds,
    'pull_heads': pullHeads,
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

/// Durable per-substation GitHub polling state.
class GitHubReconcilerCursor {
  /// Creates polling state.
  const GitHubReconcilerCursor({
    this.since,
    this.etags = const <String, String>{},
    this.observationIds = const <String>[],
  });

  /// Intake high-water mark.
  final DateTime? since;

  /// Conditional response tags keyed by polling endpoint.
  final Map<String, String> etags;

  /// Newest-first bounded observation identity ledger.
  final List<String> observationIds;

  /// Whether [id] has already been durably claimed.
  bool hasObserved(String id) => observationIds.contains(id);

  /// Claims [id], retaining the newest 512 identities.
  GitHubReconcilerCursor record(String id) {
    if (hasObserved(id)) return this;
    return copyWith(
      observationIds: <String>[id, ...observationIds].take(512).toList(),
    );
  }

  /// Returns an immutable copy with selected values replaced.
  GitHubReconcilerCursor copyWith({
    DateTime? since,
    bool clearSince = false,
    Map<String, String>? etags,
    List<String>? observationIds,
  }) => GitHubReconcilerCursor(
    since: clearSince ? null : since ?? this.since,
    etags: Map.unmodifiable(etags ?? this.etags),
    observationIds: List.unmodifiable(observationIds ?? this.observationIds),
  );

  /// Encodes the versioned cursor document.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'since': since?.toUtc().toIso8601String(),
    'etags': etags,
    'observation_ids': observationIds,
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

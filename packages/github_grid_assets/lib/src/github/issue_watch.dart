import 'package:json_annotation/json_annotation.dart';

/// The kind of life event observed on a watched OUTBOUND issue.
///
/// The set is closed on purpose: it enumerates every terminal and
/// near-terminal state a watch can land in, so a watched issue can never go
/// quiet in a state nothing names. A comment is NOT here — it is its own
/// normalized variant.
enum GitHubIssueWatchChange {
  /// Closed with GitHub's `completed` reason (or with no reason at all).
  @JsonValue('closed_completed')
  closedCompleted('closed_completed'),

  /// Closed with GitHub's `not_planned` reason — the maintainer declined it.
  @JsonValue('closed_not_planned')
  closedNotPlanned('closed_not_planned'),

  /// Reopened after having been closed.
  @JsonValue('reopened')
  reopened('reopened'),

  /// The issue's LOCK state changed.
  ///
  /// One value covers `locked` and `unlocked` because the direction is not a
  /// separate KIND of event: the envelope's own `locked` flag carries it, and
  /// a second enum entry would let a reader trust the name over the flag.
  @JsonValue('locked')
  locked('locked'),

  /// Transferred to another repository — the coordinates we watch are dead.
  @JsonValue('transferred')
  transferred('transferred'),

  /// Deleted outright; GitHub answers `410` for it from then on.
  @JsonValue('deleted')
  deleted('deleted'),

  /// Converted into a discussion; there is no issue left to poll.
  @JsonValue('converted_to_discussion')
  convertedToDiscussion('converted_to_discussion'),

  /// No longer readable — the repository went private, or `404`s at us.
  ///
  /// Distinct from [deleted]: access may come back, so the watch keeps asking
  /// for the issue resource (and only that) until it does.
  @JsonValue('unreadable')
  unreadable('unreadable');

  const GitHubIssueWatchChange(this.wire);

  /// The stable wire spelling carried by envelopes, cursors and observation
  /// ids.
  final String wire;

  /// The change named by [wire]; an unknown spelling throws.
  static GitHubIssueWatchChange fromWire(String wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    throw FormatException('unsupported issue-watch change "$wire"');
  }
}

/// The actor a watch observation carries when GitHub named nobody.
///
/// A transition reported by the issue RESOURCE or by an HTTP status — a
/// transfer, a deletion, a repository that went private — has no login behind
/// it. It is never consulted for authority: ownership of a watch is decided by
/// the issue's AUTHOR, never by whoever moved it.
const String kIssueWatchResourceActor = 'github';

/// ONE outbound issue the station keeps watching after it was opened.
///
/// The station opens issues — its own, and the ones the operator files on its
/// ruling in repositories we do NOT control — and then goes blind: the
/// reconciler observes an issue being OPENED and never its life afterwards.
/// This value is the standing instruction to keep looking, and it carries the
/// ORIGINATING BEAD so an observation lands on the work that caused the issue
/// rather than on a fresh, unattached bead.
///
/// ```dart
/// const GitHubIssueWatch(
///   originatingBeadId: 'lunar_station-6p9',
///   owner: 'ricardoboss',
///   repository: 'radioactive_dart',
///   issueNumber: 1,
/// );
/// ```
class GitHubIssueWatch {
  /// Creates one watch entry.
  const GitHubIssueWatch({
    required this.originatingBeadId,
    required this.owner,
    required this.repository,
    required this.issueNumber,
  });

  /// The bead whose work caused this issue to be filed.
  final String originatingBeadId;

  /// The watched repository's owner, exactly as authored.
  final String owner;

  /// The watched repository's name, exactly as authored.
  final String repository;

  /// The watched issue's number.
  final int issueNumber;

  /// The lower-cased `owner/repository#number` this watch is keyed by.
  ///
  /// GitHub owners and repository names are case-INSENSITIVE, so a seat that
  /// authors `RicardoBoss/Radioactive_Dart` and one that authors
  /// `ricardoboss/radioactive_dart` must not accumulate two cursor records for
  /// one issue.
  String get coordinateKey =>
      '${owner.trim().toLowerCase()}/${repository.trim().toLowerCase()}'
      '#$issueNumber';

  /// Whether this watch names the seat's OWN repository — the lane split.
  ///
  /// An installed repository rides the App client and its installation token;
  /// everything else is FOREIGN and can only ever be read token-lessly,
  /// because a GitHub App cannot be installed on a third party's repository.
  bool isInstalledRepository({
    required String owner,
    required String repository,
  }) =>
      this.owner.trim().toLowerCase() == owner.trim().toLowerCase() &&
      this.repository.trim().toLowerCase() == repository.trim().toLowerCase();

  /// Whether [key] is a well-formed lower-cased `owner/repository#number`.
  ///
  /// The ONE home of the coordinate shape, so the seat that AUTHORS a watch and
  /// the cursor that DECODES one refuse exactly the same strings. A shape only
  /// the reader refused would be written happily and then make the whole cursor
  /// document unloadable — bricking the seat's polling for a typo.
  ///
  /// The repository segment deliberately admits a leading `.` or `_`: the org's
  /// own `memento-engineering/.github` is a real repository.
  static bool isCoordinateKey(String key) => _coordinatePattern.hasMatch(key);

  /// Refuses a watch that cannot address an issue or a bead.
  ///
  /// LOUD by design: a blank coordinate would poll `/repos//` forever and a
  /// blank bead id would project an observation onto nothing at all — both
  /// are wiring bugs at the seat that authored them, not runtime conditions.
  /// The coordinate SHAPE is checked here for the same reason: the cursor
  /// refuses a malformed key on load, so authoring one would write a document
  /// that can never be read back and would stop the seat polling entirely.
  void validate() {
    if (originatingBeadId.trim().isEmpty) {
      throw ArgumentError.value(
        originatingBeadId,
        'originatingBeadId',
        'must not be blank',
      );
    }
    if (owner.trim().isEmpty) {
      throw ArgumentError.value(owner, 'owner', 'must not be blank');
    }
    if (repository.trim().isEmpty) {
      throw ArgumentError.value(repository, 'repository', 'must not be blank');
    }
    if (issueNumber <= 0) {
      throw ArgumentError.value(issueNumber, 'issueNumber', 'must be positive');
    }
    if (!isCoordinateKey(coordinateKey)) {
      throw ArgumentError.value(
        coordinateKey,
        'coordinateKey',
        'must be a GitHub owner/repository pair',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GitHubIssueWatch &&
      other.originatingBeadId == originatingBeadId &&
      other.owner == owner &&
      other.repository == repository &&
      other.issueNumber == issueNumber;

  @override
  int get hashCode =>
      Object.hash(originatingBeadId, owner, repository, issueNumber);

  @override
  String toString() =>
      'GitHubIssueWatch($originatingBeadId, $owner/$repository#$issueNumber)';
}

/// A GitHub login, then a repository name, then a positive issue number.
final RegExp _coordinatePattern = RegExp(
  r'^[a-z0-9][a-z0-9-]*/[a-z0-9._-]+#[1-9][0-9]*$',
);

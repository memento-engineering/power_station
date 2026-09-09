import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import '../support/issue_watch_fixtures.dart';

/// The seat trust the binding builds: one human login plus the seat's own
/// workflow identity.
GitHubSelfTrust _trust() => GitHubSelfTrust(
  githubUser: kSelfLogin,
  repository: '$kSeatOwner/$kSeatRepository',
);

/// A trust that FAILS the test if it is asked about anything but the issue
/// author.
final class _AuthorOnlyTrust implements Trust {
  _AuthorOnlyTrust(this._author);
  final String _author;
  final List<ActorIdentity> asked = <ActorIdentity>[];

  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) async {
    asked.add(actor);
    return actor.scheme == 'github' && actor.id == _author
        ? TrustLevel.self
        : TrustLevel.external;
  }
}

/// An approval service that must never be reached from this leg.
final class _RefusingStore implements GitHubIntakeStore {
  @override
  Future<void> upsert(GitHubIntakeRecord record) =>
      throw StateError('a watch never files fresh intake');

  @override
  Future<void> appendIssueWatch(GitHubIssueWatchUpdate update) async {}
}

NormalizedGitHubEvent _comment({String issueAuthor = kSelfLogin}) =>
    NormalizedGitHubEvent.issueCommented(
      nodeId: 'IC_first',
      actor: 'ricardoboss',
      repository: 'ricardoboss/radioactive_dart',
      substation: kSubstation,
      observationId: 'poll:issue-comment:IC_first',
      originatingBeadId: 'lunar_station-6p9',
      issueNodeId: 'I_kwDO',
      issueAuthor: issueAuthor,
      issueNumber: 1,
      commentId: 11,
      body: 'The containment is intentional.',
      url: 'https://github.com/ricardoboss/radioactive_dart/issues/1',
      updatedAt: DateTime.utc(2026, 9, 9, 11),
    );

NormalizedGitHubEvent _stateChange({
  GitHubIssueWatchChange change = GitHubIssueWatchChange.closedNotPlanned,
  String state = 'closed',
  String? stateReason = 'not_planned',
  bool locked = false,
  String actor = 'ricardoboss',
}) => NormalizedGitHubEvent.watchedIssueStateChanged(
  nodeId: 'CE_closed',
  actor: actor,
  repository: 'ricardoboss/radioactive_dart',
  substation: kSubstation,
  observationId: 'poll:issue-state:CE_closed:${change.wire}',
  originatingBeadId: 'lunar_station-6p9',
  issueNodeId: 'I_kwDO',
  issueAuthor: kSelfLogin,
  issueNumber: 1,
  change: change,
  state: state,
  stateReason: stateReason,
  locked: locked,
  url: 'https://github.com/ricardoboss/radioactive_dart/issues/1',
  updatedAt: DateTime.utc(2026, 9, 9, 13),
);

void main() {
  test('the delivery leg is its own durable acknowledgement key', () {
    expect(kGitHubIssueWatchDeliveryLeg, 'issue-watch');
    expect(kGitHubIssueWatchDeliveryLeg, isNot(kCiFeedbackDeliveryLeg));
    expect(kGitHubIssueWatchDeliveryLeg, isNot(kSinkDeliveryLeg));
  });

  test('an external maintainer reply on OUR issue reaches the bead', () async {
    final store = RecordingIntakeStore();
    await GitHubIssueWatchProjection(trust: _trust(), store: store)(_comment());

    final update = store.watchUpdates.single;
    expect(update.beadId, 'lunar_station-6p9');
    expect(update.actor, 'ricardoboss');
    expect(update.change, kIssueWatchCommentedChange);
    expect(update.note, contains('new comment from @ricardoboss'));
    expect(update.note, contains('The containment is intentional.'));
    expect(
      update.metadata.containsKey('github.watch.state'),
      isFalse,
      reason: 'a comment observes no state, so it asserts none',
    );
    expect(
      update.unsetMetadata,
      isNot(contains('github.watch.state_reason')),
      reason: 'nor does it erase the state the last transition wrote',
    );
  });

  test('an issue somebody else opened is not ours to answer', () async {
    final store = RecordingIntakeStore();
    await GitHubIssueWatchProjection(trust: _trust(), store: store)(
      _comment(issueAuthor: 'someone-else'),
    );
    expect(store.watchUpdates, isEmpty);
  });

  test('only the ISSUE AUTHOR is asked for authority', () async {
    final trust = _AuthorOnlyTrust(kSelfLogin);
    await GitHubIssueWatchProjection(
      trust: trust,
      store: RecordingIntakeStore(),
    )(_comment());

    expect(trust.asked, hasLength(1));
    expect(trust.asked.single.scheme, 'github');
    expect(
      trust.asked.single.id,
      kSelfLogin,
      reason: 'promoting a commenter would invert the feature',
    );
  });

  test('a state change writes state, reason and change per key', () async {
    final store = RecordingIntakeStore();
    await GitHubIssueWatchProjection(trust: _trust(), store: store)(
      _stateChange(),
    );

    final update = store.watchUpdates.single;
    expect(update.metadata, <String, String>{
      'github.watch.repository': 'ricardoboss/radioactive_dart',
      'github.watch.issue_number': '1',
      'github.watch.issue_node_id': 'I_kwDO',
      'github.watch.last_observation':
          'poll:issue-state:CE_closed:closed_not_planned',
      'github.watch.change': 'closed_not_planned',
      'github.watch.updated_at': '2026-09-09T13:00:00.000Z',
      'github.watch.state': 'closed',
      'github.watch.state_reason': 'not_planned',
    });
    expect(update.note, contains('closed as not planned'));
    expect(update.note, contains('State: closed (not_planned)'));
  });

  test('a reopen UNSETS the reason it was closed with', () async {
    final store = RecordingIntakeStore();
    await GitHubIssueWatchProjection(trust: _trust(), store: store)(
      _stateChange(
        change: GitHubIssueWatchChange.reopened,
        state: 'open',
        stateReason: null,
      ),
    );

    final update = store.watchUpdates.single;
    expect(update.metadata.containsKey('github.watch.state_reason'), isFalse);
    expect(update.unsetMetadata, contains('github.watch.state_reason'));
  });

  test('every observation removes all three approval stamps', () async {
    final store = RecordingIntakeStore();
    final projection = GitHubIssueWatchProjection(
      trust: _trust(),
      store: store,
    );
    await projection(_comment());
    await projection(_stateChange());

    for (final update in store.watchUpdates) {
      expect(
        update.unsetMetadata,
        containsAll(<String>[
          'grid.approved_by',
          'grid.approved_at',
          'grid.approved_rev',
        ]),
      );
    }
  });

  test('an unattributed transition names no author in its note', () async {
    final store = RecordingIntakeStore();
    await GitHubIssueWatchProjection(trust: _trust(), store: store)(
      _stateChange(
        change: GitHubIssueWatchChange.unreadable,
        actor: kIssueWatchResourceActor,
      ),
    );

    final update = store.watchUpdates.single;
    expect(update.note, isNot(contains('By: @')));
    expect(update.note, contains('no longer readable'));
    expect(update.note, contains('the repository may have gone private'));
  });

  test('a lock change reads as locked or unlocked by its flag', () async {
    final store = RecordingIntakeStore();
    final projection = GitHubIssueWatchProjection(
      trust: _trust(),
      store: store,
    );
    await projection(
      _stateChange(
        change: GitHubIssueWatchChange.locked,
        state: 'open',
        stateReason: null,
        locked: true,
      ),
    );
    await projection(
      _stateChange(
        change: GitHubIssueWatchChange.locked,
        state: 'open',
        stateReason: null,
      ),
    );

    expect(store.watchUpdates.first.note, contains('#1: locked'));
    expect(store.watchUpdates.last.note, contains('#1: unlocked'));
  });

  test('non-watch variants never reach the store', () async {
    final projection = GitHubIssueWatchProjection(
      trust: _trust(),
      store: _RefusingStore(),
    );
    await projection(
      const NormalizedGitHubEvent.issueOpened(
        nodeId: 'I_1',
        actor: kSelfLogin,
        repository: '$kSeatOwner/$kSeatRepository',
        substation: kSubstation,
        observationId: 'poll:issue:I_1:2026-09-09T10:00:00Z',
        number: 7,
        title: 'An issue',
        body: '',
      ),
    );
    await projection(
      const NormalizedGitHubEvent.checkConcluded(
        nodeId: 'CR_1',
        actor: 'github-actions',
        repository: '$kSeatOwner/$kSeatRepository',
        substation: kSubstation,
        observationId: 'poll:check:CR_1',
        headBranch: 'grid/pow-1rn',
        checkName: 'test',
        conclusion: 'failure',
      ),
    );
  });
}

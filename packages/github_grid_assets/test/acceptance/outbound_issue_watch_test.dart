// pow-1rn.8 acceptance — the OUTBOUND issue watch, end to end and offline.
//
// AC-1 … AC-8 drive the real reconciler, the real cursor, the real read client
// and the real projection over Fakes: a fake HTTP transport that answers by
// path, an in-memory cursor store, and a recording `bd` runner. No network, no
// process, no mocks.

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

import '../support/issue_watch_fixtures.dart';

/// The seat's SELF-only trust, exactly as the binding builds it.
GitHubSelfTrust _trust() => GitHubSelfTrust(
  githubUser: kSelfLogin,
  repository: '$kSeatOwner/$kSeatRepository',
);

/// Counts installation-token requests so a lane can prove it made none.
final class _CountingTokens implements GitHubAppTokenProvider {
  int calls = 0;

  @override
  Future<String> accessToken() async {
    calls++;
    return 'installation-token';
  }
}

GitHubReadClient _readClient(
  GitHubHttpTransport transport, {
  String? token,
  GitHubReadScheduler? schedule,
}) => GitHubReadClient(
  transport: transport,
  apiBaseUri: Uri.parse('https://api.github.test'),
  personalToken: token,
  schedule: schedule,
);

/// A reconciler wired for one lane, collecting every emitted envelope.
({
  GitHubReconciler reconciler,
  List<NormalizedGitHubEvent> events,
  MemoryCursorStore cursors,
  _CountingTokens tokens,
})
_reconciler({
  required RouteTransport transport,
  required List<GitHubIssueWatch> watches,
  MemoryCursorStore? cursors,
  GitHubReadScheduler? schedule,
  String? token,
  bool withForeignClient = true,
}) {
  final events = <NormalizedGitHubEvent>[];
  final store = cursors ?? MemoryCursorStore();
  final tokens = _CountingTokens();
  final reconciler = GitHubReconciler(
    owner: kSeatOwner,
    repository: kSeatRepository,
    substation: kSubstation,
    client: GitHubAppClient(
      config: GitHubAppConfig(
        appId: 'app',
        installationId: 1,
        apiBaseUri: Uri.parse('https://api.github.test'),
      ),
      tokens: tokens,
      transport: transport,
    ),
    cursors: store,
    emit: (event) async => events.add(event),
    issueWatches: watches,
    foreignClient: withForeignClient
        ? _readClient(transport, token: token, schedule: schedule)
        : null,
  );
  return (
    reconciler: reconciler,
    events: events,
    cursors: store,
    tokens: tokens,
  );
}

void main() {
  group('AC-1 — a foreign comment is observed without installation auth', () {
    test(
      'AC-1 — every unseen comment is emitted oldest-first, token-lessly',
      () async {
        final transport = RouteTransport()
          ..on(issuePath(kForeignWatch), jsonResponse(issueBody()))
          ..on(
            timelinePath(kForeignWatch),
            jsonResponse(<Object?>[
              commentRow(
                id: 22,
                nodeId: 'IC_second',
                actor: 'ricardoboss',
                body: 'Second reply.',
                createdAt: '2026-09-09T12:00:00Z',
              ),
              commentRow(
                id: 11,
                nodeId: 'IC_first',
                actor: 'ricardoboss',
                body: 'First reply.',
                createdAt: '2026-09-09T11:00:00Z',
              ),
            ]),
          );
        final wired = _reconciler(
          transport: transport,
          watches: const <GitHubIssueWatch>[kForeignWatch],
        );

        await wired.reconciler.reconcileForeignIssueWatchesOnce();

        final comments = wired.events.whereType<IssueCommented>().toList();
        expect(
          comments.map((event) => event.body),
          <String>['First reply.', 'Second reply.'],
          reason: 'a recorded page is unordered; the leg orders it',
        );
        expect(comments.first.originatingBeadId, 'lunar_station-6p9');
        expect(comments.first.issueAuthor, kSelfLogin);
        expect(comments.first.repository, 'ricardoboss/radioactive_dart');
        expect(comments.map((event) => event.observationId), <String>[
          'poll:issue-comment:IC_first',
          'poll:issue-comment:IC_second',
        ]);

        expect(
          wired.tokens.calls,
          0,
          reason: 'no installation exists on a foreign repository',
        );
        for (final request in transport.requests) {
          expect(request.method, 'GET');
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(request.headers['Accept'], 'application/vnd.github+json');
          expect(request.headers['X-GitHub-Api-Version'], '2022-11-28');
        }
      },
    );

    test(
      'AC-1 — a configured personal token buys rate limit, not authority',
      () async {
        final transport = RouteTransport()
          ..on(issuePath(kForeignWatch), jsonResponse(issueBody()))
          ..on(timelinePath(kForeignWatch), jsonResponse(<Object?>[]));
        final wired = _reconciler(
          transport: transport,
          watches: const <GitHubIssueWatch>[kForeignWatch],
          token: 'personal',
        );

        await wired.reconciler.reconcileForeignIssueWatchesOnce();

        expect(
          transport.requests.first.headers['Authorization'],
          'Bearer personal',
        );
        expect(wired.tokens.calls, 0);
      },
    );
  });

  group('AC-2 — the terminal and near-terminal matrix', () {
    /// A watch already at its baseline, so a later poll has identity to work
    /// from.
    GitHubReconcilerCursor baseline({
      String state = 'open',
      String? stateReason,
      bool locked = false,
      int lastTimelineEventId = 0,
    }) => const GitHubReconcilerCursor().recordIssueWatch(
      kForeignWatch.coordinateKey,
      GitHubIssueWatchCursorRecord(
        issueNodeId: 'I_kwDO',
        issueAuthor: kSelfLogin,
        lastCommentId: 0,
        lastTimelineEventId: lastTimelineEventId,
        lastState: state,
        lastStateReason: stateReason,
        locked: locked,
        lastUpdatedAt: DateTime.utc(2026, 9, 9, 10),
        lastChange: null,
      ),
    );

    Future<List<NormalizedGitHubEvent>> drive(
      RouteTransport transport, {
      GitHubReconcilerCursor? cursor,
    }) async {
      final wired = _reconciler(
        transport: transport,
        watches: const <GitHubIssueWatch>[kForeignWatch],
        cursors: MemoryCursorStore(cursor ?? baseline()),
      );
      await wired.reconciler.reconcileForeignIssueWatchesOnce();
      return wired.events;
    }

    test(
      'AC-2 — closed as completed and closed as not planned differ',
      () async {
        for (final (reason, expected) in <(String?, GitHubIssueWatchChange)>[
          (null, GitHubIssueWatchChange.closedCompleted),
          ('completed', GitHubIssueWatchChange.closedCompleted),
          ('not_planned', GitHubIssueWatchChange.closedNotPlanned),
        ]) {
          final transport = RouteTransport()
            ..on(
              issuePath(kForeignWatch),
              jsonResponse(
                issueBody(
                  state: 'closed',
                  stateReason: reason,
                  updatedAt: '2026-09-09T13:00:00Z',
                  closedBy: 'ricardoboss',
                ),
              ),
            )
            ..on(
              timelinePath(kForeignWatch),
              jsonResponse(<Object?>[
                eventRow(
                  event: 'closed',
                  id: 91,
                  nodeId: 'CE_closed',
                  stateReason: reason,
                ),
              ]),
            );
          final events = await drive(transport);
          final change = events.whereType<WatchedIssueStateChanged>().single;
          expect(change.change, expected, reason: 'state_reason $reason');
          expect(change.state, 'closed');
          expect(
            change.observationId,
            'poll:issue-state:CE_closed:${expected.wire}',
          );
        }
      },
    );

    test('AC-2 — reopened and lock changes are observed', () async {
      final transport = RouteTransport()
        ..on(
          issuePath(kForeignWatch),
          jsonResponse(
            issueBody(locked: true, updatedAt: '2026-09-09T14:00:00Z'),
          ),
        )
        ..on(
          timelinePath(kForeignWatch),
          jsonResponse(<Object?>[
            eventRow(
              event: 'reopened',
              id: 92,
              nodeId: 'CE_reopened',
              createdAt: '2026-09-09T13:00:00Z',
            ),
            eventRow(
              event: 'locked',
              id: 93,
              nodeId: 'CE_locked',
              createdAt: '2026-09-09T14:00:00Z',
            ),
          ]),
        );
      final events = await drive(
        transport,
        cursor: baseline(state: 'closed', stateReason: 'completed'),
      );
      final changes = events.whereType<WatchedIssueStateChanged>().toList();
      expect(changes.map((event) => event.change), <GitHubIssueWatchChange>[
        GitHubIssueWatchChange.reopened,
        GitHubIssueWatchChange.locked,
      ]);
      expect(changes.first.state, 'open');
      expect(changes.first.locked, isFalse);
      expect(changes.last.locked, isTrue);
    });

    test('AC-2 — an unlock is observed and carries its direction', () async {
      final transport = RouteTransport()
        ..on(
          issuePath(kForeignWatch),
          jsonResponse(issueBody(updatedAt: '2026-09-09T15:00:00Z')),
        )
        ..on(
          timelinePath(kForeignWatch),
          jsonResponse(<Object?>[
            eventRow(event: 'unlocked', id: 94, nodeId: 'CE_unlocked'),
          ]),
        );
      final events = await drive(transport, cursor: baseline(locked: true));
      final change = events.whereType<WatchedIssueStateChanged>().single;
      expect(change.change, GitHubIssueWatchChange.locked);
      expect(change.locked, isFalse, reason: 'the flag carries the direction');
    });

    test('AC-2 — converted to a discussion is terminal', () async {
      final transport = RouteTransport()
        ..on(issuePath(kForeignWatch), jsonResponse(issueBody()))
        ..on(
          timelinePath(kForeignWatch),
          jsonResponse(<Object?>[
            eventRow(
              event: 'converted_to_discussion',
              id: 95,
              nodeId: 'CE_converted',
            ),
          ]),
        );
      final wired = _reconciler(
        transport: transport,
        watches: const <GitHubIssueWatch>[kForeignWatch],
        cursors: MemoryCursorStore(baseline()),
      );
      await wired.reconciler.reconcileForeignIssueWatchesOnce();
      expect(
        wired.events.whereType<WatchedIssueStateChanged>().single.change,
        GitHubIssueWatchChange.convertedToDiscussion,
      );

      final before = transport.requests.length;
      await wired.reconciler.reconcileForeignIssueWatchesOnce();
      expect(
        transport.requests.length,
        before,
        reason: 'a converted watch stops asking',
      );
    });

    test('AC-2 — 301 transferred and 410 deleted are terminal', () async {
      for (final (status, expected) in <(int, GitHubIssueWatchChange)>[
        (301, GitHubIssueWatchChange.transferred),
        (410, GitHubIssueWatchChange.deleted),
      ]) {
        final transport = RouteTransport()
          ..on(issuePath(kForeignWatch), jsonResponse('', status: status));
        final wired = _reconciler(
          transport: transport,
          watches: const <GitHubIssueWatch>[kForeignWatch],
          cursors: MemoryCursorStore(baseline()),
        );
        await wired.reconciler.reconcileForeignIssueWatchesOnce();
        final change = wired.events
            .whereType<WatchedIssueStateChanged>()
            .single;
        expect(change.change, expected);
        expect(
          change.observationId,
          'poll:issue-state:I_kwDO:$status:${expected.wire}',
        );
        expect(transport.paths, <String>[
          issuePath(kForeignWatch),
        ], reason: 'a dead resource has no timeline to read');

        await wired.reconciler.reconcileForeignIssueWatchesOnce();
        expect(transport.requests, hasLength(1), reason: 'terminal stops');
      }
    });

    test(
      'AC-2 — 404 is unreadable, retries the resource, and recovers',
      () async {
        final transport = RouteTransport()
          ..on(issuePath(kForeignWatch), jsonResponse('', status: 404))
          ..on(issuePath(kForeignWatch), jsonResponse('', status: 404))
          ..on(issuePath(kForeignWatch), jsonResponse(issueBody()))
          ..on(timelinePath(kForeignWatch), jsonResponse(<Object?>[]));
        final wired = _reconciler(
          transport: transport,
          watches: const <GitHubIssueWatch>[kForeignWatch],
          cursors: MemoryCursorStore(baseline()),
        );

        await wired.reconciler.reconcileForeignIssueWatchesOnce();
        final unreadable = wired.events
            .whereType<WatchedIssueStateChanged>()
            .single;
        expect(unreadable.change, GitHubIssueWatchChange.unreadable);
        expect(unreadable.url, isNull);
        expect(transport.paths, <String>[issuePath(kForeignWatch)]);

        await wired.reconciler.reconcileForeignIssueWatchesOnce();
        expect(
          wired.events.whereType<WatchedIssueStateChanged>(),
          hasLength(1),
          reason: 'an unchanged refusal is not a second observation',
        );
        expect(transport.paths, <String>[
          issuePath(kForeignWatch),
          issuePath(kForeignWatch),
        ], reason: 'unreadable retries ONLY the issue resource');

        await wired.reconciler.reconcileForeignIssueWatchesOnce();
        expect(
          transport.paths.last,
          timelinePath(kForeignWatch),
          reason: 'access returned; comment polling resumes',
        );
        expect(
          wired
              .cursors
              .cursor
              .issueWatches[kForeignWatch.coordinateKey]!
              .lastChange,
          isNull,
          reason: 'a successful read clears the stale unreadable',
        );
      },
    );

    test('AC-2 — a status transition before any baseline throws', () async {
      final transport = RouteTransport()
        ..on(issuePath(kForeignWatch), jsonResponse('', status: 404));
      final wired = _reconciler(
        transport: transport,
        watches: const <GitHubIssueWatch>[kForeignWatch],
      );
      await expectLater(
        wired.reconciler.reconcileForeignIssueWatchesOnce(),
        throwsA(isA<GitHubPollException>()),
      );
      expect(wired.events, isEmpty);
    });

    test('AC-2 — a closed watch keeps polling for comments', () async {
      final transport = RouteTransport()
        ..on(
          issuePath(kForeignWatch),
          jsonResponse(issueBody(state: 'closed', stateReason: 'completed')),
        )
        ..on(
          timelinePath(kForeignWatch),
          jsonResponse(<Object?>[
            commentRow(
              id: 30,
              nodeId: 'IC_after_close',
              actor: 'ricardoboss',
              body: 'Reopening this later.',
            ),
          ]),
        );
      final events = await drive(
        transport,
        cursor: baseline(state: 'closed', stateReason: 'completed'),
      );
      expect(events.whereType<IssueCommented>(), hasLength(1));
    });
  });

  group('AC-3 — the installed lane emits the same envelopes', () {
    test(
      'AC-3 — installed and foreign envelopes match field for field',
      () async {
        Future<NormalizedGitHubEvent> observe(GitHubIssueWatch watch) async {
          final transport = RouteTransport()
            ..on(
              '/repos/$kSeatOwner/$kSeatRepository/issues',
              jsonResponse('', status: 304),
            )
            ..on(
              '/repos/$kSeatOwner/$kSeatRepository/pulls',
              jsonResponse('', status: 304),
            )
            ..on(issuePath(watch), jsonResponse(issueBody()))
            ..on(
              timelinePath(watch),
              jsonResponse(<Object?>[
                commentRow(
                  id: 11,
                  nodeId: 'IC_first',
                  actor: 'ricardoboss',
                  body: 'One reply.',
                ),
              ]),
            );
          final wired = _reconciler(
            transport: transport,
            watches: <GitHubIssueWatch>[watch],
          );
          await wired.reconciler.reconcileOnce();
          return wired.events.whereType<IssueCommented>().single;
        }

        final foreign = await observe(kForeignWatch);
        final installed = await observe(kInstalledWatch);
        expect(
          (installed.toJson()
            ..remove('repository')
            ..remove('originatingBeadId')),
          (foreign.toJson()
            ..remove('repository')
            ..remove('originatingBeadId')),
        );
        expect(
          GitHubReconcilerCursor.observationIdOf(installed),
          GitHubReconcilerCursor.observationIdOf(foreign),
        );
      },
    );

    test('AC-3 — an installed watch rides the App client', () async {
      final transport = RouteTransport()
        ..on(
          '/repos/$kSeatOwner/$kSeatRepository/issues',
          jsonResponse('', status: 304),
        )
        ..on(
          '/repos/$kSeatOwner/$kSeatRepository/pulls',
          jsonResponse('', status: 304),
        )
        ..on(issuePath(kInstalledWatch), jsonResponse(issueBody()))
        ..on(timelinePath(kInstalledWatch), jsonResponse(<Object?>[]));
      final wired = _reconciler(
        transport: transport,
        watches: const <GitHubIssueWatch>[kInstalledWatch],
        withForeignClient: false,
      );

      await wired.reconciler.reconcileOnce();

      final watchRequests = transport.requests.where(
        (request) => request.uri.path.contains('/issues/1'),
      );
      expect(watchRequests, isNotEmpty);
      for (final request in watchRequests) {
        expect(request.headers['Authorization'], 'Bearer installation-token');
      }
    });

    test('AC-3 — a foreign watch with no read client is refused loudly', () {
      expect(
        () => _reconciler(
          transport: RouteTransport(),
          watches: const <GitHubIssueWatch>[kForeignWatch],
          withForeignClient: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AC-4 — the foreign lane has its own rate budget', () {
    test(
      'AC-4 — token-less starts are spaced under the dedicated key',
      () async {
        var now = DateTime.utc(2026, 9, 9);
        final waits = <Duration>[];
        final keys = <String>[];
        final coordinator = GitHubPollCoordinator(
          minimumSpacing: kUnauthenticatedGitHubMinimumSpacing,
          now: () => now,
          delay: (duration) async {
            waits.add(duration);
            now = now.add(duration);
          },
        );
        final transport = RouteTransport()
          ..on(issuePath(kForeignWatch), jsonResponse(issueBody()))
          ..on(timelinePath(kForeignWatch), jsonResponse(<Object?>[]));
        final wired = _reconciler(
          transport: transport,
          watches: const <GitHubIssueWatch>[kForeignWatch],
          schedule: (request) {
            keys.add(kForeignIssueWatchRateKey);
            return coordinator.schedule(kForeignIssueWatchRateKey, request);
          },
        );

        await wired.reconciler.reconcileForeignIssueWatchesOnce();

        expect(keys, everyElement('foreign/issue-watch'));
        expect(keys, hasLength(2), reason: 'the resource and its timeline');
        expect(waits, <Duration>[kUnauthenticatedGitHubMinimumSpacing]);
        expect(kUnauthenticatedGitHubMinimumSpacing.inSeconds, 65);
      },
    );

    test(
      'AC-4 — an installed start neither waits on nor spends that budget',
      () async {
        var now = DateTime.utc(2026, 9, 9);
        final waits = <Duration>[];
        final coordinator = GitHubPollCoordinator(
          minimumSpacing: kUnauthenticatedGitHubMinimumSpacing,
          now: () => now,
          delay: (duration) async {
            waits.add(duration);
            now = now.add(duration);
          },
        );
        await coordinator.schedule(
          kForeignIssueWatchRateKey,
          () async => 'first',
        );
        final installed = await coordinator.schedule(
          'installation-1',
          () async => 'installed',
        );
        expect(installed, 'installed');
        expect(waits, isEmpty, reason: 'a different key has its own clock');

        await coordinator.schedule(
          kForeignIssueWatchRateKey,
          () async => 'again',
        );
        expect(waits, <Duration>[kUnauthenticatedGitHubMinimumSpacing]);
      },
    );
  });

  group('AC-5 — projection onto the originating bead', () {
    test(
      'AC-5 — an external maintainer reply reaches lunar_station-6p9',
      () async {
        final store = RecordingIntakeStore();
        final projection = GitHubIssueWatchProjection(
          trust: _trust(),
          store: store,
        );
        final transport = RouteTransport()
          ..on(issuePath(kForeignWatch), jsonResponse(issueBody()))
          ..on(
            timelinePath(kForeignWatch),
            jsonResponse(<Object?>[
              commentRow(
                id: 11,
                nodeId: 'IC_first',
                actor: 'ricardoboss',
                body: 'The workspace containment is intentional.',
              ),
            ]),
          );
        final wired = _reconciler(
          transport: transport,
          watches: const <GitHubIssueWatch>[kForeignWatch],
        );
        wired.reconciler.addObserver(
          kGitHubIssueWatchDeliveryLeg,
          projection.call,
        );

        await wired.reconciler.reconcileForeignIssueWatchesOnce();

        final update = store.watchUpdates.single;
        expect(update.beadId, 'lunar_station-6p9');
        expect(update.repository, 'ricardoboss/radioactive_dart');
        expect(update.issueNumber, 1);
        expect(update.actor, 'ricardoboss');
        expect(update.change, kIssueWatchCommentedChange);
        expect(
          update.note,
          contains('The workspace containment is intentional.'),
        );
        expect(
          update.unsetMetadata,
          containsAll(<String>[
            'grid.approved_by',
            'grid.approved_at',
            'grid.approved_rev',
          ]),
        );
      },
    );

    test('AC-5 — an externally authored issue writes nothing', () async {
      final store = RecordingIntakeStore();
      final projection = GitHubIssueWatchProjection(
        trust: _trust(),
        store: store,
      );
      final transport = RouteTransport()
        ..on(
          issuePath(kForeignWatch),
          jsonResponse(issueBody(author: 'someone-else')),
        )
        ..on(
          timelinePath(kForeignWatch),
          jsonResponse(<Object?>[
            commentRow(
              id: 11,
              nodeId: 'IC_first',
              actor: 'ricardoboss',
              body: 'Not ours.',
            ),
          ]),
        );
      final wired = _reconciler(
        transport: transport,
        watches: const <GitHubIssueWatch>[kForeignWatch],
      );
      wired.reconciler.addObserver(
        kGitHubIssueWatchDeliveryLeg,
        projection.call,
      );

      await wired.reconciler.reconcileForeignIssueWatchesOnce();

      expect(wired.events.whereType<IssueCommented>(), hasLength(1));
      expect(store.watchUpdates, isEmpty);
    });

    test(
      'AC-5 — the store update is one OPEN bd update with no approval',
      () async {
        final runner = RecordingBdRunner();
        final projection = GitHubIssueWatchProjection(
          trust: _trust(),
          store: BdGitHubIntakeStore(runner),
        );
        await projection(
          NormalizedGitHubEvent.watchedIssueStateChanged(
            nodeId: 'CE_closed',
            actor: 'ricardoboss',
            repository: 'ricardoboss/radioactive_dart',
            substation: kSubstation,
            observationId: 'poll:issue-state:CE_closed:closed_not_planned',
            originatingBeadId: 'lunar_station-6p9',
            issueNodeId: 'I_kwDO',
            issueAuthor: kSelfLogin,
            issueNumber: 1,
            change: GitHubIssueWatchChange.closedNotPlanned,
            state: 'closed',
            stateReason: 'not_planned',
            locked: false,
            url: 'https://github.com/ricardoboss/radioactive_dart/issues/1',
            updatedAt: DateTime.utc(2026, 9, 9, 13),
          ),
        );

        expect(
          runner.argvs,
          hasLength(1),
          reason: 'ONE update, no second store',
        );
        final argv = runner.argvs.single;
        expect(argv.take(2), <String>['update', 'lunar_station-6p9']);
        expect(argv, containsAllInOrder(<String>['--status', 'open']));
        expect(
          argv,
          containsAllInOrder(<String>[
            '--set-metadata',
            'github.watch.change=closed_not_planned',
          ]),
        );
        expect(
          argv,
          containsAllInOrder(<String>[
            '--set-metadata',
            'github.watch.state_reason=not_planned',
          ]),
        );
        for (final key in <String>[
          'grid.approved_by',
          'grid.approved_at',
          'grid.approved_rev',
        ]) {
          expect(argv, containsAllInOrder(<String>['--unset-metadata', key]));
        }
        expect(argv, isNot(contains('--acceptance')));
      },
    );
  });

  group('AC-6 — cursor upgrade and durable replay', () {
    test('AC-6 — watch state is additive at version one and round-trips', () {
      const legacy = <String, Object?>{
        'version': 1,
        'since': null,
        'etags': <String, Object?>{},
        'observation_ids': <Object?>[],
      };
      final upgraded = GitHubReconcilerCursor.fromJson(legacy);
      expect(upgraded.issueWatches, isEmpty);

      final recorded = upgraded.recordIssueWatch(
        kForeignWatch.coordinateKey,
        GitHubIssueWatchCursorRecord(
          issueNodeId: 'I_kwDO',
          issueAuthor: kSelfLogin,
          lastCommentId: 11,
          lastTimelineEventId: 91,
          lastState: 'closed',
          lastStateReason: 'not_planned',
          locked: true,
          lastUpdatedAt: DateTime.utc(2026, 9, 9, 13),
          lastChange: GitHubIssueWatchChange.closedNotPlanned,
        ),
        issueEtag: '"issue"',
        timelineEtag: '"timeline"',
      );
      final round = GitHubReconcilerCursor.fromJson(recorded.toJson());
      expect(round.toJson(), recorded.toJson());
      expect(round.toJson()['version'], 1);
      expect(
        round.etags['issue-watch/ricardoboss/radioactive_dart#1/issue'],
        '"issue"',
      );
      expect(
        round.etags['issue-watch/ricardoboss/radioactive_dart#1/timeline'],
        '"timeline"',
      );
    });

    test(
      'AC-6 — a pending watch observation replays with per-leg acks',
      () async {
        final event = NormalizedGitHubEvent.issueCommented(
          nodeId: 'IC_first',
          actor: 'ricardoboss',
          repository: 'ricardoboss/radioactive_dart',
          substation: kSubstation,
          observationId: 'poll:issue-comment:IC_first',
          originatingBeadId: 'lunar_station-6p9',
          issueNodeId: 'I_kwDO',
          issueAuthor: kSelfLogin,
          issueNumber: 1,
          commentId: 11,
          body: 'A reply nobody acknowledged yet.',
          url: 'https://github.com/ricardoboss/radioactive_dart/issues/1',
          updatedAt: DateTime.utc(2026, 9, 9, 11),
        );
        final cursors = MemoryCursorStore(
          const GitHubReconcilerCursor()
              .enqueue(event)
              .ack('poll:issue-comment:IC_first', kSinkDeliveryLeg),
        );
        final transport = RouteTransport()
          ..on(issuePath(kForeignWatch), jsonResponse(issueBody()))
          ..on(timelinePath(kForeignWatch), jsonResponse(<Object?>[]));
        final wired = _reconciler(
          transport: transport,
          watches: const <GitHubIssueWatch>[kForeignWatch],
          cursors: cursors,
        );
        final delivered = <NormalizedGitHubEvent>[];
        var failures = 0;
        wired.reconciler.addObserver(kGitHubIssueWatchDeliveryLeg, (
          value,
        ) async {
          if (failures++ == 0) throw StateError('leg is down');
          delivered.add(value);
        });

        await expectLater(
          wired.reconciler.reconcileForeignIssueWatchesOnce(),
          throwsStateError,
        );
        expect(
          cursors.cursor.isPending('poll:issue-comment:IC_first'),
          isTrue,
          reason: 'a failed leg leaves the observation pending',
        );
        expect(
          wired.events,
          isEmpty,
          reason: 'the sink already acked; it is not re-driven',
        );

        await wired.reconciler.reconcileForeignIssueWatchesOnce();
        expect(delivered.single.observationId, 'poll:issue-comment:IC_first');
        expect(
          cursors.cursor.hasObserved('poll:issue-comment:IC_first'),
          isTrue,
        );
        expect(cursors.cursor.pending, isEmpty);
      },
    );

    test('AC-6 — a dropped watch loses its record and both tags', () {
      final recorded = const GitHubReconcilerCursor().recordIssueWatch(
        kForeignWatch.coordinateKey,
        GitHubIssueWatchCursorRecord(
          issueNodeId: 'I_kwDO',
          issueAuthor: kSelfLogin,
          lastCommentId: 0,
          lastTimelineEventId: 0,
          lastState: 'open',
          lastStateReason: null,
          locked: false,
          lastUpdatedAt: DateTime.utc(2026, 9, 9, 10),
          lastChange: null,
        ),
        issueEtag: '"issue"',
        timelineEtag: '"timeline"',
      );
      final pruned = recorded.retainIssueWatches(const <GitHubIssueWatch>[]);
      expect(pruned.issueWatches, isEmpty);
      expect(pruned.etags, isEmpty);
    });
  });

  group('AC-7 — the feature is off by default', () {
    test('AC-7 — an empty watch list makes no watch request', () async {
      const config = GitHubReconcilerConfig(
        owner: kSeatOwner,
        repository: kSeatRepository,
        substation: kSubstation,
        installationId: 'installation',
      );
      expect(config.issueWatches, isEmpty);
      expect(config.foreignReadTokenVariable, isNull);
      expect(
        config.foreignMinimumSpacing,
        kUnauthenticatedGitHubMinimumSpacing,
      );

      final transport = RouteTransport()
        ..on(
          '/repos/$kSeatOwner/$kSeatRepository/issues',
          jsonResponse('', status: 304),
        )
        ..on(
          '/repos/$kSeatOwner/$kSeatRepository/pulls',
          jsonResponse('', status: 304),
        );
      final wired = _reconciler(
        transport: transport,
        watches: config.issueWatches,
        withForeignClient: false,
      );

      await wired.reconciler.reconcileOnce();

      expect(
        transport.paths.where((path) => path.contains('/issues/')),
        isEmpty,
      );
      expect(
        transport.paths.where((path) => path.endsWith('/timeline')),
        isEmpty,
      );
      expect(wired.cursors.saves, 0, reason: 'nothing changed to save');
    });
  });

  group('AC-8 — generated variants and exhaustive routing', () {
    test('AC-8 — both variants round-trip and carry an observation id', () {
      final events = <NormalizedGitHubEvent>[
        NormalizedGitHubEvent.issueCommented(
          nodeId: 'IC_first',
          actor: 'ricardoboss',
          repository: 'ricardoboss/radioactive_dart',
          substation: kSubstation,
          observationId: 'poll:issue-comment:IC_first',
          originatingBeadId: 'lunar_station-6p9',
          issueNodeId: 'I_kwDO',
          issueAuthor: kSelfLogin,
          issueNumber: 1,
          commentId: 11,
          body: 'Reply.',
          url: 'https://github.com/ricardoboss/radioactive_dart/issues/1',
          updatedAt: DateTime.utc(2026, 9, 9, 11),
        ),
        NormalizedGitHubEvent.watchedIssueStateChanged(
          nodeId: 'CE_closed',
          actor: 'ricardoboss',
          repository: 'ricardoboss/radioactive_dart',
          substation: kSubstation,
          observationId: 'poll:issue-state:CE_closed:closed_completed',
          originatingBeadId: 'lunar_station-6p9',
          issueNodeId: 'I_kwDO',
          issueAuthor: kSelfLogin,
          issueNumber: 1,
          change: GitHubIssueWatchChange.closedCompleted,
          state: 'closed',
          stateReason: null,
          locked: false,
          url: null,
          updatedAt: DateTime.utc(2026, 9, 9, 13),
        ),
      ];
      for (final event in events) {
        expect(NormalizedGitHubEvent.fromJson(event.toJson()), event);
        expect(GitHubReconcilerCursor.observationIdOf(event), isNotEmpty);
      }
    });

    test(
      'AC-8 — every exhaustive adapter routes watch events to ONE leg',
      () async {
        final store = RecordingIntakeStore();
        final watch = GitHubIssueWatchProjection(trust: _trust(), store: store);
        final intake = GitHubIntakeProjection(trust: _trust(), store: store);
        final event = NormalizedGitHubEvent.watchedIssueStateChanged(
          nodeId: 'CE_closed',
          actor: 'ricardoboss',
          repository: 'ricardoboss/radioactive_dart',
          substation: kSubstation,
          observationId: 'poll:issue-state:CE_closed:closed_completed',
          originatingBeadId: 'lunar_station-6p9',
          issueNodeId: 'I_kwDO',
          issueAuthor: kSelfLogin,
          issueNumber: 1,
          change: GitHubIssueWatchChange.closedCompleted,
          state: 'closed',
          stateReason: null,
          locked: false,
          url: null,
          updatedAt: DateTime.utc(2026, 9, 9, 13),
        );

        await intake(event);
        expect(store.records, isEmpty, reason: 'intake never files a watch');

        await projectCiFeedback(null, event);
        await projectIssueWatch(null, event);
        expect(
          store.watchUpdates,
          isEmpty,
          reason: 'a null projection is inert',
        );

        await projectIssueWatch(watch, event);
        expect(store.watchUpdates, hasLength(1));
      },
    );
  });
}

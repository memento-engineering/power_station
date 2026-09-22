import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'real_bd_store.dart';

/// The lifecycle of the REAL bd fixture store, measured against a real binary.
///
/// The filing suites prove what the verbs do with a store. This one proves the
/// store itself: that it stops the servers it started before deleting the data
/// directory they hold, that it cannot be captured by a server some earlier run
/// abandoned, and that a failure against it names what it was bound to. Each is
/// a defect this fixture actually shipped — an orphaned `dolt sql-server` sat
/// over a deleted temp store on the station host for six days, and every fresh
/// store that bound to it failed with a refusal naming neither.
void main() {
  group('the real bd fixture store', () {
    test(
      'AC-1 — teardown awaits every proxied store process before delete',
      () async {
        final store = await bdStore(prefix: 'reaped');
        final identity = bdStoreIdentity(store);
        expect(
          await bdStoreProcesses(store),
          isNotEmpty,
          reason: 'a freshly initialized store must be serving: $identity',
        );

        await tearDownBdStore(store);

        // The delete is the LAST thing, and it is only correct if nothing is
        // still holding the data directory when it runs — so all three are
        // asserted, not just the directory a passing teardown already removed.
        expect(store.existsSync(), isFalse, reason: '$identity');
        expect(
          _alive(identity.proxyPid),
          isFalse,
          reason: 'the proxy outlived the store: $identity',
        );
        expect(
          _alive(identity.doltPid),
          isFalse,
          reason: 'the Dolt server outlived the store: $identity',
        );
        expect(
          await bdStoreProcesses(store),
          isEmpty,
          reason: 'a store process survived teardown: $identity',
        );
      },
      skip: skipWithoutBd,
    );

    test(
      'AC-2 — a deleted stale store cannot capture a fresh store',
      () async {
        final stale = await bdStore(prefix: 'stale');
        final staleIdentity = bdStoreIdentity(stale);
        // Deleted WITHOUT stopping its servers: the leak this fixture shipped,
        // reproduced deliberately so the isolation below is measured against
        // the real hazard rather than against an idle host.
        stale.deleteSync(recursive: true);
        expect(
          _alive(staleIdentity.proxyPid) || _alive(staleIdentity.doltPid),
          isTrue,
          reason: 'the leak under test did not reproduce: $staleIdentity',
        );

        final fresh = await bdStore(prefix: 'fresh');
        final freshIdentity = bdStoreIdentity(fresh);
        // The write is the proof: a store bound to the stale server refuses
        // here with `issue_prefix config is missing`, because that server
        // knows nothing of this store's prefix.
        await runBd(fresh, const [
          'create',
          '--id',
          'fresh-one',
          '--title',
          'fresh',
          '--type',
          'task',
          '--actor',
          'test',
        ]);

        // The READ is the other half of the proof. A write that landed
        // somewhere else still exits zero; only reading the bead back out of
        // THIS store's path — through the production client, not the fixture's
        // own `bd` argv — shows the fresh store answering for itself.
        final beads = await BdCliService(
          ProcessBdRunner(workspaceRoot: fresh.path),
        ).query('id=fresh-one');
        expect(
          [for (final bead in beads) bead.id],
          ['fresh-one'],
          reason: 'the fresh store answered for another store: $freshIdentity',
        );

        expect(freshIdentity.storePath, isNot(staleIdentity.storePath));
        expect(freshIdentity.configPath, isNot(staleIdentity.configPath));
        expect(freshIdentity.rootPath, isNot(staleIdentity.rootPath));
        expect(freshIdentity.proxyPid, isNot(staleIdentity.proxyPid));
        expect(freshIdentity.proxyPort, isNot(staleIdentity.proxyPort));
        expect(freshIdentity.doltPid, isNot(staleIdentity.doltPid));
        expect(freshIdentity.doltPort, isNot(staleIdentity.doltPort));

        final serving = await bdStoreProcesses(fresh);
        expect(
          serving.map((row) => row.pid),
          containsAll(<int>[freshIdentity.proxyPid, freshIdentity.doltPid]),
          reason: 'the fresh store is not served by its own pair: $serving',
        );
        for (final row in serving) {
          expect(row.command, contains(freshIdentity.storePath));
          expect(row.command, isNot(contains(staleIdentity.storePath)));
        }

        await tearDownBdStore(stale);
        expect(_alive(staleIdentity.proxyPid), isFalse);
        expect(_alive(staleIdentity.doltPid), isFalse);
      },
      skip: skipWithoutBd,
    );

    test('a store bd does not answer for is refused at creation', () async {
      // The OTHER capture, and the one that cost this bead its rounds: not a
      // stale server, but a `.beads/` REDIRECT stub in a git work tree above
      // the store. That is a per-bead grid worktree exactly, and under one bd
      // answers out of the redirect's target however the store is named —
      // measured as `config get issue_prefix` saying `(not set)` and the next
      // `create` refusing with `issue_prefix config is missing`, six filing
      // tests at a time, naming neither store. Here it is built on purpose,
      // so the refusal is measured rather than described.
      final hostile = Directory.systemTemp.createTempSync('filing-captured-');
      final hostilePath = hostile.resolveSymbolicLinksSync();
      addTearDown(() {
        if (hostile.existsSync()) hostile.deleteSync(recursive: true);
      });

      // The target has to be a store bd can actually resolve: bd falls
      // through a redirect that names nothing, and then there is no capture
      // to catch. It is minted BEFORE the stub exists, so it is not captured
      // itself.
      final decoy = await bdStore(
        prefix: 'decoy',
        at: Directory(p.join(hostile.path, 'decoy')),
      );
      final ambient = Directory(p.join(hostile.path, '.beads'))
        ..createSync(recursive: true);
      File(p.join(ambient.path, 'metadata.json')).writeAsStringSync(
        File(p.join(decoy.path, '.beads', 'metadata.json')).readAsStringSync(),
      );
      File(
        p.join(ambient.path, 'redirect'),
      ).writeAsStringSync('decoy/.beads\n');
      // The git work tree is load-bearing: without one the same stub is
      // ignored and bd resolves the store correctly.
      final git = await Process.run('git', const [
        'init',
        '--initial-branch=main',
      ], workingDirectory: hostile.path);
      expect(git.exitCode, 0, reason: '${git.stdout}${git.stderr}');

      await expectLater(
        bdStore(
          prefix: 'captured',
          at: Directory(p.join(hostile.path, 'store')),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('is not the store bd answers for'),
              contains(p.join(hostilePath, 'store')),
              contains('"captured"'),
              contains('bd_version=bd version'),
            ),
          ),
        ),
        reason:
            'a captured store must be refused where it is built, not six '
            'filing failures later',
      );
    }, skip: skipWithoutBd);

    test(
      'AC-3 — runBd failures name bd and bound server identity',
      () async {
        final store = await bdStore(prefix: 'named');
        final identity = bdStoreIdentity(store);

        // `bd show` is the cheapest guaranteed refusal, and the rule against
        // calling it is about a re-query path against a LIVE store's watcher:
        // this store is a throwaway temp directory with no watcher to trigger.
        Object? thrown;
        try {
          await runBd(store, const ['show', 'missing-fixture-id']);
        } on TestFailure catch (failure) {
          thrown = failure;
        }
        expect(
          thrown,
          isNotNull,
          reason: 'bd show of an absent bead must fail the test',
        );

        final message = '$thrown';
        expect(message, contains('bd_version=${identity.bdVersion}'));
        expect(message, contains('store_path=${identity.storePath}'));
        expect(message, contains('proxy_pid=${identity.proxyPid}'));
        expect(message, contains('proxy_port=${identity.proxyPort}'));
        expect(message, contains('dolt_pid=${identity.doltPid}'));
        expect(message, contains('dolt_port=${identity.doltPort}'));
      },
      skip: skipWithoutBd,
    );
  });
}

/// Whether [pid] names a live process right now.
///
/// The working directory is given explicitly, as every subprocess here is:
/// nothing in this suite reads or assigns [Directory.current]
/// (power_station#test-tree-package-root-is-source-located).
bool _alive(int pid) {
  final result = Process.runSync('ps', [
    '-p',
    '$pid',
    '-o',
    'pid=',
  ], workingDirectory: Directory.systemTemp.path);
  return (result.stdout as String).trim().isNotEmpty;
}

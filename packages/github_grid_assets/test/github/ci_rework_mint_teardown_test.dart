import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

// The fixture is imported for its TEARDOWN seams alone. A prefixed import runs
// no `main`, so the store-booting acceptance case next door stays in its own
// suite while every branch of the fence it depends on is proved here — with
// fakes, against no bd and no Dolt.
import 'ci_rework_mint_acceptance_test.dart' as fixture;

const _workspace = '/tmp/ci-rework-mint-fake';
const _lockRoot = '$_workspace/grid/.grid/.beads/dolt';
const _proxyLock = '$_lockRoot/proxy.lock';
const _proxyChildLock = '$_lockRoot/proxy-child.lock';
const _proxyPid = '$_lockRoot/proxy.pid';
const _proxyChildPid = '$_lockRoot/proxy-child.pid';

/// A [fixture.WorkspaceProcessCensus] with only the arm under test filled.
fixture.WorkspaceProcessCensus _census({
  List<({int pid, String command})> stores = const [],
  List<int> residents = const [],
}) => (stores: stores, residents: residents);

void main() {
  test('the state runner drains every spawn it still owes', () async {
    // The fence no process census can supply: a bd client that has not been
    // spawned yet is in no process table, and it is a CLIENT — not a stray
    // server — that rebuilds a proxied store after a delete. One permit turns
    // the runner's FIFO semaphore into proof that it owes no more spawns.
    final runner = fixture.seededStateBdRunner(_workspace);
    expect(runner.workspaceRoot, _workspace);

    final inFlight = Completer<void>();
    var finished = false;
    final spawn = runner.guarded(() async {
      await inFlight.future;
      finished = true;
    });

    var drained = false;
    unawaited(fixture.drainStateBdRunner(runner).then((_) => drained = true));
    await pumpEventQueue();
    expect(drained, isFalse, reason: 'a spawn is still outstanding');

    inFlight.complete();
    await spawn;
    await pumpEventQueue();
    expect(finished, isTrue);
    expect(drained, isTrue, reason: 'the drain waits the spawn out');

    // And it RETURNS against an IDLE runner. The station teardown reaches this
    // fence after the runtime is already down, so the common case owes no
    // spawn at all — a drain that only ever completed behind an outstanding
    // permit would hang exactly the teardown it was built for.
    await fixture.drainStateBdRunner(runner);
  });

  test('the lsof census reads p records and drops this process', () {
    // `-Fp` output as lsof actually writes it: one tagged field per line, a
    // file-descriptor record between the process records, and a warning row
    // `+D` emits for a directory it cannot descend into.
    const output =
        'p1234\n'
        'fcwd\n'
        'lsof: WARNING: can\'t stat() apfs file system /System/Volumes/Data\n'
        'pnot-a-pid\n'
        'p\n'
        '5678\n'
        'p4242\n'
        'p5678\n';

    expect(
      fixture.parseLsofPids(output, selfPid: 4242),
      orderedEquals(<int>[1234, 5678]),
    );
  });

  test('a missing lsof censuses nothing rather than refusing', () async {
    var invoked = 0;

    final residents = await fixture.workspaceResidents(
      _workspace,
      selfPid: 4242,
      runProcess: (executable, arguments) async {
        invoked++;
        expect(executable, 'lsof');
        expect(arguments, contains(_workspace));
        throw const ProcessException('lsof', ['-Fp'], 'No such file', 2);
      },
    );

    expect(invoked, 1);
    expect(residents, isEmpty);
  });

  test('both proxy pid files seed the exit fence', () {
    final read = <String>[];

    // bd has written a PID both ways, and the two files name DIFFERENT
    // processes: `proxy.pid` the bd proxy, `proxy-child.pid` the Dolt server it
    // supervises. The fence waits out both or it waits out nothing.
    final pids = fixture.proxiedStateStorePids(
      _workspace,
      readPidFile: (path) {
        read.add(path);
        return path.endsWith('proxy-child.pid')
            ? '{"pid":68385,"port":63237}\n'
            : '68187\n';
      },
    );

    expect(read, orderedEquals(<String>[_proxyPid, _proxyChildPid]));
    expect(pids, unorderedEquals(<int>[68187, 68385]));

    expect(
      fixture.proxiedStateStorePids(_workspace, readPidFile: (_) => null),
      isEmpty,
      reason: 'an absent pid file is a store that is already down',
    );
  });

  test('a pid file present but unreadable refuses by name', () async {
    expect(
      () => fixture.proxiedStateStorePids(
        _workspace,
        readPidFile: (path) =>
            path.endsWith('proxy-child.pid') ? '{"port":63237}' : '68187',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(_proxyChildPid),
        ),
      ),
    );
  });

  test('a re-created workspace is deleted again before absence '
      'stabilizes', () async {
    // The leak this fence was built for: the delete succeeds, and a store
    // process re-creates the workspace on its way out. Every later poll finds
    // it gone, so the second delete is the last one.
    final presence = <bool>[true, false, false, false, false, false];
    var polls = 0;
    var deletes = 0;
    var fallbacks = 0;
    final waits = <Duration>[];

    await fixture.deleteTemporaryWorkspaceWithRetry(
      delete: () async {
        deletes++;
      },
      stillPresent: () => presence[polls++],
      delay: (duration) async => waits.add(duration),
      onDeleteFallback: () => fallbacks++,
      workspacePath: _workspace,
      reappearanceCensus: () async =>
          fail('a recovered delete censuses nothing'),
      absenceChecks: 5,
    );

    expect(deletes, 2);
    expect(fallbacks, 1, reason: 'a workspace that comes back is a miss');
    expect(polls, 6, reason: 'one poll, then the five that came back bare');
    expect(waits, hasLength(6));
    expect(waits, everyElement(const Duration(milliseconds: 50)));
  });

  test('a workspace that keeps coming back refuses loudly', () async {
    var deletes = 0;
    var fallbacks = 0;
    var censuses = 0;

    // A workspace no number of deletions removes is a live writer, and the
    // only useful report of one names it. The two arms carry DIFFERENT pids on
    // purpose: a store the argv census caught, and a resident only a cwd
    // names.
    Future<fixture.WorkspaceProcessCensus> census() async {
      censuses++;
      return (
        stores: [(pid: 68187, command: 'dolt sql-server --config $_lockRoot')],
        residents: const [68385],
      );
    }

    await expectLater(
      fixture.deleteTemporaryWorkspaceWithRetry(
        delete: () async {
          deletes++;
        },
        stillPresent: () => true,
        delay: (_) async {},
        onDeleteFallback: () => fallbacks++,
        workspacePath: _workspace,
        reappearanceCensus: census,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains(_workspace), contains('68187'), contains('68385')),
        ),
      ),
    );

    expect(deletes, 5);
    expect(fallbacks, 5, reason: 'every reappearance counts, the last too');
    expect(
      censuses,
      1,
      reason: 'the census is taken once, at the final reappearance',
    );
  });

  test('the last delete attempt rethrows the original failure', () async {
    final failure = FileSystemException(
      'Deletion failed',
      _workspace,
      const OSError('Directory not empty', 66),
    );
    var attempts = 0;
    var fallbacks = 0;
    final waits = <Duration>[];

    await expectLater(
      fixture.deleteTemporaryWorkspaceWithRetry(
        delete: () async {
          attempts++;
          throw failure;
        },
        stillPresent: () => true,
        delay: (duration) async => waits.add(duration),
        onDeleteFallback: () => fallbacks++,
        workspacePath: _workspace,
        reappearanceCensus: () async =>
            fail('a delete that never succeeded censuses nothing'),
      ),
      throwsA(same(failure)),
    );

    expect(attempts, 5);
    expect(fallbacks, 4, reason: 'every non-final attempt counts a fallback');
    expect(waits, everyElement(const Duration(milliseconds: 50)));
    expect(waits, hasLength(4));
  });

  test('the default absence window is the measured one', () async {
    // The window is a MEASUREMENT: a 20 Hz stat loop around ten consecutive
    // deletes of the acceptance workspace saw none come back and every one
    // stay gone through a 3,000 ms tail, so the default spends 6,000 ms —
    // twice that — before it believes a delete. A caller that takes the
    // default takes that bound, and shortening it is the regression this
    // fixture was rewritten to stop.
    var deletes = 0;
    final waits = <Duration>[];

    await fixture.deleteTemporaryWorkspaceWithRetry(
      delete: () async {
        deletes++;
      },
      stillPresent: () => false,
      delay: (duration) async => waits.add(duration),
      onDeleteFallback: () => fail('a workspace that stays gone is no miss'),
      workspacePath: _workspace,
      reappearanceCensus: () async => fail('a clean delete censuses nothing'),
    );

    expect(deletes, 1);
    expect(waits, hasLength(120));
    expect(waits, everyElement(const Duration(milliseconds: 50)));
  });

  test(
    'the durable leak check returns immediately when count and census are clean',
    () async {
      // The common teardown: the workspace is gone, the count is back at the
      // baseline, and nothing works under the path. It spends no window, says
      // nothing, and never walks `/tmp` for evidence it does not need.
      var counts = 0;
      var censuses = 0;

      await fixture.expectNoDurableTemporaryWorkspaceLeak(
        baselineCount: 8,
        currentCount: () {
          counts++;
          return 8;
        },
        processCensus: () async {
          censuses++;
          return _census();
        },
        describeWorkspaces: () => fail('a clean teardown describes nothing'),
        delay: (_) async => fail('a clean teardown waits for nothing'),
        reportTransient: (_) => fail('a clean teardown reports nothing'),
      );

      expect(counts, 1);
      expect(censuses, 1);
    },
  );

  test('a transient workspace count is reported once and accepted', () async {
    // The residue the station measured red with nothing durable behind it: one
    // workspace over the baseline and a bd client still working under the
    // path, both gone a sample later. It is a line on stderr, not a failure.
    final counts = <int>[9, 8];
    final censuses = <fixture.WorkspaceProcessCensus>[
      _census(residents: const [68385]),
      _census(),
    ];
    var countSamples = 0;
    var censusSamples = 0;
    final waits = <Duration>[];
    final reports = <String>[];

    await fixture.expectNoDurableTemporaryWorkspaceLeak(
      baselineCount: 8,
      currentCount: () => counts[countSamples++],
      processCensus: () async => censuses[censusSamples++],
      describeWorkspaces: () => fail('a recovered transient describes nothing'),
      delay: (duration) async => waits.add(duration),
      reportTransient: reports.add,
    );

    expect(waits, orderedEquals(const [Duration(milliseconds: 50)]));
    expect(countSamples, 2);
    expect(censusSamples, 2);
    expect(reports, hasLength(1));
    expect(reports.single, isNot(contains('\n')));
    expect(
      reports.single,
      allOf(contains('recovered to 8 from 9'), contains('68385')),
    );
  });

  test(
    'a durable workspace count refuses with process and directory evidence',
    () async {
      // A count that never comes back is a leak, and the only useful report of
      // one names the process still holding it AND the directory it left: the
      // path, when it was last written, and what is inside it.
      const leaked = '/private/tmp/ci-rework-mint-ys7D8n';
      const modified = '2026-09-15T19:19:02.000Z';
      const listed = 'grid/.grid/.beads/dolt/proxy.lock';
      var countSamples = 0;
      var describes = 0;
      final waits = <Duration>[];

      await expectLater(
        fixture.expectNoDurableTemporaryWorkspaceLeak(
          baselineCount: 8,
          currentCount: () {
            countSamples++;
            return 9;
          },
          processCensus: () async => (
            stores: [
              (pid: 68187, command: 'dolt sql-server --config $_lockRoot'),
            ],
            residents: const [68385],
          ),
          describeWorkspaces: () {
            describes++;
            return '$leaked (modified $modified)\n  $listed';
          },
          delay: (duration) async => waits.add(duration),
          reportTransient: (_) => fail('a durable leak is no transient'),
          checks: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('9 workspaces on disk against a baseline of 8'),
              contains(leaked),
              contains(modified),
              contains(listed),
              contains('68187'),
              contains('dolt sql-server'),
              contains('68385'),
            ),
          ),
        ),
      );

      expect(waits, hasLength(3));
      expect(waits, everyElement(const Duration(milliseconds: 50)));
      expect(countSamples, 4, reason: 'the first sample, then one per check');
      expect(describes, 1, reason: 'evidence is read on the failure alone');
    },
  );

  test('an empty census clears the delete to run', () {
    fixture.expectEmptyWorkspaceProcessCensus(
      _census(),
      workspacePath: _workspace,
      phase: 'before delete',
    );
  });

  test('a store still holding the workspace refuses by name', () {
    // The arm the stop fence owns: a Dolt server the delete would race.
    expect(
      () => fixture.expectEmptyWorkspaceProcessCensus(
        _census(
          stores: [
            (pid: 68187, command: 'dolt sql-server --config $_lockRoot'),
          ],
        ),
        workspacePath: _workspace,
        phase: 'before delete',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('before delete'),
            contains(_workspace),
            contains('68187'),
            contains('dolt sql-server'),
          ),
        ),
      ),
    );
  });

  test('a resident working under the workspace refuses by name', () {
    // The arm no window can outlast: a bd client whose cwd is the workspace,
    // caught on the far side of the absence window, where the phase is the
    // whole report — the same census reads clean before the delete.
    expect(
      () => fixture.expectEmptyWorkspaceProcessCensus(
        _census(residents: const [68385]),
        workspacePath: _workspace,
        phase: 'after absence window',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('after absence window'),
            contains(_workspace),
            contains('68385'),
          ),
        ),
      ),
    );
  });

  test('the exit wait polls through pid and lock residue', () async {
    final pidResidue = <Set<int>>[
      {68187},
      <int>{},
      <int>{},
    ];
    final lockResidue = <Set<String>>[
      <String>{},
      {_proxyChildLock},
      <String>{},
    ];
    final start = DateTime.utc(2026, 9, 15);
    var pidPolls = 0;
    var lockPolls = 0;
    var ticks = 0;
    final waits = <Duration>[];

    await fixture.waitForProxiedStateStoreExit(
      survivingPids: () async => pidResidue[pidPolls++],
      heldLockPaths: () async => lockResidue[lockPolls++],
      now: () => start.add(Duration(milliseconds: 50 * ticks++)),
      delay: (duration) async => waits.add(duration),
    );

    expect(
      pidPolls,
      3,
      reason: 'a store is gone only when BOTH come back bare',
    );
    expect(lockPolls, 3);
    expect(waits, hasLength(2));
    expect(waits, everyElement(const Duration(milliseconds: 50)));
  });

  test('the exit wait names the residue it timed out on', () async {
    final start = DateTime.utc(2026, 9, 15);
    final clock = <DateTime>[start, start.add(const Duration(seconds: 11))];
    var ticks = 0;

    await expectLater(
      fixture.waitForProxiedStateStoreExit(
        survivingPids: () async => {68187},
        heldLockPaths: () async => {_proxyChildLock, _proxyLock},
        now: () => clock[ticks++],
        delay: (duration) async => fail('the bound was spent, not refused'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('68187'),
            contains(_proxyLock),
            contains(_proxyChildLock),
          ),
        ),
      ),
    );

    expect(ticks, 2, reason: 'the deadline, then the one poll that passed it');
  });
}

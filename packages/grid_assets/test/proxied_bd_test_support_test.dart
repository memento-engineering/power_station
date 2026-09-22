import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_root.dart';
import 'support/proxied_bd_test_support.dart';

/// The shared proxied-`bd` lifecycle harness, proved WITHOUT a bd store.
///
/// Every seam the two consumers depend on is injected here — the PID reader,
/// the process probe, the clock, the delay — so the parse, the degradation and
/// the bound are all measurable against fakes rather than against a real
/// server that would have to be leaked to observe them. The one thing that
/// does touch the OS is the port reservation, which is the OS answer under
/// test.
///
/// The last group is the falsifiable half of "ONE harness": it reads both
/// consumers off disk and fails if either grows a census, a PID parser or a
/// stop fence of its own again.
void main() {
  group('the installed-bd compatibility probe', () {
    test('names the four flags an isolated store is built from', () {
      expect(
        requiredIsolatedBdInitFlags,
        orderedEquals(const [
          '--proxied-server',
          '--proxied-server-config-path',
          '--proxied-server-root-path',
          '--proxied-server-port',
        ]),
      );
    });

    test('an absent binary skips with the CI reason', () {
      expect(
        isolatedBdFixtureSkipReason(bdVersion: null, initFlags: const {}),
        'requires a real bd binary on PATH (absent in CI)',
      );
    });

    test('an incompatible binary names its version and EVERY missing '
        'flag', () {
      // The skew worth naming: a binary that has proxied mode but cannot be
      // told which port the proxy takes, which is the flag that makes a
      // store's own server identifiable at all.
      final reason = isolatedBdFixtureSkipReason(
        bdVersion: 'bd version 1.0.9 (deadbee)',
        initFlags: const {'--proxied-server', '--proxied-server-config-path'},
      );

      expect(
        reason,
        allOf(
          contains('bd version 1.0.9 (deadbee)'),
          contains('--proxied-server-root-path'),
          contains('--proxied-server-port'),
          isNot(contains('--proxied-server-config-path,')),
        ),
      );
    });

    test('a complete binary is no skip at all', () {
      expect(
        isolatedBdFixtureSkipReason(
          bdVersion: 'bd version 1.1.0 (f82590301)',
          initFlags: requiredIsolatedBdInitFlags.toSet(),
        ),
        isNull,
      );
    });
  });

  group('the proxy pid artifacts', () {
    const pidRoot = '/private/tmp/zo1g-fixture/.beads/dolt';

    test('both files seed the fence, bare and JSON alike', () {
      final read = <String>[];

      // bd has written a PID both ways, and the two files name DIFFERENT
      // processes: `proxy.pid` the db-proxy-child, `proxy-child.pid` the Dolt
      // server it supervises. The fence waits out both or it waits out
      // nothing.
      final pids = proxiedStateStorePids(
        pidRootPath: pidRoot,
        readPidFile: (path) {
          read.add(path);
          return path.endsWith('proxy-child.pid')
              ? '{"pid":68385,"port":63237}\n'
              : '68187\n';
        },
      );

      expect(
        read,
        orderedEquals(<String>[
          '$pidRoot/proxy.pid',
          '$pidRoot/proxy-child.pid',
        ]),
      );
      expect(pids, unorderedEquals(<int>[68187, 68385]));
    });

    test('an absent file is a store that is already down', () {
      expect(
        proxiedStateStorePids(pidRootPath: pidRoot, readPidFile: (_) => null),
        isEmpty,
      );
    });

    test('a file present but unreadable refuses by name', () {
      // A PID file this cannot read names a process the exit fence cannot wait
      // out; reading it as "nothing to wait for" is how a live Dolt server was
      // abandoned over a deleted store in the first place.
      for (final contents in const ['{"port":63237}', 'not-a-pid', '0']) {
        expect(
          () => proxiedStateStorePids(
            pidRootPath: pidRoot,
            readPidFile: (path) =>
                path.endsWith('proxy-child.pid') ? contents : '68187',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('$pidRoot/proxy-child.pid'), contains(contents)),
            ),
          ),
          reason: 'contents: $contents',
        );
      }
    });
  });

  group('the workspace census', () {
    const storePath = '/private/tmp/zo1g-deleted-store';
    const proxy =
        '/opt/homebrew/bin/bd db-proxy-child --root '
        '$storePath/.beads/dolt --port 56169 --config '
        '$storePath/.beads/dolt/fixture-server.yaml';
    const dolt =
        '/opt/homebrew/bin/dolt sql-server --config '
        '$storePath/.beads/dolt/fixture-server.yaml';

    test('a store process for a DELETED path is still visible', () {
      // The case the canonical-resolution-only matcher lost: the directory is
      // gone, so nothing resolves, and the raw argv is the only account left
      // of which store the server belongs to. That is exactly the server that
      // captures the next fixture store on the host.
      expect(Directory(storePath).existsSync(), isFalse);

      expect(
        storeProcessesIn(const {8903: proxy, 8915: dolt}, storePath),
        orderedEquals(<({int pid, String command})>[
          (pid: 8903, command: proxy),
          (pid: 8915, command: dolt),
        ]),
      );
    });

    test('another store, and a non-store client, are not this census', () {
      const otherStore =
          '/opt/homebrew/bin/dolt sql-server --config '
          '/private/tmp/zo1g-other-store/.beads/dolt/fixture-server.yaml';
      // A detached bd child working IN the path: no --config, no --root, so
      // only the resident arm can see it — never this one.
      const client = '/opt/homebrew/bin/bd send-metrics';

      expect(
        storeProcessesIn(const {8900: otherStore, 8901: client}, storePath),
        isEmpty,
      );
    });

    test('lsof reads p records, drops this process, and is asked for cwd '
        'alone', () async {
      final invocations = <({String executable, List<String> arguments})>[];

      final residents = await workspaceResidents(
        storePath,
        selfPid: 4242,
        runProcess: (executable, arguments) async {
          invocations.add((executable: executable, arguments: arguments));
          return ProcessResult(
            0,
            0,
            // `-Fp` output as lsof actually writes it: one tagged field per
            // line, a file-descriptor record between the process records, and
            // a warning row `+D` emits for a directory it cannot descend into.
            'p1234\n'
                'fcwd\n'
                "lsof: WARNING: can't stat() apfs file system /System\n"
                'pnot-a-pid\n'
                'p\n'
                '5678\n'
                'p4242\n'
                'p5678\n',
            '',
          );
        },
      );

      expect(residents, orderedEquals(<int>[1234, 5678]));
      expect(invocations, hasLength(1));
      expect(invocations.single.executable, 'lsof');
      expect(
        invocations.single.arguments,
        orderedEquals(<String>[
          '-w',
          '-a',
          '-d',
          'cwd',
          '-Fp',
          '+D',
          storePath,
        ]),
      );
    });

    test('a missing lsof censuses nothing rather than refusing', () async {
      var invoked = 0;

      final residents = await workspaceResidents(
        storePath,
        selfPid: 4242,
        runProcess: (executable, arguments) async {
          invoked++;
          throw const ProcessException('lsof', ['-Fp'], 'No such file', 2);
        },
      );

      expect(invoked, 1);
      expect(residents, isEmpty);
    });

    test('an empty census clears the delete to run', () {
      expectEmptyWorkspaceProcessCensus(
        (stores: const [], residents: const []),
        workspacePath: storePath,
        phase: 'before delete',
      );
    });

    test('either arm alone refuses by name, naming the phase', () {
      // The two arms answer different questions — a store the argv census
      // caught, and a client only a cwd names — and a teardown that reports
      // residue owes the reader which kind it found.
      expect(
        () => expectEmptyWorkspaceProcessCensus(
          (stores: [(pid: 8915, command: dolt)], residents: const []),
          workspacePath: storePath,
          phase: 'before delete',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('before delete'),
              contains(storePath),
              contains('8915'),
              contains('dolt sql-server'),
            ),
          ),
        ),
      );

      expect(
        () => expectEmptyWorkspaceProcessCensus(
          (stores: const [], residents: const [68385]),
          workspacePath: storePath,
          phase: 'after delete',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('after delete'),
              contains(storePath),
              contains('68385'),
            ),
          ),
        ),
      );
    });
  });

  group('the exit fence', () {
    test('polls through pid AND lock residue', () async {
      // A store is gone only when BOTH come back bare: the PID can leave the
      // table while the proxy's flock is still held, and a lock can be
      // released by a process that has not exited yet.
      final pidResidue = <Set<int>>[
        {68187},
        <int>{},
        <int>{},
      ];
      final lockResidue = <Set<String>>[
        <String>{},
        {'/private/tmp/zo1g/proxy-child.lock'},
        <String>{},
      ];
      final start = DateTime.utc(2026, 9, 22);
      var pidPolls = 0;
      var lockPolls = 0;
      var ticks = 0;
      final waits = <Duration>[];

      await waitForProxiedStateStoreExit(
        survivingPids: () async => pidResidue[pidPolls++],
        heldLockPaths: () async => lockResidue[lockPolls++],
        now: () => start.add(Duration(milliseconds: 50 * ticks++)),
        delay: (duration) async => waits.add(duration),
      );

      expect(pidPolls, 3);
      expect(lockPolls, 3);
      expect(waits, hasLength(2));
      expect(waits, everyElement(const Duration(milliseconds: 50)));
    });

    test('names the residue it timed out on, sorted', () async {
      final start = DateTime.utc(2026, 9, 22);
      final clock = <DateTime>[start, start.add(const Duration(seconds: 11))];
      var ticks = 0;

      await expectLater(
        waitForProxiedStateStoreExit(
          survivingPids: () async => {68385, 68187},
          heldLockPaths: () async => {
            '/private/tmp/zo1g/proxy.lock',
            '/private/tmp/zo1g/proxy-child.lock',
          },
          now: () => clock[ticks++],
          delay: (duration) async => fail('the bound was spent, not refused'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('10000ms'),
              contains('68187, 68385'),
              contains(
                '/private/tmp/zo1g/proxy-child.lock, '
                '/private/tmp/zo1g/proxy.lock',
              ),
            ),
          ),
        ),
      );

      expect(
        ticks,
        2,
        reason: 'the deadline, then the one poll that passed it',
      );
    });
  });

  group('the port reservation', () {
    test('hands out two DISTINCT free loopback ports', () async {
      // Both sockets are held at once before either is released, which is what
      // makes the two ports different — and a store built on one port could
      // verify neither server.
      final ports = await reserveProxiedBdPorts();

      expect(ports.proxyPort, isNot(ports.doltPort));
      expect(ports.proxyPort, greaterThan(0));
      expect(ports.doltPort, greaterThan(0));

      // Released, not held: bd starts both servers itself, so a reservation
      // this process kept would be a port bd could never bind.
      for (final port in [ports.proxyPort, ports.doltPort]) {
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        addTearDown(socket.close);
        expect(socket.port, port);
      }
    });
  });

  group('AC-4 — one harness, and the source says so', () {
    // The falsifiable half of the decision. Both consumers are read off disk
    // and asserted to IMPORT the shared module and to define none of the
    // lifecycle machinery that used to live in them: a re-duplication turns
    // this red at the moment it is written, not at the moment a station host
    // leaks a server six days later.
    //
    // Resolved from `packageRoot()`, never the process working directory
    // (power_station#test-tree-package-root-is-source-located).
    final fixture = p.join(
      packageRoot(),
      'test',
      'filing',
      'real_bd_store.dart',
    );
    final acceptance = p.normalize(
      p.join(
        packageRoot(),
        '..',
        'github_grid_assets',
        'test',
        'github',
        'ci_rework_mint_acceptance_test.dart',
      ),
    );

    /// The retired implementations — the names each consumer's own census,
    /// PID parser and stop fence went by.
    const retired = [
      '_pidArtifact',
      '_processTable',
      '_storeProcessesIn',
      '_harnessStoreProcesses',
      '_namesTempPath',
      '_recordedPid',
      '_readPidFileIfPresent',
      '_workspaceProcessCensus',
      '_stopAndAwaitProxiedStateStore',
    ];

    test('the real bd fixture consumes the shared module', () {
      final source = File(fixture).readAsStringSync();

      expect(
        source,
        contains("import '../support/proxied_bd_test_support.dart'"),
      );
      for (final identifier in retired) {
        expect(source, isNot(contains(identifier)), reason: identifier);
      }
      expect(source, isNot(contains("Process.run('ps'")));
    });

    test('the station acceptance fixture consumes the shared module', () {
      final source = File(acceptance).readAsStringSync();

      expect(
        source,
        contains(
          "import '../../../grid_assets/test/support/"
          "proxied_bd_test_support.dart'",
        ),
      );
      for (final identifier in retired) {
        expect(source, isNot(contains(identifier)), reason: identifier);
      }
      expect(source, isNot(contains("Process.run('ps'")));
    });

    test('the fence reads the files it claims to', () {
      // A source fence over a path that does not resolve passes vacuously, and
      // a vacuous fence is how a re-duplication ships green.
      for (final path in [fixture, acceptance]) {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(
          File(path).readAsStringSync(),
          contains('proxied_bd_test_support.dart'),
          reason: path,
        );
      }
    });
  });
}

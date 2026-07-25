import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('buildComputeServeCommand', () {
    test('wires the flag surface and caller-owned bounds', () async {
      final command = buildComputeServeCommand(allow: const ['echo']);

      expect(command.argParser.options.keys, {
        'help',
        'station',
        'host',
        'port',
        'kind',
        'slots',
        'token',
        'ttl',
        'max-lifetime',
        'lease-wait',
        'max-queue',
        'allow',
        'exec-timeout',
      });
      final args = command.argParser.parse(const []);
      expect(args.multiOption('allow'), ['echo']);
      expect(args.option('exec-timeout'), '300');

      final logs = <String>[];
      final asset = command.handlerFor(args, logs.add);
      expect(asset.banner, contains('allow-list [echo]'));
      expect(asset.banner, contains('timeout 300s'));
      expect(asset.onLeaseEnded, isNull);

      final result = CommandResult.fromJson(
        await asset.handler(const DispatchCommand(command: 'uname').toJson()),
      );
      expect(result.exitCode, 126);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('not on the compute allow-list'));
      expect(logs, contains(contains('compute REFUSED')));
    });
  });

  group('buildComputeLeaseCommand', () {
    test('encodes trailing argv as a dispatch payload', () {
      final command = buildComputeLeaseCommand();

      expect(command.argParser.options.keys, {
        'help',
        'peer',
        'lessee',
        'kind',
        'token',
      });
      expect(
        command.payloadFor(const ['git', 'status', '--short']),
        const DispatchCommand(
          command: 'git',
          args: ['status', '--short'],
        ).toJson(),
      );
    });

    test('splits non-empty streams and passes through exit code', () {
      final command = buildComputeLeaseCommand();
      final stdout = <String>[];
      final stderr = <String>[];

      final exitCode = command.render(
        const CommandResult(
          exitCode: 23,
          stdout: 'out',
          stderr: 'err',
          durationMs: 7,
        ).toJson(),
        stdout.add,
        stderr.add,
      );

      expect(stdout, ['out']);
      expect(stderr, ['err']);
      expect(exitCode, 23);
    });

    test('does not emit empty streams', () {
      final command = buildComputeLeaseCommand();
      final stdout = <String>[];
      final stderr = <String>[];

      final exitCode = command.render(
        const CommandResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
          durationMs: 0,
        ).toJson(),
        stdout.add,
        stderr.add,
      );

      expect(stdout, isEmpty);
      expect(stderr, isEmpty);
      expect(exitCode, 0);
    });
  });
}

import 'package:args/args.dart';
import 'package:federated_grid_assets/federated_grid_assets.dart';

import 'bounded_use.dart';
import 'compute_command.dart';

/// Builds the COMPUTE asset's bounded lessor command.
///
/// [allow] is the composing station's security policy. It is required rather
/// than silently defaulted by the asset; callers may still override the
/// supplied CLI default with `--allow`.
ServeCommand buildComputeServeCommand({required List<String> allow}) =>
    ServeCommand(
      defaultKind: kComputeKind,
      configureFlags: (ArgParser parser) => parser
        ..addMultiOption(
          'allow',
          defaultsTo: allow,
          help:
              'The executables the lessor will run (the bounded-use '
              'allow-list). A dispatched command not on this list is '
              'REFUSED (no shell-as-a-service; ADR-0011 RCE-bounds).',
        )
        ..addOption(
          'exec-timeout',
          defaultsTo: '300',
          help: 'Per-command timeout in seconds (the bounded-use upper bound).',
        ),
      handlerFor: (args, log) {
        final bounds = ComputeBounds(
          allowedCommands: args.multiOption('allow').toSet(),
          timeout: Duration(seconds: int.parse(args.option('exec-timeout')!)),
        );
        return (
          handler: computeDispatchHandler(bounds: bounds, onLog: log),
          banner:
              'bounded use: allow-list '
              '${bounds.allowedCommands.toList()..sort()}  ·  '
              'timeout ${bounds.timeout.inSeconds}s',
          onLeaseEnded: null,
        );
      },
    );

/// Builds the COMPUTE asset's lessee command and payload/result codecs.
LeaseCommand buildComputeLeaseCommand() => LeaseCommand(
  defaultKind: kComputeKind,
  payloadFor: (rest) => DispatchCommand(
    command: rest.first,
    args: rest.skip(1).toList(),
  ).toJson(),
  render: (raw, out, err) {
    final result = CommandResult.fromJson(raw);
    if (result.stdout.isNotEmpty) out(result.stdout);
    if (result.stderr.isNotEmpty) err(result.stderr);
    return result.exitCode;
  },
);

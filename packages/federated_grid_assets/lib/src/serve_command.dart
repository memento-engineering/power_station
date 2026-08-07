import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'station_server.dart';

/// Builds the ASSET's dispatch [handler] (+ an optional [banner] line + an
/// optional lessor-teardown [onLeaseEnded] hook) from the parsed args — the
/// seam that keeps `serve` GENERIC ("leasing is core"): the core command owns
/// the lessor lifecycle; the asset domain owns the "use" AND the reap of any
/// work it launched under a lease (ADR-0011 D3 + Hazards). The reference app
/// supplies the compute one; the burn's reaps its follower app.
typedef ServeHandlerFactory =
    ({
      DispatchHandler handler,
      String? banner,
      void Function(String leaseId)? onLeaseEnded,
    })
    Function(ArgResults args, void Function(String) log);

/// Builds the asset domain's opaque advertised profile from serve arguments.
typedef ServeProfileFactory = Map<String, Object?> Function(ArgResults args);

/// `grid serve` — run as a LESSOR station: offer slots over the federation bus
/// (ADR-0011). A peer leases a slot and dispatches a use to run HERE. GENERIC:
/// the dispatched "use" is the asset domain's, injected via [handlerFor] +
/// [configureFlags] (the runner assembles e.g. the compute bounded-use).
class ServeCommand extends Command<int> {
  /// Wires the generic serve flags, then the asset's [configureFlags]; the
  /// offered [defaultKind] and the dispatch [handlerFor] are the asset's.
  ServeCommand({
    required String defaultKind,
    required void Function(ArgParser) configureFlags,
    required this.handlerFor,
    ServeProfileFactory? profileFor,
  }) : profileFor = profileFor ?? ((_) => const <String, Object?>{}) {
    argParser
      ..addOption(
        'station',
        defaultsTo: Platform.localHostname,
        help: 'This station id (defaults to the hostname).',
      )
      ..addOption('host', defaultsTo: '0.0.0.0', help: 'Bind address.')
      ..addOption('port', defaultsTo: '8080', help: 'Bind port.')
      ..addMultiOption(
        'kind',
        defaultsTo: [defaultKind],
        help: 'The resource-asset kind offered.',
      )
      ..addMultiOption(
        'slots',
        defaultsTo: const ['1'],
        help: 'How many slots to offer for the corresponding kind.',
      )
      ..addOption(
        'token',
        help:
            'Optional shared secret; when set, peers must send it as '
            'X-Grid-Token (LAN trust, this pass).',
      )
      ..addOption(
        'ttl',
        defaultsTo: '300',
        help: 'Lease TTL in seconds (reaped if idle this long).',
      )
      ..addOption(
        'max-lifetime',
        defaultsTo: '3600',
        help:
            'Max lease lifetime in seconds (caps total TTL renewal — the '
            'starvation bound; a held lease is reaped past this regardless of '
            'activity).',
      )
      ..addOption(
        'lease-wait',
        defaultsTo: '0',
        help:
            'Seconds a full-capacity request waits in the FIFO queue before '
            'it is denied (0 = deny immediately).',
      )
      ..addOption(
        'max-queue',
        defaultsTo: '64',
        help: 'Max requests that may wait in the FIFO queue.',
      );
    configureFlags(argParser);
  }

  /// The asset's dispatch-handler factory (the compute bounded-use in the
  /// reference app).
  final ServeHandlerFactory handlerFor;

  /// The asset domain's opaque presence-profile factory.
  final ServeProfileFactory profileFor;

  /// Parses ordered repeated `--kind`/`--slots` pairs into offered capacities.
  Map<String, int> serveOfferings(ArgResults args) {
    final kinds = args.multiOption('kind');
    final slots = args.multiOption('slots');
    if (kinds.length != slots.length) {
      throw UsageException(
        'each --kind requires one --slots value in the same position',
        argParser.usage,
      );
    }
    final result = <String, int>{};
    for (var index = 0; index < kinds.length; index++) {
      final kind = kinds[index];
      final capacity = int.tryParse(slots[index]);
      if (kind.isEmpty || result.containsKey(kind)) {
        throw UsageException(
          'served kinds must be non-empty and unique',
          argParser.usage,
        );
      }
      if (capacity == null || capacity <= 0) {
        throw UsageException(
          '--slots values must be positive integers',
          argParser.usage,
        );
      }
      result[kind] = capacity;
    }
    return Map.unmodifiable(result);
  }

  @override
  final String name = 'serve';

  @override
  final String description =
      'Run as a LESSOR station: offer compute slots over the federation bus; a '
      'peer leases a slot and dispatches a command to run here.';

  @override
  Future<int> run() async {
    final a = argResults!;
    final station = a.option('station')!;
    final token = a.option('token');
    final offerings = serveOfferings(a);
    final asset = handlerFor(a, (m) => stdout.writeln('  $m'));
    final server = await StationServer.start(
      station: station,
      host: a.option('host')!,
      port: int.parse(a.option('port')!),
      offerings: offerings,
      profile: profileFor(a),
      token: token,
      ttl: Duration(seconds: int.parse(a.option('ttl')!)),
      maxLifetime: Duration(seconds: int.parse(a.option('max-lifetime')!)),
      leaseWait: Duration(seconds: int.parse(a.option('lease-wait')!)),
      maxQueueDepth: int.parse(a.option('max-queue')!),
      handler: asset.handler,
      // The asset's lessor teardown (lease release/reap → reap launched work).
      onLeaseEnded: asset.onLeaseEnded,
      onLog: (m) => stdout.writeln('  $m'),
    );
    stdout
      ..writeln('grid serve — LESSOR station "$station"')
      ..writeln(
        'listening on ${a.option('host')}:${server.port}  ·  offering '
        '${offerings.entries.map((e) => '${e.value} ${e.key} slot(s)').join(', ')}'
        '${token != null ? '  ·  token REQUIRED' : ''}',
      );
    if (asset.banner != null) stdout.writeln(asset.banner);
    stdout.writeln('Ctrl-C to stop.');

    final done = Completer<void>();
    final sub = ProcessSignal.sigint.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    await sub.cancel();
    await server.close();
    stdout.writeln('stopped.');
    return 0;
  }
}

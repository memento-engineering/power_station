/// `seat <name>` — the OUTER harness for an operator seat.
///
/// It launches the coding harness as a child with that seat's role definition
/// and disc, and relaunches it when the occupant hands off. The signal goes UP
/// because the inner agent cannot compact, clear, or restart itself (bead
/// `pow-pry0`).
///
/// Harness-NEUTRAL by construction: this library reads only declarations
/// (`seat_launch.dart`), and a fence in `test/seat/seat_command_test.dart`
/// greps it for vendor flag literals.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_engine/grid_engine.dart' show Workspace;
import 'package:path/path.dart' as p;

import '../agent/acp_session_adapter.dart';
import '../agent/agent_environment.dart';
import '../agent/agent_harness.dart';
import '../agent/agent_session.dart';
import '../agent/environment_registry.dart';
import 'seat_disc.dart';
import 'seat_launch.dart';

/// Runs one planned [SeatLaunch] and returns the child's exit code — the ONE IO
/// seam the verb has, so a test drives the whole loop with a Fake and no
/// harness is ever spawned.
typedef SeatProcessRunner = Future<int> Function(SeatLaunch launch);

String _currentDirectory() => Directory.current.path;

/// The TERMINAL's side of a channel-harness occupancy.
///
/// The first message starts the adapter session as a BRIEF; every later message
/// is a STEER. A handoff supplied through [prime] starts the session before any
/// terminal input. This tiny state machine is independently testable without
/// spawning a harness.
class SeatChannelClient {
  /// Creates the terminal client over [adapter] and the child's [write] sink.
  SeatChannelClient({
    required this.adapter,
    required void Function(List<int>) write,
  }) : _write = write;

  /// The selected channel adapter.
  final AgentSessionAdapter adapter;
  final void Function(List<int>) _write;
  bool _started = false;

  /// Starts the session with [text]. Refuses a second initial message loudly.
  void prime(String text) {
    if (_started) {
      throw StateError('the channel session already has its initial brief');
    }
    _write(adapter.encodeBrief(AgentBrief(task: text)));
    _started = true;
  }

  /// Sends one terminal [text]: the initial brief when fresh, then a steer.
  void send(String text) {
    if (!_started) {
      prime(text);
      return;
    }
    _write(adapter.encodeSteer(text));
  }
}

/// The real runner: a TTY plan INHERITS this terminal's stdio; a channel plan
/// rides the station's existing session adapter with the terminal as the
/// client.
class ProcessSeatRunner {
  /// Creates the runner over the station's [adapters], the [terminalLines] a
  /// channel occupancy steers with, and its [out]/[err] sinks.
  ProcessSeatRunner({
    this.adapters = kBuiltinAgentSessionAdapters,
    Stream<String>? terminalLines,
    StringSink? out,
    StringSink? err,
  }) : _terminalLines =
           terminalLines ??
           stdin
               .transform(utf8.decoder)
               .transform(const LineSplitter())
               .asBroadcastStream(),
       _out = out ?? stdout,
       _err = err ?? stderr;

  /// The adapter registry a channel plan resolves its transport from.
  final AgentSessionAdapterRegistry adapters;

  final Stream<String> _terminalLines;
  final StringSink _out;
  final StringSink _err;

  /// Runs [launch] and returns the child's exit code.
  Future<int> call(SeatLaunch launch) async => switch (launch) {
    SeatTtyLaunch() => _tty(launch),
    SeatChannelLaunch() => _channel(launch),
  };

  Future<int> _tty(SeatTtyLaunch launch) async {
    final process = await Process.start(
      launch.command,
      launch.args,
      workingDirectory: launch.workingDirectory,
      environment: launch.processEnvironment,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  Future<int> _channel(SeatChannelLaunch launch) async {
    final adapter = adapters.require(launch.adapterId);
    final config = adapter.launch(
      environment: launch.environment,
      workspace: Workspace(
        workspaceDir: launch.workingDirectory,
        branch: 'seat/${launch.seat}',
        baseBranch: 'seat/${launch.seat}',
      ),
      model: launch.environment.model,
    );
    final process = await Process.start(
      config.command,
      config.args,
      workingDirectory: config.workDir,
      environment: <String, String>{
        ...config.env,
        ...launch.processEnvironment,
      },
    );
    final events = adapter.decode(process.stdout).listen(_render);
    final errors = process.stderr.transform(utf8.decoder).listen(_err.write);
    final client = SeatChannelClient(
      adapter: adapter,
      write: process.stdin.add,
    );
    final priming = launch.priming;
    if (priming != null) client.prime(priming);
    final input = _terminalLines.listen(client.send);
    final code = await process.exitCode;
    await events.cancel();
    await errors.cancel();
    await input.cancel();
    return code;
  }

  void _render(AgentProtocolEvent event) {
    switch (event) {
      case AgentProtocolProgress(:final fields):
        _out.writeln(
          fields.entries.map((e) => '${e.key}: ${e.value}').join(' '),
        );
      case AgentProtocolCompleted(:final result):
        _out.writeln(
          result.entries.map((e) => '${e.key}: ${e.value}').join(' '),
        );
      case AgentProtocolFailed(:final reason):
        _err.writeln(reason);
      case AgentProtocolSessionBound() ||
          AgentProtocolPermissionRequested() ||
          AgentProtocolPermissionFallback():
        // AUTHORIZATION traffic, not output: answered by [SeatChannelClient]
        // before it ever reaches the renderer.
        return;
    }
  }
}

/// `seat <name> [--env <name>] [--grid-home <abs>] [--once]`.
class SeatCommand extends Command<int> {
  /// Creates the verb over its injectable seams: the environment [registry]
  /// selection reads, the [runner] that executes a plan, [gridHomeDefault], and
  /// the [now] clock the relaunch predicate compares against. [out] and [err]
  /// are the report sinks.
  SeatCommand({
    EnvironmentRegistry? registry,
    SeatProcessRunner? runner,
    String Function() gridHomeDefault = _currentDirectory,
    DateTime Function() now = DateTime.now,
    StringSink? out,
    StringSink? err,
  }) : _registry = registry ?? buildBuiltinEnvironmentRegistry(),
       _runner = runner ?? ProcessSeatRunner().call,
       _gridHomeDefault = gridHomeDefault,
       _now = now,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addOption(
        'env',
        help:
            'The armed environment name this seat is occupied on (the same '
            'names every spawn selects by).',
        defaultsTo: 'claude',
      )
      ..addOption(
        'grid-home',
        abbr: 'g',
        help:
            'The station grid home (ABSOLUTE): where .grid/seats/<name>/ and '
            'the role definition live. Defaults to the current directory.',
      )
      ..addFlag(
        'once',
        negatable: false,
        help: 'Occupy ONCE: return the child exit code, never relaunch.',
      );
  }

  final EnvironmentRegistry _registry;
  final SeatProcessRunner _runner;
  final String Function() _gridHomeDefault;
  final DateTime Function() _now;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'seat';

  @override
  final String description =
      "Occupy an operator seat: launch the harness with that seat's role "
      'definition and disc, and relaunch it on handoff.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape = 'seat <name> [--env <name>] [--grid-home <abs>] [--once]';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln('seat: exactly one seat name is required — $invocation');
      return 64;
    }
    final seat = rest.single.trim();
    final flag = argResults!.option('grid-home')?.trim();
    final unresolved = (flag == null || flag.isEmpty)
        ? _gridHomeDefault()
        : flag;
    if (!p.isAbsolute(unresolved)) {
      usageException(
        'seat: --grid-home must be an ABSOLUTE path (got "$unresolved").',
      );
    }
    final gridHome = p.normalize(unresolved);
    final environmentName = argResults!.option('env')!.trim();

    final AgentEnvironment environment;
    try {
      environment = _registry.resolve(environmentName);
    } on EnvironmentRegistryError catch (error) {
      _err.writeln('seat: ${error.message}');
      return 1;
    }
    final illegal = environment.validate();
    if (illegal != null) {
      _err.writeln('seat: environment "$environmentName" is illegal: $illegal');
      return 1;
    }
    final asset = renderRoleAsset(environment, seat);
    if (asset == null) {
      _err.writeln(
        'seat: environment "$environmentName" declares no role-definition home '
        '— it cannot be occupied.',
      );
      return 1;
    }
    final rolePath = p.join(gridHome, asset);
    if (!File(rolePath).existsSync()) {
      _err.writeln(
        'seat: "$seat" has no role definition at $rolePath — author the seat '
        '(or install the station overlay) before occupying it.',
      );
      return 1;
    }

    final disc = SeatDisc(
      directory: seatDiscPath(gridHome, seat),
      gridHome: gridHome,
    )..ensure();
    final once = argResults!.flag('once');
    while (true) {
      final launchedAt = _now();
      final handoff = disc.newestHandoff();
      final code = await _runner(
        planSeatLaunch(
          environment: environment,
          seat: seat,
          gridHome: gridHome,
          discDirectory: disc.directory,
          handoffBody: handoff?.body,
        ),
      );
      if (once || !disc.hasHandoffNewerThan(launchedAt)) return code;
      _out.writeln('seat: $seat handed off — relaunching.');
    }
  }
}

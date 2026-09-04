/// The PURE half of the operator-seat launcher: one planned launch, computed
/// from an [AgentEnvironment]'s own declarations and NOTHING else.
///
/// There is no vendor flag in this library. Every harness-specific token comes
/// from [AgentEnvironment.roleArgs], [AgentEnvironment.memoryDirArgs],
/// [AgentEnvironment.primeMode] and [AgentEnvironment.drivenArgs] — "it lives on
/// AgentEnvironment beside resumeFlag, or nowhere" (Nico, 2026-09-03).
library;

import '../agent/agent_environment.dart';
import 'seat_disc.dart';

/// One planned OPERATOR-SEAT launch — a pure VALUE an injected runner executes.
/// Sealed: a caller faces both transports with an exhaustive `switch`.
sealed class SeatLaunch {
  /// Creates the shared part of a plan.
  const SeatLaunch({
    required this.environment,
    required this.seat,
    required this.workingDirectory,
    required this.processEnvironment,
  });

  /// The resolved environment the seat is occupied on.
  final AgentEnvironment environment;

  /// The seat name — the role definition asset's name.
  final String seat;

  /// The grid home the occupant runs in.
  final String workingDirectory;

  /// The process env, carrying [kSeatEnvironmentVariable] and
  /// [kGridHomeEnvironmentVariable].
  final Map<String, String> processEnvironment;
}

/// A TTY harness: run [command] + [args] with INHERITED stdio.
final class SeatTtyLaunch extends SeatLaunch {
  /// Creates the TTY plan.
  const SeatTtyLaunch({
    required this.command,
    required this.args,
    required super.environment,
    required super.seat,
    required super.workingDirectory,
    required super.processEnvironment,
  });

  /// The executable.
  final String command;

  /// The composed argv — never the driven-session posture.
  final List<String> args;

  @override
  String toString() => 'SeatTtyLaunch($command ${args.join(' ')})';
}

/// A CHANNEL harness (a non-null [AgentEnvironment.sessionAdapter]): the
/// station's existing session adapter owns the launch and the terminal is the
/// client — no second spawner. [priming] is the first session message, or null.
final class SeatChannelLaunch extends SeatLaunch {
  /// Creates the channel plan.
  const SeatChannelLaunch({
    required this.adapterId,
    required this.priming,
    required super.environment,
    required super.seat,
    required super.workingDirectory,
    required super.processEnvironment,
  });

  /// The adapter registry id ([AgentEnvironment.sessionAdapter]).
  final String adapterId;

  /// The handoff body delivered as the first session message, or null.
  final String? priming;

  @override
  String toString() =>
      'SeatChannelLaunch($adapterId, primed: ${priming != null})';
}

/// Plans [seat]'s occupancy of [environment] — PURE.
///
/// The driven-session posture is DECLARED and dropped: `spawnFor` renders
/// [AgentEnvironment.drivenArgs] and an operator seat does not, and a prompt
/// segment rides ONLY when [handoffBody] must be delivered by
/// [SeatPrimeMode.prompt].
///
/// [gridHome] is the working directory and [discDirectory] the ABSOLUTE disc
/// the memory declaration is rendered against.
///
/// THROWS a [StateError] when the environment resolves no command — an
/// unspawnable environment is not occupiable, and refusing loudly beats a
/// launcher that spawns nothing and says nothing.
SeatLaunch planSeatLaunch({
  required AgentEnvironment environment,
  required String seat,
  required String gridHome,
  required String discDirectory,
  String? handoffBody,
}) {
  final command = environment.command;
  if (command == null || command.isEmpty) {
    throw StateError(
      'environment is not occupiable: no command resolved for seat "$seat"',
    );
  }
  final processEnvironment = <String, String>{
    ...environment.env,
    kSeatEnvironmentVariable: seat,
    kGridHomeEnvironmentVariable: gridHome,
  };
  final priming = switch (environment.primeMode ?? SeatPrimeMode.prompt) {
    SeatPrimeMode.hook => null,
    SeatPrimeMode.prompt => handoffBody,
  };
  final adapter = environment.sessionAdapter;
  if (adapter != null) {
    return SeatChannelLaunch(
      adapterId: adapter,
      priming: priming,
      environment: environment,
      seat: seat,
      workingDirectory: gridHome,
      processEnvironment: processEnvironment,
    );
  }
  final promptSegment = priming == null
      ? const <String>[]
      : switch (environment.promptMode ?? PromptMode.arg) {
          PromptMode.arg => <String>[priming],
          PromptMode.flag => <String>[environment.promptFlag!, priming],
          PromptMode.none => const <String>[],
        };
  return SeatTtyLaunch(
    command: command,
    args: <String>[
      ...?environment.args,
      ...environment.argsAppend,
      ...renderRoleArgs(environment, seat),
      ...renderMemoryDirArgs(environment, discDirectory),
      ...promptSegment,
    ],
    environment: environment,
    seat: seat,
    workingDirectory: gridHome,
    processEnvironment: processEnvironment,
  );
}

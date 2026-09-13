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

/// Whether [environment] can DELIVER a consumed handoff body to its child, or
/// the one-line reason it cannot — PURE.
///
/// The launcher asks this BEFORE it consumes (`pow-d5ol`, ruling 2: "a
/// successor cannot start unprimed"). Consuming is destructive: the note is
/// archived and deleted, so an environment that has no transport for the body
/// would hand the successor nothing and destroy the evidence on the way. There
/// are exactly two transports, and every environment declares which one it
/// takes:
///
///  - [SeatPrimeMode.hook] — the body rides
///    [kConsumedHandoffEnvironmentVariable] in the child's process environment
///    and the station's own SessionStart hook (`prime`) injects it;
///  - [SeatPrimeMode.prompt] — the body rides the first session message on a
///    channel plan, or the prompt segment of a TTY plan.
///
/// A TTY environment that declares [SeatPrimeMode.prompt] with
/// [PromptMode.none] declares BOTH that it wants the body and that it takes no
/// prompt: there is no transport left, and the honest answer is a refusal
/// rather than a silent drop.
String? seatHandoffDeliveryRefusal(AgentEnvironment environment) =>
    switch (environment.primeMode ?? SeatPrimeMode.prompt) {
      SeatPrimeMode.hook => null,
      SeatPrimeMode.prompt when environment.sessionAdapter != null => null,
      SeatPrimeMode.prompt => switch (environment.promptMode ??
          PromptMode.arg) {
        PromptMode.arg || PromptMode.flag => null,
        PromptMode.none =>
          'it declares primeMode prompt with promptMode none, so a consumed '
              'handoff has no transport to the child',
      },
    };

/// Plans [seat]'s occupancy of [environment] — PURE.
///
/// The driven-session posture is DECLARED and dropped: `spawnFor` renders
/// [AgentEnvironment.drivenArgs] and an operator seat does not, and
/// [handoffBody] rides the ONE transport [environment] declares: a prompt
/// segment (or a channel's first message) under [SeatPrimeMode.prompt], and
/// [kConsumedHandoffEnvironmentVariable] in the child's process environment
/// under [SeatPrimeMode.hook], where the harness's own SessionStart hook —
/// `prime` — injects it. A hook-primed child reads no disc for it: the
/// launcher consumed the note before this plan existed.
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
  final (:priming, :hookDelivery) = switch (environment.primeMode ??
      SeatPrimeMode.prompt) {
    SeatPrimeMode.hook => (priming: null, hookDelivery: handoffBody),
    SeatPrimeMode.prompt => (priming: handoffBody, hookDelivery: null),
  };
  final processEnvironment = <String, String>{
    ...environment.env,
    kSeatEnvironmentVariable: seat,
    kGridHomeEnvironmentVariable: gridHome,
    if (hookDelivery != null) kConsumedHandoffEnvironmentVariable: hookDelivery,
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

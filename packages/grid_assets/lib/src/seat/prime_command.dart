/// `prime --hook-json` — the grid's OWN SessionStart hook target, replacing the
/// vended `bd prime --hook-json` registration.
///
/// It ECHOES `bd prime` verbatim (Nico, 2026-09-03) and, only when the process
/// occupies an operator seat AND the SessionStart `source` is `startup`,
/// `clear` or `compact`, APPENDS that seat's newest handoff after one naming
/// line. A `resume` source echoes bd's context byte-for-byte and never reads the
/// disc because the context survives a resume; injecting there is pure
/// inference cost (Nico, 2026-09-04). It injects nothing else — no disc summary
/// and no disc-recording instructions:
/// `the_grid#agent-disc-file-shape-and-home` section 5 says "Nothing injects
/// the disc, or disc-recording instructions, per session", and the harness
/// already loads the disc natively once `AgentEnvironment.memoryDirArgs` points
/// its memory directory at it.
///
/// It exits 0 in EVERY case. A hook that fails must not fail a session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdRunner, ProcessBdRunner;

import 'seat_disc.dart';

/// The hook event this verb answers when a payload names none.
const String kSessionStartHookEvent = 'SessionStart';

/// The four SessionStart sources the harness sends. Sealed by the enum so the
/// injection-cost rule is consumed with an exhaustive switch.
enum SessionStartSource {
  /// A new process context.
  startup,

  /// A resumed context, which already retains its prior context.
  resume,

  /// A context cleared in place.
  clear,

  /// A context compacted in place.
  compact,
}

String _currentDirectory() => Directory.current.path;
Map<String, String> _processEnvironment() => Platform.environment;
BdRunner _processRunnerFor(String cwd) => ProcessBdRunner(workspaceRoot: cwd);
Future<String> _readStdinPayload() => stdin
    .transform(utf8.decoder)
    .join()
    .timeout(const Duration(seconds: 2), onTimeout: () => '');

/// bd's own `additionalContext` out of a `bd prime --hook-json` [stdout].
///
/// TOLERANT by design: the raw hook object, a `BD_JSON_ENVELOPE=1` wrapper
/// ([ProcessBdRunner] forces that envelope on), and unparsable output all
/// resolve to a String — empty when bd said nothing. PURE.
String extractBdAdditionalContext(String stdout) {
  final trimmed = stdout.trim();
  if (trimmed.isEmpty) return '';
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return '';
  }
  for (var depth = 0; depth < 4; depth++) {
    if (decoded is! Map<String, Object?>) return '';
    final hook = decoded['hookSpecificOutput'];
    if (hook is Map<String, Object?>) {
      final context = hook['additionalContext'];
      return context is String ? context : '';
    }
    decoded = decoded['data'];
  }
  return '';
}

/// The ONE line that precedes an injected handoff body. PURE.
String handoffNamingLine(SeatHandoff handoff) =>
    'Handoff ${handoff.relativePath} — act on Resume here, then delete this '
    'file and its MEMORY.md line in this turn.';

/// The `additionalContext` this verb emits: [bdContext] VERBATIM, plus — only
/// when [handoff] is non-null — [handoffNamingLine] and the handoff BODY. PURE.
String composePrimeContext({required String bdContext, SeatHandoff? handoff}) {
  if (handoff == null) return bdContext;
  final note = '${handoffNamingLine(handoff)}\n\n${handoff.body}';
  if (bdContext.isEmpty) return note;
  final separator = bdContext.endsWith('\n') ? '\n' : '\n\n';
  return '$bdContext$separator$note';
}

/// The hook object a SessionStart hook writes on stdout. PURE.
String renderPrimeHookJson({
  required String hookEventName,
  required String additionalContext,
}) => jsonEncode(<String, Object?>{
  'hookSpecificOutput': <String, Object?>{
    'hookEventName': hookEventName,
    'additionalContext': additionalContext,
  },
});

/// The event name carried by a SessionStart [payload], defaulting to
/// [kSessionStartHookEvent] when absent or malformed. PURE.
String hookEventNameOf(String payload) {
  final trimmed = payload.trim();
  if (trimmed.isEmpty) return kSessionStartHookEvent;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, Object?>) {
      final name = decoded['hook_event_name'];
      if (name is String && name.isNotEmpty) return name;
    }
  } on FormatException {
    return kSessionStartHookEvent;
  }
  return kSessionStartHookEvent;
}

/// The SessionStart source carried by [payload], or `null` when absent,
/// unknown or malformed. PURE.
SessionStartSource? hookSourceOf(String payload) {
  final trimmed = payload.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, Object?>) return null;
    return switch (decoded['source']) {
      'startup' => SessionStartSource.startup,
      'resume' => SessionStartSource.resume,
      'clear' => SessionStartSource.clear,
      'compact' => SessionStartSource.compact,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// Whether the seat's newest handoff is injected for [payload].
///
/// Nico's 2026-09-04 ruling is explicit: a fresh, cleared or compacted context
/// needs the handoff, while a resumed context already retains it. Unknown and
/// malformed sources fail closed to bd's context only rather than spending
/// inference on an unproved injection.
bool shouldInjectHandoff(String payload) => switch (hookSourceOf(payload)) {
  SessionStartSource.startup ||
  SessionStartSource.clear ||
  SessionStartSource.compact => true,
  SessionStartSource.resume || null => false,
};

/// `prime [--hook-json]` — the thin adapter over the pure composers above.
class PrimeCommand extends Command<int> {
  /// Creates the verb over its four injectable seams: [runnerFor] spawns `bd`
  /// in the cwd, [environment] reads `GRID_SEAT`/`GRID_HOME`, [cwd] is the
  /// fallback grid home, and [readStdin] takes the hook payload. [out] is where
  /// the hook object is written.
  PrimeCommand({
    BdRunner Function(String cwd) runnerFor = _processRunnerFor,
    Map<String, String> Function() environment = _processEnvironment,
    String Function() cwd = _currentDirectory,
    Future<String> Function() readStdin = _readStdinPayload,
    StringSink? out,
  }) : _runnerFor = runnerFor,
       _environment = environment,
       _cwd = cwd,
       _readStdin = readStdin,
       _out = out ?? stdout {
    argParser.addFlag(
      'hook-json',
      negatable: false,
      help:
          'Read the SessionStart payload on stdin and write the hook object on '
          'stdout. Without it the context is written as plain text.',
    );
  }

  final BdRunner Function(String cwd) _runnerFor;
  final Map<String, String> Function() _environment;
  final String Function() _cwd;
  final Future<String> Function() _readStdin;
  final StringSink _out;

  @override
  final String name = 'prime';

  @override
  final String description =
      "Answer a SessionStart hook: echo bd prime, then inject only the seat's "
      'newest handoff.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape = 'prime [--hook-json]';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final hookJson = argResults!.flag('hook-json');
    final payload = hookJson ? await _payload() : '';
    final context = await _context(payload);
    _out.writeln(
      hookJson
          ? renderPrimeHookJson(
              hookEventName: hookEventNameOf(payload),
              additionalContext: context,
            )
          : context,
    );
    return 0;
  }

  /// The hook payload, or '' when stdin is closed, empty, or slow.
  Future<String> _payload() async {
    try {
      return await _readStdin();
    } on Object {
      return '';
    }
  }

  /// The composed context, or '' when ANY step fails — a hook that fails must
  /// not fail a session, so every failure degrades to an empty injection and
  /// exit 0.
  Future<String> _context(String payload) async {
    try {
      final here = _cwd();
      final result = await _runnerFor(here).run(const [
        'prime',
        '--hook-json',
      ], timeout: const Duration(seconds: 10));
      final bdContext = result.ok
          ? extractBdAdditionalContext(result.stdout)
          : '';
      final env = _environment();
      final seat = env[kSeatEnvironmentVariable]?.trim() ?? '';
      final declaredHome = env[kGridHomeEnvironmentVariable]?.trim() ?? '';
      final home = declaredHome.isEmpty ? here : declaredHome;
      final handoff = seat.isEmpty || !shouldInjectHandoff(payload)
          ? null
          : SeatDisc(
              directory: seatDiscPath(home, seat),
              gridHome: home,
            ).newestHandoff();
      return composePrimeContext(bdContext: bdContext, handoff: handoff);
    } on Object {
      return '';
    }
  }
}

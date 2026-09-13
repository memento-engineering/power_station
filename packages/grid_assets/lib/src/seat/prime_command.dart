/// `prime --hook-json` — the grid's OWN SessionStart hook target, replacing the
/// vended `bd prime --hook-json` registration.
///
/// It answers for the STATION, and it POINTS rather than restates
/// (`memento-engineering#a-station-explains-itself-through-prime-and-bounded-help`
/// obligation 1). The station's identity, how it is invoked, every verb it
/// exposes BY NAME, where ratified decisions live and which verb searches them,
/// where the seat's own disc is, and what wakes a seat: those are the facts no
/// other surface answers, and a seat that has to infer them builds a substitute
/// for a verb that already exists. Every verb is a POINTER at its own `help` —
/// whatever a verb's help can answer, prime must not duplicate, because the
/// root help is already ~1,700 tokens and a copy of it here would cost the
/// window twice.
///
/// The verb list is DERIVED from the composed [CommandRunner] at run time, not
/// authored here. A hand-written list is the same defect one layer down: it
/// drifts the moment a station composes a verb this package never heard of.
///
/// Beneath that it carries the issue tracker's own reference — it ECHOES `bd
/// prime` verbatim (Nico, 2026-09-03) under a labelled heading, so the material
/// that used to be the WHOLE answer stays reachable without being it — and,
/// only when the process occupies an operator seat AND the SessionStart
/// `source` is `startup`, `clear` or `compact`, APPENDS that seat's handoff
/// after one naming line.
///
/// WHICH handoff is the launcher's call. Since `pow-d5ol` the seat launcher
/// consumes the note itself and hands this session the body in
/// [kConsumedHandoffEnvironmentVariable] — that declaration wins, and it is the
/// ONLY priming a `SeatPrimeMode.hook` harness gets, because the note it names
/// is already archived and deleted. With no declaration the disc is read
/// instead, which is the hand-started session: that note is named with one
/// [seatHandoffAgeDiagnostic] line — how long it has sat unconsumed, the
/// difference between a handoff written at this boundary and a seat that never
/// handed off — and the succession verb is named as the recovery it is owed.
/// A `resume` source reads neither,
/// because the context survives a resume and injecting there is pure inference
/// cost (Nico, 2026-09-04). It injects nothing else — no disc summary
/// and no disc-recording instructions:
/// `the_grid#agent-disc-file-shape-and-home` section 5 says "Nothing injects
/// the disc, or disc-recording instructions, per session", and the harness
/// already loads the disc natively once `AgentEnvironment.memoryDirArgs` points
/// its memory directory at it.
///
/// The whole answer is BOUNDED by the pack's one [boundedOutput] selector, so
/// the verb that exists to cut a session's opening cost cannot become the cost:
/// prime supplies only its own trim POLICY — tracker body first, then the
/// handoff body, then whole verb-pointer records — and every cut NAMES the
/// bytes withheld and how to ask for them.
///
/// It exits 0 in EVERY case. A hook that fails must not fail a session, so
/// every dependency — the tracker, the environment, the working directory, the
/// disc, the payload — is isolated to its own degraded value.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show BdRunner, ProcessBdRunner;

import '../io/bounded_output.dart';
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

/// The ONE handoff body an answer injects, with the single line that NAMES it
/// and the pointer that replaces the body when the bound withholds it.
///
/// Two ORIGINS, and what separates them is what the reader is owed:
///
///  - [PrimeHandoff.consumed] — the LAUNCHER archived this note, proved the
///    archive, deleted it and its one `MEMORY.md` pointer line, and handed the
///    body to this session through [kConsumedHandoffEnvironmentVariable]
///    (`pow-d5ol`). There is nothing on the disc and no verb is owed — telling
///    a successor to "run the succession verb in this turn" would send it after
///    a note the launcher already destroyed;
///  - [PrimeHandoff.unconsumed] — a note is still ON the disc, which by
///    construction means no launcher consumed it: this session was started by
///    hand, and the succession verb is the HAND-RECOVERY path that archives and
///    deletes it.
///
/// PURE.
final class PrimeHandoff {
  const PrimeHandoff._({
    required this.namingLine,
    required this.body,
    required this.recovery,
  });

  /// The note the launcher consumed for this occupancy, delivered in the
  /// process environment.
  factory PrimeHandoff.consumed(String body) => PrimeHandoff._(
    namingLine:
        'Handoff — CONSUMED by the launcher before this session started: it '
        'archived the disc and deleted the note and its index line. Act on '
        'Resume here; there is nothing on the disc and no verb to run.',
    body: body,
    recovery:
        'the launcher archived this note before deleting it — its CONSUMED '
        'line names the archive',
  );

  /// A note still live on the disc — no launcher consumed it.
  factory PrimeHandoff.unconsumed(SeatHandoff handoff) => PrimeHandoff._(
    namingLine:
        'Handoff ${handoff.relativePath} — still on the disc, so no launcher '
        'consumed it. Act on Resume here, then run the succession verb to '
        'archive and delete it.',
    body: handoff.body,
    recovery: 'read ${handoff.relativePath} from the Agent Disc',
  );

  /// The ONE line that precedes the body.
  final String namingLine;

  /// The BODY: the prose the successor acts on, front matter never included.
  final String body;

  /// How to reach the body when the bound withheld it — the pointer, without
  /// which a trim would leave the reader nowhere to go.
  final String recovery;

  /// This handoff with its body replaced by the pointer naming the [bytes]
  /// withheld. The naming line SURVIVES: a seat that is not told a handoff
  /// exists cannot go and read it.
  PrimeHandoff withheld(int bytes) => PrimeHandoff._(
    namingLine: namingLine,
    body: 'Withheld: $bytes handoff-body bytes; $recovery.',
    recovery: recovery,
  );
}

/// The `additionalContext` this verb emits: [bdContext] VERBATIM, plus — only
/// when [handoff] is non-null — its [PrimeHandoff.namingLine], an optional
/// [handoffDiagnostic] line, and the handoff BODY. PURE.
///
/// [handoffDiagnostic] is [seatHandoffAgeDiagnostic]'s line, and it sits between
/// the naming line and the body so a seat reads how OLD the note is before it
/// reads the note: a handoff that has been sitting for hours is a succession
/// that did not happen, and the body alone cannot say so. It belongs to the
/// UNCONSUMED origin only — a note the launcher consumed at this launch has no
/// age to report.
String composePrimeContext({
  required String bdContext,
  PrimeHandoff? handoff,
  String? handoffDiagnostic,
}) {
  if (handoff == null) return bdContext;
  final head = <String>[
    handoff.namingLine,
    if (handoffDiagnostic != null) handoffDiagnostic,
  ].join('\n');
  final note = '$head\n\n${handoff.body}';
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

/// The heading over the verb POINTERS.
const String _verbsHeading = 'Verbs:';

/// The heading over the SUBORDINATE tracker reference — the material that used
/// to be the whole answer, kept reachable and clearly not the station's own.
const String _trackerHeading = 'Tracker reference (bd prime):';

/// What stands under that heading when `bd` said nothing this prime can pass
/// on. It POINTS: the tracker is still one command away.
const String _trackerUnavailable = 'Unavailable here; run bd prime.';

/// The UTF-8 weight of one line record — what dropping it gives back, and what
/// keeping it costs.
int _bytesOf(String text) => utf8.encode(text).length;

/// One prime answer, assembled and ready to render — the value the pack's
/// bound selects between.
///
/// Every part is already whole: an orientation line, a tracker section and a
/// handoff are kept entire or replaced entire by a record that NAMES what went
/// missing. Nothing here holds a fragment of a line, a rune or a JSON envelope.
final class _PrimeAnswer {
  const _PrimeAnswer({
    required this.orientation,
    required this.tracker,
    required this.handoff,
    required this.handoffDiagnostic,
  });

  /// The station-orientation records — identity, invocation, the verb pointers
  /// and the decision/disc/wake facts — or the ONE line naming their withheld
  /// bytes.
  final List<String> orientation;

  /// bd's own context VERBATIM, the unavailable pointer, or the line naming the
  /// bytes withheld.
  final String tracker;

  /// The handoff this answer injects, whose BODY may itself be a
  /// withheld-bytes pointer. Its naming line survives either way: a seat that
  /// is not told a handoff exists cannot go and read it.
  final PrimeHandoff? handoff;

  /// How OLD that unconsumed handoff is, or null when the injected note was
  /// consumed by the launcher at this launch, or when there is none at all.
  ///
  /// NOT droppable. It is one line, and it is the line that distinguishes a
  /// handoff written at this boundary from one that has been sitting for nine
  /// hours — a trim that gave it up would leave the cheapest signal out while
  /// keeping the expensive body.
  final String? handoffDiagnostic;

  /// The `additionalContext` this answer is.
  String render() => composePrimeContext(
    bdContext: [...orientation, '', _trackerHeading, tracker].join('\n'),
    handoff: handoff,
    handoffDiagnostic: handoffDiagnostic,
  );
}

/// Everything one prime answer could say, with the cost of each droppable
/// part — this verb's own trim POLICY, and nothing of the bound itself.
///
/// The droppable material is ONE priority-ordered list: the verb pointers, then
/// the handoff body, then the tracker body. A budget keeps the longest PREFIX
/// of it that fits, so the tracker reference goes first, the handoff body next
/// and the verb pointers last — and the rendering only ever grows with the
/// budget, which is what makes the pack's binary search over it correct.
final class _PrimeMaterial {
  _PrimeMaterial({
    required this.executableName,
    required this.heading,
    required this.verbs,
    required this.trailer,
    required this.trackerBody,
    required this.handoff,
    required this.handoffDiagnostic,
  });

  /// The station executable — what a withheld record tells the reader to run.
  final String executableName;

  /// `Station:` and `Invoke:`.
  final List<String> heading;

  /// One `- <verb> — <executable> help <verb>` POINTER per key the composed
  /// runner exposes, aliases included.
  final List<String> verbs;

  /// The `Decisions:`, `Agent Disc:` and `Wake:` records.
  final List<String> trailer;

  /// bd's own context, or null when it could not be read.
  final String? trackerBody;

  /// The handoff injected into this answer, or null when none is.
  final PrimeHandoff? handoff;

  /// [seatHandoffAgeDiagnostic]'s line for that handoff, or null when there is
  /// none. Carried through every candidate: one line is never the cut.
  final String? handoffDiagnostic;

  late final List<int> _verbCosts = [
    for (final record in verbs) _bytesOf(record),
  ];
  late final int _handoffCost = switch (handoff) {
    null => 0,
    final note => _bytesOf(note.body),
  };
  late final int _trackerCost = switch (trackerBody) {
    null => 0,
    final body => _bytesOf(body),
  };
  late final int _orientationCost = _bytesOf(
    _orientationLines(verbs, null).join('\n'),
  );

  /// The largest budget worth searching: every droppable byte.
  int get maximumTrimBudget =>
      _verbCosts.fold(0, (sum, cost) => sum + cost) +
      _handoffCost +
      _trackerCost;

  /// The whole answer, nothing withheld.
  _PrimeAnswer get complete => trimTo(maximumTrimBudget);

  /// The answer that spends at most [budget] bytes on droppable material.
  _PrimeAnswer trimTo(int budget) {
    if (budget <= 0) return _collapsed();
    var spent = 0;
    var keptVerbs = 0;
    while (keptVerbs < verbs.length &&
        spent + _verbCosts[keptVerbs] <= budget) {
      spent += _verbCosts[keptVerbs];
      keptVerbs++;
    }
    final keepsHandoff =
        keptVerbs == verbs.length && spent + _handoffCost <= budget;
    if (keepsHandoff) spent += _handoffCost;
    final keepsTracker = keepsHandoff && spent + _trackerCost <= budget;
    final droppedVerbs = verbs.length - keptVerbs;
    return _PrimeAnswer(
      orientation: _orientationLines(
        verbs.take(keptVerbs).toList(growable: false),
        droppedVerbs == 0
            ? null
            : 'Withheld: $droppedVerbs verb-pointer records '
                  '(${_verbCosts.skip(keptVerbs).fold(0, (sum, cost) => sum + cost)} '
                  'bytes); run $executableName help.',
      ),
      tracker: switch (trackerBody) {
        null => _trackerUnavailable,
        final body when keepsTracker => body,
        _ => 'Withheld: $_trackerCost tracker-reference bytes; run bd prime.',
      },
      handoff: switch (handoff) {
        null => null,
        final note when keepsHandoff => note,
        final note => note.withheld(_handoffCost),
      },
      handoffDiagnostic: handoffDiagnostic,
    );
  }

  /// The floor: the orientation itself replaced by the count of its withheld
  /// bytes. Reached only when a station's own identity cannot fit the cap, and
  /// it still POINTS at the help that carries it.
  _PrimeAnswer _collapsed() => _PrimeAnswer(
    orientation: [
      'Withheld: $_orientationCost station-orientation bytes; run the '
          'station executable with help.',
    ],
    tracker: switch (trackerBody) {
      null => _trackerUnavailable,
      _ => 'Withheld: $_trackerCost tracker-reference bytes; run bd prime.',
    },
    handoff: switch (handoff) {
      null => null,
      final note => note.withheld(_handoffCost),
    },
    handoffDiagnostic: handoffDiagnostic,
  );

  /// The orientation block: heading, the verb pointers under their own
  /// heading with [note] naming any dropped record, then the trailer.
  List<String> _orientationLines(List<String> keptVerbs, String? note) => [
    ...heading,
    '',
    _verbsHeading,
    ...keptVerbs,
    if (note != null) note,
    '',
    ...trailer,
  ];
}

/// `prime [--hook-json]` — the thin adapter over the pure composers above.
class PrimeCommand extends Command<int> {
  /// Creates the verb over its five injectable seams: [runnerFor] spawns `bd`
  /// in the cwd, [environment] reads `GRID_SEAT`, `GRID_HOME` and the
  /// launcher's [kConsumedHandoffEnvironmentVariable], [cwd] is the fallback
  /// grid home, [readStdin] takes the hook payload, and [now] is the clock the
  /// unconsumed-handoff age is measured against. [out] is where the hook object
  /// is written.
  PrimeCommand({
    BdRunner Function(String cwd) runnerFor = _processRunnerFor,
    Map<String, String> Function() environment = _processEnvironment,
    String Function() cwd = _currentDirectory,
    Future<String> Function() readStdin = _readStdinPayload,
    DateTime Function() now = DateTime.now,
    StringSink? out,
  }) : _runnerFor = runnerFor,
       _environment = environment,
       _cwd = cwd,
       _readStdin = readStdin,
       _now = now,
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
  final DateTime Function() _now;
  final StringSink _out;

  @override
  final String name = 'prime';

  @override
  final String description =
      'Orient a session in this station: its verbs, its decisions, the seat '
      "disc, then bd prime and the seat's newest handoff.";

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
    final hookEventName = hookEventNameOf(payload);
    final material = await _material(payload);
    final context = boundedOutput<_PrimeAnswer>(
      complete: material.complete,
      maximumTrimBudget: material.maximumTrimBudget,
      renderPlain: (answer) => answer.render(),
      renderJson: (answer) => renderPrimeHookJson(
        hookEventName: hookEventName,
        additionalContext: answer.render(),
      ),
      trim: material.trimTo,
    ).render();
    _out.writeln(
      hookJson
          ? renderPrimeHookJson(
              hookEventName: hookEventName,
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

  /// Everything this answer could say, each dependency isolated: a failing
  /// tracker, environment, working directory or disc degrades to its own
  /// unavailable value and NEVER to a failed session.
  Future<_PrimeMaterial> _material(String payload) async {
    final station = runner;
    if (station == null) {
      throw StateError(
        'prime names the verbs of the runner it is composed into, and it is '
        'composed into none',
      );
    }
    final here = _here();
    final environment = _environmentOrEmpty();
    final seat = environment[kSeatEnvironmentVariable]?.trim() ?? '';
    final declaredHome =
        environment[kGridHomeEnvironmentVariable]?.trim() ?? '';
    final home = declaredHome.isEmpty ? here : declaredHome;
    final executable = station.executableName;
    final injected = _injectedHandoff(
      home: home,
      seat: seat,
      payload: payload,
      environment: environment,
    );
    return _PrimeMaterial(
      executableName: executable,
      heading: [
        'Station: $executable — ${station.description}',
        'Invoke: ${station.invocation}',
      ],
      // DERIVED, never authored: the composed runner already knows its own
      // command set, aliases included, and a list maintained here would drift
      // the moment a station adds a verb.
      verbs: [
        for (final verb in station.commands.keys.toList()..sort())
          '- $verb — $executable help $verb',
      ],
      trailer: [
        'Decisions: docs/decisions/ in every mounted substation; ratified '
            'decisions bind. Search with $executable search; usage: '
            '$executable help search.',
        'Agent Disc: '
            '${seat.isEmpty ? '<grid home>/$kSeatsSubdirectory/<seat>/' : seatDiscPath(home, seat)}.',
        'Wake: the resident station evaluates the seat wake predicate on the '
            'existing fenced service tick; a seat adds no second wake '
            'mechanism.',
      ],
      trackerBody: await _trackerBody(here),
      handoff: injected?.handoff,
      handoffDiagnostic: injected?.diagnostic,
    );
  }

  /// [seatHandoffAgeDiagnostic] for [state], or null when the clock itself
  /// cannot be read — one more dependency isolated to its own degraded value,
  /// because a hook must never fail a session.
  String? _ageOf({
    required String seat,
    required ({SeatHandoff handoff, DateTime at}) state,
  }) {
    try {
      return seatHandoffAgeDiagnostic(
        seat: seat,
        handoff: state.handoff,
        authoredAt: state.at,
        now: _now(),
      );
    } on Object {
      return null;
    }
  }

  /// The working directory, or '' when the process cannot name it.
  String _here() {
    try {
      return _cwd();
    } on Object {
      return '';
    }
  }

  /// The process environment, or none.
  Map<String, String> _environmentOrEmpty() {
    try {
      return _environment();
    } on Object {
      return const <String, String>{};
    }
  }

  /// bd's own `additionalContext`, or null when the runner is empty, non-zero,
  /// malformed or unreachable — every one of which is "ask bd yourself", not a
  /// failed session.
  Future<String?> _trackerBody(String here) async {
    try {
      final result = await _runnerFor(here).run(const [
        'prime',
        '--hook-json',
      ], timeout: const Duration(seconds: 10));
      if (!result.ok) return null;
      final context = extractBdAdditionalContext(result.stdout);
      return context.isEmpty ? null : context;
    } on Object {
      return null;
    }
  }

  /// The handoff this answer injects and the age line beside it, or null when
  /// there is no seat, no injection is due for this source, and nothing to
  /// inject.
  ///
  /// The LAUNCHER'S declaration wins. Since `pow-d5ol` the seat launcher
  /// consumes the note before the child exists and delivers the body in
  /// [kConsumedHandoffEnvironmentVariable], so on a hook-primed harness — the
  /// only kind that reaches this verb for its priming — the disc is EMPTY by
  /// the time the hook runs. A disc read is still the fallback, and it is the
  /// hand-recovery path: a note that survived on the disc is one no launcher
  /// touched, which is exactly when the succession verb is owed.
  ///
  /// A consumed body carries no age: it was consumed at this launch, and the
  /// launcher reported the age it had when it did. The disc path resolves the
  /// note and its age in ONE read, so a note written between two reads can
  /// never be named with the other one's timestamp.
  ({PrimeHandoff handoff, String? diagnostic})? _injectedHandoff({
    required String home,
    required String seat,
    required String payload,
    required Map<String, String> environment,
  }) {
    if (seat.isEmpty || !shouldInjectHandoff(payload)) return null;
    final consumed =
        environment[kConsumedHandoffEnvironmentVariable]?.trim() ?? '';
    if (consumed.isNotEmpty) {
      return (handoff: PrimeHandoff.consumed(consumed), diagnostic: null);
    }
    final state = _newestHandoffState(home: home, seat: seat);
    if (state == null) return null;
    return (
      handoff: PrimeHandoff.unconsumed(state.handoff),
      diagnostic: _ageOf(seat: seat, state: state),
    );
  }

  /// The seat's newest handoff WITH the instant it was written, or null when
  /// the disc holds none or cannot be read.
  ({SeatHandoff handoff, DateTime at})? _newestHandoffState({
    required String home,
    required String seat,
  }) {
    try {
      return SeatDisc(
        directory: seatDiscPath(home, seat),
        gridHome: home,
      ).newestHandoffState();
    } on Object {
      return null;
    }
  }
}

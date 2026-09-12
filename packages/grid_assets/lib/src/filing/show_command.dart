/// The ONE-BEAD READ — the station-down-safe counterpart to the resident's
/// `bead board` / `bead round` verbs.
///
/// Those two are serviced BY a running station and refuse when it is down, and
/// neither renders a bead's own prose: to read one bead an operator still had
/// to know which seat mints its prefix and shell `bd` from that root. This verb
/// renders it — id, title, type, status, priority, revision, description,
/// design, acceptance criteria, notes, the `grid.approved_*` stamp and the
/// dependency edges — straight out of the work store, with no station in the
/// path.
///
/// **Read-only by construction (A37).** It reaches the store through exactly
/// one [ExactSubstationBeadSource.readExact] — one exact-id `bd query` plus one
/// `bd dep list` — which has no mutation surface and never calls `bd show`
/// (that write touches `.beads/last-touched` and self-triggers the store's
/// watcher). Nothing here spawns a station, a session or a coding agent.
///
/// **Bounded output** (`power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`):
/// every rendering — plain or structured — fits [kShowOutputCapBytes], and
/// anything cut is NAMED with the byte count withheld. The beads this renders
/// are the long ones (an epic with ten rounds of notes is exactly what a seat
/// asks for), so an uncapped render would land on the largest per-call cost in
/// the system rather than reduce it. Suppression is keyed on the ANSWER, never
/// the question: `--if-revision` withholds the prose only when the bead's own
/// `updated_at` revision proves it unchanged.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart'
    show Bead, BeadDependency, BdRunner, BeadStatus, IssueType, ProcessBdRunner;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

import '../search/station_search.dart';
import 'approval_stamp.dart';
import 'state_root_option.dart';

part 'show_command.freezed.dart';

String _currentDirectory() => Directory.current.path;
BdRunner _processRunnerFor(String storeRoot) =>
    ProcessBdRunner(workspaceRoot: storeRoot);

/// The HARD ceiling on one rendered result, in UTF-8 bytes, counting the
/// trailing newline the command writes. It binds BOTH renderings: the plain
/// text and the single-line JSON object.
///
/// The only thing never cut is the result's SKELETON — the bead id, its type,
/// status, priority and revision, every JSON key and the truncation marker
/// itself — because a render that drops the answer's identity to fit is worse
/// than one that says what it withheld.
const int kShowOutputCapBytes = 8000;

/// The withheld-map key naming DROPPED dependency edges (a count of edges, not
/// of bytes — an edge is kept whole or not at all).
const String _withheldEdgesKey = 'dependency_edges';

/// The report keys of the variable prose chunks, in the FIXED order that
/// breaks a budget tie AND orders the truncation marker's rows.
const List<String> _proseKeys = <String>[
  'title',
  'description',
  'design',
  'acceptance_criteria',
  'notes',
  kApprovedByKey,
  kApprovedAtKey,
  kApprovedRevKey,
];

/// The outcome of one show run — a sealed union so every consumer faces all
/// three arms.
@freezed
sealed class ShowOutcome with _$ShowOutcome {
  const ShowOutcome._();

  /// The bead was read and is rendered in full, or rendered bounded with
  /// [withheld] naming every cut.
  const factory ShowOutcome.shown({
    required String beadId,
    required String title,
    required IssueType issueType,
    required BeadStatus status,
    required int priority,
    required String description,
    required String design,
    required String acceptanceCriteria,
    required String notes,
    required Map<String, String?> approval,
    required List<BeadDependency> dependencies,
    String? revision,
    @Default(<String, int>{}) Map<String, int> withheld,
  }) = BeadShown;

  /// The bead's current revision is EXACTLY the one the caller already holds,
  /// so the prose and the edges are withheld as provably stale-free.
  const factory ShowOutcome.unchanged({
    required String beadId,
    required String revision,
  }) = ShowUnchanged;

  /// The bead was NOT rendered, and [reason] says why.
  const factory ShowOutcome.refused({
    required String beadId,
    required String reason,
    @Default(0) int withheldReasonBytes,
  }) = ShowRefused;

  /// The externally stable structured result — the schema the calling skill
  /// parses instead of scraping the plain rendering (ADR-0001).
  Map<String, Object?> toJson() => switch (this) {
    BeadShown(
      :final beadId,
      :final title,
      :final issueType,
      :final status,
      :final priority,
      :final description,
      :final design,
      :final acceptanceCriteria,
      :final notes,
      :final approval,
      :final dependencies,
      :final revision,
      :final withheld,
    ) =>
      {
        'id': beadId,
        'shown': true,
        'unchanged': false,
        'revision': revision,
        'title': title,
        'type': issueType.wire,
        'status': status.wire,
        'priority': priority,
        'description': description,
        'design': design,
        'acceptance_criteria': acceptanceCriteria,
        'notes': notes,
        'approval': approval,
        'dependencies': [
          for (final edge in dependencies) _dependencyJson(edge),
        ],
        if (withheld.isNotEmpty)
          'truncation': {
            'cap_bytes': kShowOutputCapBytes,
            'withheld': withheld,
          },
      },
    ShowUnchanged(:final beadId, :final revision) => {
      'id': beadId,
      'shown': true,
      'unchanged': true,
      'revision': revision,
    },
    ShowRefused(:final beadId, :final reason, :final withheldReasonBytes) => {
      'id': beadId,
      'shown': false,
      'reason': reason,
      if (withheldReasonBytes > 0)
        'truncation': {
          'cap_bytes': kShowOutputCapBytes,
          'withheld': {'reason': withheldReasonBytes},
        },
    },
  };
}

/// One dependency edge, rendered from beads' OWN [BeadDependency] — this verb
/// declares no parallel edge type of its own.
Map<String, Object?> _dependencyJson(BeadDependency edge) => {
  'issue_id': edge.issueId,
  'depends_on_id': edge.dependsOnId,
  'type': edge.type.wire,
};

// ── the bounding path ────────────────────────────────────────────────────────

/// One variable-length chunk of a shown bead — a prose field or one approval
/// stamp value — with its per-rune costs precomputed ONCE so the budget search
/// below never re-encodes the whole string.
final class _ProseChunk {
  factory _ProseChunk(String key, String? value) {
    if (value == null) {
      return _ProseChunk._(key, null, const <int>[], const <int>[0], const [0]);
    }
    final runes = value.runes.toList(growable: false);
    final jsonCost = <int, int>{};
    final utf8Cost = <int, int>{};
    final jsonPrefix = List<int>.filled(runes.length + 1, 0);
    final utf8Prefix = List<int>.filled(runes.length + 1, 0);
    // The two quotes every JSON string pays before a single rune of content.
    jsonPrefix[0] = 2;
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      final char = String.fromCharCode(rune);
      jsonPrefix[i + 1] =
          jsonPrefix[i] +
          jsonCost.putIfAbsent(
            rune,
            () => utf8.encode(jsonEncode(char)).length - 2,
          );
      utf8Prefix[i + 1] =
          utf8Prefix[i] +
          utf8Cost.putIfAbsent(rune, () => utf8.encode(char).length);
    }
    return _ProseChunk._(key, value, runes, jsonPrefix, utf8Prefix);
  }

  const _ProseChunk._(
    this.key,
    this.value,
    this._runes,
    this._jsonPrefix,
    this._utf8Prefix,
  );

  /// The JSON field or approval-metadata key this chunk is reported under.
  final String key;

  /// The untrimmed text, or null for an absent approval stamp value.
  final String? value;

  final List<int> _runes;
  final List<int> _jsonPrefix;
  final List<int> _utf8Prefix;

  /// What emitting this chunk WHOLE costs the payload budget. An absent value
  /// is structural, not content, so it costs nothing and is never cut.
  int get cost => value == null ? 0 : _jsonPrefix.last;

  /// The longest Unicode-RUNE prefix whose JSON-encoded form fits [share],
  /// with the UTF-8 bytes of the original it drops.
  ///
  /// Cutting on runes (never code units, never bytes) is what keeps a
  /// multibyte character from being halved into a replacement glyph.
  ({String? text, int withheldBytes}) cutTo(int share) {
    final value = this.value;
    if (value == null) return (text: null, withheldBytes: 0);
    if (_jsonPrefix.last <= share) return (text: value, withheldBytes: 0);
    var keep = 0;
    var low = 0;
    var high = _runes.length;
    while (low <= high) {
      final mid = low + (high - low) ~/ 2;
      if (_jsonPrefix[mid] <= share) {
        keep = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return (
      text: String.fromCharCodes(_runes.take(keep)),
      withheldBytes: _utf8Prefix.last - _utf8Prefix[keep],
    );
  }
}

/// The variable chunks of [shown], in [_proseKeys] order.
List<_ProseChunk> _proseChunksOf(BeadShown shown) {
  final values = <String?>[
    shown.title,
    shown.description,
    shown.design,
    shown.acceptanceCriteria,
    shown.notes,
    shown.approval[kApprovedByKey],
    shown.approval[kApprovedAtKey],
    shown.approval[kApprovedRevKey],
  ];
  return [
    for (var i = 0; i < _proseKeys.length; i++)
      _ProseChunk(_proseKeys[i], values[i]),
  ];
}

/// MAX-MIN water filling: hands every chunk an equal integer share of
/// [budget], settles each one whose full [costs] entry already fits that
/// share, and redistributes the unused remainder over the chunks still
/// pending. A long field cannot starve a short one, and no chunk is ever
/// given more than it can spend.
///
/// [divisible] separates the two kinds of chunk, and that distinction is what
/// keeps the marker HONEST. A prose string can spend any share, down to one
/// rune; a dependency edge is emitted whole or not at all, so an edge holding
/// a share it cannot afford is budget withheld from the reader for nothing.
/// When no chunk can settle and some pending chunk is indivisible, those
/// chunks are dropped FIRST and their allocation is re-poured over the chunks
/// that can actually use it.
List<int> _waterFill(List<int> costs, List<bool> divisible, int budget) {
  final shares = List<int>.filled(costs.length, 0);
  final pending = <int>[for (var i = 0; i < costs.length; i++) i];
  var remaining = budget;
  while (pending.isNotEmpty) {
    final share = remaining ~/ pending.length;
    final settled = [
      for (final index in pending)
        if (costs[index] <= share) index,
    ];
    if (settled.isNotEmpty) {
      for (final index in settled) {
        shares[index] = costs[index];
        remaining -= costs[index];
      }
      pending.removeWhere(settled.contains);
      continue;
    }
    final unaffordable = [
      for (final index in pending)
        if (!divisible[index]) index,
    ];
    if (unaffordable.isNotEmpty && unaffordable.length < pending.length) {
      pending.removeWhere(unaffordable.contains);
      continue;
    }
    for (final index in pending) {
      shares[index] = share;
    }
    break;
  }
  return shares;
}

/// [shown] rendered down to a payload [budget]: every invariant field kept,
/// each prose/approval string cut to its water-filled share, and only the
/// LEADING dependency edges whose complete encoded maps fit theirs.
BeadShown _trimShown(
  BeadShown shown,
  List<_ProseChunk> prose,
  List<int> edgeCosts,
  int budget,
) {
  final shares = _waterFill(
    [for (final chunk in prose) chunk.cost, ...edgeCosts],
    [for (final _ in prose) true, for (final _ in edgeCosts) false],
    budget,
  );
  final withheld = <String, int>{};
  final texts = <String, String?>{};
  for (var i = 0; i < prose.length; i++) {
    final cut = prose[i].cutTo(shares[i]);
    texts[prose[i].key] = cut.text;
    if (cut.withheldBytes > 0) withheld[prose[i].key] = cut.withheldBytes;
  }
  var kept = 0;
  while (kept < edgeCosts.length &&
      edgeCosts[kept] <= shares[prose.length + kept]) {
    kept++;
  }
  if (kept < edgeCosts.length) {
    withheld[_withheldEdgesKey] = edgeCosts.length - kept;
  }
  return shown.copyWith(
    title: texts['title'] ?? '',
    description: texts['description'] ?? '',
    design: texts['design'] ?? '',
    acceptanceCriteria: texts['acceptance_criteria'] ?? '',
    notes: texts['notes'] ?? '',
    approval: {
      kApprovedByKey: texts[kApprovedByKey],
      kApprovedAtKey: texts[kApprovedAtKey],
      kApprovedRevKey: texts[kApprovedRevKey],
    },
    dependencies: shown.dependencies.take(kept).toList(growable: false),
    withheld: withheld,
  );
}

/// Whether BOTH complete newline-terminated renderings of [outcome] — the JSON
/// line and the plain text, truncation marker included — fit the cap.
bool _fitsCap(ShowOutcome outcome) =>
    utf8.encode('${jsonEncode(outcome.toJson())}\n').length <=
        kShowOutputCapBytes &&
    utf8.encode('${_renderPlain(outcome)}\n').length <= kShowOutputCapBytes;

/// The ONE bounding path every returned outcome passes through.
///
/// Never a silent clip: whatever it cuts, it names. An outcome that already
/// fits comes back untouched.
ShowOutcome _bounded(ShowOutcome outcome) {
  if (_fitsCap(outcome)) return outcome;
  return switch (outcome) {
    BeadShown() => _boundedShown(outcome),
    ShowRefused() => _boundedRefused(outcome),
    // The skeleton alone — id and revision — is all an unchanged answer is.
    ShowUnchanged() => outcome,
  };
}

BeadShown _boundedShown(BeadShown shown) {
  final prose = _proseChunksOf(shown);
  final edgeCosts = [
    for (final edge in shown.dependencies)
      utf8.encode(jsonEncode(_dependencyJson(edge))).length,
  ];
  var low = 0;
  var high =
      prose.fold(0, (sum, chunk) => sum + chunk.cost) +
      edgeCosts.fold(0, (sum, cost) => sum + cost);
  var best = 0;
  while (low <= high) {
    final mid = low + (high - low) ~/ 2;
    if (_fitsCap(_trimShown(shown, prose, edgeCosts, mid))) {
      best = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return _trimShown(shown, prose, edgeCosts, best);
}

ShowRefused _boundedRefused(ShowRefused refused) {
  final chunk = _ProseChunk('reason', refused.reason);
  var low = 0;
  var high = chunk.cost;
  var best = _cutRefusal(refused, chunk, 0);
  while (low <= high) {
    final mid = low + (high - low) ~/ 2;
    final candidate = _cutRefusal(refused, chunk, mid);
    if (_fitsCap(candidate)) {
      best = candidate;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return best;
}

ShowRefused _cutRefusal(ShowRefused refused, _ProseChunk chunk, int share) {
  final cut = chunk.cutTo(share);
  return refused.copyWith(
    reason: cut.text ?? '',
    withheldReasonBytes: cut.withheldBytes,
  );
}

// ── the plain rendering ──────────────────────────────────────────────────────

/// The plain rendering of one bounded [outcome] — the single renderer both the
/// bound calculation and [ShowCommand] consume, so what the cap is measured
/// against is exactly what is printed.
String _renderPlain(ShowOutcome outcome) {
  switch (outcome) {
    case ShowUnchanged(:final beadId, :final revision):
      return 'UNCHANGED $beadId revision $revision';
    case ShowRefused(:final beadId, :final reason, :final withheldReasonBytes):
      final buffer = StringBuffer('REFUSED $beadId: $reason');
      if (withheldReasonBytes > 0) {
        buffer
          ..writeln()
          ..writeln('TRUNCATION:')
          ..writeln('cap_bytes: $kShowOutputCapBytes')
          ..write('reason: $withheldReasonBytes bytes withheld');
      }
      return buffer.toString();
    case BeadShown(
      :final beadId,
      :final title,
      :final issueType,
      :final status,
      :final priority,
      :final description,
      :final design,
      :final acceptanceCriteria,
      :final notes,
      :final approval,
      :final dependencies,
      :final revision,
      :final withheld,
    ):
      final buffer = StringBuffer()
        ..writeln('ID: $beadId')
        ..writeln('TITLE: $title')
        ..writeln('TYPE: ${issueType.wire}')
        ..writeln('STATUS: ${status.wire}')
        ..writeln('PRIORITY: $priority')
        ..writeln('REVISION: ${revision ?? ''}')
        ..writeln('DESCRIPTION:')
        ..writeln(description)
        ..writeln('DESIGN:')
        ..writeln(design)
        ..writeln('ACCEPTANCE CRITERIA:')
        ..writeln(acceptanceCriteria)
        ..writeln('NOTES:')
        ..writeln(notes)
        ..writeln('APPROVAL:');
      for (final key in const [
        kApprovedByKey,
        kApprovedAtKey,
        kApprovedRevKey,
      ]) {
        buffer.writeln('$key: ${approval[key] ?? ''}');
      }
      buffer.write('DEPENDENCIES:');
      if (dependencies.isEmpty) {
        buffer.write('\n(none)');
      }
      for (final edge in dependencies) {
        buffer.write(
          '\n- issue_id=${edge.issueId} depends_on_id=${edge.dependsOnId} '
          'type=${edge.type.wire}',
        );
      }
      if (withheld.isNotEmpty) {
        buffer
          ..write('\nTRUNCATION:')
          ..write('\ncap_bytes: $kShowOutputCapBytes');
        for (final key in _proseKeys) {
          final count = withheld[key];
          if (count != null) {
            buffer.write('\n$key: $count bytes withheld');
          }
        }
        final edges = withheld[_withheldEdgesKey];
        if (edges != null) {
          buffer.write('\n$_withheldEdgesKey: $edges edges withheld');
        }
      }
      return buffer.toString();
  }
}

// ── the service ──────────────────────────────────────────────────────────────

/// UI-drivable one-bead read: ONE exact-id read of the work store, projected
/// into a bounded [ShowOutcome].
///
/// It composes the SAME [ExactSubstationBeadSource] the filing preflight and
/// the park verbs read through, so there is one exact-read implementation in
/// this package and not a second one per verb. That source owns the exact-id
/// `query`, the single `dep list`, the two dependency-row shapes, the
/// duplicate-id [StateError] and the missing-bead null; this service adds only
/// the projection, the revision comparison and the bound.
final class ShowService {
  /// Creates the service over the two injectable seams — the per-root runner
  /// and, for a test that wants to script the read itself, the source.
  ShowService({
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
    ExactSubstationBeadSource? source,
  }) : _source = source ?? ExactSubstationBeadSource(runnerFor: runnerFor);

  final ExactSubstationBeadSource _source;

  /// Reads [beadId] out of [storeRoot] and renders the outcome.
  ///
  /// [ifRevision] is the revision the caller already holds. When it is
  /// non-blank and EXACTLY equal to the bead's current `updated_at` revision,
  /// the answer is provably unchanged and comes back as [ShowUnchanged]; an
  /// absent, blank or mismatched value — and a bead carrying no revision at
  /// all — always renders fresh. The key is the identity of the ANSWER, never
  /// the text of the request, because a bead is mutable and a stale render is
  /// worse than a re-read.
  ///
  /// No read failure escapes: a refusing `bd`, a malformed envelope and a
  /// duplicate id all arrive as a [ShowRefused] naming the bead and the
  /// failure class.
  Future<ShowOutcome> show({
    required String storeRoot,
    required String beadId,
    String? ifRevision,
  }) async {
    final ({Bead? bead, List<BeadDependency> dependencies}) read;
    try {
      read = await _source.readExact(storeRoot: storeRoot, beadId: beadId);
    } on Object catch (error) {
      return _bounded(
        ShowRefused(
          beadId: beadId,
          reason:
              'reading $beadId from $storeRoot failed '
              '(${error.runtimeType}): $error',
        ),
      );
    }
    final bead = read.bead;
    if (bead == null) {
      return _bounded(
        ShowRefused(
          beadId: beadId,
          reason: 'bead $beadId not found in $storeRoot',
        ),
      );
    }
    final revision = bead.updatedAt?.toIso8601String();
    final requested = ifRevision?.trim();
    if (requested != null &&
        requested.isNotEmpty &&
        revision != null &&
        revision.isNotEmpty &&
        requested == revision) {
      return ShowUnchanged(beadId: beadId, revision: revision);
    }
    return _bounded(
      ShowOutcome.shown(
        beadId: bead.id,
        title: bead.title,
        issueType: bead.issueType,
        status: bead.status,
        priority: bead.priority,
        description: bead.description,
        design: bead.design,
        acceptanceCriteria: bead.acceptanceCriteria,
        notes: bead.notes,
        approval: {
          for (final key in const [
            kApprovedByKey,
            kApprovedAtKey,
            kApprovedRevKey,
          ])
            key: switch (bead.metadata[key]) {
              final String value => value,
              _ => null,
            },
        },
        dependencies: read.dependencies,
        revision: revision,
      ),
    );
  }
}

/// `show [--json] [--if-revision <revision>] [--state-root <path>] <bead-id>` —
/// the one-bead READ verb.
class ShowCommand extends Command<int> {
  /// Creates the thin adapter over [service].
  ///
  /// [storeRoot] is the WORK store the bead is read from (the CWD by default);
  /// [stateRoot] is the station-injected grid home, taken through the SAME
  /// seam `filing`, `approve` and `park` ride so the option cannot mean two
  /// things across the verb set.
  ShowCommand({
    ShowService? service,
    String Function() storeRoot = _currentDirectory,
    String? Function() stateRoot = noStateRoot,
    StringSink? out,
    StringSink? err,
  }) : _service = service ?? ShowService(),
       _storeRoot = storeRoot,
       _stateRoot = stateRoot,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit {id, shown, unchanged, revision, title, type, status, '
            'priority, description, design, acceptance_criteria, notes, '
            'approval, dependencies, truncation?} as one JSON object.',
      )
      ..addOption(
        'if-revision',
        help:
            "The revision already held. When it equals the bead's current "
            'revision the prose and the edges are withheld as unchanged.',
      );
    addStateRootOption(argParser);
  }

  final ShowService _service;
  final String Function() _storeRoot;
  final String? Function() _stateRoot;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'show';

  @override
  final String description =
      'Render one bead — prose, approval stamp and dependency edges — from '
      'the work store, with no station in the path.';

  @override
  String get invocation {
    final executable = runner?.executableName;
    const shape =
        'show [--json] [--if-revision <revision>] [--state-root <path>] '
        '<bead-id>';
    return executable == null ? shape : '$executable $shape';
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      _err.writeln('show: exactly one bead id is required — $invocation');
      return 64;
    }
    final beadId = rest.single.trim();
    final ShowOutcome outcome;
    try {
      // The shared state-root contract is VALIDATED here and nowhere read: a
      // bead lives in the WORK store, and the grid home's state store holds
      // link and session-lifecycle beads this verb has no business in. A verb
      // that accepted the option and skipped the check would report an
      // unrelated root as fine.
      resolveStateRoot(argResults!, _stateRoot);
      outcome = await _service.show(
        storeRoot: p.normalize(_storeRoot()),
        beadId: beadId,
        ifRevision: argResults!.option('if-revision'),
      );
    } on Object catch (error) {
      _err.writeln('show: failed to read $beadId: $error');
      return 1;
    }
    if (argResults!.flag('json')) {
      _out.writeln(jsonEncode(outcome.toJson()));
    } else {
      _out.writeln(_renderPlain(outcome));
    }
    return switch (outcome) {
      BeadShown() || ShowUnchanged() => 0,
      ShowRefused() => 1,
    };
  }
}

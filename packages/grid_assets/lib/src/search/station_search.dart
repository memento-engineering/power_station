/// The SEARCH domain — deterministic cross-store search over a station's
/// ATTACHED substations (bead `pow-ovh`; the first instance of the coupled
/// skill+command pattern, Nico 2026-07-10).
///
/// A composed station's agentic skills (the `discover` skill first) must NOT
/// reinvent cross-store search by inference — they CALL the station's `search`
/// Command, and the Command is a THIN adapter over THIS service (the CLI-SDK
/// layering rule: logic is UI-drivable — a Flutter app executes the same
/// [StationSearchService] — never coded on the Command).
///
/// **The roster is resolved from the resident-station context, never
/// hardcoded.** [mountedRosterOf] mounts the composing station's
/// [sdk.GridDelegate] tree offline (the same tree `up` arms — space-6ds: the
/// roster is authored IN the tree) and walks the mounted
/// [sdk.SubstationScope]s. Deterministic and station-up/-down agnostic: search
/// needs no live station, only the station's authored shape.
///
/// **Read-only, by construction (A37 / coexistence).** A substation's work
/// store is a FOREIGN store to a search — the fence is structural, not a
/// runtime check: the per-store seam ([SubstationBeadSource]) has no mutation
/// surface, and the default source ([BdExportBeadSource]) can only issue one
/// all-status `bd query` — ONE spawn per store, a pure read. Never `bd show`
/// (which writes `.beads/last-touched` and self-triggers the store's watcher),
/// never a bd mutation, never SQL. (It shelled `bd export --all` until that
/// read was retired upstream; `export` is refused in proxied-server mode.)
library;

import 'dart:convert';

import 'package:beads_dart/beads_dart.dart'
    show
        Bead,
        BeadDependency,
        BdCliService,
        BdResult,
        BdRunner,
        ProcessBdRunner;
import 'package:grid_sdk/grid_sdk.dart' as sdk;

import '../assets/mounted_tree.dart';
import 'semantic_search.dart';

/// Enumerates the mounted substation roster of [delegate] — the ATTACHED
/// substations, resolved from the resident-station context at run time.
///
/// Mounts the delegate's authored tree in a bare offline [TreeOwner] (the H2
/// authoring-only shape: no wiring, no stores armed, no effects — composition
/// Seeds are pure at build), flushes one build pass, collects every provided
/// [sdk.SubstationScope] in tree order, and unmounts. A one-shot enumeration
/// at the effect boundary (each search re-mounts fresh) — never a retained
/// tree, so there is no reactive state to go stale (ADR-0008 D-H).
///
/// [configuration] is the observed value the delegate builds against
/// (config = VALUES); defaults to the empty configuration, matching an
/// unarmed mount.
List<sdk.SubstationScope> mountedRosterOf(
  sdk.GridDelegate delegate, {
  sdk.GridConfiguration configuration = const sdk.GridConfiguration(),
}) => mountedValuesOf<sdk.SubstationScope>(
  delegate,
  configuration: configuration,
);

/// Enumerates the coded substation roster authored by a fresh delegate from
/// [factory], then disposes that owned delegate.
///
/// The delegate is disposed in a `finally` block, including when the offline
/// mount performed by [mountedRosterOf] throws. [configuration] is forwarded
/// to that mount and defaults to the empty, unarmed configuration.
List<sdk.SubstationScope> codedRosterOf(
  sdk.GridDelegate Function() factory, {
  sdk.GridConfiguration configuration = const sdk.GridConfiguration(),
}) {
  final delegate = factory();
  try {
    return mountedRosterOf(delegate, configuration: configuration);
  } finally {
    delegate.dispose();
  }
}

/// The per-store read seam — READ-ONLY by construction (A37): one read
/// method, no mutation surface. The service is built on this seam so a search
/// cannot write a foreign store *by type*, and tests exercise the whole
/// service offline (Fakes, not mocks).
abstract interface class SubstationBeadSource {
  /// Reads the COMPLETE bead graph of [scope]'s work store
  /// (`<scope.root>/.beads/`): all statuses, backlog and decision beads alike
  /// (decisions are usually closed — "have we already decided this" needs
  /// them). Filtering is the caller's job.
  Future<List<Bead>> read(sdk.SubstationScope scope);
}

/// The default [SubstationBeadSource]: ONE `bd query` spawn per store,
/// covering every status. A pure read: no `last-touched` write, no watcher
/// self-trigger, no mutation (A37).
///
/// This used to shell `bd export --all`, but `export` is REFUSED in
/// proxied-server mode and `BdCliService.exportAll` was removed upstream in
/// beads_dart 0.2.0. The all-status query below is the same read the engine's
/// own `CliSnapshotReader` now performs, and it stays one spawn.
class BdExportBeadSource implements SubstationBeadSource {
  /// Creates the source. [runnerFor] is the injectable spawn seam (tests
  /// record argv through it; the default spawns a real `bd` in the store
  /// root).
  const BdExportBeadSource({
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
  }) : _runnerFor = runnerFor;

  final BdRunner Function(String storeRoot) _runnerFor;

  static BdRunner _processRunnerFor(String storeRoot) =>
      ProcessBdRunner(workspaceRoot: storeRoot);

  /// Every status, closed included — the doc above is explicit that decision
  /// beads are usually closed and search needs them.
  static const String _allStatuses =
      'status=open OR status=in_progress OR status=blocked OR '
      'status=deferred OR status=closed';

  @override
  Future<List<Bead>> read(sdk.SubstationScope scope) async => BdCliService(
    _runnerFor(scope.root),
  ).query(_allStatuses, includeClosed: true);
}

/// Normalizes the two read-only `bd dep list --json` row shapes supported by
/// the exact source without adding another process spawn.
///
/// Released clients return edge rows (`issue_id`, `depends_on_id`, `type`).
/// Current bd builds return the dependency bead with `dependency_type`; for
/// this single-id downward read, that is the same edge expressed from the
/// requested bead to the returned bead.
final class _ExactDependencyRowsRunner implements BdRunner {
  const _ExactDependencyRowsRunner(this._delegate, this._issueId);

  final BdRunner _delegate;
  final String _issueId;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final result = await _delegate.run(args, timeout: timeout, stdin: stdin);
    if (!result.ok ||
        args.length < 2 ||
        args[0] != 'dep' ||
        args[1] != 'list') {
      return result;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return result;
    }
    if (decoded is! Map<String, dynamic>) return result;
    final data = decoded['data'];
    if (data is! List ||
        data.isEmpty ||
        data.every(
          (row) => row is Map<String, dynamic> && row.containsKey('issue_id'),
        )) {
      return result;
    }
    if (!data.every(
      (row) =>
          row is Map<String, dynamic> &&
          row['id'] is String &&
          row['dependency_type'] is String,
    )) {
      return result;
    }

    return BdResult(
      exitCode: result.exitCode,
      stdout: jsonEncode({
        ...decoded,
        'data': [
          for (final row in data.cast<Map<String, dynamic>>())
            {
              'issue_id': _issueId,
              'depends_on_id': row['id'],
              'type': row['dependency_type'],
            },
        ],
      }),
      stderr: result.stderr,
    );
  }
}

/// An exact-id extension of [BdExportBeadSource] for filing checks.
///
/// Read-only by construction: a present bead costs one exact-id `bd query`
/// and one `bd dep list`; an absent bead costs only the query. This type has
/// no mutation method and never calls `bd show`.
class ExactSubstationBeadSource extends BdExportBeadSource {
  /// Creates an exact source over the inherited per-root runner seam.
  const ExactSubstationBeadSource({super.runnerFor});

  /// Reads [beadId] and its dependency rows from [storeRoot].
  Future<({Bead? bead, List<BeadDependency> dependencies})> readExact({
    required String storeRoot,
    required String beadId,
  }) async {
    final cli = BdCliService(
      _ExactDependencyRowsRunner(_runnerFor(storeRoot), beadId),
    );
    final matches = (await cli.query(
      'id=$beadId',
      includeClosed: true,
    )).where((bead) => bead.id == beadId).toList(growable: false);
    if (matches.length > 1) {
      throw StateError('duplicate bead id "$beadId" in exact query result');
    }
    if (matches.isEmpty) {
      return (bead: null, dependencies: const <BeadDependency>[]);
    }
    return (bead: matches.single, dependencies: await cli.depList([beadId]));
  }
}

/// One structured hit: a bead that matched the query, with WHERE it lives
/// (the owning substation), WHAT state it is in, and WHY it matched (the
/// matched field + an excerpt).
class SearchHit {
  /// Creates a hit.
  const SearchHit({
    required this.beadId,
    required this.store,
    required this.status,
    required this.issueType,
    required this.title,
    required this.field,
    required this.snippet,
  });

  /// The matched bead's id (e.g. `tg-5r9`).
  final String beadId;

  /// The owning substation's NAME (the store axis of the hit; the store's
  /// root rides the enclosing [StoreSearched]).
  final String store;

  /// The bead's status wire string (`open` / `closed` / …) — carried so
  /// consumers filter without a second lookup.
  final String status;

  /// The bead's issue-type wire string (`task` / `decision` / …).
  final String issueType;

  /// The bead's title (always carried — the human handle on the hit).
  final String title;

  /// The FIRST field the query matched, in precedence order
  /// (`id`, `title`, `description`, `design`, `acceptance_criteria`,
  /// `notes`, `close_reason`, `labels`).
  final String field;

  /// A short excerpt of [field]'s text around the match.
  final String snippet;

  /// JSON form — the structured contract the discover skill consumes.
  Map<String, dynamic> toJson() => {
    'id': beadId,
    'store': store,
    'status': status,
    'type': issueType,
    'title': title,
    'field': field,
    'snippet': snippet,
  };
}

/// The per-store outcome — a sealed union so a consumer must face all three
/// cases: a store was [StoreSearched], was [StoreAbsent] (roster seat with no
/// `.beads/` at its root — a coded sibling not checked out), or the read
/// [StoreFailed]. A search never silently drops a roster seat.
sealed class StoreSearchOutcome {
  const StoreSearchOutcome(this.store);

  /// The roster seat this outcome is for.
  final sdk.SubstationScope store;

  /// JSON form (each case adds its own fields over the shared envelope).
  Map<String, dynamic> toJson();

  Map<String, dynamic> _envelope(String outcome) => {
    'substation': store.name,
    'prefix': store.prefix,
    'root': store.root,
    'outcome': outcome,
  };
}

/// The store resolved and was queried; [hits] may be empty.
class StoreSearched extends StoreSearchOutcome {
  /// Creates the searched outcome.
  const StoreSearched(
    super.store, {
    required this.hits,
    required this.beadsSearched,
  });

  /// The structured hits, in bead-id order (deterministic).
  final List<SearchHit> hits;

  /// How many beads were actually matched against (post type-filter) — the
  /// coverage denominator, so "0 hits" is distinguishable from "0 beads".
  final int beadsSearched;

  @override
  Map<String, dynamic> toJson() => {
    ..._envelope('searched'),
    'beadsSearched': beadsSearched,
    'hits': [for (final h in hits) h.toJson()],
  };
}

/// The roster seat's root has no work store (`<root>/.beads/` absent). NOT a
/// refusal: an absent coded sibling still mounts its seat (space-6ds), so a
/// search reports the gap loud and keeps covering the rest of the roster —
/// the same skip-loud posture arming takes.
class StoreAbsent extends StoreSearchOutcome {
  /// Creates the absent outcome with the human-readable [reason].
  const StoreAbsent(super.store, {required this.reason});

  /// Names the missing store path.
  final String reason;

  @override
  Map<String, dynamic> toJson() => {..._envelope('absent'), 'reason': reason};
}

/// The store exists but the read failed (bd unavailable, export error, …) —
/// surfaced per-store, never masking the other seats' results.
class StoreFailed extends StoreSearchOutcome {
  /// Creates the failed outcome with the human-readable [reason].
  const StoreFailed(super.store, {required this.reason});

  /// The failure detail.
  final String reason;

  @override
  Map<String, dynamic> toJson() => {..._envelope('failed'), 'reason': reason};
}

/// The whole search's structured result: the query + one outcome per roster
/// seat, in roster (mount) order.
class StationSearchReport {
  /// Creates the report.
  const StationSearchReport({
    required this.query,
    required this.stores,
    required this.semantic,
  });

  /// The query as searched.
  final String query;

  /// One outcome per roster seat, in roster order.
  final List<StoreSearchOutcome> stores;

  /// The independent, additive semantic result.
  final SemanticSearchOutcome semantic;

  /// Every hit across all searched stores, in roster-then-id order.
  List<SearchHit> get hits => [
    for (final s in stores)
      if (s is StoreSearched) ...s.hits,
  ];

  /// True when at least one store was actually searched — the "did the search
  /// cover ANYTHING" signal (all-absent/all-failed is a loud non-answer, not
  /// an empty result).
  bool get searchedAnyStore => stores.any((s) => s is StoreSearched);

  /// JSON form — the structured contract the discover skill consumes:
  /// `{query, stores: [{substation, prefix, root, outcome, ...}], hitCount}`.
  Map<String, dynamic> toJson() => {
    'query': query,
    'stores': [for (final s in stores) s.toJson()],
    'hitCount': hits.length,
    'semantic': semantic.toJson(),
  };
}

/// The reusable, UI-drivable search SERVICE — all the logic behind the
/// station's `search` verb ([SearchCommand] is a thin adapter over this; a
/// Flutter app calls this directly).
///
/// Pure orchestration over injected seams: the per-store read is
/// [SubstationBeadSource] (read-only by construction — A37) and store
/// existence is a [sdk.DirectoryProbe] (grid_sdk's filesystem seam), so the
/// whole service tests offline.
class StationSearchService {
  /// Creates the service over [source] (default: the real one-spawn
  /// `bd export --all` read) and [dirExists] (default: the real probe).
  const StationSearchService({
    SubstationBeadSource source = const BdExportBeadSource(),
    sdk.DirectoryProbe dirExists = sdk.defaultDirectoryProbe,
    SemanticSearchBackendMount semanticBackendMount =
        mountSemanticSearchBackend,
  }) : _source = source,
       _dirExists = dirExists,
       _semanticBackendMount = semanticBackendMount;

  final SubstationBeadSource _source;
  final sdk.DirectoryProbe _dirExists;
  final SemanticSearchBackendMount _semanticBackendMount;

  /// Searches every roster seat's work store for [query]. The query is split
  /// on whitespace and each term is matched as a case-insensitive substring;
  /// a bead matches when ANY term occurs in a searchable field.
  ///
  /// Only CORE-typed beads are matched (task/bug/feature/chore/epic/spike/
  /// story/milestone — the backlog — plus `decision`); the_grid's custom
  /// lifecycle types (session/step/gate/…) and infra types are noise for
  /// discovery and are excluded. ALL statuses are included — decisions are
  /// usually closed, and "have we already decided this" needs them; [SearchHit.status]
  /// rides every hit so consumers filter.
  ///
  /// Stores are read SEQUENTIALLY in roster order — deterministic output and
  /// bounded spawn pressure (one `bd` at a time). An empty [query] is a LOUD
  /// [ArgumentError]: a search has a query (caller defect, never an
  /// everything-matches scan).
  Future<StationSearchReport> search({
    required String query,
    required List<sdk.SubstationScope> roster,
    required String gridHome,
  }) async {
    if (query.trim().isEmpty) {
      throw ArgumentError.value(
        query,
        'query',
        'StationSearchService.search: a search has a query — an empty one '
            'would be an everything-matches scan, never intended',
      );
    }
    final outcomes = <StoreSearchOutcome>[];
    final semanticInputs = <SemanticStoreInput>[];
    for (final scope in roster) {
      final beadsDir = scope.workStore.beadsDir;
      if (!_dirExists(beadsDir)) {
        outcomes.add(StoreAbsent(scope, reason: 'no work store at $beadsDir'));
        continue;
      }
      try {
        final beads = await _source.read(scope);
        final searchable = [
          for (final bead in beads)
            if (bead.issueType.isCore) bead,
        ]..sort((left, right) => left.id.compareTo(right.id));
        semanticInputs.add(SemanticStoreInput(scope: scope, beads: searchable));
        outcomes.add(_searchStore(scope, searchable, query));
      } on Object catch (e) {
        // Per-store isolation: one failing store never masks the roster's
        // other seats; the failure is IN the report, loud.
        outcomes.add(StoreFailed(scope, reason: '$e'));
      }
    }
    final semantic = await runSemanticSearch(
      query: query,
      gridHome: gridHome,
      stores: semanticInputs,
      mount: _semanticBackendMount,
    );
    return StationSearchReport(
      query: query,
      stores: outcomes,
      semantic: semantic,
    );
  }

  StoreSearched _searchStore(
    sdk.SubstationScope scope,
    List<Bead> searchable,
    String query,
  ) {
    final needles = query.trim().toLowerCase().split(RegExp(r'\s+'));
    final hits = <SearchHit>[];
    for (final bead in searchable) {
      final hit = _matchBead(scope, bead, needles);
      if (hit != null) hits.add(hit);
    }
    return StoreSearched(scope, hits: hits, beadsSearched: searchable.length);
  }

  /// Matches any of [needles] against [bead]'s searchable fields in
  /// precedence order. The FIRST matching field names the hit; within that
  /// field the earliest matching term yields the snippet.
  SearchHit? _matchBead(
    sdk.SubstationScope scope,
    Bead bead,
    List<String> needles,
  ) {
    final fields = <(String, String)>[
      ('id', bead.id),
      ('title', bead.title),
      ('description', bead.description),
      ('design', bead.design),
      ('acceptance_criteria', bead.acceptanceCriteria),
      ('notes', bead.notes),
      ('close_reason', bead.closeReason),
      ('labels', bead.labels.join(' ')),
    ];
    for (final (name, value) in fields) {
      if (value.isEmpty) continue;
      final lowerValue = value.toLowerCase();
      var matchAt = -1;
      var matchLength = 0;
      for (final needle in needles) {
        final at = lowerValue.indexOf(needle);
        if (at >= 0 && (matchAt < 0 || at < matchAt)) {
          matchAt = at;
          matchLength = needle.length;
        }
      }
      if (matchAt < 0) continue;
      return SearchHit(
        beadId: bead.id,
        store: scope.name,
        status: bead.status.wire,
        issueType: bead.issueType.wire,
        title: bead.title,
        field: name,
        snippet: _snippet(value, matchAt, matchLength),
      );
    }
    return null;
  }

  /// The line containing the first match, windowed to at most
  /// [_snippetWindow] chars around the match when the line runs long —
  /// deterministic, single-line, ellipsis-marked where clipped.
  static String _snippet(String text, int matchAt, int matchLength) {
    final lineStart = text.lastIndexOf('\n', matchAt) + 1;
    final newlineAt = text.indexOf('\n', matchAt);
    final lineEnd = newlineAt < 0 ? text.length : newlineAt;
    final line = text.substring(lineStart, lineEnd);
    final at = matchAt - lineStart;
    if (line.length <= _snippetWindow) return line.trim();
    final margin = (_snippetWindow - matchLength) ~/ 2;
    var from = at - margin;
    var to = at + matchLength + margin;
    if (from < 0) {
      to -= from;
      from = 0;
    }
    if (to > line.length) {
      from -= to - line.length;
      to = line.length;
      if (from < 0) from = 0;
    }
    final prefix = from > 0 ? '…' : '';
    final suffix = to < line.length ? '…' : '';
    return '$prefix${line.substring(from, to).trim()}$suffix';
  }

  static const int _snippetWindow = 160;
}

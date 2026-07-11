/// The SEARCH domain's exported CLI component — the `search` Command a
/// composed station assembles (the CLI-SDK model: an asset vends domain AND
/// CLI components; `space_station` composes this as `space search <query>`).
///
/// THIN by rule (the layering redline, `SCRATCH-pub-capability-and-repo-split.md`):
/// ALL logic lives in [StationSearchService] + [mountedRosterOf] (UI-drivable —
/// a Flutter app runs the same search); this Command only parses argv, resolves
/// the roster from the injected resident-station context, and renders the
/// [StationSearchReport].
///
/// This is the deterministic substrate UNDER the front-of-house agentic
/// skills (the coupled skill+command pattern): the `discover` skill CALLS
/// `<verb> search --json <query>` and consumes the structured report — it
/// never reinvents cross-store search by inference.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;

import 'station_search.dart';

/// `search <query…>` — deterministic cross-store search over the station's
/// attached substations.
///
/// A station composes it with ITS resident-station context:
/// `runner.addCommand(SearchCommand(delegate: () => MyDelegate(...)))` —
/// the [delegate] factory is invoked per run, its tree is mounted OFFLINE to
/// enumerate the roster ([mountedRosterOf]), and the delegate is disposed
/// after the run (this command owns the instance it asked for).
class SearchCommand extends Command<int> {
  /// Creates the command over the composing station's [delegate] factory (the
  /// resident-station context the roster is resolved from) and the search
  /// [service] (injectable for tests). [out]/[err] default to the real
  /// stdout/stderr; tests capture them.
  SearchCommand({
    required sdk.GridDelegate Function() delegate,
    StationSearchService service = const StationSearchService(),
    StringSink? out,
    StringSink? err,
  }) : _delegate = delegate,
       _service = service,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser.addFlag(
      'json',
      negatable: false,
      help:
          'Emit the structured report as ONE JSON object '
          '({query, stores: [{substation, prefix, root, outcome, …}], '
          'hitCount}) — the surface agentic skills consume.',
    );
  }

  final sdk.GridDelegate Function() _delegate;
  final StationSearchService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'search';

  @override
  final String description =
      'Search the attached substations\' work stores (backlog + decision '
      'beads) for a query — deterministic, read-only (A37), roster-driven '
      'from the resident-station context.';

  @override
  String get invocation {
    final exe = runner?.executableName;
    return exe == null ? 'search <query…>' : '$exe search <query…>';
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final query = args.rest.join(' ').trim();
    if (query.isEmpty) {
      _err.writeln('search: a query is required — $invocation');
      return 64;
    }

    final delegate = _delegate();
    try {
      final roster = mountedRosterOf(delegate);
      if (roster.isEmpty) {
        _err.writeln(
          'search: the resident-station context mounts no substations — '
          'nothing to search',
        );
        return 1;
      }
      final report = await _service.search(query: query, roster: roster);
      if (args.flag('json')) {
        _out.writeln(jsonEncode(report.toJson()));
      } else {
        _render(report);
      }
      // "Ran" means the search covered at least one store; a roster whose
      // every seat was absent/failed is a loud non-answer, not an empty
      // result (the report on stdout says which and why either way).
      return report.searchedAnyStore ? 0 : 1;
    } finally {
      delegate.dispose();
    }
  }

  void _render(StationSearchReport report) {
    for (final outcome in report.stores) {
      switch (outcome) {
        case StoreSearched(:final store, :final hits, :final beadsSearched):
          _out.writeln(
            '${store.name}: ${hits.length} hit(s) '
            '($beadsSearched beads searched)',
          );
          for (final hit in hits) {
            _out
              ..writeln(
                '  ${hit.beadId}  ${hit.status}  [${hit.issueType}]  '
                '${hit.title}',
              )
              ..writeln('      ${hit.field}: ${hit.snippet}');
          }
        case StoreAbsent(:final store, :final reason):
          _out.writeln('${store.name}: store absent — $reason');
        case StoreFailed(:final store, :final reason):
          _out.writeln('${store.name}: read FAILED — $reason');
      }
    }
    _out.writeln(
      '${report.hits.length} hit(s) across ${report.stores.length} '
      'substation(s) for "${report.query}"',
    );
  }
}

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
import 'package:path/path.dart' as p;

import 'station_search.dart';

String _currentDirectory() => Directory.current.path;

/// `search <query…>` — deterministic cross-store search over the station's
/// attached substations.
///
/// A station composes it with ITS resident-station context:
/// `runner.addCommand(SearchCommand(delegate: (home) => MyDelegate(home)))` —
/// the [delegate] factory receives the normalized absolute grid home and is
/// invoked per run. Its tree is mounted OFFLINE to enumerate the roster
/// ([mountedRosterOf]), and the delegate is disposed after the run.
class SearchCommand extends Command<int> {
  /// Creates the command over the composing station's [delegate] factory (the
  /// resident-station context the roster is resolved from). The factory
  /// receives the selected grid home after trimming, absolute-path validation,
  /// and normalization. [gridHomeDefault] defaults to the current directory
  /// and is injectable for offline tests. The search [service] is also
  /// injectable; [out]/[err] default to the real stdout/stderr.
  SearchCommand({
    required sdk.GridDelegate Function(String gridHome) delegate,
    String Function() gridHomeDefault = _currentDirectory,
    StationSearchService service = const StationSearchService(),
    StringSink? out,
    StringSink? err,
  }) : _delegate = delegate,
       _gridHomeDefault = gridHomeDefault,
       _service = service,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit the structured report as ONE JSON object '
            '({query, stores: [{substation, prefix, root, outcome, …}], '
            'hitCount}) — the surface agentic skills consume.',
      )
      ..addOption(
        'grid-home',
        abbr: 'g',
        help:
            "The grid's HOME (ABSOLUTE): the root the coded roster's relative "
            'substation seats resolve against. Defaults to the current '
            'directory.',
      );
  }

  final sdk.GridDelegate Function(String gridHome) _delegate;
  final String Function() _gridHomeDefault;
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

    final flag = args.option('grid-home')?.trim();
    final unresolvedHome = (flag == null || flag.isEmpty)
        ? _gridHomeDefault()
        : flag;
    if (!p.isAbsolute(unresolvedHome)) {
      usageException(
        'search: --grid-home must be an ABSOLUTE path (got "$unresolvedHome") — '
        'a cwd-relative grid home re-imports the ambience the v3 model kills '
        '(the coded roster resolves its relative seats against it).',
      );
    }
    final gridHome = p.normalize(unresolvedHome);
    final delegate = _delegate(gridHome);
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

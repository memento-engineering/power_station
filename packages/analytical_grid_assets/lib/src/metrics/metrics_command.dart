/// The ANALYTICAL domain's exported CLI component — the `metrics` Command
/// group a composed station assembles (`space metrics report --json`). THIN by
/// rule: all logic lives in [StationMetricsService] + `buildStationMetricsReport`
/// (UI-drivable); this Command parses argv, resolves the store set from the
/// resident-station context, and renders.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import 'distribution.dart';
import 'metrics_store.dart';
import 'station_metrics_render.dart';
import 'station_metrics_service.dart';

String _processCwd() => Directory.current.path;

/// `metrics` — the station-health report group (subcommands carry the verbs).
class MetricsCommand extends Command<int> {
  /// Creates the group over the composing station's [delegate] factory (the
  /// resident-station context the store set is resolved from).
  MetricsCommand({
    required sdk.GridDelegate Function(String gridHome) delegate,
    String Function() gridHomeDefault = _processCwd,
    StationMetricsService service = const StationMetricsService(),
    StringSink? out,
    StringSink? err,
  }) {
    addSubcommand(
      MetricsReportCommand(
        delegate: delegate,
        gridHomeDefault: gridHomeDefault,
        service: service,
        out: out ?? stdout,
        err: err ?? stderr,
      ),
    );
  }

  @override
  final String name = 'metrics';

  @override
  final String description =
      'Station health and effectiveness reports over the session ledger — '
      'deterministic, read-only, roster-driven. Reports what the station HAS '
      'been doing; the cockpit owns what is running now.';
}

/// `metrics report` — the whole report, human or `--json`.
class MetricsReportCommand extends Command<int> {
  /// Creates the op.
  MetricsReportCommand({
    required sdk.GridDelegate Function(String gridHome) delegate,
    required String Function() gridHomeDefault,
    required StationMetricsService service,
    required StringSink out,
    required StringSink err,
  }) : _delegate = delegate,
       _gridHomeDefault = gridHomeDefault,
       _service = service,
       _out = out,
       _err = err {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit the report as ONE JSON object — the surface agentic skills '
            'parse rather than scrape.',
      )
      ..addOption(
        'grid-home',
        abbr: 'g',
        help:
            "The grid's HOME (ABSOLUTE): the root the coded roster's relative "
            'substation roots resolve against. Defaults to the current '
            'directory.',
      )
      ..addOption(
        'sparse-threshold',
        help:
            'The sampled-session floor below which a split reports '
            'insufficient-data instead of percentiles.',
        defaultsTo: '$kDefaultSparseSampleThreshold',
      )
      ..addOption(
        'headroom',
        help:
            'The factor applied to a per-circuit / per-task high-water mark. '
            'This is a REPORT, never a cap: nothing is enforced.',
        defaultsTo: '$kDefaultHeadroomFactor',
      );
  }

  final sdk.GridDelegate Function(String gridHome) _delegate;
  final String Function() _gridHomeDefault;
  final StationMetricsService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'report';

  @override
  final String description =
      'Report grade distribution, false-F provenance, cost and tokens per '
      'landed delivery, cache hits, rework rounds, rubric calibration and the '
      'split token distributions across the station store set.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final flag = args.option('grid-home')?.trim();
    final unresolved = (flag == null || flag.isEmpty)
        ? _gridHomeDefault()
        : flag;
    if (!p.isAbsolute(unresolved)) {
      _err.writeln(
        'metrics report: --grid-home must be an ABSOLUTE path (got '
        '"$unresolved") — the coded roster resolves its relative roots '
        'against it.',
      );
      return 64;
    }
    final threshold = int.tryParse(args.option('sparse-threshold') ?? '');
    if (threshold == null || threshold < 1) {
      _err.writeln(
        'metrics report: --sparse-threshold must be a positive integer.',
      );
      return 64;
    }
    final headroom = double.tryParse(args.option('headroom') ?? '');
    if (headroom == null || !headroom.isFinite || headroom < 1) {
      _err.writeln(
        'metrics report: --headroom must be a finite number of at least 1.0.',
      );
      return 64;
    }

    final gridHome = p.normalize(unresolved);
    final delegate = _delegate(gridHome);
    try {
      final report = await _service.report(
        stores: stationMetricsStoresOf(delegate, gridHome: gridHome),
        sparseSampleThreshold: threshold,
        headroomFactor: headroom,
      );
      if (args.flag('json')) {
        _out.writeln(jsonEncode(report.toJson()));
      } else {
        renderStationMetricsReport(report, _out);
      }
      if (!report.readAnyStore) {
        _err.writeln(
          'metrics report: no store in the set carried a grid state store — '
          'a loud non-answer, not an empty report',
        );
        return 1;
      }
      return 0;
    } finally {
      delegate.dispose();
    }
  }
}

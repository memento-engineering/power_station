/// Thin CLI adapter for incremental embedding indexing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;

import 'embedding_index.dart';
import 'embedding_provider.dart';
import 'station_index.dart';
import 'station_search.dart';

typedef EmbeddingIndexOpen =
    Future<DoltEmbeddingIndex> Function({
      required String gridHome,
      required EmbeddingIndexIdentity identity,
    });
typedef EmbeddingSiteBindingLoad = EmbeddingSiteBinding Function(String path);

String _currentDirectory() => Directory.current.path;

class IndexCommand extends Command<int> {
  IndexCommand({
    required GridDelegate Function(String) delegate,
    EmbeddingProviderRegistry registry = const EmbeddingProviderRegistry(),
    Map<String, String> environment = const {},
    String Function() gridHomeDefault = _currentDirectory,
    EmbeddingHttpSend send = sendEmbeddingHttpRequest,
    SubstationBeadSource source = const BdExportBeadSource(),
    IndexBeadChangeKey changeKeyOf = _noChangeKey,
    DirectoryProbe dirExists = defaultDirectoryProbe,
    EmbeddingIndexOpen indexOpen = DoltEmbeddingIndex.open,
    EmbeddingSiteBindingLoad siteBindingLoad =
        EmbeddingSiteBinding.loadJsonFile,
    StringSink? out,
    StringSink? err,
  }) : _delegate = delegate,
       _registry = registry,
       _environment = environment,
       _gridHomeDefault = gridHomeDefault,
       _send = send,
       _source = source,
       _changeKeyOf = changeKeyOf,
       _dirExists = dirExists,
       _indexOpen = indexOpen,
       _siteBindingLoad = siteBindingLoad,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addFlag(
        'full',
        negatable: false,
        help: 'Re-embed every current bead; incremental is the default.',
      )
      ..addFlag('json', negatable: false)
      ..addOption('provider')
      ..addOption('grid-home', abbr: 'g');
  }

  final GridDelegate Function(String) _delegate;
  final EmbeddingProviderRegistry _registry;
  final Map<String, String> _environment;
  final String Function() _gridHomeDefault;
  final EmbeddingHttpSend _send;
  final SubstationBeadSource _source;
  final IndexBeadChangeKey _changeKeyOf;
  final DirectoryProbe _dirExists;
  final EmbeddingIndexOpen _indexOpen;
  final EmbeddingSiteBindingLoad _siteBindingLoad;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'index';

  @override
  final String description =
      'Incrementally embed attached bead stores into .grid/embeddings.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('index: no positional arguments are accepted');
    }
    final selected = argResults!.option('grid-home')?.trim();
    final unresolved = selected == null || selected.isEmpty
        ? _gridHomeDefault()
        : selected;
    if (!p.isAbsolute(unresolved)) {
      usageException(
        'index: --grid-home must be an ABSOLUTE path (got "$unresolved")',
      );
    }
    final home = p.normalize(unresolved);
    final provider = _registry.resolve(argResults!.option('provider'));
    final index = await _indexOpen(
      gridHome: home,
      identity: provider.indexIdentity,
    );
    final binding = _siteBindingLoad(p.join(home, kEmbeddingSiteBindingFile));
    final client = EmbeddingClient.mount(
      registry: _registry,
      providerId: provider.id,
      environment: _environment,
      indexIdentity: provider.indexIdentity,
      siteBinding: binding,
      send: _send,
    );
    final delegate = _delegate(home);
    try {
      final roster = mountedRosterOf(delegate);
      if (roster.isEmpty) {
        _err.writeln('index: resident station mounts no substations');
        return 1;
      }
      final report = await StationIndexService(
        index: index,
        client: client,
        provider: provider,
        source: _source,
        changeKeyOf: _changeKeyOf,
        dirExists: _dirExists,
      ).indexRoster(roster: roster, full: argResults!.flag('full'));
      if (argResults!.flag('json')) {
        _out.writeln(jsonEncode(report.toJson()));
      } else {
        for (final outcome in report.stores) {
          switch (outcome) {
            case StoreIndexed(
              :final store,
              :final embedded,
              :final skippedFresh,
              :final removed,
            ):
              _out.writeln(
                '${store.name}: embedded=$embedded '
                'skipped-fresh=$skippedFresh removed=$removed',
              );
            case IndexStoreAbsent(:final store, :final reason):
              _out.writeln('${store.name}: absent — $reason');
            case IndexStoreFailed(:final store, :final reason):
              _err.writeln('${store.name}: FAILED — $reason');
          }
        }
      }
      return report.succeeded ? 0 : 1;
    } finally {
      delegate.dispose();
    }
  }
}

String? _noChangeKey(Bead bead) => null;

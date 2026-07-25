// M6 Track D — the compute-domain structural fence (DoD-4).
//
// The federation CORE (federated_grid_assets/lib) must name NO compute-specific
// detail after the Track D split — the bus/protocol stays kind-agnostic
// (ADR-0011 D3). This grep-style assertion proves it; the meaningfulness half
// proves the compute payloads DO live in grid_assets, so the fence is not
// vacuous. Reads files only — no live anything.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves a package's `lib` dir through the resolved package config (walking
/// up to the workspace `.dart_tool/package_config.json`) — the package config
/// is the one authority on where a workspace member resolved. The `<pkg>.dart`
/// barrel is the marker so a `lib` candidate matches only its own package.
Directory _libDir(String pkg) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final config = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) {
      final doc = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
      final packages = (doc['packages'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final entry in packages) {
        if (entry['name'] != pkg) continue;
        var rootUri = entry['rootUri'] as String;
        if (!rootUri.endsWith('/')) rootUri = '$rootUri/';
        final packageUri = entry['packageUri'] as String? ?? 'lib/';
        final probe = Directory(
          config.uri.resolve(rootUri).resolve(packageUri).toFilePath(),
        );
        if (probe.existsSync() &&
            File(p.join(probe.path, '$pkg.dart')).existsSync()) {
          return probe;
        }
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not resolve package:$pkg/lib from ${Directory.current.path}');
}

String _allSource(Directory libDir, {bool Function(File f) exclude = _never}) =>
    libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !exclude(f))
        .map((f) => f.readAsStringSync())
        .join('\n');

bool _never(File f) => false;

void main() {
  group('Track D structural fence — the federation core is kind-agnostic', () {
    // `federated_grid_assets` also carries the asset-exported CLI Commands
    // (ServeCommand/LeaseCommand, AL-5b) — GENERIC adapters whose doc comments
    // illustrate them with the compute reference app ("the reference app
    // supplies the compute one"). That's prose about a CONSUMER, not the bus/
    // protocol naming compute detail, so the fence excludes them; the actual
    // lease-bus/protocol core (station_server/station_client/lease_manager/
    // membership/git_sync) is what ADR-0011 D3 requires stay kind-agnostic.
    bool isCliCommand(File f) =>
        f.path.endsWith('serve_command.dart') ||
        f.path.endsWith('lease_command.dart');
    final fedSource = _allSource(
      _libDir('federated_grid_assets'),
      exclude: isCliCommand,
    );

    test(
      'federated_grid_assets/lib names NO compute symbol (case-insensitive)',
      () {
        final lower = fedSource.toLowerCase();
        // `commandresult` is checked precisely in the next test (it must
        // exclude the legitimate git-sync `GitCommandResult`, Track E /
        // ADR-0011 D7).
        const forbidden = ['compute', 'dispatchcommand', 'commandexecutor'];
        for (final symbol in forbidden) {
          expect(
            lower.contains(symbol),
            isFalse,
            reason:
                'the federation core must not name "$symbol" — the bus stays '
                'kind-agnostic (ADR-0011 D3); the compute concern lives in '
                'grid_assets/src/compute/',
          );
        }
      },
    );

    test('the git-SYNC channel type is NOT a compute leak (Track E vs the D '
        'fence)', () {
      // `GitCommandResult` is the git-over-LAN sync channel's result type (Track
      // E, ADR-0011 D7 — git sync IS a federation-native concern that belongs in
      // the core); its name happens to END in `CommandResult` but it is NOT the
      // compute domain's `CommandResult`. The fence below excludes that one
      // legitimate collision so the kind-agnostic `commandresult` check stays
      // precise (it still catches the bare compute type).
      final lower = fedSource.toLowerCase();
      final computeResultLeak = RegExp(
        r'(?<!git)commandresult',
      ).hasMatch(lower);
      expect(
        computeResultLeak,
        isFalse,
        reason:
            'the federation core must not name the compute "CommandResult" — '
            'only the git-sync `GitCommandResult` may appear',
      );
    });

    test(
      'the compute domain DOES live in grid_assets (the fence is meaningful)',
      () {
        final assetSource = _allSource(_libDir('grid_assets'));
        expect(assetSource, contains('class DispatchCommand'));
        expect(assetSource, contains('class CommandResult'));
        // The compute lease consumer (the generic LeaseCapability<H> family is core,
        // in grid_engine; the compute-specific impl over the bus lives here).
        expect(assetSource, contains('class ComputeLeaseCapability'));
        expect(assetSource, contains("kComputeKind = 'compute'"));
      },
    );
  });
}

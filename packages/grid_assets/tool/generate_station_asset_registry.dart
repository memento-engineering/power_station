import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  final packageRoot = io.Directory.current.absolute.path;
  final parser = ArgParser()
    ..addFlag(
      'check',
      negatable: false,
      help: 'Verify the generated station registrant; write nothing.',
    )
    ..addOption(
      'station-root',
      defaultsTo: p.normalize(p.join(packageRoot, '..', '..')),
      help: 'Root containing .dart_tool/package_config.json and pubspec.lock.',
    )
    ..addOption(
      'output',
      defaultsTo: p.join(packageRoot, kGeneratedStationAssetRegistryPath),
      help: 'Dart registrant path.',
    );
  final options = parser.parse(arguments);
  try {
    io.exitCode = runStationAssetRegistryGenerator(
      stationRoot: p.normalize(options.option('station-root')!),
      outputPath: p.normalize(options.option('output')!),
      check: options.flag('check'),
    );
  } on StalePackageGraphException catch (error) {
    io.stderr.writeln(error.message);
    io.exitCode = 2;
  } on StationAssetRegistryException catch (error) {
    io.stderr.writeln(error.message);
    io.exitCode = 2;
  } on GridBlockException catch (error) {
    io.stderr.writeln(error.message);
    io.exitCode = 2;
  } on ArgumentError catch (error) {
    io.stderr.writeln(error.message);
    io.exitCode = 2;
  }
}

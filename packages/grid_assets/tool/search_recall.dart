import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:grid_assets/grid_assets.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('runner')
    ..addOption('grid-home')
    ..addFlag('record-baseline', negatable: false);
  final options = parser.parse(arguments);
  final runner = options.option('runner') ?? '';
  final gridHome = options.option('grid-home') ?? '';
  final code = await runRecall(
    runner: runner,
    gridHome: gridHome,
    recordBaseline: options.flag('record-baseline'),
  );
  io.exitCode = code;
}
